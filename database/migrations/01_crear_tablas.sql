-- ============================================================
-- TW-001 — Estructura de Datos — Total Weight Digital Suite
-- Base de datos: total_weight_stg
-- Versión: 2.3  |  Fecha: 2026-09-08
-- Motor: MySQL 8.0
-- 60 tablas — 7 capas + transversal
-- ============================================================
-- Convenciones:
--   · Sin FK ni UNIQUE declarados en DDL — integridad en SPs
--   · Soft delete: eliminado_en IS NOT NULL  =  registro dado de baja
--   · Bloque auditoría 6 campos al final de cada tabla
--   · Alias de tipos: ID=BIGINT AUTO_INCREMENT, BOOL=TINYINT(1), FILE=VARCHAR(500)
-- ============================================================

SET NAMES utf8mb4;

USE total_weight_stg;

-- ============================================================
-- DROP (orden inverso de dependencia — seguro porque no hay FKs)
-- ============================================================
DROP TABLE IF EXISTS token_acceso_publico;
DROP TABLE IF EXISTS exportacion_ergosoft;
DROP TABLE IF EXISTS descarga_documento;
DROP TABLE IF EXISTS procedimiento_tecnico;
DROP TABLE IF EXISTS sync_pendiente;
DROP TABLE IF EXISTS sesion_usuario;
DROP TABLE IF EXISTS notificacion;
DROP TABLE IF EXISTS ticket_soporte;
DROP TABLE IF EXISTS auditoria_evento;
DROP TABLE IF EXISTS documento_adjunto;
DROP TABLE IF EXISTS repuesto_instalado;
DROP TABLE IF EXISTS item_presalida;
DROP TABLE IF EXISTS alerta_predictiva;
DROP TABLE IF EXISTS contingencia_zero_device;
DROP TABLE IF EXISTS jornada_laboral;
DROP TABLE IF EXISTS incidencia_operativa;
DROP TABLE IF EXISTS gasto_viatico;
DROP TABLE IF EXISTS conformidad_digital;
DROP TABLE IF EXISTS evidencia_fotografica;
DROP TABLE IF EXISTS informe_tecnico;
DROP TABLE IF EXISTS medicion_metrologica;
DROP TABLE IF EXISTS variable_ambiental;
DROP TABLE IF EXISTS demora_registro;
DROP TABLE IF EXISTS evento_campo;
DROP TABLE IF EXISTS ssoma_documento;
DROP TABLE IF EXISTS oc_propuesta;
DROP TABLE IF EXISTS comision_comercial;
DROP TABLE IF EXISTS orden_compra;
DROP TABLE IF EXISTS seguimiento_comercial;
DROP TABLE IF EXISTS visto_bueno;
DROP TABLE IF EXISTS propuesta_item;
DROP TABLE IF EXISTS propuesta_comercial;
DROP TABLE IF EXISTS requerimiento;
DROP TABLE IF EXISTS ticket_metrologia;
DROP TABLE IF EXISTS precotizacion;
DROP TABLE IF EXISTS backlog_programacion;
DROP TABLE IF EXISTS om_equipo;
DROP TABLE IF EXISTS orden_metrologia;
DROP TABLE IF EXISTS os_equipo;
DROP TABLE IF EXISTS os_personal;
DROP TABLE IF EXISTS orden_servicio;
DROP TABLE IF EXISTS expediente_bloqueador;
DROP TABLE IF EXISTS expediente_digital;
DROP TABLE IF EXISTS configuracion_notificacion;
DROP TABLE IF EXISTS condicion_comercial;
DROP TABLE IF EXISTS plantilla_certificado;
DROP TABLE IF EXISTS requisito_ssoma_cliente;
DROP TABLE IF EXISTS contrato_marco;
DROP TABLE IF EXISTS catalogo_item;
DROP TABLE IF EXISTS tecnico_scorecard;
DROP TABLE IF EXISTS rol_permiso;
DROP TABLE IF EXISTS patron_medicion;
DROP TABLE IF EXISTS equipo_historial;
DROP TABLE IF EXISTS equipo;
DROP TABLE IF EXISTS contacto;
DROP TABLE IF EXISTS persona_contacto;
DROP TABLE IF EXISTS sede;
DROP TABLE IF EXISTS cliente;
DROP TABLE IF EXISTS usuario;
DROP TABLE IF EXISTS tabla_maestra;


-- ============================================================
-- CAPA 1 — MAESTRO DE MAESTROS (1 tabla)
-- ============================================================

CREATE TABLE tabla_maestra (
    IdTablaMaestra  INT             NOT NULL AUTO_INCREMENT,
    IdEmpresa       INT             NOT NULL DEFAULT 1,
    IdMaestro       INT             NOT NULL,
    Descripcion     VARCHAR(200)    NOT NULL,
    Num1            INT             NULL,
    Num2            DECIMAL(18,6)   NULL,
    Num3            DECIMAL(18,6)   NULL,
    String1         VARCHAR(255)    NULL,
    String2         VARCHAR(255)    NULL,
    String3         VARCHAR(255)    NULL,
    Date1           DATETIME        NULL,
    Date2           DATETIME        NULL,
    Date3           DATETIME        NULL,
    -- AUDITORÍA
    creado_en       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por      BIGINT          NULL,
    modificado_en   DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por  BIGINT          NULL,
    eliminado_en    DATETIME        NULL,
    eliminado_por   BIGINT          NULL,
    PRIMARY KEY (IdTablaMaestra)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- ============================================================
-- CAPA 3 — MAESTROS DE NEGOCIO (11 tablas)
-- usuario primero: bloque auditoría de todas las demás lo referencia
-- ============================================================

CREATE TABLE usuario (
    id_usuario          BIGINT          NOT NULL AUTO_INCREMENT,
    id_area             INT             NULL,
    numero_documento    VARCHAR(15)     NULL,
    id_tipo_doc_identidad INT           NULL,
    nombre              VARCHAR(100)    NOT NULL,
    apellido            VARCHAR(100)    NOT NULL,
    correo              VARCHAR(150)    NOT NULL,
    password_hash       VARCHAR(255)    NOT NULL,
    rol_sistema         VARCHAR(80)     NOT NULL,
    canal_acceso        ENUM('intranet','movil','extranet','todos') NOT NULL,
    id_persona_contacto BIGINT          NULL,
    estado              ENUM('activo','inactivo','suspendido') NOT NULL DEFAULT 'activo',
    ultimo_login        DATETIME        NULL,
    -- AUDITORÍA
    creado_en           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por          BIGINT          NULL,
    modificado_en       DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por      BIGINT          NULL,
    eliminado_en        DATETIME        NULL,
    eliminado_por       BIGINT          NULL,
    PRIMARY KEY (id_usuario)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE cliente (
    id_cliente          BIGINT          NOT NULL AUTO_INCREMENT,
    razon_social        VARCHAR(200)    NOT NULL,
    ruc                 VARCHAR(11)     NOT NULL,
    nombre_comercial    VARCHAR(150)    NULL,
    id_sector           INT             NULL,
    direccion_fiscal    VARCHAR(300)    NULL,
    linea_credito       DECIMAL(14,2)   NULL,
    estado              ENUM('activo','inactivo','suspendido') NOT NULL DEFAULT 'activo',
    notas_internas      TEXT            NULL,
    -- AUDITORÍA
    creado_en           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por          BIGINT          NULL,
    modificado_en       DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por      BIGINT          NULL,
    eliminado_en        DATETIME        NULL,
    eliminado_por       BIGINT          NULL,
    PRIMARY KEY (id_cliente)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE sede (
    id_sede             BIGINT          NOT NULL AUTO_INCREMENT,
    id_cliente          BIGINT          NOT NULL,
    nombre              VARCHAR(150)    NOT NULL,
    id_tipo_sede        INT             NULL,
    direccion           VARCHAR(250)    NOT NULL,
    distrito            VARCHAR(80)     NULL,
    provincia           VARCHAR(80)     NULL,
    departamento        VARCHAR(80)     NULL,
    pais                VARCHAR(50)     NOT NULL DEFAULT 'Perú',
    latitud             DECIMAL(10,7)   NULL,
    longitud            DECIMAL(10,7)   NULL,
    -- AUDITORÍA
    creado_en           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por          BIGINT          NULL,
    modificado_en       DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por      BIGINT          NULL,
    eliminado_en        DATETIME        NULL,
    eliminado_por       BIGINT          NULL,
    PRIMARY KEY (id_sede)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE persona_contacto (
    id_persona          BIGINT          NOT NULL AUTO_INCREMENT,
    nombre              VARCHAR(100)    NOT NULL,
    apellido            VARCHAR(100)    NOT NULL,
    correo              VARCHAR(150)    NOT NULL,
    numero_documento    VARCHAR(15)     NULL,
    id_tipo_doc         INT             NULL,
    telefono            VARCHAR(20)     NULL,
    -- AUDITORÍA
    creado_en           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por          BIGINT          NULL,
    modificado_en       DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por      BIGINT          NULL,
    eliminado_en        DATETIME        NULL,
    eliminado_por       BIGINT          NULL,
    PRIMARY KEY (id_persona)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE contacto (
    id_contacto         BIGINT          NOT NULL AUTO_INCREMENT,
    id_persona          BIGINT          NOT NULL,
    id_cliente          BIGINT          NOT NULL,
    cargo               VARCHAR(100)    NULL,
    id_rol_extranet     INT             NULL,
    activo              TINYINT(1)      NOT NULL DEFAULT 1,
    fecha_inicio        DATE            NULL,
    fecha_fin           DATE            NULL,
    -- AUDITORÍA
    creado_en           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por          BIGINT          NULL,
    modificado_en       DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por      BIGINT          NULL,
    eliminado_en        DATETIME        NULL,
    eliminado_por       BIGINT          NULL,
    PRIMARY KEY (id_contacto)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE equipo (
    id_equipo                   BIGINT          NOT NULL AUTO_INCREMENT,
    codigo_tw                   VARCHAR(20)     NOT NULL,
    id_cliente                  BIGINT          NOT NULL,
    id_sede                     BIGINT          NOT NULL,
    id_tipo_equipo              INT             NOT NULL,
    id_marca                    INT             NOT NULL,
    modelo                      VARCHAR(100)    NULL,
    numero_serie                VARCHAR(80)     NULL,
    alcance_min                 DECIMAL(12,4)   NULL,
    alcance_max                 DECIMAL(12,4)   NULL,
    ubicacion                   VARCHAR(200)    NULL,
    capacidad_maxima            DECIMAL(12,3)   NULL,
    id_unidad_capacidad         INT             NULL,
    division_e                  DECIMAL(12,4)   NULL,
    id_clase_metrologica        INT             NULL,
    tolerancia_mpe              DECIMAL(12,4)   NULL,
    id_estado_garantia          INT             NOT NULL,
    fecha_vencimiento_garantia  DATE            NULL,
    fecha_ultima_calibracion    DATE            NULL,
    fecha_proxima_calibracion   DATE            NULL,
    estado_operativo            ENUM('activo','observado','fuera_servicio','baja') NOT NULL DEFAULT 'activo',
    url_qr                      VARCHAR(500)    NULL,
    notas                       TEXT            NULL,
    -- AUDITORÍA
    creado_en                   DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por                  BIGINT          NULL,
    modificado_en               DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por              BIGINT          NULL,
    eliminado_en                DATETIME        NULL,
    eliminado_por               BIGINT          NULL,
    PRIMARY KEY (id_equipo)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- INSERT-ONLY: sin bloque auditoría (es el trail de auditoría del equipo)
CREATE TABLE equipo_historial (
    id_historial        BIGINT          NOT NULL AUTO_INCREMENT,
    id_equipo           BIGINT          NOT NULL,
    campo_modificado    VARCHAR(80)     NOT NULL,
    valor_anterior      VARCHAR(300)    NULL,
    valor_nuevo         VARCHAR(300)    NOT NULL,
    motivo              TEXT            NULL,
    registrado_por      BIGINT          NOT NULL,
    registrado_en       DATETIME        NOT NULL,
    PRIMARY KEY (id_historial)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE patron_medicion (
    id_patron                   BIGINT          NOT NULL AUTO_INCREMENT,
    codigo_interno              VARCHAR(30)     NOT NULL,
    nombre                      VARCHAR(100)    NOT NULL,
    tipo                        VARCHAR(50)     NOT NULL,
    numero_serie                VARCHAR(80)     NULL,
    id_clase                    INT             NULL,
    capacidad_maxima            DECIMAL(12,3)   NULL,
    id_unidad                   INT             NULL,
    numero_certificado          VARCHAR(50)     NULL,
    fecha_vencimiento_cert      DATE            NULL,
    id_estado                   INT             NOT NULL,
    -- AUDITORÍA
    creado_en                   DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por                  BIGINT          NULL,
    modificado_en               DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por              BIGINT          NULL,
    eliminado_en                DATETIME        NULL,
    eliminado_por               BIGINT          NULL,
    PRIMARY KEY (id_patron)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE rol_permiso (
    id                  BIGINT          NOT NULL AUTO_INCREMENT,
    rol_sistema         VARCHAR(80)     NOT NULL,
    id_permiso          INT             NOT NULL,
    -- AUDITORÍA
    creado_en           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por          BIGINT          NULL,
    modificado_en       DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por      BIGINT          NULL,
    eliminado_en        DATETIME        NULL,
    eliminado_por       BIGINT          NULL,
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE tecnico_scorecard (
    id_scorecard                    BIGINT          NOT NULL AUTO_INCREMENT,
    id_usuario                      BIGINT          NOT NULL,
    periodo_mes                     DATE            NOT NULL,
    servicios_asignados             INT             NOT NULL DEFAULT 0,
    servicios_completados           INT             NOT NULL DEFAULT 0,
    tasa_completitud_pct            DECIMAL(5,2)    NULL,
    tiempo_promedio_llegada_min     INT             NULL,
    informes_observados             INT             NOT NULL DEFAULT 0,
    incidencias_registradas         INT             NOT NULL DEFAULT 0,
    score_general                   DECIMAL(5,2)    NULL,
    nivel                           ENUM('optimo','bueno','regular','bajo') NULL,
    foto_override_count             INT             NOT NULL DEFAULT 0,
    cumplimiento_jornada_pct        DECIMAL(5,2)    NULL,
    tiempo_promedio_cierre_min      INT             NULL,
    -- AUDITORÍA
    creado_en                       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por                      BIGINT          NULL,
    modificado_en                   DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por                  BIGINT          NULL,
    eliminado_en                    DATETIME        NULL,
    eliminado_por                   BIGINT          NULL,
    PRIMARY KEY (id_scorecard)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE catalogo_item (
    id_catalogo_item    BIGINT          NOT NULL AUTO_INCREMENT,
    codigo              VARCHAR(30)     NOT NULL,
    descripcion         VARCHAR(300)    NOT NULL,
    id_tipo_item        INT             NOT NULL,
    id_tipo_servicio    INT             NULL,
    id_tipo_equipo      INT             NULL,
    precio_referencia   DECIMAL(12,2)   NULL,
    id_moneda           INT             NOT NULL,
    unidad_medida       VARCHAR(30)     NULL,
    activo              TINYINT(1)      NOT NULL DEFAULT 1,
    -- AUDITORÍA
    creado_en           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por          BIGINT          NULL,
    modificado_en       DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por      BIGINT          NULL,
    eliminado_en        DATETIME        NULL,
    eliminado_por       BIGINT          NULL,
    PRIMARY KEY (id_catalogo_item)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- ============================================================
-- CAPA 2 — CONFIGURACIÓN (5 tablas)
-- ============================================================

CREATE TABLE requisito_ssoma_cliente (
    id                  BIGINT          NOT NULL AUTO_INCREMENT,
    id_requisito        INT             NOT NULL,
    id_cliente          BIGINT          NULL,
    id_sede             BIGINT          NULL,
    id_tipo_servicio    INT             NULL,
    es_obligatorio      TINYINT(1)      NOT NULL DEFAULT 1,
    bloquea_servicio    TINYINT(1)      NOT NULL DEFAULT 1,
    -- AUDITORÍA
    creado_en           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por          BIGINT          NULL,
    modificado_en       DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por      BIGINT          NULL,
    eliminado_en        DATETIME        NULL,
    eliminado_por       BIGINT          NULL,
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE condicion_comercial (
    id_condicion        BIGINT          NOT NULL AUTO_INCREMENT,
    titulo              VARCHAR(150)    NOT NULL,
    cuerpo              TEXT            NOT NULL,
    id_tipo_formato     INT             NOT NULL,
    es_base             TINYINT(1)      NOT NULL DEFAULT 1,
    -- AUDITORÍA
    creado_en           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por          BIGINT          NULL,
    modificado_en       DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por      BIGINT          NULL,
    eliminado_en        DATETIME        NULL,
    eliminado_por       BIGINT          NULL,
    PRIMARY KEY (id_condicion)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE plantilla_certificado (
    id_plantilla        BIGINT          NOT NULL AUTO_INCREMENT,
    nombre              VARCHAR(100)    NOT NULL,
    id_tipo_servicio    INT             NULL,
    url_plantilla       VARCHAR(500)    NOT NULL,
    -- AUDITORÍA
    creado_en           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por          BIGINT          NULL,
    modificado_en       DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por      BIGINT          NULL,
    eliminado_en        DATETIME        NULL,
    eliminado_por       BIGINT          NULL,
    PRIMARY KEY (id_plantilla)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE configuracion_notificacion (
    id_config           BIGINT          NOT NULL AUTO_INCREMENT,
    id_usuario          BIGINT          NOT NULL,
    evento              VARCHAR(80)     NOT NULL,
    id_canal            INT             NOT NULL,
    -- AUDITORÍA
    creado_en           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por          BIGINT          NULL,
    modificado_en       DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por      BIGINT          NULL,
    eliminado_en        DATETIME        NULL,
    eliminado_por       BIGINT          NULL,
    PRIMARY KEY (id_config)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE contrato_marco (
    id_contrato             BIGINT          NOT NULL AUTO_INCREMENT,
    numero                  VARCHAR(20)     NOT NULL,
    id_cliente              BIGINT          NOT NULL,
    descripcion             VARCHAR(300)    NULL,
    fecha_inicio            DATE            NOT NULL,
    fecha_fin               DATE            NULL,
    monto_total             DECIMAL(14,2)   NULL,
    id_moneda               INT             NULL,
    condiciones_especiales  TEXT            NULL,
    url_documento           VARCHAR(500)    NULL,
    estado                  ENUM('vigente','vencido','suspendido','anulado') NOT NULL DEFAULT 'vigente',
    -- AUDITORÍA
    creado_en               DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por              BIGINT          NULL,
    modificado_en           DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por          BIGINT          NULL,
    eliminado_en            DATETIME        NULL,
    eliminado_por           BIGINT          NULL,
    PRIMARY KEY (id_contrato)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- ============================================================
-- CAPA 5 — CORE 2 COMERCIAL (8 tablas)
-- Antes que Capa 4: expediente_digital referencia requerimiento y propuesta
-- ============================================================

CREATE TABLE requerimiento (
    id_requerimiento    BIGINT          NOT NULL AUTO_INCREMENT,
    numero              VARCHAR(20)     NOT NULL,
    id_cliente          BIGINT          NOT NULL,
    id_contacto         BIGINT          NULL,
    id_origen           INT             NOT NULL,
    id_area             INT             NULL,
    id_prioridad        INT             NOT NULL,
    descripcion         TEXT            NOT NULL,
    estado              ENUM('nuevo','en_proceso','con_propuesta','cerrado','anulado') NOT NULL DEFAULT 'nuevo',
    id_usuario_creador  BIGINT          NOT NULL,
    id_ejecutivo        BIGINT          NULL,
    fecha_creacion      DATETIME        NOT NULL,
    fecha_cierre        DATETIME        NULL,
    es_inacal           TINYINT(1)      NOT NULL DEFAULT 0,
    -- AUDITORÍA
    creado_en           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por          BIGINT          NULL,
    modificado_en       DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por      BIGINT          NULL,
    eliminado_en        DATETIME        NULL,
    eliminado_por       BIGINT          NULL,
    PRIMARY KEY (id_requerimiento)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE propuesta_comercial (
    id_propuesta            BIGINT          NOT NULL AUTO_INCREMENT,
    numero                  VARCHAR(20)     NOT NULL,
    version                 INT             NOT NULL DEFAULT 1,
    id_requerimiento        BIGINT          NOT NULL,
    id_cliente              BIGINT          NOT NULL,
    id_moneda               INT             NOT NULL,
    subtotal                DECIMAL(14,2)   NOT NULL DEFAULT 0,
    descuento_monto         DECIMAL(14,2)   NOT NULL DEFAULT 0,
    descuento_pct           DECIMAL(5,2)    NULL,
    id_motivo_descuento     INT             NULL,
    igv_pct                 DECIMAL(5,2)    NOT NULL DEFAULT 18.00,
    igv_monto               DECIMAL(14,2)   NOT NULL DEFAULT 0,
    total                   DECIMAL(14,2)   NOT NULL DEFAULT 0,
    aplica_igv              TINYINT(1)      NOT NULL DEFAULT 1,
    plazo_entrega_dias      INT             NULL,
    vigencia_dias           INT             NULL,
    id_condicion_pago       INT             NULL,
    introduccion            TEXT            NULL,
    notas_generales         TEXT            NULL,
    estado                  ENUM('borrador','pendiente_vb','enviado','aprobado','rechazado','anulado','vencido') NOT NULL DEFAULT 'borrador',
    id_propuesta_padre      BIGINT          NULL,
    id_motivo_nueva_version INT             NULL,
    id_creador              BIGINT          NOT NULL,
    fecha_creacion          DATETIME        NOT NULL,
    fecha_envio             DATETIME        NULL,
    fecha_expiracion        DATE            NULL,
    url_pdf                 VARCHAR(500)    NULL,
    -- AUDITORÍA
    creado_en               DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por              BIGINT          NULL,
    modificado_en           DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por          BIGINT          NULL,
    eliminado_en            DATETIME        NULL,
    eliminado_por           BIGINT          NULL,
    PRIMARY KEY (id_propuesta)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE propuesta_item (
    id_item             BIGINT          NOT NULL AUTO_INCREMENT,
    id_propuesta        BIGINT          NOT NULL,
    id_tipo_servicio    INT             NULL,
    descripcion         VARCHAR(300)    NOT NULL,
    cantidad            DECIMAL(10,2)   NOT NULL,
    id_catalogo_item    BIGINT          NULL,
    precio_unitario     DECIMAL(12,2)   NOT NULL,
    subtotal            DECIMAL(14,2)   NOT NULL,
    orden               INT             NOT NULL DEFAULT 1,
    -- AUDITORÍA
    creado_en           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por          BIGINT          NULL,
    modificado_en       DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por      BIGINT          NULL,
    eliminado_en        DATETIME        NULL,
    eliminado_por       BIGINT          NULL,
    PRIMARY KEY (id_item)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE visto_bueno (
    id_vb               BIGINT          NOT NULL AUTO_INCREMENT,
    id_propuesta        BIGINT          NOT NULL,
    id_aprobador        BIGINT          NOT NULL,
    estado              ENUM('pendiente','aprobado','rechazado','reasignado') NOT NULL DEFAULT 'pendiente',
    comentario          TEXT            NULL,
    sla_horas           INT             NOT NULL,
    fecha_solicitud     DATETIME        NOT NULL,
    fecha_respuesta     DATETIME        NULL,
    url_firma_imagen    VARCHAR(500)    NULL,
    -- AUDITORÍA
    creado_en           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por          BIGINT          NULL,
    modificado_en       DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por      BIGINT          NULL,
    eliminado_en        DATETIME        NULL,
    eliminado_por       BIGINT          NULL,
    PRIMARY KEY (id_vb)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE seguimiento_comercial (
    id_seguimiento          BIGINT          NOT NULL AUTO_INCREMENT,
    id_propuesta            BIGINT          NOT NULL,
    id_responsable          BIGINT          NOT NULL,
    id_canal                INT             NOT NULL,
    id_resultado            INT             NULL,
    notas                   TEXT            NULL,
    estado                  ENUM('activo','cerrado_aceptacion','cerrado_rechazo','cerrado_sin_venta') NOT NULL,
    id_motivo_cierre        INT             NULL,
    fecha_interaccion       DATETIME        NOT NULL,
    proxima_accion_fecha    DATETIME        NULL,
    id_prioridad_accion     INT             NULL,
    permite_reactivacion    TINYINT(1)      NOT NULL DEFAULT 0,
    -- AUDITORÍA
    creado_en               DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por              BIGINT          NULL,
    modificado_en           DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por          BIGINT          NULL,
    eliminado_en            DATETIME        NULL,
    eliminado_por           BIGINT          NULL,
    PRIMARY KEY (id_seguimiento)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE orden_compra (
    id_oc                   BIGINT          NOT NULL AUTO_INCREMENT,
    numero_oc               VARCHAR(50)     NOT NULL,
    id_propuesta            BIGINT          NULL,
    id_cliente              BIGINT          NOT NULL,
    id_moneda               INT             NOT NULL,
    monto_total             DECIMAL(14,2)   NOT NULL,
    monto_aplicado          DECIMAL(14,2)   NOT NULL DEFAULT 0,
    saldo                   DECIMAL(14,2)   NOT NULL,
    cobertura_pct           DECIMAL(5,2)    NOT NULL,
    fecha_oc                DATE            NOT NULL,
    fecha_recepcion         DATE            NOT NULL,
    vigencia_desde          DATE            NULL,
    vigencia_hasta          DATE            NULL,
    url_archivo_pdf         VARCHAR(500)    NULL,
    estado                  ENUM('pendiente_validacion','vigente','cobertura_parcial','saldo_insuficiente','vencida','anulada') NOT NULL,
    id_motivo_observacion   INT             NULL,
    id_validado_por         BIGINT          NULL,
    fecha_registro          DATETIME        NOT NULL,
    -- AUDITORÍA
    creado_en               DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por              BIGINT          NULL,
    modificado_en           DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por          BIGINT          NULL,
    eliminado_en            DATETIME        NULL,
    eliminado_por           BIGINT          NULL,
    PRIMARY KEY (id_oc)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE comision_comercial (
    id_comision             BIGINT          NOT NULL AUTO_INCREMENT,
    id_propuesta            BIGINT          NOT NULL,
    id_orden_compra         BIGINT          NOT NULL,
    id_ejecutivo            BIGINT          NOT NULL,
    id_moneda               INT             NOT NULL,
    monto_base              DECIMAL(14,2)   NOT NULL,
    porcentaje_comision     DECIMAL(5,2)    NOT NULL,
    monto_comision          DECIMAL(14,2)   NOT NULL,
    estado                  ENUM('pendiente','aprobada','pagada','rechazada') NOT NULL DEFAULT 'pendiente',
    fecha_devengado         DATE            NOT NULL,
    fecha_pago              DATE            NULL,
    aprobado_por            BIGINT          NULL,
    notas                   TEXT            NULL,
    -- AUDITORÍA
    creado_en               DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por              BIGINT          NULL,
    modificado_en           DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por          BIGINT          NULL,
    eliminado_en            DATETIME        NULL,
    eliminado_por           BIGINT          NULL,
    PRIMARY KEY (id_comision)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE oc_propuesta (
    id                  BIGINT          NOT NULL AUTO_INCREMENT,
    id_oc               BIGINT          NOT NULL,
    id_propuesta        BIGINT          NOT NULL,
    monto_asignado      DECIMAL(14,2)   NOT NULL,
    -- AUDITORÍA
    creado_en           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por          BIGINT          NULL,
    modificado_en       DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por      BIGINT          NULL,
    eliminado_en        DATETIME        NULL,
    eliminado_por       BIGINT          NULL,
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- ============================================================
-- CAPA 4 — CORE 1 OPERATIVO (10 tablas)
-- ============================================================

CREATE TABLE expediente_digital (
    id_expediente           BIGINT          NOT NULL AUTO_INCREMENT,
    numero                  VARCHAR(20)     NOT NULL,
    id_requerimiento        BIGINT          NULL,
    id_propuesta            BIGINT          NULL,
    id_orden_compra         BIGINT          NULL,
    etapa_actual            ENUM('requerimiento','propuesta','visto_bueno','orden_compra','programacion','ssoma','ejecucion','revision','conformidad','facturacion','cerrado') NOT NULL,
    estado                  ENUM('activo','listo_para_avanzar','bloqueado','con_excepcion','sla_vencido','cerrado') NOT NULL,
    id_responsable_actual   BIGINT          NULL,
    fecha_creacion          DATETIME        NOT NULL,
    fecha_cierre            DATETIME        NULL,
    -- AUDITORÍA
    creado_en               DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por              BIGINT          NULL,
    modificado_en           DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por          BIGINT          NULL,
    eliminado_en            DATETIME        NULL,
    eliminado_por           BIGINT          NULL,
    PRIMARY KEY (id_expediente)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE expediente_bloqueador (
    id_bloqueador       BIGINT          NOT NULL AUTO_INCREMENT,
    id_expediente       BIGINT          NOT NULL,
    descripcion         VARCHAR(300)    NOT NULL,
    tipo                ENUM('documento_faltante','ssoma','cobertura_oc','sin_aprobacion','otro') NOT NULL,
    resuelto            TINYINT(1)      NOT NULL DEFAULT 0,
    fecha_resolucion    DATETIME        NULL,
    -- AUDITORÍA
    creado_en           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por          BIGINT          NULL,
    modificado_en       DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por      BIGINT          NULL,
    eliminado_en        DATETIME        NULL,
    eliminado_por       BIGINT          NULL,
    PRIMARY KEY (id_bloqueador)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE orden_servicio (
    id_os                       BIGINT          NOT NULL AUTO_INCREMENT,
    numero                      VARCHAR(20)     NOT NULL,
    id_expediente               BIGINT          NOT NULL,
    id_cliente                  BIGINT          NOT NULL,
    id_sede                     BIGINT          NOT NULL,
    id_tipo_servicio            INT             NOT NULL,
    id_tecnico_principal        BIGINT          NULL,
    fecha_ejecucion             DATE            NOT NULL,
    hora_inicio                 TIME            NOT NULL,
    hora_fin_estimada           TIME            NULL,
    hora_llegada_real           TIME            NULL,
    hora_fin_real               TIME            NULL,
    costo_total_estimado        DECIMAL(12,2)   NULL,
    latitud_llegada             DECIMAL(10,7)   NULL,
    longitud_llegada            DECIMAL(10,7)   NULL,
    estado                      ENUM('programada','en_ruta','en_ejecucion','pausada','finalizada','reprogramada','anulada','bloqueada') NOT NULL DEFAULT 'programada',
    confirmacion_cliente        TINYINT(1)      NOT NULL DEFAULT 0,
    id_canal_confirmacion       INT             NULL,
    id_contacto_confirma        BIGINT          NULL,
    fecha_confirmacion_cliente  DATETIME        NULL,
    notas_operativas            TEXT            NULL,
    fecha_creacion              DATETIME        NOT NULL,
    -- AUDITORÍA
    creado_en                   DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por                  BIGINT          NULL,
    modificado_en               DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por              BIGINT          NULL,
    eliminado_en                DATETIME        NULL,
    eliminado_por               BIGINT          NULL,
    PRIMARY KEY (id_os)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE os_personal (
    id                  BIGINT          NOT NULL AUTO_INCREMENT,
    id_os               BIGINT          NOT NULL,
    id_usuario          BIGINT          NOT NULL,
    rol_en_servicio     VARCHAR(80)     NOT NULL,
    estado_ssoma        ENUM('habilitado','pendiente','bloqueado') NOT NULL,
    -- AUDITORÍA
    creado_en           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por          BIGINT          NULL,
    modificado_en       DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por      BIGINT          NULL,
    eliminado_en        DATETIME        NULL,
    eliminado_por       BIGINT          NULL,
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE os_equipo (
    id                      BIGINT          NOT NULL AUTO_INCREMENT,
    id_os                   BIGINT          NOT NULL,
    id_equipo               BIGINT          NOT NULL,
    id_tipo_intervencion    INT             NOT NULL,
    ingresado_en_campo      TINYINT(1)      NOT NULL DEFAULT 0,
    -- AUDITORÍA
    creado_en               DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por              BIGINT          NULL,
    modificado_en           DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por          BIGINT          NULL,
    eliminado_en            DATETIME        NULL,
    eliminado_por           BIGINT          NULL,
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE orden_metrologia (
    id_om                       BIGINT          NOT NULL AUTO_INCREMENT,
    numero                      VARCHAR(20)     NOT NULL,
    id_expediente               BIGINT          NOT NULL,
    id_os                       BIGINT          NULL,
    id_cliente                  BIGINT          NOT NULL,
    id_sede                     BIGINT          NOT NULL,
    id_metrologo                BIGINT          NULL,
    id_metodo                   INT             NOT NULL,
    id_patron                   BIGINT          NOT NULL,
    id_norma                    INT             NOT NULL,
    id_origen                   INT             NOT NULL,
    fecha_calibracion           DATE            NULL,
    id_resultado                INT             NULL,
    estado                      ENUM('activa','en_calibracion','pendiente_certificado','patron_vencido','finalizada','anulada') NOT NULL,
    numero_certificado          VARCHAR(50)     NULL,
    fecha_emision_certificado   DATE            NULL,
    id_plantilla_certificado    BIGINT          NULL,
    url_certificado_pdf         VARCHAR(500)    NULL,
    fecha_creacion              DATETIME        NOT NULL,
    -- AUDITORÍA
    creado_en                   DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por                  BIGINT          NULL,
    modificado_en               DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por              BIGINT          NULL,
    eliminado_en                DATETIME        NULL,
    eliminado_por               BIGINT          NULL,
    PRIMARY KEY (id_om)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE om_equipo (
    id          BIGINT          NOT NULL AUTO_INCREMENT,
    id_om       BIGINT          NOT NULL,
    id_equipo   BIGINT          NOT NULL,
    orden       INT             NOT NULL DEFAULT 1,
    -- AUDITORÍA
    creado_en       DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por      BIGINT      NULL,
    modificado_en   DATETIME    NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por  BIGINT      NULL,
    eliminado_en    DATETIME    NULL,
    eliminado_por   BIGINT      NULL,
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE backlog_programacion (
    id_backlog              BIGINT          NOT NULL AUTO_INCREMENT,
    id_expediente           BIGINT          NOT NULL,
    id_os                   BIGINT          NULL,
    id_om                   BIGINT          NULL,
    id_prioridad            INT             NOT NULL,
    id_tecnico_sugerido     BIGINT          NULL,
    fecha_limite            DATE            NOT NULL,
    estado                  ENUM('pendiente','asignado','reprogramado','cancelado') NOT NULL DEFAULT 'pendiente',
    notas_programacion      TEXT            NULL,
    -- AUDITORÍA
    creado_en               DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por              BIGINT          NULL,
    modificado_en           DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por          BIGINT          NULL,
    eliminado_en            DATETIME        NULL,
    eliminado_por           BIGINT          NULL,
    PRIMARY KEY (id_backlog)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE precotizacion (
    id_precotizacion        BIGINT          NOT NULL AUTO_INCREMENT,
    numero                  VARCHAR(20)     NOT NULL,
    id_requerimiento        BIGINT          NULL,
    id_cliente              BIGINT          NOT NULL,
    id_creador              BIGINT          NOT NULL,
    id_tipo_servicio        INT             NOT NULL,
    descripcion_servicio    TEXT            NOT NULL,
    id_moneda               INT             NOT NULL,
    monto_estimado_min      DECIMAL(14,2)   NULL,
    monto_estimado_max      DECIMAL(14,2)   NULL,
    estado                  ENUM('borrador','enviado','aceptado','rechazado','convertido_propuesta') NOT NULL DEFAULT 'borrador',
    id_propuesta_generada   BIGINT          NULL,
    fecha_creacion          DATETIME        NOT NULL,
    -- AUDITORÍA
    creado_en               DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por              BIGINT          NULL,
    modificado_en           DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por          BIGINT          NULL,
    eliminado_en            DATETIME        NULL,
    eliminado_por           BIGINT          NULL,
    PRIMARY KEY (id_precotizacion)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE ticket_metrologia (
    id_ticket_met           BIGINT          NOT NULL AUTO_INCREMENT,
    numero                  VARCHAR(20)     NOT NULL,
    id_os                   BIGINT          NOT NULL,
    id_om                   BIGINT          NULL,
    id_tecnico_solicitante  BIGINT          NOT NULL,
    id_metrologo_asignado   BIGINT          NULL,
    correlativo_asignado    VARCHAR(50)     NULL,
    estado                  ENUM('solicitado','asignado','despachado','cancelado') NOT NULL DEFAULT 'solicitado',
    notas                   TEXT            NULL,
    fecha_solicitud         DATETIME        NOT NULL,
    fecha_asignacion        DATETIME        NULL,
    -- AUDITORÍA
    creado_en               DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por              BIGINT          NULL,
    modificado_en           DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por          BIGINT          NULL,
    eliminado_en            DATETIME        NULL,
    eliminado_por           BIGINT          NULL,
    PRIMARY KEY (id_ticket_met)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- ============================================================
-- CAPA 6 — EJECUCIÓN DE CAMPO (15 tablas)
-- ============================================================

CREATE TABLE ssoma_documento (
    id_ssoma_doc        BIGINT          NOT NULL AUTO_INCREMENT,
    id_os               BIGINT          NOT NULL,
    id_usuario          BIGINT          NOT NULL,
    id_requisito        INT             NOT NULL,
    url_archivo         VARCHAR(500)    NULL,
    estado              ENUM('pendiente','cargado','aprobado','observado','vencido') NOT NULL,
    fecha_vencimiento   DATE            NULL,
    motivo_observacion  TEXT            NULL,
    aprobado_por        BIGINT          NULL,
    version             INT             NOT NULL DEFAULT 1,
    fecha_carga         DATETIME        NOT NULL,
    -- AUDITORÍA
    creado_en           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por          BIGINT          NULL,
    modificado_en       DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por      BIGINT          NULL,
    eliminado_en        DATETIME        NULL,
    eliminado_por       BIGINT          NULL,
    PRIMARY KEY (id_ssoma_doc)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE evento_campo (
    id_evento           BIGINT          NOT NULL AUTO_INCREMENT,
    id_os               BIGINT          NOT NULL,
    id_usuario          BIGINT          NOT NULL,
    id_tipo_evento      INT             NOT NULL,
    latitud             DECIMAL(10,7)   NULL,
    longitud            DECIMAL(10,7)   NULL,
    timestamp_utc       DATETIME        NOT NULL,
    sincronizado        TINYINT(1)      NOT NULL DEFAULT 0,
    notas               TEXT            NULL,
    -- AUDITORÍA
    creado_en           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por          BIGINT          NULL,
    modificado_en       DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por      BIGINT          NULL,
    eliminado_en        DATETIME        NULL,
    eliminado_por       BIGINT          NULL,
    PRIMARY KEY (id_evento)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE demora_registro (
    id_demora           BIGINT          NOT NULL AUTO_INCREMENT,
    id_os               BIGINT          NOT NULL,
    id_usuario          BIGINT          NOT NULL,
    id_motivo           INT             NOT NULL,
    descripcion         TEXT            NULL,
    duracion_minutos    INT             NULL,
    fotografia_url      VARCHAR(500)    NULL,
    fecha_registro      DATETIME        NOT NULL,
    -- AUDITORÍA
    creado_en           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por          BIGINT          NULL,
    modificado_en       DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por      BIGINT          NULL,
    eliminado_en        DATETIME        NULL,
    eliminado_por       BIGINT          NULL,
    PRIMARY KEY (id_demora)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE variable_ambiental (
    id_variable         BIGINT          NOT NULL AUTO_INCREMENT,
    id_om               BIGINT          NOT NULL,
    id_usuario          BIGINT          NOT NULL,
    temperatura_c       DECIMAL(6,2)    NULL,
    humedad_pct         DECIMAL(5,2)    NULL,
    presion_hpa         DECIMAL(8,2)    NULL,
    latitud             DECIMAL(10,7)   NULL,
    longitud            DECIMAL(10,7)   NULL,
    registrado_en       DATETIME        NOT NULL,
    -- AUDITORÍA
    creado_en           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por          BIGINT          NULL,
    modificado_en       DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por      BIGINT          NULL,
    eliminado_en        DATETIME        NULL,
    eliminado_por       BIGINT          NULL,
    PRIMARY KEY (id_variable)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE medicion_metrologica (
    id_medicion             BIGINT          NOT NULL AUTO_INCREMENT,
    id_om                   BIGINT          NOT NULL,
    id_equipo               BIGINT          NOT NULL,
    id_tipo_prueba          INT             NOT NULL,
    numero_prueba           INT             NOT NULL,
    carga_aplicada          DECIMAL(12,4)   NOT NULL,
    lectura_instrumento     DECIMAL(12,4)   NOT NULL,
    error                   DECIMAL(12,4)   NOT NULL,
    incertidumbre           DECIMAL(12,4)   NULL,
    tolerancia_mpe          DECIMAL(12,4)   NULL,
    resultado               ENUM('cumple','no_cumple') NOT NULL,
    u_patron                DECIMAL(12,4)   NULL,
    u_combinada             DECIMAL(12,4)   NULL,
    factor_k                DECIMAL(4,2)    NULL,
    u_expandida             DECIMAL(12,4)   NULL,
    -- AUDITORÍA
    creado_en               DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por              BIGINT          NULL,
    modificado_en           DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por          BIGINT          NULL,
    eliminado_en            DATETIME        NULL,
    eliminado_por           BIGINT          NULL,
    PRIMARY KEY (id_medicion)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE informe_tecnico (
    id_informe                  BIGINT          NOT NULL AUTO_INCREMENT,
    numero                      VARCHAR(20)     NOT NULL,
    id_os                       BIGINT          NULL,
    id_om                       BIGINT          NULL,
    id_equipo                   BIGINT          NULL,
    equipo_snapshot             JSON            NULL,
    id_tecnico                  BIGINT          NOT NULL,
    id_revisor                  BIGINT          NULL,
    diagnostico_principal       TEXT            NULL,
    hallazgos                   TEXT            NULL,
    datos_reporte               JSON            NULL,
    estado                      ENUM('borrador','pendiente_revision','en_revision','observado','aprobado') NOT NULL,
    version                     INT             NOT NULL DEFAULT 1,
    id_informe_padre            BIGINT          NULL,
    url_pdf                     VARCHAR(500)    NULL,
    fecha_envio_cliente         DATETIME        NULL,
    fecha_aceptacion_tactica    DATETIME        NULL,
    fecha_creacion              DATETIME        NOT NULL,
    -- AUDITORÍA
    creado_en                   DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por                  BIGINT          NULL,
    modificado_en               DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por              BIGINT          NULL,
    eliminado_en                DATETIME        NULL,
    eliminado_por               BIGINT          NULL,
    PRIMARY KEY (id_informe)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE evidencia_fotografica (
    id_evidencia        BIGINT          NOT NULL AUTO_INCREMENT,
    id_os               BIGINT          NULL,
    id_informe          BIGINT          NULL,
    id_usuario          BIGINT          NOT NULL,
    id_tipo_evidencia   INT             NOT NULL,
    url_archivo         VARCHAR(500)    NOT NULL,
    latitud             DECIMAL(10,7)   NULL,
    longitud            DECIMAL(10,7)   NULL,
    timestamp_captura   DATETIME        NOT NULL,
    validacion_ia       ENUM('aprobada','rechazada','pendiente','omitida') NOT NULL DEFAULT 'pendiente',
    override_aprobado   TINYINT(1)      NOT NULL DEFAULT 0,
    id_motivo_override  INT             NULL,
    id_usuario_override BIGINT          NULL,
    -- AUDITORÍA
    creado_en           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por          BIGINT          NULL,
    modificado_en       DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por      BIGINT          NULL,
    eliminado_en        DATETIME        NULL,
    eliminado_por       BIGINT          NULL,
    PRIMARY KEY (id_evidencia)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE conformidad_digital (
    id_conformidad          BIGINT          NOT NULL AUTO_INCREMENT,
    id_informe              BIGINT          NOT NULL,
    id_contacto_cliente     BIGINT          NULL,
    tipo                    ENUM('presencial','digital_extranet','tactica') NOT NULL,
    url_firma_imagen        VARCHAR(500)    NULL,
    latitud                 DECIMAL(10,7)   NULL,
    longitud                DECIMAL(10,7)   NULL,
    estado                  ENUM('pendiente','conforme','observado') NOT NULL,
    observaciones           TEXT            NULL,
    registrado_en           DATETIME        NOT NULL,
    -- AUDITORÍA
    creado_en               DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por              BIGINT          NULL,
    modificado_en           DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por          BIGINT          NULL,
    eliminado_en            DATETIME        NULL,
    eliminado_por           BIGINT          NULL,
    PRIMARY KEY (id_conformidad)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE gasto_viatico (
    id_gasto            BIGINT          NOT NULL AUTO_INCREMENT,
    id_os               BIGINT          NOT NULL,
    id_usuario          BIGINT          NOT NULL,
    id_concepto         INT             NOT NULL,
    id_moneda           INT             NOT NULL,
    monto               DECIMAL(12,2)   NOT NULL,
    descripcion         VARCHAR(300)    NULL,
    url_comprobante     VARCHAR(500)    NULL,
    tipo                ENUM('viatico_asignado','gasto_solicitado') NOT NULL,
    estado              ENUM('pendiente','aprobado','observado','rechazado','rendido') NOT NULL,
    fecha_solicitud     DATE            NOT NULL,
    aprobado_por        BIGINT          NULL,
    -- AUDITORÍA
    creado_en           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por          BIGINT          NULL,
    modificado_en       DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por      BIGINT          NULL,
    eliminado_en        DATETIME        NULL,
    eliminado_por       BIGINT          NULL,
    PRIMARY KEY (id_gasto)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE incidencia_operativa (
    id_incidencia       BIGINT          NOT NULL AUTO_INCREMENT,
    id_os               BIGINT          NOT NULL,
    id_usuario          BIGINT          NOT NULL,
    id_tipo             INT             NOT NULL,
    descripcion         TEXT            NOT NULL,
    id_nivel_alerta     INT             NOT NULL,
    estado              ENUM('abierta','escalada','resuelta') NOT NULL,
    fecha_registro      DATETIME        NOT NULL,
    -- AUDITORÍA
    creado_en           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por          BIGINT          NULL,
    modificado_en       DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por      BIGINT          NULL,
    eliminado_en        DATETIME        NULL,
    eliminado_por       BIGINT          NULL,
    PRIMARY KEY (id_incidencia)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE jornada_laboral (
    id_jornada              BIGINT          NOT NULL AUTO_INCREMENT,
    id_usuario              BIGINT          NOT NULL,
    fecha                   DATE            NOT NULL,
    hora_entrada            TIME            NOT NULL,
    hora_salida             TIME            NULL,
    latitud_entrada         DECIMAL(10,7)   NULL,
    longitud_entrada        DECIMAL(10,7)   NULL,
    latitud_salida          DECIMAL(10,7)   NULL,
    longitud_salida         DECIMAL(10,7)   NULL,
    duracion_minutos        INT             NULL,
    id_tipo_jornada         INT             NOT NULL,
    estado                  ENUM('abierta','cerrada','forzada') NOT NULL DEFAULT 'abierta',
    notas                   TEXT            NULL,
    -- AUDITORÍA
    creado_en               DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por              BIGINT          NULL,
    modificado_en           DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por          BIGINT          NULL,
    eliminado_en            DATETIME        NULL,
    eliminado_por           BIGINT          NULL,
    PRIMARY KEY (id_jornada)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE contingencia_zero_device (
    id_contingencia         BIGINT          NOT NULL AUTO_INCREMENT,
    id_os                   BIGINT          NOT NULL,
    id_usuario              BIGINT          NOT NULL,
    id_tipo_formulario      INT             NOT NULL,
    url_archivo_papel       VARCHAR(500)    NULL,
    datos_transcritos       JSON            NULL,
    estado                  ENUM('pendiente_transcripcion','transcrito','verificado') NOT NULL DEFAULT 'pendiente_transcripcion',
    fecha_evento_real       DATETIME        NOT NULL,
    fecha_ingreso_sistema   DATETIME        NULL,
    transcrito_por          BIGINT          NULL,
    verificado_por          BIGINT          NULL,
    -- AUDITORÍA
    creado_en               DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por              BIGINT          NULL,
    modificado_en           DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por          BIGINT          NULL,
    eliminado_en            DATETIME        NULL,
    eliminado_por           BIGINT          NULL,
    PRIMARY KEY (id_contingencia)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE alerta_predictiva (
    id_alerta               BIGINT          NOT NULL AUTO_INCREMENT,
    id_equipo               BIGINT          NOT NULL,
    id_os                   BIGINT          NULL,
    id_tipo_alerta          INT             NOT NULL,
    descripcion             TEXT            NOT NULL,
    id_prioridad            INT             NOT NULL,
    resuelta                TINYINT(1)      NOT NULL DEFAULT 0,
    id_resolucion           INT             NULL,
    id_usuario_resolucion   BIGINT          NULL,
    fecha_generacion        DATETIME        NOT NULL,
    fecha_resolucion        DATETIME        NULL,
    -- AUDITORÍA
    creado_en               DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por              BIGINT          NULL,
    modificado_en           DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por          BIGINT          NULL,
    eliminado_en            DATETIME        NULL,
    eliminado_por           BIGINT          NULL,
    PRIMARY KEY (id_alerta)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE item_presalida (
    id_item             BIGINT          NOT NULL AUTO_INCREMENT,
    id_os               BIGINT          NOT NULL,
    id_tipo_item        INT             NOT NULL,
    id_alerta           BIGINT          NULL,
    descripcion         VARCHAR(300)    NOT NULL,
    confirmado          TINYINT(1)      NOT NULL DEFAULT 0,
    confirmado_por      BIGINT          NULL,
    confirmado_en       DATETIME        NULL,
    -- AUDITORÍA
    creado_en           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por          BIGINT          NULL,
    modificado_en       DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por      BIGINT          NULL,
    eliminado_en        DATETIME        NULL,
    eliminado_por       BIGINT          NULL,
    PRIMARY KEY (id_item)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE repuesto_instalado (
    id_repuesto         BIGINT          NOT NULL AUTO_INCREMENT,
    id_os               BIGINT          NOT NULL,
    id_equipo           BIGINT          NOT NULL,
    id_catalogo_item    BIGINT          NULL,
    numero_serie        VARCHAR(100)    NULL,
    descripcion         VARCHAR(300)    NOT NULL,
    fecha_instalacion   DATE            NOT NULL,
    garantia_meses      INT             NULL,
    vigencia_hasta      DATE            NULL,
    -- AUDITORÍA
    creado_en           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por          BIGINT          NULL,
    modificado_en       DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por      BIGINT          NULL,
    eliminado_en        DATETIME        NULL,
    eliminado_por       BIGINT          NULL,
    PRIMARY KEY (id_repuesto)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- ============================================================
-- CAPA 7 — TRANSVERSAL (10 tablas)
-- ============================================================

CREATE TABLE documento_adjunto (
    id_documento        BIGINT          NOT NULL AUTO_INCREMENT,
    entidad_tipo        ENUM('requerimiento','propuesta','orden_compra','expediente','orden_servicio','orden_metrologia','informe','ssoma_doc','ticket') NOT NULL,
    id_entidad          BIGINT          NOT NULL,
    id_tipo_documento   INT             NOT NULL,
    nombre_archivo      VARCHAR(200)    NOT NULL,
    url_archivo         VARCHAR(500)    NOT NULL,
    version             INT             NOT NULL DEFAULT 1,
    id_visibilidad      INT             NOT NULL,
    metadatos           JSON            NULL,
    subido_por          BIGINT          NOT NULL,
    fecha_carga         DATETIME        NOT NULL,
    -- AUDITORÍA
    creado_en           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por          BIGINT          NULL,
    modificado_en       DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por      BIGINT          NULL,
    eliminado_en        DATETIME        NULL,
    eliminado_por       BIGINT          NULL,
    PRIMARY KEY (id_documento)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- INSERT-ONLY: sin bloque auditoría (es el log de cambios de estado)
CREATE TABLE auditoria_evento (
    id_auditoria    BIGINT          NOT NULL AUTO_INCREMENT,
    entidad_tipo    VARCHAR(50)     NOT NULL,
    id_entidad      BIGINT          NOT NULL,
    accion          VARCHAR(100)    NOT NULL,
    estado_anterior VARCHAR(80)     NULL,
    estado_nuevo    VARCHAR(80)     NULL,
    descripcion     TEXT            NULL,
    id_usuario      BIGINT          NULL,
    registrado_en   DATETIME        NOT NULL,
    metadata        JSON            NULL,
    PRIMARY KEY (id_auditoria)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE ticket_soporte (
    id_ticket           BIGINT          NOT NULL AUTO_INCREMENT,
    numero              VARCHAR(20)     NOT NULL,
    id_cliente          BIGINT          NOT NULL,
    id_contacto         BIGINT          NULL,
    id_equipo           BIGINT          NULL,
    asunto              VARCHAR(250)    NOT NULL,
    descripcion         TEXT            NOT NULL,
    id_prioridad        INT             NOT NULL,
    id_canal_origen     INT             NOT NULL,
    estado              ENUM('abierto','en_atencion','escalado','en_espera_cliente','resuelto','cerrado') NOT NULL,
    id_agente           BIGINT          NULL,
    fecha_creacion      DATETIME        NOT NULL,
    fecha_cierre        DATETIME        NULL,
    -- AUDITORÍA
    creado_en           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por          BIGINT          NULL,
    modificado_en       DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por      BIGINT          NULL,
    eliminado_en        DATETIME        NULL,
    eliminado_por       BIGINT          NULL,
    PRIMARY KEY (id_ticket)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE notificacion (
    id_notificacion     BIGINT          NOT NULL AUTO_INCREMENT,
    id_usuario_destino  BIGINT          NOT NULL,
    id_canal            INT             NOT NULL,
    titulo              VARCHAR(150)    NOT NULL,
    cuerpo              TEXT            NOT NULL,
    entidad_tipo        VARCHAR(50)     NULL,
    id_entidad          BIGINT          NULL,
    leido               TINYINT(1)      NOT NULL DEFAULT 0,
    enviado             TINYINT(1)      NOT NULL DEFAULT 0,
    fecha_creacion      DATETIME        NOT NULL,
    -- AUDITORÍA
    creado_en           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por          BIGINT          NULL,
    modificado_en       DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por      BIGINT          NULL,
    eliminado_en        DATETIME        NULL,
    eliminado_por       BIGINT          NULL,
    PRIMARY KEY (id_notificacion)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE sesion_usuario (
    id_sesion           BIGINT          NOT NULL AUTO_INCREMENT,
    id_usuario          BIGINT          NOT NULL,
    token_jti           VARCHAR(100)    NOT NULL,
    id_canal_acceso     INT             NOT NULL,
    ip_origen           VARCHAR(45)     NULL,
    user_agent          VARCHAR(300)    NULL,
    activo              TINYINT(1)      NOT NULL DEFAULT 1,
    fecha_inicio        DATETIME        NOT NULL,
    fecha_expiracion    DATETIME        NOT NULL,
    fecha_revocacion    DATETIME        NULL,
    motivo_revocacion   VARCHAR(100)    NULL,
    -- AUDITORÍA
    creado_en           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por          BIGINT          NULL,
    modificado_en       DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por      BIGINT          NULL,
    eliminado_en        DATETIME        NULL,
    eliminado_por       BIGINT          NULL,
    PRIMARY KEY (id_sesion)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE sync_pendiente (
    id_sync             BIGINT          NOT NULL AUTO_INCREMENT,
    id_usuario          BIGINT          NOT NULL,
    id_dispositivo      VARCHAR(100)    NOT NULL,
    entidad_tipo        VARCHAR(50)     NOT NULL,
    operacion           ENUM('insert','update','delete') NOT NULL,
    payload             JSON            NOT NULL,
    intentos            INT             NOT NULL DEFAULT 0,
    max_intentos        INT             NOT NULL DEFAULT 5,
    estado              ENUM('pendiente','en_proceso','sincronizado','error','descartado') NOT NULL DEFAULT 'pendiente',
    error_detalle       TEXT            NULL,
    timestamp_local     DATETIME        NOT NULL,
    timestamp_sync      DATETIME        NULL,
    -- AUDITORÍA
    creado_en           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por          BIGINT          NULL,
    modificado_en       DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por      BIGINT          NULL,
    eliminado_en        DATETIME        NULL,
    eliminado_por       BIGINT          NULL,
    PRIMARY KEY (id_sync)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE procedimiento_tecnico (
    id_procedimiento    BIGINT          NOT NULL AUTO_INCREMENT,
    codigo              VARCHAR(30)     NOT NULL,
    titulo              VARCHAR(200)    NOT NULL,
    id_tipo_servicio    INT             NOT NULL,
    id_tipo_equipo      INT             NULL,
    contenido           TEXT            NOT NULL,
    version             VARCHAR(10)     NOT NULL DEFAULT '1.0',
    id_estado           INT             NOT NULL,
    embedding_vector    JSON            NULL,
    fecha_vigencia      DATE            NULL,
    aprobado_por        BIGINT          NULL,
    url_pdf             VARCHAR(500)    NULL,
    -- AUDITORÍA
    creado_en           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por          BIGINT          NULL,
    modificado_en       DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por      BIGINT          NULL,
    eliminado_en        DATETIME        NULL,
    eliminado_por       BIGINT          NULL,
    PRIMARY KEY (id_procedimiento)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- INSERT-ONLY: sin bloque auditoría (log de descargas, nunca se modifica)
CREATE TABLE descarga_documento (
    id_descarga         BIGINT          NOT NULL AUTO_INCREMENT,
    id_usuario          BIGINT          NOT NULL,
    entidad_tipo        VARCHAR(50)     NOT NULL,
    id_entidad          BIGINT          NOT NULL,
    url_archivo         VARCHAR(500)    NOT NULL,
    ip_origen           VARCHAR(45)     NULL,
    canal               ENUM('extranet','intranet','movil') NOT NULL,
    registrado_en       DATETIME        NOT NULL,
    PRIMARY KEY (id_descarga)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE exportacion_ergosoft (
    id_exportacion          BIGINT          NOT NULL AUTO_INCREMENT,
    id_usuario              BIGINT          NOT NULL,
    id_tipo_exportacion     INT             NOT NULL,
    periodo_desde           DATE            NOT NULL,
    periodo_hasta           DATE            NOT NULL,
    url_archivo             VARCHAR(500)    NULL,
    registros_incluidos     INT             NULL,
    estado                  ENUM('generando','listo','enviado_erp','procesado_erp','error') NOT NULL DEFAULT 'generando',
    error_detalle           TEXT            NULL,
    fecha_generacion        DATETIME        NOT NULL,
    fecha_envio_erp         DATETIME        NULL,
    confirmacion_erp        VARCHAR(100)    NULL,
    -- AUDITORÍA
    creado_en               DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por              BIGINT          NULL,
    modificado_en           DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por          BIGINT          NULL,
    eliminado_en            DATETIME        NULL,
    eliminado_por           BIGINT          NULL,
    PRIMARY KEY (id_exportacion)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE token_acceso_publico (
    id_token            BIGINT          NOT NULL AUTO_INCREMENT,
    token               VARCHAR(100)    NOT NULL,
    entidad_tipo        ENUM('equipo','informe','certificado','orden_metrologia') NOT NULL,
    id_entidad          BIGINT          NOT NULL,
    fecha_expiracion    DATETIME        NOT NULL,
    usos                INT             NOT NULL DEFAULT 0,
    max_usos            INT             NULL,
    activo              TINYINT(1)      NOT NULL DEFAULT 1,
    generado_por        BIGINT          NOT NULL,
    -- AUDITORÍA
    creado_en           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por          BIGINT          NULL,
    modificado_en       DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por      BIGINT          NULL,
    eliminado_en        DATETIME        NULL,
    eliminado_por       BIGINT          NULL,
    PRIMARY KEY (id_token)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- FIN — 60 tablas creadas
-- ============================================================
