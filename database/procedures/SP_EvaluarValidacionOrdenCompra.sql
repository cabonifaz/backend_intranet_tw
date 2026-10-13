-- HU-26 (interno) Checklist de validación de la OC. Llena la tabla temporal tmp_oc_check.
-- El que llama valida permiso y alcance antes, y hace DROP TEMPORARY TABLE tmp_oc_check al terminar.
-- Cada ítem trae el valor registrado en el sistema, el valor de referencia (propuesta), si cumple la
-- verificación automática y si requiere que el validador lo confirme contra la OC física
-- (razón social, RUC, moneda, monto y legibilidad del PDF).
-- HU-27: el monto se compara contra el requerido neto (sin lo que ya cubren otras OC).
DROP PROCEDURE IF EXISTS SP_EvaluarValidacionOrdenCompra;

DELIMITER $$

CREATE PROCEDURE SP_EvaluarValidacionOrdenCompra(
    IN p_id_oc BIGINT
)
BEGIN
    DECLARE v_id_cliente   BIGINT;
    DECLARE v_id_moneda    INT;
    DECLARE v_monto        DECIMAL(14,2);
    DECLARE v_numero_oc    VARCHAR(50)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tiene_pdf    TINYINT;
    DECLARE v_vig_hasta    DATE;
    DECLARE v_id_prop      BIGINT;
    DECLARE v_prop_cliente BIGINT;
    DECLARE v_prop_moneda  INT;
    DECLARE v_prop_numero  VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_prop_estado  VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_prop_ultima  TINYINT DEFAULT 0;
    DECLARE v_aceptada     TINYINT DEFAULT 0;
    DECLARE v_total        DECIMAL(14,2) DEFAULT 0;
    DECLARE v_otra_moneda  INT DEFAULT 0;
    DECLARE v_tolerancia   DECIMAL(9,4) DEFAULT 0;
    DECLARE v_razon        VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_razon_prop   VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_ruc          VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_mon_oc       VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_mon_prop     VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_sim_oc       VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_sim_prop     VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_duplicadas   INT DEFAULT 0;
    DECLARE v_otros        DECIMAL(14,2) DEFAULT 0;

    SELECT oc.id_cliente, oc.id_moneda, oc.monto_total, oc.numero_oc, (oc.url_archivo_pdf IS NOT NULL),
           oc.vigencia_hasta, oc.id_propuesta
      INTO v_id_cliente, v_id_moneda, v_monto, v_numero_oc, v_tiene_pdf, v_vig_hasta, v_id_prop
    FROM orden_compra oc WHERE oc.id_oc = p_id_oc;

    SELECT p.id_cliente, p.id_moneda, CONCAT(p.numero, ' v', p.version), p.estado,
           (p.version = (SELECT MAX(p2.version) FROM propuesta_comercial p2
                         WHERE p2.numero = p.numero AND p2.eliminado_en IS NULL)),
           (p.estado = 'aprobado'
            OR EXISTS (SELECT 1 FROM seguimiento_comercial s
                       WHERE s.id_propuesta = p.id_propuesta AND s.estado = 'cerrado_aceptacion' AND s.eliminado_en IS NULL))
      INTO v_prop_cliente, v_prop_moneda, v_prop_numero, v_prop_estado, v_prop_ultima, v_aceptada
    FROM propuesta_comercial p WHERE p.id_propuesta = v_id_prop;

    SELECT IFNULL(SUM(pv.total), 0), IFNULL(SUM(pv.id_moneda <> v_id_moneda), 0) INTO v_total, v_otra_moneda
    FROM propuesta_comercial pv
    WHERE pv.id_propuesta = v_id_prop;
    -- HU-27: más lo asignado a las propuestas distribuidas
    SET v_total = v_total + (SELECT IFNULL(SUM(op.monto_asignado), 0) FROM oc_propuesta op
                             WHERE op.id_oc = p_id_oc AND op.eliminado_en IS NULL AND op.id_propuesta <> IFNULL(v_id_prop, 0));

    -- HU-27: lo que otras OC ya cubren de la propuesta principal no lo tiene que cubrir esta OC
    SELECT IFNULL(SUM(op2.monto_asignado), 0) INTO v_otros
    FROM oc_propuesta op2
    JOIN orden_compra o2 ON o2.id_oc = op2.id_oc AND o2.eliminado_en IS NULL AND o2.estado <> 'anulada'
             AND o2.id_moneda = (SELECT pz.id_moneda FROM propuesta_comercial pz WHERE pz.id_propuesta = op2.id_propuesta)
    WHERE op2.eliminado_en IS NULL AND op2.id_oc <> p_id_oc AND op2.id_propuesta = v_id_prop;
    SET v_total = GREATEST(v_total - v_otros, 0);

    SELECT CAST(IFNULL(MAX(Num2), 0) AS DECIMAL(9,4)) INTO v_tolerancia
    FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROPUESTA' AND String2 = 'OC_TOLERANCIA_MONTO_PCT';

    SELECT razon_social, ruc INTO v_razon, v_ruc FROM cliente WHERE id_cliente = v_id_cliente;
    SELECT razon_social INTO v_razon_prop FROM cliente WHERE id_cliente = v_prop_cliente;
    SELECT MAX(String1), MAX(String2) INTO v_mon_oc, v_sim_oc
    FROM tabla_maestra WHERE IdMaestro = 1 AND IdEmpresa = 1 AND Num1 = v_id_moneda;
    SELECT MAX(String1), MAX(String2) INTO v_mon_prop, v_sim_prop
    FROM tabla_maestra WHERE IdMaestro = 1 AND IdEmpresa = 1 AND Num1 = v_prop_moneda;

    SELECT COUNT(*) INTO v_duplicadas
    FROM orden_compra
    WHERE id_cliente = v_id_cliente AND numero_oc = v_numero_oc AND id_oc <> p_id_oc
      AND estado <> 'anulada' AND eliminado_en IS NULL;

    DROP TEMPORARY TABLE IF EXISTS tmp_oc_check;
    CREATE TEMPORARY TABLE tmp_oc_check (
        orden                 INT,
        codigo                VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        descripcion           VARCHAR(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        valor_sistema         VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        valor_referencia      VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        cumple_auto           TINYINT,
        requiere_confirmacion TINYINT,
        detalle               VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
    );

    INSERT INTO tmp_oc_check VALUES
    (1, 'razon_social', 'Razón Social del Cliente', v_razon, v_razon_prop,
        IF(v_id_cliente = v_prop_cliente, 1, 0), 1,
        IF(v_id_cliente = v_prop_cliente, 'Confirme que la OC física está emitida a esta razón social.',
           'El cliente de la OC no es el de la propuesta.')),
    (2, 'ruc', 'RUC del Cliente', v_ruc, v_ruc,
        IF(v_ruc REGEXP '^[0-9]{11}$', 1, 0), 1,
        IF(v_ruc REGEXP '^[0-9]{11}$', 'Confirme que el RUC de la OC física coincide.',
           'El RUC registrado del cliente no es válido (11 dígitos).')),
    (3, 'propuesta_aceptada', 'Propuesta técnica aceptada', v_prop_numero, NULL,
        IF(v_aceptada = 1 AND v_prop_ultima = 1 AND v_prop_estado NOT IN ('anulado', 'vencido', 'rechazado', 'borrador'), 1, 0), 0,
        CASE WHEN v_aceptada = 0 THEN 'La propuesta no tiene registrada la aceptación del cliente.'
             WHEN v_prop_ultima = 0 THEN 'Existe una versión más reciente de la propuesta.'
             WHEN v_prop_estado IN ('anulado', 'vencido', 'rechazado', 'borrador') THEN 'La propuesta está anulada, vencida o rechazada.'
             ELSE 'La propuesta es la última versión y está aceptada por el cliente.' END),
    (4, 'moneda', CONCAT('Moneda (', IFNULL(v_mon_oc, '-'), ')'), v_mon_oc, v_mon_prop,
        IF(v_otra_moneda = 0 AND v_id_moneda = v_prop_moneda, 1, 0), 1,
        IF(v_otra_moneda = 0 AND v_id_moneda = v_prop_moneda, 'Misma moneda que la propuesta. Confirme la moneda de la OC física.',
           CONCAT('La propuesta está en ', IFNULL(v_mon_prop, '-'), '.'))),
    (5, 'monto', 'Monto total coincide',
        CONCAT(IFNULL(v_sim_oc, ''), ' ', FORMAT(v_monto, 2)), CONCAT(IFNULL(v_sim_prop, ''), ' ', FORMAT(v_total, 2)),
        IF(v_otra_moneda = 0 AND v_monto >= ROUND(v_total * (1 - v_tolerancia / 100), 2), 1, 0), 1,
        CASE WHEN v_otra_moneda > 0 THEN 'No se puede comparar: las monedas son distintas.'
             WHEN v_monto >= ROUND(v_total * (1 - v_tolerancia / 100), 2) THEN 'El monto de la OC cubre la propuesta. Confirme el monto de la OC física.'
             ELSE CONCAT('Faltan ', FORMAT(v_total - v_monto, 2), ' para cubrir la propuesta.') END),
    (6, 'numero_unico', 'N.° de OC no duplicado', v_numero_oc, NULL,
        IF(v_duplicadas = 0, 1, 0), 0,
        IF(v_duplicadas = 0, 'No hay otra OC del cliente con este número.', 'Existe otra OC del cliente con el mismo número.')),
    (7, 'pdf_legible', 'Documento PDF adjunto y legible', IF(v_tiene_pdf = 1, 'Adjunto', 'Sin PDF'), NULL,
        v_tiene_pdf, 1,
        IF(v_tiene_pdf = 1, 'Abra el documento y confirme que es legible y está firmado o sellado.', 'La OC no tiene PDF adjunto.')),
    (8, 'oc_vigente', 'Orden de compra vigente', IFNULL(DATE_FORMAT(v_vig_hasta, '%d/%m/%Y'), 'Sin vigencia'), NULL,
        IF(v_vig_hasta IS NULL OR v_vig_hasta >= CURDATE(), 1, 0), 0,
        IF(v_vig_hasta IS NULL OR v_vig_hasta >= CURDATE(), 'La OC está vigente.', 'La vigencia de la OC ya venció.'));
END$$

DELIMITER ;
