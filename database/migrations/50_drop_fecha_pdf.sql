-- ============================================================
-- Migración 50 — Elimina propuesta_comercial.fecha_pdf.
--   El PDF se regenera on-the-fly con QuestPDF cada vez que se pide la vista previa;
--   nunca se persistió, así que la columna siempre quedaba NULL. La validación
--   "PDF generado" se retiró del flujo de envío a VB (SP_EnviarVistoBuenoPropuesta).
-- IDEMPOTENTE.
-- ============================================================

SET @existe = (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
               WHERE TABLE_SCHEMA = DATABASE()
                 AND TABLE_NAME   = 'propuesta_comercial'
                 AND COLUMN_NAME  = 'fecha_pdf');
SET @sql = IF(@existe > 0,
              'ALTER TABLE propuesta_comercial DROP COLUMN fecha_pdf',
              'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
