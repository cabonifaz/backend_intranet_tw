-- ============================================================
-- 20_create_categoria_cliente.sql
-- Tabla maestra de categorías de cliente.
-- Reemplaza el texto libre categoria VARCHAR en cliente.
-- Las columnas de negocio (prioridad_atencion, pct_ganancia_*)
-- se definen luego cuando se establezcan las reglas.
-- ============================================================

CREATE TABLE IF NOT EXISTS categoria_cliente (
    id_categoria        INT            NOT NULL AUTO_INCREMENT,
    nombre              VARCHAR(100)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL,
    descripcion         VARCHAR(300)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
    prioridad_atencion  INT            NULL,
    pct_ganancia_min    DECIMAL(5,2)   NULL,
    pct_ganancia_max    DECIMAL(5,2)   NULL,
    estado              VARCHAR(20)    CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL DEFAULT 'Activo',
    SoftDelete          TINYINT(1)     NOT NULL DEFAULT 0,
    UsuCre              VARCHAR(100)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
    FchCre              DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UsuMod              VARCHAR(100)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
    FchMod              DATETIME       NULL,
    PRIMARY KEY (id_categoria)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Seed inicial: migrar categorías desde tabla_maestra IdMaestro=62
INSERT INTO categoria_cliente (nombre, estado, UsuCre, FchCre) VALUES
    ('Platino',  'Activo', 'SYSTEM', NOW()),
    ('Gold',     'Activo', 'SYSTEM', NOW()),
    ('Silver',   'Activo', 'SYSTEM', NOW()),
    ('Estándar', 'Activo', 'SYSTEM', NOW());

-- Agregar id_categoria a cliente
ALTER TABLE cliente
    ADD COLUMN id_categoria INT NULL AFTER categoria;

-- Migrar datos existentes: mapear el texto al nuevo id
UPDATE cliente c
JOIN categoria_cliente cc ON cc.nombre = c.categoria AND cc.SoftDelete = 0
SET c.id_categoria = cc.id_categoria
WHERE c.categoria IS NOT NULL AND c.SoftDelete = 0;

-- Eliminar columna legacy categoria
ALTER TABLE cliente
    DROP COLUMN categoria;
