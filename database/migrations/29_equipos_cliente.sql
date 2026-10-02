-- ============================================================
-- Migración 29 — HU-88: Maestro de Equipos del Cliente
--   1) Nueva tabla equipo_cliente (independiente de la tabla
--      vieja `equipo` de la migración 01, que no cuadraba con el
--      modelo del front — modelo FK vs VARCHAR + catálogos nuevos).
--   2) Catálogos nuevos en tabla_maestra:
--        - CLASIFICACION_EQUIPO (IdMaestro 81)
--        - CLASE_EXACTITUD      (IdMaestro 82)
--        - ESTADO_OPERATIVO_EQUIPO (IdMaestro 83)
--   NOTA: ejecutar junto con los SPs SP_ObtenerEquiposCliente,
--   SP_ObtenerEquipoClientePorId, SP_GuardarEquipoCliente,
--   SP_CambiarEstadoEquipoCliente de este mismo batch, y
--   publicar el back inmediatamente después.
-- ============================================================

-- ── 1) Tabla equipo_cliente ──────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS equipo_cliente (
    id_equipo                 BIGINT       NOT NULL AUTO_INCREMENT,
    codigo_tw                 VARCHAR(30)  NOT NULL,   -- autogenerado: EQ-TW-YYYY-XXXX
    num_serie                 VARCHAR(80)  NOT NULL,
    id_cliente                BIGINT       NOT NULL,
    id_sede                   BIGINT       NOT NULL,
    codigo_cliente            VARCHAR(80)  NULL,
    clasificacion             VARCHAR(60)  NOT NULL,   -- String2 de CLASIFICACION_EQUIPO
    marca                     VARCHAR(80)  NOT NULL,
    modelo                    VARCHAR(80)  NOT NULL,

    -- 01 — Datos generales y ubicación
    ubicacion_especifica      VARCHAR(200) NULL,
    es_pre_revisado           TINYINT(1)   NOT NULL DEFAULT 0,
    usuario_pre_revisor       VARCHAR(150) NULL,
    fecha_pre_revision        DATETIME     NULL,
    bloqueado_para_servicios  TINYINT(1)   NOT NULL DEFAULT 0,

    -- 02 — Especificaciones metrológicas y técnicas
    id_suministro             BIGINT       NULL,       -- vinculación opcional a catalogo_item (HU-86)
    division_minima           VARCHAR(40)  NULL,
    division_verif            VARCHAR(40)  NULL,
    division_verif_igual      TINYINT(1)   NOT NULL DEFAULT 1,
    clase_exactitud           VARCHAR(10)  NULL,       -- String2 de CLASE_EXACTITUD
    alcance_maximo            VARCHAR(40)  NULL,
    escala_graduacion         VARCHAR(100) NULL,
    puntos_calibracion        VARCHAR(200) NULL,
    rango_operativo_real      VARCHAR(100) NULL,
    observaciones             TEXT         NULL,

    -- 03 — Estado operativo
    estado_operativo          VARCHAR(40)  NOT NULL,   -- String2 de ESTADO_OPERATIVO_EQUIPO
    es_activo                 TINYINT(1)   NOT NULL DEFAULT 1,

    -- Estado de registro (Activo / Inactivo / Borrador)
    estado                    ENUM('activo','inactivo','borrador') NOT NULL DEFAULT 'activo',

    -- Trazabilidad / auditoría
    usuario_registro          VARCHAR(150) NULL,
    pc_registro               VARCHAR(60)  NULL,

    SoftDelete                TINYINT(1)   NOT NULL DEFAULT 0,
    UsuCre                    VARCHAR(100) NULL,
    FchCre                    DATETIME     NULL,
    UsuMod                    VARCHAR(100) NULL,
    FchMod                    DATETIME     NULL,
    PRIMARY KEY (id_equipo)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ── 2) Catálogos en tabla_maestra ────────────────────────────────────────────

-- Clasificación de equipos (IdMaestro 81)
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2) VALUES
(1, 81, 'CLASIFICACION_EQUIPO',  1, 'Balanza de Plataforma Industrial',           'balanza_plataforma_industrial'),
(1, 81, 'CLASIFICACION_EQUIPO',  2, 'Báscula Camionera',                          'bascula_camionera'),
(1, 81, 'CLASIFICACION_EQUIPO',  3, 'Balanza de Precisión Analítica',             'balanza_precision_analitica'),
(1, 81, 'CLASIFICACION_EQUIPO',  4, 'Balanza Comercial de Sobremesa',             'balanza_comercial_sobremesa'),
(1, 81, 'CLASIFICACION_EQUIPO',  5, 'Tolva de Pesaje Industrial',                 'tolva_pesaje_industrial'),
(1, 81, 'CLASIFICACION_EQUIPO',  6, 'Balanza Dosificadora de Gancho / Grua',      'balanza_dosificador_gancho'),
(1, 81, 'CLASIFICACION_EQUIPO',  7, 'Balanza Colgante Etiquetadora Comercial',    'balanza_colgante_etiquetadora'),
(1, 81, 'CLASIFICACION_EQUIPO',  8, 'Balanza de Laboratorio',                     'balanza_laboratorio'),
(1, 81, 'CLASIFICACION_EQUIPO',  9, 'Pesa Patrón',                                'pesa_patron'),
(1, 81, 'CLASIFICACION_EQUIPO', 10, 'Indicador de Pesaje',                        'indicador_pesaje');

-- Clase de exactitud OIML (IdMaestro 82)
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2) VALUES
(1, 82, 'CLASE_EXACTITUD', 1, 'Clase I (Especial)',    'I'),
(1, 82, 'CLASE_EXACTITUD', 2, 'Clase II (Fina)',       'II'),
(1, 82, 'CLASE_EXACTITUD', 3, 'Clase III (Media)',     'III'),
(1, 82, 'CLASE_EXACTITUD', 4, 'Clase IIII (Ordinaria)','IIII');

-- Estado operativo del equipo (IdMaestro 83)
-- Num1 define el orden del timeline en el front (1 = primero).
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2) VALUES
(1, 83, 'ESTADO_OPERATIVO_EQUIPO', 1, 'En Oficina TW',        'oficina_tw'),
(1, 83, 'ESTADO_OPERATIVO_EQUIPO', 2, 'En Evaluación',        'evaluacion'),
(1, 83, 'ESTADO_OPERATIVO_EQUIPO', 3, 'En Ejecución',         'ejecucion'),
(1, 83, 'ESTADO_OPERATIVO_EQUIPO', 4, 'Operativo en Planta',  'operativo_planta');
