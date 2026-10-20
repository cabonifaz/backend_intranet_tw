-- Expediente Digital (interno, HU-30/33): historial cronológico del expediente.
-- Junta en tmp_exp_evt (el que llama hace DROP TEMPORARY TABLE tmp_exp_evt) los eventos de:
--   - el expediente (auditoria_evento 'expediente'),
--   - el RQ (historial_requerimiento),
--   - las propuestas del RQ y sus vistos buenos (auditoria_evento 'propuesta', visto_bueno),
--   - las órdenes de compra que cubren esas propuestas (auditoria_evento 'orden_compra').
-- Solo lectura: la auditoría es inmutable (no hay SP que modifique o borre eventos).
-- Los eventos de documentos internos (adjuntar_documento) respetan la visibilidad del documento: si el usuario no
-- puede ver el documento (solo un área), tampoco ve el evento con su nombre y descripción.
-- tipo_evento: creacion, requerimiento, visto_bueno, orden_compra, etapa, bloqueo, documento, reasignacion,
--   anulacion, otro.
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
    SELECT op.id_oc FROM oc_propuesta op JOIN tmp_exp_props t ON t.id_propuesta = op.id_propuesta
    WHERE op.eliminado_en IS NULL;

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
        urgente      TINYINT
    );

    -- Expediente, propuestas y OC (auditoria_evento)
    INSERT INTO tmp_exp_evt
    SELECT a.registrado_en, NULL, a.accion, NULL, a.descripcion,
           CASE
               WHEN a.entidad_tipo = 'expediente' THEN
                   COALESCE(NULLIF(JSON_UNQUOTE(JSON_EXTRACT(a.metadata, '$.etapa')), 'null'),
                            IF(a.estado_nuevo IN ('requerimiento', 'propuesta', 'visto_bueno', 'orden_compra', 'programacion',
                                                  'ssoma', 'ejecucion', 'revision', 'conformidad', 'facturacion', 'cerrado'),
                               a.estado_nuevo, NULL))
               WHEN a.entidad_tipo = 'propuesta' AND a.accion IN ('envio_vb', 'solicitar_revocacion_vb') THEN 'visto_bueno'
               WHEN a.entidad_tipo = 'propuesta' AND a.accion = 'envio_cliente'                      THEN 'orden_compra'
               WHEN a.entidad_tipo = 'propuesta'                                                     THEN 'propuesta'
               ELSE 'orden_compra'
           END,
           a.id_usuario, a.entidad_tipo,
           CASE a.entidad_tipo
               WHEN 'expediente'   THEN (SELECT e.numero FROM expediente_digital e WHERE e.id_expediente = a.id_entidad)
               WHEN 'propuesta'    THEN (SELECT CONCAT(p.numero, ' v', p.version) FROM propuesta_comercial p WHERE p.id_propuesta = a.id_entidad)
               WHEN 'orden_compra' THEN (SELECT CONCAT('OC ', oc.numero_oc) FROM orden_compra oc WHERE oc.id_oc = a.id_entidad)
           END,
           (a.accion IN ('observar_oc', 'registrar_bloqueo', 'anular_oc')
            OR (a.accion = 'decision_oc' AND a.estado_nuevo = 'correccion_cliente'))
    FROM auditoria_evento a
    WHERE ((a.entidad_tipo = 'expediente' AND a.id_entidad = p_id_expediente
            AND (a.accion <> 'adjuntar_documento'
                 OR IFNULL(v_area, '') IN ('gerencia', 'ti')
                 OR a.id_usuario = p_id_usuario
                 OR IFNULL(CAST(JSON_UNQUOTE(JSON_EXTRACT(a.metadata, '$.id_visibilidad')) AS UNSIGNED), 1) IN (1, 5)
                 OR EXISTS (SELECT 1 FROM tabla_maestra v
                            WHERE v.IdMaestro = 35 AND v.IdEmpresa = 1 AND LOWER(v.String2) = IFNULL(v_area, '')
                              AND v.Num1 = CAST(JSON_UNQUOTE(JSON_EXTRACT(a.metadata, '$.id_visibilidad')) AS UNSIGNED))))
       OR (a.entidad_tipo = 'propuesta' AND a.id_entidad IN (SELECT id_propuesta FROM tmp_exp_props)))
       OR (a.entidad_tipo = 'orden_compra' AND a.id_entidad IN (SELECT id_oc FROM tmp_exp_ocs)
           -- El detalle fino de la OC (cada validación, extracción o corrección) queda en el timeline de la OC
           AND a.accion NOT IN ('exportar_auditoria_oc', 'validacion_ia', 'extraccion_ia', 'corregir_campo_oc',
                                'editar_vinculacion', 'cargar_pdf_oc', 'cambio_estado_oc'));

    -- RQ (historial propio del requerimiento)
    INSERT INTO tmp_exp_evt
    SELECT h.fecha, IF(h.tipo = 'creacion', 'creacion', 'requerimiento'), CONCAT('rq_', h.tipo), h.tipo_label,
           h.descripcion, 'requerimiento', h.creado_por, 'requerimiento',
           (SELECT r.numero FROM requerimiento r WHERE r.id_requerimiento = h.id_requerimiento), 0
    FROM historial_requerimiento h
    WHERE v_id_rq IS NOT NULL AND h.id_requerimiento = v_id_rq AND IFNULL(h.SoftDelete, 0) = 0;

    -- Vistos buenos: respuesta del aprobador (la solicitud ya está como envio_vb)
    INSERT INTO tmp_exp_evt
    SELECT v.fecha_respuesta, 'visto_bueno', CONCAT('vb_', v.estado),
           CASE v.estado WHEN 'aprobado' THEN 'Visto bueno aprobado'
                         WHEN 'rechazado' THEN 'Visto bueno rechazado'
                         WHEN 'devuelto' THEN 'Propuesta devuelta para corrección'
                         WHEN 'reasignado' THEN 'Visto bueno reasignado'
                         ELSE CONCAT('Visto bueno ', REPLACE(v.estado, '_', ' ')) END,
           NULLIF(TRIM(IFNULL(v.comentario_respuesta, '')), ''),
           'visto_bueno', IFNULL(v.resuelto_por, v.id_aprobador), 'visto_bueno',
           (SELECT CONCAT(p.numero, ' v', p.version) FROM propuesta_comercial p WHERE p.id_propuesta = v.id_propuesta),
           (v.estado = 'rechazado')
    FROM visto_bueno v
    WHERE v.id_propuesta IN (SELECT id_propuesta FROM tmp_exp_props)
      AND v.fecha_respuesta IS NOT NULL AND v.eliminado_en IS NULL AND v.tipo = 'aprobacion';

    -- Categoría y título
    UPDATE tmp_exp_evt SET
        tipo_evento = IFNULL(tipo_evento, CASE
            WHEN accion IN ('crear_expediente', 'creacion', 'nueva_version', 'nueva_version_por_revocacion') THEN 'creacion'
            WHEN accion IN ('envio_vb', 'solicitar_revocacion_vb')                                       THEN 'visto_bueno'
            WHEN accion IN ('envio_cliente', 'registrar_oc', 'registrar_oc_complementaria', 'validar_oc', 'editar_oc',
                            'editar_oc_revalidacion', 'distribuir_oc', 'autogenerar_oc', 'reemplazar_oc_auto',
                            'decision_oc', 'vincular_propuesta', 'desvincular_propuesta', 'nueva_version_propuesta') THEN 'orden_compra'
            WHEN accion IN ('observar_oc', 'levantar_observacion_oc', 'registrar_bloqueo', 'resolver_bloqueo', 'registrar_excepcion',
                            'cerrar_excepcion')                                                            THEN 'bloqueo'
            WHEN accion IN ('liberar_oc', 'liberar_programacion', 'crear_y_liberar_programacion', 'avanzar_etapa',
                            'pasar_programacion', 'volver_orden_compra')                                   THEN 'etapa'
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
            WHEN 'liberar_oc'                    THEN 'OC liberada a programación'
            WHEN 'autogenerar_oc'                THEN 'OC provisional autogenerada'
            WHEN 'reemplazar_oc_auto'            THEN 'OC provisional reemplazada por la OC del cliente'
            WHEN 'decision_oc'                   THEN 'Decisión sobre la OC'
            WHEN 'vincular_propuesta'            THEN 'Propuesta vinculada a la OC'
            WHEN 'desvincular_propuesta'         THEN 'Propuesta desvinculada de la OC'
            WHEN 'nueva_version_propuesta'       THEN 'Nueva versión de propuesta por la OC'
            WHEN 'reemplazar_pdf'                THEN 'PDF de la OC reemplazado'
            WHEN 'subir_oc_corregida'            THEN 'OC corregida por el cliente'
            WHEN 'anular_oc'                     THEN 'OC anulada'
            WHEN 'pasar_programacion'            THEN 'Expediente pasa a Programación'
            WHEN 'volver_orden_compra'           THEN 'Expediente vuelve a la etapa Orden de Compra'
            WHEN 'liberar_programacion'          THEN 'Expediente liberado a programación'
            WHEN 'crear_y_liberar_programacion'  THEN 'Expediente creado y liberado a programación'
            WHEN 'cerrar_por_anulacion'          THEN 'Expediente cerrado por anulación'
            WHEN 'anular_proceso'                THEN 'Proceso operativo anulado'
            WHEN 'exportar_historial'            THEN 'Historial exportado'
            WHEN 'exportar_expediente'           THEN 'Expediente exportado'
            WHEN 'avanzar_etapa'                 THEN 'Etapa completada'
            WHEN 'registrar_bloqueo'             THEN 'Bloqueo registrado'
            WHEN 'resolver_bloqueo'              THEN 'Bloqueo resuelto'
            WHEN 'registrar_excepcion'           THEN 'Excepción registrada'
            WHEN 'cerrar_excepcion'              THEN 'Excepción cerrada'
            WHEN 'adjuntar_documento'            THEN 'Documento adjuntado'
            WHEN 'reasignar_responsable'         THEN 'Responsable reasignado'
            ELSE CONCAT(UPPER(LEFT(REPLACE(accion, '_', ' '), 1)), SUBSTRING(REPLACE(accion, '_', ' '), 2)) END);

    DROP TEMPORARY TABLE IF EXISTS tmp_exp_ocs;
    DROP TEMPORARY TABLE IF EXISTS tmp_exp_props;
END$$

DELIMITER ;
