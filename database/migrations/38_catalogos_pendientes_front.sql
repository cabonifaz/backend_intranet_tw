-- ============================================================
-- Migración 38 — Catálogos pendientes de limpiar en el front
--   Mueve 2 listas desplegables que el front mantenía como constantes TS
--   locales a `tabla_maestra` para que haya una sola fuente de verdad.
--     IdMaestro 86 = NIVEL_TARIFA_SUMINISTRO (3 escalas de precio de la ficha de Suministros)
--     IdMaestro 87 = SERVICIO_TEXTO_BASE (checkboxes de "Servicios Aplicables" en Textos Base)
--
--   TRONCAL_TW (IdMaestro=84) y ROL_SISTEMA (IdMaestro=68) ya existen desde la migración 34.
--   El front consumirá esos directamente sin cambios en el back.
--
--   IDEMPOTENTE. Se puede re-ejecutar.
-- ============================================================

-- ── 86 NIVEL_TARIFA_SUMINISTRO ──────────────────────────────
--      Las 3 escalas de precio de la Sección 3 de la ficha de Suministros.
--      Num1 = número de escala (1 = más barato, 3 = más caro / corporativo).
--      String2 = código estable (compatible con tabla suministro_escala.nivel).
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2)
SELECT 1, 86, 'NIVEL_TARIFA_SUMINISTRO', n.num, n.etiqueta, n.codigo
FROM (SELECT 1 AS num, 'Estándar'                AS etiqueta, 'estandar'         AS codigo
      UNION ALL SELECT 2, 'Volumen',             'volumen'
      UNION ALL SELECT 3, 'Corporativo Alto',    'corporativo_alto') n
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra x
                  WHERE x.IdMaestro = 86 AND x.IdEmpresa = 1 AND x.String2 = n.codigo);

-- ── 87 SERVICIO_TEXTO_BASE ──────────────────────────────────
--      Checkboxes de "Servicios Aplicables" en la ficha de Texto Base.
--      Determina en qué servicios de la propuesta/informe aplica cada texto.
--      String2 = código estable que viaja en el DTO (compatible con las
--      columnas booleanas aplica_* actuales de la tabla texto_base).
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2)
SELECT 1, 87, 'SERVICIO_TEXTO_BASE', s.n, s.etiqueta, s.codigo
FROM (SELECT 1 AS n, 'Calibración (Laboratorio)' AS etiqueta, 'calibracion_lab' AS codigo
      UNION ALL SELECT 2, 'Calibración (Planta)',    'calibracion_planta'
      UNION ALL SELECT 3, 'Mantenimiento',           'mantenimiento'
      UNION ALL SELECT 4, 'Venta de Suministros',    'venta_suministros') s
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra x
                  WHERE x.IdMaestro = 87 AND x.IdEmpresa = 1 AND x.String2 = s.codigo);
