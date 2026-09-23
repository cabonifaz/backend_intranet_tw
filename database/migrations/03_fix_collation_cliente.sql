-- ============================================================
-- 03_fix_collation_cliente.sql
-- Unifica la collation de todas las columnas VARCHAR/TEXT
-- de la tabla cliente a utf8mb4_unicode_ci para evitar el
-- error "Illegal mix of collations" en los stored procedures.
-- ============================================================

ALTER TABLE cliente
    CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
