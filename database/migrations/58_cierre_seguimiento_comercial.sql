-- ============================================================
-- Migración 58 — HU-21 Cierre del seguimiento (aceptación, rechazo o sin venta)
--   1. seguimiento_comercial: id_canal pasa a NULL (los cierres por rechazo o sin venta no tienen
--      canal de contacto) y nueva columna id_tipo_aceptacion
--   2. Catálogo TIPO_ACEPTACION_PROPUESTA (Num1 = id, String1 = nombre, String2 = código,
--      String3 = canal de comunicación con el que se registra)
--   Se reutilizan tal cual: MOTIVO_RECHAZO (10) para el rechazo y MOTIVO_CIERRE_SIN_VENTA (12)
--   para el cierre sin venta. La acción propuesta_seguimiento_cerrar ya existe (migración 55).
--
--   IDEMPOTENTE. Se puede re-ejecutar.
-- ============================================================

-- 1. seguimiento_comercial
ALTER TABLE seguimiento_comercial MODIFY COLUMN id_canal INT NULL;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'seguimiento_comercial'
                             AND COLUMN_NAME = 'id_tipo_aceptacion'),
    'ALTER TABLE seguimiento_comercial ADD COLUMN id_tipo_aceptacion INT NULL AFTER id_motivo_cierre',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- 2. Tipos de aceptación (el IdMaestro se reserva al crear la primera fila)
SET @id_tipo_acep := (SELECT MAX(IdMaestro) FROM tabla_maestra WHERE Descripcion = 'TIPO_ACEPTACION_PROPUESTA');
SET @id_tipo_acep := IFNULL(@id_tipo_acep, (SELECT MAX(IdMaestro) + 1 FROM tabla_maestra));

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2, String3)
SELECT 1, @id_tipo_acep, 'TIPO_ACEPTACION_PROPUESTA', t.id, t.nombre, t.codigo, t.canal
FROM (
          SELECT 1 AS id, 'Confirmación por correo' AS nombre, 'CORREO' AS codigo, 'CORREO' AS canal
UNION ALL SELECT 2, 'Carta de aceptación',        'CARTA',     'CORREO'
UNION ALL SELECT 3, 'Confirmación telefónica',    'TELEFONO',  'LLAMADA'
UNION ALL SELECT 4, 'Confirmación en reunión',    'REUNION',   'REUNION'
UNION ALL SELECT 5, 'Propuesta firmada',          'FIRMA',     'VISITA'
) t
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra x
                  WHERE x.Descripcion = 'TIPO_ACEPTACION_PROPUESTA' AND x.String2 = t.codigo);
