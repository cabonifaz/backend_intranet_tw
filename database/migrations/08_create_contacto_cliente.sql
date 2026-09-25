-- ============================================================
-- 08_create_contacto_cliente.sql
-- Tabla de contactos clave por cliente (HU-81)
-- ============================================================

CREATE TABLE IF NOT EXISTS contacto_cliente (
    id_contacto                      BIGINT       NOT NULL AUTO_INCREMENT,
    id_cliente                       BIGINT       NOT NULL,
    id_sede                          BIGINT       NULL,
    nombres                          VARCHAR(200) NOT NULL,
    documento_identidad              VARCHAR(20)  NULL,
    cargo                            VARCHAR(100) NULL,
    area                             VARCHAR(100) NULL,
    correo                           VARCHAR(200) NULL,
    telefono_movil                   VARCHAR(50)  NULL,
    telefono_anexo                   VARCHAR(50)  NULL,
    es_contacto_principal            BIT          NOT NULL DEFAULT 0,
    autorizado_aprobar_cotizaciones  BIT          NOT NULL DEFAULT 0,
    recibe_alertas_calibracion       BIT          NOT NULL DEFAULT 0,
    autorizado_recepcion_tecnica     BIT          NOT NULL DEFAULT 0,
    estado                           VARCHAR(20)  NOT NULL DEFAULT 'Activo',
    SoftDelete                       BIT          NOT NULL DEFAULT 0,
    UsuCre                           VARCHAR(100) NULL,
    FchCre                           DATETIME     NULL,
    UsuMod                           VARCHAR(100) NULL,
    FchMod                           DATETIME     NULL,
    PRIMARY KEY (id_contacto)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
