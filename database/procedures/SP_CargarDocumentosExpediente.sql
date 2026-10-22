-- Expediente Digital (interno, HU-31): repositorio integrado de documentos del expediente.
-- Llena tmp_exp_doc (el que llama hace DROP TEMPORARY TABLE tmp_exp_doc) con los documentos que el usuario puede ver:
--   comerciales  adjuntos del RQ, PDF de cada versión de la propuesta (se genera al descargar), evidencias del
--                seguimiento comercial y PDF de las órdenes de compra (todas sus versiones)
--   internos     documentos adjuntados al expediente (HU-31), con su tipo, etapa y visibilidad
--   ssoma        documentos SSOMA del personal de las OS
--   operativos   adjuntos de las OS / OM y certificados de metrología
-- Clave (para descargar): prop-<id_propuesta>, seg-<id_adjunto>, doc-<id_documento>, ocpdf-<id_oc>, ssoma-<id>, om-<id_om>.
-- Visibilidad de los documentos internos (VISIBILIDAD_DOCUMENTO 35): 1 interno y 5 cliente los ven todos, 2-4 solo
--   el área indicada, quien lo subió y Gerencia/TI.
-- estado: COMPLETO, APROBADO, VALIDADO, EN REVISIÓN, PENDIENTE, OBSERVADO, CARGADO, VENCIDO, RECHAZADO, ANULADO, HISTÓRICO
DROP PROCEDURE IF EXISTS SP_CargarDocumentosExpediente;

DELIMITER $$

CREATE PROCEDURE SP_CargarDocumentosExpediente(
    IN p_id_usuario    BIGINT,
    IN p_id_expediente BIGINT
)
BEGIN
    DECLARE v_id_rq BIGINT;
    DECLARE v_area  VARCHAR(60) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_todo  TINYINT DEFAULT 0;

    SELECT id_requerimiento INTO v_id_rq FROM expediente_digital WHERE id_expediente = p_id_expediente;
    SELECT area INTO v_area FROM usuario WHERE id_usuario = p_id_usuario;
    SET v_todo = IF(v_area IN ('gerencia', 'ti'), 1, 0);

    DROP TEMPORARY TABLE IF EXISTS tmp_exp_props;
    CREATE TEMPORARY TABLE tmp_exp_props (id_propuesta BIGINT PRIMARY KEY);
    INSERT IGNORE INTO tmp_exp_props
    SELECT p.id_propuesta FROM propuesta_comercial p
    WHERE v_id_rq IS NOT NULL AND p.id_requerimiento = v_id_rq AND p.eliminado_en IS NULL
    UNION
    SELECT e.id_propuesta FROM expediente_digital e WHERE e.id_expediente = p_id_expediente AND e.id_propuesta IS NOT NULL;

    DROP TEMPORARY TABLE IF EXISTS tmp_exp_ocs;
    CREATE TEMPORARY TABLE tmp_exp_ocs (id_oc BIGINT PRIMARY KEY);
    INSERT IGNORE INTO tmp_exp_ocs
    SELECT oc.id_oc FROM orden_compra oc JOIN tmp_exp_props t ON t.id_propuesta = oc.id_propuesta WHERE oc.eliminado_en IS NULL;
    INSERT IGNORE INTO tmp_exp_ocs
    SELECT op.id_oc FROM oc_propuesta op JOIN tmp_exp_props t ON t.id_propuesta = op.id_propuesta WHERE op.eliminado_en IS NULL;

    DROP TEMPORARY TABLE IF EXISTS tmp_exp_doc;
    CREATE TEMPORARY TABLE tmp_exp_doc (
        clave          VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        nombre         VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        nombre_archivo VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        tipo           VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        categoria      VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        origen         VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        etapa          VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        version        INT,
        estado         VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        fecha          DATETIME,
        id_usuario     BIGINT,
        tamano_bytes   BIGINT,
        tipo_contenido VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        descripcion    VARCHAR(1000) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        visibilidad    VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        es_interno     TINYINT,
        ruta           VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        id_propuesta   BIGINT
    );

    -- Adjuntos del RQ
    INSERT INTO tmp_exp_doc
    SELECT CONCAT('doc-', d.id_documento), d.nombre_archivo, d.nombre_archivo, IFNULL(td.String1, 'Adjunto del requerimiento'),
           'comerciales', 'CRM', 'requerimiento', d.version, 'COMPLETO', d.fecha_carga, d.subido_por,
           CAST(NULLIF(JSON_UNQUOTE(JSON_EXTRACT(d.metadatos, '$.tamano_bytes')), 'null') AS SIGNED), NULL, NULL, NULL, 0,
           d.url_archivo, NULL
    FROM documento_adjunto d
    LEFT JOIN tabla_maestra td ON td.IdMaestro = 96 AND td.IdEmpresa = 1 AND td.Num1 = d.id_tipo_documento
    WHERE d.entidad_tipo = 'requerimiento' AND d.id_entidad = v_id_rq AND d.eliminado_en IS NULL;

    -- Propuestas (PDF generado en cada descarga)
    INSERT INTO tmp_exp_doc
    SELECT CONCAT('prop-', p.id_propuesta), CONCAT(p.numero, '-v', p.version, '.pdf'), CONCAT(p.numero, '-v', p.version, '.pdf'),
           'Propuesta', 'comerciales', 'CRM', 'propuesta', p.version,
           CASE
               WHEN p.estado = 'anulado'                                                   THEN 'ANULADO'
               WHEN EXISTS (SELECT 1 FROM propuesta_comercial p2
                            WHERE p2.numero = p.numero AND p2.version > p.version AND p2.eliminado_en IS NULL) THEN 'HISTÓRICO'
               WHEN p.estado = 'aceptado'                                                   THEN 'ACEPTADO'
               WHEN p.estado IN ('aprobado', 'enviado')                                     THEN 'APROBADO'
               WHEN p.estado IN ('pendiente_vb', 'pendiente_revocacion')                    THEN 'EN REVISIÓN'
               WHEN p.estado = 'rechazado'                                                  THEN 'RECHAZADO'
               WHEN p.estado = 'borrador'                                                   THEN 'PENDIENTE'
               ELSE UPPER(REPLACE(p.estado, '_', ' '))
           END,
           p.fecha_creacion, p.id_creador, NULL, 'application/pdf', p.descripcion_cambios, NULL, 0, NULL, p.id_propuesta
    FROM propuesta_comercial p
    WHERE p.id_propuesta IN (SELECT id_propuesta FROM tmp_exp_props) AND p.eliminado_en IS NULL;

    -- Evidencias del seguimiento comercial (aceptación del cliente, correos)
    INSERT INTO tmp_exp_doc
    SELECT CONCAT('seg-', a.id_adjunto), a.nombre_archivo, a.nombre_archivo, 'Evidencia de seguimiento comercial',
           'comerciales', 'CRM', 'orden_compra', 1, 'CARGADO', a.creado_en, a.creado_por, a.tamano_bytes,
           a.tipo_contenido, NULL, NULL, 0, a.ruta, NULL
    FROM seguimiento_adjunto a
    JOIN seguimiento_comercial s ON s.id_seguimiento = a.id_seguimiento AND s.eliminado_en IS NULL
    WHERE s.id_propuesta IN (SELECT id_propuesta FROM tmp_exp_props) AND a.eliminado_en IS NULL;

    -- PDF de las órdenes de compra (el vigente y los reemplazados, que quedan como HISTÓRICO)
    INSERT INTO tmp_exp_doc
    SELECT CONCAT('doc-', d.id_documento), CONCAT('OC-', oc.numero_oc, '.pdf'), d.nombre_archivo,
           IF(oc.es_autogenerada = 1, 'Orden de Compra provisional', 'Orden de Compra'),
           'comerciales', 'CRM', 'orden_compra', d.version,
           CASE
               WHEN d.version < (SELECT MAX(d2.version) FROM documento_adjunto d2
                                 WHERE d2.entidad_tipo = 'orden_compra' AND d2.id_entidad = oc.id_oc AND d2.eliminado_en IS NULL) THEN 'HISTÓRICO'
               WHEN oc.estado = 'anulada'                                   THEN 'ANULADO'
               WHEN oc.estado = 'observada'                                 THEN 'OBSERVADO'
               WHEN oc.estado = 'validada_parcial'                          THEN 'VALIDADO PARCIAL'
               WHEN oc.reemplazada_por IS NOT NULL                          THEN 'REEMPLAZADO'
               WHEN oc.estado = 'pendiente_reemplazo'                       THEN 'PENDIENTE CORRECCIÓN'
               WHEN oc.estado = 'autogenerada'                              THEN 'PENDIENTE'
               ELSE 'VALIDADO'
           END,
           d.fecha_carga, d.subido_por,
           CAST(NULLIF(JSON_UNQUOTE(JSON_EXTRACT(d.metadatos, '$.tamano_bytes')), 'null') AS SIGNED), 'application/pdf',
           NULLIF(JSON_UNQUOTE(JSON_EXTRACT(d.metadatos, '$.motivo')), 'null'), NULL, 0, d.url_archivo, NULL
    FROM documento_adjunto d
    JOIN orden_compra oc ON oc.id_oc = d.id_entidad
    WHERE d.entidad_tipo = 'orden_compra' AND d.eliminado_en IS NULL AND d.id_entidad IN (SELECT id_oc FROM tmp_exp_ocs);

    -- OC antiguas con PDF pero sin versiones registradas
    INSERT INTO tmp_exp_doc
    SELECT CONCAT('ocpdf-', oc.id_oc), CONCAT('OC-', oc.numero_oc, '.pdf'), IFNULL(oc.nombre_archivo_pdf, CONCAT('OC-', oc.numero_oc, '.pdf')),
           'Orden de Compra', 'comerciales', 'CRM', 'orden_compra', 1,
           CASE oc.estado WHEN 'anulada' THEN 'ANULADO' WHEN 'observada' THEN 'OBSERVADO'
                          WHEN 'validada_parcial' THEN 'VALIDADO PARCIAL' WHEN 'autogenerada' THEN 'PENDIENTE'
                          WHEN 'pendiente_reemplazo' THEN 'PENDIENTE CORRECCIÓN' ELSE 'VALIDADO' END,
           oc.fecha_registro, oc.creado_por, oc.tamano_pdf_bytes, 'application/pdf', NULL, NULL, 0, oc.url_archivo_pdf, NULL
    FROM orden_compra oc
    WHERE oc.id_oc IN (SELECT id_oc FROM tmp_exp_ocs) AND oc.url_archivo_pdf IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM documento_adjunto d
                      WHERE d.entidad_tipo = 'orden_compra' AND d.id_entidad = oc.id_oc AND d.eliminado_en IS NULL);

    -- Documentos internos del expediente
    INSERT INTO tmp_exp_doc
    SELECT CONCAT('doc-', d.id_documento),
           COALESCE(NULLIF(JSON_UNQUOTE(JSON_EXTRACT(d.metadatos, '$.nombre_documento')), 'null'), d.nombre_archivo),
           d.nombre_archivo, IFNULL(td.String1, 'Documento interno'), IFNULL(td.String3, 'operativos'), 'Interno',
           NULLIF(JSON_UNQUOTE(JSON_EXTRACT(d.metadatos, '$.etapa')), 'null'), d.version, 'CARGADO', d.fecha_carga, d.subido_por,
           CAST(NULLIF(JSON_UNQUOTE(JSON_EXTRACT(d.metadatos, '$.tamano_bytes')), 'null') AS SIGNED),
           NULLIF(JSON_UNQUOTE(JSON_EXTRACT(d.metadatos, '$.tipo_contenido')), 'null'),
           NULLIF(JSON_UNQUOTE(JSON_EXTRACT(d.metadatos, '$.descripcion')), 'null'),
           vis.String1, 1, d.url_archivo, NULL
    FROM documento_adjunto d
    LEFT JOIN tabla_maestra td  ON td.IdMaestro = 96 AND td.IdEmpresa = 1 AND td.Num1 = d.id_tipo_documento
    LEFT JOIN tabla_maestra vis ON vis.IdMaestro = 35 AND vis.IdEmpresa = 1 AND vis.Num1 = d.id_visibilidad
    WHERE d.entidad_tipo = 'expediente' AND d.id_entidad = p_id_expediente AND d.eliminado_en IS NULL
      AND (v_todo = 1 OR d.id_visibilidad IN (1, 5) OR d.subido_por = p_id_usuario
           OR LOWER(IFNULL(vis.String2, '')) = IFNULL(v_area, ''));

    -- Documentos SSOMA del personal de las OS
    INSERT INTO tmp_exp_doc
    SELECT CONCAT('ssoma-', sd.id_ssoma_doc),
           CONCAT(IFNULL(t36.String1, 'Documento SSOMA'), ' - ', IFNULL(CONCAT(u.nombre, ' ', u.apellido), '')),
           SUBSTRING_INDEX(sd.url_archivo, '/', -1), IFNULL(t36.String1, 'Documento SSOMA'), 'ssoma', 'SSOMA', 'ssoma', sd.version,
           CASE
               WHEN sd.estado = 'vencido' OR (sd.fecha_vencimiento IS NOT NULL AND sd.fecha_vencimiento < CURDATE()) THEN 'VENCIDO'
               WHEN sd.estado = 'aprobado'  THEN 'APROBADO'
               WHEN sd.estado = 'observado' THEN 'OBSERVADO'
               WHEN sd.estado = 'cargado'   THEN 'CARGADO'
               ELSE 'PENDIENTE'
           END,
           sd.fecha_carga, IFNULL(sd.creado_por, sd.id_usuario), NULL, NULL,
           IF(sd.fecha_vencimiento IS NULL, NULL, CONCAT('Vence el ', DATE_FORMAT(sd.fecha_vencimiento, '%d/%m/%Y'))),
           NULL, 0, sd.url_archivo, NULL
    FROM ssoma_documento sd
    JOIN orden_servicio os ON os.id_os = sd.id_os AND os.eliminado_en IS NULL
    LEFT JOIN tabla_maestra t36 ON t36.IdMaestro = 36 AND t36.IdEmpresa = 1 AND t36.Num1 = sd.id_requisito
    LEFT JOIN usuario u ON u.id_usuario = sd.id_usuario
    WHERE os.id_expediente = p_id_expediente AND sd.eliminado_en IS NULL;

    -- Adjuntos de las OS y OM
    INSERT INTO tmp_exp_doc
    SELECT CONCAT('doc-', d.id_documento), d.nombre_archivo, d.nombre_archivo, IFNULL(td.String1, 'Documento operativo'),
           IFNULL(td.String3, IF(d.entidad_tipo = 'orden_metrologia', 'metrologia', 'operativos')),
           IF(d.entidad_tipo = 'orden_metrologia', 'Metrología', 'Operaciones'),
           IF(d.entidad_tipo = 'orden_metrologia', 'ejecucion', 'programacion'), d.version, 'CARGADO', d.fecha_carga, d.subido_por,
           CAST(NULLIF(JSON_UNQUOTE(JSON_EXTRACT(d.metadatos, '$.tamano_bytes')), 'null') AS SIGNED), NULL, NULL, NULL, 0,
           d.url_archivo, NULL
    FROM documento_adjunto d
    LEFT JOIN tabla_maestra td ON td.IdMaestro = 96 AND td.IdEmpresa = 1 AND td.Num1 = d.id_tipo_documento
    WHERE d.eliminado_en IS NULL
      AND ((d.entidad_tipo = 'orden_servicio'
            AND d.id_entidad IN (SELECT os.id_os FROM orden_servicio os WHERE os.id_expediente = p_id_expediente AND os.eliminado_en IS NULL))
        OR (d.entidad_tipo = 'orden_metrologia'
            AND d.id_entidad IN (SELECT om.id_om FROM orden_metrologia om WHERE om.id_expediente = p_id_expediente AND om.eliminado_en IS NULL)));

    -- Certificados de metrología
    INSERT INTO tmp_exp_doc
    SELECT CONCAT('om-', om.id_om), CONCAT('Certificado ', IFNULL(om.numero_certificado, om.numero), '.pdf'),
           CONCAT('Certificado-', IFNULL(om.numero_certificado, om.numero), '.pdf'), 'Certificado de calibración',
           'metrologia', 'Metrología', 'ejecucion', 1, IF(om.estado = 'anulada', 'ANULADO', 'COMPLETO'),
           IFNULL(om.fecha_emision_certificado, om.fecha_creacion), om.id_metrologo, NULL, 'application/pdf', NULL, NULL, 0,
           om.url_certificado_pdf, NULL
    FROM orden_metrologia om
    WHERE om.id_expediente = p_id_expediente AND om.eliminado_en IS NULL AND om.url_certificado_pdf IS NOT NULL;

    DROP TEMPORARY TABLE IF EXISTS tmp_exp_ocs;
    DROP TEMPORARY TABLE IF EXISTS tmp_exp_props;
END$$

DELIMITER ;
