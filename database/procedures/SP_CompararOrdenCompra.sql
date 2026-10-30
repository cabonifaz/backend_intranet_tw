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
--   5 hitos de pago de cada propuesta (ticket D): porcentaje, condición y días de crédito
-- p_id_oc_reemplaza ya no es necesario para las OC autogeneradas: al registrar, las OC-AUTO de las propuestas
--   vinculadas no descuentan el saldo (tickets A y B). Sigue sirviendo para la OC pendiente de reemplazo.
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
    SELECT e.orden, e.id_propuesta, e.numero, e.monto_asignado, e.monto_cubierto, e.resultado, e.coincidencias,
           e.advertencias, e.criticas, e.total_campos, e.sugerencia, p.id_moneda, m.String3 AS moneda, m.String2 AS moneda_simbolo
    FROM tmp_oc_eval e
    JOIN propuesta_comercial p ON p.id_propuesta = e.id_propuesta
    LEFT JOIN tabla_maestra m  ON m.IdMaestro = 1 AND m.IdEmpresa = 1 AND m.Num1 = p.id_moneda
    ORDER BY e.orden;

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

    -- 5. Hitos de pago (CREDITO_NN → NN días; CONTADO → 0)
    SELECT f.id_propuesta, f.porcentaje,
           IFNULL((SELECT MAX(tm.String1) FROM tabla_maestra tm WHERE tm.IdMaestro = 39 AND tm.IdEmpresa = 1
                     AND tm.String2 = f.condicion AND tm.eliminado_en IS NULL), f.condicion) AS condicion,
           f.condicion AS codigo,
           CASE WHEN f.condicion = 'CONTADO' THEN 0
                WHEN f.condicion REGEXP '^CREDITO_[0-9]+$' THEN CAST(SUBSTRING(f.condicion, 9) AS UNSIGNED) END AS dias_credito
    FROM propuesta_forma_pago f
    WHERE f.id_propuesta IN (SELECT id_propuesta FROM tmp_oc_eval)
    ORDER BY f.id_propuesta, f.orden, f.id;

    DROP TEMPORARY TABLE IF EXISTS tmp_oc_eval;
END$$

DELIMITER ;
