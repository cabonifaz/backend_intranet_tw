-- Saldo de la propuesta por cubrir con la OC REAL del cliente (ticket A, multi-propuesta).
-- Igual que FN_SaldoPropuestaOc, pero las OC autogeneradas (OC-AUTO) vigentes no cuentan: al registrar la OC del cliente
-- se dan de baja solas (SP_RegistrarOrdenCompra), así que su cobertura queda disponible para la OC real.
-- p_excluir_oc: no cuenta lo que asignó esa OC.
DROP FUNCTION IF EXISTS FN_SaldoPropuestaOcSinAutogenerada;

DELIMITER $$

CREATE FUNCTION FN_SaldoPropuestaOcSinAutogenerada(
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
      AND oc.eliminado_en IS NULL AND oc.estado NOT IN ('anulada', 'autogenerada') AND oc.reemplazada_por IS NULL
      AND oc.id_oc <> IFNULL(p_excluir_oc, 0);

    RETURN IFNULL(v_total, 0) - v_asignado;
END$$

DELIMITER ;
