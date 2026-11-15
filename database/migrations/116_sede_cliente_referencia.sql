-- ============================================================
-- Migración 116 — sede_cliente.urbanizacion pasa a llamarse referencia
--   El usuario la usa para pistas de llegada ("frente al grifo Primax, portón negro"), no solo para la urbanización.
--   Se renombra la columna (mismo tipo VARCHAR(200) NULL, los datos se conservan). IDEMPOTENTE.
--   Después de correrla, volver a crear SP_GuardarSede y SP_ObtenerSedesPorCliente (usan la columna nueva).
-- ============================================================
SET @sql := IF(EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sede_cliente' AND COLUMN_NAME = 'urbanizacion')
           AND NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sede_cliente' AND COLUMN_NAME = 'referencia'),
    'ALTER TABLE sede_cliente RENAME COLUMN urbanizacion TO referencia', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SELECT 'Migración 116: sede_cliente.referencia' AS verificacion,
       IF(EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sede_cliente' AND COLUMN_NAME = 'referencia')
          AND NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sede_cliente' AND COLUMN_NAME = 'urbanizacion'),
          'OK', 'REVISAR') AS resultado;
