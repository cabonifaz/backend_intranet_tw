-- ============================================================
-- Migración 98 — Lista de objetivos y selección de equipos desde la app móvil (App Mobile HU-07)
--   1. os_equipo (el "objetivo" de la OS = un equipo a intervenir): seguimiento de la ejecución desde la app.
--        iniciado_utc / reanudado_utc / acumulado_seg   tiempo real trabajado (reanudado_utc = inicio del tramo en curso; NULL = detenido)
--        pausado / motivo_pausa / pausa_requiere_aprobacion   "PAUSADO"; si requiere aprobación, el técnico NO puede reanudar
--        id_usuario_ejecucion   quién lo inició o reanudó (un técnico trabaja en un solo equipo a la vez)
--   2. equipo_cliente: equipos registrados en campo desde la app (NEW): quedan en estado 'borrador' hasta que la intranet los apruebe y
--      les asigne el COD TW. registrado_en_campo, id_os_registro y foto_placa_url (foto de la placa, solo cámara).
--   3. Catálogo TIPO_INTERVENCION_EQUIPO: String3 = sigla ("MC", "MP") y Num2 = minutos estimados del objetivo (solo si están vacíos;
--      Calibración 30 y Mantenimiento correctivo 60 según el mockup; el resto usa el parámetro de abajo).
--   4. Parámetro OBJETIVO_MINUTOS_POR_DEFECTO (60): minutos estimados cuando el tipo de intervención no define los suyos.
--   No borra ni cambia datos existentes. IDEMPOTENTE. Requiere las migraciones 80 y 97.
-- ============================================================

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'os_equipo' AND COLUMN_NAME = 'iniciado_utc'),
    'ALTER TABLE os_equipo ADD COLUMN iniciado_utc DATETIME NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'os_equipo' AND COLUMN_NAME = 'reanudado_utc'),
    'ALTER TABLE os_equipo ADD COLUMN reanudado_utc DATETIME NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'os_equipo' AND COLUMN_NAME = 'acumulado_seg'),
    'ALTER TABLE os_equipo ADD COLUMN acumulado_seg INT NOT NULL DEFAULT 0', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'os_equipo' AND COLUMN_NAME = 'pausado'),
    'ALTER TABLE os_equipo ADD COLUMN pausado TINYINT(1) NOT NULL DEFAULT 0', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'os_equipo' AND COLUMN_NAME = 'motivo_pausa'),
    'ALTER TABLE os_equipo ADD COLUMN motivo_pausa VARCHAR(300) NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'os_equipo' AND COLUMN_NAME = 'pausa_requiere_aprobacion'),
    'ALTER TABLE os_equipo ADD COLUMN pausa_requiere_aprobacion TINYINT(1) NOT NULL DEFAULT 0', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'os_equipo' AND COLUMN_NAME = 'id_usuario_ejecucion'),
    'ALTER TABLE os_equipo ADD COLUMN id_usuario_ejecucion BIGINT NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'equipo_cliente' AND COLUMN_NAME = 'registrado_en_campo'),
    'ALTER TABLE equipo_cliente ADD COLUMN registrado_en_campo TINYINT(1) NOT NULL DEFAULT 0', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'equipo_cliente' AND COLUMN_NAME = 'id_os_registro'),
    'ALTER TABLE equipo_cliente ADD COLUMN id_os_registro BIGINT NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'equipo_cliente' AND COLUMN_NAME = 'foto_placa_url'),
    'ALTER TABLE equipo_cliente ADD COLUMN foto_placa_url VARCHAR(500) NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- ── Catálogo TIPO_INTERVENCION_EQUIPO (31): sigla y minutos estimados, solo donde están vacíos ──────────
UPDATE tabla_maestra
SET    String3 = CASE String2 WHEN 'MANTENIMIENTO_CORR' THEN 'MC' WHEN 'MANTENIMIENTO_PREV' THEN 'MP' END
WHERE  Descripcion = 'TIPO_INTERVENCION_EQUIPO' AND IdEmpresa = 1 AND (String3 IS NULL OR String3 = '') AND String2 IN ('MANTENIMIENTO_CORR', 'MANTENIMIENTO_PREV');

UPDATE tabla_maestra
SET    Num2 = CASE String2 WHEN 'CALIBRACION' THEN 30 WHEN 'MANTENIMIENTO_CORR' THEN 60 END
WHERE  Descripcion = 'TIPO_INTERVENCION_EQUIPO' AND IdEmpresa = 1 AND Num2 IS NULL AND String2 IN ('CALIBRACION', 'MANTENIMIENTO_CORR');

-- ── Parámetro ──────────────────────────────────────────────────────────────────────────────
SET @id_param := (SELECT MAX(IdMaestro) FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROGRAMACION');
SET @id_param := IFNULL(@id_param, (SELECT MAX(IdMaestro) + 1 FROM tabla_maestra));

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, Num2, String1, String2)
SELECT 1, @id_param, 'PARAMETRO_PROGRAMACION',
       (SELECT IFNULL(MAX(t.Num1), 0) + 1 FROM tabla_maestra t WHERE t.IdMaestro = @id_param AND t.IdEmpresa = 1),
       60, 'Minutos estimados de un objetivo cuando su tipo de intervención no define los suyos', 'OBJETIVO_MINUTOS_POR_DEFECTO'
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra t WHERE t.Descripcion = 'PARAMETRO_PROGRAMACION' AND t.IdEmpresa = 1 AND t.String2 = 'OBJETIVO_MINUTOS_POR_DEFECTO');

-- ── Verificación ─────────────────────────────────────────────────────────────
SELECT 'Migración 98 (debe ser 11)' AS verificacion,
       (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'os_equipo'
           AND COLUMN_NAME IN ('iniciado_utc', 'reanudado_utc', 'acumulado_seg', 'pausado', 'motivo_pausa', 'pausa_requiere_aprobacion', 'id_usuario_ejecucion'))
     + (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'equipo_cliente'
           AND COLUMN_NAME IN ('registrado_en_campo', 'id_os_registro', 'foto_placa_url'))
     + (SELECT COUNT(*) FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROGRAMACION' AND IdEmpresa = 1 AND String2 = 'OBJETIVO_MINUTOS_POR_DEFECTO') AS valor;
