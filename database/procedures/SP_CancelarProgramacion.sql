-- HU-38 (Sprint 5) Cancelar la Programación activa de una OS/OM. Permitida a cualquier rol con prog_gestionar (Asistente o Jefe),
-- sin aprobación previa, desde cualquier estado de la programación (pendiente de confirmación o programado).
--   p_id_motivo: obligatorio, del catálogo MOTIVO_CANCELACION_PROGRAMACION. p_comentario: hasta 500; el largo mínimo lo fija el parámetro
--   CANCELACION_COMENTARIO_MIN (0 = opcional).
-- Efecto: la programación pasa a CANCELADA (terminal, no se reactiva). La OS NO se anula: sigue EMITIDA, sin técnico ni fecha, y vuelve
--   a la bandeja en Pendientes > "Pendiente por programar" para crear una nueva programación cuando se decida. El personal de la OS se
--   libera y una solicitud de reprogramación pendiente queda cancelada. Los viáticos ya depositados NO se tocan: quedan a disposición de
--   Contabilidad (la respuesta informa el monto). No se envía nada al cliente. Se avisa a los técnicos y a los jefes de operaciones.
--   Un servicio que ya salió a campo (en ruta, en ejecución...) no se cancela desde aquí.
-- Concurrencia: OS → programación (mismo orden que la anulación). Resultados: 1 mensaje, 2 resultado.
DROP PROCEDURE IF EXISTS SP_CancelarProgramacion;

DELIMITER $$

CREATE PROCEDURE SP_CancelarProgramacion(
    IN p_id_usuario       BIGINT,
    IN p_id_programacion  BIGINT,
    IN p_id_motivo        INT,
    IN p_comentario       VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_motivo      VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_comentario  VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_min         DECIMAL(18,6) DEFAULT 0;
    DECLARE v_id_os       BIGINT       DEFAULT NULL;
    DECLARE v_numero      VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tipo        VARCHAR(5)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado_os   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_cliente  BIGINT       DEFAULT NULL;
    DECLARE v_cliente     VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_codigo      VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado_prg  VARCHAR(25)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_fecha       DATE;
    DECLARE v_ini         TIME;
    DECLARE v_fin         TIME;
    DECLARE v_viaticos    DECIMAL(12,2) DEFAULT 0;
    DECLARE v_personal    INT          DEFAULT 0;
    DECLARE v_solicitudes INT          DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            @err_msg  = MESSAGE_TEXT,
            @err_code = MYSQL_ERRNO;
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_can_tec;
        IF @err_code IN (1213, 1205) THEN   -- interbloqueo / espera de bloqueo por otra operación simultánea: se reintenta
            SELECT 1 AS IdTipoMensaje, 'Otra persona está modificando esta programación en este momento. Inténtalo de nuevo.' AS Mensaje;
        ELSE
            SELECT 3 AS IdTipoMensaje,
                   CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
        END IF;
    END;

    IF FN_PermisoAccion(p_id_usuario, 'prog_gestionar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para cancelar programaciones.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF IFNULL(p_id_programacion, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'La programación no existe.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_motivo = NULL;
    IF IFNULL(p_id_motivo, 0) > 0 THEN
        SELECT String1 INTO v_motivo FROM tabla_maestra
        WHERE Descripcion = 'MOTIVO_CANCELACION_PROGRAMACION' AND IdEmpresa = 1 AND Num1 = p_id_motivo AND eliminado_en IS NULL
        LIMIT 1;
    END IF;
    IF v_motivo IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Selecciona el motivo de la cancelación.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_comentario = NULLIF(TRIM(IFNULL(p_comentario, '')), '');
    CALL SP_LeerParametroProgramacion('CANCELACION_COMENTARIO_MIN', 0, v_min);
    IF v_min > 0 AND CHAR_LENGTH(IFNULL(v_comentario, '')) < v_min THEN
        SELECT 1 AS IdTipoMensaje,
               CONCAT('Explica la cancelación con detalle: la justificación debe tener al menos ', CAST(v_min AS UNSIGNED), ' caracteres.') AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT id_os INTO v_id_os FROM programacion WHERE id_programacion = p_id_programacion AND eliminado_en IS NULL;
    IF v_id_os IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'La programación no existe.' AS Mensaje;
        LEAVE proc;
    END IF;

    START TRANSACTION;

    SELECT numero, tipo, estado, id_cliente INTO v_numero, v_tipo, v_estado_os, v_id_cliente
    FROM orden_servicio WHERE id_os = v_id_os AND eliminado_en IS NULL FOR UPDATE;

    SELECT codigo, estado, fecha_ejecucion, hora_inicio, hora_fin_estimada INTO v_codigo, v_estado_prg, v_fecha, v_ini, v_fin
    FROM programacion WHERE id_programacion = p_id_programacion AND eliminado_en IS NULL FOR UPDATE;

    IF v_codigo IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'La programación no existe.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_estado_prg = 'cancelada' THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, CONCAT('La programación ', v_codigo, ' ya está cancelada.') AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_estado_os IS NULL OR v_estado_os NOT IN ('programada', 'reprogramada') THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje,
               CONCAT('La orden ', IFNULL(v_numero, ''), ' está ', IFNULL(v_estado_os, 'inexistente'),
                      ': solo se cancela una programación de un servicio que aún no empezó.') AS Mensaje;
        LEAVE proc;
    END IF;

    -- Técnicos a avisar (antes de liberar el personal)
    DROP TEMPORARY TABLE IF EXISTS tmp_can_tec;
    CREATE TEMPORARY TABLE tmp_can_tec (id_usuario BIGINT NOT NULL, PRIMARY KEY (id_usuario));
    INSERT IGNORE INTO tmp_can_tec (id_usuario)
    SELECT id_usuario FROM programacion_tecnico WHERE id_programacion = p_id_programacion AND eliminado_en IS NULL;

    SELECT IFNULL(SUM(monto), 0) INTO v_viaticos
    FROM gasto_viatico
    WHERE id_os = v_id_os AND eliminado_en IS NULL AND tipo = 'viatico_asignado' AND estado = 'aprobado';

    UPDATE programacion
    SET estado = 'cancelada', id_motivo_cancelacion = p_id_motivo, comentario_cancelacion = v_comentario,
        cancelada_en = NOW(), cancelada_por = p_id_usuario, modificado_por = p_id_usuario
    WHERE id_programacion = p_id_programacion;

    -- La OS sigue emitida y vuelve a "Pendiente por programar"
    UPDATE orden_servicio
    SET estado = 'emitida', id_tecnico_principal = NULL, fecha_ejecucion = NULL, hora_inicio = NULL, hora_fin_estimada = NULL,
        confirmacion_cliente = 0, id_canal_confirmacion = NULL, id_contacto_confirma = NULL, fecha_confirmacion_cliente = NULL,
        modificado_por = p_id_usuario
    WHERE id_os = v_id_os;

    UPDATE os_personal SET eliminado_en = NOW(), eliminado_por = p_id_usuario
    WHERE id_os = v_id_os AND eliminado_en IS NULL;
    SET v_personal = ROW_COUNT();

    UPDATE os_reprogramacion
    SET estado = 'cancelada', resuelto_por = p_id_usuario, fecha_resolucion = NOW(),
        comentario_resolucion = 'La programación fue cancelada.', modificado_por = p_id_usuario
    WHERE estado = 'pendiente' AND eliminado_en IS NULL
      AND (id_programacion = p_id_programacion OR (id_programacion IS NULL AND id_os = v_id_os));
    SET v_solicitudes = ROW_COUNT();

    SELECT razon_social INTO v_cliente FROM cliente WHERE id_cliente = v_id_cliente;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion,
                                  id_usuario, registrado_en, metadata)
    VALUES ('programacion', p_id_programacion, 'cancelar_programacion', v_estado_prg, 'cancelada',
            LEFT(CONCAT('Programación ', v_codigo, ' cancelada. Motivo: ', v_motivo, '.',
                        IFNULL(CONCAT(' ', v_comentario, IF(RIGHT(v_comentario, 1) IN ('.', '!', '?'), '', '.')), ''),
                        ' La ', v_tipo, ' ', v_numero, ' sigue emitida y vuelve a pendiente por programar.'), 900),
            p_id_usuario, NOW(),
            JSON_OBJECT('idMotivo', p_id_motivo, 'motivo', v_motivo, 'personalLiberado', v_personal,
                        'solicitudesCanceladas', v_solicitudes, 'viaticosDepositados', v_viaticos));

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion,
                                  id_usuario, registrado_en, metadata)
    VALUES ('orden_servicio', v_id_os, 'cancelar_programacion', v_estado_os, 'emitida',
            LEFT(CONCAT(v_tipo, ' ', v_numero, ': programación ', v_codigo, ' cancelada (', v_motivo, '). Vuelve a pendiente por programar.'), 900),
            p_id_usuario, NOW(), JSON_OBJECT('programacion', v_codigo, 'idProgramacion', p_id_programacion));

    INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
    SELECT t.id_usuario, 5, CONCAT('Programación cancelada: ', v_numero),
           LEFT(CONCAT('Se canceló la programación de la ', v_tipo, ' ', v_numero, IF(v_cliente IS NULL, '', CONCAT(' de ', v_cliente)),
                       ' del ', DATE_FORMAT(v_fecha, '%d/%m/%Y'), ' de ', TIME_FORMAT(v_ini, '%H:%i'), ' a ', TIME_FORMAT(v_fin, '%H:%i'),
                       '. Motivo: ', v_motivo, '.'), 1000),
           'orden_servicio', v_id_os, NOW(), p_id_usuario
    FROM tmp_can_tec t
    WHERE t.id_usuario <> p_id_usuario;

    INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
    SELECT u.id_usuario, 5, CONCAT('Programación cancelada: ', v_numero),
           LEFT(CONCAT('Se canceló la programación ', v_codigo, ' de la ', v_tipo, ' ', v_numero, IF(v_cliente IS NULL, '', CONCAT(' de ', v_cliente)),
                       '. Motivo: ', v_motivo, '. La orden vuelve a pendiente por programar.',
                       IF(v_viaticos > 0, CONCAT(' Hay viáticos depositados por S/ ', FORMAT(v_viaticos, 2), ' a disposición de Contabilidad.'), '')), 1000),
           'orden_servicio', v_id_os, NOW(), p_id_usuario
    FROM usuario u
    WHERE u.eliminado_en IS NULL AND u.estado = 'activo' AND u.id_usuario <> p_id_usuario AND u.area = 'operaciones'
      AND FN_PermisoAccion(u.id_usuario, 'prog_aprobar_reprogramacion') = 1
      AND NOT EXISTS (SELECT 1 FROM tmp_can_tec t WHERE t.id_usuario = u.id_usuario);

    DROP TEMPORARY TABLE IF EXISTS tmp_can_tec;

    COMMIT;

    SELECT 2 AS IdTipoMensaje, CONCAT('Programación ', v_codigo, ' cancelada. La ', v_tipo, ' ', v_numero, ' vuelve a pendiente por programar.') AS Mensaje;
    SELECT p_id_programacion AS id_programacion, v_codigo AS codigo, 'cancelada' AS estado, 'Cancelada' AS estado_label,
           v_id_os AS id_os, v_numero AS numero_os, 'emitida' AS estado_os, v_motivo AS motivo,
           v_viaticos AS viaticos_depositados, v_solicitudes AS solicitudes_canceladas, 'programar' AS siguiente_accion;
END$$

DELIMITER ;
