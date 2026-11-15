-- Datos de prueba de equipos para Ensayos y Calibración. Capacidad máxima SIEMPRE en kg; d y e en g cuando son menores a 1 kg (si no, en kg).
-- Se completan los equipos NUEVOS (id_equipo >= 19) y los activos que no tengan clase o d. EMP lo más pequeño posible: e = el paso 1-2-5 más
-- fino que deja n = capacidad / e dentro de la clase (II hasta 100 kg, n ≤ 100 000; III desde 100 kg, n ≤ 10 000), mínimo 0,1 g; d = e.
-- Una capacidad menor a 1 kg (p. ej. 71 g) pasa a 6 kg. Ejecutar con Alt+X (responder No al aviso de script grande). No hace falta reiniciar la API.
DROP PROCEDURE IF EXISTS tmp_completar_equipos;
DELIMITER $$
CREATE PROCEDURE tmp_completar_equipos()
BEGIN
    DECLARE v_fin   TINYINT DEFAULT 0;
    DECLARE v_id    BIGINT;
    DECLARE v_clase VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_un    VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cap, v_d, v_e, v_paso DECIMAL(14,4);
    DECLARE v_i     INT;
    DECLARE v_txt   VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_pasos VARCHAR(200) DEFAULT '0.0001,0.0002,0.0005,0.001,0.002,0.005,0.01,0.02,0.05,0.1,0.2,0.5,1,2,5,10,20,50,100';
    DECLARE cur CURSOR FOR
        SELECT id_equipo FROM equipo_cliente
        WHERE  es_activo = 1 AND (id_equipo >= 19 OR NULLIF(TRIM(clase_exactitud), '') IS NULL OR NULLIF(TRIM(division_minima), '') IS NULL);
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_fin = 1;

    OPEN cur;
    leer: LOOP
        FETCH cur INTO v_id;
        IF v_fin = 1 THEN LEAVE leer; END IF;

        CALL SP_EspecEquipoMovil(v_id, v_clase, v_un, v_cap, v_d, v_e);   -- capacidad ya en kg
        IF v_cap IS NULL OR v_cap < 1 THEN SET v_cap = 6; END IF;

        -- e: el paso más fino que no pasa del n máximo de la clase
        SET v_e = 100, v_i = 1;
        paso: LOOP
            SET v_paso = CAST(SUBSTRING_INDEX(SUBSTRING_INDEX(v_pasos, ',', v_i), ',', -1) AS DECIMAL(14,4));
            IF v_cap / v_paso <= IF(v_cap <= 100, 100000, 10000) OR v_i >= 19 THEN SET v_e = v_paso; LEAVE paso; END IF;
            SET v_i = v_i + 1;
        END LOOP;
        SET v_clase = IF(v_cap <= 100, 'II', 'III');

        -- Texto: d y e en g si son menores a 1 kg
        SET v_txt = CAST(IF(v_e < 1, v_e * 1000, v_e) AS CHAR);
        SET v_txt = IF(LOCATE('.', v_txt) > 0, TRIM(TRAILING '.' FROM TRIM(TRAILING '0' FROM v_txt)), v_txt);
        UPDATE equipo_cliente
        SET    alcance_maximo = CONCAT(TRIM(TRAILING '.' FROM TRIM(TRAILING '0' FROM CAST(v_cap AS CHAR))), ' kg'),
               division_minima = CONCAT(v_txt, IF(v_e < 1, ' g', ' kg')), division_verif = NULL, division_verif_igual = 1, clase_exactitud = v_clase
        WHERE  id_equipo = v_id;
    END LOOP;
    CLOSE cur;
END$$
DELIMITER ;

CALL tmp_completar_equipos();
DROP PROCEDURE IF EXISTS tmp_completar_equipos;

-- Comprobación
SELECT id_equipo, codigo_tw, marca, modelo, alcance_maximo, division_minima, division_verif_igual, clase_exactitud FROM equipo_cliente WHERE es_activo = 1 ORDER BY id_equipo DESC LIMIT 12;
