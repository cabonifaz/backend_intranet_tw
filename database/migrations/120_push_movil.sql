-- ============================================================
-- Migración 120 — Notificaciones push de la app móvil
--   Tabla dispositivo_push_movil: el token de Expo Push de cada teléfono donde un usuario inició sesión en la app.
--   Con eso la API envía cada notificación nueva (tabla `notificacion`) a la bandeja de notificaciones del teléfono,
--   aunque la app esté cerrada. Un token pertenece a UN usuario a la vez (si otro usuario inicia sesión en el mismo teléfono,
--   el token pasa a él: SP_RegistrarDispositivoPushMovil). Soft delete + auditoría. Sin FK. IDEMPOTENTE.
-- ============================================================
CREATE TABLE IF NOT EXISTS dispositivo_push_movil (
    id_dispositivo_push BIGINT       NOT NULL AUTO_INCREMENT,
    id_usuario          BIGINT       NOT NULL,
    id_dispositivo      VARCHAR(100) NOT NULL,
    token               VARCHAR(255) NOT NULL,
    plataforma          VARCHAR(10)  NOT NULL DEFAULT 'android',
    ultimo_registro     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    -- AUDITORÍA
    creado_en           DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por          BIGINT       NULL,
    modificado_en       DATETIME     NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por      BIGINT       NULL,
    eliminado_en        DATETIME     NULL,
    eliminado_por       BIGINT       NULL,
    PRIMARY KEY (id_dispositivo_push)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'dispositivo_push_movil' AND INDEX_NAME = 'ix_dispositivo_push_usuario'),
    'ALTER TABLE dispositivo_push_movil ADD KEY ix_dispositivo_push_usuario (id_usuario, eliminado_en)', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'dispositivo_push_movil' AND INDEX_NAME = 'ix_dispositivo_push_token'),
    'ALTER TABLE dispositivo_push_movil ADD KEY ix_dispositivo_push_token (token)', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SELECT 'Migración 120 (debe ser 1)' AS verificacion,
       (SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'dispositivo_push_movil') AS valor;
