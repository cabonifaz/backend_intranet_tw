-- 119: jornada_salida — cada «Salida de planta» del Reloj marcador (HU-20). Un técnico puede salir de varias plantas el mismo día (una por servicio concluido);
-- jornada_marcacion conserva solo la primera por su índice único (usuario, día, tipo). Idempotente.
CREATE TABLE IF NOT EXISTS jornada_salida (
    id_salida    BIGINT        NOT NULL AUTO_INCREMENT,
    id_usuario   BIGINT        NOT NULL,
    fecha        DATE          NOT NULL,
    id_os        BIGINT        NULL,
    marcado_utc  DATETIME      NOT NULL,
    latitud      DECIMAL(10,7) NULL,
    longitud     DECIMAL(10,7) NULL,
    precision_m  INT           NULL,
    lugar        VARCHAR(200)  NULL,
    sin_conexion TINYINT       NOT NULL DEFAULT 0,
    creado_en    DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id_salida),
    KEY ix_jornada_salida_dia (id_usuario, fecha),
    KEY ix_jornada_salida_os (id_os)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
