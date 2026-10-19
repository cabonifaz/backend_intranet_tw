-- Próximo código de una ficha en modo "nuevo" (transversal, reunión 02-oct).
-- Es REFERENCIAL: el definitivo se asigna al guardar (otro usuario puede guardar antes).
--   p_entidad: requerimiento | propuesta | suministro | equipo_cliente
DROP PROCEDURE IF EXISTS SP_ObtenerSiguienteCodigo;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerSiguienteCodigo(
    IN p_entidad VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
BEGIN
    DECLARE v_codigo VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_n      BIGINT;

    IF p_entidad = 'requerimiento' THEN
        SELECT IFNULL(MAX(id_requerimiento), 0) + 1 INTO v_n FROM requerimiento;
        SET v_codigo = CONCAT('RQ-', LPAD(v_n, 4, '0'), '-', YEAR(NOW()));
    ELSEIF p_entidad = 'propuesta' THEN
        SELECT IFNULL(MAX(id_propuesta), 0) + 1 INTO v_n FROM propuesta_comercial;
        SET v_codigo = CONCAT('PROP-', LPAD(v_n, 6, '0'));
    ELSEIF p_entidad = 'suministro' THEN
        SELECT IFNULL(MAX(id_suministro), 0) + 1 INTO v_n FROM suministros;
        SET v_codigo = CONCAT('SUM-', LPAD(v_n, 4, '0'));
    ELSEIF p_entidad = 'equipo_cliente' THEN
        SELECT IFNULL(MAX(CAST(SUBSTRING_INDEX(codigo_tw, '-', -1) AS UNSIGNED)), 0) + 1 INTO v_n
        FROM equipo_cliente
        WHERE codigo_tw LIKE CONCAT('EQ-TW-', YEAR(NOW()), '-%');
        SET v_codigo = CONCAT('EQ-TW-', YEAR(NOW()), '-', LPAD(v_n, 4, '0'));
    END IF;

    IF v_codigo IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Entidad no válida. Use requerimiento, propuesta, suministro o equipo_cliente.' AS Mensaje;
    ELSE
        SELECT 2 AS IdTipoMensaje, 'Código referencial: el definitivo se asigna al guardar.' AS Mensaje;
        SELECT p_entidad AS entidad, v_codigo AS codigo;
    END IF;
END$$

DELIMITER ;
