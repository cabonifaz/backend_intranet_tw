-- ============================================================
-- Migración 117 — Ingreso de equipos de la OS desde la app móvil (App Mobile HU-22)
--   1. os_equipo_ingreso: el ingreso formal de un equipo de la OS (estado de ingreso: operativo, operativo con observaciones o inoperativo;
--      observación obligatoria si no está operativo). Un equipo se ingresa UNA sola vez en la misma OS (lo controla SP_RegistrarIngresoEquipoMovil).
--   2. os_equipo_ingreso_foto: fotos de evidencia (solo cámara) del ingreso con observaciones o inoperativo.
--   No cambia datos existentes. IDEMPOTENTE.
-- ============================================================

CREATE TABLE IF NOT EXISTS os_equipo_ingreso (
    id              BIGINT       NOT NULL AUTO_INCREMENT,
    id_os           BIGINT       NOT NULL,
    id_os_equipo    BIGINT       NOT NULL,
    estado_ingreso  ENUM('operativo','con_observaciones','inoperativo') NOT NULL,
    observacion     VARCHAR(500) NULL,
    ingresado_utc   DATETIME     NOT NULL,
    id_usuario      BIGINT       NOT NULL,
    creado_en       DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    eliminado_en    DATETIME     NULL,
    PRIMARY KEY (id),
    KEY ix_ingreso_os (id_os),
    KEY ix_ingreso_os_equipo (id_os_equipo)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS os_equipo_ingreso_foto (
    id          BIGINT       NOT NULL AUTO_INCREMENT,
    id_ingreso  BIGINT       NOT NULL,
    orden       INT          NOT NULL,
    ruta        VARCHAR(500) NOT NULL,
    creado_en   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY ix_ingreso_foto (id_ingreso)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
