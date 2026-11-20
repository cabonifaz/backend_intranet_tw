-- ============================================================
-- Migración 125 — «¿El servicio tendrá informe físico?» (respuesta del cliente a la programación, HU-37)
--   1. programacion_confirmacion.informe_fisico: lo que se respondió al registrar «Aceptó» (1 = sí, 0 = no; NULL = no se preguntó: otras respuestas o registros anteriores).
--   2. orden_servicio.informe_fisico: lo vigente para la orden (la última aceptación). NULL o 1 = lleva informe físico (la foto del informe a mano es obligatoria en la
--      app móvil, como hasta ahora); 0 = NO lleva: la app no pide esa foto (el registro fotográfico pasa de 9 a 8 evidencias).
--   No cambia datos existentes (todo lo anterior queda NULL = sí). IDEMPOTENTE.
-- ============================================================

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'programacion_confirmacion' AND COLUMN_NAME = 'informe_fisico'),
    'ALTER TABLE programacion_confirmacion ADD COLUMN informe_fisico TINYINT(1) NULL AFTER comentario', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'orden_servicio' AND COLUMN_NAME = 'informe_fisico'),
    'ALTER TABLE orden_servicio ADD COLUMN informe_fisico TINYINT(1) NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- ── Verificación ─────────────────────────────────────────────────────────────
SELECT 'Migración 125 (debe ser 2)' AS verificacion,
       (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND COLUMN_NAME = 'informe_fisico'
          AND TABLE_NAME IN ('programacion_confirmacion', 'orden_servicio')) AS valor;
