-- ============================================================
-- Migración 44 — HU-12: Envío a Visto Bueno y Anulación de Propuesta
--   1. propuesta_comercial: datos de la anulación (motivo, justificación,
--      fecha y usuario).
--   2. Acciones (sistema de permisos de la migración 41, módulo propuestas):
--        propuesta_enviar_vb  nivel 2 (editar)
--        propuesta_anular     nivel 2 (editar)
--   3. Parámetros configurables en tabla_maestra (grupo PARAMETRO_PROPUESTA):
--        String2 = código, Num2 = valor
--        DESCUENTO_APROBACION_ESPECIAL  10  descuento global (en %) a partir del cual
--                                           el VB requiere aprobación especial
--        VB_EXIGIR_PDF                  0   1 = el PDF generado es obligatorio para
--                                           enviar a VB (activar cuando exista el PDF de HU-09)
--        VB_EXIGIR_EQUIPOS              1   1 = exige al menos un equipo asociado
--   IDEMPOTENTE. Sin punto y coma dentro de los comentarios.
-- ============================================================

-- 1. Columnas de anulación
SET @t := 'propuesta_comercial';

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = @t AND COLUMN_NAME = 'id_motivo_anulacion'),
    'ALTER TABLE propuesta_comercial ADD COLUMN id_motivo_anulacion INT NULL',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = @t AND COLUMN_NAME = 'justificacion_anulacion'),
    'ALTER TABLE propuesta_comercial ADD COLUMN justificacion_anulacion TEXT NULL AFTER id_motivo_anulacion',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = @t AND COLUMN_NAME = 'fecha_anulacion'),
    'ALTER TABLE propuesta_comercial ADD COLUMN fecha_anulacion DATETIME NULL AFTER justificacion_anulacion',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = @t AND COLUMN_NAME = 'anulado_por'),
    'ALTER TABLE propuesta_comercial ADD COLUMN anulado_por BIGINT NULL AFTER fecha_anulacion',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- 2. Acciones
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2, String3)
SELECT 1, 88, 'ACCION_SISTEMA', 2, 'Enviar propuesta a visto bueno', 'propuesta_enviar_vb', 'propuestas'
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra WHERE IdMaestro = 88 AND IdEmpresa = 1 AND String2 = 'propuesta_enviar_vb');

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2, String3)
SELECT 1, 88, 'ACCION_SISTEMA', 2, 'Anular propuesta', 'propuesta_anular', 'propuestas'
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra WHERE IdMaestro = 88 AND IdEmpresa = 1 AND String2 = 'propuesta_anular');

-- 3. Parámetros (el IdMaestro del grupo se reserva al crear la primera fila)
SET @id_param := (SELECT MAX(IdMaestro) FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROPUESTA');
SET @id_param := IFNULL(@id_param, (SELECT MAX(IdMaestro) + 1 FROM tabla_maestra));

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, Num2, String1, String2)
SELECT 1, @id_param, 'PARAMETRO_PROPUESTA', 1, 10,
       'Descuento global (%) desde el cual el VB requiere aprobación especial', 'DESCUENTO_APROBACION_ESPECIAL'
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROPUESTA' AND String2 = 'DESCUENTO_APROBACION_ESPECIAL');

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, Num2, String1, String2)
SELECT 1, @id_param, 'PARAMETRO_PROPUESTA', 2, 0,
       'Exigir PDF generado para enviar a VB (1 = sí)', 'VB_EXIGIR_PDF'
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROPUESTA' AND String2 = 'VB_EXIGIR_PDF');

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, Num2, String1, String2)
SELECT 1, @id_param, 'PARAMETRO_PROPUESTA', 3, 1,
       'Exigir al menos un equipo asociado para enviar a VB (1 = sí)', 'VB_EXIGIR_EQUIPOS'
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROPUESTA' AND String2 = 'VB_EXIGIR_EQUIPOS');
