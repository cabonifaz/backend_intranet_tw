-- ============================================================
-- Migración 99 — Trabajo en el equipo y Variables ambientales desde la app móvil (App Mobile HU-08 / HU-09)
--   variable_ambiental era solo de la Orden de Metrología (id_om NOT NULL). La app registra las condiciones del entorno por EQUIPO de una OS
--   (servicio técnico) o de una OM (metrología), así que:
--     - id_om pasa a ser opcional;
--     - nuevas columnas id_os, id_equipo (equipo_cliente) y procedencia ("N.I" = no indicado, por defecto);
--     - índice por (id_os, id_equipo).
--   La fecha y la hora (registrado_en, UTC) las pone el servidor. Una sola fila vigente por OS + equipo: guardar otra vez la actualiza
--   (el cambio queda en auditoria_evento).
--   No borra ni cambia datos existentes. IDEMPOTENTE. Requiere las migraciones 80 y 98.
-- ============================================================

ALTER TABLE variable_ambiental MODIFY COLUMN id_om BIGINT NULL;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'variable_ambiental' AND COLUMN_NAME = 'id_os'),
    'ALTER TABLE variable_ambiental ADD COLUMN id_os BIGINT NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'variable_ambiental' AND COLUMN_NAME = 'id_equipo'),
    'ALTER TABLE variable_ambiental ADD COLUMN id_equipo BIGINT NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'variable_ambiental' AND COLUMN_NAME = 'procedencia'),
    'ALTER TABLE variable_ambiental ADD COLUMN procedencia VARCHAR(100) NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'variable_ambiental' AND INDEX_NAME = 'ix_variable_ambiental_os_equipo'),
    'ALTER TABLE variable_ambiental ADD KEY ix_variable_ambiental_os_equipo (id_os, id_equipo)', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SELECT 'Migración 99 (debe ser 4)' AS verificacion,
       (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'variable_ambiental'
           AND COLUMN_NAME IN ('id_os', 'id_equipo', 'procedencia'))
     + (SELECT COUNT(*) FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'variable_ambiental'
           AND INDEX_NAME = 'ix_variable_ambiental_os_equipo' AND SEQ_IN_INDEX = 1) AS valor;
