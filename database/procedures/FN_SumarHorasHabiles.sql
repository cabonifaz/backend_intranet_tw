-- Fecha y hora en que se cumplen N horas hábiles desde una fecha (HU-13, vencimiento del SLA).
-- Misma jornada que FN_HorasHabiles (lun–vie, JORNADA_INICIO a JORNADA_FIN, sin feriados).
DROP FUNCTION IF EXISTS FN_SumarHorasHabiles;

DELIMITER $$

CREATE FUNCTION FN_SumarHorasHabiles(p_desde DATETIME, p_horas DECIMAL(10,2)) RETURNS DATETIME
READS SQL DATA
BEGIN
    DECLARE v_ini       INT;
    DECLARE v_fin       INT;
    DECLARE v_actual    DATETIME;
    DECLARE v_cierre    DATETIME;
    DECLARE v_restante  BIGINT;
    DECLARE v_disp      BIGINT;
    DECLARE v_n         INT DEFAULT 0;

    IF p_desde IS NULL THEN
        RETURN NULL;
    END IF;

    SELECT IFNULL(MAX(CASE WHEN String2 = 'JORNADA_INICIO' THEN CAST(Num2 AS SIGNED) END), 8),
           IFNULL(MAX(CASE WHEN String2 = 'JORNADA_FIN'    THEN CAST(Num2 AS SIGNED) END), 18)
      INTO v_ini, v_fin
    FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROPUESTA';

    SET v_restante = ROUND(IFNULL(p_horas, 0) * 60);
    SET v_actual   = p_desde;

    WHILE v_n < 800 DO
        -- Llevar al próximo momento hábil
        IF WEEKDAY(v_actual) >= 5 OR TIME(v_actual) >= MAKETIME(v_fin, 0, 0) THEN
            SET v_actual = TIMESTAMP(DATE_ADD(DATE(v_actual), INTERVAL 1 DAY), MAKETIME(v_ini, 0, 0));
        ELSEIF TIME(v_actual) < MAKETIME(v_ini, 0, 0) THEN
            SET v_actual = TIMESTAMP(DATE(v_actual), MAKETIME(v_ini, 0, 0));
        ELSE
            SET v_cierre = TIMESTAMP(DATE(v_actual), MAKETIME(v_fin, 0, 0));
            SET v_disp   = TIMESTAMPDIFF(MINUTE, v_actual, v_cierre);
            IF v_restante <= v_disp THEN
                RETURN DATE_ADD(v_actual, INTERVAL v_restante MINUTE);
            END IF;
            SET v_restante = v_restante - v_disp;
            SET v_actual   = v_cierre;
        END IF;
        SET v_n = v_n + 1;
    END WHILE;

    RETURN v_actual;
END$$

DELIMITER ;
