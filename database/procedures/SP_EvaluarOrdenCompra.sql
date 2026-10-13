-- HU-24 Panel lateral "Validación de Cobertura" y "Checklist de negocio" en tiempo real.
-- No guarda nada y no falla por los datos que se van escribiendo: los muestra como checks en rojo.
-- Modos:
--   Registro: p_id_propuesta = propuesta aceptada, p_id_oc NULL (acción oc_registrar)
--   Edición : p_id_oc = OC a editar, p_id_propuesta NULL (acción oc_editar)
-- Cobertura (monto OC frente al monto de la propuesta, en la misma moneda):
--   sin_monto, completa, con_saldo (la OC supera la propuesta), insuficiente (no alcanza) o moneda_diferente.
-- Resultados: 1 mensaje, 2 cobertura (y en edición el impacto del cambio), 3 checklist.
DROP PROCEDURE IF EXISTS SP_EvaluarOrdenCompra;

DELIMITER $$

CREATE PROCEDURE SP_EvaluarOrdenCompra(
    IN p_id_usuario    BIGINT,
    IN p_id_propuesta  BIGINT,
    IN p_id_oc         BIGINT,
    IN p_numero_oc     VARCHAR(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_moneda     INT,
    IN p_monto         DECIMAL(14,2),
    IN p_tiene_archivo TINYINT
)
proc: BEGIN
    DECLARE v_dias_sin_resp  INT;
    DECLARE v_meta           INT;
    DECLARE v_sla_horas      INT;
    DECLARE v_alerta_horas   INT;
    DECLARE v_edicion        TINYINT DEFAULT 0;
    DECLARE v_existe         INT DEFAULT 0;
    DECLARE v_estado_seg     VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tiene_oc       INT DEFAULT 0;
    DECLARE v_aceptada       TINYINT DEFAULT 0;
    DECLARE v_id_prop        BIGINT;
    DECLARE v_id_cliente     BIGINT;
    DECLARE v_id_cliente_oc  BIGINT;
    DECLARE v_total          DECIMAL(14,2) DEFAULT 0;
    DECLARE v_id_moneda_prop INT;
    DECLARE v_simbolo_prop   VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_simbolo_oc     VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_numero_oc      VARCHAR(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_duplicada      INT DEFAULT 0;
    DECLARE v_tolerancia     DECIMAL(9,4) DEFAULT 0;
    DECLARE v_estado_cob     VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_pct            DECIMAL(7,2) DEFAULT 0;
    DECLARE v_diferencia     DECIMAL(14,2);
    DECLARE v_en_tolerancia  TINYINT DEFAULT 0;
    DECLARE v_cliente_ok     TINYINT DEFAULT 0;
    DECLARE v_archivo        TINYINT DEFAULT 0;
    -- edición
    DECLARE v_monto_actual   DECIMAL(14,2);
    DECLARE v_moneda_actual  INT;
    DECLARE v_validada       TINYINT DEFAULT 0;
    DECLARE v_estado_bd      VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_n_os           INT DEFAULT 0;
    DECLARE v_cambia         TINYINT DEFAULT 0;

    SET v_edicion   = IF(IFNULL(p_id_oc, 0) > 0, 1, 0);
    SET v_numero_oc = NULLIF(TRIM(IFNULL(p_numero_oc, '')), '');

    IF FN_PermisoAccion(p_id_usuario, IF(v_edicion = 1, 'oc_editar', 'oc_registrar')) = 0 THEN
        SELECT 1 AS IdTipoMensaje,
               IF(v_edicion = 1, 'No tienes permiso para editar órdenes de compra.',
                                 'No tienes permiso para registrar órdenes de compra.') AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT CAST(IFNULL(MAX(Num2), 0) AS DECIMAL(9,4)) INTO v_tolerancia
    FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROPUESTA' AND String2 = 'OC_TOLERANCIA_MONTO_PCT';

    IF v_edicion = 0 THEN
        CALL SP_CalcularSeguimientoComercial(p_id_usuario, p_id_propuesta,
                                             v_dias_sin_resp, v_meta, v_sla_horas, v_alerta_horas);
        SELECT COUNT(*), MAX(estado_seguimiento), IFNULL(MAX(fecha_primera_oc IS NOT NULL), 0),
               MAX(id_propuesta), MAX(id_cliente), MAX(total), MAX(id_moneda)
          INTO v_existe, v_estado_seg, v_tiene_oc, v_id_prop, v_id_cliente, v_total, v_id_moneda_prop
        FROM tmp_seg;
        DROP TEMPORARY TABLE IF EXISTS tmp_seg;
        DROP TEMPORARY TABLE IF EXISTS tmp_seg_base;

        IF v_existe = 0 THEN
            SELECT 1 AS IdTipoMensaje, 'La propuesta no está en seguimiento comercial o no pertenece a tu área.' AS Mensaje;
            LEAVE proc;
        END IF;
        SET v_aceptada      = IF(v_estado_seg = 'aceptada' AND v_tiene_oc = 0, 1, 0);
        SET v_id_cliente_oc = v_id_cliente;
    ELSE
        CALL SP_CalcularOrdenesCompra(p_id_usuario, p_id_oc);
        SELECT COUNT(*), MAX(id_propuesta), MAX(id_cliente), MAX(monto_propuesta), MAX(monto_oc),
               MAX(id_moneda), MAX(validada), MAX(estado_bd), MAX(ordenes_servicio)
          INTO v_existe, v_id_prop, v_id_cliente_oc, v_total, v_monto_actual,
               v_moneda_actual, v_validada, v_estado_bd, v_n_os
        FROM tmp_oc;
        DROP TEMPORARY TABLE IF EXISTS tmp_oc;

        IF v_existe = 0 THEN
            SELECT 1 AS IdTipoMensaje, 'La orden de compra no existe o no pertenece a tu área.' AS Mensaje;
            LEAVE proc;
        END IF;

        SELECT p.id_cliente, p.id_moneda,
               (p.estado = 'aprobado'
                OR EXISTS (SELECT 1 FROM seguimiento_comercial s
                           WHERE s.id_propuesta = p.id_propuesta AND s.estado = 'cerrado_aceptacion'
                             AND s.eliminado_en IS NULL))
          INTO v_id_cliente, v_id_moneda_prop, v_aceptada
        FROM propuesta_comercial p WHERE p.id_propuesta = v_id_prop;

        SET v_archivo = IF(EXISTS (SELECT 1 FROM orden_compra WHERE id_oc = p_id_oc AND url_archivo_pdf IS NOT NULL), 1, 0);
        SET v_cambia  = IF(p_monto IS NOT NULL AND p_id_moneda IS NOT NULL
                           AND (p_monto <> v_monto_actual OR p_id_moneda <> v_moneda_actual), 1, 0);
    END IF;

    SET v_archivo    = IF(v_archivo = 1 OR IFNULL(p_tiene_archivo, 0) = 1, 1, 0);
    SET v_cliente_ok = IF(v_id_cliente IS NOT NULL AND v_id_cliente = v_id_cliente_oc
                          AND EXISTS (SELECT 1 FROM cliente WHERE id_cliente = v_id_cliente AND eliminado_en IS NULL), 1, 0);

    IF v_numero_oc IS NOT NULL THEN
        SELECT COUNT(*) INTO v_duplicada
        FROM orden_compra
        WHERE id_cliente = v_id_cliente_oc AND numero_oc = v_numero_oc
          AND id_oc <> IFNULL(p_id_oc, 0) AND estado <> 'anulada' AND eliminado_en IS NULL;
    END IF;

    SELECT MAX(String2) INTO v_simbolo_prop FROM tabla_maestra WHERE IdMaestro = 1 AND IdEmpresa = 1 AND Num1 = v_id_moneda_prop;
    SELECT MAX(String2) INTO v_simbolo_oc   FROM tabla_maestra WHERE IdMaestro = 1 AND IdEmpresa = 1 AND Num1 = p_id_moneda;

    -- Cobertura
    IF p_monto IS NULL OR p_monto <= 0 OR p_id_moneda IS NULL THEN
        SET v_estado_cob = 'sin_monto';
        SET v_pct        = 0;
        SET v_diferencia = NULL;
    ELSEIF p_id_moneda <> v_id_moneda_prop THEN
        SET v_estado_cob = 'moneda_diferente';
        SET v_pct        = 0;
        SET v_diferencia = NULL;
    ELSE
        SET v_diferencia    = p_monto - v_total;
        SET v_pct           = IF(v_total > 0, LEAST(ROUND(p_monto * 100 / v_total, 2), 999.99), 100);
        SET v_estado_cob    = CASE WHEN ABS(v_diferencia) < 0.01 THEN 'completa'
                                   WHEN v_diferencia > 0         THEN 'con_saldo'
                                   ELSE                               'insuficiente' END;
        SET v_en_tolerancia = IF(p_monto >= ROUND(v_total * (1 - v_tolerancia / 100), 2), 1, 0);
    END IF;

    -- 1. Header
    SELECT 2 AS IdTipoMensaje, 'Evaluado.' AS Mensaje;

    -- 2. Cobertura
    SELECT v_estado_cob AS estado_cobertura,
           CASE v_estado_cob
               WHEN 'completa'         THEN 'Cobertura completa'
               WHEN 'con_saldo'        THEN 'Cobertura completa con saldo a favor'
               WHEN 'insuficiente'     THEN 'Cobertura insuficiente'
               WHEN 'moneda_diferente' THEN 'Moneda diferente a la propuesta'
               ELSE                         'Ingrese el monto de la OC'
           END                                              AS etiqueta_cobertura,
           v_pct                                            AS cobertura_pct,
           v_diferencia                                     AS diferencia,
           v_total                                          AS monto_propuesta,
           v_id_moneda_prop                                 AS id_moneda_propuesta,
           v_simbolo_prop                                   AS moneda_simbolo_propuesta,
           p_monto                                          AS monto_oc,
           p_id_moneda                                      AS id_moneda_oc,
           v_simbolo_oc                                     AS moneda_simbolo_oc,
           v_tolerancia                                     AS tolerancia_pct,
           v_en_tolerancia                                  AS dentro_tolerancia,
           v_edicion                                        AS es_edicion,
           v_monto_actual                                   AS monto_oc_actual,
           v_moneda_actual                                  AS id_moneda_actual,
           v_cambia                                         AS cambia_monto_moneda,
           IF(v_edicion = 1 AND v_cambia = 1 AND v_validada = 1, 1, 0) AS requiere_revalidacion,
           IF(v_edicion = 1 AND v_cambia = 1 AND v_n_os > 0, 1, 0)       AS cambio_bloqueado,
           -- Al cambiar monto o moneda la OC vuelve a validación: lo aplicado queda en 0 hasta revalidar
           IF(v_edicion = 1 AND v_validada = 1 AND v_cambia = 0 AND v_estado_cob <> 'moneda_diferente',
              v_total, 0)                                   AS monto_aplicado_proyectado,
           IFNULL(p_monto, 0) - IF(v_edicion = 1 AND v_validada = 1 AND v_cambia = 0
                                   AND v_estado_cob <> 'moneda_diferente', v_total, 0) AS saldo_proyectado;

    -- 3. Checklist de negocio
    SELECT 'propuesta_aceptada' AS codigo, 'Propuesta aceptada' AS descripcion, v_aceptada AS cumple,
           CASE WHEN v_aceptada = 1  THEN 'El cliente aceptó la propuesta.'
                WHEN v_tiene_oc = 1  THEN 'La propuesta ya tiene una orden de compra registrada.'
                ELSE 'Registre primero la aceptación del cliente (Cierre del seguimiento).' END AS detalle
    UNION ALL
    SELECT 'cliente_coincide', 'Cliente coincide con registro', v_cliente_ok,
           IF(v_cliente_ok = 1, 'Cliente heredado de la propuesta.', 'El cliente no coincide o no está registrado.')
    UNION ALL
    SELECT 'moneda_coincide', 'Moneda coincide con propuesta',
           IF(p_id_moneda IS NOT NULL AND p_id_moneda = v_id_moneda_prop, 1, 0),
           CASE WHEN p_id_moneda IS NULL             THEN 'Seleccione la moneda.'
                WHEN p_id_moneda = v_id_moneda_prop  THEN 'Misma moneda que la propuesta.'
                ELSE CONCAT('La propuesta está en ', IFNULL(v_simbolo_prop, ''), '.') END
    UNION ALL
    SELECT 'numero_disponible', 'N.° de OC disponible en sistema',
           IF(v_numero_oc IS NOT NULL AND v_duplicada = 0, 1, 0),
           CASE WHEN v_numero_oc IS NULL THEN 'Ingrese el número de la orden de compra.'
                WHEN v_duplicada = 0     THEN 'No hay otra OC del cliente con este número.'
                ELSE CONCAT('Ya existe la OC ', v_numero_oc, ' para este cliente.') END
    UNION ALL
    SELECT 'archivo_cargado', 'Archivo de sustento cargado', v_archivo,
           IF(v_archivo = 1, 'PDF de la orden de compra adjunto.', 'Adjunte el PDF de la orden de compra.')
    UNION ALL
    SELECT 'monto_tolerancia', 'Monto dentro de tolerancia', v_en_tolerancia,
           CASE WHEN v_estado_cob = 'sin_monto'        THEN 'Ingrese el monto de la OC.'
                WHEN v_estado_cob = 'moneda_diferente' THEN 'No se puede comparar: las monedas son distintas.'
                WHEN v_en_tolerancia = 1 AND v_tolerancia > 0 AND v_diferencia < 0
                     THEN CONCAT('Menor a la propuesta pero dentro de la tolerancia del ', ROUND(v_tolerancia, 2), '%.')
                WHEN v_en_tolerancia = 1               THEN 'El monto cubre la propuesta.'
                ELSE CONCAT('Faltan ', FORMAT(-v_diferencia, 2), ' para cubrir la propuesta.') END;
END$$

DELIMITER ;
