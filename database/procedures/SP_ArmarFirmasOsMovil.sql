-- ============================================================
-- SP_ArmarFirmasOsMovil  (App Mobile HU-17 — apoyo, NO es un endpoint)
-- Arma, UNA sola vez, el estado de firmas de los informes técnicos de una OS en dos tablas temporales (quien la llame debe terminar con
-- DROP TEMPORARY TABLE IF EXISTS tmp_fm_inf, tmp_fm_resp):
--   tmp_fm_inf  : un informe por equipo de la OS (os_equipo con equipo): numero_informe, equipo, código, completo (informe GENERADO — HU-15/HU-16 — y con el
--                 responsable "Quién atiende en planta"), motivo del INCOMPLETO, responsable (nombre, cargo, teléfono), clave y si está firmado.
--   tmp_fm_resp : los RESPONSABLES distintos (clave = MD5 de nombre y cargo en minúsculas) de los informes completos, con sus informes, su firma
--                 (dispositivo / fisico / ausente), la hora, los trazos y si está "resuelto" (firmado, o cliente ausente con el plazo de aceptación tácita vencido).
--   Aceptación tácita: plazo = FIRMA_ACEPTACION_TACITA_HORAS (48 por defecto) desde que se generó el PRIMER informe (informe_tecnico.generado_en, UTC);
--   p_segundos = lo que queda (0 si ya venció; NULL si no hay informes generados).
--   Listo (p_listo = 1) = hay informes, TODOS completos y TODOS los responsables resueltos.
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ArmarFirmasOsMovil;

DELIMITER $$

CREATE PROCEDURE SP_ArmarFirmasOsMovil(
    IN  p_id_os    BIGINT,
    OUT p_horas    INT,
    OUT p_vence    DATETIME,
    OUT p_segundos INT,
    OUT p_n_inf    INT,
    OUT p_n_comp   INT,
    OUT p_n_firm   INT,
    OUT p_n_resp   INT,
    OUT p_n_ok     INT,
    OUT p_listo    TINYINT
)
BEGIN
    DECLARE v_primero DATETIME DEFAULT NULL;
    DECLARE v_ahora   DATETIME DEFAULT UTC_TIMESTAMP();

    SELECT IFNULL(MAX(m.Num2), 48) INTO p_horas
    FROM   tabla_maestra m WHERE m.Descripcion = 'PARAMETRO_PROGRAMACION' AND m.String2 = 'FIRMA_ACEPTACION_TACITA_HORAS' AND m.eliminado_en IS NULL;
    IF p_horas < 1 OR p_horas > 720 THEN SET p_horas = 48; END IF;

    DROP TEMPORARY TABLE IF EXISTS tmp_fm_inf;
    CREATE TEMPORARY TABLE tmp_fm_inf (
        n              INT NOT NULL AUTO_INCREMENT,
        id_os_equipo   BIGINT,
        id_equipo      BIGINT,
        id_informe     BIGINT NULL,
        numero_informe VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        equipo         VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        codigo_equipo  VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        completo       TINYINT NOT NULL DEFAULT 0,
        motivo         VARCHAR(160) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        resp_nombre    VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        resp_cargo     VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        resp_telefono  VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        clave          CHAR(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        generado_en    DATETIME NULL,
        firmado        TINYINT NOT NULL DEFAULT 0,
        PRIMARY KEY (n)
    );

    INSERT INTO tmp_fm_inf (id_os_equipo, id_equipo, id_informe, numero_informe, equipo, codigo_equipo, completo, motivo, resp_nombre, resp_cargo, resp_telefono, clave, generado_en)
    SELECT oe.id, oe.id_equipo, it.id_informe, it.numero_informe,
           LEFT(COALESCE(NULLIF(TRIM(su.descripcion), ''), ec.clasificacion), 200), COALESCE(NULLIF(ec.codigo_cliente, ''), ec.codigo_tw),
           IF(it.id_informe IS NOT NULL AND COALESCE(NULLIF(TRIM(it.responsable_nombre), ''), NULLIF(TRIM(cc.nombres), '')) IS NOT NULL, 1, 0),
           CASE WHEN it.id_informe IS NULL THEN 'Falta finalizar el trabajo en el equipo (HU-16)'
                WHEN COALESCE(NULLIF(TRIM(it.responsable_nombre), ''), NULLIF(TRIM(cc.nombres), '')) IS NULL THEN 'Falta «Quién atiende en planta» en la cabecera del informe'
                ELSE NULL END,
           -- «Quién atiende en planta»: lo guardado en la cabecera o, si el técnico no lo tocó, el contacto de la OS (lo mismo que muestra la pestaña Datos)
           COALESCE(NULLIF(TRIM(it.responsable_nombre), ''), NULLIF(TRIM(cc.nombres), '')),
           IF(NULLIF(TRIM(it.responsable_nombre), '') IS NULL, NULLIF(TRIM(cc.cargo), ''), NULLIF(TRIM(it.responsable_cargo), '')),
           IF(NULLIF(TRIM(it.responsable_nombre), '') IS NULL, NULLIF(TRIM(cc.telefono_movil), ''), NULLIF(TRIM(it.responsable_telefono), '')),
           IF(it.id_informe IS NOT NULL AND COALESCE(NULLIF(TRIM(it.responsable_nombre), ''), NULLIF(TRIM(cc.nombres), '')) IS NOT NULL,
              MD5(CONCAT(LOWER(TRIM(COALESCE(NULLIF(TRIM(it.responsable_nombre), ''), cc.nombres))), '|',
                         LOWER(TRIM(IFNULL(IF(NULLIF(TRIM(it.responsable_nombre), '') IS NULL, cc.cargo, it.responsable_cargo), ''))))), NULL),
           it.generado_en
    FROM   os_equipo oe
    JOIN   equipo_cliente ec ON ec.id_equipo = oe.id_equipo
    JOIN   orden_servicio osr ON osr.id_os = oe.id_os
    LEFT JOIN contacto_cliente cc ON cc.id_contacto = osr.id_contacto AND cc.SoftDelete = 0
    LEFT JOIN suministros su ON su.id_suministro = ec.id_suministro
    LEFT JOIN informe_tecnico it ON it.id_informe = (SELECT MAX(x.id_informe) FROM informe_tecnico x
                                                     WHERE x.id_os = oe.id_os AND x.id_equipo = oe.id_equipo AND x.eliminado_en IS NULL AND x.generado_en IS NOT NULL)
    WHERE  oe.id_os = p_id_os AND oe.eliminado_en IS NULL AND oe.id_equipo IS NOT NULL
    ORDER BY oe.id;

    -- Aceptación tácita: desde el primer informe generado
    SELECT MIN(i.generado_en) INTO v_primero FROM tmp_fm_inf i WHERE i.completo = 1;
    SET p_vence = IF(v_primero IS NULL, NULL, v_primero + INTERVAL p_horas HOUR);
    SET p_segundos = IF(p_vence IS NULL, NULL, GREATEST(0, TIMESTAMPDIFF(SECOND, v_ahora, p_vence)));

    DROP TEMPORARY TABLE IF EXISTS tmp_fm_resp;
    CREATE TEMPORARY TABLE tmp_fm_resp (
        clave        CHAR(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL,
        nombre       VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        cargo        VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        telefono     VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        n_informes   INT NOT NULL DEFAULT 0,
        informes     VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        modo         VARCHAR(12)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        firmado      TINYINT NOT NULL DEFAULT 0,
        ausente      TINYINT NOT NULL DEFAULT 0,
        resuelto     TINYINT NOT NULL DEFAULT 0,
        firmado_en   DATETIME NULL,
        firmante     VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        motivo       VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        trazos       JSON NULL,
        PRIMARY KEY (clave)
    );
    INSERT INTO tmp_fm_resp (clave, nombre, cargo, telefono, n_informes, informes)
    SELECT i.clave, MIN(i.resp_nombre), MIN(i.resp_cargo), MIN(i.resp_telefono), COUNT(*),
           LEFT(GROUP_CONCAT(i.numero_informe ORDER BY i.numero_informe SEPARATOR ' · '), 300)
    FROM   tmp_fm_inf i
    WHERE  i.completo = 1
    GROUP BY i.clave;

    UPDATE tmp_fm_resp r
    JOIN   os_firma_responsable f ON f.id_os = p_id_os AND f.clave = r.clave
    SET    r.modo = f.modo, r.firmado = IF(f.modo IN ('dispositivo', 'fisico'), 1, 0), r.ausente = IF(f.modo = 'ausente', 1, 0),
           r.firmado_en = f.firmado_en, r.firmante = f.nombre_firmante, r.motivo = f.motivo, r.trazos = f.trazos;
    UPDATE tmp_fm_resp SET resuelto = IF(firmado = 1 OR (ausente = 1 AND IFNULL(p_segundos, 1) = 0), 1, 0);
    UPDATE tmp_fm_inf i JOIN tmp_fm_resp r ON r.clave = i.clave SET i.firmado = r.firmado;

    SELECT COUNT(*), IFNULL(SUM(completo), 0), IFNULL(SUM(firmado), 0) INTO p_n_inf, p_n_comp, p_n_firm FROM tmp_fm_inf;
    SELECT COUNT(*), IFNULL(SUM(resuelto), 0) INTO p_n_resp, p_n_ok FROM tmp_fm_resp;
    SET p_listo = IF(p_n_inf > 0 AND p_n_comp = p_n_inf AND p_n_resp > 0 AND p_n_ok = p_n_resp, 1, 0);
END$$

DELIMITER ;
