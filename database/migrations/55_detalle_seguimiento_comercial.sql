-- ============================================================
-- Migración 55 — HU-18 Vista Detalle del Seguimiento
--   Acciones para los botones del detalle (módulo propuestas):
--     propuesta_seguimiento_registrar  nivel 2  Registrar seguimiento / Ejecutar próxima acción
--     propuesta_seguimiento_cerrar     nivel 2  Registrar aceptación o rechazo del cliente
--   nivel 2 = editar  -> usuario (asistente), supervisor (jefe) y administrador del área
--   Los SP nuevos son SP_CalcularSeguimientoComercial (cálculo común con la bandeja HU-17)
--   y SP_ObtenerDetalleSeguimiento. SP_ObtenerBandejaSeguimiento se vuelve a crear para usar
--   el cálculo común (mismo resultado que en la HU-17).
--
--   IDEMPOTENTE. Se puede re-ejecutar.
-- ============================================================

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2, String3)
SELECT 1, 88, 'ACCION_SISTEMA', a.nivel, a.etiqueta, a.codigo, a.modulo
FROM (
          SELECT 2 AS nivel, 'Registrar seguimiento comercial de propuestas' AS etiqueta,
                 'propuesta_seguimiento_registrar' AS codigo, 'propuestas' AS modulo
UNION ALL SELECT 2, 'Registrar aceptación o rechazo del cliente',
                 'propuesta_seguimiento_cerrar', 'propuestas'
) a
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra x WHERE x.IdMaestro = 88 AND x.IdEmpresa = 1 AND x.String2 = a.codigo);
