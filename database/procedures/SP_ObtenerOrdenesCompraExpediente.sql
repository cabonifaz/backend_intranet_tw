-- HU-30 Tab 🧾 OC (N) de la ficha del expediente (carga perezosa, solo lectura). Acción expediente_bandeja.
-- Pills por OC (las OC de las propuestas del RQ, vigentes y como historial las anuladas o reemplazadas);
-- p_id_oc = OC elegida (por defecto la primera vigente).
-- Resultados: 1 mensaje
--   2 OC del expediente (pills: número, propuesta, estado, seleccionada)
--   3 datos de la OC: código, fechas, moneda, montos (total, asignado a este expediente y saldo), forma de pago, IGV,
--     "La factura tendrá exactamente lo mismo que la OC", observaciones, PDF (clave para ver/descargar), anulación o
--     reemplazo y su responsable
--   4 validación por IA por propuesta vinculada (sub-aplicación): resultado, coincidencias, advertencias, críticas,
--     confianza (0–100), motor, dictamen, estado de la vinculación y monto asignado
--   5 comparación campo por campo de la última validación de la primera propuesta vinculada de este expediente
--   6 timeline de la OC (auditoría; el detalle fino de cada validación queda en el módulo OC)
--   7 órdenes de servicio vinculadas a la OC (las de los expedientes de sus propuestas): número, estado, costo estimado,
--     fecha de ejecución, técnico principal y responsable comercial
DROP PROCEDURE IF EXISTS SP_ObtenerOrdenesCompraExpediente;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerOrdenesCompraExpediente(
    IN p_id_usuario    BIGINT,
    IN p_id_expediente BIGINT,
    IN p_id_oc         BIGINT
)
proc: BEGIN
    DECLARE v_id_rq   BIGINT;
    DECLARE v_id_oc   BIGINT;
    DECLARE v_id_val  BIGINT;

    IF FN_PermisoAccion(p_id_usuario, 'expediente_bandeja') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver los expedientes digitales.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM expediente_digital WHERE id_expediente = p_id_expediente AND eliminado_en IS NULL) THEN
        SELECT 1 AS IdTipoMensaje, 'El expediente no existe.' AS Mensaje;
        LEAVE proc;
    END IF;
    SELECT id_requerimiento INTO v_id_rq FROM expediente_digital WHERE id_expediente = p_id_expediente;

    -- OC del expediente: vinculadas a alguna versión de las propuestas del RQ
    DROP TEMPORARY TABLE IF EXISTS tmp_exp_oc;
    CREATE TEMPORARY TABLE tmp_exp_oc AS
    SELECT oc.id_oc, oc.numero_oc, oc.estado, oc.es_autogenerada, oc.reemplazada_por, oc.fecha_registro,
           MIN(p.id_propuesta) AS id_propuesta, MIN(CONCAT(p.numero, ' v', p.version)) AS propuesta,
           SUM(op.monto_asignado) AS monto_asignado_exp,
           (oc.estado <> 'anulada' AND oc.reemplazada_por IS NULL) AS vigente
    FROM orden_compra oc
    JOIN oc_propuesta op ON op.id_oc = oc.id_oc AND op.eliminado_en IS NULL
    JOIN propuesta_comercial p ON p.id_propuesta = op.id_propuesta AND p.id_requerimiento = v_id_rq
    WHERE oc.eliminado_en IS NULL
    GROUP BY oc.id_oc;

    IF IFNULL(p_id_oc, 0) > 0 THEN
        SELECT id_oc INTO v_id_oc FROM tmp_exp_oc WHERE id_oc = p_id_oc;
        IF v_id_oc IS NULL THEN
            DROP TEMPORARY TABLE IF EXISTS tmp_exp_oc;
            SELECT 1 AS IdTipoMensaje, 'La orden de compra no pertenece a este expediente.' AS Mensaje;
            LEAVE proc;
        END IF;
    ELSE
        SELECT id_oc INTO v_id_oc FROM tmp_exp_oc ORDER BY vigente DESC, id_oc LIMIT 1;
    END IF;

    -- Última validación de la primera propuesta del expediente vinculada a la OC
    SELECT v.id_validacion INTO v_id_val
    FROM orden_compra_validacion v
    JOIN propuesta_comercial p ON p.id_propuesta = v.id_propuesta AND p.id_requerimiento = v_id_rq
    WHERE v.id_oc = v_id_oc AND v.eliminado_en IS NULL
    ORDER BY v.id_propuesta, v.corrida DESC, v.id_validacion DESC LIMIT 1;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. OC (pills)
    SELECT t.id_oc, t.numero_oc, t.estado, t.es_autogenerada, t.vigente, t.id_propuesta, t.propuesta,
           (t.id_oc = v_id_oc) AS seleccionada
    FROM tmp_exp_oc t ORDER BY t.vigente DESC, t.id_oc;

    -- 3. Datos de la OC
    SELECT oc.id_oc, oc.numero_oc, oc.estado, oc.es_autogenerada, oc.referencia,
           oc.fecha_oc AS fecha_emision, oc.fecha_recepcion, oc.fecha_registro, oc.vigencia_hasta,
           oc.id_moneda, m.String1 AS moneda, m.String2 AS simbolo_moneda,
           oc.monto_total, t.monto_asignado_exp AS monto_asignado,
           oc.monto_total - IFNULL((SELECT SUM(op.monto_asignado) FROM oc_propuesta op
                                    WHERE op.id_oc = oc.id_oc AND op.eliminado_en IS NULL), 0) AS saldo,
           IFNULL(oc.forma_pago,
                  (SELECT cp.String1 FROM tabla_maestra cp WHERE cp.IdMaestro = 39 AND cp.IdEmpresa = 1
                     AND cp.Num1 = oc.id_condicion_pago AND cp.eliminado_en IS NULL LIMIT 1)) AS forma_pago,
           oc.igv_incluido, oc.igv_pct, oc.factura_igual_oc, oc.observaciones,
           COALESCE((SELECT CONCAT('doc-', d.id_documento) FROM documento_adjunto d
                     WHERE d.entidad_tipo = 'orden_compra' AND d.id_entidad = oc.id_oc AND d.eliminado_en IS NULL
                     ORDER BY d.version DESC, d.id_documento DESC LIMIT 1),
                    IF(oc.url_archivo_pdf IS NULL, NULL, CONCAT('ocpdf-', oc.id_oc)))      AS clave_pdf,
           oc.nombre_archivo_pdf, oc.tamano_pdf_bytes,
           (SELECT n.numero_oc FROM orden_compra n WHERE n.id_oc = oc.reemplazada_por)     AS reemplazada_por,
           oc.fecha_reemplazo, oc.fecha_anulacion, ma.String1 AS motivo_anulacion, oc.justificacion_anulacion,
           oc.id_responsable, CONCAT(u.nombre, ' ', u.apellido) AS responsable,
           oc.creado_por AS id_registrado_por, CONCAT(ur.nombre, ' ', ur.apellido) AS registrado_por
    FROM orden_compra oc
    JOIN tmp_exp_oc t ON t.id_oc = oc.id_oc
    LEFT JOIN tabla_maestra m  ON m.IdMaestro = 1 AND m.IdEmpresa = 1 AND m.Num1 = oc.id_moneda
    LEFT JOIN tabla_maestra ma ON ma.IdMaestro = 102 AND ma.IdEmpresa = 1 AND ma.Num1 = oc.id_motivo_anulacion
    LEFT JOIN usuario u  ON u.id_usuario = COALESCE(oc.id_responsable,
                                                    (SELECT COALESCE(p.id_responsable, p.id_creador) FROM propuesta_comercial p
                                                     WHERE p.id_propuesta = t.id_propuesta))
    LEFT JOIN usuario ur ON ur.id_usuario = oc.creado_por
    WHERE oc.id_oc = v_id_oc;

    DROP TEMPORARY TABLE IF EXISTS tmp_exp_oc;

    -- 4. Validación por propuesta vinculada (todas las de la OC; de_este_expediente marca las del RQ)
    SELECT op.id_propuesta, CONCAT(p.numero, ' v', p.version) AS propuesta, p.estado AS estado_propuesta,
           (p.id_requerimiento = v_id_rq) AS de_este_expediente,
           op.monto_asignado, ROUND(op.monto_asignado * 100 / NULLIF(oc.monto_total, 0), 1) AS porcentaje_oc,
           op.estado_validacion, op.tipo_observacion, op.resultado_ia, op.fecha_decision,
           v.corrida, v.coincidencias, v.advertencias, v.criticas, v.total_campos, v.confianza, v.motor, v.dictamen,
           v.sugerencia, v.fecha_validacion
    FROM oc_propuesta op
    JOIN orden_compra oc ON oc.id_oc = op.id_oc
    JOIN propuesta_comercial p ON p.id_propuesta = op.id_propuesta
    LEFT JOIN orden_compra_validacion v ON v.id_validacion = (
            SELECT v2.id_validacion FROM orden_compra_validacion v2
            WHERE v2.id_oc = op.id_oc AND v2.id_propuesta = op.id_propuesta AND v2.eliminado_en IS NULL
            ORDER BY v2.corrida DESC, v2.id_validacion DESC LIMIT 1)
    WHERE op.id_oc = v_id_oc AND op.eliminado_en IS NULL
    ORDER BY (p.id_requerimiento = v_id_rq) DESC, op.id;

    -- 5. Comparación campo por campo (última validación)
    SELECT d.orden, d.campo, d.etiqueta, d.valor_oc, d.valor_propuesta, d.severidad, d.mensaje
    FROM orden_compra_validacion v
    JOIN JSON_TABLE(IFNULL(v.detalle, JSON_ARRAY()), '$[*]' COLUMNS (
            orden           INT          PATH '$.orden',
            campo           VARCHAR(30)  PATH '$.campo',
            etiqueta        VARCHAR(60)  PATH '$.etiqueta',
            valor_oc        VARCHAR(400) PATH '$.valorOc',
            valor_propuesta VARCHAR(400) PATH '$.valorPropuesta',
            severidad       VARCHAR(15)  PATH '$.severidad',
            mensaje         VARCHAR(400) PATH '$.mensaje')) d
    WHERE v.id_validacion = IFNULL(v_id_val, 0)
    ORDER BY d.orden;

    -- 6. Timeline de la OC
    SELECT a.registrado_en AS fecha, a.accion,
           CASE a.accion
               WHEN 'registrar_oc'        THEN 'Creación y registro de OC'
               WHEN 'cargar_pdf_oc'       THEN 'Carga de documento PDF'
               WHEN 'extraccion_ia'       THEN 'Extracción de datos por IA'
               WHEN 'validacion_ia'       THEN 'Validación por IA'
               WHEN 'decision_oc'         THEN 'Decisión del comercial'
               WHEN 'cambio_estado_oc'    THEN 'Cambio de estado'
               WHEN 'autogenerar_oc'      THEN 'OC provisional autogenerada'
               WHEN 'reemplazar_oc_auto'  THEN 'OC provisional reemplazada'
               WHEN 'reemplazar_oc'       THEN 'OC reemplazada'
               WHEN 'anular_oc'           THEN 'OC anulada'
               WHEN 'editar_oc'           THEN 'OC editada'
               WHEN 'corregir_campo_oc'   THEN 'Corrección manual de un campo'
               WHEN 'reasignar_responsable' THEN 'Responsable reasignado'
               ELSE CONCAT(UPPER(LEFT(REPLACE(a.accion, '_', ' '), 1)), SUBSTRING(REPLACE(a.accion, '_', ' '), 2)) END AS titulo,
           a.descripcion, a.estado_anterior, a.estado_nuevo, a.id_usuario,
           IFNULL(CONCAT(u.nombre, ' ', u.apellido), 'Sistema') AS usuario,
           (a.accion IN ('extraccion_ia', 'validacion_ia')) AS automatico_ia
    FROM auditoria_evento a
    LEFT JOIN usuario u ON u.id_usuario = a.id_usuario
    WHERE a.entidad_tipo = 'orden_compra' AND a.id_entidad = v_id_oc AND a.accion <> 'exportar_auditoria_oc'
    ORDER BY a.registrado_en DESC, a.id_auditoria DESC;

    -- 7. Órdenes de servicio vinculadas a la OC
    SELECT os.id_os, os.numero, os.estado, os.costo_total_estimado, os.fecha_ejecucion, os.hora_inicio,
           os.id_tecnico_principal, CONCAT(ut.nombre, ' ', ut.apellido) AS tecnico,
           os.id_responsable_comercial, CONCAT(uc.nombre, ' ', uc.apellido) AS responsable_comercial,
           os.confirmacion_cliente, e.id_expediente, e.numero AS numero_expediente
    FROM orden_servicio os
    JOIN expediente_digital e ON e.id_expediente = os.id_expediente AND e.eliminado_en IS NULL
    LEFT JOIN usuario ut ON ut.id_usuario = os.id_tecnico_principal
    LEFT JOIN usuario uc ON uc.id_usuario = os.id_responsable_comercial
    WHERE os.eliminado_en IS NULL
      AND os.id_expediente IN (SELECT FN_ExpedienteDePropuesta(op.id_propuesta) FROM oc_propuesta op
                               WHERE op.id_oc = v_id_oc AND op.eliminado_en IS NULL)
    ORDER BY os.fecha_ejecucion DESC, os.id_os DESC;
END$$

DELIMITER ;
