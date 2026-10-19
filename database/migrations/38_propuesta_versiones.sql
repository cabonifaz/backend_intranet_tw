-- ============================================================
-- Migración 38 — HU-10: Edición y Gestión de Versiones de Propuesta
--   1. propuesta_comercial.descripcion_cambios: descripción breve de lo
--      que cambia respecto a la versión anterior (obligatoria al crear
--      una nueva versión, junto con id_motivo_nueva_version).
--   2. visto_bueno.estado admite 'cancelado': si se crea una nueva
--      versión mientras la anterior espera VB, esa solicitud se cancela.
--   IDEMPOTENTE.
-- ============================================================

-- 1. descripcion_cambios
SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE()
                             AND TABLE_NAME   = 'propuesta_comercial'
                             AND COLUMN_NAME  = 'descripcion_cambios'),
    'ALTER TABLE propuesta_comercial ADD COLUMN descripcion_cambios VARCHAR(500) NULL AFTER id_motivo_nueva_version',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- 2. visto_bueno: estado 'cancelado'
ALTER TABLE visto_bueno
    MODIFY COLUMN estado ENUM('pendiente','aprobado','rechazado','reasignado','cancelado')
                  NOT NULL DEFAULT 'pendiente';
