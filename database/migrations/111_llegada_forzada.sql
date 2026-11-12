-- ============================================================
-- Migración 111 — Llegada forzada (HU-06): el técnico fuera del radio permitido pide a Jefatura que le autorice registrar su llegada
--   Tras 5 capturas de ubicación fuera del rango, la app ofrece «Confirmar llegada forzada»: crea una solicitud que le llega al encargado del área
--   (misma regla que la autorización de salida) y aparece en Aprobaciones. Solo cuando el encargado la aprueba el técnico puede registrar la llegada
--   (una sola vez: la aprobación se marca como usada al registrar). IDEMPOTENTE.
-- ============================================================
CREATE TABLE IF NOT EXISTS llegada_forzada_os (
    id_solicitud     BIGINT        NOT NULL AUTO_INCREMENT,
    id_os            BIGINT        NOT NULL,
    id_tecnico       BIGINT        NOT NULL,
    estado           ENUM('pendiente','aprobada','rechazada') NOT NULL DEFAULT 'pendiente',
    motivo           VARCHAR(500)  NULL,
    intentos         SMALLINT      NOT NULL DEFAULT 0,          -- capturas fuera de rango que hizo el técnico antes de pedirla
    latitud          DECIMAL(10,7) NULL,                        -- dónde estaba al pedirla
    longitud         DECIMAL(10,7) NULL,
    precision_metros DECIMAL(8,1)  NULL,
    distancia_metros INT           NULL,                        -- a cuántos metros de la planta
    area_destino     VARCHAR(30)   NULL,                        -- AREA_USUARIO del encargado al que se avisó (según la RQ)
    solicitado_en    DATETIME      NULL,
    id_jefe          BIGINT        NULL,
    resuelto_en      DATETIME      NULL,
    comentario       VARCHAR(500)  NULL,
    usada_en         DATETIME      NULL,                        -- cuando el técnico registró la llegada con esta aprobación
    -- AUDITORÍA
    creado_en        DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por       BIGINT        NULL,
    modificado_en    DATETIME      NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por   BIGINT        NULL,
    eliminado_en     DATETIME      NULL,
    eliminado_por    BIGINT        NULL,
    PRIMARY KEY (id_solicitud),
    KEY ix_llegada_forzada_os (id_os, estado),
    KEY ix_llegada_forzada_estado (estado, solicitado_en)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

SELECT 'Migración 111 (debe ser 1)' AS verificacion, COUNT(*) AS valor FROM information_schema.TABLES
WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'llegada_forzada_os';
