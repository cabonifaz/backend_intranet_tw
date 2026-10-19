-- ============================================================
-- Migración 57 — HU-20 Reprogramación de acciones de seguimiento
--   1. seguimiento_reprogramacion: historial de cada reprogramación (acción anterior y nueva,
--      motivo y detalle). id_seguimiento = seguimiento cuya acción se reprogramó
--      (NULL = el "Primer seguimiento", cuando la propuesta aún no tiene seguimientos).
--   2. Catálogo MOTIVO_REPROGRAMACION_SEGUIMIENTO (Num1 = id, String1 = nombre, String2 = código)
--      (distinto de MOTIVO_REPROGRAMACION = 13, que es para reprogramar servicios técnicos)
--   3. Acción propuesta_seguimiento_reprogramar (nivel 2: asistente, jefe y administrador del área)
--
--   IDEMPOTENTE. Se puede re-ejecutar.
-- ============================================================

-- 1. Historial de reprogramaciones
CREATE TABLE IF NOT EXISTS seguimiento_reprogramacion (
    id_reprogramacion        BIGINT          NOT NULL AUTO_INCREMENT,
    id_propuesta             BIGINT          NOT NULL,
    id_seguimiento           BIGINT          NULL,
    -- Acción anterior
    fecha_anterior           DATETIME        NULL,
    id_tipo_accion_anterior  INT             NULL,
    id_prioridad_anterior    INT             NULL,
    id_responsable_anterior  BIGINT          NULL,
    -- Acción nueva
    fecha_nueva              DATETIME        NOT NULL,
    id_tipo_accion_nueva     INT             NOT NULL,
    id_prioridad_nueva       INT             NOT NULL,
    id_responsable_nuevo     BIGINT          NOT NULL,
    -- Motivo
    id_motivo                INT             NOT NULL,
    detalle                  VARCHAR(500)    NOT NULL,
    -- AUDITORÍA
    creado_en                DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por               BIGINT          NULL,
    modificado_en            DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por           BIGINT          NULL,
    eliminado_en             DATETIME        NULL,
    eliminado_por            BIGINT          NULL,
    PRIMARY KEY (id_reprogramacion)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- 2. Motivos de reprogramación (el IdMaestro se reserva al crear la primera fila)
SET @id_motivo := (SELECT MAX(IdMaestro) FROM tabla_maestra WHERE Descripcion = 'MOTIVO_REPROGRAMACION_SEGUIMIENTO');
SET @id_motivo := IFNULL(@id_motivo, (SELECT MAX(IdMaestro) + 1 FROM tabla_maestra));

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2)
SELECT 1, @id_motivo, 'MOTIVO_REPROGRAMACION_SEGUIMIENTO', t.id, t.nombre, t.codigo
FROM (
          SELECT 1 AS id, 'Cliente solicita nueva fecha' AS nombre, 'CLIENTE_NUEVA_FECHA' AS codigo
UNION ALL SELECT 2, 'Sin respuesta',                'SIN_RESPUESTA'
UNION ALL SELECT 3, 'Dependencia interna',          'DEPENDENCIA_INTERNA'
UNION ALL SELECT 4, 'Esperando información',        'ESPERANDO_INFORMACION'
) t
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra x
                  WHERE x.Descripcion = 'MOTIVO_REPROGRAMACION_SEGUIMIENTO' AND x.String2 = t.codigo);

-- 3. Acción
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2, String3)
SELECT 1, 88, 'ACCION_SISTEMA', 2, 'Reprogramar acciones de seguimiento comercial',
       'propuesta_seguimiento_reprogramar', 'propuestas'
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra
                  WHERE IdMaestro = 88 AND IdEmpresa = 1 AND String2 = 'propuesta_seguimiento_reprogramar');
