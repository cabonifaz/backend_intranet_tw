-- HU-23 (Sprint 4) Aplica la decisión del comercial a las vinculaciones de la OC. Uso interno, sin resultados.
-- Usa el resultado de la última validación de cada vinculación (oc_propuesta.resultado_ia). La decisión ya fue
-- validada por SP_EvaluarDatosOrdenCompra.
--   validar             todas las vinculaciones → validada
--   observar            ok → validada; con diferencias → observada (informativa)
--   correccion_cliente  ok → validada; con diferencias → observada (corrección del cliente);
--                       si ninguna tiene diferencias, todas quedan observadas (pedido expreso del comercial)
--   nueva_version       ok → validada; con diferencias → observada (nueva versión de propuesta)
-- Luego recalcula el estado de la OC y pasa a Programación los expedientes con vinculación validada.
DROP PROCEDURE IF EXISTS SP_AplicarDecisionOrdenCompra;

DELIMITER $$

CREATE PROCEDURE SP_AplicarDecisionOrdenCompra(
    IN p_id_oc      BIGINT,
    IN p_decision   VARCHAR(30),
    IN p_id_usuario BIGINT
)
BEGIN
    DECLARE v_no_ok INT DEFAULT 0;
    DECLARE v_resumen VARCHAR(600) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    SELECT IFNULL(SUM(IFNULL(resultado_ia, 'ok') <> 'ok'), 0) INTO v_no_ok
    FROM oc_propuesta WHERE id_oc = p_id_oc AND eliminado_en IS NULL;

    UPDATE oc_propuesta
    SET estado_validacion = CASE
            WHEN p_decision = 'validar'                                      THEN 'validada'
            WHEN p_decision = 'correccion_cliente' AND v_no_ok = 0           THEN 'observada'
            WHEN IFNULL(resultado_ia, 'ok') = 'ok'                           THEN 'validada'
            ELSE                                                                  'observada'
        END,
        tipo_observacion = CASE
            WHEN p_decision = 'validar'                                      THEN NULL
            WHEN p_decision = 'correccion_cliente' AND v_no_ok = 0           THEN 'correccion_cliente'
            WHEN IFNULL(resultado_ia, 'ok') = 'ok'                           THEN NULL
            WHEN p_decision = 'observar'                                     THEN 'informativa'
            ELSE                                                                  p_decision
        END,
        id_propuesta_nueva_version = IF(p_decision = 'nueva_version', id_propuesta_nueva_version, NULL),
        fecha_decision = NOW(),
        decidido_por   = p_id_usuario,
        modificado_por = p_id_usuario
    WHERE id_oc = p_id_oc AND eliminado_en IS NULL;

    SELECT GROUP_CONCAT(CONCAT(p.numero, ' v', p.version, ': ', UPPER(op.estado_validacion),
                               IFNULL(CONCAT(' (', REPLACE(op.tipo_observacion, '_', ' '), ')'), ''))
                        ORDER BY op.id SEPARATOR ', ')
      INTO v_resumen
    FROM oc_propuesta op JOIN propuesta_comercial p ON p.id_propuesta = op.id_propuesta
    WHERE op.id_oc = p_id_oc AND op.eliminado_en IS NULL;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion,
                                  id_usuario, registrado_en, metadata)
    VALUES ('orden_compra', p_id_oc, 'decision_oc', NULL, p_decision,
            CONCAT(CASE p_decision
                       WHEN 'validar'            THEN 'Guardar y validar'
                       WHEN 'observar'           THEN 'Guardar con observaciones'
                       WHEN 'correccion_cliente' THEN 'Solicitar corrección al cliente'
                       WHEN 'nueva_version'      THEN 'Generar nueva versión de propuesta'
                       ELSE p_decision END, '. ', IFNULL(v_resumen, '')),
            p_id_usuario, NOW(), JSON_OBJECT('decision', p_decision));

    CALL SP_RecalcularEstadoOrdenCompra(p_id_oc, p_id_usuario);
    CALL SP_PasarExpedientesAProgramacion(p_id_oc, p_id_usuario);
END$$

DELIMITER ;
