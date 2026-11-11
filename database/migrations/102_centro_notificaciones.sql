-- ============================================================
-- Migración 102 — Centro de Notificaciones del Usuario (HU-90, Sprint 5, Módulo 16)
--   El módulo es transversal: NO genera notificaciones (salvo las alertas operativas del Módulo 11, que hasta hoy solo se
--   calculaban al consultar la bandeja de seguimiento). Las insertan los SPs de cada módulo en `notificacion` (migración 01).
--   1. Estados: archivado + fecha_lectura + fecha_archivado (no leída → leída al abrirla → archivada a mano, solo si está leída).
--   2. Clasificación SIN tocar los ~40 SPs que ya insertan:
--        modulo_origen / tipo_origen / prioridad_origen ... los llena quien quiera decirlo explícito (p. ej. SP_GenerarAlertasOperativas).
--        modulo / tipo_notificacion / prioridad ......... columnas GENERADAS (STORED): usan el valor *_origen si viene; si no, lo deducen
--                                                         de entidad_tipo y del título que deja cada SP. Las filas antiguas quedan
--                                                         clasificadas solas. Nadie las escribe (un INSERT no puede escribirlas).
--        clave_alerta .................................... evita repetir la misma alerta operativa del día al mismo usuario.
--      Módulos: propuestas · visto_bueno · seguimiento · ordenes_compra · ordenes_servicio · expedientes · programacion · control_campo
--               · ssoma · revision_tecnica · maestros · sistema
--      Tipos:   alerta_operativa · aprobacion_pendiente · recordatorio · asignacion · cambio_estado · ssoma · informativo
--      Prioridad: critica · alta · normal
--      Alerta operativa (chip rojo): "Demora en ruta", "Ensayo con error crítico", "Servicio detenido" y las del Módulo 11.
--      "Evidencia forzada": prioridad alta, SIN chip de alerta operativa.
--   3. Índices para la bandeja / contador y para la deduplicación de alertas.
--   4. Las ya leídas toman fecha_lectura = última modificación (o creación).
--   No borra ni cambia datos existentes. IDEMPOTENTE. Los patrones de texto van sin tildes: la intercalación _ai_ci las ignora.
-- ============================================================

-- 1. Estados
SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'notificacion' AND COLUMN_NAME = 'archivado'),
    'ALTER TABLE notificacion ADD COLUMN archivado TINYINT(1) NOT NULL DEFAULT 0', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'notificacion' AND COLUMN_NAME = 'fecha_lectura'),
    'ALTER TABLE notificacion ADD COLUMN fecha_lectura DATETIME NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'notificacion' AND COLUMN_NAME = 'fecha_archivado'),
    'ALTER TABLE notificacion ADD COLUMN fecha_archivado DATETIME NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- 2. Clasificación explícita (opcional) y clave de alerta
SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'notificacion' AND COLUMN_NAME = 'modulo_origen'),
    'ALTER TABLE notificacion ADD COLUMN modulo_origen VARCHAR(30) NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'notificacion' AND COLUMN_NAME = 'tipo_origen'),
    'ALTER TABLE notificacion ADD COLUMN tipo_origen VARCHAR(30) NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'notificacion' AND COLUMN_NAME = 'prioridad_origen'),
    'ALTER TABLE notificacion ADD COLUMN prioridad_origen VARCHAR(10) NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'notificacion' AND COLUMN_NAME = 'clave_alerta'),
    'ALTER TABLE notificacion ADD COLUMN clave_alerta VARCHAR(120) NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- 2b. modulo (generada)
SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'notificacion' AND COLUMN_NAME = 'modulo'),
    'ALTER TABLE notificacion ADD COLUMN modulo VARCHAR(30) GENERATED ALWAYS AS (COALESCE(modulo_origen, CASE
        WHEN titulo LIKE ''Demora en ruta%'' OR titulo LIKE ''Ensayo con error cr%'' OR titulo LIKE ''Evidencia forzada%''
          OR titulo LIKE ''Servicio detenido:%'' OR titulo LIKE ''Cambio manual de estado:%''
          OR titulo LIKE ''Autorizacion de salida%'' OR titulo LIKE ''Solicitud de autorizacion enviada%''
          OR titulo LIKE ''Visto bueno de salida%'' OR titulo LIKE ''Salida no autorizada%''               THEN ''control_campo''
        WHEN titulo LIKE ''Revision SSOMA%''                                                                THEN ''ssoma''
        WHEN titulo LIKE ''Proxima accion asignada%'' OR titulo LIKE ''Accion reprogramada%''
          OR titulo LIKE ''Recordatorio:%'' OR titulo LIKE ''Accion pendiente:%'' OR titulo LIKE ''Propuesta aceptada:%''
          OR (titulo LIKE ''Propuesta rechazada:%'' AND cuerpo LIKE ''%Registrado por%'')                   THEN ''seguimiento''
        WHEN titulo LIKE ''Visto bueno%'' OR titulo LIKE ''Solicitud de revocacion%''
          OR titulo LIKE ''Propuesta aprobada:%'' OR titulo LIKE ''Propuesta devuelta para correccion:%''
          OR titulo LIKE ''Propuesta rechazada:%''                                                          THEN ''visto_bueno''
        WHEN titulo LIKE ''Nueva precotizacion tecnica%'' OR entidad_tipo = ''informe_tecnico''            THEN ''revision_tecnica''
        WHEN entidad_tipo IN (''propuesta'', ''precotizacion'')                                            THEN ''propuestas''
        WHEN entidad_tipo = ''orden_compra''                                                               THEN ''ordenes_compra''
        WHEN entidad_tipo = ''orden_servicio'' AND (titulo LIKE ''Nueva programacion%'' OR titulo LIKE ''Nuevo servicio%''
          OR titulo LIKE ''Programacion cancelada%'' OR titulo LIKE ''Servicio confirmado%''
          OR titulo LIKE ''Solicitud de reprogramacion%'' OR titulo LIKE ''Servicio reprogramado%''
          OR titulo LIKE ''Asignacion retirada%'' OR titulo LIKE ''Reprogramacion %'')                     THEN ''programacion''
        WHEN entidad_tipo = ''orden_servicio''                                                             THEN ''ordenes_servicio''
        WHEN entidad_tipo = ''programacion''                                                               THEN ''programacion''
        WHEN entidad_tipo = ''expediente''                                                                 THEN ''expedientes''
        WHEN entidad_tipo IN (''equipo_cliente'', ''cliente'')                                             THEN ''maestros''
        ELSE ''sistema'' END)) STORED',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- 2c. tipo_notificacion (generada)
SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'notificacion' AND COLUMN_NAME = 'tipo_notificacion'),
    'ALTER TABLE notificacion ADD COLUMN tipo_notificacion VARCHAR(30) GENERATED ALWAYS AS (COALESCE(tipo_origen, CASE
        WHEN clave_alerta IS NOT NULL OR titulo LIKE ''Demora en ruta%'' OR titulo LIKE ''Ensayo con error cr%''
          OR titulo LIKE ''Servicio detenido:%''                                                            THEN ''alerta_operativa''
        WHEN titulo LIKE ''Revision SSOMA%''                                                                THEN ''ssoma''
        WHEN titulo LIKE ''Recordatorio:%'' OR titulo LIKE ''Accion pendiente:%'' OR titulo LIKE ''Viaticos por depositar%'' THEN ''recordatorio''
        WHEN titulo LIKE ''Visto bueno pendiente%'' OR titulo LIKE ''Solicitud de edicion%''
          OR titulo LIKE ''Solicitud de reprogramacion%'' OR titulo LIKE ''Equipo nuevo por aprobar%''
          OR (titulo LIKE ''Autorizacion de salida%'' AND titulo NOT LIKE ''Autorizacion de salida aprobada%''
              AND titulo NOT LIKE ''Autorizacion de salida rechazada%'')                                    THEN ''aprobacion_pendiente''
        WHEN titulo LIKE ''Nueva programacion%'' OR titulo LIKE ''Nuevo servicio%'' OR titulo LIKE ''Proxima accion asignada%''
          OR titulo LIKE ''Te reasignaron%'' OR titulo LIKE ''Cambio de responsable%'' OR titulo LIKE ''Clientes asignados%''
          OR titulo LIKE ''Expediente listo%'' OR titulo LIKE ''Nueva precotizacion%'' OR titulo LIKE ''Asignacion retirada%'' THEN ''asignacion''
        WHEN titulo LIKE ''Evidencia forzada%'' OR titulo LIKE ''Solicitud de autorizacion enviada%''      THEN ''informativo''
        WHEN entidad_tipo IS NOT NULL                                                                       THEN ''cambio_estado''
        ELSE ''informativo'' END)) STORED',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- 2d. prioridad (generada)
SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'notificacion' AND COLUMN_NAME = 'prioridad'),
    'ALTER TABLE notificacion ADD COLUMN prioridad VARCHAR(10) GENERATED ALWAYS AS (COALESCE(prioridad_origen, CASE
        WHEN titulo LIKE ''Ensayo con error cr%'' OR titulo LIKE ''Servicio detenido:%''                    THEN ''critica''
        WHEN titulo LIKE ''Demora en ruta%'' OR titulo LIKE ''Evidencia forzada%'' OR titulo LIKE ''%anulad%''
          OR titulo LIKE ''Cobertura perdida%'' OR titulo LIKE ''Programacion cancelada%''
          OR titulo LIKE ''Visto bueno pendiente%'' OR titulo LIKE ''Revision SSOMA%''                      THEN ''alta''
        ELSE ''normal'' END)) STORED',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- 3. Índices
SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'notificacion' AND INDEX_NAME = 'ix_notificacion_bandeja'),
    'ALTER TABLE notificacion ADD KEY ix_notificacion_bandeja (id_usuario_destino, archivado, leido, fecha_creacion)', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'notificacion' AND INDEX_NAME = 'ix_notificacion_clave_alerta'),
    'ALTER TABLE notificacion ADD KEY ix_notificacion_clave_alerta (clave_alerta, id_usuario_destino)', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- 4. Fecha de lectura de las que ya estaban leídas
UPDATE notificacion
SET    fecha_lectura = COALESCE(modificado_en, fecha_creacion)
WHERE  leido = 1 AND fecha_lectura IS NULL;

SELECT 'Migración 102 (debe ser 12)' AS verificacion,
       (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'notificacion'
           AND COLUMN_NAME IN ('archivado', 'fecha_lectura', 'fecha_archivado', 'modulo_origen', 'tipo_origen', 'prioridad_origen',
                               'clave_alerta', 'modulo', 'tipo_notificacion', 'prioridad'))
     + (SELECT COUNT(*) FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'notificacion'
           AND INDEX_NAME IN ('ix_notificacion_bandeja', 'ix_notificacion_clave_alerta') AND SEQ_IN_INDEX = 1) AS valor;
