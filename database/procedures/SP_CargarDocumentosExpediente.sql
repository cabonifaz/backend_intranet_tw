-- Expediente Digital (interno, HU-31): repositorio consolidado de documentos del expediente (solo lectura).
-- Llena tmp_exp_doc (el que llama hace DROP TEMPORARY TABLE tmp_exp_doc) con los documentos que el usuario puede ver,
-- en las 4 categorías (pestañas) del refinamiento y con su origen "Módulo — Etapa":
--   comerciales  adjuntos del RQ (RQ — Adjunto cliente), PDF de cada versión de la propuesta (Propuesta — Elaboración /
--                Propuesta — VB; se genera al descargar), evidencias del seguimiento (Seguimiento — Comunicación /
--                Aceptación / Rechazo) y correos de seguimiento enviados (Seguimiento — Correo, se descargan como .eml)
--   operativos   PDF de las OC recibidas del cliente (OC — Recibida / OC — Corrección) y adjuntos de las OS (OS — Generada)
--   ssoma        documentos SSOMA del personal de las OS (SSOMA — Habilitación / SSOMA — Inducción)
--   tecnicos     informes técnicos y evidencias de ejecución, certificados y adjuntos de metrología
-- Los documentos internos adjuntados al expediente antes del refinamiento se siguen listando con su visibilidad
-- (VISIBILIDAD_DOCUMENTO 35: 1 interno y 5 cliente los ven todos; 2-4 solo el área, quien lo subió y Gerencia/TI).
-- Clave (para ver o descargar): doc-<id>, prop-<id_propuesta>, seg-<id_adjunto>, mail-<id_correo>, ocpdf-<id_oc>,
--   ssoma-<id>, om-<id_om>, inf-<id_informe>, evi-<id_evidencia>.
-- formato: PDF, XLSX, DOCX, EML, JPG, PNG u OTRO (por la extensión del archivo).
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
    SELECT op.id_oc FROM oc_propuesta op JOIN orden_compra oc ON oc.id_oc = op.id_oc AND oc.eliminado_en IS NULL
    JOIN tmp_exp_props t ON t.id_propuesta = op.id_propuesta WHERE op.eliminado_en IS NULL;

    DROP TEMPORARY TABLE IF EXISTS tmp_exp_doc;
    CREATE TEMPORARY TABLE tmp_exp_doc (
        clave          VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        nombre         VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        nombre_archivo VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        tipo           VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        categoria      VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        modulo         VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        etapa_origen   VARCHAR(60)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        etapa          VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        version        INT,
        estado         VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        fecha          DATETIME,
        id_usuario     BIGINT,
        tamano_bytes   BIGINT,
        tipo_contenido VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        descripcion    VARCHAR(1000) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        visibilidad    VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        es_interno     TINYINT,
        ruta           VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        id_propuesta   BIGINT,
        id_correo      BIGINT
    );

    -- Adjuntos del RQ
    INSERT INTO tmp_exp_doc
    SELECT CONCAT('doc-', d.id_documento), d.nombre_archivo, d.nombre_archivo, IFNULL(td.String1, 'Adjunto del requerimiento'),
           'comerciales', 'RQ', 'Adjunto cliente', 'requerimiento', d.version, 'COMPLETO', d.fecha_carga, d.subido_por,
           CAST(NULLIF(JSON_UNQUOTE(JSON_EXTRACT(d.metadatos, '$.tamano_bytes')), 'null') AS SIGNED), NULL, NULL, NULL, 0,
           d.url_archivo, NULL, NULL
    FROM documento_adjunto d
    LEFT JOIN tabla_maestra td ON td.IdMaestro = 96 AND td.IdEmpresa = 1 AND td.Num1 = d.id_tipo_documento
    WHERE d.entidad_tipo = 'requerimiento' AND d.id_entidad = v_id_rq AND d.eliminado_en IS NULL;

    -- Propuestas (PDF generado en cada descarga), una por versión
    INSERT INTO tmp_exp_doc
    SELECT CONCAT('prop-', p.id_propuesta), CONCAT(p.numero, '-v', p.version, '.pdf'), CONCAT(p.numero, '-v', p.version, '.pdf'),
           'Propuesta', 'comerciales', 'Propuesta',
           IF(p.estado IN ('aprobado', 'enviado', 'aceptado')
              OR EXISTS (SELECT 1 FROM visto_bueno v WHERE v.id_propuesta = p.id_propuesta AND v.tipo = 'aprobacion'
                           AND v.estado = 'aprobado' AND v.eliminado_en IS NULL), 'VB', 'Elaboración'),
           'propuesta', p.version,
           CASE
               WHEN p.estado = 'anulado'                                                   THEN 'ANULADO'
               WHEN EXISTS (SELECT 1 FROM propuesta_comercial p2
                            WHERE p2.numero = p.numero AND p2.version > p.version AND p2.eliminado_en IS NULL) THEN 'HISTÓRICO'
               WHEN p.estado = 'aceptado'                                                   THEN 'ACEPTADO'
               WHEN p.estado IN ('aprobado', 'enviado')                                     THEN 'APROBADO'
               WHEN p.estado IN ('pendiente_vb', 'pendiente_revocacion')                    THEN 'EN REVISIÓN'
               WHEN p.estado = 'rechazado'                                                  THEN 'RECHAZADO'
               WHEN p.estado = 'borrador'                                                   THEN 'BORRADOR'
               ELSE UPPER(REPLACE(p.estado, '_', ' '))
           END,
           p.fecha_creacion, COALESCE(p.id_responsable, p.id_creador), NULL, 'application/pdf', p.descripcion_cambios, NULL, 0,
           NULL, p.id_propuesta, NULL
    FROM propuesta_comercial p
    WHERE p.id_propuesta IN (SELECT id_propuesta FROM tmp_exp_props) AND p.eliminado_en IS NULL;

    -- Evidencias del seguimiento comercial (comunicaciones, aceptación o rechazo del cliente)
    INSERT INTO tmp_exp_doc
    SELECT CONCAT('seg-', a.id_adjunto), a.nombre_archivo, a.nombre_archivo,
           CASE s.estado WHEN 'cerrado_aceptacion' THEN 'Evidencia de aceptación'
                         WHEN 'cerrado_rechazo' THEN 'Evidencia de rechazo' ELSE 'Comunicación con el cliente' END,
           'comerciales', 'Seguimiento',
           CASE s.estado WHEN 'cerrado_aceptacion' THEN 'Aceptación' WHEN 'cerrado_rechazo' THEN 'Rechazo' ELSE 'Comunicación' END,
           'seguimiento', 1, 'CARGADO', a.creado_en, a.creado_por, a.tamano_bytes, a.tipo_contenido,
           NULLIF(TRIM(IFNULL(s.asunto, '')), ''), NULL, 0, a.ruta, NULL, NULL
    FROM seguimiento_adjunto a
    JOIN seguimiento_comercial s ON s.id_seguimiento = a.id_seguimiento AND s.eliminado_en IS NULL
    WHERE s.id_propuesta IN (SELECT id_propuesta FROM tmp_exp_props) AND a.eliminado_en IS NULL;

    -- Correos de seguimiento enviados (se descargan como .eml)
    INSERT INTO tmp_exp_doc
    SELECT CONCAT('mail-', sc.id_correo),
           LEFT(CONCAT('Correo: ', IFNULL(NULLIF(TRIM(sc.asunto), ''), '(sin asunto)')), 300),
           CONCAT('correo_seguimiento_', sc.id_correo, '.eml'), 'Correo de seguimiento',
           'comerciales', 'Seguimiento', 'Correo', 'seguimiento', 1, 'ENVIADO', IFNULL(sc.fecha_envio, sc.creado_en), sc.id_usuario,
           CHAR_LENGTH(IFNULL(sc.cuerpo_html, '')), 'message/rfc822',
           LEFT(CONCAT('Para: ', IFNULL(JSON_UNQUOTE(sc.para), '')), 1000), NULL, 0, NULL, NULL, sc.id_correo
    FROM seguimiento_correo sc
    WHERE sc.id_propuesta IN (SELECT id_propuesta FROM tmp_exp_props) AND sc.eliminado_en IS NULL AND sc.estado = 'enviado';

    -- PDF de las órdenes de compra recibidas del cliente (el vigente y los reemplazados, que quedan como HISTÓRICO)
    INSERT INTO tmp_exp_doc
    SELECT CONCAT('doc-', d.id_documento), CONCAT('OC-', oc.numero_oc, IF(d.version > 1, CONCAT('-v', d.version), ''), '.pdf'),
           d.nombre_archivo, 'Orden de Compra',
           'operativos', 'OC', IF(d.version > 1, 'Corrección', 'Recibida'), 'orden_compra', d.version,
           CASE
               WHEN d.version < (SELECT MAX(d2.version) FROM documento_adjunto d2
                                 WHERE d2.entidad_tipo = 'orden_compra' AND d2.id_entidad = oc.id_oc AND d2.eliminado_en IS NULL) THEN 'HISTÓRICO'
               WHEN oc.estado = 'anulada'                                   THEN 'ANULADO'
               WHEN oc.reemplazada_por IS NOT NULL                          THEN 'REEMPLAZADO'
               WHEN oc.estado = 'observada'                                 THEN 'OBSERVADO'
               WHEN oc.estado = 'validada_parcial'                          THEN 'VALIDADO PARCIAL'
               WHEN oc.estado = 'pendiente_reemplazo'                       THEN 'PENDIENTE CORRECCIÓN'
               WHEN oc.estado = 'autogenerada'                              THEN 'PENDIENTE'
               ELSE 'VALIDADO'
           END,
           d.fecha_carga, d.subido_por,
           CAST(NULLIF(JSON_UNQUOTE(JSON_EXTRACT(d.metadatos, '$.tamano_bytes')), 'null') AS SIGNED), 'application/pdf',
           NULLIF(JSON_UNQUOTE(JSON_EXTRACT(d.metadatos, '$.motivo')), 'null'), NULL, 0, d.url_archivo, NULL, NULL
    FROM documento_adjunto d
    JOIN orden_compra oc ON oc.id_oc = d.id_entidad
    WHERE d.entidad_tipo = 'orden_compra' AND d.eliminado_en IS NULL AND d.id_entidad IN (SELECT id_oc FROM tmp_exp_ocs);

    -- OC antiguas con PDF pero sin versiones registradas
    INSERT INTO tmp_exp_doc
    SELECT CONCAT('ocpdf-', oc.id_oc), CONCAT('OC-', oc.numero_oc, '.pdf'), IFNULL(oc.nombre_archivo_pdf, CONCAT('OC-', oc.numero_oc, '.pdf')),
           'Orden de Compra', 'operativos', 'OC', 'Recibida', 'orden_compra', 1,
           CASE WHEN oc.estado = 'anulada' THEN 'ANULADO' WHEN oc.reemplazada_por IS NOT NULL THEN 'REEMPLAZADO'
                WHEN oc.estado = 'observada' THEN 'OBSERVADO' WHEN oc.estado = 'validada_parcial' THEN 'VALIDADO PARCIAL'
                WHEN oc.estado = 'autogenerada' THEN 'PENDIENTE' WHEN oc.estado = 'pendiente_reemplazo' THEN 'PENDIENTE CORRECCIÓN'
                ELSE 'VALIDADO' END,
           oc.fecha_registro, oc.creado_por, oc.tamano_pdf_bytes, 'application/pdf', NULL, NULL, 0, oc.url_archivo_pdf, NULL, NULL
    FROM orden_compra oc
    WHERE oc.id_oc IN (SELECT id_oc FROM tmp_exp_ocs) AND oc.url_archivo_pdf IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM documento_adjunto d
                      WHERE d.entidad_tipo = 'orden_compra' AND d.id_entidad = oc.id_oc AND d.eliminado_en IS NULL);

    -- Documentos internos adjuntados al expediente antes del refinamiento (con su visibilidad)
    INSERT INTO tmp_exp_doc
    SELECT CONCAT('doc-', d.id_documento),
           COALESCE(NULLIF(JSON_UNQUOTE(JSON_EXTRACT(d.metadatos, '$.nombre_documento')), 'null'), d.nombre_archivo),
           d.nombre_archivo, IFNULL(td.String1, 'Documento interno'),
           CASE IFNULL(td.String3, 'operativos') WHEN 'metrologia' THEN 'tecnicos' WHEN 'conformidad' THEN 'tecnicos'
                                                 WHEN 'facturacion' THEN 'operativos' ELSE IFNULL(td.String3, 'operativos') END,
           'Expediente', IFNULL(et.String1, 'Interno'),
           NULLIF(JSON_UNQUOTE(JSON_EXTRACT(d.metadatos, '$.etapa')), 'null'), d.version, 'CARGADO', d.fecha_carga, d.subido_por,
           CAST(NULLIF(JSON_UNQUOTE(JSON_EXTRACT(d.metadatos, '$.tamano_bytes')), 'null') AS SIGNED),
           NULLIF(JSON_UNQUOTE(JSON_EXTRACT(d.metadatos, '$.tipo_contenido')), 'null'),
           NULLIF(JSON_UNQUOTE(JSON_EXTRACT(d.metadatos, '$.descripcion')), 'null'),
           vis.String1, 1, d.url_archivo, NULL, NULL
    FROM documento_adjunto d
    LEFT JOIN tabla_maestra td  ON td.IdMaestro = 96 AND td.IdEmpresa = 1 AND td.Num1 = d.id_tipo_documento
    LEFT JOIN tabla_maestra vis ON vis.IdMaestro = 35 AND vis.IdEmpresa = 1 AND vis.Num1 = d.id_visibilidad
    LEFT JOIN tabla_maestra et  ON et.IdMaestro = 97 AND et.IdEmpresa = 1
                               AND et.String2 = NULLIF(JSON_UNQUOTE(JSON_EXTRACT(d.metadatos, '$.etapa')), 'null')
    WHERE d.entidad_tipo = 'expediente' AND d.id_entidad = p_id_expediente AND d.eliminado_en IS NULL
      AND (v_todo = 1 OR d.id_visibilidad IN (1, 5) OR d.subido_por = p_id_usuario
           OR LOWER(IFNULL(vis.String2, '')) = IFNULL(v_area, ''));

    -- Documentos SSOMA del personal de las OS
    INSERT INTO tmp_exp_doc
    SELECT CONCAT('ssoma-', sd.id_ssoma_doc),
           CONCAT(IFNULL(t36.String1, 'Documento SSOMA'), ' - ', IFNULL(CONCAT(u.nombre, ' ', u.apellido), '')),
           SUBSTRING_INDEX(sd.url_archivo, '/', -1), IFNULL(t36.String1, 'Documento SSOMA'), 'ssoma', 'SSOMA',
           IF(LOWER(IFNULL(t36.String1, '')) LIKE '%induc%', 'Inducción', 'Habilitación'), 'ssoma', sd.version,
           CASE
               WHEN sd.estado = 'vencido' OR (sd.fecha_vencimiento IS NOT NULL AND sd.fecha_vencimiento < CURDATE()) THEN 'VENCIDO'
               WHEN sd.estado = 'aprobado'  THEN 'APROBADO'
               WHEN sd.estado = 'observado' THEN 'OBSERVADO'
               WHEN sd.estado = 'cargado'   THEN 'CARGADO'
               ELSE 'PENDIENTE'
           END,
           sd.fecha_carga, IFNULL(sd.creado_por, sd.id_usuario), NULL, NULL,
           IF(sd.fecha_vencimiento IS NULL, NULL, CONCAT('Vence el ', DATE_FORMAT(sd.fecha_vencimiento, '%d/%m/%Y'))),
           NULL, 0, sd.url_archivo, NULL, NULL
    FROM ssoma_documento sd
    JOIN orden_servicio os ON os.id_os = sd.id_os AND os.eliminado_en IS NULL
    LEFT JOIN tabla_maestra t36 ON t36.IdMaestro = 36 AND t36.IdEmpresa = 1 AND t36.Num1 = sd.id_requisito
    LEFT JOIN usuario u ON u.id_usuario = sd.id_usuario
    WHERE os.id_expediente = p_id_expediente AND sd.eliminado_en IS NULL;

    -- Adjuntos de las OS (operativos) y OM (técnicos)
    INSERT INTO tmp_exp_doc
    SELECT CONCAT('doc-', d.id_documento), d.nombre_archivo, d.nombre_archivo,
           IFNULL(td.String1, IF(d.entidad_tipo = 'orden_metrologia', 'Documento de metrología', 'Orden de servicio')),
           IF(d.entidad_tipo = 'orden_metrologia', 'tecnicos', 'operativos'),
           IF(d.entidad_tipo = 'orden_metrologia', 'Metrología', 'OS'),
           IF(d.entidad_tipo = 'orden_metrologia', 'Orden', 'Generada'),
           IF(d.entidad_tipo = 'orden_metrologia', 'ejecucion', 'orden_servicio'), d.version, 'CARGADO', d.fecha_carga, d.subido_por,
           CAST(NULLIF(JSON_UNQUOTE(JSON_EXTRACT(d.metadatos, '$.tamano_bytes')), 'null') AS SIGNED), NULL, NULL, NULL, 0,
           d.url_archivo, NULL, NULL
    FROM documento_adjunto d
    LEFT JOIN tabla_maestra td ON td.IdMaestro = 96 AND td.IdEmpresa = 1 AND td.Num1 = d.id_tipo_documento
    WHERE d.eliminado_en IS NULL
      AND ((d.entidad_tipo = 'orden_servicio'
            AND d.id_entidad IN (SELECT os.id_os FROM orden_servicio os WHERE os.id_expediente = p_id_expediente AND os.eliminado_en IS NULL))
        OR (d.entidad_tipo = 'orden_metrologia'
            AND d.id_entidad IN (SELECT om.id_om FROM orden_metrologia om WHERE om.id_expediente = p_id_expediente AND om.eliminado_en IS NULL)));

    -- Informes técnicos (PDF)
    INSERT INTO tmp_exp_doc
    SELECT CONCAT('inf-', it.id_informe), CONCAT('Informe técnico ', it.numero, IF(it.version > 1, CONCAT(' v', it.version), ''), '.pdf'),
           CONCAT('Informe-', it.numero, IF(it.version > 1, CONCAT('-v', it.version), ''), '.pdf'), 'Informe técnico',
           'tecnicos', 'Ejecución', 'Informe técnico', 'cierre', it.version, UPPER(REPLACE(it.estado, '_', ' ')),
           it.fecha_creacion, it.id_tecnico, NULL, 'application/pdf', NULL, NULL, 0, it.url_pdf, NULL, NULL
    FROM informe_tecnico it
    JOIN orden_servicio os ON os.id_os = it.id_os AND os.eliminado_en IS NULL
    WHERE os.id_expediente = p_id_expediente AND it.eliminado_en IS NULL AND it.url_pdf IS NOT NULL;

    -- Evidencias fotográficas de la ejecución
    INSERT INTO tmp_exp_doc
    SELECT CONCAT('evi-', ev.id_evidencia), SUBSTRING_INDEX(ev.url_archivo, '/', -1), SUBSTRING_INDEX(ev.url_archivo, '/', -1),
           IFNULL(t30.String1, 'Evidencia fotográfica'), 'tecnicos', 'Ejecución', 'Evidencia', 'ejecucion', 1,
           CASE ev.validacion_ia WHEN 'aprobada' THEN 'VALIDADO' WHEN 'rechazada' THEN 'OBSERVADO' ELSE 'CARGADO' END,
           ev.timestamp_captura, ev.id_usuario, NULL, NULL, NULL, NULL, 0, ev.url_archivo, NULL, NULL
    FROM evidencia_fotografica ev
    JOIN orden_servicio os ON os.id_os = ev.id_os AND os.eliminado_en IS NULL
    LEFT JOIN tabla_maestra t30 ON t30.IdMaestro = 30 AND t30.IdEmpresa = 1 AND t30.Num1 = ev.id_tipo_evidencia
    WHERE os.id_expediente = p_id_expediente AND ev.eliminado_en IS NULL;

    -- Certificados de metrología
    INSERT INTO tmp_exp_doc
    SELECT CONCAT('om-', om.id_om), CONCAT('Certificado ', IFNULL(om.numero_certificado, om.numero), '.pdf'),
           CONCAT('Certificado-', IFNULL(om.numero_certificado, om.numero), '.pdf'), 'Certificado de calibración',
           'tecnicos', 'Metrología', 'Certificado', 'cierre', 1, IF(om.estado = 'anulada', 'ANULADO', 'COMPLETO'),
           IFNULL(om.fecha_emision_certificado, om.fecha_creacion), om.id_metrologo, NULL, 'application/pdf', NULL, NULL, 0,
           om.url_certificado_pdf, NULL, NULL
    FROM orden_metrologia om
    WHERE om.id_expediente = p_id_expediente AND om.eliminado_en IS NULL AND om.url_certificado_pdf IS NOT NULL;

    DROP TEMPORARY TABLE IF EXISTS tmp_exp_ocs;
    DROP TEMPORARY TABLE IF EXISTS tmp_exp_props;

    ALTER TABLE tmp_exp_doc
        ADD COLUMN origen  VARCHAR(110) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        ADD COLUMN formato VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL;

    UPDATE tmp_exp_doc SET
        origen  = CONCAT(modulo, ' — ', etapa_origen),
        formato = CASE LOWER(SUBSTRING_INDEX(IFNULL(nombre_archivo, ''), '.', -1))
                      WHEN 'pdf' THEN 'PDF' WHEN 'xlsx' THEN 'XLSX' WHEN 'xls' THEN 'XLSX' WHEN 'docx' THEN 'DOCX'
                      WHEN 'eml' THEN 'EML' WHEN 'msg' THEN 'EML' WHEN 'jpg' THEN 'JPG' WHEN 'jpeg' THEN 'JPG'
                      WHEN 'png' THEN 'PNG' ELSE 'OTRO' END;
END$$

DELIMITER ;
