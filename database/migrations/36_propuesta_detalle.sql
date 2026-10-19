-- ============================================================
-- Migración 36 — HU-09: Detalle y Vista Previa de Propuesta
--   fecha_pdf: momento en que se generó la vista previa PDF de la
--   versión. Lo usa el workflow del detalle (paso "Preparación") y
--   lo usará HU-12 para validar "PDF generado" antes del VB.
--   IDEMPOTENTE.
-- ============================================================

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE()
                             AND TABLE_NAME   = 'propuesta_comercial'
                             AND COLUMN_NAME  = 'fecha_pdf'),
    'ALTER TABLE propuesta_comercial ADD COLUMN fecha_pdf DATETIME NULL AFTER url_pdf',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;
