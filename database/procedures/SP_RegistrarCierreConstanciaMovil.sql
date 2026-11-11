-- ============================================================
-- SP_RegistrarCierreConstanciaMovil  (App Mobile HU-17 — "Servicio cerrado")
-- Lo llama el caso de uso cuando TODO está listo (informes completos y con sus responsables resueltos, constancia firmada y generada): ya generó el PDF de la
-- constancia (p_ruta_pdf) y, si el parámetro CONSTANCIA_ENVIO_CORREO = 1 y el correo está configurado, intentó enviarla al contacto del cliente. Aquí solo se
-- PERSISTE el cierre (os_constancia.cerrada_en, ruta del PDF y resultado del envío) revalidando la regla con SP_ArmarFirmasOsMovil. Idempotente: si ya estaba cerrado
-- devuelve éxito sin cambiar nada.
--   NO cambia orden_servicio.estado: no existe una regla de cierre iniciada por el técnico (la finalización la registra Seguimiento Operativo, HU-53 / Jefatura).
--   p_envio_estado: en_espera | enviado | error | desactivado | sin_correo.   Auditoría: auditoria_evento (entidad os_constancia, acción cierre_servicio).
-- Resultados: 1 mensaje (1 regla de negocio · 2 éxito · 3 error) · 2 (solo éxito) cerrado, cerrada_en (hora de Lima).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_RegistrarCierreConstanciaMovil;

DELIMITER $$

CREATE PROCEDURE SP_RegistrarCierreConstanciaMovil(
    IN p_id_usuario     BIGINT,
    IN p_id_os          BIGINT,
    IN p_ruta_pdf       VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_envio_estado   VARCHAR(12)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_envio_destino  VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_envio_detalle  VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_msg    VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_num    VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_horas INT; DECLARE v_vence DATETIME; DECLARE v_seg INT;
    DECLARE v_inf INT; DECLARE v_comp INT; DECLARE v_firm INT; DECLARE v_resp INT; DECLARE v_ok INT; DECLARE v_listo TINYINT;
    DECLARE v_lock   BIGINT DEFAULT NULL;
    DECLARE v_firmada DATETIME DEFAULT NULL; DECLARE v_gen DATETIME DEFAULT NULL; DECLARE v_cierre DATETIME DEFAULT NULL;
    DECLARE v_ahora  DATETIME DEFAULT UTC_TIMESTAMP();

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_fm_inf;
        DROP TEMPORARY TABLE IF EXISTS tmp_fm_resp;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_envio_estado, '') NOT IN ('en_espera', 'enviado', 'error', 'desactivado', 'sin_correo') THEN
        SELECT 1 AS IdTipoMensaje, 'El estado del envío no es válido.' AS Mensaje; LEAVE proc;
    END IF;
    CALL SP_ContextoFirmaMovil(p_id_usuario, p_id_os, v_msg, v_num);
    IF v_msg IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje; LEAVE proc;
    END IF;

    START TRANSACTION;
    SELECT os.id_os INTO v_lock FROM orden_servicio os WHERE os.id_os = p_id_os FOR UPDATE;
    SELECT k.firmado_en, k.generada_en, k.cerrada_en INTO v_firmada, v_gen, v_cierre FROM os_constancia k WHERE k.id_os = p_id_os FOR UPDATE;
    IF v_cierre IS NOT NULL THEN
        COMMIT;
        SELECT 2 AS IdTipoMensaje, 'El servicio ya estaba cerrado.' AS Mensaje;
        SELECT 1 AS cerrado, CONVERT_TZ(v_cierre, '+00:00', '-05:00') AS cerrada_en;
        LEAVE proc;
    END IF;

    CALL SP_ArmarFirmasOsMovil(p_id_os, v_horas, v_vence, v_seg, v_inf, v_comp, v_firm, v_resp, v_ok, v_listo);
    DROP TEMPORARY TABLE IF EXISTS tmp_fm_inf;
    DROP TEMPORARY TABLE IF EXISTS tmp_fm_resp;
    IF v_firmada IS NULL OR v_gen IS NULL OR v_listo = 0 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Todavía falta una firma o la constancia: el servicio no se puede cerrar.' AS Mensaje; LEAVE proc;
    END IF;

    UPDATE os_constancia SET cerrada_en = v_ahora, ruta_pdf = p_ruta_pdf, envio_estado = p_envio_estado, envio_destino = NULLIF(TRIM(p_envio_destino), ''),
           envio_en = IF(p_envio_estado = 'enviado', v_ahora, NULL), envio_detalle = LEFT(NULLIF(TRIM(p_envio_detalle), ''), 300), modificado_por = p_id_usuario
    WHERE  id_os = p_id_os;
    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('os_constancia', p_id_os, 'cierre_servicio', NULL, 'cerrado',
            LEFT(CONCAT('Servicio ', v_num, ' cerrado: ', v_firm, ' informe(s) firmado(s) y constancia firmada. Envío: ', p_envio_estado, '.'), 900), p_id_usuario, NOW(),
            JSON_OBJECT('envio_estado', p_envio_estado, 'envio_destino', p_envio_destino, 'pdf', p_ruta_pdf));
    COMMIT;

    SELECT 2 AS IdTipoMensaje, 'Servicio cerrado.' AS Mensaje;
    SELECT 1 AS cerrado, CONVERT_TZ(v_ahora, '+00:00', '-05:00') AS cerrada_en;
END$$

DELIMITER ;
