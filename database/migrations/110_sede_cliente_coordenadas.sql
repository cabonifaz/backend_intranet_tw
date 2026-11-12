-- ============================================================
-- Migración 110 — Coordenadas de la planta del cliente (sede_cliente) para el mapa, la distancia y la hora de llegada estimada (HU-20)
--   sede_cliente (la planta que eligen el RQ y la OS) tenía nombre y dirección pero NO coordenadas: el seguimiento no podía dibujar el destino ni calcular
--   la llegada. Se agregan latitud y longitud (opcionales). Se llenan desde la intranet (formulario de sede) o con un UPDATE. No cambia datos existentes. IDEMPOTENTE.
-- ============================================================
SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sede_cliente' AND COLUMN_NAME = 'latitud'),
    'ALTER TABLE sede_cliente ADD COLUMN latitud DECIMAL(10,7) NULL AFTER direccion_exacta', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sede_cliente' AND COLUMN_NAME = 'longitud'),
    'ALTER TABLE sede_cliente ADD COLUMN longitud DECIMAL(10,7) NULL AFTER latitud', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SELECT 'Migración 110 (debe ser 2)' AS verificacion, COUNT(*) AS valor FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sede_cliente' AND COLUMN_NAME IN ('latitud', 'longitud');
