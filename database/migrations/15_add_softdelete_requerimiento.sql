-- ============================================================
-- Migración 15 — Alinea soft delete de requerimiento
-- con la convención SoftDelete BIT usada en cliente,
-- sede_cliente y contacto_cliente.
-- ============================================================

ALTER TABLE requerimiento
    ADD COLUMN SoftDelete BIT NOT NULL DEFAULT 0 AFTER cliente_deuda;
