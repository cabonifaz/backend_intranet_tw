-- ============================================================
-- Migración 51 — Sincroniza el catálogo AREA_CORRECCION_PROPUESTA con las 9 secciones del wizard.
--   Antes había 8 áreas de alto nivel (Descuento, Documentos...) desalineadas con el wizard.
--   Ahora las áreas = las secciones reales del wizard (configuracion, propuesta, opcionales,
--   detalle, recomendaciones, forma_pago, suministros_cliente, condiciones, listado_equipos).
--   SP_PrepararDecisionVistoBueno filtra las opcionales según propuesta_comercial.secciones_activas.
-- IDEMPOTENTE.
-- ============================================================

-- 1. Soft-delete de las áreas obsoletas que no están en la lista nueva
UPDATE tabla_maestra
   SET eliminado_en = NOW(), eliminado_por = NULL
 WHERE Descripcion = 'AREA_CORRECCION_PROPUESTA'
   AND eliminado_en IS NULL
   AND String2 NOT IN ('configuracion', 'propuesta', 'opcionales', 'detalle', 'recomendaciones',
                       'forma_pago', 'suministros_cliente', 'condiciones', 'listado_equipos');

-- 2. Resolver IdMaestro del catálogo (existe desde migración 46).
SET @id_area := (SELECT MAX(IdMaestro) FROM tabla_maestra WHERE Descripcion = 'AREA_CORRECCION_PROPUESTA');
SET @id_area := IFNULL(@id_area, (SELECT IFNULL(MAX(IdMaestro), 0) + 1 FROM tabla_maestra));

-- 3. Insertar/actualizar las 9 áreas coherentes con el wizard
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2)
SELECT 1, @id_area, 'AREA_CORRECCION_PROPUESTA', a.orden, a.etiqueta, a.codigo
FROM (
          SELECT 1 AS orden, 'Configuración'       AS etiqueta, 'configuracion'       AS codigo
UNION ALL SELECT 2, 'Ítems y precios',    'propuesta'
UNION ALL SELECT 3, 'Opcionales',         'opcionales'
UNION ALL SELECT 4, 'Detalle',            'detalle'
UNION ALL SELECT 5, 'Recomendaciones',    'recomendaciones'
UNION ALL SELECT 6, 'Forma de Pago',      'forma_pago'
UNION ALL SELECT 7, 'Suministros Cliente','suministros_cliente'
UNION ALL SELECT 8, 'Condiciones',        'condiciones'
UNION ALL SELECT 9, 'Listado de Equipos', 'listado_equipos'
) a
WHERE NOT EXISTS (
    SELECT 1 FROM tabla_maestra x
    WHERE x.Descripcion = 'AREA_CORRECCION_PROPUESTA' AND x.String2 = a.codigo AND x.eliminado_en IS NULL
);

-- 4. Si las áreas existían con etiquetas antiguas, actualizarlas al nuevo texto y orden
UPDATE tabla_maestra tm
JOIN (
          SELECT 1 AS orden, 'Configuración'       AS etiqueta, 'configuracion'       AS codigo
UNION ALL SELECT 2, 'Ítems y precios',    'propuesta'
UNION ALL SELECT 3, 'Opcionales',         'opcionales'
UNION ALL SELECT 4, 'Detalle',            'detalle'
UNION ALL SELECT 5, 'Recomendaciones',    'recomendaciones'
UNION ALL SELECT 6, 'Forma de Pago',      'forma_pago'
UNION ALL SELECT 7, 'Suministros Cliente','suministros_cliente'
UNION ALL SELECT 8, 'Condiciones',        'condiciones'
UNION ALL SELECT 9, 'Listado de Equipos', 'listado_equipos'
) nueva ON nueva.codigo = tm.String2
SET tm.String1 = nueva.etiqueta, tm.Num1 = nueva.orden
WHERE tm.Descripcion = 'AREA_CORRECCION_PROPUESTA' AND tm.eliminado_en IS NULL;
