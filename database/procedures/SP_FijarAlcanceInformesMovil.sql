-- ============================================================
-- SP_FijarAlcanceInformesMovil  (App Mobile HU-33 — apoyo, NO es un endpoint)
-- Fija, para SP_ArmarBaseInformes, el alcance de informes de la app según la regla ÁREA + ROL (SP_ResolverAprobadorMovil, la misma de aprobaciones y alertas):
--   · Gerencia, Operaciones, Administración, TI, SSOMA, Calidad, Comercial (cualquier rol) y Administradores → informes de TODAS las áreas.
--   · Supervisor de Servicio Técnico / Metrología → solo los informes de los técnicos de su área.
--   · Usuario / Visor de Servicio Técnico / Metrología (o sin área) → p_tiene = 0 (no tiene Jefatura).
-- Lo hace con variables de sesión (@tw_inf_usuario, @tw_inf_ver_todo, @tw_inf_area): SP_ArmarBaseInformes las respeta SOLO si @tw_inf_usuario es el usuario que consulta, así la intranet
-- (que no las fija) sigue con su regla de siempre. Quien llame a este SP debe terminar con: SET @tw_inf_usuario = NULL, @tw_inf_ver_todo = NULL, @tw_inf_area = NULL.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_FijarAlcanceInformesMovil;

DELIMITER $$

CREATE PROCEDURE SP_FijarAlcanceInformesMovil(
    IN  p_id_usuario BIGINT,
    OUT p_tiene      TINYINT
)
BEGIN
    DECLARE v_area VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_gen  TINYINT DEFAULT 0;

    SET p_tiene = 0;
    CALL SP_ResolverAprobadorMovil(p_id_usuario, v_area, v_gen);

    SET @tw_inf_usuario  = p_id_usuario;
    SET @tw_inf_ver_todo = IFNULL(v_gen, 0);
    SET @tw_inf_area     = IF(IFNULL(v_gen, 0) = 1, NULL, v_area);
    SET p_tiene          = IF(IFNULL(v_gen, 0) = 1 OR v_area IS NOT NULL, 1, 0);
END$$

DELIMITER ;
