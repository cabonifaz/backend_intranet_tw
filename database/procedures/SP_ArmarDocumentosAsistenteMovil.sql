-- ============================================================
-- SP_ArmarDocumentosAsistenteMovil  (App Mobile HU-19 — apoyo, no es un endpoint)
-- Arma, UNA sola vez, la lista de documentos OFICIALES que el Asistente IA puede consultar para un equipo, en la tabla temporal `tmp_doc_asist`.
-- Lo usan SP_InicioAsistenteMovil, SP_DocumentosAsistenteMovil y SP_EquiposAsistenteMovil; quien lo llame debe terminar con DROP TEMPORARY TABLE IF EXISTS tmp_doc_asist.
--   1. Manual del equipo = suministros.url_manual_pdf del suministro del equipo (equipo_cliente.id_suministro). Siempre aparece si tiene URL; `disponible` = 1
--      solo si es https (el back además la valida con guardas anti-SSRF al descargarla).
--   2. Procedimientos del servicio = los que tienen asociados los conceptos del servicio (os_concepto → suministros de clase servicio:
--      id_primer_procedimiento / id_segundo_procedimiento) aplicados a ese equipo (o generales de la OS, sin filas en os_concepto_equipo).
--      Se resuelven contra procedimiento_metrologico por código (el valor guardado puede venir como "código - título" o como el id) y solo entran los
--      ACTIVOS con PDF aprobado cargado (url_pdf_aprobado = ruta interna del almacenamiento). Si el código tiene varias versiones, la más reciente.
--   Orden: manual primero, luego procedimientos (primer procedimiento antes que el segundo). El back usa los 3 primeros disponibles.
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ArmarDocumentosAsistenteMovil;

DELIMITER $$

CREATE PROCEDURE SP_ArmarDocumentosAsistenteMovil(
    IN p_id_os         BIGINT,
    IN p_id_os_equipo  BIGINT,
    IN p_id_suministro BIGINT
)
BEGIN
    DROP TEMPORARY TABLE IF EXISTS tmp_doc_asist;
    CREATE TEMPORARY TABLE tmp_doc_asist (
        orden        INT NOT NULL AUTO_INCREMENT,
        id_documento VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL,
        tipo         VARCHAR(15)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL,
        titulo       VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL,
        version      VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        entidad      VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        actualizado  DATE NULL,
        ubicacion    VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        disponible   TINYINT NOT NULL DEFAULT 1,
        PRIMARY KEY (orden),
        UNIQUE KEY ux_tmp_doc_asist (id_documento)
    );

    -- 1. Manual del suministro del equipo
    INSERT INTO tmp_doc_asist (id_documento, tipo, titulo, version, entidad, actualizado, ubicacion, disponible)
    SELECT CONCAT('M-', su.id_suministro), 'manual',
           LEFT(CONCAT('Manual ', COALESCE(NULLIF(TRIM(CONCAT_WS(' ', su.marca, su.modelo)), ''), NULLIF(TRIM(su.descripcion), ''), su.codigo)), 300),
           NULL, NULLIF(TRIM(su.marca), ''), DATE(COALESCE(su.modificado_en, su.creado_en)), TRIM(su.url_manual_pdf),
           IF(LOWER(TRIM(su.url_manual_pdf)) LIKE 'https://%', 1, 0)
    FROM   suministros su
    WHERE  su.id_suministro = p_id_suministro AND su.eliminado_en IS NULL AND NULLIF(TRIM(su.url_manual_pdf), '') IS NOT NULL;

    -- 2. PDF aprobado de los procedimientos del servicio (ranking = la versión más reciente de cada código)
    INSERT IGNORE INTO tmp_doc_asist (id_documento, tipo, titulo, version, entidad, actualizado, ubicacion, disponible)
    SELECT CONCAT('P-', x.id_procedimiento), 'procedimiento', LEFT(CONCAT(x.codigo, ' · ', x.descripcion), 300), CONCAT('v', x.version),
           NULLIF(TRIM(x.autor_norma), ''), DATE(COALESCE(x.pdf_subido_en, x.FchMod, x.FchCre)), x.url_pdf_aprobado, 1
    FROM (
        SELECT pm.id_procedimiento, pm.codigo, pm.descripcion, pm.version, pm.autor_norma, pm.pdf_subido_en, pm.FchMod, pm.FchCre, pm.url_pdf_aprobado, r.ord,
               ROW_NUMBER() OVER (PARTITION BY r.ref ORDER BY r.ord, pm.anio DESC, pm.version DESC, pm.id_procedimiento DESC) AS rn
        FROM (
            SELECT TRIM(su2.id_primer_procedimiento) AS ref, 1 AS ord
            FROM   os_concepto oc
            JOIN   suministros su2 ON su2.id_suministro = oc.id_suministro AND su2.eliminado_en IS NULL
            WHERE  oc.id_os = p_id_os AND oc.eliminado_en IS NULL AND NULLIF(TRIM(su2.id_primer_procedimiento), '') IS NOT NULL
              AND  (EXISTS (SELECT 1 FROM os_concepto_equipo oce WHERE oce.id_os_concepto = oc.id AND oce.id_os_equipo = p_id_os_equipo AND oce.eliminado_en IS NULL)
                    OR NOT EXISTS (SELECT 1 FROM os_concepto_equipo z WHERE z.id_os_concepto = oc.id AND z.eliminado_en IS NULL))
            UNION
            SELECT TRIM(su3.id_segundo_procedimiento), 2
            FROM   os_concepto oc
            JOIN   suministros su3 ON su3.id_suministro = oc.id_suministro AND su3.eliminado_en IS NULL
            WHERE  oc.id_os = p_id_os AND oc.eliminado_en IS NULL AND NULLIF(TRIM(su3.id_segundo_procedimiento), '') IS NOT NULL
              AND  (EXISTS (SELECT 1 FROM os_concepto_equipo oce WHERE oce.id_os_concepto = oc.id AND oce.id_os_equipo = p_id_os_equipo AND oce.eliminado_en IS NULL)
                    OR NOT EXISTS (SELECT 1 FROM os_concepto_equipo z WHERE z.id_os_concepto = oc.id AND z.eliminado_en IS NULL))
        ) r
        JOIN procedimiento_metrologico pm
          ON pm.SoftDelete = 0 AND pm.estado = 'activo' AND NULLIF(TRIM(pm.url_pdf_aprobado), '') IS NOT NULL
         AND (pm.codigo = TRIM(SUBSTRING_INDEX(r.ref, ' - ', 1)) OR CAST(pm.id_procedimiento AS CHAR) COLLATE utf8mb4_0900_ai_ci = r.ref)
    ) x
    WHERE x.rn = 1
    ORDER BY x.ord, x.id_procedimiento;
END$$

DELIMITER ;
