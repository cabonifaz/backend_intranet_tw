-- HU-45 (Sprint 5) Revisión de un gasto rendido por el técnico desde la app móvil (pestaña Rendición de Gastos).
--   p_accion: 'aprobar' | 'observar' | 'rechazar'.
--   · Observar: comentario OBLIGATORIO; el técnico recibe la notificación para ajustar o adjuntar el comprobante.
--   · Rechazar: motivo OBLIGATORIO; el gasto no se reembolsa.
--   · Aprobar: solo con comprobante adjunto.
--   Solo el Jefe (prog_aprobar_reprogramacion), con la programación confirmada y la rendición abierta. Un gasto aprobado o rechazado es definitivo.
-- Resultados: 1 mensaje, 2 gasto resultante (estado, tarjetas).
DROP PROCEDURE IF EXISTS SP_RevisarGastoProgramacion;

DELIMITER $$

CREATE PROCEDURE SP_RevisarGastoProgramacion(
    IN p_id_usuario      BIGINT,
    IN p_id_programacion BIGINT,
    IN p_id_gasto        BIGINT,
    IN p_accion          VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_comentario      VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_id_os     BIGINT DEFAULT NULL;
    DECLARE v_numero    VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_codigo    VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado    VARCHAR(25)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_g_estado  VARCHAR(15)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_g_tec     BIGINT DEFAULT NULL;
    DECLARE v_g_monto   DECIMAL(12,2);
    DECLARE v_g_url     VARCHAR(500);
    DECLARE v_concepto  VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_nuevo     VARCHAR(15)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_com       VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_error     VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_titulo    VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cuerpo    VARCHAR(3000) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_mensaje   VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            @err_msg  = MESSAGE_TEXT,
            @err_code = MYSQL_ERRNO;
        ROLLBACK;
        IF @err_code IN (1213, 1205) THEN
            SELECT 1 AS IdTipoMensaje, 'Otra persona está modificando esta programación en este momento. Inténtalo de nuevo.' AS Mensaje;
        ELSE
            SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
        END IF;
    END;

    IF FN_PermisoAccion(p_id_usuario, 'prog_aprobar_reprogramacion') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Solo el Jefe de Operaciones puede revisar los gastos rendidos.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF IFNULL(p_id_programacion, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'La programación no existe.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF IFNULL(p_id_gasto, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El gasto no existe.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF p_accion IS NULL OR p_accion NOT IN ('aprobar', 'observar', 'rechazar') THEN
        SELECT 1 AS IdTipoMensaje, 'La acción debe ser aprobar, observar o rechazar.' AS Mensaje;
        LEAVE proc;
    END IF;
    SET v_com = NULLIF(TRIM(IFNULL(p_comentario, '')), '');
    IF v_com IS NOT NULL AND (CHAR_LENGTH(v_com) > 400 OR v_com REGEXP '[[:cntrl:]]') THEN
        SELECT 1 AS IdTipoMensaje, 'El comentario admite hasta 400 caracteres, sin caracteres de control.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF p_accion = 'observar' AND (v_com IS NULL OR CHAR_LENGTH(v_com) < 3) THEN
        SELECT 1 AS IdTipoMensaje, 'Para observar un gasto debes indicar qué debe corregir el técnico.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF p_accion = 'rechazar' AND (v_com IS NULL OR CHAR_LENGTH(v_com) < 3) THEN
        SELECT 1 AS IdTipoMensaje, 'Para rechazar un gasto debes indicar el motivo.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT id_os INTO v_id_os FROM programacion WHERE id_programacion = p_id_programacion AND eliminado_en IS NULL;
    IF v_id_os IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'La programación no existe.' AS Mensaje;
        LEAVE proc;
    END IF;

    START TRANSACTION;

    SELECT numero INTO v_numero FROM orden_servicio WHERE id_os = v_id_os AND eliminado_en IS NULL FOR UPDATE;
    SELECT codigo, estado INTO v_codigo, v_estado FROM programacion WHERE id_programacion = p_id_programacion AND eliminado_en IS NULL FOR UPDATE;

    IF v_codigo IS NULL THEN
        SET v_error = 'La programación no existe.';
    ELSEIF v_estado <> 'confirmada' THEN
        SET v_error = CONCAT('La programación ', v_codigo, ' no está Programada: no admite revisión de gastos.');
    ELSEIF EXISTS (SELECT 1 FROM programacion_rendicion WHERE id_programacion = p_id_programacion AND eliminado_en IS NULL) THEN
        SET v_error = 'La rendición ya fue cerrada: los gastos quedan solo de lectura.';
    END IF;

    IF v_error IS NULL THEN
        SELECT g.estado, g.id_usuario, g.monto, g.url_comprobante, IFNULL(c.String1, 'Gasto')
          INTO v_g_estado, v_g_tec, v_g_monto, v_g_url, v_concepto
        FROM gasto_viatico g
        LEFT JOIN tabla_maestra c ON c.IdMaestro = 25 AND c.IdEmpresa = 1 AND c.Num1 = g.id_concepto
        WHERE g.id_gasto = p_id_gasto AND g.tipo = 'gasto_solicitado' AND g.eliminado_en IS NULL
          AND (g.id_programacion = p_id_programacion OR (g.id_programacion IS NULL AND g.id_os = v_id_os))
        FOR UPDATE;
        IF v_g_estado IS NULL THEN
            SET v_error = 'El gasto no existe en esta programación.';
        ELSEIF v_g_estado IN ('aprobado', 'rechazado', 'rendido') THEN
            SET v_error = CONCAT('El gasto ya fue ', IF(v_g_estado = 'rechazado', 'rechazado', 'aprobado'), ': la decisión es definitiva.');
        ELSEIF v_g_estado = 'observado' AND p_accion = 'observar' THEN
            SET v_error = 'El gasto ya está observado: espera a que el técnico lo ajuste.';
        ELSEIF p_accion = 'aprobar' AND NULLIF(TRIM(IFNULL(v_g_url, '')), '') IS NULL THEN
            SET v_error = 'No se puede aprobar un gasto sin comprobante: obsérvalo para que el técnico lo adjunte.';
        END IF;
    END IF;
    IF v_error IS NOT NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, v_error AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_nuevo = CASE p_accion WHEN 'aprobar' THEN 'aprobado' WHEN 'observar' THEN 'observado' ELSE 'rechazado' END;

    UPDATE gasto_viatico
    SET estado = v_nuevo, comentario_revision = IF(p_accion = 'aprobar', NULL, v_com), revisado_por = p_id_usuario, revisado_en = NOW(),
        aprobado_por = IF(p_accion = 'aprobar', p_id_usuario, NULL), modificado_por = p_id_usuario
    WHERE id_gasto = p_id_gasto;

    SET v_titulo = LEFT(CASE p_accion WHEN 'aprobar' THEN CONCAT('Gasto aprobado: ', v_concepto)
                                      WHEN 'observar' THEN CONCAT('Gasto observado: ', v_concepto)
                                      ELSE CONCAT('Gasto rechazado: ', v_concepto) END, 150);
    SET v_cuerpo = LEFT(CONCAT(v_codigo, ' · ', v_numero, ' · ', v_concepto, ' S/ ', FORMAT(v_g_monto, 2), '. ',
                       CASE p_accion WHEN 'aprobar' THEN 'Tu gasto fue aprobado.'
                                     WHEN 'observar' THEN CONCAT('Ajusta o adjunta el comprobante: ', v_com)
                                     ELSE CONCAT('No se reembolsará. Motivo: ', v_com) END), 3000);
    INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
    VALUES (v_g_tec, 5, v_titulo, v_cuerpo, 'programacion', p_id_programacion, NOW(), p_id_usuario);

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('programacion', p_id_programacion, CONCAT('gasto_', v_nuevo), v_g_estado, v_nuevo,
            LEFT(CONCAT('Gasto ', p_id_gasto, ' (', v_concepto, ' S/ ', FORMAT(v_g_monto, 2), ') ', v_nuevo, ' en ', v_codigo, IF(v_com IS NULL, '', CONCAT(': ', v_com))), 900),
            p_id_usuario, NOW(), JSON_OBJECT('idGasto', p_id_gasto, 'idTecnico', v_g_tec, 'monto', v_g_monto, 'accion', p_accion));

    COMMIT;

    SET v_mensaje = CASE p_accion WHEN 'aprobar' THEN 'Gasto aprobado.'
                                  WHEN 'observar' THEN 'Gasto observado: se notificó al técnico para que lo ajuste.'
                                  ELSE 'Gasto rechazado: no se reembolsará.' END;
    SELECT 2 AS IdTipoMensaje, v_mensaje AS Mensaje;
    SELECT p_id_programacion AS id_programacion, p_id_gasto AS id_gasto, v_nuevo AS estado, v_g_tec AS id_tecnico;
    CALL SP_ResumenRendicionProgramacion(p_id_programacion, 1);
END$$

DELIMITER ;
