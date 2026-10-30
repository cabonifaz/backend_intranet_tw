-- ============================================================
-- Migración 77 — Refinamiento del Expediente Digital (Sprint 4, HU-29 a HU-33)
--   1. Etapas: RQ, Propuesta, Visto Bueno, Seguimiento, Orden de Compra, Orden de Servicio, Programación, SSOMA,
--      Ejecución y Cierre (+ Cerrado). Revisión técnica, Conformidad y Facturación salen del flujo. Todas las
--      etapas se calculan solas desde los módulos origen (ya no se avanzan a mano).
--      ETAPA_EXPEDIENTE (97): Num1 = orden, String1 = nombre, String2 = código, String3 = área,
--      Num2 = 0 (ya no hay avance manual), Num3 = 1 si es etapa comercial (permite reasignar, HU-33).
--   2. expediente_digital: nuevas etapas en etapa_actual y reinicio del SLA por reasignación (sla_reinicio, sla_reinicio_etapa).
--   3. Responsable comercial de la OC (orden_compra.id_responsable) y de la OS (orden_servicio.id_responsable_comercial),
--      para reasignarlos (HU-33). Se llenan con el responsable de la propuesta.
--   4. SLA de las etapas nuevas (CONFIG_SLA 49): Seguimiento, Orden de Servicio y Cierre.
--   5. Motivos de reasignación (MOTIVO_REASIGNACION_EXPEDIENTE 100) del refinamiento.
--   6. Reasignaciones: expediente_reasignacion (cabecera) y expediente_reasignacion_detalle (entidades).
--   7. Bloqueos automáticos de la OC observada (tipo oc_observada) y los que ya existen; los bloqueos manuales antiguos
--      que siguen abiertos se cierran (ya no se resuelven desde el expediente).
--   8. Acciones que ya no existen: adjuntar documento, avanzar etapa y resolver bloqueos (el expediente es de consulta).
--
--   IDEMPOTENTE. Se puede re-ejecutar.
-- ============================================================

-- ── 1. Etapas ────────────────────────────────────────────────────────────────
-- 1.1 Las etapas que salen del flujo se dan de baja (se mueven a Num1 9x para no chocar con el nuevo orden)
UPDATE tabla_maestra
SET Num1 = CASE String2 WHEN 'revision' THEN 91 WHEN 'conformidad' THEN 92 ELSE 93 END,
    eliminado_en = IFNULL(eliminado_en, NOW())
WHERE IdMaestro = 97 AND IdEmpresa = 1 AND String2 IN ('revision', 'conformidad', 'facturacion');

-- 1.2 Etapas nuevas
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, Num2, Num3, String1, String2, String3)
SELECT 1, 97, 'ETAPA_EXPEDIENTE', v.n, 0, v.comercial, v.nombre, v.codigo, v.area
FROM (
    SELECT 4 AS n, 1 AS comercial, 'Seguimiento' AS nombre, 'seguimiento' AS codigo, 'comercial' AS area UNION ALL
    SELECT 6, 1, 'Orden de Servicio', 'orden_servicio', 'operaciones' UNION ALL
    SELECT 10, 0, 'Cierre',           'cierre',         'operaciones'
) v
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra t WHERE t.IdMaestro = 97 AND t.IdEmpresa = 1 AND t.String2 = v.codigo);

-- 1.3 Orden, nombre, área y si es etapa comercial
UPDATE tabla_maestra t
JOIN (
    SELECT 'requerimiento' AS codigo, 1 AS n, 1 AS comercial, 'Requerimiento' AS nombre, 'comercial' AS area UNION ALL
    SELECT 'propuesta',       2,  1, 'Propuesta',         'comercial'   UNION ALL
    SELECT 'visto_bueno',     3,  1, 'Visto Bueno',       'comercial'   UNION ALL
    SELECT 'seguimiento',     4,  1, 'Seguimiento',       'comercial'   UNION ALL
    SELECT 'orden_compra',    5,  1, 'Orden de Compra',   'comercial'   UNION ALL
    SELECT 'orden_servicio',  6,  1, 'Orden de Servicio', 'operaciones' UNION ALL
    SELECT 'programacion',    7,  0, 'Programación',      'operaciones' UNION ALL
    SELECT 'ssoma',           8,  0, 'SSOMA',             'ssoma'       UNION ALL
    SELECT 'ejecucion',       9,  0, 'Ejecución',         'operaciones' UNION ALL
    SELECT 'cierre',          10, 0, 'Cierre',            'operaciones' UNION ALL
    SELECT 'cerrado',         11, 0, 'Cerrado',           NULL
) v ON v.codigo = t.String2
SET t.Num1 = v.n, t.Num2 = 0, t.Num3 = v.comercial, t.String1 = v.nombre, t.String3 = v.area, t.eliminado_en = NULL
WHERE t.IdMaestro = 97 AND t.IdEmpresa = 1;

-- ── 2. expediente_digital ────────────────────────────────────────────────────
ALTER TABLE expediente_digital
    MODIFY COLUMN etapa_actual ENUM('requerimiento','propuesta','visto_bueno','seguimiento','orden_compra','orden_servicio',
                                    'programacion','ssoma','ejecucion','cierre','revision','conformidad','facturacion','cerrado')
                  NOT NULL DEFAULT 'requerimiento';

-- Expedientes que quedaron en etapas que salen del flujo
UPDATE expediente_digital SET etapa_actual = 'cierre'
WHERE etapa_actual IN ('revision', 'conformidad', 'facturacion');

ALTER TABLE expediente_digital
    MODIFY COLUMN etapa_actual ENUM('requerimiento','propuesta','visto_bueno','seguimiento','orden_compra','orden_servicio',
                                    'programacion','ssoma','ejecucion','cierre','cerrado')
                  NOT NULL DEFAULT 'requerimiento';

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'expediente_digital' AND COLUMN_NAME = 'sla_reinicio'),
    'ALTER TABLE expediente_digital ADD COLUMN sla_reinicio DATETIME NULL AFTER fecha_limite_sla',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'expediente_digital' AND COLUMN_NAME = 'sla_reinicio_etapa'),
    'ALTER TABLE expediente_digital ADD COLUMN sla_reinicio_etapa VARCHAR(30) NULL AFTER sla_reinicio',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- ── 3. Responsable comercial de la OC y de la OS ─────────────────────────────
SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'orden_compra' AND COLUMN_NAME = 'id_responsable'),
    'ALTER TABLE orden_compra ADD COLUMN id_responsable BIGINT NULL AFTER id_cliente',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'orden_servicio' AND COLUMN_NAME = 'id_responsable_comercial'),
    'ALTER TABLE orden_servicio ADD COLUMN id_responsable_comercial BIGINT NULL AFTER id_tecnico_principal',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- OC: responsable de su propuesta principal (o de la primera vinculada), o quien la registró
UPDATE orden_compra oc
SET oc.id_responsable = COALESCE(
        (SELECT COALESCE(p.id_responsable, p.id_creador) FROM propuesta_comercial p WHERE p.id_propuesta = oc.id_propuesta),
        (SELECT COALESCE(p.id_responsable, p.id_creador) FROM oc_propuesta op
         JOIN propuesta_comercial p ON p.id_propuesta = op.id_propuesta
         WHERE op.id_oc = oc.id_oc ORDER BY op.id LIMIT 1),
        oc.creado_por),
    oc.modificado_en = oc.modificado_en
WHERE oc.id_responsable IS NULL;

-- OS: responsable de la propuesta del expediente (o del RQ)
UPDATE orden_servicio os
JOIN expediente_digital e ON e.id_expediente = os.id_expediente
LEFT JOIN propuesta_comercial p ON p.id_propuesta = e.id_propuesta
LEFT JOIN requerimiento r ON r.id_requerimiento = e.id_requerimiento
SET os.id_responsable_comercial = COALESCE(p.id_responsable, p.id_creador, r.id_responsable, r.id_usuario_creador),
    os.modificado_en = os.modificado_en
WHERE os.id_responsable_comercial IS NULL;

-- ── 4. SLA de las etapas nuevas (horas en Num2, alerta en Num3) ──────────────
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, Num2, Num3, String1, String2, String3)
SELECT 1, 49, 'CONFIG_SLA',
       (SELECT IFNULL(MAX(t.Num1), 0) FROM tabla_maestra t WHERE t.IdMaestro = 49 AND t.IdEmpresa = 1) + v.n,
       v.horas, v.alerta, 'expediente', v.etapa, '1'
FROM (
    SELECT 1 AS n, 'seguimiento' AS etapa, 168 AS horas, 48 AS alerta UNION ALL
    SELECT 2, 'orden_servicio', 24, 8 UNION ALL
    SELECT 3, 'cierre',         72, 24
) v
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra t
                  WHERE t.IdMaestro = 49 AND t.IdEmpresa = 1 AND t.String1 = 'expediente' AND t.String2 = v.etapa)
ORDER BY v.n;

-- ── 5. Motivos de reasignación (en el orden del refinamiento) ────────────────
UPDATE tabla_maestra t
JOIN (
    SELECT 1 AS n, 'Vacaciones' AS nombre, 'VACACIONES' AS codigo UNION ALL
    SELECT 2, 'Cambio de puesto',         'CAMBIO_PUESTO'  UNION ALL
    SELECT 3, 'Renuncia',                 'RENUNCIA'       UNION ALL
    SELECT 4, 'Carga de trabajo alta',    'CARGA_TRABAJO'  UNION ALL
    SELECT 5, 'Redistribución operativa', 'REDISTRIBUCION' UNION ALL
    SELECT 6, 'Otro',                     'OTRO'
) v ON v.n = t.Num1
SET t.String1 = v.nombre, t.String2 = v.codigo, t.eliminado_en = NULL
WHERE t.IdMaestro = 100 AND t.IdEmpresa = 1;

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2)
SELECT 1, 100, 'MOTIVO_REASIGNACION_EXPEDIENTE', v.n, v.nombre, v.codigo
FROM (
    SELECT 1 AS n, 'Vacaciones' AS nombre, 'VACACIONES' AS codigo UNION ALL
    SELECT 2, 'Cambio de puesto',         'CAMBIO_PUESTO'  UNION ALL
    SELECT 3, 'Renuncia',                 'RENUNCIA'       UNION ALL
    SELECT 4, 'Carga de trabajo alta',    'CARGA_TRABAJO'  UNION ALL
    SELECT 5, 'Redistribución operativa', 'REDISTRIBUCION' UNION ALL
    SELECT 6, 'Otro',                     'OTRO'
) v
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra t WHERE t.IdMaestro = 100 AND t.IdEmpresa = 1 AND t.Num1 = v.n);

-- ── 6. Reasignaciones ────────────────────────────────────────────────────────
-- Cabecera: una por cada confirmación del modal (modo entidad, cascada o global)
CREATE TABLE IF NOT EXISTS expediente_reasignacion (
    id_reasignacion         BIGINT        NOT NULL AUTO_INCREMENT,
    modo                    VARCHAR(20)   NOT NULL,              -- entidad, cascada, global
    id_expediente           BIGINT        NULL,                  -- expediente desde el que se abrió el modal
    entidad_tipo            VARCHAR(30)   NULL,                  -- raíz (entidad o cascada): requerimiento, propuesta, orden_compra, orden_servicio
    id_entidad              BIGINT        NULL,
    codigo_entidad          VARCHAR(60)   NULL,
    id_responsable_anterior BIGINT        NULL,
    id_responsable_nuevo    BIGINT        NOT NULL,
    id_motivo               INT           NOT NULL,
    comentario              VARCHAR(1000) NOT NULL,
    gestion_sla             VARCHAR(20)   NOT NULL,              -- mantener, reiniciar
    total_entidades         INT           NOT NULL DEFAULT 0,
    total_expedientes       INT           NOT NULL DEFAULT 0,
    registrado_en           DATETIME      NOT NULL,
    registrado_por          BIGINT        NOT NULL,
    SoftDelete              TINYINT(1)    NOT NULL DEFAULT 0,
    UsuCre                  VARCHAR(100)  NULL,
    FchCre                  DATETIME      NULL,
    UsuMod                  VARCHAR(100)  NULL,
    FchMod                  DATETIME      NULL,
    PRIMARY KEY (id_reasignacion)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Detalle: cada entidad reasignada (con su expediente, para el historial de cada uno)
CREATE TABLE IF NOT EXISTS expediente_reasignacion_detalle (
    id_detalle              BIGINT        NOT NULL AUTO_INCREMENT,
    id_reasignacion         BIGINT        NOT NULL,
    id_expediente           BIGINT        NOT NULL,
    entidad_tipo            VARCHAR(30)   NOT NULL,
    id_entidad              BIGINT        NOT NULL,
    codigo_entidad          VARCHAR(60)   NULL,
    id_responsable_anterior BIGINT        NULL,
    id_responsable_nuevo    BIGINT        NOT NULL,
    etapa                   VARCHAR(30)   NULL,                  -- etapa del expediente al reasignar
    sla_limite_anterior     DATETIME      NULL,
    sla_limite_nuevo        DATETIME      NULL,
    SoftDelete              TINYINT(1)    NOT NULL DEFAULT 0,
    UsuCre                  VARCHAR(100)  NULL,
    FchCre                  DATETIME      NULL,
    UsuMod                  VARCHAR(100)  NULL,
    FchMod                  DATETIME      NULL,
    PRIMARY KEY (id_detalle)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ── 7. Bloqueos automáticos ──────────────────────────────────────────────────
ALTER TABLE expediente_bloqueador
    MODIFY COLUMN tipo ENUM('documento_faltante','ssoma','cobertura_oc','sin_aprobacion','oc_observada','otro') NOT NULL;

-- OC observadas hoy (sin bloqueo abierto): corrección del cliente o nueva versión bloquean; la informativa es excepción
INSERT INTO expediente_bloqueador (id_expediente, clase, descripcion, tipo, etapa, impacto, critico, origen_tipo, id_origen,
                                   id_responsable, resuelto, creado_en, creado_por)
SELECT x.id_expediente,
       IF(MAX(x.bloquea) = 1, 'bloqueo', 'excepcion'),
       LEFT(CONCAT('OC ', x.numero_oc, ' observada', IF(MAX(x.bloquea) = 1, ' (requiere corrección)', ' (observación informativa)')), 300),
       'oc_observada', 'orden_compra',
       IF(MAX(x.bloquea) = 1, 'No se puede pasar a Orden de Servicio hasta corregir y validar la OC.',
                              'La OC tiene observaciones informativas registradas por el comercial.'),
       MAX(x.bloquea), 'orden_compra', x.id_oc, MAX(x.id_responsable), 0, MIN(x.fecha), MIN(x.decidido_por)
FROM (
    SELECT FN_ExpedienteDePropuesta(op.id_propuesta) AS id_expediente, oc.id_oc, oc.numero_oc,
           (op.tipo_observacion IN ('correccion_cliente', 'nueva_version')) AS bloquea,
           COALESCE(oc.id_responsable, p.id_responsable, p.id_creador) AS id_responsable,
           IFNULL(op.fecha_decision, oc.fecha_registro) AS fecha, op.decidido_por
    FROM oc_propuesta op
    JOIN orden_compra oc ON oc.id_oc = op.id_oc AND oc.eliminado_en IS NULL AND oc.estado <> 'anulada' AND oc.reemplazada_por IS NULL
    JOIN propuesta_comercial p ON p.id_propuesta = op.id_propuesta
    WHERE op.eliminado_en IS NULL AND op.estado_validacion = 'observada'
) x
WHERE x.id_expediente IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM expediente_bloqueador b
                  WHERE b.id_expediente = x.id_expediente AND b.origen_tipo = 'orden_compra' AND b.id_origen = x.id_oc
                    AND b.resuelto = 0 AND b.eliminado_en IS NULL)
GROUP BY x.id_expediente, x.id_oc, x.numero_oc;

-- Bloqueos abiertos de OC que ya no están observadas (validadas, anuladas o reemplazadas)
UPDATE expediente_bloqueador b
JOIN orden_compra oc ON oc.id_oc = b.id_origen
SET b.resuelto = 1, b.fecha_resolucion = NOW(),
    b.sustento = CASE WHEN oc.estado = 'anulada' OR oc.eliminado_en IS NOT NULL THEN 'Resuelto en Órdenes de Compra: la OC fue anulada.'
                      WHEN oc.reemplazada_por IS NOT NULL THEN 'Resuelto en Órdenes de Compra: la OC fue reemplazada.'
                      ELSE 'Resuelto en Órdenes de Compra: la OC fue validada.' END
WHERE b.origen_tipo = 'orden_compra' AND b.resuelto = 0 AND b.eliminado_en IS NULL
  AND NOT EXISTS (SELECT 1 FROM oc_propuesta op
                  WHERE op.id_oc = oc.id_oc AND op.eliminado_en IS NULL AND op.estado_validacion = 'observada'
                    AND oc.eliminado_en IS NULL AND oc.estado <> 'anulada' AND oc.reemplazada_por IS NULL
                    AND FN_ExpedienteDePropuesta(op.id_propuesta) = b.id_expediente);

-- Bloqueos y excepciones registrados a mano antes del refinamiento que siguen abiertos: ya no hay dónde resolverlos
-- (el expediente es de consulta), así que se cierran con su sustento; quedan en la pestaña Bloqueos de la auditoría.
UPDATE expediente_bloqueador
SET resuelto = 1, fecha_resolucion = NOW(),
    sustento = CONCAT(IFNULL(CONCAT(sustento, ' '), ''),
                      'Cerrado por el refinamiento del Expediente Digital: los bloqueos se resuelven en el módulo origen.')
WHERE resuelto = 0 AND eliminado_en IS NULL AND IFNULL(origen_tipo, '') <> 'orden_compra';

-- ── 8. Acciones que ya no existen (el expediente es solo de consulta) ────────
UPDATE tabla_maestra SET eliminado_en = IFNULL(eliminado_en, NOW())
WHERE IdMaestro = 88 AND IdEmpresa = 1
  AND String2 IN ('expediente_documento_adjuntar', 'expediente_avanzar', 'expediente_resolver_bloqueo');

UPDATE tabla_maestra SET String1 = 'Ver la bandeja, la ficha, los documentos y la auditoría de los expedientes'
WHERE IdMaestro = 88 AND IdEmpresa = 1 AND String2 = 'expediente_bandeja';

UPDATE tabla_maestra SET String1 = 'Reasignar el responsable comercial de RQ, propuestas, OC y OS'
WHERE IdMaestro = 88 AND IdEmpresa = 1 AND String2 = 'expediente_reasignar';

-- ── 9. Pestañas del repositorio de documentos (HU-31): Comerciales, Operativos, SSOMA y Técnicos ─────
-- Metrología y Conformidad pasan a Técnicos; Facturación a Operativos.
UPDATE tabla_maestra SET eliminado_en = IFNULL(eliminado_en, NOW())
WHERE IdMaestro = 101 AND IdEmpresa = 1 AND String2 IN ('metrologia', 'conformidad', 'facturacion');

UPDATE tabla_maestra SET String3 = CASE String3 WHEN 'metrologia' THEN 'tecnicos' WHEN 'conformidad' THEN 'tecnicos'
                                                WHEN 'facturacion' THEN 'operativos' ELSE String3 END
WHERE IdMaestro = 96 AND IdEmpresa = 1 AND String3 IN ('metrologia', 'conformidad', 'facturacion');

UPDATE tabla_maestra SET String3 = 'operativos'
WHERE IdMaestro = 96 AND IdEmpresa = 1 AND String2 = 'ORDEN_COMPRA';
