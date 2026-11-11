-- ============================================================
-- Migración 100 — Ejecución de Ensayos y Calibración desde la app móvil (App Mobile HU-10)
--   El técnico registra las lecturas de pesaje y excentricidad del equipo; la app envía solo la carga (L) y la indicación (I) y el servidor calcula
--   el error (E = I − L), el EMP (error máximo permitido según la clase y e) y la conformidad. Se guarda en informe_ensayo (migración 93), que es lo que
--   luego lee la Cabecera del informe.
--   1. informe_ensayo: + grupo (excentricidad: número de la carga de prueba) y critico (la lectura supera el EMP).
--   2. informe_tecnico: + forma_plato (rectangular | circular | triangular, define las posiciones de excentricidad), error_critico_motivo (motivo con el
--      que el técnico guardó "de todas formas" un ensayo con error crítico) y ensayos_finalizado_en (cuándo finalizó la etapa).
--   No borra ni cambia datos existentes. IDEMPOTENTE. Requiere las migraciones 93, 98 y 99.
-- ============================================================

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'informe_ensayo' AND COLUMN_NAME = 'grupo'),
    'ALTER TABLE informe_ensayo ADD COLUMN grupo INT NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'informe_ensayo' AND COLUMN_NAME = 'critico'),
    'ALTER TABLE informe_ensayo ADD COLUMN critico TINYINT(1) NOT NULL DEFAULT 0', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'informe_tecnico' AND COLUMN_NAME = 'forma_plato'),
    'ALTER TABLE informe_tecnico ADD COLUMN forma_plato VARCHAR(20) NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'informe_tecnico' AND COLUMN_NAME = 'error_critico_motivo'),
    'ALTER TABLE informe_tecnico ADD COLUMN error_critico_motivo VARCHAR(300) NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'informe_tecnico' AND COLUMN_NAME = 'ensayos_finalizado_en'),
    'ALTER TABLE informe_tecnico ADD COLUMN ensayos_finalizado_en DATETIME NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SELECT 'Migración 100 (debe ser 5)' AS verificacion,
       (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'informe_ensayo' AND COLUMN_NAME IN ('grupo', 'critico'))
     + (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'informe_tecnico'
           AND COLUMN_NAME IN ('forma_plato', 'error_critico_motivo', 'ensayos_finalizado_en')) AS valor;
