-- ============================================================
-- Migración 27 — Versión idempotente (safe re-run)
-- Mismo contenido que 27_usuarios_area_sede_limpieza.sql pero
-- envuelto en checks de INFORMATION_SCHEMA. Se puede correr
-- varias veces sin error.
-- ============================================================

-- ── 6) Nueva columna area ────────────────────────────────────────────────────
SET @sql = IF(
    (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'usuario' AND COLUMN_NAME = 'area') = 0,
    'ALTER TABLE usuario ADD COLUMN area VARCHAR(60) NULL AFTER cargo',
    'SELECT ''area ya existe'' AS info'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- Backfill area desde area_comercial (solo si area_comercial aún existe)
SET @hay_area_comercial = (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'usuario' AND COLUMN_NAME = 'area_comercial');

SET @sql = IF(@hay_area_comercial = 1,
    'UPDATE usuario SET area = CASE
            WHEN LOWER(area_comercial) LIKE ''%comercial%''    THEN ''comercial''
            WHEN LOWER(area_comercial) LIKE ''%metrolog%''     THEN ''metrologia''
            WHEN LOWER(area_comercial) LIKE ''%operacion%''    THEN ''operaciones''
            WHEN LOWER(area_comercial) LIKE ''%administra%''   THEN ''administracion''
            WHEN LOWER(area_comercial) LIKE ''%gerencia%''     THEN ''gerencia''
            WHEN LOWER(area_comercial) LIKE ''%ssoma%''        THEN ''ssoma''
            WHEN LOWER(area_comercial) IN (''ti'', ''sistemas'') THEN ''ti''
            ELSE NULL
        END
    WHERE area_comercial IS NOT NULL AND area IS NULL',
    'SELECT ''area_comercial ya se dropeo, backfill omitido'' AS info'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- ── 2) base_operativa → sede_operativa ───────────────────────────────────────
SET @hay_base_operativa = (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'usuario' AND COLUMN_NAME = 'base_operativa');

SET @sql = IF(@hay_base_operativa = 1,
    'ALTER TABLE usuario RENAME COLUMN base_operativa TO sede_operativa',
    'SELECT ''base_operativa ya se renombro'' AS info'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- Normaliza valores de sede_operativa al código del catálogo
UPDATE usuario SET sede_operativa = CASE
        WHEN LOWER(sede_operativa) LIKE '%lima%'     THEN 'lima_central'
        WHEN LOWER(sede_operativa) LIKE '%arequipa%' THEN 'arequipa'
        WHEN sede_operativa IN ('lima_central', 'arequipa') THEN sede_operativa
        ELSE NULL
    END
WHERE sede_operativa IS NOT NULL;

-- ── 3) Junction de sedes autorizadas ─────────────────────────────────────────
DROP TABLE IF EXISTS usuario_sede_autorizada;

-- ── 4) y 5) Columnas que ya no se usan ───────────────────────────────────────
SET @sql = IF(
    (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'usuario' AND COLUMN_NAME = 'area_comercial') = 1,
    'ALTER TABLE usuario DROP COLUMN area_comercial',
    'SELECT ''area_comercial ya se dropeo'' AS info'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @sql = IF(
    (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'usuario' AND COLUMN_NAME = 'id_area') = 1,
    'ALTER TABLE usuario DROP COLUMN id_area',
    'SELECT ''id_area ya se dropeo'' AS info'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @sql = IF(
    (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'usuario' AND COLUMN_NAME = 'id_tipo_doc_identidad') = 1,
    'ALTER TABLE usuario DROP COLUMN id_tipo_doc_identidad',
    'SELECT ''id_tipo_doc_identidad ya se dropeo'' AS info'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @sql = IF(
    (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'usuario' AND COLUMN_NAME = 'id_persona_contacto') = 1,
    'ALTER TABLE usuario DROP COLUMN id_persona_contacto',
    'SELECT ''id_persona_contacto ya se dropeo'' AS info'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- ── Catálogos tabla_maestra (reemplazo completo por IdMaestro) ───────────────
DELETE FROM tabla_maestra WHERE IdMaestro IN (69, 79);

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2, String3) VALUES
(1, 69, 'SEDE_OPERATIVA_TW', 1, 'Lima Central', 'lima_central', 'Lima'),
(1, 69, 'SEDE_OPERATIVA_TW', 2, 'Arequipa',     'arequipa',     'Arequipa');

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2) VALUES
(1, 79, 'AREA_USUARIO', 1, 'Comercial',      'comercial'),
(1, 79, 'AREA_USUARIO', 2, 'Metrología',     'metrologia'),
(1, 79, 'AREA_USUARIO', 3, 'Operaciones',    'operaciones'),
(1, 79, 'AREA_USUARIO', 4, 'Administración', 'administracion'),
(1, 79, 'AREA_USUARIO', 5, 'Gerencia',       'gerencia'),
(1, 79, 'AREA_USUARIO', 6, 'SSOMA',          'ssoma'),
(1, 79, 'AREA_USUARIO', 7, 'TI',             'ti');
