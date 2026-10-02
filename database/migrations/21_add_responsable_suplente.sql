-- ============================================================
-- Migración 21 — Responsable de RQ + tabla usuario_suplente
-- ============================================================

-- 1. Agregar id_responsable a requerimiento
ALTER TABLE requerimiento
    ADD COLUMN id_responsable BIGINT NULL AFTER id_usuario_creador;

-- 2. Poblar con el creador (regla inicial: creador = responsable)
UPDATE requerimiento
SET id_responsable = id_usuario_creador
WHERE SoftDelete = 0;

-- 3. Crear tabla usuario_suplente
CREATE TABLE IF NOT EXISTS usuario_suplente (
    id                  INT          NOT NULL AUTO_INCREMENT,
    id_titular          BIGINT       NOT NULL,
    id_suplente         BIGINT       NOT NULL,
    fecha_inicio        DATE         NOT NULL,
    fecha_fin           DATE         NULL,
    activo              TINYINT(1)   NOT NULL DEFAULT 1,
    SoftDelete          TINYINT(1)   NOT NULL DEFAULT 0,
    UsuCre              VARCHAR(100) NULL,
    FchCre              DATETIME     NULL,
    UsuMod              VARCHAR(100) NULL,
    FchMod              DATETIME     NULL,
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
