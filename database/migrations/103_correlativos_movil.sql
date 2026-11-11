-- ============================================================
-- Migración 103 — Correlativos de Metrología para la app móvil (App Mobile HU-14 técnico / HU-34 Jefe de Metrología)
--   El técnico pide un correlativo de certificación desde "Correlativo y certificado" (ticket TK-MET-#####), el Jefe de Metrología lo asigna
--   (CC-####-AAAA) y el técnico lo usa como N° de certificado del informe técnico. Cada técnico de Metrología tiene además una reserva diaria
--   de correlativos para trabajar sin conexión.
--   1. ticket_metrologia (ya existía, nada la llenaba): + id_equipo, id_tipo_certificado, id_correlativo, usado_en; numero único; índice del ticket abierto.
--   2. correlativo_metrologia: cada correlativo emitido (asignado a un ticket · reservado a un técnico · usado de la reserva). (anio, numero) y codigo únicos.
--   3. correlativo_secuencia: último número emitido por año (UNA sola secuencia para tickets y reservas). Arranca en el mayor CC-####-AAAA que ya
--      exista en certificados o tickets del año (orden_metrologia.numero_certificado / ticket_metrologia.correlativo_asignado); si no hay ninguno, en 0.
--   4. informe_tecnico.numero_certificado: el N° de certificado / constancia que forma parte del informe técnico.
--   5. Catálogo TIPO_CERTIFICADO_MET (tipos de certificado de la solicitud) y parámetro CORRELATIVO_RESERVA_DIARIA (2 por técnico).
--   No borra ni cambia datos existentes. IDEMPOTENTE.
-- ============================================================

-- ── 1. ticket_metrologia ───────────────────────────────────────────────────────────────────
SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'ticket_metrologia' AND COLUMN_NAME = 'id_equipo'),
    'ALTER TABLE ticket_metrologia ADD COLUMN id_equipo BIGINT NULL AFTER id_om', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'ticket_metrologia' AND COLUMN_NAME = 'id_tipo_certificado'),
    'ALTER TABLE ticket_metrologia ADD COLUMN id_tipo_certificado INT NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'ticket_metrologia' AND COLUMN_NAME = 'id_correlativo'),
    'ALTER TABLE ticket_metrologia ADD COLUMN id_correlativo BIGINT NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'ticket_metrologia' AND COLUMN_NAME = 'usado_en'),
    'ALTER TABLE ticket_metrologia ADD COLUMN usado_en DATETIME NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'ticket_metrologia' AND INDEX_NAME = 'ux_ticket_met_numero'),
    'ALTER TABLE ticket_metrologia ADD UNIQUE KEY ux_ticket_met_numero (numero)', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'ticket_metrologia' AND INDEX_NAME = 'ix_ticket_met_equipo'),
    'ALTER TABLE ticket_metrologia ADD KEY ix_ticket_met_equipo (id_os, id_equipo, estado)', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- ── 2. correlativo_metrologia ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS correlativo_metrologia (
    id_correlativo  BIGINT       NOT NULL AUTO_INCREMENT,
    anio            SMALLINT     NOT NULL,
    numero          INT          NOT NULL,
    codigo          VARCHAR(20)  NOT NULL,
    -- asignado = dado por Metrología a un ticket · reservado = reserva diaria libre de un técnico · usado = reservado que el técnico ya usó (por confirmar)
    estado          ENUM('asignado','reservado','usado') NOT NULL,
    id_ticket_met   BIGINT       NULL,
    id_tecnico      BIGINT       NULL,
    fecha_reserva   DATETIME     NULL,
    id_os           BIGINT       NULL,
    id_equipo       BIGINT       NULL,
    usado_en        DATETIME     NULL,
    -- AUDITORÍA
    creado_en       DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por      BIGINT       NULL,
    modificado_en   DATETIME     NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por  BIGINT       NULL,
    eliminado_en    DATETIME     NULL,
    eliminado_por   BIGINT       NULL,
    PRIMARY KEY (id_correlativo),
    UNIQUE KEY ux_correlativo_anio_numero (anio, numero),
    UNIQUE KEY ux_correlativo_codigo (codigo),
    KEY ix_correlativo_estado (estado, id_tecnico)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ── 3. correlativo_secuencia ───────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS correlativo_secuencia (
    anio            SMALLINT     NOT NULL,
    ultimo          INT          NOT NULL DEFAULT 0,
    modificado_en   DATETIME     NULL ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (anio)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

SET @anio := YEAR(UTC_TIMESTAMP() - INTERVAL 5 HOUR);
INSERT INTO correlativo_secuencia (anio, ultimo)
SELECT @anio, (SELECT IFNULL(MAX(CAST(SUBSTRING(x.cod, 4, 4) AS UNSIGNED)), 0)
               FROM (SELECT om.numero_certificado AS cod FROM orden_metrologia om
                     WHERE om.numero_certificado REGEXP '^CC-[0-9]{4}-[0-9]{4}$' AND RIGHT(om.numero_certificado, 4) = CAST(@anio AS CHAR)
                     UNION ALL
                     SELECT t.correlativo_asignado FROM ticket_metrologia t
                     WHERE t.correlativo_asignado REGEXP '^CC-[0-9]{4}-[0-9]{4}$' AND RIGHT(t.correlativo_asignado, 4) = CAST(@anio AS CHAR)) x)
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM correlativo_secuencia s WHERE s.anio = @anio);

-- ── 4. informe_tecnico.numero_certificado ──────────────────────────────────────────────────
SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'informe_tecnico' AND COLUMN_NAME = 'numero_certificado'),
    'ALTER TABLE informe_tecnico ADD COLUMN numero_certificado VARCHAR(50) NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- ── 5. Catálogo de tipos de certificado y parámetro de la reserva diaria ───────────────────
SET @id_cat := COALESCE((SELECT MAX(IdMaestro) FROM tabla_maestra WHERE Descripcion = 'TIPO_CERTIFICADO_MET'),
                        (SELECT MAX(IdMaestro) + 1 FROM tabla_maestra));
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2)
SELECT 1, @id_cat, 'TIPO_CERTIFICADO_MET', v.n, v.nombre, v.codigo
FROM (SELECT 1 AS n, 'Calibración con pesas' AS nombre, 'calibracion_pesas' AS codigo
      UNION ALL SELECT 2, 'Certificado de calibración', 'certificado_calibracion'
      UNION ALL SELECT 3, 'Constancia de verificación',  'constancia_verificacion') v
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra t WHERE t.Descripcion = 'TIPO_CERTIFICADO_MET' AND t.IdEmpresa = 1 AND t.Num1 = v.n);

SET @id_param  := (SELECT MAX(IdMaestro) FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROGRAMACION');
SET @num_param := (SELECT IFNULL(MAX(Num1), 0) + 1 FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROGRAMACION');
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, Num2, String1, String2)
SELECT 1, @id_param, 'PARAMETRO_PROGRAMACION', @num_param, 2,
       'Correlativos reservados por técnico de Metrología cada día (para trabajar sin conexión)', 'CORRELATIVO_RESERVA_DIARIA'
FROM DUAL
WHERE @id_param IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROGRAMACION' AND String2 = 'CORRELATIVO_RESERVA_DIARIA');
