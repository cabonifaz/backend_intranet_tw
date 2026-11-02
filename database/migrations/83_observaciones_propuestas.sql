-- ============================================================
-- Migración 83 — Observaciones del cliente Sprint 3 y 4 (31/10): Propuestas
--   1. Catálogo TIPO_PROPUESTA (106): Venta directa / Equipos evaluados / Servicio metrológico / Adicional a la
--      ejecución. Num2 = 1 → solo si el RQ "entra al sistema de acreditación" (requerimiento.es_inacal).
--      propuesta_comercial.tipo_servicio guarda el nombre (String1), igual que la data existente.
--   2. propuesta_comercial.referencia: VARCHAR(500) → VARCHAR(2000) (se precarga con el detalle del RQ, no editable).
--   3. propuesta_comercial.id_cliente_tercero: cliente intermediario elegido de la BD (servicio tercerizado).
--   4. propuesta_aplicar_descuento: nivel 3 → 2 (el comercial puede aplicar el descuento global).
--   5. CONDICION_PAGO (39) tenía filas duplicadas (mismo código cargado dos veces): se dan de baja las copias
--      (se conserva la fila más antigua de cada código). Causaba formas de pago repetidas en el detalle.
--
--   IDEMPOTENTE. Se puede re-ejecutar.
-- ============================================================

-- ── 1. Tipo de propuesta ────────────────────────────────────────────────────
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, Num2, String1, String2)
SELECT 1, 106, 'TIPO_PROPUESTA', x.n, x.req, x.nombre, x.codigo
FROM (SELECT 1 AS n, 0 AS req, 'Venta directa' AS nombre, 'venta_directa' AS codigo
      UNION ALL SELECT 2, 0, 'Equipos evaluados',        'equipos_evaluados'
      UNION ALL SELECT 3, 1, 'Servicio metrológico',     'servicio_metrologico'
      UNION ALL SELECT 4, 0, 'Adicional a la ejecución', 'adicional_ejecucion') x
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra t WHERE t.IdMaestro = 106 AND t.IdEmpresa = 1 AND t.String2 = x.codigo);

-- ── 2. Referencia más larga ─────────────────────────────────────────────────
SET @sql := IF(EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE()
                         AND TABLE_NAME = 'propuesta_comercial' AND COLUMN_NAME = 'referencia'
                         AND CHARACTER_MAXIMUM_LENGTH < 2000),
    'ALTER TABLE propuesta_comercial MODIFY COLUMN referencia VARCHAR(2000) NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- ── 3. Cliente intermediario ────────────────────────────────────────────────
SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE()
                             AND TABLE_NAME = 'propuesta_comercial' AND COLUMN_NAME = 'id_cliente_tercero'),
    'ALTER TABLE propuesta_comercial ADD COLUMN id_cliente_tercero BIGINT NULL AFTER es_tercerizado', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- Las tercerizadas existentes se enlazan con el cliente del mismo RUC, si existe
UPDATE propuesta_comercial p
JOIN cliente c ON c.ruc = p.tercero_ruc AND c.SoftDelete = 0 AND c.eliminado_en IS NULL
SET p.id_cliente_tercero = c.id_cliente
WHERE p.es_tercerizado = 1 AND p.id_cliente_tercero IS NULL AND IFNULL(p.tercero_ruc, '') <> '';

-- ── 4. Descuento global para el comercial ───────────────────────────────────
UPDATE tabla_maestra SET Num1 = 2
WHERE IdMaestro = 88 AND IdEmpresa = 1 AND String2 = 'propuesta_aplicar_descuento' AND Num1 <> 2;

-- ── 5. Condiciones de pago duplicadas ───────────────────────────────────────
DROP TEMPORARY TABLE IF EXISTS tmp_m83_cond;
CREATE TEMPORARY TABLE tmp_m83_cond AS
SELECT String2, MIN(IdTablaMaestra) AS id_conservar
FROM tabla_maestra
WHERE IdMaestro = 39 AND IdEmpresa = 1 AND eliminado_en IS NULL
GROUP BY String2;

UPDATE tabla_maestra t
JOIN tmp_m83_cond c ON c.String2 = t.String2
SET t.eliminado_en = NOW()
WHERE t.IdMaestro = 39 AND t.IdEmpresa = 1 AND t.eliminado_en IS NULL AND t.IdTablaMaestra <> c.id_conservar;
DROP TEMPORARY TABLE IF EXISTS tmp_m83_cond;
