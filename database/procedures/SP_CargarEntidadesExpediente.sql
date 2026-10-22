-- Expediente Digital (interno, HU-30/33): árbol de entidades del expediente con su responsable.
-- Llena tmp_exp_ent (el que llama hace DROP TEMPORARY TABLE tmp_exp_ent):
--   nivel 1  RQ
--   nivel 2  cada propuesta del RQ (su última versión)
--   nivel 3  las OC vinculadas a esa propuesta (cualquier versión) y, bajo la propuesta activa del expediente, sus OS y OM
-- activa = 1 si la entidad sigue viva y se puede reasignar (HU-33): RQ no cerrado ni anulado, propuesta no rechazada
--   ni anulada, OC no anulada ni reemplazada, OS no finalizada ni anulada. Las OM no se reasignan (son de Metrología).
-- Responsable: RQ id_responsable (o quien lo creó), propuesta id_responsable (o su creador), OC id_responsable
--   (o el de su propuesta), OS id_responsable_comercial (o el de la propuesta activa).
DROP PROCEDURE IF EXISTS SP_CargarEntidadesExpediente;

DELIMITER $$

CREATE PROCEDURE SP_CargarEntidadesExpediente(
    IN p_id_expediente BIGINT
)
BEGIN
    DECLARE v_id_rq       BIGINT;
    DECLARE v_id_prop_exp BIGINT;
    DECLARE v_id_activa   BIGINT;

    SELECT id_requerimiento, id_propuesta INTO v_id_rq, v_id_prop_exp
    FROM expediente_digital WHERE id_expediente = p_id_expediente AND eliminado_en IS NULL;

    DROP TEMPORARY TABLE IF EXISTS tmp_exp_ent;
    CREATE TEMPORARY TABLE tmp_exp_ent (
        clave          VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        clave_padre    VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        nivel          INT,
        orden          INT,
        entidad_tipo   VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        id_entidad     BIGINT,
        codigo         VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        version        INT,
        estado         VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        monto          DECIMAL(14,2),
        id_moneda      INT,
        id_responsable BIGINT,
        fecha          DATETIME,
        fecha_envio    DATETIME,
        fecha_cierre   DATETIME,
        detalle        VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        activa         TINYINT,
        es_activa_exp  TINYINT,
        id_propuesta   BIGINT,
        numero_prop    VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
    );

    -- RQ
    INSERT INTO tmp_exp_ent
    SELECT CONCAT('rq-', r.id_requerimiento), NULL, 1, 1, 'requerimiento', r.id_requerimiento, r.numero, NULL, r.estado,
           NULL, NULL, COALESCE(r.id_responsable, r.id_usuario_creador), r.fecha_creacion, NULL, r.fecha_cierre,
           NULL, (r.estado NOT IN ('cerrado', 'anulado')), 0, NULL, NULL
    FROM requerimiento r WHERE r.id_requerimiento = v_id_rq;

    -- Propuestas (última versión de cada número)
    INSERT INTO tmp_exp_ent
    SELECT CONCAT('prop-', p.id_propuesta), IF(v_id_rq IS NULL, NULL, CONCAT('rq-', v_id_rq)), 2, 0, 'propuesta', p.id_propuesta,
           p.numero, p.version, p.estado, p.total, p.id_moneda, COALESCE(p.id_responsable, p.id_creador), p.fecha_creacion,
           p.fecha_envio,
           CASE WHEN p.estado = 'aceptado' THEN (SELECT MIN(IFNULL(s.fecha_interaccion, s.creado_en)) FROM seguimiento_comercial s
                                                 WHERE s.id_propuesta = p.id_propuesta AND s.eliminado_en IS NULL AND s.estado = 'cerrado_aceptacion')
                WHEN p.estado = 'rechazado' THEN IFNULL((SELECT MIN(IFNULL(s.fecha_interaccion, s.creado_en)) FROM seguimiento_comercial s
                                                         WHERE s.id_propuesta = p.id_propuesta AND s.eliminado_en IS NULL AND s.estado = 'cerrado_rechazo'),
                                                        p.modificado_en)
                WHEN p.estado = 'anulado' THEN IFNULL(p.fecha_anulacion, p.modificado_en)
                ELSE NULL END,
           CASE WHEN p.estado = 'rechazado' THEN
                    (SELECT LEFT(CONCAT_WS(': ', IFNULL(m.String1, 'Motivo de rechazo'), NULLIF(TRIM(IFNULL(s.notas, '')), '')), 500)
                     FROM seguimiento_comercial s
                     LEFT JOIN tabla_maestra m ON m.IdMaestro = 10 AND m.IdEmpresa = 1 AND m.Num1 = s.id_motivo_cierre
                     WHERE s.id_propuesta = p.id_propuesta AND s.eliminado_en IS NULL AND s.estado = 'cerrado_rechazo'
                     ORDER BY s.id_seguimiento DESC LIMIT 1)
                ELSE NULL END,
           (p.estado NOT IN ('rechazado', 'anulado')), 0, p.id_propuesta, p.numero
    FROM propuesta_comercial p
    WHERE p.eliminado_en IS NULL
      AND (p.id_requerimiento = v_id_rq OR (v_id_rq IS NULL AND p.id_propuesta = v_id_prop_exp))
      AND p.version = (SELECT MAX(p2.version) FROM propuesta_comercial p2 WHERE p2.numero = p.numero AND p2.eliminado_en IS NULL);

    -- Propuesta activa del expediente: la más avanzada (aceptada > enviada/aprobada > en VB > en elaboración)
    SELECT id_entidad INTO v_id_activa FROM tmp_exp_ent
    WHERE entidad_tipo = 'propuesta' AND estado <> 'anulado'
    ORDER BY CASE estado WHEN 'aceptado' THEN 1 WHEN 'enviado' THEN 2 WHEN 'aprobado' THEN 2
                         WHEN 'pendiente_vb' THEN 3 WHEN 'pendiente_revocacion' THEN 3 WHEN 'rechazado' THEN 6 ELSE 4 END,
             id_entidad DESC
    LIMIT 1;
    UPDATE tmp_exp_ent SET es_activa_exp = 1 WHERE entidad_tipo = 'propuesta' AND id_entidad = v_id_activa;

    -- OC vinculadas a cada propuesta (a cualquiera de sus versiones); las anuladas y las reemplazadas quedan como historial
    DROP TEMPORARY TABLE IF EXISTS tmp_exp_ent_props;
    CREATE TEMPORARY TABLE tmp_exp_ent_props AS SELECT id_entidad AS id_propuesta, numero_prop FROM tmp_exp_ent WHERE entidad_tipo = 'propuesta';

    INSERT INTO tmp_exp_ent
    SELECT CONCAT('oc-', oc.id_oc), CONCAT('prop-', MIN(t.id_propuesta)), 3, 0, 'orden_compra', oc.id_oc, oc.numero_oc, NULL,
           oc.estado, oc.monto_total, oc.id_moneda,
           COALESCE(oc.id_responsable, MIN(COALESCE(p.id_responsable, p.id_creador))), oc.fecha_registro, NULL,
           COALESCE(oc.fecha_anulacion, oc.fecha_reemplazo),
           CASE WHEN oc.reemplazada_por IS NOT NULL
                    THEN CONCAT('Reemplazada por la OC ', (SELECT n.numero_oc FROM orden_compra n WHERE n.id_oc = oc.reemplazada_por))
                WHEN oc.es_autogenerada = 1 THEN 'OC provisional autogenerada'
                ELSE NULL END,
           (oc.estado <> 'anulada' AND oc.reemplazada_por IS NULL), 0, MIN(t.id_propuesta), MIN(t.numero_prop)
    FROM orden_compra oc
    JOIN oc_propuesta op ON op.id_oc = oc.id_oc
    JOIN propuesta_comercial p ON p.id_propuesta = op.id_propuesta
    JOIN tmp_exp_ent_props t ON t.numero_prop = p.numero
    WHERE oc.eliminado_en IS NULL AND op.eliminado_en IS NULL
    GROUP BY oc.id_oc;

    DROP TEMPORARY TABLE IF EXISTS tmp_exp_ent_props;

    -- OS y OM del expediente (bajo la propuesta activa)
    INSERT INTO tmp_exp_ent
    SELECT CONCAT('os-', os.id_os), IF(v_id_activa IS NULL, IF(v_id_rq IS NULL, NULL, CONCAT('rq-', v_id_rq)), CONCAT('prop-', v_id_activa)),
           IF(v_id_activa IS NULL, 2, 3), 0, 'orden_servicio', os.id_os, os.numero, NULL, os.estado, os.costo_total_estimado, NULL,
           COALESCE(os.id_responsable_comercial,
                    (SELECT COALESCE(p.id_responsable, p.id_creador) FROM propuesta_comercial p WHERE p.id_propuesta = v_id_activa)),
           os.fecha_creacion, NULL, IF(os.estado = 'finalizada', os.modificado_en, NULL),
           CONCAT('Ejecución: ', DATE_FORMAT(os.fecha_ejecucion, '%d/%m/%Y')),
           (os.estado NOT IN ('finalizada', 'anulada')), 0, v_id_activa, NULL
    FROM orden_servicio os
    WHERE os.id_expediente = p_id_expediente AND os.eliminado_en IS NULL;

    INSERT INTO tmp_exp_ent
    SELECT CONCAT('om-', om.id_om), IF(v_id_activa IS NULL, IF(v_id_rq IS NULL, NULL, CONCAT('rq-', v_id_rq)), CONCAT('prop-', v_id_activa)),
           IF(v_id_activa IS NULL, 2, 3), 0, 'orden_metrologia', om.id_om, om.numero, NULL, om.estado, NULL, NULL,
           om.id_metrologo, om.fecha_creacion, NULL, IF(om.estado = 'finalizada', om.modificado_en, NULL),
           IFNULL(CONCAT('Certificado: ', om.numero_certificado), NULL), 0, 0, v_id_activa, NULL
    FROM orden_metrologia om
    WHERE om.id_expediente = p_id_expediente AND om.eliminado_en IS NULL;

    -- Orden de presentación: propuesta activa primero, luego las demás; dentro, OC y luego OS / OM
    UPDATE tmp_exp_ent SET orden = CASE entidad_tipo
        WHEN 'requerimiento'    THEN 1
        WHEN 'propuesta'        THEN IF(es_activa_exp = 1, 10, 20)
        WHEN 'orden_compra'     THEN 30
        WHEN 'orden_servicio'   THEN 40
        ELSE 50 END;
END$$

DELIMITER ;
