-- HU-27 Modal "Registrar OC Complementaria" con el resultado calculado en tiempo real.
-- Acción oc_registrar y propuesta del área del usuario, ACEPTADA, con al menos una OC no anulada
-- y cobertura menor al 100 %.
-- p_monto (opcional): monto de la nueva OC para el cálculo OC existente + Nueva OC = Cobertura total.
-- Resultados:
--   1 mensaje
--   2 propuesta y cobertura actual: monto propuesta, cubierto por OC existentes, faltante y %
--     y el resultado con la nueva OC (cobertura total, %, estado y saldo que le quedaría a la nueva OC)
--   3 OC existentes de la propuesta con lo que aplica cada una
DROP PROCEDURE IF EXISTS SP_PrepararOcComplementaria;

DELIMITER $$

CREATE PROCEDURE SP_PrepararOcComplementaria(
    IN p_id_usuario   BIGINT,
    IN p_id_propuesta BIGINT,
    IN p_monto        DECIMAL(14,2)
)
proc: BEGIN
    DECLARE v_dias_sin_resp INT;
    DECLARE v_meta          INT;
    DECLARE v_sla_horas     INT;
    DECLARE v_alerta_horas  INT;
    DECLARE v_existe        INT DEFAULT 0;
    DECLARE v_estado        VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_total         DECIMAL(14,2);
    DECLARE v_cubierto      DECIMAL(14,2) DEFAULT 0;
    DECLARE v_n_oc          INT DEFAULT 0;
    DECLARE v_vigencia      INT DEFAULT 30;
    DECLARE v_monto         DECIMAL(14,2);

    IF FN_PermisoAccion(p_id_usuario, 'oc_registrar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para registrar órdenes de compra.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_CalcularSeguimientoComercial(p_id_usuario, p_id_propuesta, v_dias_sin_resp, v_meta, v_sla_horas, v_alerta_horas);
    SELECT COUNT(*), MAX(estado_seguimiento), MAX(total) INTO v_existe, v_estado, v_total FROM tmp_seg;

    IF v_existe = 0 OR v_estado <> 'aceptada' THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_seg;
        DROP TEMPORARY TABLE IF EXISTS tmp_seg_base;
        SELECT 1 AS IdTipoMensaje,
               IF(v_existe = 0, 'La propuesta no está en seguimiento comercial o no pertenece a tu área.',
                                'La propuesta no está aceptada por el cliente.') AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT COUNT(DISTINCT op.id_oc), IFNULL(SUM(op.monto_asignado), 0) INTO v_n_oc, v_cubierto
    FROM oc_propuesta op
    JOIN orden_compra oc ON oc.id_oc = op.id_oc AND oc.eliminado_en IS NULL AND oc.estado <> 'anulada'
             AND oc.id_moneda = (SELECT pz.id_moneda FROM propuesta_comercial pz WHERE pz.id_propuesta = op.id_propuesta)
    WHERE op.id_propuesta = p_id_propuesta AND op.eliminado_en IS NULL;

    IF v_n_oc = 0 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_seg;
        DROP TEMPORARY TABLE IF EXISTS tmp_seg_base;
        SELECT 1 AS IdTipoMensaje, 'La propuesta aún no tiene orden de compra: registre primero la OC principal.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_cubierto >= v_total - 0.005 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_seg;
        DROP TEMPORARY TABLE IF EXISTS tmp_seg_base;
        SELECT 1 AS IdTipoMensaje, 'La propuesta ya está cubierta al 100 % por sus órdenes de compra.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT CAST(IFNULL(MAX(Num2), 30) AS SIGNED) INTO v_vigencia
    FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROPUESTA' AND String2 = 'OC_VIGENCIA_DIAS_DEFECTO';

    SET v_monto = IF(p_monto IS NULL OR p_monto < 0, NULL, p_monto);

    -- 1. Header
    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Propuesta, cobertura actual y resultado
    SELECT t.id_propuesta, t.numero, t.version, t.id_cliente, c.razon_social, c.ruc,
           t.id_requerimiento, r.numero AS numero_rq,
           t.id_moneda, m.String3 AS moneda, m.String2 AS moneda_simbolo, m.String1 AS moneda_nombre,
           v_total                                        AS monto_propuesta,
           v_cubierto                                     AS monto_cubierto,
           v_total - v_cubierto                           AS faltante,
           ROUND(v_cubierto * 100 / v_total, 1)           AS cobertura_pct,
           v_vigencia                                     AS vigencia_dias_defecto,
           CURDATE()                                      AS fecha_servidor,
           -- Resultado calculado: OC existente + Nueva OC = Cobertura total
           v_monto                                        AS monto_nueva_oc,
           v_cubierto + LEAST(IFNULL(v_monto, 0), v_total - v_cubierto)          AS cobertura_total,
           ROUND((v_cubierto + LEAST(IFNULL(v_monto, 0), v_total - v_cubierto)) * 100 / v_total, 1) AS cobertura_total_pct,
           CASE WHEN v_monto IS NULL OR v_monto = 0                  THEN 'sin_monto'
                WHEN ABS(v_monto - (v_total - v_cubierto)) < 0.005   THEN 'completa'
                WHEN v_monto > v_total - v_cubierto                  THEN 'con_saldo'
                ELSE 'insuficiente' END                                         AS estado_resultado,
           GREATEST(IFNULL(v_monto, 0) - (v_total - v_cubierto), 0)            AS saldo_nueva_oc,
           GREATEST((v_total - v_cubierto) - IFNULL(v_monto, 0), 0)            AS faltante_despues
    FROM tmp_seg t
    LEFT JOIN cliente c       ON c.id_cliente       = t.id_cliente
    LEFT JOIN requerimiento r ON r.id_requerimiento = t.id_requerimiento
    LEFT JOIN tabla_maestra m ON m.IdMaestro = 1 AND m.IdEmpresa = 1 AND m.Num1 = t.id_moneda;

    DROP TEMPORARY TABLE IF EXISTS tmp_seg;
    DROP TEMPORARY TABLE IF EXISTS tmp_seg_base;

    -- 3. OC existentes
    SELECT oc.id_oc, oc.numero_oc, oc.tipo_oc, oc.estado, oc.monto_total, op.monto_asignado, oc.fecha_oc
    FROM oc_propuesta op
    JOIN orden_compra oc ON oc.id_oc = op.id_oc AND oc.eliminado_en IS NULL AND oc.estado <> 'anulada'
             AND oc.id_moneda = (SELECT pz.id_moneda FROM propuesta_comercial pz WHERE pz.id_propuesta = op.id_propuesta)
    WHERE op.id_propuesta = p_id_propuesta AND op.eliminado_en IS NULL
    ORDER BY oc.fecha_registro;
END$$

DELIMITER ;
