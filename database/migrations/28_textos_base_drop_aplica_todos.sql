-- ============================================================
-- Migración 28 — Textos Base: dropear columna aplica_todos_servicios
--   La columna era redundante: se puede derivar de los 4 flags
--   individuales (aplica_calibracion_lab, aplica_calibracion_planta,
--   aplica_mantenimiento, aplica_venta_suministros). El front ya envía
--   el valor derivado desde que se detectó esta inconsistencia, pero
--   acá sacamos la columna + el parámetro del SP + la propiedad del DTO.
--   IMPORTANTE: ejecutar junto con el script actualizado de SP_GuardarTextoBase
--   y SP_ObtenerTextoBasePorId de este mismo batch, y publicar el back
--   inmediatamente después.
-- ============================================================

ALTER TABLE texto_base DROP COLUMN aplica_todos_servicios;
