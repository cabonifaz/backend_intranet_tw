-- HU-19 Registrar una interacción de seguimiento (registro general, llamada o correo).
-- p_solo_validar = 1: hace todas las validaciones y no guarda nada (se usa antes de enviar un correo).
-- Canal: p_id_canal o, si viene NULL, p_canal_codigo (LLAMADA, CORREO, ...).
-- Resultado: p_id_resultado o, si viene NULL, p_resultado_codigo (ej. CORREO_ENVIADO).
-- Reglas:
--   Propuesta en seguimiento ABIERTO y del área del usuario, acción propuesta_seguimiento_registrar.
--   Fecha de la interacción (NULL = ahora) no futura y no anterior al envío de la propuesta.
--   Notas obligatorias (mínimo 5 caracteres) salvo en correos, que llevan asunto.
--   Llamada: duración obligatoria entre 0 y 600 minutos.
--   Próxima acción (p_programar = 1): tipo, fecha futura, responsable activo del área y prioridad.
--   Sin próxima acción (p_programar = 0) se mantiene la acción pendiente del seguimiento anterior,
--   salvo que p_ejecuta_accion = 1 (se registró desde "Ejecutar ahora": la acción queda realizada).
--   Si viene p_id_correo, el correo pasa a 'enviado' y queda enlazado al seguimiento.
--   Si el responsable de la próxima acción es otra persona, se le notifica.
-- Resultados: 1 mensaje, 2 id_seguimiento (solo al guardar).
DROP PROCEDURE IF EXISTS SP_RegistrarSeguimiento;

DELIMITER $$

CREATE PROCEDURE SP_RegistrarSeguimiento(
    IN p_id_usuario          BIGINT,
    IN p_id_propuesta        BIGINT,
    IN p_id_canal            INT,
    IN p_canal_codigo        VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_resultado        INT,
    IN p_resultado_codigo    VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_contacto         BIGINT,
    IN p_fecha_interaccion   DATETIME,
    IN p_duracion_minutos    INT,
    IN p_notas               TEXT         CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_asunto              VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_programar           TINYINT,
    IN p_id_tipo_accion      INT,
    IN p_fecha_accion        DATETIME,
    IN p_id_responsable_acc  BIGINT,
    IN p_id_prioridad        INT,
    IN p_detalle_accion      VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_correo           BIGINT,
    IN p_proveedor           VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_mensaje          VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_ejecuta_accion      TINYINT,
    IN p_solo_validar        TINYINT
)
proc: BEGIN
    DECLARE v_dias_sin_resp  INT;
    DECLARE v_meta           INT;
    DECLARE v_sla_horas      INT;
    DECLARE v_alerta_horas   INT;
    DECLARE v_existe         INT DEFAULT 0;
    DECLARE v_abierta        INT DEFAULT 0;
    DECLARE v_id_cliente     BIGINT;
    DECLARE v_id_responsable BIGINT;
    DECLARE v_fecha_envio    DATETIME;
    DECLARE v_numero         VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_area           VARCHAR(60)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_canal          INT;
    DECLARE v_canal_cod      VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_resultado      INT;
    DECLARE v_notas          TEXT         CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_asunto         VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_programar      TINYINT DEFAULT 0;
    DECLARE v_responsable    BIGINT;
    DECLARE v_id_seguimiento BIGINT;
    DECLARE v_usuario        VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tipo_accion    VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_ant_fecha      DATETIME;
    DECLARE v_ant_tipo       INT;
    DECLARE v_ant_detalle    VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_ant_prioridad  INT;
    DECLARE v_ant_resp       BIGINT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_seg;
        GET DIAGNOSTICS CONDITION 1
            @err_msg  = MESSAGE_TEXT,
            @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje,
               CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SET v_notas     = NULLIF(TRIM(IFNULL(p_notas, '')), '');
    SET v_asunto    = NULLIF(TRIM(IFNULL(p_asunto, '')), '');
    SET v_programar = IFNULL(p_programar, 0);

    -- Permiso
    IF FN_PermisoAccion(p_id_usuario, 'propuesta_seguimiento_registrar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para registrar seguimientos.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Propuesta en seguimiento abierto y en alcance
    CALL SP_CalcularSeguimientoComercial(p_id_usuario, p_id_propuesta,
                                         v_dias_sin_resp, v_meta, v_sla_horas, v_alerta_horas);
    SELECT COUNT(*), MAX(id_cliente), MAX(id_responsable), MAX(fecha_envio), MAX(numero),
           IFNULL(SUM(estado_seguimiento IN ('en_seguimiento', 'sin_respuesta', 'requiere_ajuste')), 0)
      INTO v_existe, v_id_cliente, v_id_responsable, v_fecha_envio, v_numero, v_abierta
    FROM tmp_seg;
    DROP TEMPORARY TABLE IF EXISTS tmp_seg;

    IF v_existe = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'La propuesta no está en seguimiento comercial o no pertenece a tu área.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_abierta = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El seguimiento de esta propuesta ya está cerrado (aceptada o rechazada).' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Tipo de seguimiento (canal)
    SELECT MAX(Num1), MAX(String2) INTO v_canal, v_canal_cod
    FROM tabla_maestra
    WHERE IdMaestro = 26 AND IdEmpresa = 1 AND Num2 = 1
      AND ((p_id_canal IS NOT NULL AND Num1 = p_id_canal)
           OR (p_id_canal IS NULL AND String2 = p_canal_codigo));
    IF v_canal IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Seleccione un tipo de seguimiento válido.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Resultado
    SELECT MAX(Num1) INTO v_resultado
    FROM tabla_maestra
    WHERE IdMaestro = 27 AND IdEmpresa = 1
      AND ((p_id_resultado IS NOT NULL AND Num1 = p_id_resultado)
           OR (p_id_resultado IS NULL AND String2 = p_resultado_codigo));
    IF v_resultado IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Seleccione el resultado del seguimiento.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Contacto
    IF p_id_contacto IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM contacto_cliente
        WHERE id_contacto = p_id_contacto AND id_cliente = v_id_cliente AND SoftDelete = 0) THEN
        SELECT 1 AS IdTipoMensaje, 'El contacto seleccionado no pertenece al cliente de la propuesta.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Fecha de la interacción (NULL = ahora, hora del servidor de BD)
    IF p_fecha_interaccion > NOW() + INTERVAL 5 MINUTE THEN
        SELECT 1 AS IdTipoMensaje, 'La fecha del seguimiento no puede ser futura.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF DATE(IFNULL(p_fecha_interaccion, NOW())) < DATE(v_fecha_envio) THEN
        SELECT 1 AS IdTipoMensaje,
               CONCAT('La fecha del seguimiento no puede ser anterior al envío de la propuesta (',
                      DATE_FORMAT(v_fecha_envio, '%d/%m/%Y'), ').') AS Mensaje;
        LEAVE proc;
    END IF;

    -- Notas, llamada y correo
    IF v_canal_cod = 'CORREO' THEN
        IF v_asunto IS NULL AND v_notas IS NULL THEN
            SELECT 1 AS IdTipoMensaje, 'Indique el asunto o el detalle del correo.' AS Mensaje;
            LEAVE proc;
        END IF;
    ELSEIF v_notas IS NULL OR CHAR_LENGTH(v_notas) < 5 THEN
        SELECT 1 AS IdTipoMensaje,
               IF(v_canal_cod = 'LLAMADA', 'Describa los puntos clave de la llamada (mínimo 5 caracteres).',
                                           'Escriba el detalle del seguimiento (mínimo 5 caracteres).') AS Mensaje;
        LEAVE proc;
    END IF;

    IF v_canal_cod = 'LLAMADA' AND (p_duracion_minutos IS NULL OR p_duracion_minutos < 0 OR p_duracion_minutos > 600) THEN
        SELECT 1 AS IdTipoMensaje, 'Indique la duración de la llamada en minutos (0 a 600).' AS Mensaje;
        LEAVE proc;
    END IF;

    IF p_id_correo IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM seguimiento_correo
        WHERE id_correo = p_id_correo AND id_propuesta = p_id_propuesta
          AND estado <> 'enviado' AND eliminado_en IS NULL) THEN
        SELECT 1 AS IdTipoMensaje, 'El correo no existe o ya fue registrado.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Próxima acción
    IF v_programar = 1 THEN
        SELECT MAX(String1) INTO v_tipo_accion
        FROM tabla_maestra
        WHERE Descripcion = 'TIPO_ACCION_SEGUIMIENTO' AND IdEmpresa = 1 AND Num1 = p_id_tipo_accion;
        IF v_tipo_accion IS NULL THEN
            SELECT 1 AS IdTipoMensaje, 'Seleccione el tipo de tarea de la próxima acción.' AS Mensaje;
            LEAVE proc;
        END IF;
        IF p_fecha_accion IS NULL OR p_fecha_accion <= NOW() THEN
            SELECT 1 AS IdTipoMensaje, 'La fecha y hora de la próxima acción deben ser futuras.' AS Mensaje;
            LEAVE proc;
        END IF;
        IF p_id_prioridad IS NULL OR NOT EXISTS (
            SELECT 1 FROM tabla_maestra WHERE IdMaestro = 7 AND IdEmpresa = 1 AND Num1 = p_id_prioridad) THEN
            SELECT 1 AS IdTipoMensaje, 'Seleccione la prioridad de la próxima acción.' AS Mensaje;
            LEAVE proc;
        END IF;

        SELECT area INTO v_area FROM usuario WHERE id_usuario = v_id_responsable;
        IF p_id_responsable_acc IS NULL OR NOT EXISTS (
            SELECT 1 FROM usuario
            WHERE id_usuario = p_id_responsable_acc AND eliminado_en IS NULL AND estado = 'activo'
              AND (area = v_area OR id_usuario = p_id_usuario)) THEN
            SELECT 1 AS IdTipoMensaje, 'Seleccione un responsable activo del área para la próxima acción.' AS Mensaje;
            LEAVE proc;
        END IF;
    END IF;

    IF IFNULL(p_solo_validar, 0) = 1 THEN
        SELECT 2 AS IdTipoMensaje, 'Validado.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Acción pendiente del último seguimiento (se mantiene si no se programa otra)
    IF v_programar = 0 AND IFNULL(p_ejecuta_accion, 0) = 0 THEN
        SELECT s.proxima_accion_fecha, s.id_tipo_proxima_accion, s.proxima_accion_detalle,
               s.id_prioridad_accion, s.id_responsable
          INTO v_ant_fecha, v_ant_tipo, v_ant_detalle, v_ant_prioridad, v_ant_resp
        FROM seguimiento_comercial s
        WHERE s.id_propuesta = p_id_propuesta AND s.eliminado_en IS NULL
        ORDER BY s.fecha_interaccion DESC, s.id_seguimiento DESC
        LIMIT 1;
    END IF;

    -- Guardar
    SET v_responsable = CASE
                            WHEN v_programar = 1       THEN p_id_responsable_acc
                            WHEN v_ant_fecha IS NOT NULL THEN v_ant_resp
                            ELSE p_id_usuario
                        END;

    START TRANSACTION;

    INSERT INTO seguimiento_comercial (
        id_propuesta, id_responsable, id_contacto, id_canal, id_resultado, notas, asunto, estado,
        fecha_interaccion, duracion_minutos,
        proxima_accion_fecha, id_tipo_proxima_accion, proxima_accion_detalle, id_prioridad_accion,
        permite_reactivacion, creado_por)
    VALUES (
        p_id_propuesta, v_responsable, p_id_contacto, v_canal, v_resultado, v_notas, v_asunto, 'activo',
        IFNULL(p_fecha_interaccion, NOW()), IF(v_canal_cod = 'LLAMADA', p_duracion_minutos, NULL),
        IF(v_programar = 1, p_fecha_accion, v_ant_fecha),
        IF(v_programar = 1, p_id_tipo_accion, v_ant_tipo),
        IF(v_programar = 1, NULLIF(TRIM(IFNULL(p_detalle_accion, '')), ''), v_ant_detalle),
        IF(v_programar = 1, p_id_prioridad, v_ant_prioridad),
        0, p_id_usuario);

    SET v_id_seguimiento = LAST_INSERT_ID();

    IF p_id_correo IS NOT NULL THEN
        UPDATE seguimiento_correo
        SET estado = 'enviado', id_seguimiento = v_id_seguimiento, proveedor = p_proveedor,
            id_mensaje = p_id_mensaje, error = NULL, fecha_envio = NOW(), modificado_por = p_id_usuario
        WHERE id_correo = p_id_correo;
    END IF;

    IF v_programar = 1 AND p_id_responsable_acc <> p_id_usuario THEN
        SELECT CONCAT(nombre, ' ', apellido) INTO v_usuario FROM usuario WHERE id_usuario = p_id_usuario;
        INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
        VALUES (p_id_responsable_acc, 5,
                CONCAT('Próxima acción asignada: ', v_numero),
                CONCAT(v_usuario, ' te asignó "', v_tipo_accion, '" para la propuesta ', v_numero,
                       ' el ', DATE_FORMAT(p_fecha_accion, '%d/%m/%Y %H:%i'), '.'),
                'propuesta', p_id_propuesta, NOW(), p_id_usuario);
    END IF;

    COMMIT;

    SELECT 2 AS IdTipoMensaje, 'Seguimiento registrado.' AS Mensaje;
    SELECT v_id_seguimiento AS id_seguimiento;
END$$

DELIMITER ;
