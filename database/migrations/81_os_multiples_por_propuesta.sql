-- ============================================================
-- Migración 81 — Ajustes de reglas del módulo OS/OM y del versionado de propuestas (2026-10-28)
--   1. os_concepto.alcance: el alcance del ítem de la propuesta ("200 kg"). Los conceptos ya no se fusionan por
--      suministro: cada ítem de servicio de la propuesta es una fila (mismo suministro con distinto alcance = 2 filas).
--      Para las órdenes existentes se completa cuando la propuesta tiene un solo ítem de ese suministro.
--   2. Las OS/OM no tienen borrador: toda orden se emite al guardar. Las órdenes que quedaron en 'borrador'
--      pasan a 'emitida' (se registra en auditoria_evento).
--   3. Una propuesta solo puede tener UNA versión aceptada por número: si hay varias versiones 'aceptado' del mismo
--      número, las anteriores a la última pasan a 'revocada' (bug: al aceptar una versión nueva no se revocaba
--      la aceptada anterior).
--
--   IDEMPOTENTE. Se puede re-ejecutar.
-- ============================================================

-- ── 1. os_concepto.alcance ──────────────────────────────────────────────────
SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'os_concepto' AND COLUMN_NAME = 'alcance'),
    'ALTER TABLE os_concepto ADD COLUMN alcance VARCHAR(100) NULL AFTER descripcion',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

UPDATE os_concepto oc
JOIN orden_servicio os ON os.id_os = oc.id_os
JOIN (SELECT i.id_propuesta, i.id_catalogo_item, MAX(NULLIF(TRIM(i.alcance), '')) AS alcance
      FROM propuesta_item i
      WHERE i.eliminado_en IS NULL AND IFNULL(i.es_espaciado, 0) = 0 AND i.id_catalogo_item IS NOT NULL
      GROUP BY i.id_propuesta, i.id_catalogo_item
      HAVING COUNT(*) = 1) x ON x.id_propuesta = os.id_propuesta AND x.id_catalogo_item = oc.id_suministro
SET oc.alcance = x.alcance
WHERE oc.alcance IS NULL AND x.alcance IS NOT NULL;

-- ── 2. Sin borradores ───────────────────────────────────────────────────────
DROP TEMPORARY TABLE IF EXISTS tmp_m81_borradores;
CREATE TEMPORARY TABLE tmp_m81_borradores AS
SELECT id_os, numero, tipo FROM orden_servicio WHERE estado = 'borrador';

UPDATE orden_servicio os
JOIN tmp_m81_borradores t ON t.id_os = os.id_os
SET os.estado        = 'emitida',
    os.fecha_emision = COALESCE(os.fecha_emision, os.fecha_creacion, os.creado_en, NOW()),
    os.emitido_por   = COALESCE(os.emitido_por, os.creado_por);

INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en)
SELECT 'orden_servicio', t.id_os, 'emitir_os', 'borrador', 'emitida',
       CONCAT('Migración 81: las órdenes no tienen borrador; la ', t.tipo, ' ', t.numero, ' pasa a emitida.'), NULL, NOW()
FROM tmp_m81_borradores t;
DROP TEMPORARY TABLE IF EXISTS tmp_m81_borradores;

-- ── 3. Una sola versión aceptada por número de propuesta ────────────────────
DROP TEMPORARY TABLE IF EXISTS tmp_m81_ultima;
CREATE TEMPORARY TABLE tmp_m81_ultima AS
SELECT numero, MAX(version) AS version
FROM propuesta_comercial
WHERE estado = 'aceptado' AND eliminado_en IS NULL
GROUP BY numero
HAVING COUNT(*) > 1;

DROP TEMPORARY TABLE IF EXISTS tmp_m81_revocar;
CREATE TEMPORARY TABLE tmp_m81_revocar AS
SELECT p.id_propuesta, p.numero, p.version, u.version AS version_vigente
FROM propuesta_comercial p
JOIN tmp_m81_ultima u ON u.numero = p.numero
WHERE p.estado = 'aceptado' AND p.eliminado_en IS NULL AND p.version < u.version;

UPDATE propuesta_comercial p
JOIN tmp_m81_revocar t ON t.id_propuesta = p.id_propuesta
SET p.estado = 'revocada', p.modificado_en = NOW();

INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
SELECT 'propuesta', t.id_propuesta, 'revocacion_por_version', 'aceptado', 'revocada',
       CONCAT('Corrección por bug de versionado: ', t.numero, ' v', t.version, ' revocada porque la v', t.version_vigente,
              ' es la versión aceptada vigente.'), NULL, NOW(), JSON_OBJECT('version_vigente', t.version_vigente)
FROM tmp_m81_revocar t;

DROP TEMPORARY TABLE IF EXISTS tmp_m81_revocar;
DROP TEMPORARY TABLE IF EXISTS tmp_m81_ultima;
