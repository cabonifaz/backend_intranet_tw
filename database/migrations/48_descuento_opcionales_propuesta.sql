-- ============================================================
-- Migración 48 — Descuento específico aplicado a Opcionales (paralelo al HU-11)
--   Hoy la columna `descuento_opcionales` guarda solo el monto fijo (DECIMAL).
--   Para habilitar el modal consistente con la propuesta principal (porcentaje/monto
--   + motivo obligatorio), se agregan:
--     · descuento_opcionales_pct       → % cuando el tipo es 'porcentaje' (NULL si es monto)
--     · id_motivo_descuento_opcionales → FK al catálogo MOTIVO_DESCUENTO (IdMaestro 8)
--   La columna `descuento_opcionales` existente se conserva como el monto final calculado
--   (igual que descuento_monto para la propuesta principal).
--
--   La acción 'propuesta_aplicar_descuento' aplica a ambas secciones (principal y
--   opcionales): mismo permiso, mismo motivo.
--   IDEMPOTENTE.
-- ============================================================

-- descuento_opcionales_pct
SET @col_existe = (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
                   WHERE TABLE_SCHEMA = DATABASE()
                     AND TABLE_NAME   = 'propuesta_comercial'
                     AND COLUMN_NAME  = 'descuento_opcionales_pct');
SET @sql = IF(@col_existe = 0,
              'ALTER TABLE propuesta_comercial ADD COLUMN descuento_opcionales_pct DECIMAL(5,2) NULL AFTER descuento_opcionales',
              'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- id_motivo_descuento_opcionales
SET @col_existe = (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
                   WHERE TABLE_SCHEMA = DATABASE()
                     AND TABLE_NAME   = 'propuesta_comercial'
                     AND COLUMN_NAME  = 'id_motivo_descuento_opcionales');
SET @sql = IF(@col_existe = 0,
              'ALTER TABLE propuesta_comercial ADD COLUMN id_motivo_descuento_opcionales INT NULL AFTER descuento_opcionales_pct',
              'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
