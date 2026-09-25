-- ============================================================
-- 02_alter_cliente_hu79.sql
-- Expande la tabla `cliente` para soportar HU-79:
--   - Amplía VARCHAR de razon_social y nombre_comercial
--   - Ajusta `estado` de ENUM a VARCHAR (soporte mayúsculas)
--   - Agrega campos extendidos de ficha de cliente
--   - Agrega campos SSOMA (4 booleanos + notas)
--   - Agrega convención de auditoría (SoftDelete, UsuCre/FchCre/UsuMod/FchMod)
-- ============================================================

ALTER TABLE cliente
    -- Ampliación de columnas existentes
    MODIFY COLUMN razon_social     VARCHAR(300) NOT NULL,
    MODIFY COLUMN nombre_comercial VARCHAR(200) NULL,
    MODIFY COLUMN estado           VARCHAR(20)  NOT NULL DEFAULT 'Activo',

    -- Campos extendidos HU-79
    ADD COLUMN tipo_documento          VARCHAR(20)   NULL           AFTER ruc,
    ADD COLUMN tipo_cliente            VARCHAR(50)   NULL           AFTER tipo_documento,
    ADD COLUMN condicion_fiscal        VARCHAR(50)   NULL DEFAULT 'Activo',
    ADD COLUMN condicion_contribuyente VARCHAR(50)   NULL DEFAULT 'Habido',
    ADD COLUMN condicion_pago          VARCHAR(50)   NULL,
    ADD COLUMN linea_credito_usd       DECIMAL(15,2) NULL,
    ADD COLUMN telefono_central        VARCHAR(30)   NULL,
    ADD COLUMN domicilio_fiscal        VARCHAR(500)  NULL,
    ADD COLUMN es_vip                  TINYINT(1)    NOT NULL DEFAULT 0,
    ADD COLUMN regla_vip               VARCHAR(100)  NULL,
    ADD COLUMN descuento_vip_pct       DECIMAL(5,2)  NULL,
    ADD COLUMN patron_masas_asignado   VARCHAR(100)  NULL,

    -- Campos SSOMA
    ADD COLUMN ssoma_pase_ingreso      TINYINT(1)    NOT NULL DEFAULT 0,
    ADD COLUMN ssoma_trabajo_altura    TINYINT(1)    NOT NULL DEFAULT 0,
    ADD COLUMN ssoma_espacio_confinado TINYINT(1)    NOT NULL DEFAULT 0,
    ADD COLUMN ssoma_induccion_previa  TINYINT(1)    NOT NULL DEFAULT 0,
    ADD COLUMN ssoma_notas             TEXT          NULL,

    -- Convención de auditoría (AGENTS.md)
    ADD COLUMN SoftDelete BIT         NOT NULL DEFAULT 0,
    ADD COLUMN UsuCre     VARCHAR(100) NULL,
    ADD COLUMN FchCre     DATETIME     NULL,
    ADD COLUMN UsuMod     VARCHAR(100) NULL,
    ADD COLUMN FchMod     DATETIME     NULL;
