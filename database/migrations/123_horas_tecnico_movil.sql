-- ============================================================
-- Migración 123 — Horas contabilizadas del técnico (HU-36 «Mi equipo», botón «Ver las horas contabilizadas», Jefe de Área, app móvil)
--   Las horas laboradas se cuentan «desde que inicia el servicio hasta que finaliza el servicio» (evento de campo INICIO_TRABAJO → primer CIERRE de cada OS/OM, ver SP_ConsolidarHorasTecnicoMovil)
--   y se GUARDAN como historial: lo que hizo cada técnico por día y por mes queda fijo aunque la fuente cambie después.
--     tecnico_horas_dia ........ una fila por técnico y día con actividad: minutos trabajados (unión de los servicios, sin doble conteo si se solapan), servicios, primera hora de inicio y última de
--                                fin (en minutos desde las 00:00, hora de Lima) y sin_cierre (hubo un servicio iniciado que nunca se cerró: no se inventa su duración, cuenta 0).
--     tecnico_horas_servicio ... el detalle de cada día: cada OS/OM con su inicio, fin y minutos (recortados a ese día si el servicio cruzó la medianoche).
--     tecnico_horas_mes ........ el resumen de cada mes (minutos, días trabajados, servicios). cerrado = 1 cuando el mes ya pasó: queda como FOTO y no se vuelve a recalcular.
--   Soft delete + auditoría. Sin FK. UNIQUE por (técnico, día), (técnico, día, OS) y (técnico, mes): así la consolidación es un UPSERT idempotente (como jornada_marcacion, migración 109).
--   No borra ni cambia datos existentes. IDEMPOTENTE.
-- ============================================================
CREATE TABLE IF NOT EXISTS tecnico_horas_dia (
    id_hora_dia    BIGINT      NOT NULL AUTO_INCREMENT,
    id_usuario     BIGINT      NOT NULL,
    fecha          DATE        NOT NULL,
    minutos        INT         NOT NULL DEFAULT 0,
    n_servicios    INT         NOT NULL DEFAULT 0,
    inicio_min     INT         NULL,
    fin_min        INT         NULL,
    sin_cierre     TINYINT     NOT NULL DEFAULT 0,
    calculado_en   DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    -- AUDITORÍA
    creado_en      DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por     BIGINT      NULL,
    modificado_en  DATETIME    NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por BIGINT      NULL,
    eliminado_en   DATETIME    NULL,
    eliminado_por  BIGINT      NULL,
    PRIMARY KEY (id_hora_dia),
    UNIQUE KEY ux_horas_dia_usuario_fecha (id_usuario, fecha)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS tecnico_horas_servicio (
    id_hora_servicio BIGINT      NOT NULL AUTO_INCREMENT,
    id_usuario       BIGINT      NOT NULL,
    fecha            DATE        NOT NULL,
    id_os            BIGINT      NOT NULL,
    numero           VARCHAR(20) NULL,
    inicio_dt        DATETIME    NOT NULL,
    fin_dt           DATETIME    NULL,
    minutos          INT         NOT NULL DEFAULT 0,
    sin_cierre       TINYINT     NOT NULL DEFAULT 0,
    -- AUDITORÍA
    creado_en        DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por       BIGINT      NULL,
    modificado_en    DATETIME    NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por   BIGINT      NULL,
    eliminado_en     DATETIME    NULL,
    eliminado_por    BIGINT      NULL,
    PRIMARY KEY (id_hora_servicio),
    UNIQUE KEY ux_horas_servicio_usuario_fecha_os (id_usuario, fecha, id_os)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS tecnico_horas_mes (
    id_hora_mes     BIGINT      NOT NULL AUTO_INCREMENT,
    id_usuario      BIGINT      NOT NULL,
    mes             DATE        NOT NULL,   -- primer día del mes
    minutos         INT         NOT NULL DEFAULT 0,
    dias_trabajados INT         NOT NULL DEFAULT 0,
    n_servicios     INT         NOT NULL DEFAULT 0,
    cerrado         TINYINT     NOT NULL DEFAULT 0,
    calculado_en    DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    -- AUDITORÍA
    creado_en       DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por      BIGINT      NULL,
    modificado_en   DATETIME    NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por  BIGINT      NULL,
    eliminado_en    DATETIME    NULL,
    eliminado_por   BIGINT      NULL,
    PRIMARY KEY (id_hora_mes),
    UNIQUE KEY ux_horas_mes_usuario_mes (id_usuario, mes)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

SELECT 'Migración 123 (debe ser 3)' AS verificacion,
       (SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE()
           AND TABLE_NAME IN ('tecnico_horas_dia', 'tecnico_horas_servicio', 'tecnico_horas_mes')) AS valor;
