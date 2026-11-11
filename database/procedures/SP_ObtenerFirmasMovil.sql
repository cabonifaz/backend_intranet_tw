-- ============================================================
-- SP_ObtenerFirmasMovil  (App Mobile HU-17 — "Lista de informes" · solo lectura)
-- El técnico ve los informes técnicos de su OS y quién debe firmar cada uno. El estado de firmas lo arma, una sola vez, SP_ArmarFirmasOsMovil.
-- Resultados: 1 mensaje · 2 cabecera (1 fila) · 3 informes (uno por equipo) · 4 responsables (con sus trazos, para el "Firmados · Editar firma").
--   Cabecera: plazo_horas y segundos_restantes de la aceptación tácita (desde el primer informe generado; NULL sin informes) · tacita_activa (hay plazo corriendo y
--     algo pendiente) · informes (total) · completos · firmados · responsables · resueltos · listo (todo completo y resuelto) · constancia_firmada ·
--     constancia_generada · cerrado (servicio cerrado).
--   Informe: estado COMPLETO (generado, con responsable) o INCOMPLETO con su motivo; firma pendiente | firmado | ausente.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerFirmasMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerFirmasMovil(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT
)
proc: BEGIN
    DECLARE v_msg   VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_num   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_horas INT; DECLARE v_vence DATETIME; DECLARE v_seg INT;
    DECLARE v_inf INT; DECLARE v_comp INT; DECLARE v_firm INT; DECLARE v_resp INT; DECLARE v_ok INT; DECLARE v_listo TINYINT;
    DECLARE v_c_firma DATETIME DEFAULT NULL; DECLARE v_c_gen DATETIME DEFAULT NULL; DECLARE v_c_cierre DATETIME DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_fm_inf;
        DROP TEMPORARY TABLE IF EXISTS tmp_fm_resp;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    CALL SP_ContextoFirmaMovil(p_id_usuario, p_id_os, v_msg, v_num);
    IF v_msg IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_ArmarFirmasOsMovil(p_id_os, v_horas, v_vence, v_seg, v_inf, v_comp, v_firm, v_resp, v_ok, v_listo);
    SELECT c.firmado_en, c.generada_en, c.cerrada_en INTO v_c_firma, v_c_gen, v_c_cierre FROM os_constancia c WHERE c.id_os = p_id_os;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT os.id_os AS id_os, v_num AS numero_os, COALESCE(NULLIF(c.nombre_comercial, ''), c.razon_social) AS cliente,
           v_horas AS plazo_horas, v_seg AS segundos_restantes,
           IF(v_seg IS NOT NULL AND v_seg > 0 AND v_ok < v_resp, 1, 0) AS tacita_activa,
           v_inf AS informes, v_comp AS completos, v_firm AS firmados, v_resp AS responsables, v_ok AS resueltos, v_listo AS listo,
           IF(v_c_firma IS NULL, 0, 1) AS constancia_firmada, IF(v_c_gen IS NULL, 0, 1) AS constancia_generada, IF(v_c_cierre IS NULL, 0, 1) AS cerrado
    FROM   orden_servicio os LEFT JOIN cliente c ON c.id_cliente = os.id_cliente
    WHERE  os.id_os = p_id_os;

    SELECT i.id_os_equipo AS id_os_equipo, i.id_informe AS id_informe, i.numero_informe AS numero_informe, i.equipo AS equipo, i.codigo_equipo AS codigo_equipo,
           i.completo AS completo, i.motivo AS motivo, i.resp_nombre AS responsable, i.resp_cargo AS cargo, i.resp_telefono AS telefono, i.clave AS clave,
           IF(i.completo = 0, 'incompleto', IF(i.firmado = 1, 'firmado', IF(r.ausente = 1, 'ausente', 'pendiente'))) AS firma,
           CONVERT_TZ(r.firmado_en, '+00:00', '-05:00') AS firmado_en
    FROM   tmp_fm_inf i LEFT JOIN tmp_fm_resp r ON r.clave = i.clave
    ORDER BY i.n;

    SELECT r.clave AS clave, r.nombre AS nombre, r.cargo AS cargo, r.telefono AS telefono, r.n_informes AS n_informes, r.informes AS informes,
           IF(r.firmado = 1, 'firmado', IF(r.ausente = 1, 'ausente', 'pendiente')) AS firma, r.modo AS modo, r.resuelto AS resuelto,
           CONVERT_TZ(r.firmado_en, '+00:00', '-05:00') AS firmado_en, r.firmante AS firmante, r.motivo AS motivo, CAST(r.trazos AS CHAR) AS trazos
    FROM   tmp_fm_resp r
    ORDER BY r.nombre;

    DROP TEMPORARY TABLE IF EXISTS tmp_fm_inf;
    DROP TEMPORARY TABLE IF EXISTS tmp_fm_resp;
END$$

DELIMITER ;
