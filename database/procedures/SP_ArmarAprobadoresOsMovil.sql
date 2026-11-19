-- ============================================================
-- SP_ArmarAprobadoresOsMovil  (App Mobile — apoyo, NO es un endpoint)
-- Igual que SP_ArmarAprobadoresMovil pero a partir de la OS: toma el área de su RQ (area_servicio_rq.area_usuario) y deja en `tmp_aprobadores` a quienes
-- deben ver y recibir los avisos de ESE servicio. Quien la llame debe terminar con DROP TEMPORARY TABLE IF EXISTS tmp_aprobadores. Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ArmarAprobadoresOsMovil;

DELIMITER $$

CREATE PROCEDURE SP_ArmarAprobadoresOsMovil(
    IN p_id_os BIGINT
)
BEGIN
    DECLARE v_area VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;

    SELECT asr.area_usuario INTO v_area
    FROM   orden_servicio os
    JOIN   expediente_digital ed ON ed.id_expediente    = os.id_expediente
    JOIN   requerimiento      rq ON rq.id_requerimiento = ed.id_requerimiento
    JOIN   area_servicio_rq  asr ON asr.id_area_rq      = rq.id_area
    WHERE  os.id_os = p_id_os
    LIMIT 1;

    CALL SP_ArmarAprobadoresMovil(v_area);
END$$

DELIMITER ;
