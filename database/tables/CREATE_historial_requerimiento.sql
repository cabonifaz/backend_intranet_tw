-- ============================================================
-- CREATE TABLE historial_requerimiento
-- Registra el historial de eventos de cada requerimiento:
-- creación, edición, cambios de estado y actividades manuales.
-- ============================================================
CREATE TABLE IF NOT EXISTS historial_requerimiento (
    id_historial      BIGINT        NOT NULL AUTO_INCREMENT,
    id_requerimiento  BIGINT        NOT NULL,
    tipo              VARCHAR(30)   NOT NULL,   -- creacion | edicion | cambio_estado | llamada | visita | correo | nota
    tipo_label        VARCHAR(50),
    icono             VARCHAR(50),
    descripcion       TEXT          CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL,
    usuario           VARCHAR(100),
    fecha             DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    SoftDelete        TINYINT       NOT NULL DEFAULT 0,
    creado_en         DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por        BIGINT,
    PRIMARY KEY (id_historial)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
