-- HU-23/24 (Sprint 4) Compara los datos de una orden de compra contra UNA propuesta. Uso interno.
-- Deja el resultado en la tabla temporal tmp_oc_cmp (la recrea en cada llamada) y en los parámetros OUT.
--
-- p_datos (JSON con los datos de la OC, extraídos por la IA o corregidos a mano):
--   ruc, razonSocial, numeroPropuesta, idMoneda, idCondicionPago, formaPago, igvIncluido (true/false),
--   fechaEmision (AAAA-MM-DD), conceptos [{descripcion, cantidad, precioUnitario, subtotal}], facturaIgualOc
-- p_monto_asignado: lo que la OC asigna a esta propuesta.
-- p_excluir_oc: la OC que se edita (su propia asignación no descuenta el saldo de la propuesta).
-- p_sin_autogenerada = 1 al registrar la OC real del cliente: las OC-AUTO vigentes no descuentan el saldo (se dan de
--   baja al registrar, ticket A).
-- p_datos.tipoCambio (ticket E): soles por 1 unidad de la moneda extranjera. Si la OC está en otra moneda que la
--   propuesta, el monto asignado (en la moneda de la OC) se convierte a la moneda de la propuesta con ese tipo de cambio.
--   Sin tipo de cambio la moneda distinta es crítica ("Tipo de cambio obligatorio"). Entre dos monedas extranjeras
--   (USD y COP, por ejemplo) un solo tipo de cambio en soles no alcanza: también es crítica.
-- OUT p_monto_cubierto: el monto asignado convertido a la moneda de la propuesta (NULL si es la misma moneda o no se
--   pudo convertir). Es lo que descuenta del saldo de la propuesta (oc_propuesta.monto_cubierto).
-- p_eval_ia (opcional): evaluación de la IA para esta propuesta:
--   { conceptos: [{descripcion, montoOc, montoPropuesta, estado}], dictamen, insights: [...], confianza, motor }
--   estado del concepto: coincide | falta_en_oc | adicional_en_oc | monto_distinto
--
-- Severidad por campo: ok, advertencia, critico, sin_dato (la OC no trae el dato; no suma ni resta).
--   critico:     cliente (RUC) distinto, moneda distinta sin tipo de cambio (o no convertible)
--   advertencia: N° de propuesta referenciado distinto, monto distinto al saldo de la propuesta (el monto
--                alerta pero nunca bloquea), condición de pago distinta a los hitos de pago de la propuesta
--                (ticket D), IGV distinto, OC emitida después del vencimiento de la propuesta, conceptos distintos
-- Forma de pago (ticket D): la condición de la OC se compara con los hitos de la propuesta (propuesta_forma_pago).
--   Coincide si todos los hitos tienen esa condición (ej. 100% Crédito 30 días) o si la OC dice "50% adelanto + 50%
--   contra entrega" y la propuesta tiene dos hitos de 50% con el primero al contado. Sin hitos, se compara con la
--   condición de pago de la propuesta (como antes).
-- Resultado: critico si hay alguno crítico, advertencia si hay alguna advertencia, ok si no.
-- Sugerencia (la IA no decide, solo sugiere):
--   validar             sin diferencias
--   nueva_version       las únicas diferencias son de conceptos y la factura tendrá lo mismo que la OC
--   correccion_cliente  cualquier otra diferencia
DROP PROCEDURE IF EXISTS SP_CompararOcPropuesta;

DELIMITER $$

CREATE PROCEDURE SP_CompararOcPropuesta(
    IN  p_id_propuesta    BIGINT,
    IN  p_excluir_oc      BIGINT,
    IN  p_sin_autogenerada TINYINT,
    IN  p_datos           JSON,
    IN  p_monto_asignado  DECIMAL(14,2),
    IN  p_eval_ia         JSON,
    OUT p_resultado       VARCHAR(20),
    OUT p_coincidencias   INT,
    OUT p_advertencias    INT,
    OUT p_criticas        INT,
    OUT p_total           INT,
    OUT p_sugerencia      VARCHAR(30),
    OUT p_monto_cubierto  DECIMAL(14,2)
)
BEGIN
    DECLARE v_numero        VARCHAR(20)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_version       INT;
    DECLARE v_razon         VARCHAR(300)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_ruc           VARCHAR(20)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_moneda     INT;
    DECLARE v_moneda        VARCHAR(60)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_simbolo       VARCHAR(10)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_total         DECIMAL(14,2);
    DECLARE v_saldo         DECIMAL(14,2);
    DECLARE v_id_cond       INT;
    DECLARE v_cond          VARCHAR(100)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_aplica_igv    TINYINT;
    DECLARE v_igv_pct       DECIMAL(5,2);
    DECLARE v_expiracion    DATE;
    DECLARE v_items         INT;

    DECLARE o_ruc           VARCHAR(20)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE o_razon         VARCHAR(300)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE o_num_prop      VARCHAR(50)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE o_id_moneda     INT;
    DECLARE o_moneda        VARCHAR(60)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE o_simbolo       VARCHAR(10)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE o_id_cond       INT;
    DECLARE o_cond          VARCHAR(150)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE o_igv_txt       VARCHAR(10)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE o_igv           TINYINT;
    DECLARE o_fecha         DATE;
    DECLARE o_conceptos     INT DEFAULT 0;
    DECLARE o_factura_igual TINYINT DEFAULT 1;

    DECLARE v_dif_conceptos INT DEFAULT 0;
    DECLARE v_conc_ok       INT DEFAULT 0;
    DECLARE v_conc_total    INT DEFAULT 0;
    DECLARE v_otras_adv     INT DEFAULT 0;
    DECLARE v_diferencia    DECIMAL(14,2);
    DECLARE v_ref_esta      TINYINT DEFAULT 0;
    DECLARE v_ref_otra      TINYINT DEFAULT 0;
    DECLARE v_items_en_oc   INT DEFAULT 0;
    -- Ticket E: tipo de cambio
    DECLARE v_cod_moneda    VARCHAR(10)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE o_cod_moneda    VARCHAR(10)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE o_tc            DECIMAL(12,6);
    DECLARE v_factor        DECIMAL(24,12);
    DECLARE v_monto_conv    DECIMAL(14,2);
    DECLARE v_misma_moneda  TINYINT DEFAULT 1;
    -- Ticket D: hitos de pago
    DECLARE v_n_hitos       INT DEFAULT 0;
    DECLARE v_hitos_txt     VARCHAR(600)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_hitos_cond    INT DEFAULT 0;
    DECLARE v_hitos_ok      TINYINT DEFAULT 0;
    DECLARE o_cod_cond      VARCHAR(40)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    -- Propuesta
    SELECT p.numero, p.version, c.razon_social, c.ruc, p.id_moneda,
           (SELECT MAX(m.String1) FROM tabla_maestra m WHERE m.IdMaestro = 1 AND m.IdEmpresa = 1 AND m.Num1 = p.id_moneda),
           (SELECT MAX(m.String2) FROM tabla_maestra m WHERE m.IdMaestro = 1 AND m.IdEmpresa = 1 AND m.Num1 = p.id_moneda),
           (SELECT MAX(m.String3) FROM tabla_maestra m WHERE m.IdMaestro = 1 AND m.IdEmpresa = 1 AND m.Num1 = p.id_moneda),
           p.total, p.id_condicion_pago,
           (SELECT MAX(cp.String1) FROM tabla_maestra cp WHERE cp.IdMaestro = 39 AND cp.IdEmpresa = 1 AND cp.Num1 = p.id_condicion_pago),
           p.aplica_igv, p.igv_pct, p.fecha_expiracion
      INTO v_numero, v_version, v_razon, v_ruc, v_id_moneda, v_moneda, v_simbolo, v_cod_moneda, v_total,
           v_id_cond, v_cond, v_aplica_igv, v_igv_pct, v_expiracion
    FROM propuesta_comercial p
    JOIN cliente c ON c.id_cliente = p.id_cliente
    WHERE p.id_propuesta = p_id_propuesta;

    SET v_saldo = IF(IFNULL(p_sin_autogenerada, 0) = 1, FN_SaldoPropuestaOcSinAutogenerada(p_id_propuesta, p_excluir_oc),
                     FN_SaldoPropuestaOc(p_id_propuesta, p_excluir_oc));
    SELECT COUNT(*) INTO v_items FROM propuesta_item
    WHERE id_propuesta = p_id_propuesta AND seccion = 'principal' AND IFNULL(es_espaciado, 0) = 0;

    -- Datos de la OC
    SET o_ruc       = REGEXP_REPLACE(IFNULL(FN_JsonTexto(p_datos, '$.ruc'), ''), '[^0-9]', '');
    SET o_ruc       = NULLIF(o_ruc, '');
    SET o_razon     = FN_JsonTexto(p_datos, '$.razonSocial');
    SET o_num_prop  = FN_JsonTexto(p_datos, '$.numeroPropuesta');
    SET o_id_moneda = CAST(FN_JsonTexto(p_datos, '$.idMoneda') AS SIGNED);
    SET o_id_cond   = CAST(FN_JsonTexto(p_datos, '$.idCondicionPago') AS SIGNED);
    SET o_cond      = FN_JsonTexto(p_datos, '$.formaPago');
    SET o_igv_txt   = LOWER(IFNULL(FN_JsonTexto(p_datos, '$.igvIncluido'), ''));
    SET o_igv       = CASE WHEN o_igv_txt IN ('true', '1') THEN 1 WHEN o_igv_txt IN ('false', '0') THEN 0 ELSE NULL END;
    SET o_fecha     = STR_TO_DATE(LEFT(FN_JsonTexto(p_datos, '$.fechaEmision'), 10), '%Y-%m-%d');
    SET o_conceptos = IFNULL(JSON_LENGTH(JSON_EXTRACT(p_datos, '$.conceptos')), 0);
    SET o_factura_igual = IF(LOWER(IFNULL(FN_JsonTexto(p_datos, '$.facturaIgualOc'), 'true')) IN ('false', '0'), 0, 1);

    SELECT MAX(String1), MAX(String2), MAX(String3) INTO o_moneda, o_simbolo, o_cod_moneda
    FROM tabla_maestra WHERE IdMaestro = 1 AND IdEmpresa = 1 AND Num1 = o_id_moneda;
    IF o_id_cond IS NOT NULL THEN
        SELECT MAX(String1), MAX(String2) INTO o_cond, o_cod_cond
        FROM tabla_maestra WHERE IdMaestro = 39 AND IdEmpresa = 1 AND Num1 = o_id_cond;
    END IF;

    -- Tipo de cambio (soles por 1 unidad de moneda extranjera) y conversión del monto asignado a la moneda de la propuesta
    SET o_tc = CAST(FN_JsonTexto(p_datos, '$.tipoCambio') AS DECIMAL(12,6));
    IF o_tc IS NOT NULL AND o_tc <= 0 THEN SET o_tc = NULL; END IF;
    SET v_misma_moneda = (o_id_moneda IS NULL OR o_id_moneda = v_id_moneda);
    SET v_factor = CASE
        WHEN v_misma_moneda = 1        THEN 1
        WHEN o_tc IS NULL              THEN NULL
        WHEN o_cod_moneda = 'PEN'      THEN 1 / o_tc   -- OC en soles, propuesta en moneda extranjera
        WHEN v_cod_moneda = 'PEN'      THEN o_tc       -- OC en moneda extranjera, propuesta en soles
        ELSE NULL END;                                 -- dos monedas extranjeras: no se puede con un solo TC
    -- Se divide o multiplica directo por el TC (1 / TC precalculado pierde decimales en montos grandes)
    SET v_monto_conv = CASE
        WHEN v_factor IS NULL     THEN NULL
        WHEN v_misma_moneda = 1   THEN IFNULL(p_monto_asignado, 0)
        WHEN o_cod_moneda = 'PEN' THEN ROUND(IFNULL(p_monto_asignado, 0) / o_tc, 2)
        ELSE                           ROUND(IFNULL(p_monto_asignado, 0) * o_tc, 2) END;
    -- Redondeo de la conversión: si queda a menos de un céntimo de la OC del saldo, cubre el saldo exacto
    IF v_misma_moneda = 0 AND v_monto_conv IS NOT NULL
       AND ABS(v_monto_conv - v_saldo) <= 0.01 * GREATEST(1, v_factor) + 0.001 THEN
        SET v_monto_conv = v_saldo;
    END IF;
    SET p_monto_cubierto = IF(v_misma_moneda = 1, NULL, v_monto_conv);

    -- Hitos de pago de la propuesta (ticket D)
    SELECT COUNT(*),
           LEFT(GROUP_CONCAT(CONCAT(TRIM(TRAILING '.' FROM TRIM(TRAILING '0' FROM CAST(f.porcentaje AS CHAR))), '% ',
                                    IFNULL((SELECT MAX(tm.String1) FROM tabla_maestra tm
                                            WHERE tm.IdMaestro = 39 AND tm.IdEmpresa = 1 AND tm.String2 = f.condicion
                                              AND tm.eliminado_en IS NULL), f.condicion))
                             ORDER BY f.orden, f.id SEPARATOR ' + '), 400),
           IFNULL(SUM(f.condicion = o_cod_cond), 0)
      INTO v_n_hitos, v_hitos_txt, v_hitos_cond
    FROM propuesta_forma_pago f
    WHERE f.id_propuesta = p_id_propuesta;

    IF v_n_hitos > 0 AND o_cod_cond IS NOT NULL THEN
        SET v_hitos_ok = (v_hitos_cond = v_n_hitos)
            OR (o_cod_cond = 'ADELANTO_50' AND v_n_hitos = 2
                AND (SELECT COUNT(*) FROM propuesta_forma_pago f WHERE f.id_propuesta = p_id_propuesta AND f.porcentaje = 50) = 2
                AND (SELECT f.condicion FROM propuesta_forma_pago f WHERE f.id_propuesta = p_id_propuesta
                     ORDER BY f.orden, f.id LIMIT 1) = 'CONTADO');
    END IF;

    DROP TEMPORARY TABLE IF EXISTS tmp_oc_cmp;
    CREATE TEMPORARY TABLE tmp_oc_cmp (
        orden           INT,
        campo           VARCHAR(30),
        etiqueta        VARCHAR(60),
        valor_oc        VARCHAR(400),
        valor_propuesta VARCHAR(400),
        severidad       VARCHAR(15),
        mensaje         VARCHAR(400),
        accion          VARCHAR(200)
    ) DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;

    -- 1. Cliente (RUC; si la OC no trae RUC, razón social)
    INSERT INTO tmp_oc_cmp VALUES (1, 'cliente', 'Cliente',
        NULLIF(CONCAT_WS(' · ', o_razon, IF(o_ruc IS NULL, NULL, CONCAT('RUC ', o_ruc))), ''),
        CONCAT(v_razon, ' · RUC ', IFNULL(v_ruc, '-')),
        CASE
            WHEN o_ruc IS NOT NULL THEN IF(o_ruc = v_ruc, 'ok', 'critico')
            WHEN o_razon IS NULL   THEN 'sin_dato'
            WHEN REGEXP_REPLACE(UPPER(o_razon), '[^A-Z0-9Ñ]', '') = REGEXP_REPLACE(UPPER(v_razon), '[^A-Z0-9Ñ]', '')
              OR LOCATE(REGEXP_REPLACE(UPPER(o_razon), '[^A-Z0-9Ñ]', ''), REGEXP_REPLACE(UPPER(v_razon), '[^A-Z0-9Ñ]', '')) > 0
              OR LOCATE(REGEXP_REPLACE(UPPER(v_razon), '[^A-Z0-9Ñ]', ''), REGEXP_REPLACE(UPPER(o_razon), '[^A-Z0-9Ñ]', '')) > 0
                                   THEN 'ok'
            ELSE 'advertencia'
        END,
        CASE
            WHEN o_ruc IS NOT NULL AND o_ruc = v_ruc THEN 'Coincidencia exacta del RUC.'
            WHEN o_ruc IS NOT NULL THEN 'El RUC de la OC no coincide con el del cliente de la propuesta.'
            WHEN o_razon IS NULL   THEN 'La OC no indica el cliente; se asume el de la propuesta.'
            ELSE 'La OC no indica el RUC; se comparó la razón social.'
        END,
        IF(o_ruc IS NOT NULL AND o_ruc <> v_ruc, 'Solicitar al cliente la OC con el RUC correcto', NULL));

    -- 2. N° de propuesta referenciado en la OC (si la OC cubre varias propuestas, puede referenciar otra vinculada)
    SET v_ref_esta = (o_num_prop IS NOT NULL AND (
            LOCATE(REGEXP_REPLACE(UPPER(v_numero), '[^A-Z0-9]', ''), REGEXP_REPLACE(UPPER(o_num_prop), '[^A-Z0-9]', '')) > 0
         OR LOCATE(REGEXP_REPLACE(UPPER(o_num_prop), '[^A-Z0-9]', ''), REGEXP_REPLACE(UPPER(v_numero), '[^A-Z0-9]', '')) > 0));
    SET v_ref_otra = (o_num_prop IS NOT NULL AND v_ref_esta = 0 AND JSON_LENGTH(JSON_EXTRACT(p_datos, '$._propuestasVinculadas')) > 0
         AND EXISTS (SELECT 1 FROM JSON_TABLE(JSON_EXTRACT(p_datos, '$._propuestasVinculadas'), '$[*]'
                                              COLUMNS (numero VARCHAR(40) PATH '$')) jv
                     WHERE LOCATE(REGEXP_REPLACE(UPPER(jv.numero), '[^A-Z0-9]', ''), REGEXP_REPLACE(UPPER(o_num_prop), '[^A-Z0-9]', '')) > 0));
    INSERT INTO tmp_oc_cmp VALUES (2, 'numero_propuesta', 'N° Propuesta referenciada',
        o_num_prop, CONCAT(v_numero, ' v', v_version),
        CASE WHEN o_num_prop IS NULL THEN 'sin_dato' WHEN v_ref_esta = 1 OR v_ref_otra = 1 THEN 'ok' ELSE 'advertencia' END,
        CASE WHEN o_num_prop IS NULL THEN 'La OC no menciona el número de la propuesta.'
             WHEN v_ref_esta = 1     THEN 'La OC referencia esta propuesta.'
             WHEN v_ref_otra = 1     THEN 'La OC referencia otra de las propuestas vinculadas.'
             ELSE 'La OC referencia una propuesta que no está vinculada.' END,
        NULL);

    -- 3. Monto asignado frente al saldo de la propuesta (alerta, nunca bloquea). Si la OC está en otra moneda, se compara
    --    el monto convertido con el tipo de cambio.
    SET v_diferencia = v_monto_conv - v_saldo;
    INSERT INTO tmp_oc_cmp VALUES (3, 'monto', 'Monto',
        CONCAT(IFNULL(o_simbolo, ''), ' ', FORMAT(IFNULL(p_monto_asignado, 0), 2),
               IF(v_misma_moneda = 0 AND v_monto_conv IS NOT NULL,
                  CONCAT(' (', IFNULL(v_simbolo, ''), ' ', FORMAT(v_monto_conv, 2), ' con TC ', FORMAT(o_tc, 4), ')'), '')),
        CONCAT(IFNULL(v_simbolo, ''), ' ', FORMAT(v_saldo, 2),
               IF(v_saldo <> v_total, CONCAT(' (saldo de ', FORMAT(v_total, 2), ')'), '')),
        CASE WHEN v_monto_conv IS NULL THEN 'sin_dato' WHEN ABS(v_diferencia) < 0.01 THEN 'ok' ELSE 'advertencia' END,
        CASE
            WHEN v_monto_conv IS NULL THEN IF(o_tc IS NULL,
                'No se puede comparar el monto: la OC está en otra moneda y falta el tipo de cambio.',
                'No se puede comparar el monto: un tipo de cambio en soles no convierte entre esas dos monedas.')
            WHEN ABS(v_diferencia) < 0.01 THEN 'El monto asignado cubre el saldo de la propuesta.'
            WHEN v_diferencia < 0 THEN CONCAT('Faltan ', FORMAT(-v_diferencia, 2), ' para cubrir la propuesta (',
                                              IF(v_saldo > 0, ROUND(v_diferencia * 100 / v_saldo, 2), 0), '% dif.).')
            ELSE CONCAT('El monto asignado excede el saldo de la propuesta en ', FORMAT(v_diferencia, 2), '.')
        END,
        IF(v_monto_conv IS NULL OR ABS(v_diferencia) < 0.01, NULL, 'Confirmar el monto con el cliente'));

    -- 4. Moneda
    INSERT INTO tmp_oc_cmp VALUES (4, 'moneda', 'Moneda',
        o_moneda, v_moneda,
        CASE WHEN o_id_moneda IS NULL THEN 'sin_dato' WHEN v_misma_moneda = 1 OR v_factor IS NOT NULL THEN 'ok' ELSE 'critico' END,
        CASE WHEN o_id_moneda IS NULL THEN 'La OC no indica la moneda.'
             WHEN v_misma_moneda = 1 THEN 'Misma moneda.'
             WHEN v_factor IS NOT NULL THEN CONCAT('La OC está en ', IFNULL(o_cod_moneda, o_moneda), ' y la propuesta en ',
                                                   IFNULL(v_cod_moneda, v_moneda), ': se convirtió con el tipo de cambio ',
                                                   FORMAT(o_tc, 4), '.')
             WHEN o_tc IS NULL THEN CONCAT('Tipo de cambio obligatorio: la OC está en ', IFNULL(o_cod_moneda, o_moneda),
                                           ' y la propuesta en ', IFNULL(v_cod_moneda, v_moneda), '.')
             ELSE CONCAT('No se puede convertir ', IFNULL(o_cod_moneda, o_moneda), ' a ', IFNULL(v_cod_moneda, v_moneda),
                         ' con un tipo de cambio en soles.') END,
        CASE WHEN v_misma_moneda = 1 OR v_factor IS NOT NULL THEN NULL
             WHEN o_tc IS NULL THEN 'Indicar el tipo de cambio'
             ELSE 'Solicitar al cliente la OC en la moneda de la propuesta' END);

    -- 5. Condición / forma de pago
    --    Con hitos de pago (propuesta_forma_pago) se compara contra los hitos; sin hitos, contra la condición de la propuesta.
    IF v_n_hitos > 0 THEN
        INSERT INTO tmp_oc_cmp VALUES (5, 'forma_pago', 'Forma de pago',
            o_cond, v_hitos_txt,
            CASE WHEN o_id_cond IS NULL THEN 'sin_dato' WHEN v_hitos_ok = 1 THEN 'ok' ELSE 'advertencia' END,
            CASE WHEN o_id_cond IS NULL THEN IF(o_cond IS NULL, 'La OC no indica la forma de pago.',
                                                'Forma de pago leída de la OC sin equivalente en el catálogo.')
                 WHEN v_hitos_ok = 1 THEN 'La condición de la OC coincide con los hitos de pago de la propuesta.'
                 ELSE LEFT(CONCAT('La condición de la OC (', o_cond, ') no coincide con los hitos de pago de la propuesta (',
                                  v_hitos_txt, ').'), 400) END,
            IF(o_id_cond IS NOT NULL AND v_hitos_ok = 0, 'Registrar con observación o solicitar corrección al cliente', NULL));
    ELSE
        INSERT INTO tmp_oc_cmp VALUES (5, 'forma_pago', 'Forma de pago',
            o_cond, v_cond,
            CASE WHEN o_id_cond IS NULL OR v_id_cond IS NULL THEN 'sin_dato'
                 WHEN o_id_cond = v_id_cond THEN 'ok' ELSE 'advertencia' END,
            CASE WHEN o_id_cond IS NULL THEN IF(o_cond IS NULL, 'La OC no indica la forma de pago.',
                                                'Forma de pago leída de la OC sin equivalente en el catálogo.')
                 WHEN v_id_cond IS NULL THEN 'La propuesta no tiene condición de pago.'
                 WHEN o_id_cond = v_id_cond THEN 'Coincide.'
                 ELSE 'La condición de pago de la OC es distinta a la de la propuesta.' END,
            IF(o_id_cond IS NOT NULL AND v_id_cond IS NOT NULL AND o_id_cond <> v_id_cond,
               'Aceptar la condición del cliente o solicitar corrección', NULL));
    END IF;

    -- 6. IGV
    INSERT INTO tmp_oc_cmp VALUES (6, 'igv', 'IGV',
        CASE o_igv WHEN 1 THEN 'Incluido' WHEN 0 THEN 'No incluido' END,
        IF(v_aplica_igv = 1, CONCAT('Incluido (', FORMAT(v_igv_pct, 0), '%)'), 'No aplica'),
        CASE WHEN o_igv IS NULL THEN 'sin_dato' WHEN o_igv = v_aplica_igv THEN 'ok' ELSE 'advertencia' END,
        CASE WHEN o_igv IS NULL THEN 'La OC no indica el IGV.'
             WHEN o_igv = v_aplica_igv THEN 'Régimen tributario coincide.'
             ELSE 'El tratamiento del IGV es distinto al de la propuesta.' END,
        NULL);

    -- 7. Fecha de emisión dentro de la vigencia de la propuesta
    INSERT INTO tmp_oc_cmp VALUES (7, 'fecha_emision', 'Fecha emisión',
        DATE_FORMAT(o_fecha, '%d/%m/%Y'),
        IF(v_expiracion IS NULL, 'Sin vencimiento', CONCAT('Vigencia hasta ', DATE_FORMAT(v_expiracion, '%d/%m/%Y'))),
        CASE WHEN o_fecha IS NULL THEN 'sin_dato'
             WHEN v_expiracion IS NULL OR o_fecha <= v_expiracion THEN 'ok' ELSE 'advertencia' END,
        CASE WHEN o_fecha IS NULL THEN 'La OC no indica la fecha de emisión.'
             WHEN v_expiracion IS NULL OR o_fecha <= v_expiracion THEN 'Dentro de vigencia.'
             ELSE 'La OC se emitió después del vencimiento de la propuesta.' END,
        NULL);

    -- 8. Conceptos (con la evaluación de la IA si existe; si no, por cantidad de ítems)
    IF p_eval_ia IS NOT NULL AND JSON_LENGTH(JSON_EXTRACT(p_eval_ia, '$.conceptos')) > 0 THEN
        SELECT COUNT(*), IFNULL(SUM(estado = 'coincide'), 0) INTO v_conc_total, v_conc_ok
        FROM JSON_TABLE(JSON_EXTRACT(p_eval_ia, '$.conceptos'), '$[*]'
                        COLUMNS (estado VARCHAR(30) PATH '$.estado')) jc;
        SET v_dif_conceptos = v_conc_total - v_conc_ok;
        INSERT INTO tmp_oc_cmp VALUES (8, 'conceptos', 'Conceptos / Equipos',
            CONCAT(o_conceptos, ' ítem(s) detectado(s)'), CONCAT(v_items, ' ítem(s) esperado(s)'),
            IF(v_dif_conceptos = 0, 'ok', 'advertencia'),
            IF(v_dif_conceptos = 0, 'Todos los conceptos coinciden.',
               CONCAT(v_conc_ok, ' de ', v_conc_total, ' conceptos coinciden.')),
            IF(v_dif_conceptos = 0, NULL,
               IF(o_factura_igual = 1, 'Generar nueva versión de la propuesta', 'Solicitar corrección al cliente')));
    ELSE
        -- Sin evaluación de la IA: cada ítem de la propuesta se busca por descripción entre los conceptos de la OC
        IF o_conceptos > 0 THEN
            SELECT COUNT(*) INTO v_items_en_oc
            FROM propuesta_item i
            WHERE i.id_propuesta = p_id_propuesta AND i.seccion = 'principal' AND IFNULL(i.es_espaciado, 0) = 0
              AND EXISTS (SELECT 1 FROM JSON_TABLE(JSON_EXTRACT(p_datos, '$.conceptos'), '$[*]'
                                                   COLUMNS (descripcion VARCHAR(300) PATH '$.descripcion')) jc
                          WHERE jc.descripcion IS NOT NULL
                            AND (LOCATE(LEFT(REGEXP_REPLACE(UPPER(i.descripcion), '[^A-Z0-9]', ''), 20),
                                        REGEXP_REPLACE(UPPER(jc.descripcion), '[^A-Z0-9]', '')) > 0
                                 OR LOCATE(LEFT(REGEXP_REPLACE(UPPER(jc.descripcion), '[^A-Z0-9]', ''), 20),
                                           REGEXP_REPLACE(UPPER(i.descripcion), '[^A-Z0-9]', '')) > 0));
        END IF;
        SET v_dif_conceptos = IF(o_conceptos > 0 AND v_items_en_oc < v_items, v_items - v_items_en_oc, 0);
        INSERT INTO tmp_oc_cmp VALUES (8, 'conceptos', 'Conceptos / Equipos',
            IF(o_conceptos > 0, CONCAT(o_conceptos, ' ítem(s) detectado(s)'), NULL),
            CONCAT(v_items, ' ítem(s) esperado(s)'),
            CASE WHEN o_conceptos = 0 THEN 'sin_dato' WHEN v_dif_conceptos = 0 THEN 'ok' ELSE 'advertencia' END,
            CASE WHEN o_conceptos = 0 THEN 'La OC no detalla conceptos.'
                 WHEN v_dif_conceptos = 0 THEN 'Los ítems de la propuesta están en la OC.'
                 ELSE CONCAT(v_items_en_oc, ' de ', v_items, ' ítems de la propuesta están en la OC (falta ',
                             v_dif_conceptos, ').') END,
            IF(v_dif_conceptos = 0, NULL,
               IF(o_factura_igual = 1, 'Generar nueva versión de la propuesta', 'Solicitar corrección al cliente')));
    END IF;

    SELECT IFNULL(SUM(severidad = 'ok'), 0), IFNULL(SUM(severidad = 'advertencia'), 0),
           IFNULL(SUM(severidad = 'critico'), 0), IFNULL(SUM(severidad <> 'sin_dato'), 0),
           IFNULL(SUM(severidad = 'advertencia' AND campo <> 'conceptos'), 0)
      INTO p_coincidencias, p_advertencias, p_criticas, p_total, v_otras_adv
    FROM tmp_oc_cmp;

    SET p_resultado = CASE WHEN p_criticas > 0 THEN 'critico' WHEN p_advertencias > 0 THEN 'advertencia' ELSE 'ok' END;
    SET p_sugerencia = CASE
        WHEN p_resultado = 'ok' THEN 'validar'
        WHEN p_criticas = 0 AND v_otras_adv = 0 AND v_dif_conceptos > 0 AND o_factura_igual = 1 THEN 'nueva_version'
        ELSE 'correccion_cliente'
    END;
END$$

DELIMITER ;
