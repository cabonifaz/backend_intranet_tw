-- ============================================================
-- Migración 95 — Número de la propuesta en formato "PC-0012-1-2026" (acuerdo del daily 06/11)
--   El número que se guarda y se muestra en todo el sistema pasa a ser PC-<correlativo 4 dígitos>-<versión>-<año>
--   (año de creación de la versión). Desaparece el campo aparte codigo_formateado.
--   1. propuesta_comercial.numero (PROP-000012) se renombra a numero_base: es el correlativo que agrupa las versiones de
--      una misma propuesta (v1, v2…). No se muestra; lo usan los SPs para "última versión", historial, seguimiento, etc.
--   2. propuesta_comercial.numero pasa a ser una columna GENERADA (STORED): se calcula sola a partir de numero_base,
--      version y fecha_creacion, queda guardada en la tabla y nadie la escribe.
--   3. Se elimina codigo_formateado (migración 94).
--   Reversible: numero_base conserva el número original. IDEMPOTENTE.
-- ============================================================

-- 3. Sin campo aparte
SET @sql := IF(EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE()
                         AND TABLE_NAME = 'propuesta_comercial' AND COLUMN_NAME = 'codigo_formateado'),
    'ALTER TABLE propuesta_comercial DROP COLUMN codigo_formateado', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- 1. numero → numero_base (solo si todavía no se hizo)
SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE()
                             AND TABLE_NAME = 'propuesta_comercial' AND COLUMN_NAME = 'numero_base'),
    'ALTER TABLE propuesta_comercial CHANGE COLUMN numero numero_base VARCHAR(20) NOT NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- 2. numero = "PC-0012-1-2026" (generado y guardado)
SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE()
                             AND TABLE_NAME = 'propuesta_comercial' AND COLUMN_NAME = 'numero'),
    'ALTER TABLE propuesta_comercial ADD COLUMN numero VARCHAR(30) GENERATED ALWAYS AS (CONCAT(''PC-'', IF(CHAR_LENGTH(CAST(CAST(SUBSTRING_INDEX(numero_base, ''-'', -1) AS UNSIGNED) AS CHAR)) >= 4, CAST(CAST(SUBSTRING_INDEX(numero_base, ''-'', -1) AS UNSIGNED) AS CHAR), LPAD(CAST(SUBSTRING_INDEX(numero_base, ''-'', -1) AS UNSIGNED), 4, ''0'')), ''-'', version, ''-'', YEAR(fecha_creacion))) STORED AFTER id_propuesta',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- 2b. Si la columna ya existía con el formato anterior ("PC: "), se corrige a "PC-" (separador guion, acuerdo 06/11)
SET @sql := IF(EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE()
                         AND TABLE_NAME = 'propuesta_comercial' AND COLUMN_NAME = 'numero'
                         AND GENERATION_EXPRESSION LIKE '%PC: %'),
    'ALTER TABLE propuesta_comercial MODIFY COLUMN numero VARCHAR(30) GENERATED ALWAYS AS (CONCAT(''PC-'', IF(CHAR_LENGTH(CAST(CAST(SUBSTRING_INDEX(numero_base, ''-'', -1) AS UNSIGNED) AS CHAR)) >= 4, CAST(CAST(SUBSTRING_INDEX(numero_base, ''-'', -1) AS UNSIGNED) AS CHAR), LPAD(CAST(SUBSTRING_INDEX(numero_base, ''-'', -1) AS UNSIGNED), 4, ''0'')), ''-'', version, ''-'', YEAR(fecha_creacion))) STORED',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE()
                             AND TABLE_NAME = 'propuesta_comercial' AND INDEX_NAME = 'ix_prop_numero_pc'),
    'ALTER TABLE propuesta_comercial ADD KEY ix_prop_numero_pc (numero)', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SELECT 'Migración 95' AS verificacion,
       IF((SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'propuesta_comercial'
             AND COLUMN_NAME IN ('numero', 'numero_base')) = 2
          AND (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'propuesta_comercial'
             AND COLUMN_NAME = 'codigo_formateado') = 0
          AND (SELECT COUNT(*) FROM propuesta_comercial WHERE numero NOT LIKE 'PC-%') = 0, 'OK', 'REVISAR') AS estado,
       (SELECT CONCAT(numero_base, ' v', version, ' → ', numero) FROM propuesta_comercial ORDER BY id_propuesta DESC LIMIT 1) AS ejemplo;
