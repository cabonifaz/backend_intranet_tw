-- ============================================================
-- Migración 59 — HU-10b: Envío de propuesta al cliente (post VB aprobado)
--   1. propuesta_comercial: columnas que registran el envío al cliente
--        (fecha_envio_cliente, enviado_cliente_por).
--   2. Acción (sistema de permisos de la migración 41, módulo propuestas):
--        propuesta_enviar_cliente  nivel 2 (editar)
--   IDEMPOTENTE. Sin punto y coma dentro de los comentarios.
-- ============================================================

-- 1. Columnas de envío al cliente
SET @t := 'propuesta_comercial';

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = @t AND COLUMN_NAME = 'fecha_envio_cliente'),
    'ALTER TABLE propuesta_comercial ADD COLUMN fecha_envio_cliente DATETIME NULL',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = @t AND COLUMN_NAME = 'enviado_cliente_por'),
    'ALTER TABLE propuesta_comercial ADD COLUMN enviado_cliente_por BIGINT NULL AFTER fecha_envio_cliente',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- 2. Acción
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2, String3)
SELECT 1, 88, 'ACCION_SISTEMA', 2, 'Enviar propuesta al cliente', 'propuesta_enviar_cliente', 'propuestas'
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra WHERE IdMaestro = 88 AND IdEmpresa = 1 AND String2 = 'propuesta_enviar_cliente');
