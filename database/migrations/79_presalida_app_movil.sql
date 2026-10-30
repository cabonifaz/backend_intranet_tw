-- ============================================================
-- Migración 79 — Detalle del servicio y checklist de pre-salida (App Mobile HU-04)
--   1. checklist_presalida_os ... ítems que el técnico confirma en la app antes de salir
--                                 (expediente revisado, EPP, materiales e insumos, herramientas,
--                                 pesas patrón). Los demás ítems salen de datos existentes
--                                 (confirmación del cliente, SSOMA, OC, repuestos, alertas).
--   2. autorizacion_salida_os ... solicitud del técnico y visto bueno del encargado del área
--                                 (lo da desde la intranet). Con el visto bueno el técnico puede
--                                 iniciar el traslado aunque queden pendientes.
--      area_destino: área que debe autorizar (servicio_tecnico | metrologia), según la RQ.
--   4. area_servicio_rq ......... a qué área (encargado) va cada "Área" de la RQ
--                                 (catálogo AREA_REQUERIMIENTO 64 → AREA_USUARIO 79).
--   3. os_riesgo + catálogo RIESGO_OPERATIVO ... riesgos identificados de cada OS
--                                 (los asignará el módulo de Programación de la intranet).
--   Solo tablas y catálogo NUEVOS: no modifica tablas, SP ni datos de la intranet.
--   IDEMPOTENTE. Se puede re-ejecutar.
-- ============================================================

-- ── 1. Checklist de pre-salida (confirmaciones del técnico) ─────────────────
-- codigo: expediente | epp | materiales | herramientas | pesas_patron
-- Sin UNIQUE (convención del proyecto por el borrado lógico): el SP actualiza la fila vigente.
CREATE TABLE IF NOT EXISTS checklist_presalida_os (
    id_checklist    BIGINT          NOT NULL AUTO_INCREMENT,
    id_os           BIGINT          NOT NULL,
    codigo          VARCHAR(30)     NOT NULL,
    confirmado      TINYINT(1)      NOT NULL DEFAULT 0,
    confirmado_por  BIGINT          NULL,
    confirmado_en   DATETIME        NULL,
    -- AUDITORÍA
    creado_en       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por      BIGINT          NULL,
    modificado_en   DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por  BIGINT          NULL,
    eliminado_en    DATETIME        NULL,
    eliminado_por   BIGINT          NULL,
    PRIMARY KEY (id_checklist),
    KEY ix_checklist_presalida_os (id_os, codigo)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ── 2. Autorización de salida (visto bueno del Jefe de Operaciones) ─────────
-- Una fila por solicitud. La vigente es la última de la OS (mayor id_autorizacion).
-- solicitado_en NULL = el jefe dio el visto bueno sin que el técnico lo pidiera.
CREATE TABLE IF NOT EXISTS autorizacion_salida_os (
    id_autorizacion BIGINT          NOT NULL AUTO_INCREMENT,
    id_os           BIGINT          NOT NULL,
    id_tecnico      BIGINT          NULL,
    motivo          VARCHAR(500)    NULL,
    pendientes      VARCHAR(500)    NULL,
    estado          ENUM('pendiente','aprobada','rechazada') NOT NULL DEFAULT 'pendiente',
    solicitado_en   DATETIME        NULL,
    area_destino    VARCHAR(30)     NULL,   -- código AREA_USUARIO (servicio_tecnico | metrologia); NULL = sin área en la RQ
    id_jefe         BIGINT          NULL,
    resuelto_en     DATETIME        NULL,
    comentario      VARCHAR(500)    NULL,
    -- AUDITORÍA
    creado_en       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por      BIGINT          NULL,
    modificado_en   DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por  BIGINT          NULL,
    eliminado_en    DATETIME        NULL,
    eliminado_por   BIGINT          NULL,
    PRIMARY KEY (id_autorizacion),
    KEY ix_autorizacion_salida_os (id_os, estado),
    KEY ix_autorizacion_salida_estado (estado, solicitado_en)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Si la tabla ya existía (versión anterior de esta migración), se agrega la columna del área.
SET @sql := IF((SELECT COUNT(*) FROM information_schema.COLUMNS
                WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'autorizacion_salida_os' AND COLUMN_NAME = 'area_destino') = 0,
    'ALTER TABLE autorizacion_salida_os ADD COLUMN area_destino VARCHAR(30) NULL AFTER estado',
    'SELECT ''autorizacion_salida_os.area_destino ya existe'' AS info');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF((SELECT COUNT(*) FROM information_schema.STATISTICS
                WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'autorizacion_salida_os' AND INDEX_NAME = 'ix_autorizacion_salida_area') = 0,
    'ALTER TABLE autorizacion_salida_os ADD KEY ix_autorizacion_salida_area (area_destino, estado)',
    'SELECT ''ix_autorizacion_salida_area ya existe'' AS info');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- ── 3. Riesgos identificados por OS ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS os_riesgo (
    id              BIGINT          NOT NULL AUTO_INCREMENT,
    id_os           BIGINT          NOT NULL,
    id_riesgo       INT             NOT NULL,   -- Num1 del catálogo RIESGO_OPERATIVO
    observacion     VARCHAR(300)    NULL,
    -- AUDITORÍA
    creado_en       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por      BIGINT          NULL,
    modificado_en   DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por  BIGINT          NULL,
    eliminado_en    DATETIME        NULL,
    eliminado_por   BIGINT          NULL,
    PRIMARY KEY (id),
    KEY ix_os_riesgo_os (id_os)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Catálogo RIESGO_OPERATIVO (String1 = nombre, String2 = código, String3 = ícono de la app)
SET @id_riesgo := (SELECT MAX(IdMaestro) FROM tabla_maestra WHERE Descripcion = 'RIESGO_OPERATIVO');
SET @id_riesgo := IFNULL(@id_riesgo, (SELECT MAX(IdMaestro) + 1 FROM tabla_maestra));

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2, String3)
SELECT 1, @id_riesgo, 'RIESGO_OPERATIVO', n.orden, n.nombre, n.codigo, n.icono
FROM (
          SELECT 1 AS orden, 'Carga suspendida'          AS nombre, 'CARGA_SUSPENDIDA'    AS codigo, 'alerta'   AS icono
UNION ALL SELECT 2, 'Superficies calientes',     'SUPERFICIE_CALIENTE', 'fuego'
UNION ALL SELECT 3, 'Trabajo en altura',         'TRABAJO_ALTURA',      'altura'
UNION ALL SELECT 4, 'Riesgo eléctrico',          'RIESGO_ELECTRICO',    'electrico'
UNION ALL SELECT 5, 'Espacio confinado',         'ESPACIO_CONFINADO',   'confinado'
UNION ALL SELECT 6, 'Tránsito de montacargas',   'MONTACARGAS',         'vehiculo'
UNION ALL SELECT 7, 'Ruido elevado',             'RUIDO',               'ruido'
UNION ALL SELECT 8, 'Sustancias químicas',       'QUIMICOS',            'quimico'
UNION ALL SELECT 9, 'Otro riesgo',               'OTRO',                'alerta'
) n
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra t
                  WHERE t.IdMaestro = @id_riesgo AND t.IdEmpresa = 1 AND t.String2 = n.codigo);

-- ── 4. Área que autoriza la salida según el "Área" de la RQ ─────────────────
-- id_area_rq   = Num1 del catálogo AREA_REQUERIMIENTO (64), el campo requerimiento.id_area.
-- area_usuario = código del catálogo AREA_USUARIO (79) cuyo encargado autoriza:
--                servicio_tecnico (Jefe de Servicio Técnico) o metrologia (Jefe de Metrología).
-- Tabla propia de la app: no toca el catálogo 64 que administra la intranet.
-- Si se agrega un área nueva a la RQ y no se mapea aquí, la solicitud va a ambos encargados.
CREATE TABLE IF NOT EXISTS area_servicio_rq (
    id_area_rq      INT             NOT NULL,
    area_usuario    VARCHAR(30)     NOT NULL,
    -- AUDITORÍA
    creado_en       DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por      BIGINT          NULL,
    modificado_en   DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por  BIGINT          NULL,
    PRIMARY KEY (id_area_rq)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Carga inicial (solo las áreas aún no mapeadas): Calibración y Metrología → Metrología;
-- Mantenimiento, Soporte técnico, Instalación y demás → Servicio Técnico.
INSERT INTO area_servicio_rq (id_area_rq, area_usuario)
SELECT t.Num1,
       CASE WHEN LOWER(t.String1) LIKE '%metrolog%' OR LOWER(t.String1) LIKE '%calibra%'
            THEN 'metrologia' ELSE 'servicio_tecnico' END
FROM   tabla_maestra t
WHERE  t.IdMaestro = 64 AND t.IdEmpresa = 1 AND t.Num1 IS NOT NULL
  AND  NOT EXISTS (SELECT 1 FROM area_servicio_rq a WHERE a.id_area_rq = t.Num1);

-- ── Verificación ───────────────────────────────────────────────────────────
SELECT TABLE_NAME AS tabla_nueva FROM information_schema.TABLES
WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME IN ('checklist_presalida_os', 'autorizacion_salida_os', 'os_riesgo', 'area_servicio_rq');
SELECT COUNT(*) AS riesgos_en_catalogo FROM tabla_maestra WHERE Descripcion = 'RIESGO_OPERATIVO' AND IdEmpresa = 1;

-- Cómo queda el ruteo: área de la RQ → área que autoriza → encargados activos con ese cargo
SELECT t.Num1 AS id_area_rq, t.String1 AS area_rq, a.area_usuario AS autoriza,
       (SELECT GROUP_CONCAT(CONCAT(u.nombre, ' ', u.apellido) SEPARATOR ', ')
        FROM usuario u
        JOIN tabla_maestra c ON c.IdMaestro = 80 AND c.IdEmpresa = 1 AND c.String2 = u.cargo
        WHERE c.String3 = a.area_usuario AND c.String2 LIKE 'jefe\\_%'
          AND u.estado = 'activo' AND u.eliminado_en IS NULL) AS encargados
FROM tabla_maestra t
LEFT JOIN area_servicio_rq a ON a.id_area_rq = t.Num1
WHERE t.IdMaestro = 64 AND t.IdEmpresa = 1
ORDER BY t.Num1;
