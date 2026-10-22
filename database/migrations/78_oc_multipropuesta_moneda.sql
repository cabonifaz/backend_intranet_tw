-- ============================================================
-- Migración 78 — Órdenes de compra multi-propuesta (ajustes de Jazir, tickets A a E)
--   1. orden_compra.tipo_cambio: soles por 1 unidad de la moneda extranjera (formato SUNAT, ej. 3.7500 PEN por USD).
--      Lo indica el comercial cuando la OC cubre propuestas en otra moneda que la suya.
--   2. oc_propuesta.monto_cubierto: lo que la OC cubre de la propuesta, en la moneda de la PROPUESTA (monto_asignado
--      sigue en la moneda de la OC). NULL = misma moneda (cubre monto_asignado). Lo usa el saldo de la propuesta
--      (FN_SaldoPropuestaOc).
--
--   IDEMPOTENTE. Se puede re-ejecutar.
-- ============================================================

-- ── 1. Tipo de cambio de la OC ───────────────────────────────────────────────
SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'orden_compra' AND COLUMN_NAME = 'tipo_cambio'),
    'ALTER TABLE orden_compra ADD COLUMN tipo_cambio DECIMAL(12,6) NULL AFTER monto_total',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- ── 2. Monto cubierto en la moneda de la propuesta ───────────────────────────
SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'oc_propuesta' AND COLUMN_NAME = 'monto_cubierto'),
    'ALTER TABLE oc_propuesta ADD COLUMN monto_cubierto DECIMAL(14,2) NULL AFTER monto_asignado',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;
