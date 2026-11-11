-- ============================================================
-- SP_TipoOrdenMovil  (App Mobile HU-08 / HU-15 — apoyo, NO es un endpoint)
-- Tipo de orden de una OS, UNA sola vez: lo define el área de la RQ (area_servicio_rq.area_usuario): servicio técnico → OS, metrología → OM.
-- Devuelve también el número de la RQ. Lo usan SP_ObtenerTrabajoEquipoMovil y la Cabecera del informe (SP_ObtenerCabeceraInformeMovil / SP_GuardarCabeceraInformeMovil).
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_TipoOrdenMovil;

DELIMITER $$

CREATE PROCEDURE SP_TipoOrdenMovil(
    IN  p_id_os     BIGINT,
    OUT p_tipo      VARCHAR(2)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    OUT p_numero_rq VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
BEGIN
    DECLARE v_area VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;

    SET p_tipo = 'OS', p_numero_rq = NULL;
    SELECT asr.area_usuario, rq.numero INTO v_area, p_numero_rq
    FROM   orden_servicio os
    JOIN   expediente_digital ed  ON ed.id_expediente = os.id_expediente
    JOIN   requerimiento      rq  ON rq.id_requerimiento = ed.id_requerimiento
    LEFT JOIN area_servicio_rq asr ON asr.id_area_rq = rq.id_area
    WHERE  os.id_os = p_id_os
    LIMIT 1;
    SET p_tipo = IF(v_area = 'metrologia', 'OM', 'OS');
END$$

DELIMITER ;
