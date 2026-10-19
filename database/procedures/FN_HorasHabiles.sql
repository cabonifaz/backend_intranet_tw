-- Horas hábiles entre dos fechas (HU-13, SLA del visto bueno).
-- Jornada lun–vie, de JORNADA_INICIO a JORNADA_FIN (PARAMETRO_PROPUESTA, por defecto 8 a 18).
-- No considera feriados. Devuelve horas con decimales (0 si hasta <= desde).
DROP FUNCTION IF EXISTS FN_HorasHabiles;

DELIMITER $$

CREATE FUNCTION FN_HorasHabiles(p_desde DATETIME, p_hasta DATETIME) RETURNS DECIMAL(10,2)
READS SQL DATA
BEGIN
    DECLARE v_ini   INT;
    DECLARE v_fin   INT;
    DECLARE v_dia   DATE;
    DECLARE v_a     DATETIME;
    DECLARE v_b     DATETIME;
    DECLARE v_min   BIGINT DEFAULT 0;
    DECLARE v_n     INT DEFAULT 0;

    IF p_desde IS NULL OR p_hasta IS NULL OR p_hasta <= p_desde THEN
        RETURN 0;
    END IF;

    SELECT IFNULL(MAX(CASE WHEN String2 = 'JORNADA_INICIO' THEN CAST(Num2 AS SIGNED) END), 8),
           IFNULL(MAX(CASE WHEN String2 = 'JORNADA_FIN'    THEN CAST(Num2 AS SIGNED) END), 18)
      INTO v_ini, v_fin
    FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROPUESTA';

    SET v_dia = DATE(p_desde);
    WHILE v_dia <= DATE(p_hasta) AND v_n < 800 DO
        IF WEEKDAY(v_dia) < 5 THEN
            SET v_a = GREATEST(p_desde, TIMESTAMP(v_dia, MAKETIME(v_ini, 0, 0)));
            SET v_b = LEAST(p_hasta,    TIMESTAMP(v_dia, MAKETIME(v_fin, 0, 0)));
            IF v_b > v_a THEN
                SET v_min = v_min + TIMESTAMPDIFF(MINUTE, v_a, v_b);
            END IF;
        END IF;
        SET v_dia = DATE_ADD(v_dia, INTERVAL 1 DAY);
        SET v_n = v_n + 1;
    END WHILE;

    RETURN ROUND(v_min / 60, 2);
END$$

DELIMITER ;
