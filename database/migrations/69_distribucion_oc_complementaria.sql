-- ============================================================
-- Migración 69 — HU-27 Gestión Financiera: Distribución de Saldos y OC Complementaria
--   1. orden_compra.tipo_oc (principal | complementaria) e id_oc_origen (OC que complementa)
--   2. Acción oc_distribuir (nivel 3 = supervisar, módulo propuestas): jefe y administrador comercial
--      (y admins de Gerencia y TI). La OC complementaria se registra con oc_registrar (HU-22).
--   3. oc_propuesta pasa a ser la fuente de la cobertura: cada OC aplica un monto a cada propuesta.
--      Se completan las filas de las OC antiguas que no tengan (monto asignado = menor entre OC y propuesta).
--
--   Cobertura de una propuesta = suma de lo asignado por todas sus OC no anuladas.
--   Saldo disponible de una OC  = monto de la OC - suma de lo que ya asignó.
--
--   IDEMPOTENTE. Se puede re-ejecutar.
-- ============================================================

-- 1. Tipo de OC y OC de origen
SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'orden_compra' AND COLUMN_NAME = 'tipo_oc'),
    'ALTER TABLE orden_compra ADD COLUMN tipo_oc ENUM(''principal'',''complementaria'') NOT NULL DEFAULT ''principal'' AFTER id_propuesta',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'orden_compra' AND COLUMN_NAME = 'id_oc_origen'),
    'ALTER TABLE orden_compra ADD COLUMN id_oc_origen BIGINT NULL AFTER tipo_oc',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- 2. Acción
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2, String3)
SELECT 1, 88, 'ACCION_SISTEMA', 3, 'Distribuir el saldo de una orden de compra entre propuestas', 'oc_distribuir', 'propuestas'
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra WHERE IdMaestro = 88 AND IdEmpresa = 1 AND String2 = 'oc_distribuir');

-- 3. Filas de oc_propuesta para las OC antiguas que no tengan
INSERT INTO oc_propuesta (id_oc, id_propuesta, monto_asignado, creado_por)
SELECT oc.id_oc, oc.id_propuesta,
       IF(p.id_moneda <> oc.id_moneda, oc.monto_total, LEAST(oc.monto_total, p.total)), oc.creado_por
FROM orden_compra oc
JOIN propuesta_comercial p ON p.id_propuesta = oc.id_propuesta
WHERE oc.eliminado_en IS NULL AND oc.id_propuesta IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM oc_propuesta op WHERE op.id_oc = oc.id_oc AND op.eliminado_en IS NULL);
