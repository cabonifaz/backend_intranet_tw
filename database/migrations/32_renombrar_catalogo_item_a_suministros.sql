-- ============================================================
-- Migración 32 — catalogo_item → suministros
--   · Renombra la tabla a suministros
--   · Renombra la PK id_catalogo_item → id_suministro
--   · Elimina las columnas en desuso id_tipo_servicio e id_tipo_equipo
--   El resto de columnas no cambia.
--   IDEMPOTENTE: se puede ejecutar aunque una parte ya se haya aplicado.
--   Ejecutar junto con los SPs actualizados de este mismo script y con
--   SP_ObtenerEquipoClientePorId actualizado.
-- ============================================================

-- 1. Renombrar la tabla (si todavía se llama catalogo_item)
SET @sql := IF(
    EXISTS (SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'catalogo_item'),
    'RENAME TABLE catalogo_item TO suministros',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- 2. Quitar llaves foráneas que pudieran colgar de las columnas a eliminar
SET @fks := (
    SELECT GROUP_CONCAT(CONCAT('DROP FOREIGN KEY `', CONSTRAINT_NAME, '`'))
    FROM information_schema.KEY_COLUMN_USAGE
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME   = 'suministros'
      AND COLUMN_NAME IN ('id_tipo_servicio', 'id_tipo_equipo')
      AND REFERENCED_TABLE_NAME IS NOT NULL
);
SET @sql := IF(@fks IS NULL, 'SELECT 1', CONCAT('ALTER TABLE suministros ', @fks));
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- 3. Eliminar id_tipo_servicio e id_tipo_equipo (si existen)
SET @sql := IF(
    EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'suministros' AND COLUMN_NAME = 'id_tipo_servicio'),
    'ALTER TABLE suministros DROP COLUMN id_tipo_servicio',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(
    EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'suministros' AND COLUMN_NAME = 'id_tipo_equipo'),
    'ALTER TABLE suministros DROP COLUMN id_tipo_equipo',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- 4. Renombrar la PK id_catalogo_item → id_suministro (si todavía tiene el nombre antiguo).
--    Las llaves foráneas de otras tablas que la referencian se actualizan solas.
SET @sql := IF(
    EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'suministros' AND COLUMN_NAME = 'id_catalogo_item'),
    'ALTER TABLE suministros RENAME COLUMN id_catalogo_item TO id_suministro',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;
