-- ============================================================
-- Migración 66 — HU-24 Registro y Edición de Orden de Compra
--   1. orden_compra.referencia: referencia / glosa de la OC (texto libre, hasta 200 caracteres)
--   2. Acción oc_editar (nivel 2, módulo propuestas): asistente, jefe y administrador comercial
--   3. Parámetro OC_TOLERANCIA_MONTO_PCT (0) en PARAMETRO_PROPUESTA: cuánto por debajo del monto
--      de la propuesta puede estar la OC y seguir "dentro de tolerancia" en el checklist.
--
--   IDEMPOTENTE. Se puede re-ejecutar.
-- ============================================================

-- 1. Referencia / glosa
SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'orden_compra' AND COLUMN_NAME = 'referencia'),
    'ALTER TABLE orden_compra ADD COLUMN referencia VARCHAR(200) NULL AFTER numero_oc',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- 2. Acción
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2, String3)
SELECT 1, 88, 'ACCION_SISTEMA', 2, 'Editar orden de compra registrada', 'oc_editar', 'propuestas'
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra WHERE IdMaestro = 88 AND IdEmpresa = 1 AND String2 = 'oc_editar');

-- 3. Tolerancia del monto
SET @id_param := (SELECT MAX(IdMaestro) FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROPUESTA');
SET @n_param  := (SELECT IFNULL(MAX(Num1), 0) FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROPUESTA');

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, Num2, String1, String2)
SELECT 1, @id_param, 'PARAMETRO_PROPUESTA', @n_param + 1, 0,
       'Tolerancia (%) por debajo del monto de la propuesta para la orden de compra', 'OC_TOLERANCIA_MONTO_PCT'
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROPUESTA' AND String2 = 'OC_TOLERANCIA_MONTO_PCT');
