-- ============================================================
-- Migración 75 — Acceso a la App Móvil de campo (App Mobile HU-01)
--   1. usuario.nombre_usuario ... usuario de acceso a la app (lo asigna el jefe;
--                                 se habilita con canal_acceso 'movil' o 'todos').
--                                 La app NO acepta correo: solo este usuario.
--   2. sesion_usuario ........... se empieza a usar para las sesiones de la app
--                                 (canal 2 = App móvil de campo, catálogo CANAL_ACCESO).
--                                 Se agrega el id del dispositivo: 1 sesión = 1 equipo.
--   La sesión de la intranet (usuario.sesion_token) NO cambia: entrar a la app
--   no cierra la intranet ni al revés.
--   IDEMPOTENTE. Ejecutar junto con los SPs de este mismo paquete.
-- ============================================================

-- ── 1. USUARIO: nombre de usuario para la app ────────────────
SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'usuario' AND COLUMN_NAME = 'nombre_usuario'),
    'ALTER TABLE usuario ADD COLUMN nombre_usuario VARCHAR(50) NULL AFTER correo', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.STATISTICS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'usuario' AND INDEX_NAME = 'ix_usuario_nombre_usuario'),
    'ALTER TABLE usuario ADD INDEX ix_usuario_nombre_usuario (nombre_usuario)', 'SELECT 1');
-- Sin UNIQUE (convención del proyecto por el borrado lógico): SP_AsignarAccesoMovil
-- valida que el usuario no esté tomado por otro registro vigente.
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- ── 2. SESION_USUARIO: dispositivo de la sesión ──────────────
SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sesion_usuario' AND COLUMN_NAME = 'id_dispositivo'),
    'ALTER TABLE sesion_usuario ADD COLUMN id_dispositivo VARCHAR(100) NULL AFTER id_canal_acceso', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sesion_usuario' AND COLUMN_NAME = 'nombre_dispositivo'),
    'ALTER TABLE sesion_usuario ADD COLUMN nombre_dispositivo VARCHAR(150) NULL AFTER id_dispositivo', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.STATISTICS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sesion_usuario' AND INDEX_NAME = 'ix_sesion_usuario_activa'),
    'ALTER TABLE sesion_usuario ADD INDEX ix_sesion_usuario_activa (id_usuario, id_canal_acceso, activo)', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.STATISTICS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sesion_usuario' AND INDEX_NAME = 'ix_sesion_usuario_token'),
    'ALTER TABLE sesion_usuario ADD INDEX ix_sesion_usuario_token (token_jti)', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- ── Verificación ─────────────────────────────────────────────
SELECT COLUMN_NAME, COLUMN_TYPE, IS_NULLABLE
FROM   information_schema.COLUMNS
WHERE  TABLE_SCHEMA = DATABASE()
  AND  ((TABLE_NAME = 'usuario' AND COLUMN_NAME = 'nombre_usuario')
     OR (TABLE_NAME = 'sesion_usuario' AND COLUMN_NAME IN ('id_dispositivo', 'nombre_dispositivo')));
