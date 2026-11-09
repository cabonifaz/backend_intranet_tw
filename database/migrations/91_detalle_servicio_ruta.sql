-- ============================================================
-- Migración 91 — Detalle del Servicio en Ruta (HU-52, Sprint 5)
--   Vista OBSERVACIONAL con 5 tabs para el Asistente de Seguimiento: el contenido lo registra la app móvil del técnico.
--   1. os_equipo_etapa: etapas por equipo (limpieza → desmontaje → pruebas → montaje → cierre) con hora de inicio y fin (UTC).
--      La escribe la app móvil; el detalle solo lee. Sin etapas, el avance del equipo se deduce de os_equipo.estado_ejecucion.
--   2. os_equipo_observacion: observaciones del técnico por equipo (pestaña "Observaciones" del drill-down).
--   3. evidencia_fotografica.id_equipo (opcional): asocia la foto al equipo (pestaña "Fotos" del drill-down).
--   4. ubicacion_tecnico: velocidad, altitud, satélites y latencia (opcionales, los envía la app) para el panel del Mapa GPS.
--   5. Parámetro SEG_DETALLE_REFRESCO_SEGUNDOS (15 s): auto-refresco del detalle.
--   No borra ni cambia datos existentes. IDEMPOTENTE. Requiere la migración 90 (HU-51).
-- ============================================================

-- ── 1. Etapas por equipo ───────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS os_equipo_etapa (
    id_etapa      BIGINT      NOT NULL AUTO_INCREMENT,
    id_os         BIGINT      NOT NULL,
    id_equipo     BIGINT      NOT NULL,
    etapa         ENUM('limpieza','desmontaje','pruebas','montaje','cierre') NOT NULL,
    inicio_utc    DATETIME    NULL,
    fin_utc       DATETIME    NULL,
    creado_en     DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por    BIGINT      NULL,
    modificado_en DATETIME    NULL,
    modificado_por BIGINT     NULL,
    eliminado_en  DATETIME    NULL,
    eliminado_por BIGINT      NULL,
    PRIMARY KEY (id_etapa),
    UNIQUE KEY ux_os_equipo_etapa (id_os, id_equipo, etapa),
    KEY ix_os_equipo_etapa_os (id_os)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ── 2. Observaciones por equipo ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS os_equipo_observacion (
    id_observacion BIGINT       NOT NULL AUTO_INCREMENT,
    id_os          BIGINT       NOT NULL,
    id_equipo      BIGINT       NOT NULL,
    id_usuario     BIGINT       NULL,
    texto          VARCHAR(1000) NOT NULL,
    fecha_utc      DATETIME     NOT NULL,
    creado_en      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    eliminado_en   DATETIME     NULL,
    PRIMARY KEY (id_observacion),
    KEY ix_os_equipo_obs (id_os, id_equipo)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ── 3. Foto asociada al equipo ─────────────────────────────────────────────────────────────
SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'evidencia_fotografica' AND COLUMN_NAME = 'id_equipo'),
    'ALTER TABLE evidencia_fotografica ADD COLUMN id_equipo BIGINT NULL AFTER id_os', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'evidencia_fotografica' AND INDEX_NAME = 'ix_evidencia_os_equipo'),
    'ALTER TABLE evidencia_fotografica ADD KEY ix_evidencia_os_equipo (id_os, id_equipo)', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- ── 4. Datos extra del GPS ─────────────────────────────────────────────────────────────────
SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'ubicacion_tecnico' AND COLUMN_NAME = 'velocidad_kmh'),
    'ALTER TABLE ubicacion_tecnico ADD COLUMN velocidad_kmh DECIMAL(6,1) NULL AFTER precision_m', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;
SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'ubicacion_tecnico' AND COLUMN_NAME = 'altitud_m'),
    'ALTER TABLE ubicacion_tecnico ADD COLUMN altitud_m DECIMAL(8,1) NULL AFTER velocidad_kmh', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;
SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'ubicacion_tecnico' AND COLUMN_NAME = 'satelites'),
    'ALTER TABLE ubicacion_tecnico ADD COLUMN satelites SMALLINT NULL AFTER altitud_m', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;
SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'ubicacion_tecnico' AND COLUMN_NAME = 'latencia_ms'),
    'ALTER TABLE ubicacion_tecnico ADD COLUMN latencia_ms INT NULL AFTER satelites', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- ── 5. Parámetro de refresco del detalle ───────────────────────────────────────────────────
SET @id_param := (SELECT MAX(IdMaestro) FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROGRAMACION');
SET @id_param := IFNULL(@id_param, (SELECT MAX(IdMaestro) + 1 FROM tabla_maestra));
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, Num2, String1, String2)
SELECT 1, @id_param, 'PARAMETRO_PROGRAMACION', 18, 15, 'Segundos entre actualizaciones automáticas del detalle del servicio en ruta', 'SEG_DETALLE_REFRESCO_SEGUNDOS'
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra t WHERE t.Descripcion = 'PARAMETRO_PROGRAMACION' AND t.IdEmpresa = 1 AND t.String2 = 'SEG_DETALLE_REFRESCO_SEGUNDOS');

-- ── Verificación ─────────────────────────────────────────────────────────────
SELECT 'Migración 91 (debe ser 9)' AS verificacion,
       (SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME IN ('os_equipo_etapa', 'os_equipo_observacion'))
     + (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'evidencia_fotografica' AND COLUMN_NAME = 'id_equipo')
     + (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'ubicacion_tecnico' AND COLUMN_NAME IN ('velocidad_kmh', 'altitud_m', 'satelites', 'latencia_ms'))
     + (SELECT COUNT(*) FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROGRAMACION' AND IdEmpresa = 1 AND String2 = 'SEG_DETALLE_REFRESCO_SEGUNDOS')
     + (SELECT COUNT(DISTINCT INDEX_NAME) FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'evidencia_fotografica' AND INDEX_NAME = 'ix_evidencia_os_equipo') AS valor;
