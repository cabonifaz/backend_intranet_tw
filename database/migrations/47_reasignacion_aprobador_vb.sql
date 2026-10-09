-- ============================================================
-- Migración 47 — HU-16: Reasignación de Aprobador
--   1. visto_bueno: id_vb_origen (el VB nuevo apunta al VB reasignado) e
--      id_motivo_reasignacion (guardado en el VB que se reasigna).
--      Al reasignar, el VB actual pasa a 'reasignado' y se crea uno nuevo
--      'pendiente' con el nuevo aprobador. Si no se reinicia el SLA, el nuevo
--      VB conserva la fecha de solicitud original.
--   2. Catálogo MOTIVO_REASIGNACION_VB (String1 = motivo).
--   3. Acción propuesta_vb_reasignar (módulo propuestas, nivel 3 supervisar).
--   IDEMPOTENTE. Sin punto y coma dentro de los comentarios.
-- ============================================================

-- 1. visto_bueno
SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE()
                           AND TABLE_NAME = 'visto_bueno' AND COLUMN_NAME = 'id_vb_origen'),
    'ALTER TABLE visto_bueno ADD COLUMN id_vb_origen BIGINT NULL AFTER id_aprobador', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE()
                           AND TABLE_NAME = 'visto_bueno' AND COLUMN_NAME = 'id_motivo_reasignacion'),
    'ALTER TABLE visto_bueno ADD COLUMN id_motivo_reasignacion INT NULL AFTER id_vb_origen', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- 2. MOTIVO_REASIGNACION_VB
SET @id_mot := (SELECT MAX(IdMaestro) FROM tabla_maestra WHERE Descripcion = 'MOTIVO_REASIGNACION_VB');
SET @id_mot := IFNULL(@id_mot, (SELECT MAX(IdMaestro) + 1 FROM tabla_maestra));

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2)
SELECT 1, @id_mot, 'MOTIVO_REASIGNACION_VB', m.orden, m.nombre, m.codigo
FROM (
          SELECT 1 AS orden, 'Excede la jurisdicción del aprobador' AS nombre, 'EXCEDE_JURISDICCION' AS codigo
UNION ALL SELECT 2, 'Requiere análisis de otra área',      'OTRA_AREA'
UNION ALL SELECT 3, 'Ausencia o vacaciones del aprobador', 'AUSENCIA'
UNION ALL SELECT 4, 'Carga de trabajo del aprobador',      'CARGA_TRABAJO'
UNION ALL SELECT 5, 'Conflicto de interés',                'CONFLICTO_INTERES'
UNION ALL SELECT 6, 'Otro motivo',                         'OTRO'
) m
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra x WHERE x.Descripcion = 'MOTIVO_REASIGNACION_VB' AND x.String2 = m.codigo);

-- 3. Acción
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2, String3)
SELECT 1, 88, 'ACCION_SISTEMA', 3, 'Reasignar el aprobador de un visto bueno', 'propuesta_vb_reasignar', 'propuestas'
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra WHERE IdMaestro = 88 AND IdEmpresa = 1 AND String2 = 'propuesta_vb_reasignar');
