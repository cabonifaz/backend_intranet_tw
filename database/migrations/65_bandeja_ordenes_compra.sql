-- ============================================================
-- Migración 65 — HU-23 Bandeja y Detalle de Órdenes de Compra
--   1. Acción oc_bandeja (nivel 1 = ver, módulo propuestas):
--      Comercial (visor, asistente, jefe y administrador) y administradores de Gerencia y TI.
--
--   El alcance por área es el mismo del seguimiento comercial:
--   propuesta_seguimiento_todas (admins de Gerencia y TI) ve las OC de todas las áreas.
--
--   IDEMPOTENTE. Se puede re-ejecutar.
-- ============================================================

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2, String3)
SELECT 1, 88, 'ACCION_SISTEMA', 1, 'Ver bandeja y detalle de órdenes de compra', 'oc_bandeja', 'propuestas'
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra WHERE IdMaestro = 88 AND IdEmpresa = 1 AND String2 = 'oc_bandeja');
