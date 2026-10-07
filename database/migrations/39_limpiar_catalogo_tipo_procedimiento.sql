-- ============================================================
-- Migración 39 — Eliminar catálogo TIPO_PROCEDIMIENTO (IdMaestro 76)
--   El campo tipo_procedimiento se removió del flujo en la migración 33.
--   Este catálogo quedó huérfano. Lo borramos aquí.
--   IDEMPOTENTE.
-- ============================================================

DELETE FROM tabla_maestra
WHERE IdEmpresa = 1 AND IdMaestro = 76;
