-- ============================================================
-- Migración 72 — Observaciones del cliente al Seguimiento Comercial (reunión 2026-10-15)
--   Obs 4. Se elimina el flujo "Cerrar sin venta" y queda unificado con el Rechazo:
--      a. MOTIVO_RECHAZO (10) recibe el motivo "Cliente dejó de responder" (CLIENTE_INACTIVO),
--         el único de MOTIVO_CIERRE_SIN_VENTA (12) que no tenía equivalente
--      b. Los cierres sin venta ya registrados pasan a cerrado_rechazo con su motivo equivalente
--      c. seguimiento_comercial.estado deja de aceptar cerrado_sin_venta
--      d. MOTIVO_CIERRE_SIN_VENTA queda dado de baja (eliminado_en)
--   Obs 2. Notificación anticipada de las acciones de seguimiento:
--      a. minutos_antes_notificar en seguimiento_comercial (acción programada al registrar)
--         y en seguimiento_reprogramacion (acción reprogramada)
--      b. seguimiento_recordatorio: cola de recordatorios que procesa el worker
--         (pendiente, enviado, cancelado u omitido)
--   Obs 1. Primera acción automática al enviar la propuesta al cliente:
--      a. propuesta_comercial.primera_accion_* (tipo, fecha, prioridad, responsable y aviso)
--      b. PARAMETRO_PROPUESTA SEGUIMIENTO_PRIMERA_ACCION_MINUTOS = 5 (plazo máximo de la llamada)
--   Obs 3 (evidencia obligatoria en la aceptación) no cambia tablas: la valida SP_CerrarSeguimiento.
--
--   IDEMPOTENTE. Se puede re-ejecutar.
-- ============================================================

-- ── Obs 4. Cerrar sin venta unificado con Rechazo ──────────────────────────

-- a. Motivo "Cliente dejó de responder" en MOTIVO_RECHAZO
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2)
SELECT 1, 10, 'MOTIVO_RECHAZO',
       (SELECT IFNULL(MAX(Num1), 0) + 1 FROM tabla_maestra WHERE IdMaestro = 10 AND IdEmpresa = 1),
       'Cliente dejó de responder', 'CLIENTE_INACTIVO'
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra WHERE IdMaestro = 10 AND IdEmpresa = 1 AND String2 = 'CLIENTE_INACTIVO');

-- b. Cierres sin venta existentes pasan a rechazo (motivo equivalente por código)
UPDATE seguimiento_comercial s
JOIN tabla_maestra sv ON sv.IdMaestro = 12 AND sv.IdEmpresa = 1 AND sv.Num1 = s.id_motivo_cierre
LEFT JOIN tabla_maestra rz ON rz.IdMaestro = 10 AND rz.IdEmpresa = 1
                          AND rz.String2 = CASE sv.String2
                                               WHEN 'POSTERGADO_INDEFINIDO' THEN 'POSTERGADO'
                                               ELSE sv.String2
                                           END
SET s.id_motivo_cierre = IFNULL(rz.Num1, (SELECT x.Num1 FROM (SELECT Num1 FROM tabla_maestra
                                                              WHERE IdMaestro = 10 AND IdEmpresa = 1 AND String2 = 'OTRO') x)),
    s.estado = 'cerrado_rechazo'
WHERE s.estado = 'cerrado_sin_venta';

UPDATE seguimiento_comercial SET estado = 'cerrado_rechazo' WHERE estado = 'cerrado_sin_venta';

-- c. El ENUM deja de aceptar cerrado_sin_venta
SET @sql := IF(EXISTS (SELECT 1 FROM information_schema.COLUMNS
                       WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'seguimiento_comercial'
                         AND COLUMN_NAME = 'estado' AND COLUMN_TYPE LIKE '%cerrado_sin_venta%'),
    'ALTER TABLE seguimiento_comercial MODIFY COLUMN estado ENUM(''activo'',''cerrado_aceptacion'',''cerrado_rechazo'') NOT NULL',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- d. Catálogo MOTIVO_CIERRE_SIN_VENTA dado de baja
UPDATE tabla_maestra SET eliminado_en = NOW()
WHERE IdMaestro = 12 AND IdEmpresa = 1 AND eliminado_en IS NULL;

-- ── Obs 2. Notificación anticipada ─────────────────────────────────────────

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'seguimiento_comercial'
                             AND COLUMN_NAME = 'minutos_antes_notificar'),
    'ALTER TABLE seguimiento_comercial ADD COLUMN minutos_antes_notificar INT NULL AFTER id_prioridad_accion',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'seguimiento_reprogramacion'
                             AND COLUMN_NAME = 'minutos_antes_notificar'),
    'ALTER TABLE seguimiento_reprogramacion ADD COLUMN minutos_antes_notificar INT NULL AFTER id_responsable_nuevo',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- Cola de recordatorios. origen: registro (seguimiento_comercial), reprogramacion o envio (primera acción).
-- fecha_notificar = fecha_accion - minutos_antes. lote = marca del worker que lo tomó.
CREATE TABLE IF NOT EXISTS seguimiento_recordatorio (
    id_recordatorio     BIGINT          NOT NULL AUTO_INCREMENT,
    id_propuesta        BIGINT          NOT NULL,
    origen              ENUM('registro','reprogramacion','envio') NOT NULL,
    id_origen           BIGINT          NULL,
    id_usuario_destino  BIGINT          NOT NULL,
    id_tipo_accion      INT             NULL,
    fecha_accion        DATETIME        NOT NULL,
    minutos_antes       INT             NOT NULL,
    fecha_notificar     DATETIME        NOT NULL,
    estado              ENUM('pendiente','enviado','cancelado','omitido') NOT NULL DEFAULT 'pendiente',
    lote                VARCHAR(40)     NULL,
    fecha_procesado     DATETIME        NULL,
    id_notificacion     BIGINT          NULL,
    -- AUDITORÍA
    creado_en           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por          BIGINT          NULL,
    modificado_en       DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por      BIGINT          NULL,
    eliminado_en        DATETIME        NULL,
    eliminado_por       BIGINT          NULL,
    PRIMARY KEY (id_recordatorio)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ── Obs 1. Primera acción automática al enviar la propuesta ────────────────

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'propuesta_comercial'
                             AND COLUMN_NAME = 'primera_accion_fecha'),
    'ALTER TABLE propuesta_comercial
        ADD COLUMN primera_accion_fecha          DATETIME NULL,
        ADD COLUMN id_tipo_primera_accion        INT      NULL,
        ADD COLUMN id_prioridad_primera_accion   INT      NULL,
        ADD COLUMN id_responsable_primera_accion BIGINT   NULL,
        ADD COLUMN minutos_primera_accion        INT      NULL',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @id_param := (SELECT MAX(IdMaestro) FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROPUESTA');
SET @n_param  := (SELECT IFNULL(MAX(Num1), 0) FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROPUESTA');

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, Num2, String1, String2)
SELECT 1, @id_param, 'PARAMETRO_PROPUESTA', @n_param + 1, 5,
       'Minutos para la primera llamada de seguimiento tras enviar la propuesta al cliente',
       'SEGUIMIENTO_PRIMERA_ACCION_MINUTOS'
FROM DUAL
WHERE @id_param IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROPUESTA'
                                                AND String2 = 'SEGUIMIENTO_PRIMERA_ACCION_MINUTOS');
