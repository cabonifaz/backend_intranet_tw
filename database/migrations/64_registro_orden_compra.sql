-- ============================================================
-- Migración 64 — HU-22 Registro de Orden de Compra recibida
--   1. orden_compra: vigencia_dias, observaciones y datos del PDF (nombre, tamaño y hash).
--      url_archivo_pdf guarda la ruta interna del almacenamiento (se descarga por el endpoint).
--   2. Acción oc_registrar (nivel 2, módulo propuestas): asistente, jefe y administrador comercial
--   3. Parámetro OC_VIGENCIA_DIAS_DEFECTO (30) en PARAMETRO_PROPUESTA
--
--   IDEMPOTENTE. Se puede re-ejecutar.
-- ============================================================

-- 1. Columnas nuevas en orden_compra
SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'orden_compra' AND COLUMN_NAME = 'vigencia_dias'),
    'ALTER TABLE orden_compra ADD COLUMN vigencia_dias INT NULL AFTER vigencia_hasta',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'orden_compra' AND COLUMN_NAME = 'observaciones'),
    'ALTER TABLE orden_compra ADD COLUMN observaciones VARCHAR(500) NULL AFTER vigencia_dias',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'orden_compra' AND COLUMN_NAME = 'nombre_archivo_pdf'),
    'ALTER TABLE orden_compra ADD COLUMN nombre_archivo_pdf VARCHAR(255) NULL AFTER url_archivo_pdf',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'orden_compra' AND COLUMN_NAME = 'tamano_pdf_bytes'),
    'ALTER TABLE orden_compra ADD COLUMN tamano_pdf_bytes BIGINT NULL AFTER nombre_archivo_pdf',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'orden_compra' AND COLUMN_NAME = 'hash_pdf'),
    'ALTER TABLE orden_compra ADD COLUMN hash_pdf CHAR(64) NULL AFTER tamano_pdf_bytes',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- 2. Acción
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2, String3)
SELECT 1, 88, 'ACCION_SISTEMA', 2, 'Registrar orden de compra recibida del cliente', 'oc_registrar', 'propuestas'
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra WHERE IdMaestro = 88 AND IdEmpresa = 1 AND String2 = 'oc_registrar');

-- 3. Parámetro de vigencia por defecto
SET @id_param := (SELECT MAX(IdMaestro) FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROPUESTA');
SET @n_param  := (SELECT IFNULL(MAX(Num1), 0) FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROPUESTA');

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, Num2, String1, String2)
SELECT 1, @id_param, 'PARAMETRO_PROPUESTA', @n_param + 1, 30,
       'Vigencia sugerida (días) de la orden de compra al registrarla', 'OC_VIGENCIA_DIAS_DEFECTO'
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROPUESTA' AND String2 = 'OC_VIGENCIA_DIAS_DEFECTO');
