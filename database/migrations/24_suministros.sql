-- ============================================================
-- Migración 24 — HU-86: Mantenimiento de Suministros
--   Amplía catalogo_item (ya referenciada por propuesta_item)
--   y crea los catálogos 71 a 75 en tabla_maestra.
-- ============================================================

-- 1. Columnas nuevas en catalogo_item
--    (codigo, descripcion, precio_referencia, unidad_medida, activo y
--     creado_en/creado_por/modificado_en ya existen y se reutilizan)
ALTER TABLE catalogo_item
    ADD COLUMN clase                    VARCHAR(20)   NULL,
    ADD COLUMN tipo                     VARCHAR(60)   NULL,
    ADD COLUMN subtipo                  VARCHAR(60)   NULL,
    ADD COLUMN marca                    VARCHAR(80)   NULL,
    ADD COLUMN modelo                   VARCHAR(80)   NULL,
    ADD COLUMN descripcion_manual       TEXT          NULL,
    ADD COLUMN alcance                  VARCHAR(200)  NULL,
    ADD COLUMN cta_contable             VARCHAR(20)   NULL,
    ADD COLUMN procedencia              VARCHAR(30)   NULL,
    ADD COLUMN casillero                VARCHAR(30)   NULL,
    ADD COLUMN usar_en_propuestas       TINYINT(1)    NOT NULL DEFAULT 0,
    ADD COLUMN codigo_unspsc            VARCHAR(20)   NULL,
    ADD COLUMN precio_nivel_estandar    DECIMAL(12,2) NULL,
    ADD COLUMN precio_nivel_volumen     DECIMAL(12,2) NULL,
    ADD COLUMN precio_nivel_corporativo DECIMAL(12,2) NULL,
    ADD COLUMN aplica_comercial         TINYINT(1)    NOT NULL DEFAULT 0,
    ADD COLUMN aplica_servicio          TINYINT(1)    NOT NULL DEFAULT 0,
    ADD COLUMN aplica_metrologia        TINYINT(1)    NOT NULL DEFAULT 0,
    ADD COLUMN id_primer_procedimiento  VARCHAR(40)   NULL,
    ADD COLUMN id_segundo_procedimiento VARCHAR(40)   NULL,
    ADD COLUMN url_foto                 VARCHAR(500)  NULL,
    ADD COLUMN url_manual_pdf           VARCHAR(500)  NULL,
    ADD COLUMN estado                   ENUM('activo','inactivo','borrador') NOT NULL DEFAULT 'activo',
    ADD COLUMN total_ediciones          INT           NOT NULL DEFAULT 0;

-- 2. Catálogos (String1 = etiqueta, String2 = código que se guarda)
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2) VALUES
-- Clase (71)
(1, 71, 'CLASE_SUMINISTRO', 1, 'Servicio',    'servicio'),
(1, 71, 'CLASE_SUMINISTRO', 2, 'Equipo',      'equipo'),
(1, 71, 'CLASE_SUMINISTRO', 3, 'Pesa',        'pesa'),
(1, 71, 'CLASE_SUMINISTRO', 4, 'Instrumento', 'instrumento'),
-- Tipo (72)
(1, 72, 'TIPO_SUMINISTRO', 1, 'Instrumento de Laboratorio',  'instrumento_laboratorio'),
(1, 72, 'TIPO_SUMINISTRO', 2, 'Balanza Industrial',          'balanza_industrial'),
(1, 72, 'TIPO_SUMINISTRO', 3, 'Balanza de Precisión',        'balanza_precision'),
(1, 72, 'TIPO_SUMINISTRO', 4, 'Celda de Carga',              'celda_carga'),
(1, 72, 'TIPO_SUMINISTRO', 5, 'Indicador Digital',           'indicador_digital'),
(1, 72, 'TIPO_SUMINISTRO', 6, 'Pesa Patrón',                 'pesa_patron'),
(1, 72, 'TIPO_SUMINISTRO', 7, 'Mantenimiento y Calibración', 'mantenimiento_calibracion'),
-- Subtipo (73)
(1, 73, 'SUBTIPO_SUMINISTRO', 1, 'Estufa',                    'estufa'),
(1, 73, 'SUBTIPO_SUMINISTRO', 2, 'De Plataforma',             'de_plataforma'),
(1, 73, 'SUBTIPO_SUMINISTRO', 3, 'Bloque Patrón',             'bloque_patron'),
(1, 73, 'SUBTIPO_SUMINISTRO', 4, 'Celda 50T Canister',        'celda_50t'),
(1, 73, 'SUBTIPO_SUMINISTRO', 5, 'Indicador Alta Resolución', 'indicador_alta_res'),
(1, 73, 'SUBTIPO_SUMINISTRO', 6, 'Pesa Clase M1',             'pesa_clase_m1'),
(1, 73, 'SUBTIPO_SUMINISTRO', 7, 'Clase III - IIII',          'clase_iii_iiii'),
(1, 73, 'SUBTIPO_SUMINISTRO', 8, 'Balanza de Camiones',       'balanza_camiones'),
-- Procedencia (74)
(1, 74, 'PROCEDENCIA_SUMINISTRO', 1, 'Nacional',         'nacional'),
(1, 74, 'PROCEDENCIA_SUMINISTRO', 2, 'Importado',        'importado'),
(1, 74, 'PROCEDENCIA_SUMINISTRO', 3, 'Importado USA',    'importado_usa'),
(1, 74, 'PROCEDENCIA_SUMINISTRO', 4, 'Importado Japón',  'importado_japon'),
(1, 74, 'PROCEDENCIA_SUMINISTRO', 5, 'Importado Europa', 'importado_europa'),
(1, 74, 'PROCEDENCIA_SUMINISTRO', 6, 'Importado China',  'importado_china'),
(1, 74, 'PROCEDENCIA_SUMINISTRO', 7, 'Servicio',         'servicio'),
-- Unidad (75)
(1, 75, 'UNIDAD_SUMINISTRO', 1, 'Unidades (Bienes)',    'unidad_bienes'),
(1, 75, 'UNIDAD_SUMINISTRO', 2, 'Unidades (Servicios)', 'unidad_servicios'),
(1, 75, 'UNIDAD_SUMINISTRO', 3, 'N',                    'n'),
(1, 75, 'UNIDAD_SUMINISTRO', 4, 'Metro',                'metro'),
(1, 75, 'UNIDAD_SUMINISTRO', 5, 'Kilogramo',            'kilogramo');
