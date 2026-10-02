-- ============================================================
-- 13_alter_requerimiento_id_sede.sql
-- Agrega id_sede a la tabla requerimiento
-- ============================================================

ALTER TABLE requerimiento
    ADD COLUMN id_sede BIGINT NULL AFTER id_contacto;
