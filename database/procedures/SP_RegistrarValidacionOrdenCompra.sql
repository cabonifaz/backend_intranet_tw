-- HU-23/24/26 (Sprint 4) Corre la validación de la OC contra una propuesta vinculada y la guarda. Uso interno.
-- Compara con SP_CompararOcPropuesta, guarda la corrida en orden_compra_validacion (historial del modal IA),
-- actualiza resultado_ia e id_validacion de la vinculación y registra el evento en la auditoría.
-- No decide el estado de la vinculación: eso lo hace el comercial (registro, edición) o la OC corregida.
-- p_origen: registro, edicion, reemplazo_pdf, oc_corregida, revalidacion, validar_contra_propuesta
DROP PROCEDURE IF EXISTS SP_RegistrarValidacionOrdenCompra;

DELIMITER $$

CREATE PROCEDURE SP_RegistrarValidacionOrdenCompra(
    IN  p_id_oc          BIGINT,
    IN  p_id_propuesta   BIGINT,
    IN  p_datos          JSON,
    IN  p_monto_asignado DECIMAL(14,2),
    IN  p_eval_ia        JSON,
    IN  p_origen         VARCHAR(30),
    IN  p_id_usuario     BIGINT,
    OUT p_id_validacion  BIGINT,
    OUT p_resultado      VARCHAR(20),
    OUT p_sugerencia     VARCHAR(30)
)
BEGIN
    DECLARE v_coinc   INT;
    DECLARE v_adv     INT;
    DECLARE v_crit    INT;
    DECLARE v_total   INT;
    DECLARE v_corrida INT;
    DECLARE v_detalle JSON;
    DECLARE v_concep  JSON;
    DECLARE v_dictamen TEXT;
    DECLARE v_numero  VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_datos   JSON;

    -- Números de las propuestas vinculadas a la OC (la OC puede referenciar cualquiera de ellas)
    SET v_datos = JSON_SET(IFNULL(p_datos, JSON_OBJECT()), '$._propuestasVinculadas',
                           (SELECT IFNULL(JSON_ARRAYAGG(px.numero), JSON_ARRAY())
                            FROM oc_propuesta op JOIN propuesta_comercial px ON px.id_propuesta = op.id_propuesta
                            WHERE op.id_oc = p_id_oc AND op.eliminado_en IS NULL));

    CALL SP_CompararOcPropuesta(p_id_propuesta, p_id_oc, v_datos, p_monto_asignado, p_eval_ia,
                                p_resultado, v_coinc, v_adv, v_crit, v_total, p_sugerencia);

    SELECT JSON_ARRAYAGG(JSON_OBJECT('orden', orden, 'campo', campo, 'etiqueta', etiqueta, 'valorOc', valor_oc,
                                     'valorPropuesta', valor_propuesta, 'severidad', severidad,
                                     'mensaje', mensaje, 'accion', accion))
      INTO v_detalle
    FROM (SELECT * FROM tmp_oc_cmp ORDER BY orden) x;

    SELECT CONCAT(numero, ' v', version) INTO v_numero FROM propuesta_comercial WHERE id_propuesta = p_id_propuesta;

    -- Conceptos: los que evaluó la IA; si no hay evaluación, los ítems de la propuesta sin comparar
    IF p_eval_ia IS NOT NULL AND JSON_LENGTH(JSON_EXTRACT(p_eval_ia, '$.conceptos')) > 0 THEN
        SET v_concep = JSON_EXTRACT(p_eval_ia, '$.conceptos');
    ELSE
        SELECT JSON_ARRAYAGG(JSON_OBJECT('descripcion', descripcion, 'montoOc', NULL, 'montoPropuesta', subtotal,
                                         'estado', 'sin_comparar'))
          INTO v_concep
        FROM propuesta_item
        WHERE id_propuesta = p_id_propuesta AND seccion = 'principal' AND IFNULL(es_espaciado, 0) = 0;
    END IF;

    SET v_dictamen = FN_JsonTexto(p_eval_ia, '$.dictamen');
    IF v_dictamen IS NULL THEN
        SELECT IF(p_resultado = 'ok', CONCAT('Sin diferencias con ', v_numero, '.'),
                  CONCAT(COUNT(*), ' diferencia(s) con ', v_numero, ': ',
                         GROUP_CONCAT(CONCAT(etiqueta, ' — ', TRIM(TRAILING '.' FROM mensaje)) ORDER BY orden SEPARATOR '; '), '.'))
          INTO v_dictamen
        FROM tmp_oc_cmp WHERE severidad IN ('advertencia', 'critico');
    END IF;

    SELECT IFNULL(MAX(corrida), 0) + 1 INTO v_corrida
    FROM orden_compra_validacion WHERE id_oc = p_id_oc AND id_propuesta = p_id_propuesta;

    INSERT INTO orden_compra_validacion (id_oc, id_propuesta, corrida, origen, resultado, coincidencias, advertencias,
                                         criticas, total_campos, detalle, conceptos, dictamen, insights, confianza,
                                         motor, sugerencia, fecha_validacion, id_usuario, creado_por)
    VALUES (p_id_oc, p_id_propuesta, v_corrida, p_origen, p_resultado, v_coinc, v_adv, v_crit, v_total,
            v_detalle, v_concep, v_dictamen, JSON_EXTRACT(p_eval_ia, '$.insights'),
            CAST(FN_JsonTexto(p_eval_ia, '$.confianza') AS DECIMAL(5,2)),
            IFNULL(FN_JsonTexto(p_eval_ia, '$.motor'), 'reglas'), p_sugerencia, NOW(), p_id_usuario, p_id_usuario);
    SET p_id_validacion = LAST_INSERT_ID();

    UPDATE oc_propuesta SET resultado_ia = p_resultado, id_validacion = p_id_validacion, modificado_por = p_id_usuario
    WHERE id_oc = p_id_oc AND id_propuesta = p_id_propuesta AND eliminado_en IS NULL;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion,
                                  id_usuario, registrado_en, metadata)
    VALUES ('orden_compra', p_id_oc, 'validacion_ia', NULL, p_resultado,
            CONCAT('Validación contra ', v_numero, ': ',
                   CASE p_resultado WHEN 'ok' THEN 'sin diferencias'
                        ELSE CONCAT(v_adv, ' advertencia(s) y ', v_crit, ' crítica(s)') END,
                   ' (', REPLACE(p_origen, '_', ' '), ').'),
            p_id_usuario, NOW(),
            JSON_OBJECT('id_validacion', p_id_validacion, 'id_propuesta', p_id_propuesta, 'corrida', v_corrida,
                        'origen', p_origen, 'coincidencias', v_coinc, 'advertencias', v_adv, 'criticas', v_crit,
                        'sugerencia', p_sugerencia));
END$$

DELIMITER ;
