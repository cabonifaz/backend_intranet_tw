-- ============================================================
-- 12_alter_requerimiento_columnas.sql
-- Agrega columnas faltantes a la tabla requerimiento
-- ============================================================

ALTER TABLE requerimiento
    ADD COLUMN fecha_necesidad   DATE       NULL          AFTER descripcion,
    ADD COLUMN notificar_correo  TINYINT(1) NOT NULL DEFAULT 0 AFTER fecha_necesidad,
    ADD COLUMN requiere_visita   TINYINT(1) NOT NULL DEFAULT 0 AFTER notificar_correo,
    ADD COLUMN cliente_deuda     TINYINT(1) NOT NULL DEFAULT 0 AFTER requiere_visita;
