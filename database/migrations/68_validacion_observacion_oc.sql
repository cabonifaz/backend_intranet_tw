-- ============================================================
-- Migración 68 — HU-26 Validación y Observación de Orden de Compra
--   1. Acción oc_validar (nivel 3 = supervisar, módulo propuestas): jefe y administrador comercial
--      (y administradores de Gerencia y TI). Valida u observa la OC.
--   2. orden_compra_observacion: cada observación con su detalle, responsable de corrección y estado
--      (abierta | levantada). Se levanta al corregir la OC con "Guardar y revalidar" (HU-24).
--   3. orden_compra_observacion_motivo: motivos tipificados (MOTIVO_OBSERVACION_OC, IdMaestro 14) de cada observación
--
--   IDEMPOTENTE. Se puede re-ejecutar.
-- ============================================================

-- 1. Acción
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2, String3)
SELECT 1, 88, 'ACCION_SISTEMA', 3, 'Validar u observar órdenes de compra', 'oc_validar', 'propuestas'
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra WHERE IdMaestro = 88 AND IdEmpresa = 1 AND String2 = 'oc_validar');

-- 2. Observaciones
CREATE TABLE IF NOT EXISTS orden_compra_observacion (
    id_observacion            BIGINT        NOT NULL AUTO_INCREMENT,
    id_oc                     BIGINT        NOT NULL,
    detalle                   VARCHAR(1000) NOT NULL,
    id_responsable_correccion BIGINT        NOT NULL,
    estado                    ENUM('abierta','levantada') NOT NULL DEFAULT 'abierta',
    estado_oc_anterior        VARCHAR(30)   NULL,
    fecha_observacion         DATETIME      NOT NULL,
    fecha_levantamiento       DATETIME      NULL,
    levantada_por             BIGINT        NULL,
    -- AUDITORÍA
    creado_en                 DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por                BIGINT        NULL,
    modificado_en             DATETIME      NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por            BIGINT        NULL,
    eliminado_en              DATETIME      NULL,
    eliminado_por             BIGINT        NULL,
    PRIMARY KEY (id_observacion)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- 3. Motivos de cada observación
CREATE TABLE IF NOT EXISTS orden_compra_observacion_motivo (
    id                  BIGINT   NOT NULL AUTO_INCREMENT,
    id_observacion      BIGINT   NOT NULL,
    id_motivo           INT      NOT NULL,
    -- AUDITORÍA
    creado_en           DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por          BIGINT   NULL,
    modificado_en       DATETIME NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por      BIGINT   NULL,
    eliminado_en        DATETIME NULL,
    eliminado_por       BIGINT   NULL,
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
