-- ============================================================
-- Migración 97 — Registro de llegada con validación GPS desde la app móvil (App Mobile HU-06)
--   1. evento_campo: precisión del GPS (± m) y distancia (m) a la planta del cliente al registrar la llegada.
--      La llegada es un evento LLEGADA (TIPO_EVENTO_CAMPO) con la hora, el GPS y estos dos datos; la bandeja de Seguimiento Operativo
--      ya lee ese evento (fase "en planta", hito "Llegada confirmada", mapa GPS).
--   2. Parámetros (PARAMETRO_PROGRAMACION): radio permitido para confirmar la llegada (200 m) y precisión máxima del GPS (100 m).
--   No borra ni cambia datos existentes. IDEMPOTENTE. Requiere la migración 90.
-- ============================================================

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'evento_campo' AND COLUMN_NAME = 'precision_metros'),
    'ALTER TABLE evento_campo ADD COLUMN precision_metros DECIMAL(8,1) NULL AFTER longitud', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'evento_campo' AND COLUMN_NAME = 'distancia_metros'),
    'ALTER TABLE evento_campo ADD COLUMN distancia_metros INT NULL AFTER precision_metros', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- ── Parámetros ────────────────────────────────────────────────────────────────────────────
SET @id_param := (SELECT MAX(IdMaestro) FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROGRAMACION');
SET @id_param := IFNULL(@id_param, (SELECT MAX(IdMaestro) + 1 FROM tabla_maestra));

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, Num2, String1, String2)
SELECT 1, @id_param, 'PARAMETRO_PROGRAMACION',
       (SELECT IFNULL(MAX(t.Num1), 0) + 1 FROM tabla_maestra t WHERE t.IdMaestro = @id_param AND t.IdEmpresa = 1),
       200, 'Metros máximos a la planta del cliente para confirmar la llegada desde la app', 'LLEGADA_RADIO_METROS'
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra t WHERE t.Descripcion = 'PARAMETRO_PROGRAMACION' AND t.IdEmpresa = 1 AND t.String2 = 'LLEGADA_RADIO_METROS');

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, Num2, String1, String2)
SELECT 1, @id_param, 'PARAMETRO_PROGRAMACION',
       (SELECT IFNULL(MAX(t.Num1), 0) + 1 FROM tabla_maestra t WHERE t.IdMaestro = @id_param AND t.IdEmpresa = 1),
       100, 'Precisión máxima del GPS (± metros) para confirmar la llegada desde la app', 'LLEGADA_PRECISION_MAX_METROS'
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra t WHERE t.Descripcion = 'PARAMETRO_PROGRAMACION' AND t.IdEmpresa = 1 AND t.String2 = 'LLEGADA_PRECISION_MAX_METROS');

-- ── Verificación ─────────────────────────────────────────────────────────────
SELECT 'Migración 97 (debe ser 4)' AS verificacion,
       (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'evento_campo' AND COLUMN_NAME IN ('precision_metros', 'distancia_metros'))
     + (SELECT COUNT(*) FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROGRAMACION' AND IdEmpresa = 1 AND String2 IN ('LLEGADA_RADIO_METROS', 'LLEGADA_PRECISION_MAX_METROS')) AS valor;
