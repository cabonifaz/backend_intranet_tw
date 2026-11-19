-- ============================================================
-- SP_ArmarEquipoAgendaMovil  (App Mobile HU-37 «Agenda y carga del área» — apoyo, NO es un endpoint)
-- El equipo de técnicos que ve el jefe en la agenda, la carga, los conflictos y sus acciones: el MISMO de «Mi equipo» (SP_ArmarEquipoJefaturaMovil, regla Área + Rol de SP_ResolverAprobadorMovil), pero
-- incluyendo también a los técnicos dados de baja o suspendidos, porque el conflicto «técnico de baja o ausente» (HU-39) es justamente de ellos y el jefe debe poder verlo y resolverlo.
-- Deja la tabla temporal `tmp_eq` (solo jornada; ver SP_ArmarEquipoJefaturaMovil). Quien la llame debe terminar con DROP TEMPORARY TABLE IF EXISTS tmp_eq.
-- p_id_tecnico: no NULL = solo ese técnico (tmp_eq queda vacía si no es del alcance). p_sin_menu = 1: el usuario no tiene menú de Jefatura («Tu cargo no tiene el menú de Jefatura.»).
-- Solo lectura. La variable @tw_eq_inactivos solo vive durante esta llamada (se limpia también si falla).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ArmarEquipoAgendaMovil;

DELIMITER $$

CREATE PROCEDURE SP_ArmarEquipoAgendaMovil(
    IN  p_id_usuario BIGINT,
    IN  p_id_tecnico BIGINT,
    OUT p_sin_menu   TINYINT
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        SET @tw_eq_inactivos = 0;
        RESIGNAL;
    END;

    SET p_sin_menu = 0;
    SET @tw_eq_inactivos = 1;
    CALL SP_ArmarEquipoJefaturaMovil(p_id_usuario, p_id_tecnico, 0, p_sin_menu);
    SET @tw_eq_inactivos = 0;
END$$

DELIMITER ;
