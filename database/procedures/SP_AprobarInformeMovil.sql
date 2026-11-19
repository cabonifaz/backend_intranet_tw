-- ============================================================
-- SP_AprobarInformeMovil  (App Mobile HU-33 — "Aprobar y liberar" el informe, Jefe de Área)
-- Es la MISMA revisión de la intranet (HU-59): delega en SP_RegistrarRevisionInforme, que vuelve a validar el checklist obligatorio (fotos, ensayos con resultado, precotización si
-- hay observaciones y procedimiento ejecutado), deja el informe REVISADO (cerrado e inmutable), envía la precotización a Comercial, registra el historial y avisa al técnico y al
-- responsable de la RQ. Aquí solo se agrega lo propio de la app:
--   · Acceso: rt_revisar + alcance de la app (regla ÁREA + ROL: SP_FijarAlcanceInformesMovil, que SP_RegistrarRevisionInforme respeta al armar su base).
--   · No se aprueba un informe OBSERVADO o con una corrección pendiente (el técnico debe atenderla).
--   · No se aprueba con una evidencia FORZADA sin revisar: primero se resuelve en Aprobaciones (HU-12).
--   p_nota: nota interna del jefe (opcional, hasta 500 caracteres).
-- Resultados (los de SP_RegistrarRevisionInforme): 1 mensaje · 2 (id_informe, estado = revisado, fecha_revision, id_precotizacion, numero_precotizacion).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_AprobarInformeMovil;

DELIMITER $$

CREATE PROCEDURE SP_AprobarInformeMovil(
    IN p_id_usuario BIGINT,
    IN p_id_informe BIGINT,
    IN p_nota       VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_tiene    TINYINT DEFAULT 0;
    DECLARE v_existe   INT DEFAULT 0;
    DECLARE v_estado   VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_forz_sr  INT DEFAULT 0;
    DECLARE v_corr     INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SET @tw_inf_usuario = NULL, @tw_inf_ver_todo = NULL, @tw_inf_area = NULL;
        DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF FN_PermisoAccion(p_id_usuario, 'rt_revisar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para registrar la revisión de informes.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF IFNULL(p_id_informe, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El informe indicado no es válido.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_FijarAlcanceInformesMovil(p_id_usuario, v_tiene);
    IF v_tiene = 0 THEN
        SET @tw_inf_usuario = NULL, @tw_inf_ver_todo = NULL, @tw_inf_area = NULL;
        SELECT 1 AS IdTipoMensaje, 'Tu cargo no tiene el menú de Jefatura.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_ArmarBaseInformes(p_id_usuario, p_id_informe);
    SELECT COUNT(*), MAX(estado), IFNULL(MAX(n_forzadas_sin_revision), 0) INTO v_existe, v_estado, v_forz_sr FROM tmp_rt_base;
    DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;
    IF v_existe = 0 THEN
        SET @tw_inf_usuario = NULL, @tw_inf_ver_todo = NULL, @tw_inf_area = NULL;
        SELECT 1 AS IdTipoMensaje, 'El informe no existe o no está en tu alcance.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT COUNT(*) INTO v_corr FROM informe_correccion WHERE id_informe = p_id_informe AND estado = 'pendiente' AND eliminado_en IS NULL;
    IF v_estado = 'observado' OR v_corr > 0 THEN
        SET @tw_inf_usuario = NULL, @tw_inf_ver_todo = NULL, @tw_inf_area = NULL;
        SELECT 1 AS IdTipoMensaje, 'El informe está en corrección: el técnico debe atenderla antes de aprobarlo.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_forz_sr > 0 THEN
        SET @tw_inf_usuario = NULL, @tw_inf_ver_todo = NULL, @tw_inf_area = NULL;
        SELECT 1 AS IdTipoMensaje, 'Tiene una evidencia forzada sin revisar: resuélvela primero en Aprobaciones.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- La revisión de la intranet (valida el checklist, cierra el informe y avisa). Las variables del alcance siguen fijas: también arma su base con la regla de la app.
    CALL SP_RegistrarRevisionInforme(p_id_usuario, p_id_informe, p_nota);
    SET @tw_inf_usuario = NULL, @tw_inf_ver_todo = NULL, @tw_inf_area = NULL;
END$$

DELIMITER ;
