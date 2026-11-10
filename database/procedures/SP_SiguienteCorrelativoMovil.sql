-- ============================================================
-- SP_SiguienteCorrelativoMovil  (App Mobile HU-14 / HU-34 — apoyo, NO es un endpoint)
-- El siguiente correlativo de certificación CC-####-AAAA disponible, de la ÚNICA secuencia (correlativo_secuencia) que usan los tickets y las reservas.
-- Año = el de Lima (UTC-5). Salta los números ya emitidos (correlativo_metrologia). Quien consume lo hace dentro de su transacción.
--   p_consumir = 0 → solo sugiere (no escribe, no bloquea).
--   p_consumir = 1 → bloquea la fila del año (FOR UPDATE), deja la secuencia en ese número y devuelve el código; quien llama lo inserta en correlativo_metrologia
--                    antes del COMMIT. Con el año agotado (9999) devuelve NULL.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_SiguienteCorrelativoMovil;

DELIMITER $$

CREATE PROCEDURE SP_SiguienteCorrelativoMovil(
    IN  p_consumir TINYINT,
    OUT p_numero   INT,
    OUT p_codigo   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    OUT p_anio     SMALLINT
)
BEGIN
    DECLARE v_ultimo INT DEFAULT 0;

    SET p_anio = YEAR(UTC_TIMESTAMP() - INTERVAL 5 HOUR);
    IF p_consumir = 1 THEN
        INSERT IGNORE INTO correlativo_secuencia (anio, ultimo) VALUES (p_anio, 0);
        SELECT s.ultimo INTO v_ultimo FROM correlativo_secuencia s WHERE s.anio = p_anio FOR UPDATE;
    ELSE
        SELECT IFNULL(MAX(s.ultimo), 0) INTO v_ultimo FROM correlativo_secuencia s WHERE s.anio = p_anio;
    END IF;

    SET p_numero = v_ultimo + 1;
    WHILE p_numero <= 9999 AND EXISTS (SELECT 1 FROM correlativo_metrologia c WHERE c.anio = p_anio AND c.numero = p_numero) DO
        SET p_numero = p_numero + 1;
    END WHILE;

    IF p_numero > 9999 THEN
        SET p_numero = NULL;
        SET p_codigo = NULL;
    ELSE
        SET p_codigo = CONCAT('CC-', LPAD(p_numero, 4, '0'), '-', p_anio);
        IF p_consumir = 1 THEN
            UPDATE correlativo_secuencia SET ultimo = p_numero WHERE anio = p_anio;
        END IF;
    END IF;
END$$

DELIMITER ;
