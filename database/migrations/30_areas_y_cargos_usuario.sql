-- ============================================================
-- Migración 30 — Catálogos de áreas y cargos de usuario (datos de Jazir)
--   AREA_USUARIO (79): 8 áreas (se agrega Servicio Técnico).
--   CARGO_USUARIO (80): 22 cargos; String3 = código del área del cargo.
--   Idempotente: borra y vuelve a cargar ambos catálogos. Seguro porque
--   usuario.area guarda el CÓDIGO (String2), que no cambia.
-- ============================================================

DELETE FROM tabla_maestra WHERE IdMaestro IN (79, 80) AND IdEmpresa = 1;

-- Áreas (79) — String1 = etiqueta, String2 = código
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2) VALUES
(1, 79, 'AREA_USUARIO', 1, 'Gerencia',         'gerencia'),
(1, 79, 'AREA_USUARIO', 2, 'Comercial',        'comercial'),
(1, 79, 'AREA_USUARIO', 3, 'Metrología',       'metrologia'),
(1, 79, 'AREA_USUARIO', 4, 'Operaciones',      'operaciones'),
(1, 79, 'AREA_USUARIO', 5, 'Servicio Técnico', 'servicio_tecnico'),
(1, 79, 'AREA_USUARIO', 6, 'Administración',   'administracion'),
(1, 79, 'AREA_USUARIO', 7, 'SSOMA',            'ssoma'),
(1, 79, 'AREA_USUARIO', 8, 'TI',               'ti');

-- Cargos (80) — String1 = etiqueta, String2 = código, String3 = código del área
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2, String3) VALUES
-- Gerencia
(1, 80, 'CARGO_USUARIO',  1, 'Gerente General',               'gerente_general',            'gerencia'),
-- Comercial
(1, 80, 'CARGO_USUARIO',  2, 'Jefe Comercial',                'jefe_comercial',             'comercial'),
(1, 80, 'CARGO_USUARIO',  3, 'Ejecutivo Comercial',           'ejecutivo_comercial',        'comercial'),
(1, 80, 'CARGO_USUARIO',  4, 'Asistente Comercial',           'asistente_comercial',        'comercial'),
-- Metrología
(1, 80, 'CARGO_USUARIO',  5, 'Jefe de Metrología',            'jefe_metrologia',            'metrologia'),
(1, 80, 'CARGO_USUARIO',  6, 'Metrólogo',                     'metrologo',                  'metrologia'),
(1, 80, 'CARGO_USUARIO',  7, 'Metrólogo Jr.',                 'metrologo_jr',               'metrologia'),
-- Operaciones
(1, 80, 'CARGO_USUARIO',  8, 'Jefe de Operaciones',           'jefe_operaciones',           'operaciones'),
(1, 80, 'CARGO_USUARIO',  9, 'Coordinador de Operaciones',    'coordinador_operaciones',    'operaciones'),
-- Servicio Técnico
(1, 80, 'CARGO_USUARIO', 10, 'Jefe de Servicio Técnico',      'jefe_servicio_tecnico',      'servicio_tecnico'),
(1, 80, 'CARGO_USUARIO', 11, 'Técnico de Campo',              'tecnico_campo',              'servicio_tecnico'),
(1, 80, 'CARGO_USUARIO', 12, 'Técnico de Campo Jr.',          'tecnico_campo_jr',           'servicio_tecnico'),
(1, 80, 'CARGO_USUARIO', 13, 'Asistente de Servicio Técnico', 'asistente_servicio_tecnico', 'servicio_tecnico'),
(1, 80, 'CARGO_USUARIO', 14, 'Asistente Documentaria',        'asistente_documentaria',     'servicio_tecnico'),
-- Administración
(1, 80, 'CARGO_USUARIO', 15, 'Jefe Administrativo',           'jefe_administrativo',        'administracion'),
(1, 80, 'CARGO_USUARIO', 16, 'Contador',                      'contador',                   'administracion'),
(1, 80, 'CARGO_USUARIO', 17, 'Asistente Administrativa',      'asistente_administrativa',   'administracion'),
(1, 80, 'CARGO_USUARIO', 18, 'Facturador',                    'facturador',                 'administracion'),
-- SSOMA
(1, 80, 'CARGO_USUARIO', 19, 'Jefe SSOMA',                    'jefe_ssoma',                 'ssoma'),
(1, 80, 'CARGO_USUARIO', 20, 'Supervisor SSOMA',              'supervisor_ssoma',           'ssoma'),
-- TI
(1, 80, 'CARGO_USUARIO', 21, 'Jefe de TI',                    'jefe_ti',                    'ti'),
(1, 80, 'CARGO_USUARIO', 22, 'Desarrollador',                 'desarrollador',              'ti');
