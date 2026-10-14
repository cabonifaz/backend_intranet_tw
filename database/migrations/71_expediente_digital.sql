-- ============================================================
-- Migración 71 — Expediente Digital (HU-29 a HU-34)
--   1. expediente_digital: cliente, área responsable, inicio de la etapa actual y su SLA.
--   2. expediente_bloqueador: distingue bloqueo de excepción, guarda su origen (OC, liberación, SSOMA),
--      impacto, motivo, responsable y la resolución (tipo, sustento, evidencia, usuario).
--   3. expediente_etapa: historial de etapas que avanzan desde el expediente (Programación en adelante).
--   4. Catálogos: ETAPA_EXPEDIENTE (97), TIPO_RESOLUCION_BLOQUEO (98), RESULTADO_CIERRE_EXCEPCION (99),
--      MOTIVO_REASIGNACION_EXPEDIENTE (100), CATEGORIA_DOCUMENTO_EXPEDIENTE (101) y tipos de documento
--      interno en TIPO_DOCUMENTO_ADJUNTO (96).
--   5. SLA por etapa del expediente (CONFIG_SLA 49).
--   6. Módulo "expedientes", sus acciones y la matriz de permisos.
--   7. Datos existentes: un expediente por cada RQ (el expediente nace con el RQ), cliente y área de los
--      expedientes ya creados, y origen de los bloqueos que dejaron las OC.
--
--   IDEMPOTENTE. Se puede re-ejecutar.
-- ============================================================

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'expediente_digital' AND COLUMN_NAME = 'id_cliente'),
    'ALTER TABLE expediente_digital ADD COLUMN id_cliente BIGINT NULL AFTER id_orden_compra',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'expediente_digital' AND COLUMN_NAME = 'area_responsable'),
    'ALTER TABLE expediente_digital ADD COLUMN area_responsable VARCHAR(40) NULL AFTER id_responsable_actual',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'expediente_digital' AND COLUMN_NAME = 'fecha_etapa'),
    'ALTER TABLE expediente_digital ADD COLUMN fecha_etapa DATETIME NULL AFTER area_responsable',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'expediente_digital' AND COLUMN_NAME = 'sla_horas'),
    'ALTER TABLE expediente_digital ADD COLUMN sla_horas INT NULL AFTER fecha_etapa',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'expediente_digital' AND COLUMN_NAME = 'fecha_limite_sla'),
    'ALTER TABLE expediente_digital ADD COLUMN fecha_limite_sla DATETIME NULL AFTER sla_horas',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'expediente_bloqueador' AND COLUMN_NAME = 'clase'),
    'ALTER TABLE expediente_bloqueador ADD COLUMN clase ENUM(''bloqueo'',''excepcion'') NOT NULL DEFAULT ''bloqueo'' AFTER id_expediente',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'expediente_bloqueador' AND COLUMN_NAME = 'etapa'),
    'ALTER TABLE expediente_bloqueador ADD COLUMN etapa VARCHAR(30) NULL AFTER tipo',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'expediente_bloqueador' AND COLUMN_NAME = 'id_motivo'),
    'ALTER TABLE expediente_bloqueador ADD COLUMN id_motivo INT NULL AFTER etapa',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'expediente_bloqueador' AND COLUMN_NAME = 'tipo_documental'),
    'ALTER TABLE expediente_bloqueador ADD COLUMN tipo_documental VARCHAR(150) NULL AFTER id_motivo',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'expediente_bloqueador' AND COLUMN_NAME = 'impacto'),
    'ALTER TABLE expediente_bloqueador ADD COLUMN impacto VARCHAR(300) NULL AFTER tipo_documental',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'expediente_bloqueador' AND COLUMN_NAME = 'critico'),
    'ALTER TABLE expediente_bloqueador ADD COLUMN critico TINYINT(1) NOT NULL DEFAULT 1 AFTER impacto',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'expediente_bloqueador' AND COLUMN_NAME = 'origen_tipo'),
    'ALTER TABLE expediente_bloqueador ADD COLUMN origen_tipo VARCHAR(30) NULL AFTER critico',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'expediente_bloqueador' AND COLUMN_NAME = 'id_origen'),
    'ALTER TABLE expediente_bloqueador ADD COLUMN id_origen BIGINT NULL AFTER origen_tipo',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'expediente_bloqueador' AND COLUMN_NAME = 'id_responsable'),
    'ALTER TABLE expediente_bloqueador ADD COLUMN id_responsable BIGINT NULL AFTER id_origen',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'expediente_bloqueador' AND COLUMN_NAME = 'id_tipo_resolucion'),
    'ALTER TABLE expediente_bloqueador ADD COLUMN id_tipo_resolucion INT NULL AFTER fecha_resolucion',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'expediente_bloqueador' AND COLUMN_NAME = 'sustento'),
    'ALTER TABLE expediente_bloqueador ADD COLUMN sustento TEXT NULL AFTER id_tipo_resolucion',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'expediente_bloqueador' AND COLUMN_NAME = 'id_documento_evidencia'),
    'ALTER TABLE expediente_bloqueador ADD COLUMN id_documento_evidencia BIGINT NULL AFTER sustento',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'expediente_bloqueador' AND COLUMN_NAME = 'resuelto_por'),
    'ALTER TABLE expediente_bloqueador ADD COLUMN resuelto_por BIGINT NULL AFTER id_documento_evidencia',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- 3. Historial de etapas
CREATE TABLE IF NOT EXISTS expediente_etapa (
    id_expediente_etapa BIGINT       NOT NULL AUTO_INCREMENT,
    id_expediente       BIGINT       NOT NULL,
    etapa               VARCHAR(30)  NOT NULL,
    area                VARCHAR(40)  NULL,
    id_responsable      BIGINT       NULL,
    fecha_inicio        DATETIME     NOT NULL,
    fecha_fin           DATETIME     NULL,
    sla_horas           INT          NULL,
    fecha_limite        DATETIME     NULL,
    resultado           VARCHAR(30)  NOT NULL DEFAULT 'en_curso',
    comentario          VARCHAR(1000) NULL,
    SoftDelete          TINYINT(1)   NOT NULL DEFAULT 0,
    UsuCre              VARCHAR(100) NULL,
    FchCre              DATETIME     NULL,
    UsuMod              VARCHAR(100) NULL,
    FchMod              DATETIME     NULL,
    PRIMARY KEY (id_expediente_etapa)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- 4. Catálogos
-- 4.1 Etapas: String2 = código, String3 = área responsable, Num2 = 1 si avanza desde el expediente
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, Num2, String1, String2, String3)
SELECT 1, 97, 'ETAPA_EXPEDIENTE', v.n, v.manual, v.nombre, v.codigo, v.area
FROM (
    SELECT 1 AS n, 0 AS manual, 'Requerimiento' AS nombre, 'requerimiento' AS codigo, 'comercial' AS area UNION ALL
    SELECT 2,  0, 'Propuesta',         'propuesta',     'comercial'        UNION ALL
    SELECT 3,  0, 'Visto bueno',       'visto_bueno',   'comercial'        UNION ALL
    SELECT 4,  0, 'Orden de compra',   'orden_compra',  'comercial'        UNION ALL
    SELECT 5,  1, 'Programación',      'programacion',  'operaciones'      UNION ALL
    SELECT 6,  1, 'SSOMA',             'ssoma',         'ssoma'            UNION ALL
    SELECT 7,  1, 'Ejecución',         'ejecucion',     'operaciones'      UNION ALL
    SELECT 8,  1, 'Revisión técnica',  'revision',      'servicio_tecnico' UNION ALL
    SELECT 9,  1, 'Conformidad',       'conformidad',   'comercial'        UNION ALL
    SELECT 10, 1, 'Facturación',       'facturacion',   'administracion'   UNION ALL
    SELECT 11, 0, 'Cerrado',           'cerrado',       NULL
) v
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra t WHERE t.IdMaestro = 97 AND t.IdEmpresa = 1 AND t.String2 = v.codigo);

-- 4.2 Tipos de resolución de un bloqueo
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2)
SELECT 1, 98, 'TIPO_RESOLUCION_BLOQUEO', v.n, v.nombre, v.codigo
FROM (
    SELECT 1 AS n, 'Documento actualizado cargado' AS nombre, 'DOCUMENTO_ACTUALIZADO' AS codigo UNION ALL
    SELECT 2, 'Reemplazo del personal asignado',      'REEMPLAZO_PERSONAL'    UNION ALL
    SELECT 3, 'Autorización de gerencia',             'AUTORIZACION_GERENCIA' UNION ALL
    SELECT 4, 'Corrección de datos en el sistema',    'CORRECCION_DATOS'      UNION ALL
    SELECT 5, 'El bloqueo no aplica',                 'NO_APLICA'             UNION ALL
    SELECT 6, 'Otro',                                 'OTRO'
) v
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra t WHERE t.IdMaestro = 98 AND t.IdEmpresa = 1 AND t.String2 = v.codigo);

-- 4.3 Resultados de cierre de una excepción
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2)
SELECT 1, 99, 'RESULTADO_CIERRE_EXCEPCION', v.n, v.nombre, v.codigo
FROM (
    SELECT 1 AS n, 'Resuelto (Documento Validado)' AS nombre, 'RESUELTO_VALIDADO' AS codigo UNION ALL
    SELECT 2, 'Resuelto con observaciones',          'RESUELTO_OBSERVACIONES' UNION ALL
    SELECT 3, 'Aceptado por gerencia',               'ACEPTADO_GERENCIA'      UNION ALL
    SELECT 4, 'No procede',                          'NO_PROCEDE'
) v
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra t WHERE t.IdMaestro = 99 AND t.IdEmpresa = 1 AND t.String2 = v.codigo);

-- 4.4 Motivos de reasignación del responsable
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2)
SELECT 1, 100, 'MOTIVO_REASIGNACION_EXPEDIENTE', v.n, v.nombre, v.codigo
FROM (
    SELECT 1 AS n, 'Carga operativa' AS nombre, 'CARGA_OPERATIVA' AS codigo UNION ALL
    SELECT 2, 'Ausencia o vacaciones',           'AUSENCIA'          UNION ALL
    SELECT 3, 'Requiere otra especialidad',      'ESPECIALIDAD'      UNION ALL
    SELECT 4, 'Cambio de zona o sede',           'CAMBIO_ZONA'       UNION ALL
    SELECT 5, 'Escalamiento por SLA',            'ESCALAMIENTO_SLA'  UNION ALL
    SELECT 6, 'Otro motivo',                     'OTRO'
) v
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra t WHERE t.IdMaestro = 100 AND t.IdEmpresa = 1 AND t.String2 = v.codigo);

-- 4.5 Categorías (pestañas) del repositorio de documentos
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2)
SELECT 1, 101, 'CATEGORIA_DOCUMENTO_EXPEDIENTE', v.n, v.nombre, v.codigo
FROM (
    SELECT 1 AS n, 'Comerciales' AS nombre, 'comerciales' AS codigo UNION ALL
    SELECT 2, 'Operativos',   'operativos'  UNION ALL
    SELECT 3, 'SSOMA',        'ssoma'       UNION ALL
    SELECT 4, 'Técnicos',     'tecnicos'    UNION ALL
    SELECT 5, 'Metrología',   'metrologia'  UNION ALL
    SELECT 6, 'Conformidad',  'conformidad' UNION ALL
    SELECT 7, 'Facturación',  'facturacion'
) v
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra t WHERE t.IdMaestro = 101 AND t.IdEmpresa = 1 AND t.String2 = v.codigo);

-- 4.6 Tipos de documento: String3 = categoría, Num2 = 1 si se puede adjuntar como documento interno
UPDATE tabla_maestra SET String3 = 'comerciales', Num2 = 0
WHERE IdMaestro = 96 AND IdEmpresa = 1 AND String2 = 'ORDEN_COMPRA' AND String3 IS NULL;

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, Num2, String1, String2, String3)
SELECT 1, 96, 'TIPO_DOCUMENTO_ADJUNTO',
       (SELECT IFNULL(MAX(t.Num1), 0) FROM tabla_maestra t WHERE t.IdMaestro = 96 AND t.IdEmpresa = 1) + v.n,
       1, v.nombre, v.codigo, v.categoria
FROM (
    SELECT 1 AS n, 'Informe interno' AS nombre, 'INFORME_INTERNO' AS codigo, 'operativos' AS categoria UNION ALL
    SELECT 2,  'Informe técnico',                      'INFORME_TECNICO',          'tecnicos'    UNION ALL
    SELECT 3,  'Checklist de servicio',                'CHECKLIST',                'tecnicos'    UNION ALL
    SELECT 4,  'Evidencia fotográfica',                'EVIDENCIA_FOTOGRAFICA',    'operativos'  UNION ALL
    SELECT 5,  'Documento SSOMA',                      'DOCUMENTO_SSOMA',          'ssoma'       UNION ALL
    SELECT 6,  'Certificado de calibración',           'CERTIFICADO_CALIBRACION',  'metrologia'  UNION ALL
    SELECT 7,  'Acta de conformidad',                  'ACTA_CONFORMIDAD',         'conformidad' UNION ALL
    SELECT 8,  'Factura',                              'FACTURA',                  'facturacion' UNION ALL
    SELECT 9,  'Comunicación del cliente',             'COMUNICACION_CLIENTE',     'comerciales' UNION ALL
    SELECT 10, 'Otro documento',                       'OTRO',                     'operativos'
) v
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra t WHERE t.IdMaestro = 96 AND t.IdEmpresa = 1 AND t.String2 = v.codigo)
ORDER BY v.n;

-- 5. SLA por etapa (horas en Num2, alerta en Num3). Programación y SSOMA ya existen.
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, Num2, Num3, String1, String2, String3)
SELECT 1, 49, 'CONFIG_SLA',
       (SELECT IFNULL(MAX(t.Num1), 0) FROM tabla_maestra t WHERE t.IdMaestro = 49 AND t.IdEmpresa = 1) + v.n,
       v.horas, v.alerta, 'expediente', v.etapa, '1'
FROM (
    SELECT 1 AS n, 'requerimiento' AS etapa, 48 AS horas, 24 AS alerta UNION ALL
    SELECT 2, 'propuesta',     72, 24 UNION ALL
    SELECT 3, 'visto_bueno',   24,  8 UNION ALL
    SELECT 4, 'orden_compra', 120, 48 UNION ALL
    SELECT 5, 'ejecucion',     72, 24 UNION ALL
    SELECT 6, 'revision',      48, 24 UNION ALL
    SELECT 7, 'conformidad',   72, 24 UNION ALL
    SELECT 8, 'facturacion',   72, 24
) v
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra t
                  WHERE t.IdMaestro = 49 AND t.IdEmpresa = 1 AND t.String1 = 'expediente' AND t.String2 = v.etapa)
ORDER BY v.n;

-- 6. Módulo, acciones y permisos
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2, String3)
SELECT 1, 85, 'MODULO_SISTEMA',
       (SELECT IFNULL(MAX(t.Num1), 0) FROM tabla_maestra t WHERE t.IdMaestro = 85 AND t.IdEmpresa = 1) + 1,
       'Expediente Digital', 'expedientes', 'operaciones'
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra WHERE IdMaestro = 85 AND IdEmpresa = 1 AND String2 = 'expedientes');

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2, String3)
SELECT 1, 88, 'ACCION_SISTEMA', v.nivel, v.nombre, v.codigo, 'expedientes'
FROM (
    SELECT 1 AS nivel, 'Ver la bandeja, el detalle, los documentos y el historial de expedientes' AS nombre,
           'expediente_bandeja' AS codigo UNION ALL
    SELECT 2, 'Adjuntar documentos internos al expediente',        'expediente_documento_adjuntar' UNION ALL
    SELECT 2, 'Avanzar el expediente a la siguiente etapa',        'expediente_avanzar'            UNION ALL
    SELECT 3, 'Resolver bloqueos y cerrar excepciones',            'expediente_resolver_bloqueo'   UNION ALL
    SELECT 3, 'Reasignar el responsable del expediente',           'expediente_reasignar'
) v
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra t WHERE t.IdMaestro = 88 AND t.IdEmpresa = 1 AND t.String2 = v.codigo);

-- Matriz: las áreas responsables de alguna etapa (Comercial, Operaciones, SSOMA, Servicio Técnico y
-- Administración/Contabilidad) trabajan el expediente: sus jefes resuelven bloqueos y reasignan, sus usuarios
-- adjuntan documentos y avanzan la etapa de su área. Gerencia y TI administran. Metrología y Calidad consultan.
-- INSERT IGNORE: no pisa cambios hechos a mano en la matriz.
INSERT IGNORE INTO permiso_area_rol (area, rol, modulo, acceso, UsuMod, FchMod)
SELECT a.area, r.rol, 'expedientes',
       CASE
           WHEN a.area IN ('gerencia', 'ti') AND r.rol = 'administrador'                  THEN 'administrar'
           WHEN a.area IN ('comercial', 'operaciones') AND r.rol = 'administrador'         THEN 'administrar'
           WHEN a.area IN ('comercial', 'operaciones', 'ssoma', 'servicio_tecnico', 'administracion', 'gerencia')
                AND r.rol IN ('administrador', 'supervisor')                              THEN 'supervisar'
           WHEN a.area IN ('comercial', 'operaciones', 'ssoma', 'servicio_tecnico', 'administracion')
                AND r.rol = 'usuario'                                                     THEN 'editar'
           ELSE 'ver'
       END,
       'migracion_71', NOW()
FROM (SELECT 'comercial' AS area UNION ALL SELECT 'operaciones' UNION ALL SELECT 'ssoma' UNION ALL
      SELECT 'gerencia' UNION ALL SELECT 'ti' UNION ALL SELECT 'administracion' UNION ALL
      SELECT 'metrologia' UNION ALL SELECT 'servicio_tecnico' UNION ALL SELECT 'calidad') a
CROSS JOIN (SELECT 'administrador' AS rol UNION ALL SELECT 'supervisor' UNION ALL
            SELECT 'usuario' UNION ALL SELECT 'visor') r
WHERE NOT (a.area = 'ti' AND r.rol <> 'administrador');

-- 7. Datos existentes
-- 7.1 Expedientes ya creados (al liberar OC): RQ y cliente desde la propuesta
UPDATE expediente_digital e
JOIN propuesta_comercial p ON p.id_propuesta = e.id_propuesta
SET e.id_requerimiento = IFNULL(e.id_requerimiento, p.id_requerimiento),
    e.id_cliente       = IFNULL(e.id_cliente, p.id_cliente)
WHERE e.id_requerimiento IS NULL OR e.id_cliente IS NULL;

UPDATE expediente_digital e
JOIN requerimiento r ON r.id_requerimiento = e.id_requerimiento
SET e.id_cliente = r.id_cliente
WHERE e.id_cliente IS NULL;

-- 7.2 Un expediente por cada RQ que aún no lo tiene (número provisional, luego EXP-AAAA-NNNN con el id)
INSERT INTO expediente_digital (numero, id_requerimiento, id_cliente, etapa_actual, estado,
                                area_responsable, fecha_creacion, fecha_cierre, creado_por)
SELECT CONCAT('EXP-TMP-', r.id_requerimiento), r.id_requerimiento, r.id_cliente,
       IF(r.estado = 'anulado', 'cerrado', 'requerimiento'),
       IF(r.estado = 'anulado', 'cerrado', 'activo'),
       IF(r.estado = 'anulado', NULL, 'comercial'),
       IFNULL(r.fecha_creacion, r.creado_en),
       IF(r.estado = 'anulado', IFNULL(r.modificado_en, r.fecha_creacion), NULL),
       r.id_usuario_creador
FROM requerimiento r
WHERE IFNULL(r.SoftDelete, 0) = 0 AND r.eliminado_en IS NULL
  AND NOT EXISTS (SELECT 1 FROM expediente_digital e
                  WHERE e.id_requerimiento = r.id_requerimiento AND e.eliminado_en IS NULL);

UPDATE expediente_digital
SET numero = CONCAT('EXP-', YEAR(fecha_creacion), '-', LPAD(id_expediente, 4, '0'))
WHERE numero LIKE 'EXP-TMP-%';

-- 7.3 Etapa ya liberada (Programación en adelante): área, inicio de la etapa y su SLA
UPDATE expediente_digital e
LEFT JOIN tabla_maestra et ON et.IdMaestro = 97 AND et.IdEmpresa = 1 AND et.String2 = e.etapa_actual
LEFT JOIN tabla_maestra sl ON sl.IdMaestro = 49 AND sl.IdEmpresa = 1
                          AND sl.String1 = 'expediente' AND sl.String2 = e.etapa_actual
SET e.area_responsable = IFNULL(e.area_responsable, et.String3),
    e.fecha_etapa      = IFNULL(e.fecha_etapa,
                                (SELECT MAX(oc.fecha_liberacion) FROM orden_compra oc
                                 WHERE oc.id_oc = e.id_orden_compra OR oc.id_propuesta = e.id_propuesta)),
    e.sla_horas        = IFNULL(e.sla_horas, CAST(sl.Num2 AS SIGNED))
WHERE e.etapa_actual NOT IN ('requerimiento', 'propuesta', 'visto_bueno', 'orden_compra', 'cerrado');

UPDATE expediente_digital
SET fecha_etapa      = IFNULL(fecha_etapa, IFNULL(modificado_en, fecha_creacion)),
    fecha_limite_sla = IFNULL(fecha_limite_sla, IFNULL(fecha_etapa, IFNULL(modificado_en, fecha_creacion)) + INTERVAL IFNULL(sla_horas, 0) HOUR)
WHERE etapa_actual NOT IN ('requerimiento', 'propuesta', 'visto_bueno', 'orden_compra', 'cerrado');

INSERT INTO expediente_etapa (id_expediente, etapa, area, id_responsable, fecha_inicio, sla_horas, fecha_limite,
                              resultado, comentario, UsuCre, FchCre)
SELECT e.id_expediente, e.etapa_actual, e.area_responsable, e.id_responsable_actual, e.fecha_etapa,
       e.sla_horas, e.fecha_limite_sla, 'en_curso', 'Etapa registrada al crear el módulo de expedientes.',
       'migracion_71', NOW()
FROM expediente_digital e
WHERE e.etapa_actual NOT IN ('requerimiento', 'propuesta', 'visto_bueno', 'orden_compra', 'cerrado')
  AND e.eliminado_en IS NULL
  AND NOT EXISTS (SELECT 1 FROM expediente_etapa x WHERE x.id_expediente = e.id_expediente AND x.SoftDelete = 0);

-- 7.4 Bloqueos que dejaron las OC observadas: se vinculan a la OC por su número
UPDATE expediente_bloqueador b
JOIN expediente_digital e ON e.id_expediente = b.id_expediente
JOIN orden_compra oc ON oc.eliminado_en IS NULL
                    AND b.descripcion LIKE CONCAT('OC ', oc.numero_oc, ' observada%')
                    AND (oc.id_propuesta = e.id_propuesta OR oc.id_oc = e.id_orden_compra
                         OR oc.id_propuesta IN (SELECT p.id_propuesta FROM propuesta_comercial p
                                                WHERE p.id_requerimiento = e.id_requerimiento))
SET b.origen_tipo = 'orden_compra', b.id_origen = oc.id_oc, b.clase = 'bloqueo',
    b.etapa = IFNULL(b.etapa, 'orden_compra'),
    b.impacto = IFNULL(b.impacto, 'No se puede liberar el expediente a programación hasta corregir y revalidar la OC.')
WHERE b.origen_tipo IS NULL;

-- 7.5 Requisitos pendientes con los que se liberó a programación: son excepciones, no bloqueos
UPDATE expediente_bloqueador
SET clase = 'excepcion', origen_tipo = 'liberacion', etapa = IFNULL(etapa, 'programacion'), critico = 0,
    tipo_documental = IFNULL(tipo_documental, 'Seguridad y Salud (SSOMA)'),
    impacto = IFNULL(impacto, 'Debe completarse antes de la salida a campo.')
WHERE origen_tipo IS NULL AND tipo = 'ssoma';
