-- HU-23 (Sprint 4) Validación en vivo de la ficha de la OC contra sus propuestas vinculadas, sin guardar.
-- Alimenta el panel "Validación IA" de la ficha y el botón "Re-validar". También la usa el registro/edición
-- para validar los datos antes de guardar el PDF (p_decision indica el botón que se presionó).
-- p_id_oc: OC que se edita (NULL al registrar). p_id_propuesta: propuesta de origen (al registrar).
-- p_id_oc_reemplaza: OC autogenerada que se reemplaza (al registrar, HU-27).
-- Resultados:
--   1 mensaje
--   2 resumen: resultado global, sugerencia y decisiones permitidas (los botones de la ficha)
--   3 por propuesta: resultado, coincidencias, advertencias, críticas y sugerencia
--   4 detalle por propuesta y campo: valor en la OC, valor en la propuesta, severidad, mensaje y acción
DROP PROCEDURE IF EXISTS SP_CompararOrdenCompra;

DELIMITER $$

CREATE PROCEDURE SP_CompararOrdenCompra(
    IN p_id_usuario       BIGINT,
    IN p_id_oc            BIGINT,
    IN p_id_propuesta     BIGINT,
    IN p_id_oc_reemplaza  BIGINT,
    IN p_datos            JSON,
    IN p_vinculaciones    JSON,
    IN p_evaluaciones_ia  JSON,
    IN p_decision         VARCHAR(30)
)
proc: BEGIN
    DECLARE v_id_cliente BIGINT;
    DECLARE v_error      VARCHAR(500);
    DECLARE v_factura    TINYINT;
    DECLARE v_criticas   INT;
    DECLARE v_no_ok      INT;
    DECLARE v_no_nv      INT;
    DECLARE v_sum_crit   INT;
    DECLARE v_sum_adv    INT;

    IF FN_PermisoAccion(p_id_usuario, IF(IFNULL(p_id_oc, 0) > 0, 'oc_editar', 'oc_registrar')) = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para registrar o editar órdenes de compra.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF IFNULL(p_id_oc, 0) > 0 THEN
        SELECT id_cliente INTO v_id_cliente FROM orden_compra WHERE id_oc = p_id_oc AND eliminado_en IS NULL;
    ELSE
        SELECT id_cliente INTO v_id_cliente FROM propuesta_comercial WHERE id_propuesta = p_id_propuesta;
    END IF;
    IF v_id_cliente IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'La orden de compra o la propuesta no existe.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_EvaluarDatosOrdenCompra(p_id_usuario, p_id_oc, IF(IFNULL(p_id_oc, 0) > 0, p_id_oc, p_id_oc_reemplaza),
                                    v_id_cliente, p_datos, p_vinculaciones, p_evaluaciones_ia, p_decision, v_error);
    IF v_error IS NOT NULL THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_oc_eval;
        SELECT 1 AS IdTipoMensaje, v_error AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_factura = IF(LOWER(IFNULL(FN_JsonTexto(p_datos, '$.facturaIgualOc'), 'true')) IN ('false', '0'), 0, 1);
    SELECT IFNULL(SUM(resultado = 'critico'), 0), IFNULL(SUM(resultado <> 'ok'), 0),
           IFNULL(SUM(resultado <> 'ok' AND sugerencia <> 'nueva_version'), 0),
           IFNULL(SUM(criticas), 0), IFNULL(SUM(advertencias), 0)
      INTO v_criticas, v_no_ok, v_no_nv, v_sum_crit, v_sum_adv
    FROM tmp_oc_eval;

    -- 1. Header
    SELECT 2 AS IdTipoMensaje, 'Validado.' AS Mensaje;

    -- 2. Resumen y decisiones permitidas
    SELECT CASE WHEN v_criticas > 0 THEN 'critico' WHEN v_no_ok > 0 THEN 'advertencia' ELSE 'ok' END AS resultado,
           CASE WHEN v_criticas > 0 THEN 'correccion_cliente'
                WHEN v_no_ok = 0    THEN 'validar'
                WHEN v_no_nv = 0    THEN 'nueva_version'
                ELSE                     'correccion_cliente' END                                    AS sugerencia,
           v_sum_crit                                                                               AS criticas,
           v_sum_adv                                                                                AS advertencias,
           (v_criticas = 0)                                                                         AS puede_validar,
           (v_criticas = 0)                                                                         AS puede_observar,
           1                                                                                        AS puede_solicitar_correccion,
           (v_criticas = 0 AND v_no_ok > 0 AND v_factura = 1)                                       AS puede_nueva_version;

    -- 3. Por propuesta
    SELECT orden, id_propuesta, numero, monto_asignado, resultado, coincidencias, advertencias, criticas,
           total_campos, sugerencia
    FROM tmp_oc_eval ORDER BY orden;

    -- 4. Detalle por campo
    SELECT e.id_propuesta, d.orden, d.campo, d.etiqueta, d.valor_oc, d.valor_propuesta, d.severidad, d.mensaje, d.accion
    FROM tmp_oc_eval e
    JOIN JSON_TABLE(e.detalle, '$[*]' COLUMNS (
            orden           INT          PATH '$.orden',
            campo           VARCHAR(30)  PATH '$.campo',
            etiqueta        VARCHAR(60)  PATH '$.etiqueta',
            valor_oc        VARCHAR(400) PATH '$.valorOc',
            valor_propuesta VARCHAR(400) PATH '$.valorPropuesta',
            severidad       VARCHAR(15)  PATH '$.severidad',
            mensaje         VARCHAR(400) PATH '$.mensaje',
            accion          VARCHAR(200) PATH '$.accion')) d
    ORDER BY e.orden, d.orden;

    DROP TEMPORARY TABLE IF EXISTS tmp_oc_eval;
END$$

DELIMITER ;
