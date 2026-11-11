-- ============================================================
-- SP_ResumenFirmasOsMovil  (App Mobile HU-17 — acceso "Firma de informes" en el menú de la orden · solo lectura, ligero)
-- Cuántos informes técnicos tiene la OS (completos, es decir generados) y cuántos están firmados, y si el servicio ya está cerrado. La regla de firmas es la de
-- SP_ArmarFirmasOsMovil (una sola vez). Resultados: 1 mensaje · 2 (solo éxito) informes, completos, firmados, resueltos, responsables, cerrado.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ResumenFirmasOsMovil;

DELIMITER $$

CREATE PROCEDURE SP_ResumenFirmasOsMovil(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT
)
proc: BEGIN
    DECLARE v_msg   VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_num   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_horas INT; DECLARE v_vence DATETIME; DECLARE v_seg INT;
    DECLARE v_inf INT; DECLARE v_comp INT; DECLARE v_firm INT; DECLARE v_resp INT; DECLARE v_ok INT; DECLARE v_listo TINYINT;
    DECLARE v_cierre DATETIME DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_fm_inf;
        DROP TEMPORARY TABLE IF EXISTS tmp_fm_resp;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    CALL SP_ContextoFirmaMovil(p_id_usuario, p_id_os, v_msg, v_num);
    IF v_msg IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje; LEAVE proc;
    END IF;
    CALL SP_ArmarFirmasOsMovil(p_id_os, v_horas, v_vence, v_seg, v_inf, v_comp, v_firm, v_resp, v_ok, v_listo);
    DROP TEMPORARY TABLE IF EXISTS tmp_fm_inf;
    DROP TEMPORARY TABLE IF EXISTS tmp_fm_resp;
    SELECT k.cerrada_en INTO v_cierre FROM os_constancia k WHERE k.id_os = p_id_os;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;
    SELECT v_inf AS informes, v_comp AS completos, v_firm AS firmados, v_ok AS resueltos, v_resp AS responsables, IF(v_cierre IS NULL, 0, 1) AS cerrado;
END$$

DELIMITER ;
