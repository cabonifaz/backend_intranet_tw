-- ============================================================
-- Migración 23 — HU-85: Mantenimiento de Textos Base
--   Tabla texto_base, historial de versiones, catálogo de
--   categorías (IdMaestro 70) y datos iniciales.
-- ============================================================

-- 1. Tabla principal
CREATE TABLE IF NOT EXISTS texto_base (
    id_texto_base                BIGINT       NOT NULL AUTO_INCREMENT,
    codigo_corto                 VARCHAR(40)  NOT NULL,
    tipo_categoria               VARCHAR(40)  NOT NULL,
    nombre                       VARCHAR(200) NOT NULL,
    texto_clausula               TEXT         NOT NULL,
    seccion_dossier              VARCHAR(20)  NULL,
    orden_aparicion              INT          NOT NULL DEFAULT 1,
    nivel_sangria                VARCHAR(20)  NOT NULL DEFAULT 'estandar',
    es_predeterminado            TINYINT(1)   NOT NULL DEFAULT 0,
    es_negrita_por_defecto       TINYINT(1)   NOT NULL DEFAULT 0,
    aplica_todos_servicios       TINYINT(1)   NOT NULL DEFAULT 0,
    aplica_calibracion_lab       TINYINT(1)   NOT NULL DEFAULT 0,
    aplica_calibracion_planta    TINYINT(1)   NOT NULL DEFAULT 0,
    aplica_mantenimiento         TINYINT(1)   NOT NULL DEFAULT 0,
    aplica_venta_suministros     TINYINT(1)   NOT NULL DEFAULT 0,
    visible_gestores_comerciales TINYINT(1)   NOT NULL DEFAULT 1,
    visible_tecnicos_metrologos  TINYINT(1)   NOT NULL DEFAULT 1,
    visible_supervisores         TINYINT(1)   NOT NULL DEFAULT 1,
    version                      INT          NOT NULL DEFAULT 1,
    estado                       ENUM('activo','inactivo','borrador') NOT NULL DEFAULT 'activo',
    id_usuario_creador           BIGINT       NULL,
    SoftDelete                   TINYINT(1)   NOT NULL DEFAULT 0,
    UsuCre                       VARCHAR(100) NULL,
    FchCre                       DATETIME     NULL,
    UsuMod                       VARCHAR(100) NULL,
    FchMod                       DATETIME     NULL,
    PRIMARY KEY (id_texto_base),
    KEY ix_texto_base_codigo (codigo_corto),
    KEY ix_texto_base_categoria (tipo_categoria)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- 2. Historial: copia del registro ANTES de cada edición
CREATE TABLE IF NOT EXISTS texto_base_version (
    id              BIGINT       NOT NULL AUTO_INCREMENT,
    id_texto_base   BIGINT       NOT NULL,
    version         INT          NOT NULL,
    datos           JSON         NOT NULL,
    UsuCre          VARCHAR(100) NULL,
    FchCre          DATETIME     NULL,
    PRIMARY KEY (id),
    KEY ix_tbv_texto (id_texto_base)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- 3. Catálogo de categorías (IdMaestro 70)
--    String1 = etiqueta, String2 = código (texto_base.tipo_categoria), String3 = prefijo de código
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2, String3) VALUES
(1, 70, 'CATEGORIA_TEXTO_BASE', 1, 'Servicio · Saludo',                          'servicio_saludo',  'TXT-SVC-SAL'),
(1, 70, 'CATEGORIA_TEXTO_BASE', 2, 'Comercial · Saludo',                         'comercial_saludo', 'TXT-COM-SAL'),
(1, 70, 'CATEGORIA_TEXTO_BASE', 3, 'Propuesta (Cláusulas generales de alcance)', 'propuesta',        'TXT-PROP-LOG'),
(1, 70, 'CATEGORIA_TEXTO_BASE', 4, 'Recomendaciones',                            'recomendaciones',  'TXT-REC'),
(1, 70, 'CATEGORIA_TEXTO_BASE', 5, 'Condiciones Comerciales',                    'condiciones',      'TXT-COND'),
(1, 70, 'CATEGORIA_TEXTO_BASE', 6, 'Garantía',                                   'garantia',         'TXT-GAR'),
(1, 70, 'CATEGORIA_TEXTO_BASE', 7, 'Cláusula Legal',                             'legal',            'TXT-LEG'),
(1, 70, 'CATEGORIA_TEXTO_BASE', 8, 'Firma / Pie de página',                      'firma_pie',        'TXT-FIRMA');

-- 4. Datos iniciales (textos del sistema actual, tomados del mock del front)
INSERT INTO texto_base (
    codigo_corto, tipo_categoria, nombre, texto_clausula, seccion_dossier, orden_aparicion, nivel_sangria,
    es_predeterminado, es_negrita_por_defecto,
    aplica_todos_servicios, aplica_calibracion_lab, aplica_calibracion_planta, aplica_mantenimiento, aplica_venta_suministros,
    visible_gestores_comerciales, visible_tecnicos_metrologos, visible_supervisores,
    estado, id_usuario_creador, UsuCre, FchCre
) VALUES
('TXT-SVC-SAL-01', 'servicio_saludo', 'Saludo',
 'Estimados Señores,\nPor medio de la presente reciban el cordial saludo de TOTAL WEIGHT & SYSTEMS S.A.C. y permítannos de acuerdo a su requerimiento, presentarles nuestra propuesta comercial.',
 'cap1', 1, 'estandar', 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 'activo', 1, 'migracion_23', NOW()),
('TXT-COM-SAL-01', 'comercial_saludo', 'Saludo',
 'Estimados Señores,\nPor medio de la presente reciban el cordial saludo de TOTAL WEIGHT & SYSTEMS S.A.C. y a su vez permítanos hacerles llegar nuestra cotización de acuerdo a su siguiente pedido.',
 'cap1', 2, 'estandar', 1, 0, 0, 0, 0, 0, 1, 1, 0, 1, 'activo', 1, 'migracion_23', NOW()),
('TXT-PROP-LOG-01', 'propuesta', 'Calibración',
 'Servicio de calibración por nuestro laboratorio acreditado TW SAC.',
 'cap2', 1, 'primer_nivel', 0, 1, 0, 1, 1, 0, 0, 1, 1, 1, 'activo', 1, 'migracion_23', NOW()),
('TXT-PROP-LOG-02', 'propuesta', 'Transporte',
 'Transporte de módulos desde taller de fabricación a lugar de instalación en planta {Cliente}.',
 'cap3', 2, 'primer_nivel', 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 'activo', 1, 'migracion_23', NOW()),
('TXT-PROP-LOG-03', 'propuesta', 'Jebe',
 '42 metros de jebes de protección tipo T para todo el perímetro de la balanza.',
 'cap4', 3, 'vineta', 0, 0, 0, 0, 0, 1, 1, 0, 1, 1, 'activo', 1, 'migracion_23', NOW()),
('TXT-PROP-LOG-04', 'propuesta', 'Piso',
 'Rotura de piso de concreto o asfalto, de existir el mismo en futura ubicación del sistema.',
 'cap5', 4, 'primer_nivel', 0, 0, 0, 0, 1, 0, 1, 0, 1, 1, 'activo', 1, 'migracion_23', NOW()),
('TXT-PROP-LOG-05', 'propuesta', 'Caseta',
 'Caseta de pesaje.',
 'cap5', 5, 'vineta', 0, 0, 0, 0, 0, 0, 1, 0, 1, 0, 'activo', 1, 'migracion_23', NOW()),
('TXT-REC-01', 'recomendaciones', 'Mantenimientos preventivos',
 'Considerar como mínimo dos (2) mantenimientos preventivos y correctivos al año para asegurar su correcta operatividad.',
 'cap6', 1, 'primer_nivel', 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 'activo', 1, 'migracion_23', NOW());
