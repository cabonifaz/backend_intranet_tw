-- Ensayos: d y e con decimales llegaban como 0. Ejecutar completo (Alt+X); al final muestra la comprobación (d y e deben ser 0.5000). Luego reiniciar la API.
-- ============================================================
-- SP_EspecEquipoMovil  (App Mobile HU-10 / HU-15 — apoyo, NO es un endpoint)
-- Especificaciones metrológicas de un equipo, UNA sola vez: clase de exactitud, unidad, capacidad máxima, d y e (división de verificación; si no tiene,
-- la división mínima). Los datos del equipo son texto libre ("80,000 kg", "0,5 g", "0.5 kg"): "80,000" y "80 000" son miles, "0,5" es decimal; la unidad son las letras
-- del primer dato (kg por defecto). Lo usan SP_ContextoEnsayoMovil (Ensayos y Calibración) y SP_GuardarCabeceraInformeMovil (EMP de la prueba de una falla).
-- Los números se arman con la parte entera y la parte decimal por separado (cada una se convierte como entero): convertir directamente un texto con punto
-- ("0.5") a DECIMAL devolvía 0 en el servidor y d y e salían en 0. Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_EspecEquipoMovil;

DELIMITER $$

CREATE PROCEDURE SP_EspecEquipoMovil(
    IN  p_id_equipo BIGINT,
    OUT p_clase     VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    OUT p_unidad    VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    OUT p_cap_max   DECIMAL(14,4),
    OUT p_d         DECIMAL(14,4),
    OUT p_e         DECIMAL(14,4)
)
BEGIN
    DECLARE v_cap_txt VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_d_txt   VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_e_txt   VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_num     VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_ent     VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_dec     VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;

    SET p_clase = NULL, p_unidad = 'kg', p_cap_max = NULL, p_d = NULL, p_e = NULL;

    SELECT UPPER(NULLIF(TRIM(ec.clase_exactitud), '')), ec.alcance_maximo, ec.division_minima, IF(ec.division_verif_igual = 1, NULL, ec.division_verif)
    INTO   p_clase, v_cap_txt, v_d_txt, v_e_txt
    FROM   equipo_cliente ec WHERE ec.id_equipo = p_id_equipo;

    -- Capacidad máxima
    SET v_num = NULLIF(REGEXP_SUBSTR(IF(REGEXP_LIKE(TRIM(IFNULL(v_cap_txt, '')), '^[0-9]+,[0-9]{1,2}([^0-9]|$)'), REPLACE(v_cap_txt, ',', '.'), REPLACE(REPLACE(IFNULL(v_cap_txt, ''), ',', ''), ' ', '')), '[0-9]+([.][0-9]+)?'), '');
    IF v_num IS NOT NULL THEN
        SET v_ent = SUBSTRING_INDEX(v_num, '.', 1);
        SET v_dec = IF(LOCATE('.', v_num) > 0, SUBSTRING_INDEX(v_num, '.', -1), '');
        SET p_cap_max = CAST(v_ent AS UNSIGNED) + IF(v_dec = '', 0, CAST(v_dec AS UNSIGNED) / POW(10, CHAR_LENGTH(v_dec)));
    END IF;

    -- d (división de escala = división mínima)
    SET v_num = NULLIF(REGEXP_SUBSTR(IF(REGEXP_LIKE(TRIM(IFNULL(v_d_txt, '')), '^[0-9]+,[0-9]{1,2}([^0-9]|$)'), REPLACE(v_d_txt, ',', '.'), REPLACE(REPLACE(IFNULL(v_d_txt, ''), ',', ''), ' ', '')), '[0-9]+([.][0-9]+)?'), '');
    IF v_num IS NOT NULL THEN
        SET v_ent = SUBSTRING_INDEX(v_num, '.', 1);
        SET v_dec = IF(LOCATE('.', v_num) > 0, SUBSTRING_INDEX(v_num, '.', -1), '');
        SET p_d = CAST(v_ent AS UNSIGNED) + IF(v_dec = '', 0, CAST(v_dec AS UNSIGNED) / POW(10, CHAR_LENGTH(v_dec)));
    END IF;

    -- e (división de verificación; si es igual a d o no tiene, la división mínima)
    SET v_num = NULLIF(REGEXP_SUBSTR(IF(REGEXP_LIKE(TRIM(IFNULL(v_e_txt, '')), '^[0-9]+,[0-9]{1,2}([^0-9]|$)'), REPLACE(v_e_txt, ',', '.'), REPLACE(REPLACE(IFNULL(v_e_txt, ''), ',', ''), ' ', '')), '[0-9]+([.][0-9]+)?'), '');
    IF v_num IS NOT NULL THEN
        SET v_ent = SUBSTRING_INDEX(v_num, '.', 1);
        SET v_dec = IF(LOCATE('.', v_num) > 0, SUBSTRING_INDEX(v_num, '.', -1), '');
        SET p_e = CAST(v_ent AS UNSIGNED) + IF(v_dec = '', 0, CAST(v_dec AS UNSIGNED) / POW(10, CHAR_LENGTH(v_dec)));
    END IF;
    SET p_e = COALESCE(p_e, p_d);

    SET p_unidad = LOWER(IFNULL(NULLIF(REGEXP_SUBSTR(COALESCE(v_cap_txt, v_d_txt, ''), '[A-Za-z]+'), ''), 'kg'));
END$$

DELIMITER ;

CALL SP_EspecEquipoMovil((SELECT id_equipo FROM equipo_cliente WHERE codigo_tw = 'EQ-TW-2026-0001'), @clase, @unidad, @cap, @d, @e);
SELECT @clase AS clase, @unidad AS unidad, CAST(@cap AS CHAR) AS cap_texto, CAST(@d AS CHAR) AS d_texto, CAST(@e AS CHAR) AS e_texto;
