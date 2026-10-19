-- ============================================================
-- Migración 40 — Tickets #4299 (revisado → bloqueado) y soporte de #4303 / #4290
--   Equipos: se registra QUIÉN y CUÁNDO bloqueó los datos para certificación.
--   (bloqueado_para_servicios = "datos validados por Metrología para el certificado")
--   IDEMPOTENTE. Ejecutar junto con los SPs de este mismo paquete.
-- ============================================================
SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'equipo_cliente' AND COLUMN_NAME = 'usuario_bloqueo'),
    'ALTER TABLE equipo_cliente ADD COLUMN usuario_bloqueo VARCHAR(150) NULL AFTER bloqueado_para_servicios', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'equipo_cliente' AND COLUMN_NAME = 'fecha_bloqueo'),
    'ALTER TABLE equipo_cliente ADD COLUMN fecha_bloqueo DATETIME NULL AFTER usuario_bloqueo', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- Directorio: índice para buscar por nombre (consulta de todo el personal)
SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'usuario' AND INDEX_NAME = 'ix_usuario_directorio'),
    'CREATE INDEX ix_usuario_directorio ON usuario (estado, apellido, nombre)', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- ── #4301: excepciones para la validación de permisos en el back ─────────
-- Metrología guarda equipos del cliente (revisar y bloquear datos para certificación, #4299).
INSERT IGNORE INTO permiso_area_rol (area, rol, modulo, acceso, UsuMod, FchMod) VALUES
('metrologia', 'usuario',       'maestro_equipos_cliente', 'editar',     'migracion_40', NOW()),
('metrologia', 'supervisor',    'maestro_equipos_cliente', 'editar',     'migracion_40', NOW()),
('metrologia', 'administrador', 'maestro_equipos_cliente', 'supervisar', 'migracion_40', NOW());
