-- ============================================================
-- Migración 43 — HU-11: Aplicación de Descuento Comercial
--   Acción propuesta_aplicar_descuento en el módulo "propuestas" con nivel 3
--   (supervisar). Con la matriz de la migración 41 la tienen el supervisor del
--   área comercial (Jefe Comercial) y los administradores. El rol usuario
--   (editar, nivel 2) puede crear y editar propuestas pero no aplicar descuentos.
--   Se ajusta desde la matriz de permisos (permiso_area_rol) sin tocar código.
--   IDEMPOTENTE. Sin punto y coma dentro de los comentarios.
-- ============================================================

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2, String3)
SELECT 1, 88, 'ACCION_SISTEMA', 3, 'Aplicar descuento global a propuesta', 'propuesta_aplicar_descuento', 'propuestas'
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra WHERE IdMaestro = 88 AND IdEmpresa = 1 AND String2 = 'propuesta_aplicar_descuento');
