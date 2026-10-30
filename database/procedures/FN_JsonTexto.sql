-- Valor de texto de un JSON en la ruta indicada. NULL si no existe, es null o queda vacío.
-- (JSON_UNQUOTE de un null JSON devuelve el texto 'null'; esta función lo evita.)
DROP FUNCTION IF EXISTS FN_JsonTexto;

DELIMITER $$

CREATE FUNCTION FN_JsonTexto(
    p_json JSON,
    p_ruta VARCHAR(200)
) RETURNS VARCHAR(4000) CHARSET utf8mb4 COLLATE utf8mb4_0900_ai_ci
DETERMINISTIC
BEGIN
    DECLARE v_valor JSON;
    IF p_json IS NULL THEN
        RETURN NULL;
    END IF;
    SET v_valor = JSON_EXTRACT(p_json, p_ruta);
    IF v_valor IS NULL OR JSON_TYPE(v_valor) = 'NULL' THEN
        RETURN NULL;
    END IF;
    RETURN NULLIF(TRIM(JSON_UNQUOTE(v_valor)), '');
END$$

DELIMITER ;
