-- ============================================================
-- Migración 113 — Revisión del encargado sobre evidencias forzadas y ensayos con error (HU-52, pestaña Aprobaciones)
--   El Detalle del Servicio en Ruta junta en una sola lista las aprobaciones de la OS: salida, llegada forzada, evidencias forzadas (HU-12) y
--   ensayos guardados con error crítico (HU-10). Las dos primeras ya guardan su resolución (autorizacion_salida_os, llegada_forzada_os); las dos
--   últimas no tenían dónde: se agregan las columnas de la revisión del encargado (quién, cuándo, resultado y comentario).
--   1. evidencia_fotografica: revision_jefe (aprobada | rechazada; NULL = pendiente), revisado_jefe_por, revisado_jefe_en, comentario_jefe.
--   2. informe_tecnico: error_critico_revision (aprobada | rechazada; NULL = pendiente), error_critico_revisado_por, error_critico_revisado_en,
--      error_critico_comentario.
--   No borra ni cambia datos existentes. IDEMPOTENTE. Requiere las migraciones 100 y 101.
-- ============================================================

-- ── 1. evidencia_fotografica ────────────────────────────────────────────────────────────────
SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'evidencia_fotografica' AND COLUMN_NAME = 'revision_jefe'),
    'ALTER TABLE evidencia_fotografica ADD COLUMN revision_jefe ENUM(''aprobada'',''rechazada'') NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'evidencia_fotografica' AND COLUMN_NAME = 'revisado_jefe_por'),
    'ALTER TABLE evidencia_fotografica ADD COLUMN revisado_jefe_por BIGINT NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'evidencia_fotografica' AND COLUMN_NAME = 'revisado_jefe_en'),
    'ALTER TABLE evidencia_fotografica ADD COLUMN revisado_jefe_en DATETIME NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'evidencia_fotografica' AND COLUMN_NAME = 'comentario_jefe'),
    'ALTER TABLE evidencia_fotografica ADD COLUMN comentario_jefe VARCHAR(500) NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- ── 2. informe_tecnico ──────────────────────────────────────────────────────────────────────
SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'informe_tecnico' AND COLUMN_NAME = 'error_critico_revision'),
    'ALTER TABLE informe_tecnico ADD COLUMN error_critico_revision ENUM(''aprobada'',''rechazada'') NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'informe_tecnico' AND COLUMN_NAME = 'error_critico_revisado_por'),
    'ALTER TABLE informe_tecnico ADD COLUMN error_critico_revisado_por BIGINT NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'informe_tecnico' AND COLUMN_NAME = 'error_critico_revisado_en'),
    'ALTER TABLE informe_tecnico ADD COLUMN error_critico_revisado_en DATETIME NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'informe_tecnico' AND COLUMN_NAME = 'error_critico_comentario'),
    'ALTER TABLE informe_tecnico ADD COLUMN error_critico_comentario VARCHAR(500) NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SELECT 'Migración 113 (debe ser 8)' AS verificacion,
       (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'evidencia_fotografica'
           AND COLUMN_NAME IN ('revision_jefe', 'revisado_jefe_por', 'revisado_jefe_en', 'comentario_jefe'))
     + (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'informe_tecnico'
           AND COLUMN_NAME IN ('error_critico_revision', 'error_critico_revisado_por', 'error_critico_revisado_en', 'error_critico_comentario')) AS valor;
