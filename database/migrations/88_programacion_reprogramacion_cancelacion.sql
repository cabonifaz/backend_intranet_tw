-- ============================================================
-- Migración 88 — Reprogramación y cancelación de la Programación (HU-38, Sprint 5)
--   1. os_reprogramacion (HU-35) ahora también guarda QUÉ se propone: la programación a la que se refiere, la hora fin, el técnico
--      principal, el apoyo y los equipos propuestos (NULL = sin cambios). Las solicitudes ya existentes siguen siendo válidas.
--   2. programacion guarda la cancelación: motivo tipificado, comentario, fecha y usuario.
--   3. Catálogos (por código, sin duplicar lo que ya exista):
--        MOTIVO_REPROGRAMACION (13): se agregan 'SSOMA sobrevenido' e 'Imprevisto operativo' si faltan
--        MOTIVO_CANCELACION_PROGRAMACION (nuevo): Cliente canceló · Cliente pidió reprogramar indefinidamente · Técnico no disponible ·
--        Falta de insumos · Imprevisto operativo · Error de registro · Otro
--   4. PARAMETRO_PROGRAMACION: CANCELACION_COMENTARIO_MIN (0). Largo mínimo del comentario al cancelar: 0 = opcional (criterio de
--      aceptación); 20 = obligatorio de 20 caracteres (como en el mockup).
--   No borra ni cambia datos existentes. IDEMPOTENTE. Ejecutar junto con los SPs de este mismo paquete.
-- ============================================================

-- ── 1. Solicitudes de reprogramación: la propuesta completa ───────────────────
SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'os_reprogramacion' AND COLUMN_NAME = 'id_programacion'),
    'ALTER TABLE os_reprogramacion ADD COLUMN id_programacion BIGINT NULL AFTER id_os', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'os_reprogramacion' AND COLUMN_NAME = 'hora_fin_propuesta'),
    'ALTER TABLE os_reprogramacion ADD COLUMN hora_fin_propuesta TIME NULL AFTER hora_propuesta', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'os_reprogramacion' AND COLUMN_NAME = 'id_tecnico_propuesto'),
    'ALTER TABLE os_reprogramacion ADD COLUMN id_tecnico_propuesto BIGINT NULL AFTER hora_fin_propuesta', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'os_reprogramacion' AND COLUMN_NAME = 'ids_apoyo_propuestos'),
    'ALTER TABLE os_reprogramacion ADD COLUMN ids_apoyo_propuestos JSON NULL AFTER id_tecnico_propuesto', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'os_reprogramacion' AND COLUMN_NAME = 'ids_equipos_propuestos'),
    'ALTER TABLE os_reprogramacion ADD COLUMN ids_equipos_propuestos JSON NULL AFTER ids_apoyo_propuestos', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'os_reprogramacion' AND INDEX_NAME = 'ix_os_reprogramacion_prog'),
    'ALTER TABLE os_reprogramacion ADD KEY ix_os_reprogramacion_prog (id_programacion, estado)', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- ── 2. Programación: datos de la cancelación ──────────────────────────────────
SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'programacion' AND COLUMN_NAME = 'id_motivo_cancelacion'),
    'ALTER TABLE programacion ADD COLUMN id_motivo_cancelacion INT NULL AFTER observaciones', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'programacion' AND COLUMN_NAME = 'comentario_cancelacion'),
    'ALTER TABLE programacion ADD COLUMN comentario_cancelacion VARCHAR(500) NULL AFTER id_motivo_cancelacion', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'programacion' AND COLUMN_NAME = 'cancelada_en'),
    'ALTER TABLE programacion ADD COLUMN cancelada_en DATETIME NULL AFTER comentario_cancelacion', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'programacion' AND COLUMN_NAME = 'cancelada_por'),
    'ALTER TABLE programacion ADD COLUMN cancelada_por BIGINT NULL AFTER cancelada_en', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- ── 3. Catálogos de motivos ───────────────────────────────────────────────────
-- 3.1 Motivos de reprogramación (13): solo los que faltan, con el siguiente Num1 libre
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2)
SELECT 1, 13, 'MOTIVO_REPROGRAMACION',
       (SELECT IFNULL(MAX(m.Num1), 0) FROM tabla_maestra m WHERE m.IdMaestro = 13 AND m.IdEmpresa = 1) + 1, 'SSOMA sobrevenido', 'SSOMA_SOBREVENIDO'
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra t WHERE t.IdMaestro = 13 AND t.IdEmpresa = 1 AND t.String2 = 'SSOMA_SOBREVENIDO');

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2)
SELECT 1, 13, 'MOTIVO_REPROGRAMACION',
       (SELECT IFNULL(MAX(m.Num1), 0) FROM tabla_maestra m WHERE m.IdMaestro = 13 AND m.IdEmpresa = 1) + 1, 'Imprevisto operativo', 'IMPREVISTO_OPERATIVO'
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra t WHERE t.IdMaestro = 13 AND t.IdEmpresa = 1 AND t.String2 = 'IMPREVISTO_OPERATIVO');

-- 3.2 Motivos de cancelación de la programación (catálogo nuevo; si ya existe se reutiliza su IdMaestro)
SET @id_cancel := (SELECT MAX(IdMaestro) FROM tabla_maestra WHERE Descripcion = 'MOTIVO_CANCELACION_PROGRAMACION');
SET @id_cancel := IFNULL(@id_cancel, (SELECT MAX(IdMaestro) + 1 FROM tabla_maestra));

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2)
SELECT 1, @id_cancel, 'MOTIVO_CANCELACION_PROGRAMACION', x.n, x.nombre, x.codigo
FROM (SELECT 1 AS n, 'Cliente canceló el servicio' AS nombre, 'CLIENTE_CANCELO' AS codigo UNION ALL
      SELECT 2, 'Cliente pidió reprogramar indefinidamente', 'CLIENTE_REPROGRAMA_INDEFINIDO' UNION ALL
      SELECT 3, 'Técnico no disponible',                     'TECNICO_NO_DISPONIBLE'          UNION ALL
      SELECT 4, 'Falta de insumos',                          'FALTA_INSUMOS'                  UNION ALL
      SELECT 5, 'Imprevisto operativo',                      'IMPREVISTO_OPERATIVO'           UNION ALL
      SELECT 6, 'Error de registro',                         'ERROR_REGISTRO'                 UNION ALL
      SELECT 7, 'Otro',                                      'OTRO') x
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra t WHERE t.Descripcion = 'MOTIVO_CANCELACION_PROGRAMACION' AND t.IdEmpresa = 1 AND t.String2 = x.codigo);

-- ── 4. Parámetro ──────────────────────────────────────────────────────────────
SET @id_param := (SELECT MAX(IdMaestro) FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROGRAMACION');
SET @id_param := IFNULL(@id_param, (SELECT MAX(IdMaestro) + 1 FROM tabla_maestra));

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, Num2, String1, String2)
SELECT 1, @id_param, 'PARAMETRO_PROGRAMACION', 7, 0, 'Largo mínimo del comentario al cancelar una programación (0 = opcional; 20 = obligatorio)', 'CANCELACION_COMENTARIO_MIN'
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra t WHERE t.Descripcion = 'PARAMETRO_PROGRAMACION' AND t.IdEmpresa = 1 AND t.String2 = 'CANCELACION_COMENTARIO_MIN');

-- ── Verificación ─────────────────────────────────────────────────────────────
SELECT 'Migración 88 (debe ser 20)' AS verificacion,
       (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'os_reprogramacion'
          AND COLUMN_NAME IN ('id_programacion', 'hora_fin_propuesta', 'id_tecnico_propuesto', 'ids_apoyo_propuestos', 'ids_equipos_propuestos'))
     + (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'programacion'
          AND COLUMN_NAME IN ('id_motivo_cancelacion', 'comentario_cancelacion', 'cancelada_en', 'cancelada_por'))
     + (SELECT COUNT(DISTINCT String2) FROM tabla_maestra WHERE Descripcion = 'MOTIVO_CANCELACION_PROGRAMACION' AND IdEmpresa = 1)
     + (SELECT COUNT(DISTINCT String2) FROM tabla_maestra WHERE IdMaestro = 13 AND IdEmpresa = 1
          AND String2 IN ('SSOMA_SOBREVENIDO', 'IMPREVISTO_OPERATIVO'))
     + (SELECT COUNT(*) FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'os_reprogramacion' AND INDEX_NAME = 'ix_os_reprogramacion_prog' AND SEQ_IN_INDEX = 1)
     + (SELECT COUNT(DISTINCT String2) FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROGRAMACION' AND IdEmpresa = 1 AND String2 = 'CANCELACION_COMENTARIO_MIN') AS valor;
