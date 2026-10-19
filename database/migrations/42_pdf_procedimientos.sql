-- ============================================================
-- Migración 42 — Carga real del PDF aprobado de Procedimientos (HU-87)
--   1. procedimiento_metrologico: datos del archivo cargado.
--      url_pdf_aprobado pasa a guardar la ruta interna del archivo
--      dentro del almacenamiento (volumen de Railway), no una URL pública.
--   2. Permiso con el sistema por acción de la migración 41 (#4301):
--      área "Calidad" (AREA_USUARIO 79), módulo "calidad" (MODULO_SISTEMA 85)
--      y acción procedimiento_pdf_cargar (ACCION_SISTEMA 88, nivel editar).
--      Pueden cargar el PDF: usuarios del área Calidad (rol usuario o superior)
--      y los administradores de cualquier área.
--      Calidad además puede VER Procedimientos (para abrir la ficha).
--   IDEMPOTENTE. Las filas que ya existan en la matriz NO se pisan.
--   Sin punto y coma dentro de los comentarios.
-- ============================================================

-- 1. Columnas del archivo
SET @t := 'procedimiento_metrologico';

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = @t AND COLUMN_NAME = 'pdf_nombre_original'),
    'ALTER TABLE procedimiento_metrologico ADD COLUMN pdf_nombre_original VARCHAR(255) NULL AFTER url_pdf_aprobado',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = @t AND COLUMN_NAME = 'pdf_tamano_bytes'),
    'ALTER TABLE procedimiento_metrologico ADD COLUMN pdf_tamano_bytes BIGINT NULL AFTER pdf_nombre_original',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = @t AND COLUMN_NAME = 'pdf_hash_sha256'),
    'ALTER TABLE procedimiento_metrologico ADD COLUMN pdf_hash_sha256 CHAR(64) NULL AFTER pdf_tamano_bytes',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = @t AND COLUMN_NAME = 'pdf_subido_en'),
    'ALTER TABLE procedimiento_metrologico ADD COLUMN pdf_subido_en DATETIME NULL AFTER pdf_hash_sha256',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = @t AND COLUMN_NAME = 'pdf_subido_por'),
    'ALTER TABLE procedimiento_metrologico ADD COLUMN pdf_subido_por BIGINT NULL AFTER pdf_subido_en',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- Hasta hoy el front siempre enviaba url_pdf_aprobado vacío, se limpia
-- cualquier valor que no tenga archivo asociado
UPDATE procedimiento_metrologico
   SET url_pdf_aprobado = NULL
 WHERE pdf_subido_en IS NULL AND url_pdf_aprobado IS NOT NULL;

-- 2a. Área Calidad
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2)
SELECT 1, 79, 'AREA_USUARIO', x.n, 'Calidad', 'calidad'
FROM (SELECT IFNULL(MAX(Num1), 0) + 1 AS n FROM tabla_maestra WHERE IdMaestro = 79 AND IdEmpresa = 1) x
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra WHERE IdMaestro = 79 AND IdEmpresa = 1 AND String2 = 'calidad');

-- 2b. Módulo calidad (String3 = área dueña del módulo)
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2, String3)
SELECT 1, 85, 'MODULO_SISTEMA', x.n, 'Calidad (documentos aprobados)', 'calidad', 'calidad'
FROM (SELECT IFNULL(MAX(Num1), 0) + 1 AS n FROM tabla_maestra WHERE IdMaestro = 85 AND IdEmpresa = 1) x
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra WHERE IdMaestro = 85 AND IdEmpresa = 1 AND String2 = 'calidad');

-- 2c. Acción procedimiento_pdf_cargar (Num1 = nivel exigido: 2 editar)
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2, String3)
SELECT 1, 88, 'ACCION_SISTEMA', 2, 'Cargar / reemplazar PDF aprobado de procedimiento', 'procedimiento_pdf_cargar', 'calidad'
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra WHERE IdMaestro = 88 AND IdEmpresa = 1 AND String2 = 'procedimiento_pdf_cargar');

-- 2d. Matriz área x rol x módulo
-- Administradores de todas las áreas: administran el módulo calidad
INSERT IGNORE INTO permiso_area_rol (area, rol, modulo, acceso, UsuMod, FchMod)
SELECT ar.String2, 'administrador', 'calidad', 'administrar', 'migracion_42', NOW()
FROM tabla_maestra ar
WHERE ar.IdMaestro = 79 AND ar.IdEmpresa = 1;

-- Área Calidad: su propio módulo según el rol, y ver Procedimientos para abrir la ficha
INSERT IGNORE INTO permiso_area_rol (area, rol, modulo, acceso, UsuMod, FchMod) VALUES
('calidad', 'supervisor', 'calidad',                'supervisar', 'migracion_42', NOW()),
('calidad', 'usuario',    'calidad',                'editar',     'migracion_42', NOW()),
('calidad', 'visor',      'calidad',                'ver',        'migracion_42', NOW()),
('calidad', 'supervisor', 'maestro_procedimientos', 'ver',        'migracion_42', NOW()),
('calidad', 'usuario',    'maestro_procedimientos', 'ver',        'migracion_42', NOW());

-- Para habilitar a la encargada de calidad: asignarle el área Calidad (area = 'calidad')
-- con rol usuario o supervisor desde el maestro de Usuarios. No requiere más cambios.
