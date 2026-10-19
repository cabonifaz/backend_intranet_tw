-- ============================================================
-- Migración 70 — HU-28 Liberación y Anulación (Control de Transición Operativa)
--   1. orden_compra.fecha_liberacion y liberado_por: la OC liberó el expediente para programación
--   2. Acción oc_liberar (nivel 3 = supervisar, módulo propuestas): jefe y administrador comercial
--      (y admins de Gerencia y TI)
--   3. CONFIG_SLA expediente / programacion: 4 horas (alerta a las 2) para que Operaciones programe
--
--   La anulación del proceso completo usa la acción propuesta_anular que ya existe (HU-12).
--
--   IDEMPOTENTE. Se puede re-ejecutar.
-- ============================================================

-- 1. Liberación
SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'orden_compra' AND COLUMN_NAME = 'fecha_liberacion'),
    'ALTER TABLE orden_compra ADD COLUMN fecha_liberacion DATETIME NULL AFTER id_validado_por',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'orden_compra' AND COLUMN_NAME = 'liberado_por'),
    'ALTER TABLE orden_compra ADD COLUMN liberado_por BIGINT NULL AFTER fecha_liberacion',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- 2. Acción
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2, String3)
SELECT 1, 88, 'ACCION_SISTEMA', 3, 'Liberar el expediente para programación', 'oc_liberar', 'propuestas'
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra WHERE IdMaestro = 88 AND IdEmpresa = 1 AND String2 = 'oc_liberar');

-- 3. SLA de programación
SET @n_sla := (SELECT IFNULL(MAX(Num1), 0) + 1 FROM tabla_maestra WHERE IdMaestro = 49 AND IdEmpresa = 1);
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, Num2, Num3, String1, String2, String3)
SELECT 1, 49, 'CONFIG_SLA', @n_sla, 4, 2, 'expediente', 'programacion', '1'
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra
                  WHERE IdMaestro = 49 AND IdEmpresa = 1 AND String1 = 'expediente' AND String2 = 'programacion');
