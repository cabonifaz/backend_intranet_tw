-- ============================================================
-- Migración 85 — Programación Operativa (HU-35, Sprint 5)
--   1. os_reprogramacion ...... solicitudes de reprogramación de un servicio programado. Las crea y resuelve la HU-38;
--                               la bandeja (HU-35) solo las lee para el sub-estado "Pendiente de reprogramación" y su alerta.
--   2. Índices para el calendario, la matriz de carga y la validación SSOMA de la bandeja:
--        orden_servicio (id_tecnico_principal, fecha_ejecucion) y (estado, fecha_ejecucion)
--        os_personal (id_usuario, id_os) ............ carga y cruces del personal de apoyo
--        ssoma_documento (id_os, id_usuario, id_requisito, version) ... última versión de cada documento
--   3. Acciones del módulo 'operaciones' (88 ACCION_SISTEMA: Num1 = nivel, String3 = módulo):
--        prog_bandeja (1) ver la bandeja · prog_gestionar (2) programar / solicitar reprogramación / cancelar
--        prog_aprobar_reprogramacion (3) jefe: reprogramar y resolver solicitudes.
--      El acceso lo da la matriz permiso_area_rol (módulo 'operaciones'); esta migración no la modifica.
--   4. PARAMETRO_PROGRAMACION (tabla_maestra): valores de la bandeja que antes iban fijos en los SPs.
--        HORAS_JORNADA (8) · DIAS_LABORABLES_SEMANA (6) · DIAS_ALERTA_SSOMA (7)
--      Si el catálogo ya existe (otra instalación) se reutiliza su IdMaestro; si no, se crea con el siguiente libre.
--   No borra ni cambia datos existentes. IDEMPOTENTE (se puede volver a ejecutar). Ejecutar junto con los SPs del paquete.
-- ============================================================

-- ── 1. Solicitudes de reprogramación ──────────────────────────────────────────
-- estado: pendiente → aprobada | rechazada | cancelada
CREATE TABLE IF NOT EXISTS os_reprogramacion (
    id_reprogramacion      BIGINT          NOT NULL AUTO_INCREMENT,
    id_os                  BIGINT          NOT NULL,
    id_solicitante         BIGINT          NOT NULL,
    id_aprobador           BIGINT          NULL,       -- Jefe de Operaciones al que se dirige (opcional)
    fecha_actual           DATE            NULL,       -- programación vigente al pedir el cambio
    hora_actual            TIME            NULL,
    fecha_propuesta        DATE            NOT NULL,
    hora_propuesta         TIME            NULL,
    id_motivo              INT             NOT NULL,   -- Num1 de MOTIVO_REPROGRAMACION (catálogo 13)
    comentario             VARCHAR(500)    NOT NULL,
    estado                 ENUM('pendiente','aprobada','rechazada','cancelada') NOT NULL DEFAULT 'pendiente',
    fecha_solicitud        DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    resuelto_por           BIGINT          NULL,
    fecha_resolucion       DATETIME        NULL,
    comentario_resolucion  VARCHAR(500)    NULL,
    -- AUDITORÍA
    creado_en              DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por             BIGINT          NULL,
    modificado_en          DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por         BIGINT          NULL,
    eliminado_en           DATETIME        NULL,
    eliminado_por          BIGINT          NULL,
    PRIMARY KEY (id_reprogramacion),
    KEY ix_os_reprogramacion_os (id_os, estado)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ── 2. Índices (tablas con muchas lecturas en la bandeja) ─────────────────────
SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.STATISTICS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'orden_servicio' AND INDEX_NAME = 'ix_orden_servicio_tecnico_fecha'),
    'ALTER TABLE orden_servicio ADD KEY ix_orden_servicio_tecnico_fecha (id_tecnico_principal, fecha_ejecucion)', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.STATISTICS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'orden_servicio' AND INDEX_NAME = 'ix_orden_servicio_estado_fecha'),
    'ALTER TABLE orden_servicio ADD KEY ix_orden_servicio_estado_fecha (estado, fecha_ejecucion)', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.STATISTICS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'os_personal' AND INDEX_NAME = 'ix_os_personal_usuario_os'),
    'ALTER TABLE os_personal ADD KEY ix_os_personal_usuario_os (id_usuario, id_os)', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.STATISTICS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'ssoma_documento' AND INDEX_NAME = 'ix_ssoma_documento_os_usuario_req'),
    'ALTER TABLE ssoma_documento ADD KEY ix_ssoma_documento_os_usuario_req (id_os, id_usuario, id_requisito, version)', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- ── 3. Acciones (88 ACCION_SISTEMA: Num1 = nivel, String3 = módulo) ───────────
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2, String3)
SELECT 1, 88, 'ACCION_SISTEMA', x.nivel, x.nombre, x.codigo, x.modulo
FROM (SELECT 1 AS nivel, 'Ver la bandeja de programación operativa' AS nombre, 'prog_bandeja' AS codigo, 'operaciones' AS modulo UNION ALL
      SELECT 2, 'Programar, solicitar reprogramación y cancelar servicios',   'prog_gestionar',              'operaciones' UNION ALL
      SELECT 3, 'Reprogramar y resolver solicitudes de reprogramación (jefe)', 'prog_aprobar_reprogramacion', 'operaciones') x
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra t WHERE t.IdMaestro = 88 AND t.IdEmpresa = 1 AND t.String2 = x.codigo);

-- ── 4. Parámetros de la programación ─────────────────────────────────────────
SET @id_param := (SELECT MAX(IdMaestro) FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROGRAMACION');
SET @id_param := IFNULL(@id_param, (SELECT MAX(IdMaestro) + 1 FROM tabla_maestra));

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, Num2, String1, String2)
SELECT 1, @id_param, 'PARAMETRO_PROGRAMACION', x.n, x.valor, x.nombre, x.codigo
FROM (SELECT 1 AS n, 8 AS valor, 'Horas de la jornada de un técnico (capacidad diaria)'               AS nombre, 'HORAS_JORNADA'          AS codigo UNION ALL
      SELECT 2,      6,          'Días laborables de la semana (capacidad semanal = jornada x días)',           'DIAS_LABORABLES_SEMANA'           UNION ALL
      SELECT 4,      7,          'Días de anticipación de la alerta SSOMA por vencer en la bandeja',            'DIAS_ALERTA_SSOMA') x
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra t WHERE t.Descripcion = 'PARAMETRO_PROGRAMACION' AND t.IdEmpresa = 1 AND t.String2 = x.codigo);

-- ── Verificación ─────────────────────────────────────────────────────────────
SELECT 'Migración 85 (debe ser 11)' AS verificacion,
       (SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'os_reprogramacion')
     + (SELECT COUNT(DISTINCT INDEX_NAME) FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE()
          AND INDEX_NAME IN ('ix_orden_servicio_tecnico_fecha', 'ix_orden_servicio_estado_fecha',
                             'ix_os_personal_usuario_os', 'ix_ssoma_documento_os_usuario_req'))
     + (SELECT COUNT(*) FROM tabla_maestra WHERE IdMaestro = 88 AND IdEmpresa = 1
          AND String2 IN ('prog_bandeja', 'prog_gestionar', 'prog_aprobar_reprogramacion'))
     + (SELECT COUNT(DISTINCT String2) FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROGRAMACION' AND IdEmpresa = 1
          AND String2 IN ('HORAS_JORNADA', 'DIAS_LABORABLES_SEMANA', 'DIAS_ALERTA_SSOMA')) AS valor;

-- Quién verá la bandeja: filas de la matriz para el módulo 'operaciones' (si falta un área/rol, se agrega desde Permisos).
SELECT area, rol, acceso FROM permiso_area_rol WHERE modulo = 'operaciones' ORDER BY area, rol;
