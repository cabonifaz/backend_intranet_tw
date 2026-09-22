-- ============================================================
-- SEED 001 — Usuario administrador de prueba
-- Contraseña: TW@Admin2026
-- ============================================================

INSERT INTO usuario (nombre, apellido, correo, password_hash, rol_sistema, canal_acceso, estado, creado_en, modificado_en)
VALUES (
  'Admin',
  'TW',
  'admin@totalweight.com',
  '$2a$12$cRdOm7WJTggA8DtwkggR9uoX2k9g/JfSEQ5Do.EkttVKp5rcLcmje',
  'admin',
  'intranet',
  'activo',
  NOW(),
  NOW()
);
