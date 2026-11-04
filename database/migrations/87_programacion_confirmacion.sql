-- ============================================================
-- Migración 87 — Detalle de la Programación y registro de la confirmación con el cliente (HU-37, Sprint 5)
--   1. programacion_confirmacion ... respuesta del cliente a una programación, registrada por Operaciones tras coordinar FUERA del
--                                    sistema (teléfono, correo, WhatsApp, presencial). El sistema no envía nada al cliente.
--                                    canal: correo | whatsapp | llamada | presencial · resultado: acepto | pidio_reprogramar | cancelo
--                                    Una programación puede tener varias respuestas (queda el historial completo).
--   2. Índice de auditoria_evento (entidad_tipo, id_entidad, registrado_en): el historial (timeline) del detalle lee los eventos
--      de la programación y de su orden de servicio.
--   No borra ni cambia datos existentes. IDEMPOTENTE (se puede volver a ejecutar). Ejecutar junto con los SPs del paquete.
--   Requiere la migración 86 (tabla programacion).
-- ============================================================

-- ── 1. Respuestas del cliente ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS programacion_confirmacion (
    id                     BIGINT          NOT NULL AUTO_INCREMENT,
    id_programacion        BIGINT          NOT NULL,
    canal                  ENUM('correo','whatsapp','llamada','presencial') NOT NULL,
    resultado              ENUM('acepto','pidio_reprogramar','cancelo')     NOT NULL,
    comentario             VARCHAR(300)    NULL,
    id_registrado_por      BIGINT          NOT NULL,
    fecha_registro         DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    -- AUDITORÍA
    creado_en              DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por             BIGINT          NULL,
    modificado_en          DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por         BIGINT          NULL,
    eliminado_en           DATETIME        NULL,
    eliminado_por          BIGINT          NULL,
    PRIMARY KEY (id),
    KEY ix_programacion_confirmacion_prog (id_programacion, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ── 2. Índice del historial ───────────────────────────────────────────────────
SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.STATISTICS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'auditoria_evento' AND INDEX_NAME = 'ix_auditoria_evento_entidad'),
    'ALTER TABLE auditoria_evento ADD KEY ix_auditoria_evento_entidad (entidad_tipo, id_entidad, registrado_en)', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- ── Verificación ─────────────────────────────────────────────────────────────
SELECT 'Migración 87 (debe ser 2)' AS verificacion,
       (SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'programacion_confirmacion')
     + (SELECT COUNT(DISTINCT INDEX_NAME) FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = 'auditoria_evento' AND INDEX_NAME = 'ix_auditoria_evento_entidad') AS valor;
