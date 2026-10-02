-- ============================================================
-- Migración 31 — HU-07: Creación de Propuesta Comercial
--   Amplía propuesta_comercial y propuesta_item (vacías hasta hoy)
--   y crea propuesta_texto, propuesta_forma_pago y propuesta_equipo.
-- ============================================================

-- 1. Cabecera de la propuesta
ALTER TABLE propuesta_comercial
    ADD COLUMN id_sede                 BIGINT        NULL AFTER id_cliente,
    ADD COLUMN id_contacto             BIGINT        NULL AFTER id_sede,
    ADD COLUMN id_responsable          BIGINT        NULL AFTER id_contacto,
    ADD COLUMN tipo_servicio           VARCHAR(200)  NULL,
    ADD COLUMN referencia              VARCHAR(500)  NULL,
    ADD COLUMN secciones_activas       JSON          NULL,
    ADD COLUMN es_tercerizado          TINYINT(1)    NOT NULL DEFAULT 0,
    ADD COLUMN tercero_ruc             VARCHAR(11)   NULL,
    ADD COLUMN tercero_razon_social    VARCHAR(300)  NULL,
    ADD COLUMN tercero_direccion       VARCHAR(500)  NULL,
    ADD COLUMN tipo_cambio             DECIMAL(8,4)  NULL,
    ADD COLUMN garantia_meses          INT           NULL,
    ADD COLUMN mostrar_garantia        TINYINT(1)    NOT NULL DEFAULT 1,
    ADD COLUMN plazo_entrega_unidad    VARCHAR(20)   NULL,
    ADD COLUMN plazo_entrega_condicion VARCHAR(300)  NULL,
    ADD COLUMN precios_incluyen_igv    TINYINT(1)    NOT NULL DEFAULT 0,
    ADD COLUMN subtotal_opcionales     DECIMAL(14,2) NOT NULL DEFAULT 0.00,
    ADD COLUMN descuento_opcionales    DECIMAL(14,2) NOT NULL DEFAULT 0.00,
    ADD COLUMN total_opcionales        DECIMAL(14,2) NOT NULL DEFAULT 0.00,
    ADD KEY ix_prop_numero (numero),
    ADD KEY ix_prop_requerimiento (id_requerimiento);

-- 2. Ítems: sección principal / opcional y columnas del diseño
ALTER TABLE propuesta_item
    ADD COLUMN seccion            ENUM('principal','opcional') NOT NULL DEFAULT 'principal' AFTER id_propuesta,
    ADD COLUMN alcance            VARCHAR(100)  NULL,
    ADD COLUMN puntos_calibracion VARCHAR(100)  NULL,
    ADD COLUMN frecuencia         DECIMAL(10,2) NOT NULL DEFAULT 1.00,
    ADD COLUMN descuento          DECIMAL(14,2) NOT NULL DEFAULT 0.00,
    ADD COLUMN es_espaciado       TINYINT(1)    NOT NULL DEFAULT 0,
    ADD KEY ix_pitem_propuesta (id_propuesta);

-- 3. Textos por sección (Detalle, Recomendaciones, Suministros del Cliente,
--    Condiciones). Jerarquía por orden: cada 'vineta' pertenece al último 'titulo'.
CREATE TABLE IF NOT EXISTS propuesta_texto (
    id             BIGINT       NOT NULL AUTO_INCREMENT,
    id_propuesta   BIGINT       NOT NULL,
    seccion        ENUM('detalle','recomendaciones','suministros_cliente','condiciones') NOT NULL,
    tipo           ENUM('titulo','vineta') NOT NULL DEFAULT 'vineta',
    texto          TEXT         NOT NULL,
    id_texto_base  BIGINT       NULL,
    orden          INT          NOT NULL DEFAULT 1,
    UsuCre         VARCHAR(100) NULL,
    FchCre         DATETIME     NULL,
    PRIMARY KEY (id),
    KEY ix_ptexto_propuesta (id_propuesta, seccion, orden)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- 4. Formas de pago (hitos que suman 100 %)
CREATE TABLE IF NOT EXISTS propuesta_forma_pago (
    id            BIGINT       NOT NULL AUTO_INCREMENT,
    id_propuesta  BIGINT       NOT NULL,
    porcentaje    DECIMAL(5,2) NOT NULL,
    condicion     VARCHAR(40)  NOT NULL,   -- código de CONDICION_PAGO (39)
    orden         INT          NOT NULL DEFAULT 1,
    UsuCre        VARCHAR(100) NULL,
    FchCre        DATETIME     NULL,
    PRIMARY KEY (id),
    KEY ix_ppago_propuesta (id_propuesta)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- 5. Equipos de la propuesta. Si viene del maestro (equipo_cliente, HU-88)
--    serie/marca/modelo se copian de allí; si es manual, quedan fijos
--    desde el primer guardado.
CREATE TABLE IF NOT EXISTS propuesta_equipo (
    id              BIGINT       NOT NULL AUTO_INCREMENT,
    id_propuesta    BIGINT       NOT NULL,
    id_equipo       BIGINT       NULL,     -- equipo_cliente.id_equipo
    local_sede      VARCHAR(200) NULL,
    tipo            VARCHAR(60)  NULL,
    subtipo         VARCHAR(100) NULL,
    num_serie       VARCHAR(80)  NOT NULL,
    marca           VARCHAR(80)  NOT NULL,
    modelo          VARCHAR(80)  NOT NULL,
    codigo_cliente  VARCHAR(80)  NULL,
    codigo_tw       VARCHAR(30)  NULL,
    orden           INT          NOT NULL DEFAULT 1,
    UsuCre          VARCHAR(100) NULL,
    FchCre          DATETIME     NULL,
    PRIMARY KEY (id),
    KEY ix_pequipo_propuesta (id_propuesta)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
