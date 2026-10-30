-- Saldo de la propuesta por cubrir con órdenes de compra (Sprint 4, HU-22 a HU-28).
-- Total de la propuesta menos lo que le asignaron las OC no anuladas (vinculaciones activas).
-- p_excluir_oc: no cuenta lo que asignó esa OC (para editar o comparar una OC contra su propia vinculación).
-- Las OC reemplazadas por la OC del cliente no cuentan (la OC autogenerada y la OC pendiente de reemplazo dejan de
-- contar al registrarse la OC que las reemplaza).
-- Cada vinculación descuenta lo que cubre en la moneda de la propuesta (monto_cubierto, migración 78; si la OC está en la
-- misma moneda, monto_asignado).
DROP FUNCTION IF EXISTS FN_SaldoPropuestaOc;

DELIMITER $$

CREATE FUNCTION FN_SaldoPropuestaOc(
    p_id_propuesta BIGINT,
    p_excluir_oc   BIGINT
) RETURNS DECIMAL(14,2)
READS SQL DATA
BEGIN
    DECLARE v_total    DECIMAL(14,2);
    DECLARE v_asignado DECIMAL(14,2);

    SELECT total INTO v_total FROM propuesta_comercial WHERE id_propuesta = p_id_propuesta;

    SELECT IFNULL(SUM(IFNULL(op.monto_cubierto, op.monto_asignado)), 0) INTO v_asignado
    FROM oc_propuesta op
    JOIN orden_compra oc ON oc.id_oc = op.id_oc
    WHERE op.id_propuesta = p_id_propuesta AND op.eliminado_en IS NULL
      AND oc.eliminado_en IS NULL AND oc.estado <> 'anulada' AND oc.reemplazada_por IS NULL
      AND oc.id_oc <> IFNULL(p_excluir_oc, 0);

    RETURN IFNULL(v_total, 0) - v_asignado;
END$$

DELIMITER ;
