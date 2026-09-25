-- ============================================================
-- 09_add_categoria_cliente.sql
-- Agrega columna categoria a la tabla cliente (HU futura)
-- ============================================================

-- NOTA: columna ya existe en el servidor; ejecutar solo si la tabla no la tiene aún.
-- ALTER TABLE cliente
--     ADD COLUMN categoria VARCHAR(50) NULL AFTER tipo_cliente;

-- Seed de categorías en tabla_maestra (IdMaestro = 62, siguiente disponible al ejecutar)
-- Verificar MAX(IdMaestro) antes de ejecutar: SELECT MAX(IdMaestro) FROM tabla_maestra WHERE IdEmpresa = 1;
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1) VALUES
    (1, 62, 'CATEGORIA_CLIENTE', 1, 'Platino'),
    (1, 62, 'CATEGORIA_CLIENTE', 2, 'Gold'),
    (1, 62, 'CATEGORIA_CLIENTE', 3, 'Silver'),
    (1, 62, 'CATEGORIA_CLIENTE', 4, 'Estándar');
