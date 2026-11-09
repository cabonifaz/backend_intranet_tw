-- ============================================================
-- Migración 90 — Bandeja de Seguimiento Operativo del día (HU-51, Sprint 5)
--   Rol observacional (Asistente de Seguimiento): ve el avance de los servicios del día, la ubicación GPS de los técnicos,
--   las alertas automáticas y las incidencias. La bandeja LEE lo que ya registra la app de campo (evento_campo, orden_servicio,
--   os_equipo, demora_registro, incidencia_operativa) y calcula el estado y las alertas al consultar (nada se duplica).
--   1. ubicacion_tecnico: última posición GPS de cada técnico (la escribe la app móvil; la bandeja solo lee). Solo agrega filas.
--   2. demora_registro e incidencia_operativa: impacto (retrasa | detiene) para la pestaña Incidencias del Día;
--      incidencia_operativa: duración estimada en minutos (opcional).
--   3. Acción seg_bandeja (nivel 1 = ver, módulo operaciones): quién puede ver la bandeja de seguimiento.
--   4. Parámetros de la bandeja (PARAMETRO_PROGRAMACION): refresco, umbrales de las alertas y de los hitos esperados.
--   No borra ni cambia datos existentes. IDEMPOTENTE. Ejecutar junto con los SPs de este mismo paquete.
-- ============================================================

-- ── 1. Ubicaciones GPS de los técnicos ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS ubicacion_tecnico (
    id_ubicacion  BIGINT        NOT NULL AUTO_INCREMENT,
    id_usuario    BIGINT        NOT NULL,
    id_os         BIGINT        NULL,
    latitud       DECIMAL(10,7) NOT NULL,
    longitud      DECIMAL(10,7) NOT NULL,
    precision_m   INT           NULL,
    direccion     VARCHAR(200)  NULL,
    timestamp_utc DATETIME      NOT NULL,
    creado_en     DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id_ubicacion),
    KEY ix_ubicacion_usuario_ts (id_usuario, timestamp_utc),
    KEY ix_ubicacion_os (id_os)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ── 2. Impacto de demoras e incidencias ────────────────────────────────────────────────────
SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'demora_registro' AND COLUMN_NAME = 'impacto'),
    'ALTER TABLE demora_registro ADD COLUMN impacto ENUM(''retrasa'',''detiene'') NOT NULL DEFAULT ''retrasa'' AFTER duracion_minutos', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'incidencia_operativa' AND COLUMN_NAME = 'impacto'),
    'ALTER TABLE incidencia_operativa ADD COLUMN impacto ENUM(''retrasa'',''detiene'') NOT NULL DEFAULT ''retrasa'' AFTER estado', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'incidencia_operativa' AND COLUMN_NAME = 'duracion_estimada_min'),
    'ALTER TABLE incidencia_operativa ADD COLUMN duracion_estimada_min INT NULL AFTER impacto', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'demora_registro' AND INDEX_NAME = 'ix_demora_fecha'),
    'ALTER TABLE demora_registro ADD KEY ix_demora_fecha (fecha_registro)', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'incidencia_operativa' AND INDEX_NAME = 'ix_incidencia_fecha'),
    'ALTER TABLE incidencia_operativa ADD KEY ix_incidencia_fecha (fecha_registro)', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'evento_campo' AND INDEX_NAME = 'ix_evento_campo_os_ts'),
    'ALTER TABLE evento_campo ADD KEY ix_evento_campo_os_ts (id_os, timestamp_utc)', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- ── 3. Acción (88 ACCION_SISTEMA: Num1 = nivel, String3 = módulo) ──────────────────────────
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2, String3)
SELECT 1, 88, 'ACCION_SISTEMA', 1, 'Ver la bandeja de seguimiento operativo del día', 'seg_bandeja', 'operaciones'
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra t WHERE t.IdMaestro = 88 AND t.IdEmpresa = 1 AND t.String2 = 'seg_bandeja');

-- ── 4. Parámetros de la bandeja ────────────────────────────────────────────────────────────
SET @id_param := (SELECT MAX(IdMaestro) FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROGRAMACION');
SET @id_param := IFNULL(@id_param, (SELECT MAX(IdMaestro) + 1 FROM tabla_maestra));

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, Num2, String1, String2)
SELECT 1, @id_param, 'PARAMETRO_PROGRAMACION', x.n, x.valor, x.nombre, x.codigo
FROM (SELECT 8 AS n, 30 AS valor, 'Segundos entre actualizaciones automáticas de la bandeja de seguimiento'                AS nombre, 'SEG_REFRESCO_SEGUNDOS'      AS codigo UNION ALL
      SELECT 9,      10,          'Minutos sin señal GPS para alertar "Pérdida de contacto"',                                           'SEG_PERDIDA_CONTACTO_MIN'            UNION ALL
      SELECT 10,     10,          'Minutos con el GPS en el mismo punto (en ruta) para alertar "GPS parado"',                           'SEG_GPS_PARADO_MIN'                  UNION ALL
      SELECT 11,     15,          'Minutos en planta sin iniciar el trabajo para alertar "Sin ingreso post-llegada"',                   'SEG_SIN_INGRESO_MIN'                 UNION ALL
      SELECT 12,     15,          'Minutos de tolerancia sobre la hora de salida programada para alertar "Sin iniciar servicio"',       'SEG_SIN_INICIAR_MIN'                 UNION ALL
      SELECT 13,     300,         'Metros al cliente para alertar "Proximidad"',                                                        'SEG_PROXIMIDAD_METROS'               UNION ALL
      SELECT 14,     60,          'Minutos de anticipación de la salida de base respecto a la hora de inicio del servicio',             'SEG_ANTICIPACION_SALIDA_MIN'         UNION ALL
      SELECT 15,     15,          'Minutos durante los que una alerta se cuenta como "nueva"',                                          'SEG_ALERTA_NUEVA_MIN'                UNION ALL
      SELECT 16,     60,          'Minutos hacia adelante que cubren los Próximos Hitos Esperados',                                     'SEG_HITOS_VENTANA_MIN'               UNION ALL
      SELECT 17,     30,          'Minutos después de finalizar el servicio en que se espera el inicio del retorno',                    'SEG_RETORNO_MIN') x
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra t WHERE t.Descripcion = 'PARAMETRO_PROGRAMACION' AND t.IdEmpresa = 1 AND t.String2 = x.codigo);

-- ── Verificación ─────────────────────────────────────────────────────────────
SELECT 'Migración 90 (debe ser 15)' AS verificacion,
       (SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'ubicacion_tecnico')
     + (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND COLUMN_NAME = 'impacto' AND TABLE_NAME IN ('demora_registro', 'incidencia_operativa'))
     + (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'incidencia_operativa' AND COLUMN_NAME = 'duracion_estimada_min')
     + (SELECT COUNT(*) FROM tabla_maestra WHERE IdMaestro = 88 AND IdEmpresa = 1 AND String2 = 'seg_bandeja')
     + (SELECT COUNT(DISTINCT String2) FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROGRAMACION' AND IdEmpresa = 1 AND String2 LIKE 'SEG\_%') AS valor;
