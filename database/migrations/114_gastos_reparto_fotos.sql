-- ============================================================
-- Migración 114 — Rendición de gastos desde la app móvil (HU-27): reparto entre viáticos, varias fotos y lectura del comprobante con IA
--   1. gasto_viatico (tipo 'gasto_solicitado'):
--        origen ............ viatico (sale del adelanto, trae reparto) | reembolso (lo pagó el técnico); NULL = gasto anterior a esta migración
--        id_cliente_app .... GUID que genera la app: un reintento de la sincronización no crea el gasto dos veces
--        concepto_texto .... el texto del concepto cuando el técnico eligió "Otro"
--        motivo_sin_foto ... obligatorio si el gasto no tiene ninguna foto
--        monto_ia / coincide_ia ... total que leyó la IA en la boleta y si coincide con el monto declarado (NULL = sin lectura)
--   2. gasto_viatico_reparto: un gasto repartido entre varias líneas del adelanto (id_viatico_linea = gasto_viatico.id_gasto de tipo viatico_asignado).
--   3. gasto_viatico_foto: hasta 5 fotos (JPEG) por gasto, en orden.
--   Auditoría como gasto_viatico (creado_en/creado_por/modificado_en/modificado_por/eliminado_en/eliminado_por). Solo PK: sin FK ni únicos.
--   No borra ni cambia datos existentes. IDEMPOTENTE.
-- ============================================================

-- ── 1. gasto_viatico ────────────────────────────────────────────────────────────────────────
SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'gasto_viatico' AND COLUMN_NAME = 'origen'),
    'ALTER TABLE gasto_viatico ADD COLUMN origen ENUM(''viatico'',''reembolso'') NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'gasto_viatico' AND COLUMN_NAME = 'id_cliente_app'),
    'ALTER TABLE gasto_viatico ADD COLUMN id_cliente_app VARCHAR(36) NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'gasto_viatico' AND COLUMN_NAME = 'concepto_texto'),
    'ALTER TABLE gasto_viatico ADD COLUMN concepto_texto VARCHAR(100) NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'gasto_viatico' AND COLUMN_NAME = 'motivo_sin_foto'),
    'ALTER TABLE gasto_viatico ADD COLUMN motivo_sin_foto VARCHAR(300) NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'gasto_viatico' AND COLUMN_NAME = 'monto_ia'),
    'ALTER TABLE gasto_viatico ADD COLUMN monto_ia DECIMAL(12,2) NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'gasto_viatico' AND COLUMN_NAME = 'coincide_ia'),
    'ALTER TABLE gasto_viatico ADD COLUMN coincide_ia TINYINT NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- ── 2. Reparto de un gasto entre líneas del adelanto ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS gasto_viatico_reparto (
    id_reparto        BIGINT          NOT NULL AUTO_INCREMENT,
    id_gasto          BIGINT          NOT NULL,
    id_viatico_linea  BIGINT          NOT NULL,
    monto             DECIMAL(12,2)   NOT NULL,
    -- AUDITORÍA
    creado_en         DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por        BIGINT          NULL,
    modificado_en     DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por    BIGINT          NULL,
    eliminado_en      DATETIME        NULL,
    eliminado_por     BIGINT          NULL,
    PRIMARY KEY (id_reparto)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ── 3. Fotos del gasto (hasta 5) ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS gasto_viatico_foto (
    id_foto           BIGINT          NOT NULL AUTO_INCREMENT,
    id_gasto          BIGINT          NOT NULL,
    url               VARCHAR(500)    NOT NULL,
    orden             TINYINT         NOT NULL,
    -- AUDITORÍA
    creado_en         DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por        BIGINT          NULL,
    modificado_en     DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por    BIGINT          NULL,
    eliminado_en      DATETIME        NULL,
    eliminado_por     BIGINT          NULL,
    PRIMARY KEY (id_foto)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

SELECT 'Migración 114 (debe ser 8)' AS verificacion,
       (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'gasto_viatico'
           AND COLUMN_NAME IN ('origen', 'id_cliente_app', 'concepto_texto', 'motivo_sin_foto', 'monto_ia', 'coincide_ia'))
     + (SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE()
           AND TABLE_NAME IN ('gasto_viatico_reparto', 'gasto_viatico_foto')) AS valor;
