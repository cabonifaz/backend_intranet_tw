-- ============================================================
-- 06_create_sede_cliente.sql
-- Crea la tabla sede_cliente para HU-80
-- ============================================================

CREATE TABLE IF NOT EXISTS sede_cliente (
    id_sede          BIGINT        NOT NULL AUTO_INCREMENT,
    id_cliente       BIGINT        NOT NULL,
    nombre           VARCHAR(200)  NOT NULL,
    tipo_instalacion VARCHAR(100)  NULL,
    region           VARCHAR(100)  NULL,
    provincia        VARCHAR(100)  NULL,
    distrito         VARCHAR(100)  NULL,
    urbanizacion     VARCHAR(200)  NULL,
    direccion_exacta VARCHAR(500)  NULL,
    estado           VARCHAR(20)   NOT NULL DEFAULT 'Activo',
    SoftDelete       BIT           NOT NULL DEFAULT 0,
    UsuCre           VARCHAR(100)  NULL,
    FchCre           DATETIME      NULL,
    UsuMod           VARCHAR(100)  NULL,
    FchMod           DATETIME      NULL,
    PRIMARY KEY (id_sede)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
