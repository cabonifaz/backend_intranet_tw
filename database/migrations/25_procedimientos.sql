-- ============================================================
-- Migración 25 — HU-87: Mantenimiento de Procedimientos Metrológicos
--   Tabla nueva (procedimiento_tecnico se mantiene para la base de
--   conocimiento técnico), historial de versiones, catálogo de tipos
--   (IdMaestro 76) y datos iniciales.
-- ============================================================

-- 1. Tabla principal
CREATE TABLE IF NOT EXISTS procedimiento_metrologico (
    id_procedimiento       BIGINT       NOT NULL AUTO_INCREMENT,
    codigo                 VARCHAR(40)  NOT NULL,
    anio                   INT          NOT NULL,
    version                INT          NOT NULL DEFAULT 1,
    autor_norma            VARCHAR(150) NULL,
    norma_base             VARCHAR(200) NULL,
    tipo_procedimiento     VARCHAR(30)  NULL,
    descripcion            TEXT         NOT NULL,
    alcance                VARCHAR(300) NULL,
    aprobado_por           VARCHAR(200) NULL,
    es_formato_digital_iso TINYINT(1)   NOT NULL DEFAULT 0,
    url_pdf_aprobado       VARCHAR(500) NULL,
    estado                 ENUM('activo','inactivo','borrador') NOT NULL DEFAULT 'activo',
    total_ediciones        INT          NOT NULL DEFAULT 0,
    id_usuario_registro    BIGINT       NULL,
    pc_registro            VARCHAR(60)  NULL,
    SoftDelete             TINYINT(1)   NOT NULL DEFAULT 0,
    UsuCre                 VARCHAR(100) NULL,
    FchCre                 DATETIME     NULL,
    UsuMod                 VARCHAR(100) NULL,
    FchMod                 DATETIME     NULL,
    PRIMARY KEY (id_procedimiento),
    KEY ix_proc_codigo (codigo),
    KEY ix_proc_anio (anio)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- 2. Historial: copia del registro ANTES de cada edición
CREATE TABLE IF NOT EXISTS procedimiento_metrologico_version (
    id                BIGINT       NOT NULL AUTO_INCREMENT,
    id_procedimiento  BIGINT       NOT NULL,
    version           INT          NOT NULL,
    datos             JSON         NOT NULL,
    UsuCre            VARCHAR(100) NULL,
    FchCre            DATETIME     NULL,
    PRIMARY KEY (id),
    KEY ix_pmv_proc (id_procedimiento)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- 3. Catálogo de tipos de procedimiento (IdMaestro 76)
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2) VALUES
(1, 76, 'TIPO_PROCEDIMIENTO', 1, 'Calibración',   'calibracion'),
(1, 76, 'TIPO_PROCEDIMIENTO', 2, 'Verificación',  'verificacion'),
(1, 76, 'TIPO_PROCEDIMIENTO', 3, 'Mantenimiento', 'mantenimiento'),
(1, 76, 'TIPO_PROCEDIMIENTO', 4, 'Instalación',   'instalacion');

-- 4. Datos iniciales (procedimientos del sistema actual, con sus ids originales)
INSERT INTO procedimiento_metrologico (
    id_procedimiento, codigo, anio, version, autor_norma, norma_base, tipo_procedimiento,
    descripcion, alcance, aprobado_por, es_formato_digital_iso, estado,
    total_ediciones, id_usuario_registro, pc_registro, UsuCre, FchCre
) VALUES
(89,  'EDW-B-2', 2016, 1, 'ASTM International', 'ASTM E4 · ISO 7500', 'verificacion',
 'Standard Practice for Force Verification of Testing Machines.',
 'Hasta 1000 kN · Precisión clase 1', 'Ing. Ana Torres · Jefe de Metrología', 1, 'activo',
 0, NULL, 'migracion_25', 'migracion_25', '2016-05-14 09:00:00'),
(141, 'VJMDR', 2009, 2, 'INDECOPI', 'OIML R76-1 · NMP 002:2009', 'calibracion',
 'Procedimiento General para la Calibración de Balanzas de Funcionamiento No Automático.',
 '0 a 300 kg · Clase III y IIII', 'Dr. Luis Vargas · Director Técnico', 1, 'activo',
 0, NULL, 'migracion_25', 'migracion_25', '2009-11-30 09:00:00'),
(162, 'PA-A', 2015, 3, 'OIML', 'OIML R111-1:2004', 'calibracion',
 'Procedimiento para la calibración de pesas patrón clase E1, E2, F1 y F2.',
 '1 mg a 50 kg · Clase E1/E2/F1/F2', NULL, 1, 'activo',
 0, NULL, 'migracion_25', 'migracion_25', '2015-08-22 09:00:00');
