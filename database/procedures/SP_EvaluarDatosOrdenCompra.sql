-- HU-23 (Sprint 4) Valida los datos de la ficha de la OC y la compara contra cada propuesta vinculada. Uso interno.
-- Lo usan la comparación en vivo, el registro y la edición. Deja el resultado por propuesta en tmp_oc_eval.
--
-- p_id_oc: OC que se edita (NULL al registrar). p_excluir_oc: OC cuya asignación no descuenta el saldo de las
--   propuestas (la que se edita o la que se reemplaza).
-- Al registrar (p_id_oc NULL) las OC autogeneradas (OC-AUTO) vigentes no descuentan el saldo de ninguna propuesta
--   vinculada: SP_RegistrarOrdenCompra las da de baja (tickets A y B, multi-propuesta).
-- tmp_oc_eval.monto_cubierto: el monto asignado en la moneda de la propuesta (con el tipo de cambio, ticket E).
-- p_datos: numeroOc, fechaEmision, fechaRecepcion, idMoneda, montoTotal, idCondicionPago, formaPago, igvIncluido,
--   igvPct, descuento, ruc, razonSocial, numeroPropuesta, vigenciaHasta, referencia, observaciones,
--   facturaIgualOc, tipoCambio (soles por 1 unidad de moneda extranjera), conceptos [...]
-- p_vinculaciones: [{idPropuesta, montoAsignado}] (al menos una; la primera es la propuesta de origen).
--   Sin p_decision (validación en vivo) se acepta monto 0; al registrar o editar debe ser mayor a 0.
-- p_evaluaciones_ia: [{idPropuesta, conceptos, dictamen, insights, confianza, motor}] (opcional)
-- p_decision (opcional, valida que se pueda tomar):
--   validar             sin diferencias críticas
--   observar            "Guardar con observaciones": sin diferencias críticas
--   correccion_cliente  "Solicitar corrección al cliente": siempre
--   nueva_version       "Generar nueva versión de propuesta": factura igual a la OC, sin críticas y con diferencias
-- OUT p_error: NULL si todo es válido; si no, el mensaje para el usuario.
DROP PROCEDURE IF EXISTS SP_EvaluarDatosOrdenCompra;

DELIMITER $$

CREATE PROCEDURE SP_EvaluarDatosOrdenCompra(
    IN  p_id_usuario       BIGINT,
    IN  p_id_oc            BIGINT,
    IN  p_excluir_oc       BIGINT,
    IN  p_id_cliente       BIGINT,
    IN  p_datos            JSON,
    IN  p_vinculaciones    JSON,
    IN  p_evaluaciones_ia  JSON,
    IN  p_decision         VARCHAR(30),
    OUT p_error            VARCHAR(500)
)
proc: BEGIN
    DECLARE v_numero_oc   VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_fecha_emi   DATE;
    DECLARE v_fecha_rec   DATE;
    DECLARE v_id_moneda   INT;
    DECLARE v_monto       DECIMAL(16,2);
    DECLARE v_id_cond     INT;
    DECLARE v_ruc         VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_factura     TINYINT;
    DECLARE v_n           INT DEFAULT 0;
    DECLARE v_i           INT DEFAULT 0;
    DECLARE v_id_prop     BIGINT;
    DECLARE v_asignado    DECIMAL(16,2);
    DECLARE v_suma        DECIMAL(16,2) DEFAULT 0;
    DECLARE v_eval        JSON;
    DECLARE v_numero_prop VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_res         VARCHAR(20);
    DECLARE v_coinc       INT;
    DECLARE v_adv         INT;
    DECLARE v_crit        INT;
    DECLARE v_tot         INT;
    DECLARE v_sug         VARCHAR(30);
    DECLARE v_criticas    INT;
    DECLARE v_no_ok       INT;
    DECLARE v_datos       JSON;
    DECLARE v_sin_auto    TINYINT;
    DECLARE v_cubierto    DECIMAL(14,2);
    DECLARE v_tc_txt      VARCHAR(40);

    SET p_error = NULL;
    SET v_sin_auto = IF(IFNULL(p_id_oc, 0) = 0, 1, 0);

    DROP TEMPORARY TABLE IF EXISTS tmp_oc_eval;
    CREATE TEMPORARY TABLE tmp_oc_eval (
        orden           INT,
        id_propuesta    BIGINT,
        numero          VARCHAR(40),
        monto_asignado  DECIMAL(14,2),
        monto_cubierto  DECIMAL(14,2),
        resultado       VARCHAR(20),
        coincidencias   INT,
        advertencias    INT,
        criticas        INT,
        total_campos    INT,
        sugerencia      VARCHAR(30),
        detalle         JSON,
        eval_ia         JSON
    ) DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;

    -- ── Datos de la OC ──────────────────────────────────────────────────
    SET v_numero_oc = FN_JsonTexto(p_datos, '$.numeroOc');
    SET v_fecha_emi = STR_TO_DATE(LEFT(FN_JsonTexto(p_datos, '$.fechaEmision'), 10), '%Y-%m-%d');
    SET v_fecha_rec = STR_TO_DATE(LEFT(FN_JsonTexto(p_datos, '$.fechaRecepcion'), 10), '%Y-%m-%d');
    SET v_id_moneda = CAST(FN_JsonTexto(p_datos, '$.idMoneda') AS SIGNED);
    SET v_monto     = CAST(FN_JsonTexto(p_datos, '$.montoTotal') AS DECIMAL(16,2));
    SET v_id_cond   = CAST(FN_JsonTexto(p_datos, '$.idCondicionPago') AS SIGNED);
    SET v_ruc       = FN_JsonTexto(p_datos, '$.ruc');
    SET v_factura   = IF(LOWER(IFNULL(FN_JsonTexto(p_datos, '$.facturaIgualOc'), 'true')) IN ('false', '0'), 0, 1);

    IF v_numero_oc IS NULL THEN
        SET p_error = 'Ingrese el número de la orden de compra.'; LEAVE proc;
    END IF;
    IF CHAR_LENGTH(v_numero_oc) > 50 THEN
        SET p_error = 'El número de la orden de compra admite hasta 50 caracteres.'; LEAVE proc;
    END IF;
    IF UPPER(v_numero_oc) LIKE 'OC-AUTO-%' THEN
        SET p_error = 'El prefijo OC-AUTO está reservado para las órdenes de compra autogeneradas.'; LEAVE proc;
    END IF;
    IF EXISTS (SELECT 1 FROM orden_compra
               WHERE id_cliente = p_id_cliente AND numero_oc = v_numero_oc AND estado <> 'anulada'
                 AND eliminado_en IS NULL AND reemplazada_por IS NULL
                 AND id_oc <> IFNULL(p_id_oc, 0) AND id_oc <> IFNULL(p_excluir_oc, 0)) THEN
        SET p_error = CONCAT('Ya existe la orden de compra ', v_numero_oc, ' registrada para este cliente.'); LEAVE proc;
    END IF;
    IF v_fecha_emi IS NULL OR v_fecha_emi > CURDATE() THEN
        SET p_error = 'Indique la fecha de emisión de la orden de compra (no puede ser futura).'; LEAVE proc;
    END IF;
    IF v_fecha_rec IS NULL OR v_fecha_rec > CURDATE() THEN
        SET p_error = 'Indique la fecha de recepción (no puede ser futura).'; LEAVE proc;
    END IF;
    IF v_fecha_rec < v_fecha_emi THEN
        SET p_error = 'La fecha de recepción no puede ser anterior a la fecha de emisión de la orden de compra.'; LEAVE proc;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM tabla_maestra WHERE IdMaestro = 1 AND IdEmpresa = 1 AND Num1 = v_id_moneda
                     AND eliminado_en IS NULL) THEN
        SET p_error = 'Seleccione la moneda de la orden de compra.'; LEAVE proc;
    END IF;
    IF v_monto IS NULL OR v_monto <= 0 OR v_monto > 999999999999 THEN
        SET p_error = 'Ingrese el monto total de la orden de compra (mayor a 0).'; LEAVE proc;
    END IF;
    IF v_id_cond IS NOT NULL AND NOT EXISTS (SELECT 1 FROM tabla_maestra WHERE IdMaestro = 39 AND IdEmpresa = 1
                                               AND Num1 = v_id_cond AND eliminado_en IS NULL) THEN
        SET p_error = 'La condición de pago no es válida.'; LEAVE proc;
    END IF;
    IF v_ruc IS NOT NULL AND REGEXP_REPLACE(v_ruc, '[^0-9]', '') NOT REGEXP '^[0-9]{11}$' THEN
        SET p_error = 'El RUC de la orden de compra debe tener 11 dígitos.'; LEAVE proc;
    END IF;
    IF CHAR_LENGTH(IFNULL(FN_JsonTexto(p_datos, '$.referencia'), '')) > 200 THEN
        SET p_error = 'La referencia admite hasta 200 caracteres.'; LEAVE proc;
    END IF;
    IF CHAR_LENGTH(IFNULL(FN_JsonTexto(p_datos, '$.observaciones'), '')) > 500 THEN
        SET p_error = 'Las observaciones admiten hasta 500 caracteres.'; LEAVE proc;
    END IF;
    IF CHAR_LENGTH(IFNULL(FN_JsonTexto(p_datos, '$.formaPago'), '')) > 150
       OR CHAR_LENGTH(IFNULL(FN_JsonTexto(p_datos, '$.razonSocial'), '')) > 300
       OR CHAR_LENGTH(IFNULL(FN_JsonTexto(p_datos, '$.numeroPropuesta'), '')) > 50 THEN
        SET p_error = 'Algún dato extraído de la OC es demasiado largo (forma de pago, razón social o N° de propuesta).'; LEAVE proc;
    END IF;
    SET v_tc_txt = FN_JsonTexto(p_datos, '$.tipoCambio');
    IF v_tc_txt IS NOT NULL AND (v_tc_txt NOT REGEXP '^[0-9]+(\\.[0-9]+)?$' OR CAST(v_tc_txt AS DECIMAL(12,6)) <= 0
                                 OR CAST(v_tc_txt AS DECIMAL(12,6)) > 100000) THEN
        SET p_error = 'El tipo de cambio debe ser un número mayor a 0 (soles por 1 unidad de la moneda extranjera).'; LEAVE proc;
    END IF;
    IF JSON_EXTRACT(p_datos, '$.conceptos') IS NOT NULL AND JSON_TYPE(JSON_EXTRACT(p_datos, '$.conceptos')) NOT IN ('ARRAY', 'NULL') THEN
        SET p_error = 'Los conceptos de la OC deben ser una lista.'; LEAVE proc;
    END IF;

    -- ── Propuestas vinculadas ───────────────────────────────────────────
    IF p_vinculaciones IS NULL OR JSON_TYPE(p_vinculaciones) <> 'ARRAY' OR JSON_LENGTH(p_vinculaciones) = 0 THEN
        SET p_error = 'Vincule al menos una propuesta a la orden de compra.'; LEAVE proc;
    END IF;
    IF JSON_LENGTH(p_vinculaciones) > 20 THEN
        SET p_error = 'Una orden de compra admite hasta 20 propuestas vinculadas.'; LEAVE proc;
    END IF;

    CALL SP_CalcularPropuestasDisponiblesOc(p_id_usuario, p_id_cliente, p_excluir_oc, v_sin_auto);

    -- Números de las propuestas vinculadas (la OC puede referenciar cualquiera de ellas)
    SET v_datos = JSON_SET(IFNULL(p_datos, JSON_OBJECT()), '$._propuestasVinculadas',
                           (SELECT IFNULL(JSON_ARRAYAGG(px.numero), JSON_ARRAY())
                            FROM JSON_TABLE(p_vinculaciones, '$[*]' COLUMNS (id BIGINT PATH '$.idPropuesta')) jv
                            JOIN propuesta_comercial px ON px.id_propuesta = jv.id));
    -- Ids de todas las vinculadas: con 2 o más, el monto se valida contra la suma de sus saldos (SP_CompararOcPropuesta)
    SET v_datos = JSON_SET(v_datos, '$._idsVinculadas',
                           (SELECT IFNULL(JSON_ARRAYAGG(jv.id), JSON_ARRAY())
                            FROM JSON_TABLE(p_vinculaciones, '$[*]' COLUMNS (id BIGINT PATH '$.idPropuesta')) jv
                            WHERE jv.id > 0));

    SET v_n = JSON_LENGTH(p_vinculaciones);
    WHILE v_i < v_n DO
        SET v_id_prop  = CAST(FN_JsonTexto(p_vinculaciones, CONCAT('$[', v_i, '].idPropuesta')) AS SIGNED);
        SET v_asignado = CAST(FN_JsonTexto(p_vinculaciones, CONCAT('$[', v_i, '].montoAsignado')) AS DECIMAL(16,2));

        IF v_id_prop IS NULL OR v_id_prop <= 0 THEN
            SET p_error = 'Hay una propuesta vinculada sin indicar.';
        ELSEIF EXISTS (SELECT 1 FROM tmp_oc_eval WHERE id_propuesta = v_id_prop) THEN
            SET p_error = 'Una propuesta está vinculada dos veces.';
        ELSEIF NOT EXISTS (SELECT 1 FROM tmp_oc_disp WHERE id_propuesta = v_id_prop)
               -- Al editar, las propuestas que ya estaban vinculadas se conservan aunque ya no tengan saldo
               AND NOT EXISTS (SELECT 1 FROM oc_propuesta op JOIN propuesta_comercial px ON px.id_propuesta = op.id_propuesta
                               WHERE op.id_oc = IFNULL(p_id_oc, 0) AND op.id_propuesta = v_id_prop
                                 AND op.eliminado_en IS NULL AND px.id_cliente = p_id_cliente) THEN
            SET p_error = CONCAT('La propuesta ',
                                 IFNULL((SELECT CONCAT(numero, ' v', version) FROM propuesta_comercial WHERE id_propuesta = v_id_prop), v_id_prop),
                                 ' no está aceptada por el cliente, es de otro cliente o ya está cubierta por órdenes de compra.');
        -- En la validación en vivo (sin decisión) el monto 0 es válido: el comercial aún lo está repartiendo
        ELSEIF p_decision IS NOT NULL AND (v_asignado IS NULL OR v_asignado <= 0) THEN
            SET p_error = 'Indique el monto asignado a cada propuesta vinculada (mayor a 0).';
        ELSEIF v_asignado < 0 THEN
            SET p_error = 'El monto asignado a una propuesta no puede ser negativo.';
        END IF;
        IF p_error IS NOT NULL THEN
            DROP TEMPORARY TABLE IF EXISTS tmp_oc_disp;
            LEAVE proc;
        END IF;

        SET v_asignado = IFNULL(v_asignado, 0);
        SET v_suma = v_suma + v_asignado;

        SET v_eval = NULL;
        IF p_evaluaciones_ia IS NOT NULL AND JSON_TYPE(p_evaluaciones_ia) = 'ARRAY' THEN
            SELECT j.obj INTO v_eval
            FROM JSON_TABLE(p_evaluaciones_ia, '$[*]' COLUMNS (id BIGINT PATH '$.idPropuesta', obj JSON PATH '$')) j
            WHERE j.id = v_id_prop
            LIMIT 1;
        END IF;

        CALL SP_CompararOcPropuesta(v_id_prop, p_excluir_oc, v_sin_auto, v_datos, v_asignado, v_eval,
                                    v_res, v_coinc, v_adv, v_crit, v_tot, v_sug, v_cubierto);

        SELECT CONCAT(numero, ' v', version) INTO v_numero_prop FROM propuesta_comercial WHERE id_propuesta = v_id_prop;

        INSERT INTO tmp_oc_eval
        SELECT v_i + 1, v_id_prop, v_numero_prop, v_asignado, v_cubierto, v_res, v_coinc, v_adv, v_crit, v_tot, v_sug,
               (SELECT JSON_ARRAYAGG(JSON_OBJECT('orden', orden, 'campo', campo, 'etiqueta', etiqueta, 'valorOc', valor_oc,
                                                 'valorPropuesta', valor_propuesta, 'severidad', severidad,
                                                 'mensaje', mensaje, 'accion', accion))
                FROM tmp_oc_cmp),
               v_eval;

        SET v_i = v_i + 1;
    END WHILE;

    DROP TEMPORARY TABLE IF EXISTS tmp_oc_disp;
    DROP TEMPORARY TABLE IF EXISTS tmp_oc_cmp;

    IF v_suma > v_monto + 0.009 THEN
        SET p_error = CONCAT('Lo asignado a las propuestas (', FORMAT(v_suma, 2), ') supera el monto total de la OC (',
                             FORMAT(v_monto, 2), ').');
        LEAVE proc;
    END IF;

    -- ── Decisión del comercial ──────────────────────────────────────────
    IF p_decision IS NOT NULL THEN
        SELECT IFNULL(SUM(resultado = 'critico'), 0), IFNULL(SUM(resultado <> 'ok'), 0) INTO v_criticas, v_no_ok
        FROM tmp_oc_eval;

        IF p_decision NOT IN ('validar', 'observar', 'correccion_cliente', 'nueva_version') THEN
            SET p_error = 'Indique qué hacer con la orden de compra: validar, guardar con observaciones, solicitar corrección o generar nueva versión.';
        -- Moneda distinta sin conversión: no se puede guardar (el saldo de la propuesta quedaría en otra moneda)
        ELSEIF EXISTS (SELECT 1 FROM tmp_oc_eval e JOIN propuesta_comercial p ON p.id_propuesta = e.id_propuesta
                       WHERE p.id_moneda <> v_id_moneda AND e.monto_cubierto IS NULL) THEN
            SET p_error = 'Hay propuestas vinculadas en otra moneda que la OC: indique el tipo de cambio (soles por 1 unidad de la moneda extranjera). Entre dos monedas extranjeras no se puede convertir.';
        ELSEIF p_decision IN ('validar', 'observar', 'nueva_version') AND v_criticas > 0 THEN
            SET p_error = 'Hay diferencias críticas con la propuesta: solo se puede solicitar la corrección al cliente.';
        ELSEIF p_decision = 'nueva_version' AND v_factura = 0 THEN
            SET p_error = 'Para generar una nueva versión de la propuesta marque "¿La factura tendrá lo mismo que la OC?". Si no, solicite la corrección al cliente.';
        ELSEIF p_decision = 'nueva_version' AND v_no_ok = 0 THEN
            SET p_error = 'No hay diferencias con las propuestas: no hace falta generar una nueva versión.';
        END IF;
    END IF;
END$$

DELIMITER ;
