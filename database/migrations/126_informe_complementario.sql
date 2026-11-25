-- ============================================================
-- Migración 126 — Informe Complementario (Mód. 12 Revisión Técnica, HU-56 a HU-60, cambio del 23/11/2026)
--   El Supervisor Técnico ya NO edita el informe que genera el técnico desde la app (queda inmutable). Si hace falta, genera un
--   INFORME COMPLEMENTARIO: una fila nueva de informe_tecnico con id_informe_padre = informe original, que trae precargados las
--   observaciones, recomendaciones y fotos del original y donde el supervisor agrega/edita fotos, videos, observaciones,
--   recomendaciones y registra la precotización (precotizacion.id_informe = id del complementario).
--   · El complementario va SIN id_os ni id_equipo (se enlaza solo por id_informe_padre): así ningún SP de la app móvil que busca
--     "el último informe de la OS y el equipo" lo toma como el informe del técnico. Sus fotos tampoco llevan id_os ni id_equipo.
--   · estado del complementario: 'borrador' (generado, sin guardar) → 'complementario' (guardado). El original sigue con sus estados
--     de siempre ('revisado' al cerrar la revisión); "revisado con complementario" se calcula por la existencia del complementario.
--   1. informe_tecnico.estado: agrega 'complementario' (al final del ENUM: cambio instantáneo, no reescribe la tabla).
--   2. informe_tecnico: índice por id_informe_padre.
--   3. evidencia_fotografica.id_evidencia_origen: foto del original de la que se copió (NULL = subida por el supervisor).
--   4. informe_observacion.id_observacion_origen: observación del original de la que se copió (para enlazar las recomendaciones).
--   No cambia datos existentes. IDEMPOTENTE.
-- ============================================================

SET @sql := IF((SELECT COLUMN_TYPE FROM information_schema.COLUMNS
                WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'informe_tecnico' AND COLUMN_NAME = 'estado') LIKE '%''complementario''%',
    'SELECT 1',
    'ALTER TABLE informe_tecnico MODIFY COLUMN estado ENUM(''borrador'',''pendiente_revision'',''en_revision'',''observado'',''aprobado'',''revisado'',''complementario'') NOT NULL');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.STATISTICS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'informe_tecnico' AND INDEX_NAME = 'ix_informe_padre'),
    'ALTER TABLE informe_tecnico ADD KEY ix_informe_padre (id_informe_padre)', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'evidencia_fotografica' AND COLUMN_NAME = 'id_evidencia_origen'),
    'ALTER TABLE evidencia_fotografica ADD COLUMN id_evidencia_origen BIGINT NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'informe_observacion' AND COLUMN_NAME = 'id_observacion_origen'),
    'ALTER TABLE informe_observacion ADD COLUMN id_observacion_origen BIGINT NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;
