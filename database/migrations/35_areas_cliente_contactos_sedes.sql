-- ============================================================
-- Migración 35 — Cierre de pendientes del back (reunión 02-oct)
--   1. Áreas del cliente: se asignan desde el catálogo AREA_USUARIO (79)
--      (decisión del equipo: un solo mantenimiento de áreas). Reemplaza a
--      area_cliente (áreas propias por empresa de la migración 33).
--      La ubicación de los equipos guarda el código del área.
--   2. Contactos en varias sedes, con contacto principal por sede.
--      El principal de la empresa sigue siendo contacto_cliente.es_contacto_principal.
--   IDEMPOTENTE. Ejecutar junto con los SPs de este mismo paquete.
-- ============================================================

-- ── 1. ÁREAS DEL CLIENTE ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS cliente_area (
    id_cliente  BIGINT      NOT NULL,
    area        VARCHAR(60) NOT NULL,
    UsuCre      VARCHAR(100) NULL,
    FchCre      DATETIME     NULL,
    PRIMARY KEY (id_cliente, area)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

DROP PROCEDURE IF EXISTS SP_GuardarAreaCliente;
DROP PROCEDURE IF EXISTS SP_CambiarEstadoAreaCliente;
DROP TABLE IF EXISTS area_cliente;

-- ── 2. CONTACTOS EN VARIAS SEDES ─────────────────────────────
CREATE TABLE IF NOT EXISTS contacto_sede (
    id_contacto        BIGINT     NOT NULL,
    id_sede            BIGINT     NOT NULL,
    es_principal_sede  TINYINT(1) NOT NULL DEFAULT 0,
    PRIMARY KEY (id_contacto, id_sede),
    KEY ix_contacto_sede_sede (id_sede)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Los contactos existentes conservan su sede actual
INSERT IGNORE INTO contacto_sede (id_contacto, id_sede, es_principal_sede)
SELECT id_contacto, id_sede, 0
FROM contacto_cliente
WHERE id_sede IS NOT NULL AND SoftDelete = 0;
