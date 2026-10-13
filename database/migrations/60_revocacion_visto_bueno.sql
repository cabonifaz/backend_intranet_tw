-- ============================================================
-- Migración 60 — HU-13b: Solicitud de revocación de Visto Bueno
--   Flujo nuevo tras HU-10b: una propuesta ya aprobada por VB puede ser revertida
--   antes de salir al cliente si el comercial la solicita y el jefe la autoriza.
--
--   1. propuesta_comercial.estado ← añade 'pendiente_revocacion'.
--   2. visto_bueno.estado         ← añade 'revocacion_pendiente', 'revocacion_aprobada',
--                                   'revocacion_rechazada'.
--   3. visto_bueno                ← columnas de contexto:
--        tipo ENUM('aprobacion','revocacion') NOT NULL DEFAULT 'aprobacion'
--        motivo_revocacion TEXT   NULL  (el motivo que escribe el comercial)
--        id_vb_padre       BIGINT NULL  (referencia al VB de aprobación que se quiere revocar)
--   4. Acciones (sistema de permisos de la migración 41, módulo propuestas / visto_bueno):
--        propuesta_solicitar_revocacion  nivel 2 (editar)     — módulo propuestas
--        vb_resolver_revocacion          nivel 3 (supervisar) — módulo propuestas
--   IDEMPOTENTE. Sin punto y coma dentro de los comentarios.
-- ============================================================

-- 1. propuesta_comercial.estado
ALTER TABLE propuesta_comercial
    MODIFY COLUMN estado ENUM(
        'borrador', 'pendiente_vb', 'enviado', 'aprobado',
        'rechazado', 'anulado', 'vencido', 'pendiente_revocacion'
    ) NOT NULL DEFAULT 'borrador';

-- 2. visto_bueno.estado
ALTER TABLE visto_bueno
    MODIFY COLUMN estado ENUM(
        'pendiente', 'aprobado', 'rechazado', 'reasignado', 'cancelado', 'devuelto',
        'revocacion_pendiente', 'revocacion_aprobada', 'revocacion_rechazada'
    ) NOT NULL DEFAULT 'pendiente';

-- 3. visto_bueno — columnas de contexto para revocación
SET @t := 'visto_bueno';

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = @t AND COLUMN_NAME = 'tipo'),
    'ALTER TABLE visto_bueno ADD COLUMN tipo ENUM(''aprobacion'',''revocacion'') NOT NULL DEFAULT ''aprobacion'' AFTER estado',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = @t AND COLUMN_NAME = 'motivo_revocacion'),
    'ALTER TABLE visto_bueno ADD COLUMN motivo_revocacion TEXT NULL AFTER tipo',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = @t AND COLUMN_NAME = 'id_vb_padre'),
    'ALTER TABLE visto_bueno ADD COLUMN id_vb_padre BIGINT NULL AFTER motivo_revocacion',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- 4. Acciones del sistema
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2, String3)
SELECT 1, 88, 'ACCION_SISTEMA', 2, 'Solicitar revocación de visto bueno', 'propuesta_solicitar_revocacion', 'propuestas'
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra WHERE IdMaestro = 88 AND IdEmpresa = 1 AND String2 = 'propuesta_solicitar_revocacion');

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2, String3)
SELECT 1, 88, 'ACCION_SISTEMA', 3, 'Resolver solicitudes de revocación de VB', 'vb_resolver_revocacion', 'propuestas'
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra WHERE IdMaestro = 88 AND IdEmpresa = 1 AND String2 = 'vb_resolver_revocacion');
