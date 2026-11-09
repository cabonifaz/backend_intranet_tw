-- ============================================================
-- Migración 96 — Registro de demoras en ruta desde la app móvil (App Mobile HU-05)
--   1. demora_registro: tipo de demora (llegada | ingreso), GPS de quien la registra, y la hora estimada (ETA) antes y después.
--        tipo             llegada = demora durante el traslado (recalcula la ETA de llegada)
--                         ingreso = ya llegó pero no puede ingresar (recalcula el inicio del trabajo)
--        latitud/longitud/precision_metros   GPS capturado al registrar (la hora la pone el servidor)
--        eta_anterior / eta_recalculada      hora de llegada (o de inicio del trabajo) antes y después de esta demora (hora de Lima)
--      La foto (opcional, solo cámara) ya tenía su columna: fotografia_url guarda la ruta en el almacenamiento de archivos.
--   2. Catálogo MOTIVO_DEMORA_RUTA: el ámbito de cada motivo va en String3 (traslado | ingreso | ambos; vacío = ambos).
--      Solo se completa si está vacío, por código (no pisa lo que ya se haya configurado).
--   3. Índice por servicio para listar las demoras de una OS.
--   No borra ni cambia datos existentes. IDEMPOTENTE.
-- ============================================================

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'demora_registro' AND COLUMN_NAME = 'tipo'),
    'ALTER TABLE demora_registro ADD COLUMN tipo ENUM(''llegada'',''ingreso'') NOT NULL DEFAULT ''llegada'' AFTER id_motivo', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'demora_registro' AND COLUMN_NAME = 'latitud'),
    'ALTER TABLE demora_registro ADD COLUMN latitud DECIMAL(10,7) NULL AFTER fotografia_url', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'demora_registro' AND COLUMN_NAME = 'longitud'),
    'ALTER TABLE demora_registro ADD COLUMN longitud DECIMAL(10,7) NULL AFTER latitud', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'demora_registro' AND COLUMN_NAME = 'precision_metros'),
    'ALTER TABLE demora_registro ADD COLUMN precision_metros DECIMAL(8,1) NULL AFTER longitud', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'demora_registro' AND COLUMN_NAME = 'eta_anterior'),
    'ALTER TABLE demora_registro ADD COLUMN eta_anterior DATETIME NULL AFTER precision_metros', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'demora_registro' AND COLUMN_NAME = 'eta_recalculada'),
    'ALTER TABLE demora_registro ADD COLUMN eta_recalculada DATETIME NULL AFTER eta_anterior', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'demora_registro' AND INDEX_NAME = 'ix_demora_os'),
    'CREATE INDEX ix_demora_os ON demora_registro (id_os, tipo, eliminado_en)', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- ── Ámbito de los motivos de demora (String3) ─────────────────────────────────────────────
UPDATE tabla_maestra
SET    String3 = CASE String2
                     WHEN 'TRAFICO'           THEN 'traslado'
                     WHEN 'ACCIDENTE_RUTA'    THEN 'traslado'
                     WHEN 'PROBLEMA_VEHICULO' THEN 'traslado'
                     WHEN 'CLIMA'             THEN 'traslado'
                     WHEN 'ACCESO_DENEGADO'   THEN 'ingreso'
                     WHEN 'ESPERA_CLIENTE'    THEN 'ingreso'
                     WHEN 'OTRO'              THEN 'ambos'
                 END
WHERE  Descripcion = 'MOTIVO_DEMORA_RUTA' AND IdEmpresa = 1
  AND  (String3 IS NULL OR String3 = '')
  AND  String2 IN ('TRAFICO', 'ACCIDENTE_RUTA', 'PROBLEMA_VEHICULO', 'CLIMA', 'ACCESO_DENEGADO', 'ESPERA_CLIENTE', 'OTRO');
