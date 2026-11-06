-- ============================================================
-- Migración 93 — Revisión Técnica (Sprint 5, HU-56 a HU-60)
--   El técnico genera el informe de servicio técnico desde la app móvil (informe_tecnico: uno por OS + equipo). El
--   Supervisor / Jefe de Servicio Técnico lo revisa en la intranet, puede editarlo, registra la precotización cuando hay
--   observaciones y lo marca como REVISADO (inmutable). Comercial convierte la precotización en propuesta.
--
--   1. informe_tecnico: + estado 'revisado', datos del resultado global de los ensayos, descripción complementaria y
--      datos de la revisión (inicio, revisor, fecha, nota).
--   2. informe_procedimiento : pasos del procedimiento ejecutado (realizado / no realizado).
--   3. informe_ensayo        : lecturas de los ensayos (pesaje y excentricidad).
--   4. informe_observacion   : observaciones técnicas (OBS-01…) con ubicación, nivel de afectación y foto.
--   5. informe_recomendacion : recomendaciones (REC-01…) con prioridad, plazo y observación vinculada.
--   6. precotizacion         : + informe / OS / equipo de origen, nota del supervisor y datos de la conversión.
--      precotizacion_item    : conceptos sugeridos (concepto, código, descripción técnica, cantidad, prioridad, OBS).
--   7. evidencia_fotografica.id_observacion: foto vinculada a una observación.
--   8. Acciones (88): rt_bandeja, rt_editar, rt_revisar (servicio_tecnico, supervisar) y precot_ver / precot_convertir (propuestas).
--   9. Parámetro RT_SLA_REVISION_HORAS (48 h) para el control de tiempos de la bandeja.
--
--   Las tablas hijas las llena la app móvil al generar el informe (origen = 'tecnico'); lo que agrega el supervisor
--   queda con origen = 'supervisor'. Todo cambio queda en auditoria_evento (entidad 'informe_tecnico').
--   No borra ni cambia datos existentes. IDEMPOTENTE.
-- ============================================================

-- ── 1. informe_tecnico ─────────────────────────────────────────────────────────────────────
ALTER TABLE informe_tecnico
    MODIFY COLUMN estado ENUM('borrador','pendiente_revision','en_revision','observado','aprobado','revisado') NOT NULL;

DROP PROCEDURE IF EXISTS tmp_m93_columna;
DELIMITER $$
CREATE PROCEDURE tmp_m93_columna(IN p_tabla VARCHAR(64), IN p_columna VARCHAR(64), IN p_definicion VARCHAR(500))
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                   WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = p_tabla AND COLUMN_NAME = p_columna) THEN
        SET @sql := CONCAT('ALTER TABLE ', p_tabla, ' ADD COLUMN ', p_columna, ' ', p_definicion);
        PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;
    END IF;
END$$
DELIMITER ;

CALL tmp_m93_columna('informe_tecnico', 'normativa',                 'VARCHAR(120) NULL AFTER hallazgos');
CALL tmp_m93_columna('informe_tecnico', 'patron_ensayo',             'VARCHAR(200) NULL AFTER normativa');
CALL tmp_m93_columna('informe_tecnico', 'tolerancia_excentricidad',  'DECIMAL(14,4) NULL AFTER patron_ensayo');
CALL tmp_m93_columna('informe_tecnico', 'resultado_global',          "ENUM('dentro','fuera') NULL AFTER tolerancia_excentricidad");
CALL tmp_m93_columna('informe_tecnico', 'error_maximo',              'DECIMAL(10,4) NULL AFTER resultado_global');
CALL tmp_m93_columna('informe_tecnico', 'error_maximo_detalle',      'VARCHAR(150) NULL AFTER error_maximo');
CALL tmp_m93_columna('informe_tecnico', 'incertidumbre',             'DECIMAL(10,4) NULL AFTER error_maximo_detalle');
CALL tmp_m93_columna('informe_tecnico', 'factor_k',                  'DECIMAL(4,2) NULL AFTER incertidumbre');
CALL tmp_m93_columna('informe_tecnico', 'decision_tecnica',          'VARCHAR(300) NULL AFTER factor_k');
CALL tmp_m93_columna('informe_tecnico', 'descripcion_complementaria','TEXT NULL AFTER decision_tecnica');
CALL tmp_m93_columna('informe_tecnico', 'fecha_envio_revision',      'DATETIME NULL AFTER descripcion_complementaria');
CALL tmp_m93_columna('informe_tecnico', 'fecha_inicio_revision',     'DATETIME NULL AFTER fecha_envio_revision');
CALL tmp_m93_columna('informe_tecnico', 'fecha_revision',            'DATETIME NULL AFTER fecha_inicio_revision');
CALL tmp_m93_columna('informe_tecnico', 'nota_revision',             'VARCHAR(500) NULL AFTER fecha_revision');

-- ── 2. Procedimiento ejecutado ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS informe_procedimiento (
    id_paso        BIGINT       NOT NULL AUTO_INCREMENT,
    id_informe     BIGINT       NOT NULL,
    orden          INT          NOT NULL DEFAULT 0,
    titulo         VARCHAR(200) NOT NULL,
    detalle        VARCHAR(500) NULL,
    realizado      TINYINT(1)   NOT NULL DEFAULT 1,
    nota           VARCHAR(300) NULL,
    origen         ENUM('tecnico','supervisor') NOT NULL DEFAULT 'tecnico',
    creado_en      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por     BIGINT       NULL,
    modificado_en  DATETIME     NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por BIGINT       NULL,
    eliminado_en   DATETIME     NULL,
    eliminado_por  BIGINT       NULL,
    PRIMARY KEY (id_paso),
    KEY ix_informe_procedimiento (id_informe)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ── 3. Ensayos ─────────────────────────────────────────────────────────────────────────────
--   pesaje       : punto = carga aplicada (kg), lectura, error en %, tolerancia en ± %
--   excentricidad: punto = posición en la plataforma, lectura (kg), error = desviación en kg, tolerancia en ± kg
CREATE TABLE IF NOT EXISTS informe_ensayo (
    id_ensayo      BIGINT        NOT NULL AUTO_INCREMENT,
    id_informe     BIGINT        NOT NULL,
    tipo           ENUM('pesaje','excentricidad') NOT NULL,
    orden          INT           NOT NULL DEFAULT 0,
    punto          VARCHAR(100)  NOT NULL,
    nota_punto     VARCHAR(60)   NULL,
    carga          DECIMAL(14,4) NULL,
    lectura        DECIMAL(14,4) NULL,
    error          DECIMAL(14,4) NULL,
    tolerancia     DECIMAL(14,4) NULL,
    resultado      ENUM('conforme','no_conforme') NULL,
    origen         ENUM('tecnico','supervisor') NOT NULL DEFAULT 'tecnico',
    creado_en      DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por     BIGINT        NULL,
    modificado_en  DATETIME      NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por BIGINT        NULL,
    eliminado_en   DATETIME      NULL,
    eliminado_por  BIGINT        NULL,
    PRIMARY KEY (id_ensayo),
    KEY ix_informe_ensayo (id_informe, tipo)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ── 4. Observaciones técnicas ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS informe_observacion (
    id_observacion   BIGINT        NOT NULL AUTO_INCREMENT,
    id_informe       BIGINT        NOT NULL,
    codigo           VARCHAR(10)   NOT NULL,
    orden            INT           NOT NULL DEFAULT 0,
    titulo           VARCHAR(200)  NOT NULL,
    descripcion      VARCHAR(1000) NULL,
    ubicacion        VARCHAR(200)  NULL,
    detalle_extra    VARCHAR(200)  NULL,
    nivel_afectacion ENUM('critico','alto','medio','bajo') NULL,
    id_evidencia     BIGINT        NULL,
    origen           ENUM('tecnico','supervisor') NOT NULL DEFAULT 'tecnico',
    creado_en        DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por       BIGINT        NULL,
    modificado_en    DATETIME      NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por   BIGINT        NULL,
    eliminado_en     DATETIME      NULL,
    eliminado_por    BIGINT        NULL,
    PRIMARY KEY (id_observacion),
    KEY ix_informe_observacion (id_informe)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ── 5. Recomendaciones ─────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS informe_recomendacion (
    id_recomendacion BIGINT        NOT NULL AUTO_INCREMENT,
    id_informe       BIGINT        NOT NULL,
    codigo           VARCHAR(10)   NOT NULL,
    orden            INT           NOT NULL DEFAULT 0,
    titulo           VARCHAR(200)  NOT NULL,
    descripcion      VARCHAR(1000) NULL,
    prioridad        ENUM('alta','media','baja') NOT NULL DEFAULT 'media',
    plazo            VARCHAR(100)  NULL,
    id_observacion   BIGINT        NULL,
    origen           ENUM('tecnico','supervisor') NOT NULL DEFAULT 'tecnico',
    creado_en        DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por       BIGINT        NULL,
    modificado_en    DATETIME      NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por   BIGINT        NULL,
    eliminado_en     DATETIME      NULL,
    eliminado_por    BIGINT        NULL,
    PRIMARY KEY (id_recomendacion),
    KEY ix_informe_recomendacion (id_informe)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ── 6. Precotización técnica ───────────────────────────────────────────────────────────────
ALTER TABLE precotizacion
    MODIFY COLUMN id_tipo_servicio     INT  NULL,
    MODIFY COLUMN descripcion_servicio TEXT NULL,
    MODIFY COLUMN id_moneda            INT  NULL;

CALL tmp_m93_columna('precotizacion', 'id_informe',         'BIGINT NULL AFTER id_requerimiento');
CALL tmp_m93_columna('precotizacion', 'id_os',              'BIGINT NULL AFTER id_informe');
CALL tmp_m93_columna('precotizacion', 'id_equipo',          'BIGINT NULL AFTER id_os');
CALL tmp_m93_columna('precotizacion', 'nota_supervisor',    'VARCHAR(1000) NULL AFTER descripcion_servicio');
CALL tmp_m93_columna('precotizacion', 'fecha_envio',        'DATETIME NULL AFTER fecha_creacion');
CALL tmp_m93_columna('precotizacion', 'fecha_conversion',   'DATETIME NULL AFTER fecha_envio');
CALL tmp_m93_columna('precotizacion', 'id_convertido_por',  'BIGINT NULL AFTER fecha_conversion');

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE()
                             AND TABLE_NAME = 'precotizacion' AND INDEX_NAME = 'ix_precotizacion_informe'),
    'ALTER TABLE precotizacion ADD KEY ix_precotizacion_informe (id_informe)', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

CREATE TABLE IF NOT EXISTS precotizacion_item (
    id_item             BIGINT        NOT NULL AUTO_INCREMENT,
    id_precotizacion    BIGINT        NOT NULL,
    orden               INT           NOT NULL DEFAULT 0,
    concepto            VARCHAR(200)  NOT NULL,
    codigo              VARCHAR(60)   NULL,
    id_suministro       BIGINT        NULL,
    descripcion_tecnica VARCHAR(500)  NULL,
    cantidad            DECIMAL(10,2) NOT NULL DEFAULT 1,
    unidad              VARCHAR(20)   NOT NULL DEFAULT 'un',
    prioridad           ENUM('alta','media','opcional') NOT NULL DEFAULT 'media',
    id_observacion      BIGINT        NULL,
    creado_en           DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por          BIGINT        NULL,
    modificado_en       DATETIME      NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por      BIGINT        NULL,
    eliminado_en        DATETIME      NULL,
    eliminado_por       BIGINT        NULL,
    PRIMARY KEY (id_item),
    KEY ix_precotizacion_item (id_precotizacion)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ── 7. Foto vinculada a una observación ────────────────────────────────────────────────────
CALL tmp_m93_columna('evidencia_fotografica', 'id_observacion', 'BIGINT NULL AFTER id_informe');
CALL tmp_m93_columna('evidencia_fotografica', 'descripcion',    'VARCHAR(200) NULL AFTER url_archivo');

DROP PROCEDURE IF EXISTS tmp_m93_columna;

-- ── 8. Acciones (88 ACCION_SISTEMA: Num1 = nivel, String3 = módulo) ────────────────────────
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2, String3)
SELECT 1, 88, 'ACCION_SISTEMA', x.nivel, x.nombre, x.codigo, x.modulo
FROM (SELECT 3 AS nivel, 'Ver la bandeja y el detalle de los informes de servicio técnico' AS nombre, 'rt_bandeja' AS codigo, 'servicio_tecnico' AS modulo UNION ALL
      SELECT 3, 'Editar el informe de servicio técnico y registrar la precotización',            'rt_editar',        'servicio_tecnico' UNION ALL
      SELECT 3, 'Marcar el informe de servicio técnico como revisado',                            'rt_revisar',       'servicio_tecnico' UNION ALL
      SELECT 1, 'Ver las precotizaciones técnicas',                                               'precot_ver',       'propuestas'       UNION ALL
      SELECT 2, 'Convertir una precotización técnica en propuesta',                               'precot_convertir', 'propuestas') x
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra t WHERE t.IdMaestro = 88 AND t.IdEmpresa = 1 AND t.String2 = x.codigo);

-- ── 9. Parámetro de SLA de la revisión ─────────────────────────────────────────────────────
SET @id_param := (SELECT MAX(IdMaestro) FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROGRAMACION');
SET @num_param := (SELECT IFNULL(MAX(Num1), 0) + 1 FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROGRAMACION');
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, Num2, String1, String2)
SELECT 1, @id_param, 'PARAMETRO_PROGRAMACION', @num_param, 48,
       'Horas para revisar un informe de servicio técnico desde que llega a la bandeja', 'RT_SLA_REVISION_HORAS'
WHERE @id_param IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM tabla_maestra t WHERE t.Descripcion = 'PARAMETRO_PROGRAMACION' AND t.String2 = 'RT_SLA_REVISION_HORAS');

-- Informes ya enviados por la app sin fecha de envío: se toma la de creación
UPDATE informe_tecnico SET fecha_envio_revision = COALESCE(fecha_creacion, creado_en)
WHERE fecha_envio_revision IS NULL AND estado <> 'borrador';

-- ── Verificación ───────────────────────────────────────────────────────────────────────────
SELECT 'Migración 93 (debe ser 26)' AS verificacion,
       (SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME IN ('informe_procedimiento', 'informe_ensayo', 'informe_observacion', 'informe_recomendacion', 'precotizacion_item'))
     + (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'informe_tecnico'
          AND COLUMN_NAME IN ('normativa', 'patron_ensayo', 'tolerancia_excentricidad', 'resultado_global', 'error_maximo', 'error_maximo_detalle',
                              'incertidumbre', 'factor_k', 'decision_tecnica', 'descripcion_complementaria', 'fecha_envio_revision',
                              'fecha_inicio_revision', 'fecha_revision', 'nota_revision'))
     + (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'precotizacion'
          AND COLUMN_NAME IN ('id_informe', 'id_os', 'id_equipo', 'nota_supervisor', 'fecha_envio', 'fecha_conversion', 'id_convertido_por'))
     - 0 AS valor
UNION ALL
SELECT 'Acciones rt_* / precot_* (debe ser 5)',
       (SELECT COUNT(*) FROM tabla_maestra WHERE IdMaestro = 88 AND IdEmpresa = 1
          AND String2 IN ('rt_bandeja', 'rt_editar', 'rt_revisar', 'precot_ver', 'precot_convertir'))
UNION ALL
SELECT 'Estado revisado en informe_tecnico (debe ser 1)',
       (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'informe_tecnico'
          AND COLUMN_NAME = 'estado' AND COLUMN_TYPE LIKE '%revisado%')
UNION ALL
SELECT 'Parámetro RT_SLA_REVISION_HORAS (debe ser 1)',
       (SELECT COUNT(*) FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROGRAMACION' AND String2 = 'RT_SLA_REVISION_HORAS');
