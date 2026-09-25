-- ============================================================
-- 14_alter_usuario_sesion_token.sql
-- Agrega columna sesion_token a la tabla usuario para controlar
-- sesión única por usuario.
-- ============================================================

ALTER TABLE usuario
    ADD COLUMN sesion_token VARCHAR(36) NULL AFTER estado;
