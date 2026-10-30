-- Secciones activas de una propuesta, completas y en el orden del wizard (configuracion, propuesta, opcionales, detalle,
-- recomendaciones, forma_pago, suministros_cliente, condiciones, listado_equipos).
-- Las fijas (configuracion, propuesta, forma_pago, listado_equipos) siempre van; las opcionales solo si están en
-- propuesta_comercial.secciones_activas. Si secciones_activas es NULL (propuestas antiguas) van todas (igual que
-- SP_PrepararDecisionVistoBueno).
DROP FUNCTION IF EXISTS FN_SeccionesActivasPropuesta;

DELIMITER $$

CREATE FUNCTION FN_SeccionesActivasPropuesta(p_secciones JSON) RETURNS JSON
DETERMINISTIC
BEGIN
    DECLARE v_todas TINYINT DEFAULT (p_secciones IS NULL OR NOT JSON_VALID(p_secciones) OR JSON_TYPE(p_secciones) <> 'ARRAY');

    RETURN CAST(CONCAT('[', CONCAT_WS(',',
        '"configuracion"',
        '"propuesta"',
        IF(v_todas = 1 OR JSON_CONTAINS(p_secciones, '"opcionales"'),          '"opcionales"',          NULL),
        IF(v_todas = 1 OR JSON_CONTAINS(p_secciones, '"detalle"'),             '"detalle"',             NULL),
        IF(v_todas = 1 OR JSON_CONTAINS(p_secciones, '"recomendaciones"'),     '"recomendaciones"',     NULL),
        '"forma_pago"',
        IF(v_todas = 1 OR JSON_CONTAINS(p_secciones, '"suministros_cliente"'), '"suministros_cliente"', NULL),
        IF(v_todas = 1 OR JSON_CONTAINS(p_secciones, '"condiciones"'),         '"condiciones"',         NULL),
        '"listado_equipos"'), ']') AS JSON);
END$$

DELIMITER ;
