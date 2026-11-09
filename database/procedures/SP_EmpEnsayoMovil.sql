-- ============================================================
-- SP_EmpEnsayoMovil  (App Mobile HU-10 — apoyo, no es un endpoint)
-- Error máximo permitido (EMP) de una carga, UNA sola vez: ±0,5 e, ±1 e o ±1,5 e según cuántas divisiones (m = carga / e) tenga la carga y la clase de
-- exactitud del equipo (verificación inicial, OIML R76):
--   clase I   : hasta 50 000 e → 0,5 e · hasta 200 000 e → 1 e · más → 1,5 e
--   clase II  : hasta  5 000 e → 0,5 e · hasta  20 000 e → 1 e · más → 1,5 e
--   clase III : hasta    500 e → 0,5 e · hasta   2 000 e → 1 e · más → 1,5 e
--   clase IIII (IV): hasta 50 e → 0,5 e · hasta 200 e → 1 e · más → 1,5 e
-- Con la clase vacía o desconocida, o sin e, el EMP es NULL (no se puede evaluar). Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_EmpEnsayoMovil;

DELIMITER $$

CREATE PROCEDURE SP_EmpEnsayoMovil(
    IN  p_clase VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN  p_e     DECIMAL(14,4),
    IN  p_carga DECIMAL(14,4),
    OUT p_emp   DECIMAL(14,4)
)
BEGIN
    DECLARE v_l1 DECIMAL(14,2) DEFAULT NULL;
    DECLARE v_l2 DECIMAL(14,2) DEFAULT NULL;
    DECLARE v_m  DECIMAL(24,6);

    SET p_emp = NULL;
    IF p_e IS NULL OR p_e <= 0 OR p_carga IS NULL THEN
        SET p_emp = NULL;
    ELSE
        CASE UPPER(TRIM(IFNULL(p_clase, '')))
            WHEN 'I'    THEN SET v_l1 = 50000, v_l2 = 200000;
            WHEN 'II'   THEN SET v_l1 = 5000,  v_l2 = 20000;
            WHEN 'III'  THEN SET v_l1 = 500,   v_l2 = 2000;
            WHEN 'IIII' THEN SET v_l1 = 50,    v_l2 = 200;
            WHEN 'IV'   THEN SET v_l1 = 50,    v_l2 = 200;
            ELSE BEGIN END;
        END CASE;
        IF v_l1 IS NOT NULL THEN
            SET v_m = p_carga / p_e;
            SET p_emp = p_e * IF(v_m <= v_l1, 0.5, IF(v_m <= v_l2, 1, 1.5));
        END IF;
    END IF;
END$$

DELIMITER ;
