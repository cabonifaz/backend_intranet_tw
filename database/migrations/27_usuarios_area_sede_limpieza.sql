-- ============================================================
-- Migración 27 — Usuarios (2do batch, pedido de Jazir)
--   1) Catálogos AREA_USUARIO (79) y CARGO_USUARIO (80, sin datos aún)
--   2) SEDE_OPERATIVA (69) → SEDE_OPERATIVA_TW con 2 sedes reales de TW
--      y usuario.base_operativa → usuario.sede_operativa
--   3) DROP de la tabla usuario_sede_autorizada
--   4) DROP de usuario.area_comercial
--   5) DROP de columnas legacy id_area, id_tipo_doc_identidad, id_persona_contacto
--   6) Nueva columna usuario.area (guarda String2 de AREA_USUARIO)
--   IMPORTANTE: ejecutar junto con el SCRIPT DE SPs de este mismo batch
--   y publicar el back inmediatamente después.
-- ============================================================

-- ── 6) Nueva columna area (antes de borrar area_comercial, para migrar datos) ──
ALTER TABLE usuario ADD COLUMN area VARCHAR(60) NULL AFTER cargo;

UPDATE usuario SET area = CASE
        WHEN LOWER(area_comercial) LIKE '%comercial%'    THEN 'comercial'
        WHEN LOWER(area_comercial) LIKE '%metrolog%'     THEN 'metrologia'
        WHEN LOWER(area_comercial) LIKE '%operacion%'    THEN 'operaciones'
        WHEN LOWER(area_comercial) LIKE '%administra%'   THEN 'administracion'
        WHEN LOWER(area_comercial) LIKE '%gerencia%'     THEN 'gerencia'
        WHEN LOWER(area_comercial) LIKE '%ssoma%'        THEN 'ssoma'
        WHEN LOWER(area_comercial) IN ('ti', 'sistemas') THEN 'ti'
        ELSE NULL
    END
WHERE area_comercial IS NOT NULL;

-- ── 2) base_operativa → sede_operativa (con código del catálogo) ──────────────
ALTER TABLE usuario RENAME COLUMN base_operativa TO sede_operativa;

UPDATE usuario SET sede_operativa = CASE
        WHEN LOWER(sede_operativa) LIKE '%lima%'     THEN 'lima_central'
        WHEN LOWER(sede_operativa) LIKE '%arequipa%' THEN 'arequipa'
        ELSE NULL
    END
WHERE sede_operativa IS NOT NULL;

-- ── 3) Junction de sedes autorizadas ──────────────────────────────────────────
DROP TABLE IF EXISTS usuario_sede_autorizada;

-- ── 4) y 5) Columnas que ya no se usan ───────────────────────────────────────
ALTER TABLE usuario
    DROP COLUMN area_comercial,
    DROP COLUMN id_area,
    DROP COLUMN id_tipo_doc_identidad,
    DROP COLUMN id_persona_contacto;

-- ── 2) Catálogo de sedes de TW (IdMaestro 69) ────────────────────────────────
--    String1 = etiqueta, String2 = código (usuario.sede_operativa), String3 = ubicación
DELETE FROM tabla_maestra WHERE IdMaestro = 69;

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2, String3) VALUES
(1, 69, 'SEDE_OPERATIVA_TW', 1, 'Lima Central', 'lima_central', 'Lima'),
(1, 69, 'SEDE_OPERATIVA_TW', 2, 'Arequipa',     'arequipa',     'Arequipa');

-- ── 1) Catálogo de áreas (IdMaestro 79) ──────────────────────────────────────
--    String1 = etiqueta, String2 = código (usuario.area)
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2) VALUES
(1, 79, 'AREA_USUARIO', 1, 'Comercial',      'comercial'),
(1, 79, 'AREA_USUARIO', 2, 'Metrología',     'metrologia'),
(1, 79, 'AREA_USUARIO', 3, 'Operaciones',    'operaciones'),
(1, 79, 'AREA_USUARIO', 4, 'Administración', 'administracion'),
(1, 79, 'AREA_USUARIO', 5, 'Gerencia',       'gerencia'),
(1, 79, 'AREA_USUARIO', 6, 'SSOMA',          'ssoma'),
(1, 79, 'AREA_USUARIO', 7, 'TI',             'ti');

-- ── 1) CARGO_USUARIO (IdMaestro 80): los cargos se cargarán en otra migración.
--    Formato acordado por fila:
--      String1 = cargo, String2 = código del cargo,
--      Num2    = id del área (Num1 del ítem en AREA_USUARIO),
--      String3 = código del área (ej. 'comercial')
