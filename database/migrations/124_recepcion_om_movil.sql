-- ============================================================
-- Migración 124 — Recepción de instrumentos de la OM en el taller desde la app móvil (App Mobile HU-23)
--   1. om_recepcion: una recepción registrada por el técnico de Metrología (guía, medio de entrega, quién entrega, quién recibe, firma de quien entrega como
--      TRAZOS normalizados —igual que HU-17—, estado conforme / observado / parcial, motivo si es parcial, PDF de la constancia y si se envió por correo).
--      Una OM puede tener varias recepciones (la parcial se completa después).
--   2. om_recepcion_equipo: cada instrumento recibido en esa recepción (estado físico, observaciones y accesorios). Un instrumento se recibe UNA sola vez en la
--      misma OM (lo controla SP_RegistrarRecepcionOmMovil).
--   3. om_recepcion_foto: fotos de recepción (solo cámara). Nacen sin recepción (id_recepcion_equipo NULL: «pendientes» del técnico) y quedan ligadas al registrar.
--   No cambia datos existentes. IDEMPOTENTE.
-- ============================================================

CREATE TABLE IF NOT EXISTS om_recepcion (
    id_recepcion        BIGINT        NOT NULL AUTO_INCREMENT,
    id_os               BIGINT        NOT NULL,
    numero_guia         VARCHAR(40)   NOT NULL,
    medio_entrega       ENUM('cliente_taller','courier','traslado_tw') NOT NULL,
    entrego_nombre      VARCHAR(120)  NOT NULL,
    entrego_cargo       VARCHAR(120)  NULL,
    id_usuario_recibio  BIGINT        NOT NULL,
    recibido_utc        DATETIME      NOT NULL,
    estado              ENUM('conforme','observado','parcial') NOT NULL,
    motivo_parcial      VARCHAR(300)  NULL,
    firma_trazos        JSON          NULL,
    ruta_constancia     VARCHAR(500)  NULL,
    correo_enviado      TINYINT(1)    NOT NULL DEFAULT 0,
    creado_en           DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por          BIGINT        NULL,
    modificado_en       DATETIME      NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por      BIGINT        NULL,
    eliminado_en        DATETIME      NULL,
    eliminado_por       BIGINT        NULL,
    PRIMARY KEY (id_recepcion),
    KEY ix_om_recepcion_os (id_os)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS om_recepcion_equipo (
    id_recepcion_equipo BIGINT        NOT NULL AUTO_INCREMENT,
    id_recepcion        BIGINT        NOT NULL,
    id_os_equipo        BIGINT        NOT NULL,
    estado_fisico       ENUM('conforme','observado') NOT NULL,
    observaciones       VARCHAR(500)  NOT NULL,
    accesorios          JSON          NULL,
    creado_en           DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    eliminado_en        DATETIME      NULL,
    PRIMARY KEY (id_recepcion_equipo),
    KEY ix_om_recepcion_equipo_rec (id_recepcion),
    KEY ix_om_recepcion_equipo_oe (id_os_equipo)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS om_recepcion_foto (
    id_foto             BIGINT        NOT NULL AUTO_INCREMENT,
    id_os_equipo        BIGINT        NOT NULL,
    id_usuario          BIGINT        NOT NULL,
    id_recepcion_equipo BIGINT        NULL,
    orden               INT           NOT NULL,
    ruta                VARCHAR(500)  NOT NULL,
    creado_en           DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    eliminado_en        DATETIME      NULL,
    PRIMARY KEY (id_foto),
    KEY ix_om_recepcion_foto_oe (id_os_equipo),
    KEY ix_om_recepcion_foto_re (id_recepcion_equipo)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
