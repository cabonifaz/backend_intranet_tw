-- ============================================================
-- Migración 49 — VB sin aprobador asignado individual.
--   En el nuevo modelo (bandeja compartida por área + rol), ya no se asigna un aprobador
--   único al enviar a VB. Todos los supervisores/administradores del área del comercial
--   autor ven la propuesta en su bandeja. El `id_aprobador` deja de ser gating y pasa a
--   ser nullable: queda null al enviar, y se llena con `resuelto_por` cuando alguien del
--   equipo del área la resuelve.
-- IDEMPOTENTE.
-- ============================================================

SET @actual = (SELECT IS_NULLABLE FROM INFORMATION_SCHEMA.COLUMNS
               WHERE TABLE_SCHEMA = DATABASE()
                 AND TABLE_NAME   = 'visto_bueno'
                 AND COLUMN_NAME  = 'id_aprobador');
SET @sql = IF(@actual = 'NO',
              'ALTER TABLE visto_bueno MODIFY COLUMN id_aprobador BIGINT NULL',
              'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
