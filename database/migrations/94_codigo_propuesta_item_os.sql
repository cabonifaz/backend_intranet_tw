-- ============================================================
-- Migración 94 — Pedidos de Jazir 06/11
--   #4437 propuesta_comercial.codigo_formateado: código para mostrar "PC: 0012-2-2026" (correlativo de 4 dígitos ·
--         versión · año de creación de la versión). Columna GENERADA (virtual): se calcula sola, no se escribe nunca y
--         la usan todos los SPs que devuelven una propuesta (OC, OS, expedientes, VB, seguimiento…).
--         El número interno (PROP-000012) no cambia.
--   #4435 os_concepto.id_item: línea de la propuesta (propuesta_item) de la que sale cada concepto de la OS, para
--         distinguir el mismo suministro con distinto alcance.
--   No borra ni cambia datos existentes. IDEMPOTENTE. Sin procedimientos auxiliares.
-- ============================================================

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE()
                             AND TABLE_NAME = 'propuesta_comercial' AND COLUMN_NAME = 'codigo_formateado'),
    'ALTER TABLE propuesta_comercial ADD COLUMN codigo_formateado VARCHAR(40) GENERATED ALWAYS AS (CONCAT(''PC: '', IF(CHAR_LENGTH(CAST(CAST(SUBSTRING_INDEX(numero, ''-'', -1) AS UNSIGNED) AS CHAR)) >= 4, CAST(CAST(SUBSTRING_INDEX(numero, ''-'', -1) AS UNSIGNED) AS CHAR), LPAD(CAST(SUBSTRING_INDEX(numero, ''-'', -1) AS UNSIGNED), 4, ''0'')), ''-'', version, ''-'', YEAR(fecha_creacion))) VIRTUAL',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE()
                             AND TABLE_NAME = 'os_concepto' AND COLUMN_NAME = 'id_item'),
    'ALTER TABLE os_concepto ADD COLUMN id_item BIGINT NULL AFTER id_suministro', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- Conceptos ya guardados: se enlazan con la línea de la propuesta del mismo suministro y alcance (si es única)
UPDATE os_concepto oc
JOIN orden_servicio os ON os.id_os = oc.id_os
JOIN propuesta_item i  ON i.id_propuesta = os.id_propuesta AND i.id_catalogo_item = oc.id_suministro
                      AND IFNULL(NULLIF(TRIM(i.alcance), ''), '') = IFNULL(oc.alcance, '') AND i.eliminado_en IS NULL
SET oc.id_item = i.id_item
WHERE oc.id_item IS NULL AND oc.eliminado_en IS NULL
  AND (SELECT COUNT(*) FROM propuesta_item i2
       WHERE i2.id_propuesta = os.id_propuesta AND i2.id_catalogo_item = oc.id_suministro AND i2.eliminado_en IS NULL
         AND IFNULL(NULLIF(TRIM(i2.alcance), ''), '') = IFNULL(oc.alcance, '')) = 1;

SELECT 'Migración 94 (debe ser 2)' AS verificacion,
       (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE()
          AND ((TABLE_NAME = 'propuesta_comercial' AND COLUMN_NAME = 'codigo_formateado')
            OR (TABLE_NAME = 'os_concepto' AND COLUMN_NAME = 'id_item'))) AS valor;
