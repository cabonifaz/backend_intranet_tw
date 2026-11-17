-- ============================================================
-- Migración 118 — Alertas y apoyo en campo desde la app móvil (App Mobile HU-32)
--   incidencia_operativa (la misma que lee la bandeja de Seguimiento Operativo): + evidencia_url (foto de la incidencia, solo cámara)
--   y escalada_en (cuándo el jefe la escaló). No cambia datos existentes. IDEMPOTENTE.
-- ============================================================

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'incidencia_operativa' AND COLUMN_NAME = 'evidencia_url'),
    'ALTER TABLE incidencia_operativa ADD COLUMN evidencia_url VARCHAR(500) NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'incidencia_operativa' AND COLUMN_NAME = 'escalada_en'),
    'ALTER TABLE incidencia_operativa ADD COLUMN escalada_en DATETIME NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;
