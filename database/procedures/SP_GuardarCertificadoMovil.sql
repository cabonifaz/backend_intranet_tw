-- ============================================================
-- SP_GuardarCertificadoMovil  (App Mobile HU-14 — "Correlativo y certificado" → Guardar; marca el correlativo como USADO)
-- Guarda el N° de certificado / constancia del equipo en su informe técnico (informe_tecnico.numero_certificado) y marca el correlativo como usado.
-- Solo se acepta un CORRELATIVO emitido para este técnico (formato CC-####-AAAA):
--   · el que Metrología le ASIGNÓ en un ticket de este equipo (ticket asignado → pasa a despachado = usado, con su hora), o
--   · uno de SU reserva diaria libre (reservado → usado, "por confirmar" por Metrología).
--   Cualquier otro (inexistente, de otro técnico, de otro equipo, ya usado) se rechaza. Idempotente: guardar de nuevo el mismo certificado responde éxito; un equipo
--   que ya tiene otro certificado no se reemplaza.
--   Contexto (OS suya, Hard Stop, equipo en ejecución, ensayos finalizados) por SP_ContextoCorrelativoMovil. Se bloquea el informe y luego el correlativo.
--   Con esto la etapa 5 "Correlativo y certificado" del trabajo en el equipo (SP_ObtenerTrabajoEquipoMovil) pasa a conforme. Auditoría: auditoria_evento.
-- Resultados: 1 mensaje (1 regla de negocio · 2 éxito · 3 error) · 2 (solo éxito) numero_certificado, origen (ticket · reserva), ticket.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_GuardarCertificadoMovil;

DELIMITER $$

CREATE PROCEDURE SP_GuardarCertificadoMovil(
    IN p_id_usuario   BIGINT,
    IN p_id_os        BIGINT,
    IN p_id_os_equipo BIGINT,
    IN p_certificado  VARCHAR(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_msg      VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_id_eq    BIGINT DEFAULT NULL;
    DECLARE v_estado   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_hab      TINYINT DEFAULT 0;
    DECLARE v_num_os   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_informe  BIGINT DEFAULT NULL;
    DECLARE v_final    DATETIME DEFAULT NULL;
    DECLARE v_cert_ant VARCHAR(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_cert     VARCHAR(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_corr     BIGINT DEFAULT NULL;
    DECLARE v_c_estado VARCHAR(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_c_ticket BIGINT DEFAULT NULL;
    DECLARE v_c_tec    BIGINT DEFAULT NULL;
    DECLARE v_t_equipo BIGINT DEFAULT NULL;
    DECLARE v_t_tec    BIGINT DEFAULT NULL;
    DECLARE v_t_estado VARCHAR(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_t_num    VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_origen   VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_ahora    DATETIME;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_cc_ctx;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 OR IFNULL(p_id_os_equipo, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio o equipo no válido.' AS Mensaje; LEAVE proc;
    END IF;
    SET v_cert = UPPER(TRIM(IFNULL(p_certificado, '')));
    IF v_cert = '' OR v_cert NOT REGEXP '^CC-[0-9]{4}-[0-9]{4}$' THEN
        SELECT 1 AS IdTipoMensaje, 'El certificado debe ser el correlativo que asignó Metrología, con el formato CC-0000-2026.' AS Mensaje; LEAVE proc;
    END IF;

    START TRANSACTION;

    CALL SP_ContextoCorrelativoMovil(p_id_usuario, p_id_os, p_id_os_equipo);
    SELECT c.mensaje, c.id_equipo, c.estado_equipo, c.habilitado, c.numero_os, c.id_informe, c.ens_final
    INTO   v_msg, v_id_eq, v_estado, v_hab, v_num_os, v_informe, v_final
    FROM   tmp_cc_ctx c LIMIT 1;
    DROP TEMPORARY TABLE IF EXISTS tmp_cc_ctx;

    IF v_msg IS NULL AND (v_hab = 0 OR v_estado <> 'en_ejecucion') THEN
        SET v_msg = IF(v_estado = 'pausado', 'El equipo está pausado: reanúdalo para guardar el certificado.',
                       IF(v_estado = 'completado', 'Este equipo ya está completado.', 'El servicio ya no está en curso.'));
    ELSEIF v_msg IS NULL AND (v_informe IS NULL OR v_final IS NULL) THEN
        SET v_msg = 'Primero finaliza los ensayos y la calibración del equipo.';
    END IF;
    IF v_msg IS NOT NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje; LEAVE proc;
    END IF;

    SELECT it.numero_certificado INTO v_cert_ant FROM informe_tecnico it WHERE it.id_informe = v_informe FOR UPDATE;
    IF v_cert_ant IS NOT NULL THEN
        ROLLBACK;
        IF v_cert_ant = v_cert THEN
            SELECT 2 AS IdTipoMensaje, 'El certificado ya estaba guardado.' AS Mensaje;
            SELECT v_cert AS numero_certificado, NULL AS origen, NULL AS ticket;
        ELSE
            SELECT 1 AS IdTipoMensaje, CONCAT('Este equipo ya tiene el certificado ', v_cert_ant, '.') AS Mensaje;
        END IF;
        LEAVE proc;
    END IF;

    SELECT c.id_correlativo, c.estado, c.id_ticket_met, c.id_tecnico INTO v_corr, v_c_estado, v_c_ticket, v_c_tec
    FROM   correlativo_metrologia c WHERE c.codigo = v_cert AND c.eliminado_en IS NULL FOR UPDATE;
    IF v_corr IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Ese correlativo no existe. Usa el que te asignó Metrología o uno de tu reserva.' AS Mensaje; LEAVE proc;
    END IF;

    IF v_c_estado = 'asignado' AND v_c_ticket IS NOT NULL THEN
        SELECT t.id_equipo, t.id_tecnico_solicitante, t.estado, t.numero INTO v_t_equipo, v_t_tec, v_t_estado, v_t_num
        FROM   ticket_metrologia t WHERE t.id_ticket_met = v_c_ticket FOR UPDATE;
        IF v_t_tec <> p_id_usuario OR v_t_equipo <> v_id_eq THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, 'Ese correlativo se asignó a otro técnico o a otro equipo.' AS Mensaje; LEAVE proc;
        ELSEIF v_t_estado <> 'asignado' THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, 'Ese correlativo ya se usó.' AS Mensaje; LEAVE proc;
        END IF;
        SET v_origen = 'ticket';
    ELSEIF v_c_estado = 'reservado' THEN
        IF v_c_tec <> p_id_usuario THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, 'Ese correlativo está reservado a otro técnico.' AS Mensaje; LEAVE proc;
        END IF;
        SET v_origen = 'reserva';
    ELSE
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Ese correlativo ya se usó.' AS Mensaje; LEAVE proc;
    END IF;

    SET v_ahora = UTC_TIMESTAMP();
    IF v_origen = 'ticket' THEN
        UPDATE ticket_metrologia SET estado = 'despachado', usado_en = v_ahora, modificado_por = p_id_usuario WHERE id_ticket_met = v_c_ticket;
        UPDATE correlativo_metrologia SET id_os = p_id_os, id_equipo = v_id_eq, usado_en = v_ahora, modificado_por = p_id_usuario WHERE id_correlativo = v_corr;
    ELSE
        UPDATE correlativo_metrologia SET estado = 'usado', id_os = p_id_os, id_equipo = v_id_eq, usado_en = v_ahora, modificado_por = p_id_usuario WHERE id_correlativo = v_corr;
    END IF;
    UPDATE informe_tecnico SET numero_certificado = v_cert, modificado_por = p_id_usuario WHERE id_informe = v_informe;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('informe_tecnico', v_informe, 'guardar_certificado', NULL, v_cert,
            LEFT(CONCAT('Certificado ', v_cert, ' vinculado al equipo de ', v_num_os, IF(v_origen = 'ticket', CONCAT(' (ticket ', v_t_num, ')'), ' (reserva del técnico, por confirmar)')), 900),
            p_id_usuario, NOW(), JSON_OBJECT('certificado', v_cert, 'origen', v_origen, 'id_correlativo', v_corr, 'id_ticket_met', v_c_ticket));

    COMMIT;

    SELECT 2 AS IdTipoMensaje, 'Certificado guardado: forma parte del informe técnico.' AS Mensaje;
    SELECT v_cert AS numero_certificado, v_origen AS origen, v_t_num AS ticket;
END$$

DELIMITER ;
