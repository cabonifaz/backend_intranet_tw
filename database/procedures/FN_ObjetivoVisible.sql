-- ¿El equipo (fila de os_equipo) es un objetivo VISIBLE de su OS? (1 = sí, 0 = no)
-- Misma regla que la lista de objetivos de la app (SP_ArmarObjetivosMovil; si se cambia una, cambiar la otra): se ve si lo registró el técnico en campo
-- (ingresado_en_campo = 1), si la programación vigente de la OS no elige equipos (se trabajan todos) o si está entre los equipos de esa programación.
-- La usan los detalles de la intranet (Avance por equipos, detalle del servicio y contadores del seguimiento) para mostrar los mismos equipos que la app.
DROP FUNCTION IF EXISTS FN_ObjetivoVisible;

DELIMITER $$

CREATE FUNCTION FN_ObjetivoVisible(
    p_id_os_equipo BIGINT
) RETURNS TINYINT
READS SQL DATA
BEGIN
    DECLARE v_id_os     BIGINT DEFAULT NULL;
    DECLARE v_id_equipo BIGINT DEFAULT NULL;
    DECLARE v_campo     TINYINT DEFAULT 0;
    DECLARE v_id_prog   BIGINT DEFAULT NULL;
    DECLARE v_n         INT DEFAULT 0;
    DECLARE v_en        INT DEFAULT 0;

    SELECT oe.id_os, oe.id_equipo, IFNULL(oe.ingresado_en_campo, 0) INTO v_id_os, v_id_equipo, v_campo
    FROM   os_equipo oe WHERE oe.id = p_id_os_equipo;
    IF v_id_os IS NULL THEN RETURN 0; END IF;
    IF v_campo = 1 THEN RETURN 1; END IF;

    SELECT pr.id_programacion INTO v_id_prog
    FROM   programacion pr
    WHERE  pr.id_os = v_id_os AND pr.estado <> 'cancelada' AND pr.eliminado_en IS NULL
    ORDER BY pr.id_programacion DESC LIMIT 1;

    SELECT COUNT(*), IFNULL(SUM(pe.id_equipo = v_id_equipo), 0) INTO v_n, v_en
    FROM   programacion_equipo pe
    WHERE  pe.id_programacion = v_id_prog AND pe.eliminado_en IS NULL;

    RETURN IF(v_n = 0 OR v_en > 0, 1, 0);
END$$

DELIMITER ;
