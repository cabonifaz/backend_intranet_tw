-- HU-19 Guardar el correo de seguimiento como borrador o con el error de envío.
-- p_estado: borrador | error. El paso a 'enviado' lo hace SP_RegistrarSeguimiento al registrar
-- el seguimiento (así el correo enviado siempre queda enlazado a su seguimiento).
-- p_id_correo NULL crea un correo nuevo. Si viene, actualiza ese correo (debe ser del mismo usuario
-- y propuesta y no estar enviado).
-- Resultados: 1 mensaje, 2 id_correo y datos del usuario remitente (nombre, correo, cargo).
DROP PROCEDURE IF EXISTS SP_GuardarCorreoSeguimiento;

DELIMITER $$

CREATE PROCEDURE SP_GuardarCorreoSeguimiento(
    IN p_id_usuario   BIGINT,
    IN p_id_propuesta BIGINT,
    IN p_id_correo    BIGINT,
    IN p_id_plantilla INT,
    IN p_para         TEXT         CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_cc           TEXT         CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_asunto       VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_cuerpo_html  MEDIUMTEXT   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_estado       VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_proveedor    VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_error        VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_dias_sin_resp  INT;
    DECLARE v_meta           INT;
    DECLARE v_sla_horas      INT;
    DECLARE v_alerta_horas   INT;
    DECLARE v_existe         INT DEFAULT 0;
    DECLARE v_abierta        INT DEFAULT 0;
    DECLARE v_id_correo      BIGINT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        DROP TEMPORARY TABLE IF EXISTS tmp_seg;
        GET DIAGNOSTICS CONDITION 1
            @err_msg  = MESSAGE_TEXT,
            @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje,
               CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF FN_PermisoAccion(p_id_usuario, 'propuesta_seguimiento_registrar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para registrar seguimientos.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF IFNULL(p_estado, '') NOT IN ('borrador', 'error') THEN
        SELECT 1 AS IdTipoMensaje, 'Estado de correo no válido.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_CalcularSeguimientoComercial(p_id_usuario, p_id_propuesta,
                                         v_dias_sin_resp, v_meta, v_sla_horas, v_alerta_horas);
    SELECT COUNT(*),
           IFNULL(SUM(estado_seguimiento IN ('en_seguimiento', 'sin_respuesta', 'requiere_ajuste')), 0)
      INTO v_existe, v_abierta
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

    IF p_id_plantilla IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM plantilla_correo_seguimiento WHERE id_plantilla = p_id_plantilla AND eliminado_en IS NULL) THEN
        SELECT 1 AS IdTipoMensaje, 'La plantilla seleccionada no existe.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF p_id_correo IS NULL THEN
        INSERT INTO seguimiento_correo (id_propuesta, id_plantilla, para, cc, asunto, cuerpo_html,
                                        estado, proveedor, error, id_usuario, creado_por)
        VALUES (p_id_propuesta, p_id_plantilla, IFNULL(p_para, '[]'), p_cc, IFNULL(p_asunto, ''),
                IFNULL(p_cuerpo_html, ''), p_estado, p_proveedor, p_error, p_id_usuario, p_id_usuario);
        SET v_id_correo = LAST_INSERT_ID();
    ELSE
        IF NOT EXISTS (SELECT 1 FROM seguimiento_correo
                       WHERE id_correo = p_id_correo AND id_propuesta = p_id_propuesta
                         AND id_usuario = p_id_usuario AND estado <> 'enviado' AND eliminado_en IS NULL) THEN
            SELECT 1 AS IdTipoMensaje, 'El borrador no existe, es de otro usuario o ya fue enviado.' AS Mensaje;
            LEAVE proc;
        END IF;
        UPDATE seguimiento_correo
        SET id_plantilla = p_id_plantilla, para = IFNULL(p_para, '[]'), cc = p_cc,
            asunto = IFNULL(p_asunto, ''), cuerpo_html = IFNULL(p_cuerpo_html, ''),
            estado = p_estado, proveedor = p_proveedor, error = p_error, modificado_por = p_id_usuario
        WHERE id_correo = p_id_correo;
        SET v_id_correo = p_id_correo;
    END IF;

    SELECT 2 AS IdTipoMensaje, IF(p_estado = 'borrador', 'Borrador guardado.', 'Error de envío registrado.') AS Mensaje;
    SELECT v_id_correo AS id_correo,
           CONCAT(u.nombre, ' ', u.apellido) AS usuario, u.correo AS correo_usuario, u.cargo AS cargo_usuario
    FROM usuario u WHERE u.id_usuario = p_id_usuario;
END$$

DELIMITER ;
