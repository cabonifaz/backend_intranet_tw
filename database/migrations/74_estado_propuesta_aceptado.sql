-- ============================================================
-- Migración 74 — Estado 'aceptado' de la propuesta (aceptación del cliente)
--   Hasta ahora la aceptación del cliente solo quedaba en el seguimiento (cerrado_aceptacion) y la
--   propuesta seguía en 'enviado'. Desde esta migración:
--     aprobado = visto bueno interno aprobado (lista para enviar)
--     aceptado = el cliente aceptó la propuesta (habilita el registro de la orden de compra)
--   1. propuesta_comercial.estado acepta 'aceptado'
--   2. Las propuestas con el seguimiento cerrado con aceptación que siguen en 'enviado' pasan a 'aceptado'
--      (se registra el cambio en auditoria_evento)
--   SP_CerrarSeguimiento pasa la propuesta a 'aceptado' al cerrar con aceptación.
--
--   IDEMPOTENTE. Se puede re-ejecutar.
-- ============================================================

-- 1. ENUM con 'aceptado'
SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'propuesta_comercial'
                             AND COLUMN_NAME = 'estado' AND COLUMN_TYPE LIKE '%''aceptado''%'),
    'ALTER TABLE propuesta_comercial MODIFY COLUMN estado ENUM(''borrador'',''pendiente_vb'',''enviado'',''aprobado'',''aceptado'',''rechazado'',''anulado'',''vencido'',''pendiente_revocacion'',''revocada'') NOT NULL DEFAULT ''borrador''',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- 2. Propuestas ya aceptadas por el cliente
DROP TEMPORARY TABLE IF EXISTS tmp_m74_aceptadas;
CREATE TEMPORARY TABLE tmp_m74_aceptadas AS
SELECT DISTINCT p.id_propuesta
FROM propuesta_comercial p
JOIN seguimiento_comercial s ON s.id_propuesta = p.id_propuesta AND s.eliminado_en IS NULL
                            AND s.estado = 'cerrado_aceptacion'
WHERE p.eliminado_en IS NULL AND p.estado = 'enviado';

UPDATE propuesta_comercial p
JOIN tmp_m74_aceptadas t ON t.id_propuesta = p.id_propuesta
SET p.estado = 'aceptado';

INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en)
SELECT 'propuesta', t.id_propuesta, 'cambio_estado', 'enviado', 'aceptado',
       'Migración 74: la propuesta aceptada por el cliente pasa al estado Aceptada.', NULL, NOW()
FROM tmp_m74_aceptadas t;

DROP TEMPORARY TABLE IF EXISTS tmp_m74_aceptadas;
