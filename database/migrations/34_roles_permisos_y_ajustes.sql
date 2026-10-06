-- ============================================================
-- Migración 34 — Roles por niveles, permisos por área, supervisor automático
--                y ajustes pendientes de la reunión del 02-oct
--   1. Usuarios ..... troncal telefónica (569-9750 / 569-9751) para el anexo
--   2. Roles ........ 4 niveles: administrador, supervisor, usuario, visor
--                     (los roles anteriores se convierten; el área se completa si falta)
--   3. Permisos ..... módulos del sistema + matriz área × rol × módulo (excepciones)
--   4. Suministros .. cada TIPO_SUMINISTRO queda asociado a su clase (String3)
--   5. Equipos ...... material y valor nominal (pesas); clase de exactitud I, II, III, IV
--   IDEMPOTENTE. Ejecutar junto con los SPs de este mismo paquete.
-- ============================================================

-- ── 1. USUARIOS: troncal del anexo ───────────────────────────
SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'usuario' AND COLUMN_NAME = 'troncal'),
    'ALTER TABLE usuario ADD COLUMN troncal VARCHAR(10) NULL AFTER anexo', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2)
SELECT 1, 84, 'TRONCAL_TW', t.n, t.etiqueta, t.codigo
FROM (SELECT 1 AS n, '569-9750' AS etiqueta, '5699750' AS codigo
      UNION ALL SELECT 2, '569-9751', '5699751') t
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra x WHERE x.IdMaestro = 84 AND x.IdEmpresa = 1 AND x.String2 = t.codigo);

-- ── 2. ROLES POR NIVELES ─────────────────────────────────────
-- 2a. Completar el área de los usuarios que no la tienen, según su rol anterior
UPDATE usuario
SET area = CASE rol_sistema
        WHEN 'gerencia'         THEN 'gerencia'
        WHEN 'jefe_comercial'   THEN 'comercial'
        WHEN 'comercial'        THEN 'comercial'
        WHEN 'jefe_metrologia'  THEN 'metrologia'
        WHEN 'metrologo'        THEN 'metrologia'
        WHEN 'jefe_operaciones' THEN 'operaciones'
        WHEN 'operaciones'      THEN 'operaciones'
        WHEN 'admin'            THEN 'ti'
        WHEN 'desarrollador'    THEN 'ti'
        ELSE area
    END
WHERE (area IS NULL OR area = '')
  AND rol_sistema IN ('gerencia','jefe_comercial','comercial','jefe_metrologia','metrologo',
                      'jefe_operaciones','operaciones','admin','desarrollador');

-- 2b. Convertir los roles anteriores a niveles
UPDATE usuario
SET rol_sistema = CASE
        WHEN rol_sistema IN ('admin', 'gerencia', 'desarrollador')                     THEN 'administrador'
        WHEN rol_sistema IN ('jefe_comercial', 'jefe_metrologia', 'jefe_operaciones') THEN 'supervisor'
        ELSE 'usuario'
    END
WHERE rol_sistema IN ('admin','gerencia','jefe_comercial','comercial','jefe_metrologia','metrologo',
                      'jefe_operaciones','operaciones','desarrollador');

-- 2c. Catálogo ROL_SISTEMA (68): Num1 = nivel (1 = más alto), Num3 = 1 si puede supervisar
DELETE FROM tabla_maestra
WHERE IdMaestro = 68 AND IdEmpresa = 1
  AND String2 NOT IN ('administrador', 'supervisor', 'usuario', 'visor');

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, Num2, Num3, String1, String2)
SELECT 1, 68, 'ROL_SISTEMA', r.nivel, 0, r.supervisa, r.etiqueta, r.codigo
FROM (SELECT 1 AS nivel, 1 AS supervisa, 'Administrador' AS etiqueta, 'administrador' AS codigo
      UNION ALL SELECT 2, 1, 'Supervisor', 'supervisor'
      UNION ALL SELECT 3, 0, 'Usuario',    'usuario'
      UNION ALL SELECT 4, 0, 'Visor',      'visor') r
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra x WHERE x.IdMaestro = 68 AND x.IdEmpresa = 1 AND x.String2 = r.codigo);

-- ── 3. PERMISOS: módulos y excepciones por área × rol ────────
-- Catálogo MODULO_SISTEMA (85): String2 = código, String3 = área dueña ('*' = todas)
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2, String3)
SELECT 1, 85, 'MODULO_SISTEMA', m.orden, m.etiqueta, m.codigo, m.area
FROM (
          SELECT  1 AS orden, 'Inicio (dashboard)'          AS etiqueta, 'dashboard'               AS codigo, '*'                AS area
UNION ALL SELECT  2, 'Requerimientos',                      'requerimientos',          'comercial'
UNION ALL SELECT  3, 'Propuestas comerciales',              'propuestas',              'comercial'
UNION ALL SELECT  4, 'Operaciones',                         'operaciones',             'operaciones'
UNION ALL SELECT  5, 'Servicio Técnico',                    'servicio_tecnico',        'servicio_tecnico'
UNION ALL SELECT  6, 'Equipos y Activos',                   'equipos_activos',         'servicio_tecnico'
UNION ALL SELECT  7, 'Metrología',                          'metrologia',              'metrologia'
UNION ALL SELECT  8, 'Cierre y Facturación',                'facturacion',             'administracion'
UNION ALL SELECT  9, 'SSOMA',                               'ssoma',                   'ssoma'
UNION ALL SELECT 10, 'Maestro: Clientes',                   'maestro_clientes',        'comercial'
UNION ALL SELECT 11, 'Maestro: Usuarios y suplencias',      'maestro_usuarios',        'gerencia'
UNION ALL SELECT 12, 'Maestro: Textos base',                'maestro_textos_base',     'comercial'
UNION ALL SELECT 13, 'Maestro: Suministros',                'maestro_suministros',     'comercial'
UNION ALL SELECT 14, 'Maestro: Procedimientos',             'maestro_procedimientos',  'metrologia'
UNION ALL SELECT 15, 'Maestro: Equipos del cliente',        'maestro_equipos_cliente', 'servicio_tecnico'
UNION ALL SELECT 16, 'Reportes e indicadores',              'reportes',                'gerencia'
UNION ALL SELECT 17, 'Configuración',                       'configuracion',           'ti'
) m
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra x WHERE x.IdMaestro = 85 AND x.IdEmpresa = 1 AND x.String2 = m.codigo);

-- Excepciones a la regla general (la regla está en SP_ObtenerPermisosUsuario):
--   · Administrador de Gerencia o TI      → administra todos los módulos
--   · Módulo de su propia área           → acceso según su rol
--     (administrador = administrar, supervisor = supervisar, usuario = editar, visor = ver)
--   · Dashboard                           → todos lo ven
--   · Módulo de otra área                → sin acceso, salvo que exista una fila aquí
--   Ej.: metrología + usuario → servicio_tecnico = 'ver' (el metrólogo revisa informes y fotos)
CREATE TABLE IF NOT EXISTS permiso_area_rol (
    area     VARCHAR(40) NOT NULL,
    rol      VARCHAR(20) NOT NULL,
    modulo   VARCHAR(40) NOT NULL,
    acceso   ENUM('ninguno','ver','editar','supervisar','administrar') NOT NULL,
    UsuMod   VARCHAR(100) NULL,
    FchMod   DATETIME     NULL,
    PRIMARY KEY (area, rol, modulo)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Ejemplo dado por TW en la reunión: el metrólogo (usuario) consulta Servicio Técnico
INSERT IGNORE INTO permiso_area_rol (area, rol, modulo, acceso, UsuMod, FchMod) VALUES
('metrologia', 'usuario',    'servicio_tecnico', 'ver', 'migracion_34', NOW()),
('metrologia', 'supervisor', 'servicio_tecnico', 'ver', 'migracion_34', NOW());

-- ── 4. SUMINISTROS: tipo asociado a su clase ─────────────────
UPDATE tabla_maestra
SET String3 = CASE String2
        WHEN 'instrumento_laboratorio'   THEN 'instrumento'
        WHEN 'balanza_industrial'        THEN 'equipo'
        WHEN 'balanza_precision'         THEN 'equipo'
        WHEN 'celda_carga'               THEN 'equipo'
        WHEN 'indicador_digital'         THEN 'equipo'
        WHEN 'pesa_patron'               THEN 'pesa'
        WHEN 'mantenimiento_calibracion' THEN 'servicio'
    END
WHERE IdMaestro = 72 AND IdEmpresa = 1
  AND (String3 IS NULL OR String3 = '')
  AND String2 IN ('instrumento_laboratorio','balanza_industrial','balanza_precision','celda_carga',
                  'indicador_digital','pesa_patron','mantenimiento_calibracion');

-- ── 5. EQUIPOS DEL CLIENTE ──────────────────────────────────
SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'equipo_cliente' AND COLUMN_NAME = 'material'),
    'ALTER TABLE equipo_cliente ADD COLUMN material VARCHAR(80) NULL AFTER observaciones', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;
SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'equipo_cliente' AND COLUMN_NAME = 'valor_nominal'),
    'ALTER TABLE equipo_cliente ADD COLUMN valor_nominal VARCHAR(40) NULL AFTER material', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- Clase de exactitud: I, II, III, IV (antes la cuarta era "IIII")
UPDATE equipo_cliente SET clase_exactitud = 'IV' WHERE clase_exactitud = 'IIII';
UPDATE tabla_maestra SET String1 = 'IV', String2 = 'IV'
WHERE IdMaestro = 82 AND IdEmpresa = 1 AND String2 = 'IIII';

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2)
SELECT 1, 82, 'CLASE_EXACTITUD', c.n, c.cod, c.cod
FROM (SELECT 1 AS n, 'I' AS cod UNION ALL SELECT 2, 'II' UNION ALL SELECT 3, 'III' UNION ALL SELECT 4, 'IV') c
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra x WHERE x.IdMaestro = 82 AND x.IdEmpresa = 1 AND x.String2 = c.cod);

-- ── 6. LIMPIEZA DE CATÁLOGOS ─────────────────────────────────
-- El IdMaestro 66 tenía mezclados los MOTIVOS DE ANULACIÓN (mig. 18) con los ESTADOS
-- del requerimiento (mig. 11). Los estados viven en el 67 (mig. 19): se quitan del 66.
-- requerimiento.estado guarda el código de texto, no referencia estas filas.
DELETE FROM tabla_maestra
WHERE IdMaestro = 66 AND IdEmpresa = 1 AND Descripcion = 'ESTADO_REQUERIMIENTO';
