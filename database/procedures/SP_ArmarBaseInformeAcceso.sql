-- ============================================================
-- SP_ArmarBaseInformeAcceso  (Revisión Técnica — apoyo, no es un endpoint · 24/11/2026)
-- Arma tmp_rt_base (SP_ArmarBaseInformes) para UN informe del técnico con la regla de acceso del PDF y de sus fotos:
--   · rt_bandeja con el informe en su alcance (informes de los técnicos de su área; gerencia / TI ven todo), o
--   · precot_ver si una precotización del informe o de su complementario está en su alcance del CRM (Comercial descarga el PDF desde el
--     modal de la precotización): los datos se leen sin el filtro de área.
-- p_acceso: rt (supervisor / jefe) · comercial · NULL (sin acceso; tmp_rt_base queda vacía). El que llama hace DROP TEMPORARY TABLE tmp_rt_base.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ArmarBaseInformeAcceso;

DELIMITER $$

CREATE PROCEDURE SP_ArmarBaseInformeAcceso(
    IN  p_id_usuario BIGINT,
    IN  p_id_informe BIGINT,
    OUT p_acceso     VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
BEGIN
    DECLARE v_n        INT DEFAULT 0;
    DECLARE v_prev_usr BIGINT;
    DECLARE v_prev_tod TINYINT;
    DECLARE v_prev_are VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    SET p_acceso = NULL;

    IF FN_PermisoAccion(p_id_usuario, 'rt_bandeja') = 1 THEN
        CALL SP_ArmarBaseInformes(p_id_usuario, IFNULL(p_id_informe, 0));
        SELECT COUNT(*) INTO v_n FROM tmp_rt_base;
        IF v_n > 0 THEN SET p_acceso = 'rt'; END IF;
    END IF;

    IF p_acceso IS NULL AND FN_PermisoAccion(p_id_usuario, 'precot_ver') = 1 THEN
        CALL SP_ArmarBasePrecotizaciones(p_id_usuario, NULL);
        SELECT COUNT(*) INTO v_n FROM tmp_pct_base WHERE id_informe_original = p_id_informe;
        DROP TEMPORARY TABLE IF EXISTS tmp_pct_base;
        IF v_n > 0 THEN
            SET v_prev_usr = @tw_inf_usuario, v_prev_tod = @tw_inf_ver_todo, v_prev_are = @tw_inf_area;
            SET @tw_inf_usuario = p_id_usuario, @tw_inf_ver_todo = 1, @tw_inf_area = NULL;
            CALL SP_ArmarBaseInformes(p_id_usuario, IFNULL(p_id_informe, 0));
            SET @tw_inf_usuario = v_prev_usr, @tw_inf_ver_todo = v_prev_tod, @tw_inf_area = v_prev_are;
            SELECT COUNT(*) INTO v_n FROM tmp_rt_base;
            IF v_n > 0 THEN SET p_acceso = 'comercial'; END IF;
        END IF;
    END IF;

    -- Sin acceso: deja tmp_rt_base creada y vacía para que el que llama la lea y la borre igual
    IF p_acceso IS NULL THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;
        CALL SP_ArmarBaseInformes(p_id_usuario, -1);
    END IF;
END$$

DELIMITER ;
