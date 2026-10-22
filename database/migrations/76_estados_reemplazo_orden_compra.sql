-- ============================================================
-- Migración 76 — Estados y reemplazo de la Orden de Compra (ajustes del front, 2026-10-21)
--   1. orden_compra.estado:
--        autogenerada         OC-AUTO provisional, sin PDF (antes 'recibida')
--        validada             todas las propuestas vinculadas validadas (facturable)
--        validada_parcial     varias propuestas: alguna validada y otra observada o pendiente
--        observada            diferencias menores aceptadas por TW ("Guardar con observaciones"), facturable con nota
--        pendiente_reemplazo  diferencias críticas: se pidió al cliente la OC corregida ("Solicitar corrección")
--        anulada              anulada permanentemente
--   2. Las OC observadas con corrección del cliente pendiente pasan a 'pendiente_reemplazo'.
--   3. Las OC autogeneradas ya reemplazadas quedan dadas de baja (eliminado_en): la OC del cliente las sustituye
--      y no tienen PDF que conservar. Las OC reemplazadas con PDF se conservan (reemplazada_por) para auditoría.
--
--   IDEMPOTENTE. Se puede re-ejecutar.
-- ============================================================

-- 1. ENUM: primero el conjunto con los valores viejos y nuevos, luego solo los nuevos
SET @sql := IF(EXISTS (SELECT 1 FROM information_schema.COLUMNS
                       WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'orden_compra'
                         AND COLUMN_NAME = 'estado' AND COLUMN_TYPE LIKE '%''recibida''%'),
    'ALTER TABLE orden_compra MODIFY COLUMN estado ENUM(''recibida'',''autogenerada'',''validada'',''validada_parcial'',''observada'',''pendiente_reemplazo'',''anulada'') NOT NULL',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

UPDATE orden_compra SET estado = 'autogenerada' WHERE estado = 'recibida';

-- 2. Corrección del cliente pendiente (sin vinculaciones validadas) → pendiente_reemplazo
UPDATE orden_compra oc
SET oc.estado = 'pendiente_reemplazo'
WHERE oc.eliminado_en IS NULL AND oc.estado = 'observada'
  AND EXISTS (SELECT 1 FROM oc_propuesta op
              WHERE op.id_oc = oc.id_oc AND op.eliminado_en IS NULL
                AND op.estado_validacion = 'observada' AND op.tipo_observacion = 'correccion_cliente');

SET @sql := IF(EXISTS (SELECT 1 FROM information_schema.COLUMNS
                       WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'orden_compra'
                         AND COLUMN_NAME = 'estado' AND COLUMN_TYPE LIKE '%''recibida''%'),
    'ALTER TABLE orden_compra MODIFY COLUMN estado ENUM(''autogenerada'',''validada'',''validada_parcial'',''observada'',''pendiente_reemplazo'',''anulada'') NOT NULL',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- 3. OC autogeneradas ya reemplazadas: baja lógica
UPDATE orden_compra
SET eliminado_en = IFNULL(fecha_reemplazo, NOW())
WHERE es_autogenerada = 1 AND reemplazada_por IS NOT NULL AND eliminado_en IS NULL;
