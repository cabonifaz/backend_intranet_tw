-- Expediente Digital (interno, HU-30/32): timeline consolidado del expediente (solo lectura, inmutable).
-- Junta en tmp_exp_evt (el que llama hace DROP TEMPORARY TABLE tmp_exp_evt) los eventos de cada módulo origen, una sola
-- vez cada uno y con su origen identificado:
--   RQ            historial_requerimiento
--   Propuesta     auditoria_evento 'propuesta' (creación, versiones, envío a VB y al cliente, anulación)
--   Visto Bueno   respuestas del aprobador (visto_bueno); la misma respuesta en la auditoría de la propuesta no se repite
--   Seguimiento   interacciones, cierre con aceptación o rechazo (seguimiento_comercial) y correos enviados
--   OC            auditoria_evento 'orden_compra' (registro, decisión, reemplazo, anulación; el detalle fino queda en la OC)
--   OS            generación de la OS y confirmación del cliente (Programación)
--   Ejecución     eventos de campo e incidencias          Cierre   informe técnico y conformidad del cliente
--   Expediente    auditoria_evento 'expediente' (creación, paso a OS, reasignaciones consolidadas, exportaciones)
-- Los eventos de documentos internos antiguos respetan su visibilidad (solo el área indicada, quien lo subió y Gerencia/TI).
-- tipo_evento (ícono): creacion, requerimiento, propuesta, visto_bueno, seguimiento, orden_compra, orden_servicio,
--   programacion, ejecucion, cierre, bloqueo, reasignacion, documento, anulacion, otro.
DROP PROCEDURE IF EXISTS SP_CargarEventosExpediente;

DELIMITER $$

CREATE PROCEDURE SP_CargarEventosExpediente(
    IN p_id_usuario    BIGINT,
    IN p_id_expediente BIGINT
)
BEGIN
    DECLARE v_id_rq BIGINT;
    DECLARE v_area  VARCHAR(60) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    SELECT area INTO v_area FROM usuario WHERE id_usuario = p_id_usuario;
    SELECT id_requerimiento INTO v_id_rq FROM expediente_digital WHERE id_expediente = p_id_expediente;

    DROP TEMPORARY TABLE IF EXISTS tmp_exp_props;
    CREATE TEMPORARY TABLE tmp_exp_props (id_propuesta BIGINT PRIMARY KEY);
    INSERT IGNORE INTO tmp_exp_props
    SELECT p.id_propuesta FROM propuesta_comercial p WHERE v_id_rq IS NOT NULL AND p.id_requerimiento = v_id_rq
    UNION
    SELECT e.id_propuesta FROM expediente_digital e WHERE e.id_expediente = p_id_expediente AND e.id_propuesta IS NOT NULL;

    DROP TEMPORARY TABLE IF EXISTS tmp_exp_ocs;
    CREATE TEMPORARY TABLE tmp_exp_ocs (id_oc BIGINT PRIMARY KEY);
    INSERT IGNORE INTO tmp_exp_ocs
    SELECT oc.id_oc FROM orden_compra oc JOIN tmp_exp_props t ON t.id_propuesta = oc.id_propuesta;
    INSERT IGNORE INTO tmp_exp_ocs
    SELECT op.id_oc FROM oc_propuesta op JOIN tmp_exp_props t ON t.id_propuesta = op.id_propuesta;

    DROP TEMPORARY TABLE IF EXISTS tmp_exp_oss;
    CREATE TEMPORARY TABLE tmp_exp_oss (id_os BIGINT PRIMARY KEY, numero VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci);
    INSERT IGNORE INTO tmp_exp_oss
    SELECT os.id_os, os.numero FROM orden_servicio os WHERE os.id_expediente = p_id_expediente AND os.eliminado_en IS NULL;

    DROP TEMPORARY TABLE IF EXISTS tmp_exp_evt;
    CREATE TEMPORARY TABLE tmp_exp_evt (
        fecha        DATETIME,
        tipo_evento  VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        accion       VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        titulo       VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        descripcion  TEXT         CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        etapa        VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        id_usuario   BIGINT,
        entidad      VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        referencia   VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        urgente      TINYINT,
        origen       VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
    );

    -- 1. Expediente, propuestas y OC (auditoria_evento)
    INSERT INTO tmp_exp_evt
    SELECT a.registrado_en, NULL, a.accion, NULL, a.descripcion,
           CASE
               WHEN a.entidad_tipo = 'expediente' THEN
                   COALESCE(NULLIF(JSON_UNQUOTE(JSON_EXTRACT(a.metadata, '$.etapa')), 'null'),
                            IF(a.estado_nuevo IN ('requerimiento', 'propuesta', 'visto_bueno', 'seguimiento', 'orden_compra',
                                                  'orden_servicio', 'programacion', 'ssoma', 'ejecucion', 'cierre', 'cerrado'),
                               a.estado_nuevo, NULL))
               WHEN a.entidad_tipo = 'propuesta' AND a.accion IN ('envio_vb', 'solicitar_revocacion_vb') THEN 'visto_bueno'
               WHEN a.entidad_tipo = 'propuesta' AND a.accion IN ('envio_cliente', 'cambio_estado')      THEN 'seguimiento'
               WHEN a.entidad_tipo = 'propuesta'                                                         THEN 'propuesta'
               ELSE 'orden_compra'
           END,
           a.id_usuario, a.entidad_tipo,
           CASE a.entidad_tipo
               WHEN 'expediente'   THEN (SELECT e.numero FROM expediente_digital e WHERE e.id_expediente = a.id_entidad)
               WHEN 'propuesta'    THEN (SELECT CONCAT(p.numero, ' v', p.version) FROM propuesta_comercial p WHERE p.id_propuesta = a.id_entidad)
               WHEN 'orden_compra' THEN (SELECT CONCAT('OC ', oc.numero_oc) FROM orden_compra oc WHERE oc.id_oc = a.id_entidad)
           END,
           (a.accion IN ('observar_oc', 'registrar_bloqueo', 'anular_oc')
            OR (a.accion = 'decision_oc' AND a.estado_nuevo IN ('correccion_cliente', 'nueva_version'))),
           CASE a.entidad_tipo WHEN 'expediente' THEN 'Expediente' WHEN 'propuesta' THEN 'Propuestas' ELSE 'Órdenes de Compra' END
    FROM auditoria_evento a
    WHERE ((a.entidad_tipo = 'expediente' AND a.id_entidad = p_id_expediente
            AND (a.accion <> 'adjuntar_documento'
                 OR IFNULL(v_area, '') IN ('gerencia', 'ti')
                 OR a.id_usuario = p_id_usuario
                 OR IFNULL(CAST(JSON_UNQUOTE(JSON_EXTRACT(a.metadata, '$.id_visibilidad')) AS UNSIGNED), 1) IN (1, 5)
                 OR EXISTS (SELECT 1 FROM tabla_maestra v
                            WHERE v.IdMaestro = 35 AND v.IdEmpresa = 1 AND LOWER(v.String2) = IFNULL(v_area, '')
                              AND v.Num1 = CAST(JSON_UNQUOTE(JSON_EXTRACT(a.metadata, '$.id_visibilidad')) AS UNSIGNED))))
       OR (a.entidad_tipo = 'propuesta' AND a.id_entidad IN (SELECT id_propuesta FROM tmp_exp_props)
           -- la respuesta del VB sale de visto_bueno; la reasignación, del evento consolidado del expediente
           AND a.accion NOT LIKE 'vb\_%' AND a.accion NOT IN ('edicion', 'reasignar_responsable'))
       OR (a.entidad_tipo = 'orden_compra' AND a.id_entidad IN (SELECT id_oc FROM tmp_exp_ocs)
           -- El detalle fino de la OC (cada validación, extracción o corrección) queda en el timeline de la OC
           AND a.accion NOT IN ('exportar_auditoria_oc', 'validacion_ia', 'extraccion_ia', 'corregir_campo_oc',
                                'editar_vinculacion', 'cargar_pdf_oc', 'cambio_estado_oc', 'reasignar_responsable')));

    -- 2. RQ (historial propio del requerimiento)
    INSERT INTO tmp_exp_evt
    SELECT h.fecha, IF(h.tipo = 'creacion', 'creacion', 'requerimiento'), CONCAT('rq_', h.tipo), h.tipo_label,
           h.descripcion, 'requerimiento', h.creado_por, 'requerimiento',
           (SELECT r.numero FROM requerimiento r WHERE r.id_requerimiento = h.id_requerimiento), 0, 'Requerimientos'
    FROM historial_requerimiento h
    WHERE v_id_rq IS NOT NULL AND h.id_requerimiento = v_id_rq AND IFNULL(h.SoftDelete, 0) = 0
      AND h.tipo <> 'reasignacion';

    -- 3. Visto bueno: respuesta del aprobador y reasignación del aprobador
    INSERT INTO tmp_exp_evt
    SELECT v.fecha_respuesta, 'visto_bueno', CONCAT('vb_', v.estado),
           CASE v.estado WHEN 'aprobado' THEN 'Visto bueno aprobado'
                         WHEN 'rechazado' THEN 'Visto bueno rechazado'
                         WHEN 'devuelto' THEN 'Propuesta devuelta para ajuste'
                         WHEN 'reasignado' THEN 'Aprobador del visto bueno reasignado'
                         ELSE CONCAT('Visto bueno ', REPLACE(v.estado, '_', ' ')) END,
           NULLIF(TRIM(IFNULL(v.comentario_respuesta, '')), ''),
           'visto_bueno', IFNULL(v.resuelto_por, v.id_aprobador), 'visto_bueno',
           (SELECT CONCAT(p.numero, ' v', p.version) FROM propuesta_comercial p WHERE p.id_propuesta = v.id_propuesta),
           (v.estado IN ('rechazado', 'devuelto')), 'Visto Bueno'
    FROM visto_bueno v
    WHERE v.id_propuesta IN (SELECT id_propuesta FROM tmp_exp_props)
      AND v.fecha_respuesta IS NOT NULL AND v.eliminado_en IS NULL AND v.tipo = 'aprobacion';

    -- 4. Seguimiento comercial: interacciones y cierre
    INSERT INTO tmp_exp_evt
    SELECT IFNULL(s.fecha_interaccion, s.creado_en), 'seguimiento',
           CASE s.estado WHEN 'cerrado_aceptacion' THEN 'seguimiento_aceptacion'
                         WHEN 'cerrado_rechazo' THEN 'seguimiento_rechazo' ELSE 'seguimiento_interaccion' END,
           CASE s.estado WHEN 'cerrado_aceptacion' THEN 'Propuesta ACEPTADA por el cliente'
                         WHEN 'cerrado_rechazo' THEN 'Propuesta rechazada por el cliente'
                         ELSE CONCAT(IFNULL(c.String1, 'Interacción'), IFNULL(CONCAT(' · ', rs.String1), '')) END,
           LEFT(CONCAT_WS('. ', IF(s.estado = 'cerrado_aceptacion', ta.String1, NULL),
                          IF(s.estado = 'cerrado_rechazo', mr.String1, NULL),
                          NULLIF(TRIM(IFNULL(s.asunto, '')), ''), NULLIF(TRIM(IFNULL(s.notas, '')), '')), 2000),
           'seguimiento', s.creado_por, 'seguimiento',
           (SELECT CONCAT(p.numero, ' v', p.version) FROM propuesta_comercial p WHERE p.id_propuesta = s.id_propuesta),
           (s.estado = 'cerrado_rechazo'), 'Seguimiento'
    FROM seguimiento_comercial s
    LEFT JOIN tabla_maestra c  ON c.IdMaestro = 26 AND c.IdEmpresa = 1 AND c.Num1 = s.id_canal
    LEFT JOIN tabla_maestra rs ON rs.IdMaestro = 27 AND rs.IdEmpresa = 1 AND rs.Num1 = s.id_resultado
    LEFT JOIN tabla_maestra ta ON ta.IdMaestro = 95 AND ta.IdEmpresa = 1 AND ta.Num1 = s.id_tipo_aceptacion
    LEFT JOIN tabla_maestra mr ON mr.IdMaestro = 10 AND mr.IdEmpresa = 1 AND mr.Num1 = s.id_motivo_cierre
    WHERE s.id_propuesta IN (SELECT id_propuesta FROM tmp_exp_props) AND s.eliminado_en IS NULL;

    -- Correos de seguimiento enviados
    INSERT INTO tmp_exp_evt
    SELECT IFNULL(sc.fecha_envio, sc.creado_en), 'seguimiento', 'seguimiento_correo', 'Correo de seguimiento enviado',
           LEFT(CONCAT('Asunto: ', IFNULL(sc.asunto, '(sin asunto)')), 2000), 'seguimiento', sc.id_usuario, 'seguimiento',
           (SELECT CONCAT(p.numero, ' v', p.version) FROM propuesta_comercial p WHERE p.id_propuesta = sc.id_propuesta),
           0, 'Seguimiento'
    FROM seguimiento_correo sc
    WHERE sc.id_propuesta IN (SELECT id_propuesta FROM tmp_exp_props) AND sc.eliminado_en IS NULL AND sc.estado = 'enviado';

    -- 5. Orden de servicio: generación y confirmación del cliente
    INSERT INTO tmp_exp_evt
    SELECT os.fecha_creacion, 'orden_servicio', 'generar_os', 'Orden de servicio generada',
           CONCAT('Ejecución programada para el ', DATE_FORMAT(os.fecha_ejecucion, '%d/%m/%Y'),
                  IFNULL(CONCAT(' a las ', DATE_FORMAT(os.hora_inicio, '%H:%i')), ''), '.'),
           'orden_servicio', os.creado_por, 'orden_servicio', os.numero, 0, 'Órdenes de Servicio'
    FROM orden_servicio os
    WHERE os.id_expediente = p_id_expediente AND os.eliminado_en IS NULL;

    INSERT INTO tmp_exp_evt
    SELECT os.fecha_confirmacion_cliente, 'programacion', 'confirmar_programacion', 'Cliente confirmó la programación',
           NULLIF(CONCAT_WS(' · ', c.String1, ct.nombres), ''), 'programacion', os.modificado_por, 'orden_servicio', os.numero, 0,
           'Programación'
    FROM orden_servicio os
    LEFT JOIN tabla_maestra c ON c.IdMaestro = 26 AND c.IdEmpresa = 1 AND c.Num1 = os.id_canal_confirmacion
    LEFT JOIN contacto_cliente ct ON ct.id_contacto = os.id_contacto_confirma
    WHERE os.id_expediente = p_id_expediente AND os.eliminado_en IS NULL
      AND os.confirmacion_cliente = 1 AND os.fecha_confirmacion_cliente IS NOT NULL;

    -- 6. Ejecución: eventos de campo e incidencias
    INSERT INTO tmp_exp_evt
    SELECT ec.timestamp_utc, 'ejecucion', 'evento_campo', IFNULL(t29.String1, 'Evento de campo'),
           NULLIF(TRIM(IFNULL(ec.notas, '')), ''), 'ejecucion', ec.id_usuario, 'orden_servicio', t.numero,
           (ec.id_tipo_evento IN (7, 10)), 'Ejecución'
    FROM evento_campo ec
    JOIN tmp_exp_oss t ON t.id_os = ec.id_os
    LEFT JOIN tabla_maestra t29 ON t29.IdMaestro = 29 AND t29.IdEmpresa = 1 AND t29.Num1 = ec.id_tipo_evento
    WHERE ec.eliminado_en IS NULL;

    INSERT INTO tmp_exp_evt
    SELECT i.fecha_registro, 'bloqueo', 'incidencia', CONCAT('Incidencia: ', IFNULL(t33.String1, 'operativa')),
           LEFT(i.descripcion, 2000), 'ejecucion', i.id_usuario, 'orden_servicio', t.numero, 1, 'Ejecución'
    FROM incidencia_operativa i
    JOIN tmp_exp_oss t ON t.id_os = i.id_os
    LEFT JOIN tabla_maestra t33 ON t33.IdMaestro = 33 AND t33.IdEmpresa = 1 AND t33.Num1 = i.id_tipo
    WHERE i.eliminado_en IS NULL;

    -- 7. Cierre: informe técnico y conformidad del cliente
    INSERT INTO tmp_exp_evt
    SELECT it.fecha_creacion, 'cierre', 'informe_tecnico', CONCAT('Informe técnico ', it.numero),
           CONCAT('Estado: ', REPLACE(it.estado, '_', ' '), IF(it.version > 1, CONCAT(' (versión ', it.version, ')'), ''), '.'),
           'cierre', it.id_tecnico, 'orden_servicio', t.numero, 0, 'Cierre'
    FROM informe_tecnico it
    JOIN tmp_exp_oss t ON t.id_os = it.id_os
    WHERE it.eliminado_en IS NULL;

    INSERT INTO tmp_exp_evt
    SELECT cd.registrado_en, 'cierre', 'conformidad',
           CASE cd.estado WHEN 'conforme' THEN 'Conformidad del cliente registrada'
                          WHEN 'observado' THEN 'Cliente observó el servicio' ELSE 'Conformidad pendiente' END,
           NULLIF(TRIM(IFNULL(cd.observaciones, '')), ''), 'cierre', cd.creado_por, 'orden_servicio', t.numero,
           (cd.estado = 'observado'), 'Cierre'
    FROM conformidad_digital cd
    JOIN informe_tecnico it ON it.id_informe = cd.id_informe AND it.eliminado_en IS NULL
    JOIN tmp_exp_oss t ON t.id_os = it.id_os
    WHERE cd.eliminado_en IS NULL;

    -- Categoría y título de los eventos de la auditoría
    UPDATE tmp_exp_evt SET
        tipo_evento = IFNULL(tipo_evento, CASE
            WHEN accion IN ('crear_expediente', 'creacion')                                                THEN 'creacion'
            WHEN accion IN ('nueva_version', 'nueva_version_por_revocacion')                               THEN 'propuesta'
            WHEN accion IN ('envio_vb', 'solicitar_revocacion_vb')                                         THEN 'visto_bueno'
            WHEN accion IN ('envio_cliente', 'cambio_estado')                                              THEN 'seguimiento'
            WHEN accion IN ('registrar_oc', 'registrar_oc_complementaria', 'validar_oc', 'editar_oc',
                            'editar_oc_revalidacion', 'distribuir_oc', 'autogenerar_oc', 'reemplazar_oc_auto', 'reemplazar_oc',
                            'vincular_propuesta', 'desvincular_propuesta', 'nueva_version_propuesta', 'liberar_oc') THEN 'orden_compra'
            WHEN accion = 'decision_oc' AND urgente = 1                                                    THEN 'bloqueo'
            WHEN accion = 'decision_oc'                                                                    THEN 'orden_compra'
            WHEN accion IN ('observar_oc', 'levantar_observacion_oc', 'registrar_bloqueo', 'resolver_bloqueo',
                            'registrar_excepcion', 'cerrar_excepcion')                                     THEN 'bloqueo'
            WHEN accion IN ('liberar_programacion', 'crear_y_liberar_programacion', 'avanzar_etapa',
                            'pasar_programacion', 'pasar_orden_servicio', 'volver_orden_compra')           THEN 'orden_servicio'
            WHEN accion IN ('adjuntar_documento', 'reemplazar_pdf_oc', 'reemplazar_pdf', 'subir_oc_corregida') THEN 'documento'
            WHEN accion = 'reasignar_responsable'                                                          THEN 'reasignacion'
            WHEN accion IN ('anulacion', 'anulacion_por_version', 'cerrar_por_anulacion', 'propuesta_anulada',
                            'anular_proceso', 'anular_oc')                                                 THEN 'anulacion'
            ELSE 'otro' END),
        titulo = IFNULL(titulo, CASE accion
            WHEN 'crear_expediente'              THEN 'Expediente creado'
            WHEN 'creacion'                      THEN 'Propuesta creada'
            WHEN 'nueva_version'                 THEN 'Nueva versión de la propuesta'
            WHEN 'nueva_version_por_revocacion'  THEN 'Nueva versión por revocación'
            WHEN 'envio_vb'                      THEN 'Propuesta enviada a visto bueno'
            WHEN 'solicitar_revocacion_vb'       THEN 'Revocación de visto bueno solicitada'
            WHEN 'envio_cliente'                 THEN 'Propuesta enviada al cliente'
            WHEN 'cambio_estado'                 THEN 'Cambio de estado de la propuesta'
            WHEN 'anulacion'                     THEN 'Propuesta anulada'
            WHEN 'anulacion_por_version'         THEN 'Versión reemplazada'
            WHEN 'propuesta_anulada'             THEN 'Propuesta anulada'
            WHEN 'registrar_oc'                  THEN 'OC registrada'
            WHEN 'registrar_oc_complementaria'   THEN 'OC complementaria registrada'
            WHEN 'validar_oc'                    THEN 'OC validada'
            WHEN 'observar_oc'                   THEN 'OC observada'
            WHEN 'levantar_observacion_oc'       THEN 'Observación de la OC levantada'
            WHEN 'editar_oc'                     THEN 'OC editada'
            WHEN 'editar_oc_revalidacion'        THEN 'OC corregida y enviada a revalidación'
            WHEN 'distribuir_oc'                 THEN 'Saldo de OC distribuido'
            WHEN 'reemplazar_pdf_oc'             THEN 'PDF de la OC reemplazado'
            WHEN 'liberar_oc'                    THEN 'OC liberada'
            WHEN 'autogenerar_oc'                THEN 'OC provisional autogenerada'
            WHEN 'reemplazar_oc_auto'            THEN 'OC provisional reemplazada por la OC del cliente'
            WHEN 'reemplazar_oc'                 THEN 'OC reemplazada por la OC corregida del cliente'
            WHEN 'decision_oc'                   THEN 'Decisión sobre la OC'
            WHEN 'vincular_propuesta'            THEN 'Propuesta vinculada a la OC'
            WHEN 'desvincular_propuesta'         THEN 'Propuesta desvinculada de la OC'
            WHEN 'nueva_version_propuesta'       THEN 'Nueva versión de propuesta por la OC'
            WHEN 'reemplazar_pdf'                THEN 'PDF de la OC reemplazado'
            WHEN 'subir_oc_corregida'            THEN 'OC corregida por el cliente'
            WHEN 'anular_oc'                     THEN 'OC anulada'
            WHEN 'pasar_programacion'            THEN 'Expediente pasa a Programación'
            WHEN 'pasar_orden_servicio'          THEN 'Expediente pasa a Orden de Servicio'
            WHEN 'volver_orden_compra'           THEN 'Expediente vuelve a la etapa Orden de Compra'
            WHEN 'liberar_programacion'          THEN 'Expediente liberado a programación'
            WHEN 'crear_y_liberar_programacion'  THEN 'Expediente creado y liberado a programación'
            WHEN 'cerrar_por_anulacion'          THEN 'Expediente cerrado por anulación'
            WHEN 'anular_proceso'                THEN 'Proceso operativo anulado'
            WHEN 'exportar_historial'            THEN 'Auditoría exportada'
            WHEN 'exportar_expediente'           THEN 'Expediente exportado'
            WHEN 'avanzar_etapa'                 THEN 'Etapa completada'
            WHEN 'registrar_bloqueo'             THEN 'Bloqueo registrado'
            WHEN 'resolver_bloqueo'              THEN 'Bloqueo resuelto'
            WHEN 'registrar_excepcion'           THEN 'Excepción registrada'
            WHEN 'cerrar_excepcion'              THEN 'Excepción cerrada'
            WHEN 'adjuntar_documento'            THEN 'Documento adjuntado'
            WHEN 'reasignar_responsable'         THEN 'Responsable reasignado'
            ELSE CONCAT(UPPER(LEFT(REPLACE(accion, '_', ' '), 1)), SUBSTRING(REPLACE(accion, '_', ' '), 2)) END);

    DROP TEMPORARY TABLE IF EXISTS tmp_exp_oss;
    DROP TEMPORARY TABLE IF EXISTS tmp_exp_ocs;
    DROP TEMPORARY TABLE IF EXISTS tmp_exp_props;
END$$

DELIMITER ;
