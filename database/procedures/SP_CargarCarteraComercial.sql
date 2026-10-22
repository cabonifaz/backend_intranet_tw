-- Expediente Digital (interno, HU-33 Opción C): todo lo pendiente de un comercial en todos los expedientes.
-- Llena tmp_cartera (el que llama hace DROP TEMPORARY TABLE tmp_cartera) con las entidades ACTIVAS de las que el
-- comercial es responsable: RQ no cerrados ni anulados, propuestas (última versión) no rechazadas ni anuladas, OC no
-- anuladas ni reemplazadas y OS no finalizadas ni anuladas. Las finalizadas conservan su responsable histórico.
-- El seguimiento no aparece: hereda el responsable de su propuesta.
DROP PROCEDURE IF EXISTS SP_CargarCarteraComercial;

DELIMITER $$

CREATE PROCEDURE SP_CargarCarteraComercial(
    IN p_id_responsable BIGINT
)
BEGIN
    DROP TEMPORARY TABLE IF EXISTS tmp_cartera;
    CREATE TEMPORARY TABLE tmp_cartera (
        id_expediente  BIGINT,
        entidad_tipo   VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        id_entidad     BIGINT,
        codigo         VARCHAR(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        estado         VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        detalle        VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        KEY (id_expediente)
    );

    -- RQ
    INSERT INTO tmp_cartera
    SELECT e.id_expediente, 'requerimiento', r.id_requerimiento, r.numero, r.estado, LEFT(r.descripcion, 300)
    FROM requerimiento r
    JOIN expediente_digital e ON e.id_requerimiento = r.id_requerimiento AND e.eliminado_en IS NULL
    WHERE r.eliminado_en IS NULL AND IFNULL(r.SoftDelete, 0) = 0 AND r.estado NOT IN ('cerrado', 'anulado')
      AND COALESCE(r.id_responsable, r.id_usuario_creador) = p_id_responsable;

    -- Propuestas (última versión)
    INSERT INTO tmp_cartera
    SELECT e.id_expediente, 'propuesta', p.id_propuesta, CONCAT(p.numero, ' v', p.version), p.estado,
           LEFT(CONCAT_WS(' · ', p.tipo_servicio, p.referencia), 300)
    FROM propuesta_comercial p
    JOIN expediente_digital e ON e.id_requerimiento = p.id_requerimiento AND e.eliminado_en IS NULL
    WHERE p.eliminado_en IS NULL AND p.estado NOT IN ('rechazado', 'anulado')
      AND p.version = (SELECT MAX(p2.version) FROM propuesta_comercial p2 WHERE p2.numero = p.numero AND p2.eliminado_en IS NULL)
      AND COALESCE(p.id_responsable, p.id_creador) = p_id_responsable;

    -- OC vigentes (el expediente de su primera propuesta vinculada)
    INSERT INTO tmp_cartera
    SELECT FN_ExpedienteDePropuesta(MIN(op.id_propuesta)), 'orden_compra', oc.id_oc, oc.numero_oc, oc.estado,
           IF(oc.es_autogenerada = 1, 'OC provisional autogenerada', NULL)
    FROM orden_compra oc
    JOIN oc_propuesta op ON op.id_oc = oc.id_oc AND op.eliminado_en IS NULL
    JOIN propuesta_comercial p ON p.id_propuesta = op.id_propuesta
    WHERE oc.eliminado_en IS NULL AND oc.estado <> 'anulada' AND oc.reemplazada_por IS NULL
    GROUP BY oc.id_oc
    HAVING COALESCE(MAX(oc.id_responsable), MIN(COALESCE(p.id_responsable, p.id_creador))) = p_id_responsable;

    -- OS abiertas
    INSERT INTO tmp_cartera
    SELECT os.id_expediente, 'orden_servicio', os.id_os, os.numero, os.estado,
           CONCAT('Ejecución: ', DATE_FORMAT(os.fecha_ejecucion, '%d/%m/%Y'))
    FROM orden_servicio os
    JOIN expediente_digital e ON e.id_expediente = os.id_expediente AND e.eliminado_en IS NULL
    LEFT JOIN propuesta_comercial p ON p.id_propuesta = e.id_propuesta
    WHERE os.eliminado_en IS NULL AND os.estado NOT IN ('finalizada', 'anulada')
      AND COALESCE(os.id_responsable_comercial, p.id_responsable, p.id_creador) = p_id_responsable;

    -- Sin expediente o con el RQ cerrado o anulado: no son pendientes
    DELETE t FROM tmp_cartera t
    LEFT JOIN expediente_digital e ON e.id_expediente = t.id_expediente
    LEFT JOIN requerimiento r ON r.id_requerimiento = e.id_requerimiento
    WHERE t.id_expediente IS NULL OR e.id_expediente IS NULL OR IFNULL(r.estado, '') IN ('cerrado', 'anulado');
END$$

DELIMITER ;
