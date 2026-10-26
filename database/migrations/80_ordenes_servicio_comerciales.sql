-- ============================================================
-- Migración 80 — Módulo Órdenes de Servicio / Metrología (Sprint 4, HU-40 a HU-44)
--   La OS/OM comercial usa la tabla orden_servicio que ya leen el Expediente Digital y la app móvil:
--   una sola tabla para OS y OM (columna tipo). La OS/OM nace de una propuesta aceptada en estado BORRADOR,
--   el comercial la EMITE y desde ahí sigue el ciclo operativo que ya existía (programada, en_ruta, en_ejecucion,
--   pausada, reprogramada, bloqueada, finalizada, anulada). orden_metrologia queda para la ejecución metrológica
--   (certificado) y se vincula por id_os.
--
--   1. orden_servicio: estados borrador y emitida; columnas comerciales (tipo, propuesta, RQ, contacto, emisión,
--      rango de fecha programada tentativa, observaciones, datos del certificado de la OM y anulación). Las columnas
--      operativas que define Programación (sede, fecha y hora de ejecución, expediente, tipo de servicio) pasan a
--      aceptar NULL: una OS en borrador o emitida todavía no las tiene.
--   2. os_equipo: orden, estado de ejecución por equipo (Módulo 11) y fecha; el tipo de intervención pasa a opcional.
--   3. os_concepto ............ conceptos del servicio (suministros de clase servicio), sin precios.
--   4. os_concepto_equipo ..... a qué equipos aplica cada concepto (sin filas = "General").
--   5. os_solicitud ........... solicitudes de edición (y, si se confirma, de anulación) al Jefe Comercial.
--   6. Catálogos MOTIVO_EDICION_OS y MOTIVO_ANULACION_OS.
--   7. Acciones: os_bandeja (Comercial), os_bandeja_operaciones (Operaciones, consulta), os_guardar, os_anular,
--      os_aprobar_edicion (Jefe Comercial).
--
--   No borra ni cambia datos existentes. IDEMPOTENTE. Se puede re-ejecutar.
-- ============================================================

-- ── 1. orden_servicio ─────────────────────────────────────────────────────────
ALTER TABLE orden_servicio
    MODIFY COLUMN estado ENUM('borrador','emitida','programada','en_ruta','en_ejecucion','pausada','finalizada',
                              'reprogramada','anulada','bloqueada') NOT NULL DEFAULT 'programada',
    MODIFY COLUMN id_expediente    BIGINT   NULL,
    MODIFY COLUMN id_sede          BIGINT   NULL,
    MODIFY COLUMN id_tipo_servicio INT      NULL,
    MODIFY COLUMN fecha_ejecucion  DATE     NULL,
    MODIFY COLUMN hora_inicio      TIME     NULL,
    MODIFY COLUMN fecha_creacion   DATETIME NULL;

DROP PROCEDURE IF EXISTS tmp_mig80_columna;
DELIMITER $$
CREATE PROCEDURE tmp_mig80_columna(IN p_tabla VARCHAR(64), IN p_columna VARCHAR(64), IN p_definicion VARCHAR(500))
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                   WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = p_tabla AND COLUMN_NAME = p_columna) THEN
        SET @sql = CONCAT('ALTER TABLE ', p_tabla, ' ADD COLUMN ', p_columna, ' ', p_definicion);
        PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;
    END IF;
END$$
DELIMITER ;

CALL tmp_mig80_columna('orden_servicio', 'tipo',                   "ENUM('OS','OM') NOT NULL DEFAULT 'OS' AFTER numero");
CALL tmp_mig80_columna('orden_servicio', 'id_propuesta',           'BIGINT NULL AFTER id_expediente');
CALL tmp_mig80_columna('orden_servicio', 'id_requerimiento',       'BIGINT NULL AFTER id_propuesta');
CALL tmp_mig80_columna('orden_servicio', 'id_contacto',            'BIGINT NULL AFTER id_sede');
CALL tmp_mig80_columna('orden_servicio', 'fecha_emision',          'DATETIME NULL AFTER estado');
CALL tmp_mig80_columna('orden_servicio', 'emitido_por',            'BIGINT NULL AFTER fecha_emision');
CALL tmp_mig80_columna('orden_servicio', 'fecha_programada_desde', 'DATE NULL AFTER emitido_por');
CALL tmp_mig80_columna('orden_servicio', 'fecha_programada_hasta', 'DATE NULL AFTER fecha_programada_desde');
CALL tmp_mig80_columna('orden_servicio', 'observaciones',          'TEXT NULL AFTER fecha_programada_hasta');
CALL tmp_mig80_columna('orden_servicio', 'es_tercerizado',         'TINYINT(1) NOT NULL DEFAULT 0 AFTER observaciones');
CALL tmp_mig80_columna('orden_servicio', 'cert_razon_social',      'VARCHAR(300) NULL AFTER es_tercerizado');
CALL tmp_mig80_columna('orden_servicio', 'cert_ruc',               'VARCHAR(11) NULL AFTER cert_razon_social');
CALL tmp_mig80_columna('orden_servicio', 'cert_direccion',         'VARCHAR(500) NULL AFTER cert_ruc');
CALL tmp_mig80_columna('orden_servicio', 'cert_contacto',          'VARCHAR(200) NULL AFTER cert_direccion');
CALL tmp_mig80_columna('orden_servicio', 'id_motivo_anulacion',    'INT NULL AFTER cert_contacto');
CALL tmp_mig80_columna('orden_servicio', 'comentario_anulacion',   'VARCHAR(500) NULL AFTER id_motivo_anulacion');
CALL tmp_mig80_columna('orden_servicio', 'anulado_en',             'DATETIME NULL AFTER comentario_anulacion');
CALL tmp_mig80_columna('orden_servicio', 'anulado_por',            'BIGINT NULL AFTER anulado_en');

-- ── 2. os_equipo ──────────────────────────────────────────────────────────────
ALTER TABLE os_equipo MODIFY COLUMN id_tipo_intervencion INT NULL;
CALL tmp_mig80_columna('os_equipo', 'orden',                 'INT NULL AFTER id_equipo');
CALL tmp_mig80_columna('os_equipo', 'estado_ejecucion',      "ENUM('pendiente','en_proceso','ejecutado','observado') NOT NULL DEFAULT 'pendiente' AFTER ingresado_en_campo");
CALL tmp_mig80_columna('os_equipo', 'fecha_ejecucion',       'DATETIME NULL AFTER estado_ejecucion');
CALL tmp_mig80_columna('os_equipo', 'observacion_ejecucion', 'VARCHAR(500) NULL AFTER fecha_ejecucion');

DROP PROCEDURE IF EXISTS tmp_mig80_columna;

-- Índices para la bandeja (tabla con muchas lecturas)
SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.STATISTICS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'orden_servicio' AND INDEX_NAME = 'ix_orden_servicio_propuesta'),
    'ALTER TABLE orden_servicio ADD KEY ix_orden_servicio_propuesta (id_propuesta)', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.STATISTICS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'os_equipo' AND INDEX_NAME = 'ix_os_equipo_os'),
    'ALTER TABLE os_equipo ADD KEY ix_os_equipo_os (id_os)', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- ── 3. Conceptos del servicio ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS os_concepto (
    id              BIGINT          NOT NULL AUTO_INCREMENT,
    id_os           BIGINT          NOT NULL,
    id_suministro   BIGINT          NULL,       -- suministros (clase servicio)
    codigo          VARCHAR(30)     NULL,       -- copia del código del suministro al agregarlo
    descripcion     VARCHAR(300)    NOT NULL,   -- copia de la descripción (no cambia si se edita el catálogo)
    orden           INT             NOT NULL DEFAULT 1,
    -- AUDITORÍA
    creado_en       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por      BIGINT          NULL,
    modificado_en   DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por  BIGINT          NULL,
    eliminado_en    DATETIME        NULL,
    eliminado_por   BIGINT          NULL,
    PRIMARY KEY (id),
    KEY ix_os_concepto_os (id_os)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ── 4. Concepto ↔ equipo (un concepto sin filas aplica a toda la OS: "General") ──
CREATE TABLE IF NOT EXISTS os_concepto_equipo (
    id              BIGINT          NOT NULL AUTO_INCREMENT,
    id_os           BIGINT          NOT NULL,
    id_os_concepto  BIGINT          NOT NULL,
    id_os_equipo    BIGINT          NOT NULL,
    -- AUDITORÍA
    creado_en       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por      BIGINT          NULL,
    modificado_en   DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por  BIGINT          NULL,
    eliminado_en    DATETIME        NULL,
    eliminado_por   BIGINT          NULL,
    PRIMARY KEY (id),
    KEY ix_os_concepto_equipo_os (id_os)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ── 5. Solicitudes al Jefe Comercial ──────────────────────────────────────────
-- estado: pendiente → aprobada (el comercial ya puede editar) → ejecutada (guardó los cambios) | rechazada | cancelada
CREATE TABLE IF NOT EXISTS os_solicitud (
    id_solicitud           BIGINT          NOT NULL AUTO_INCREMENT,
    id_os                  BIGINT          NOT NULL,
    tipo                   ENUM('edicion','anulacion') NOT NULL DEFAULT 'edicion',
    id_motivo              INT             NOT NULL,   -- Num1 de MOTIVO_EDICION_OS / MOTIVO_ANULACION_OS
    comentario             VARCHAR(500)    NOT NULL,
    estado                 ENUM('pendiente','aprobada','rechazada','ejecutada','cancelada') NOT NULL DEFAULT 'pendiente',
    id_solicitante         BIGINT          NOT NULL,
    id_aprobador           BIGINT          NULL,       -- Jefe Comercial al que se dirige
    fecha_solicitud        DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    resuelto_por           BIGINT          NULL,
    fecha_resolucion       DATETIME        NULL,
    comentario_resolucion  VARCHAR(500)    NULL,
    fecha_ejecucion        DATETIME        NULL,
    -- AUDITORÍA
    creado_en              DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por             BIGINT          NULL,
    modificado_en          DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por         BIGINT          NULL,
    eliminado_en           DATETIME        NULL,
    eliminado_por          BIGINT          NULL,
    PRIMARY KEY (id_solicitud),
    KEY ix_os_solicitud_os (id_os, estado)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ── 6. Catálogos (String1 = nombre, String2 = código) ─────────────────────────
SET @id_cat := (SELECT MAX(IdMaestro) FROM tabla_maestra WHERE Descripcion = 'MOTIVO_EDICION_OS');
SET @id_cat := IFNULL(@id_cat, (SELECT MAX(IdMaestro) + 1 FROM tabla_maestra));
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2)
SELECT 1, @id_cat, 'MOTIVO_EDICION_OS', x.n, x.nombre, x.codigo
FROM (SELECT 1 AS n, 'Agregar o quitar equipos' AS nombre, 'equipos' AS codigo UNION ALL
      SELECT 2, 'Cambiar conceptos del servicio', 'conceptos' UNION ALL
      SELECT 3, 'Cambiar la fecha programada',    'fecha'     UNION ALL
      SELECT 4, 'Cambiar el contacto',            'contacto'  UNION ALL
      SELECT 5, 'Corregir observaciones',         'observaciones' UNION ALL
      SELECT 6, 'Corregir datos del certificado', 'certificado' UNION ALL
      SELECT 7, 'Otro',                           'otro') x
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra t WHERE t.Descripcion = 'MOTIVO_EDICION_OS' AND t.String2 = x.codigo);

SET @id_cat := (SELECT MAX(IdMaestro) FROM tabla_maestra WHERE Descripcion = 'MOTIVO_ANULACION_OS');
SET @id_cat := IFNULL(@id_cat, (SELECT MAX(IdMaestro) + 1 FROM tabla_maestra));
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2)
SELECT 1, @id_cat, 'MOTIVO_ANULACION_OS', 1, 'Disponibilidad de equipos del cliente', 'disponibilidad_equipos'
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra t WHERE t.Descripcion = 'MOTIVO_ANULACION_OS' AND t.String2 = 'disponibilidad_equipos');

-- ── 7. Acciones (88 ACCION_SISTEMA: Num1 = nivel, String3 = módulo) ──────────
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2, String3)
SELECT 1, 88, 'ACCION_SISTEMA', x.nivel, x.nombre, x.codigo, x.modulo
FROM (SELECT 1 AS nivel, 'Ver bandeja y detalle de órdenes de servicio / metrología' AS nombre, 'os_bandeja' AS codigo, 'propuestas' AS modulo UNION ALL
      SELECT 1, 'Consultar órdenes de servicio / metrología (Operaciones)', 'os_bandeja_operaciones', 'operaciones' UNION ALL
      SELECT 2, 'Crear, editar y emitir órdenes de servicio / metrología',  'os_guardar',            'propuestas' UNION ALL
      SELECT 2, 'Anular órdenes de servicio / metrología',                  'os_anular',             'propuestas' UNION ALL
      SELECT 3, 'Aprobar o rechazar la edición de una OS / OM emitida',     'os_aprobar_edicion',    'propuestas') x
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra t WHERE t.IdMaestro = 88 AND t.IdEmpresa = 1 AND t.String2 = x.codigo);

-- ── Verificación ─────────────────────────────────────────────────────────────
SELECT 'Migración 80 (debe ser 9)' AS verificacion,
       (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'orden_servicio'
          AND COLUMN_NAME IN ('tipo', 'id_propuesta', 'fecha_programada_desde', 'cert_razon_social', 'anulado_en'))
     + (SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME IN ('os_concepto', 'os_concepto_equipo', 'os_solicitud'))
     + (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'os_equipo'
          AND COLUMN_NAME = 'estado_ejecucion') AS valor;
