-- ============================================================
-- Migración 84 — Observaciones del cliente Sprint 3 y 4 (31/10): Visto Bueno
--   "Solicitar corrección" ya no exige fecha límite: propuesta_correccion.fecha_limite pasa a NULL.
--   IDEMPOTENTE. Se puede re-ejecutar.
-- ============================================================
SET @sql := IF(EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE()
                         AND TABLE_NAME = 'propuesta_correccion' AND COLUMN_NAME = 'fecha_limite' AND IS_NULLABLE = 'NO'),
    'ALTER TABLE propuesta_correccion MODIFY COLUMN fecha_limite DATETIME NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;
