-- Cálculo compartido de las órdenes de compra (bandeja HU-22 y detalle HU-25). Sprint 4.
-- Llena la tabla temporal tmp_oc. El que llama debe hacer DROP TEMPORARY TABLE tmp_oc al terminar.
-- p_id_oc NULL = todas las OC en alcance.
--
-- Alcance: OC cuya propuesta de origen pertenece a un responsable del área del usuario.
--   Con la acción propuesta_seguimiento_todas (admins de Gerencia y TI) todas las áreas.
--
-- Montos (en la moneda de la OC):
--   monto_asignado = suma de lo asignado a las propuestas vinculadas (vinculaciones activas)
--   saldo_oc       = monto de la OC - monto asignado (lo que aún se puede vincular a otra propuesta)
--
-- estado (BD): autogenerada, validada, validada_parcial, observada, pendiente_reemplazo, anulada
--   (ver SP_RecalcularEstadoOrdenCompra). estado_visual = estado (se mantiene por compatibilidad).
-- reemplazada_por: OC del cliente que la reemplazó (la OC reemplazada se conserva para auditoría).
-- pendiente_reemplazo (bandera): OC autogenerada o con corrección pendiente que todavía no se reemplazó.
-- resultado_ia: el peor resultado de la última validación de cada vinculación (critico, advertencia, ok o NULL).
DROP PROCEDURE IF EXISTS SP_CalcularOrdenesCompra;

DELIMITER $$

CREATE PROCEDURE SP_CalcularOrdenesCompra(
    IN p_id_usuario BIGINT,
    IN p_id_oc      BIGINT
)
BEGIN
    DECLARE v_todas TINYINT DEFAULT 0;
    DECLARE v_area  VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    SET v_todas = FN_PermisoAccion(p_id_usuario, 'propuesta_seguimiento_todas');

    SELECT area INTO v_area
    FROM usuario WHERE id_usuario = p_id_usuario AND eliminado_en IS NULL AND estado = 'activo' LIMIT 1;

    DROP TEMPORARY TABLE IF EXISTS tmp_oc_base;
    CREATE TEMPORARY TABLE tmp_oc_base AS
    SELECT
        oc.id_oc, oc.numero_oc, oc.es_autogenerada, oc.id_oc_reemplazada, oc.reemplazada_por, oc.fecha_reemplazo,
        oc.id_cliente, oc.id_moneda, oc.monto_total AS monto_oc, oc.estado,
        oc.fecha_oc, oc.fecha_recepcion, oc.vigencia_hasta, oc.fecha_registro, oc.creado_por,
        oc.factura_igual_oc, oc.referencia,
        (oc.url_archivo_pdf IS NOT NULL)                                       AS tiene_pdf,
        p.id_propuesta, p.numero AS numero_propuesta, p.version AS version_propuesta, p.id_requerimiento,
        COALESCE(p.id_responsable, p.id_creador, oc.creado_por)                AS id_responsable,
        (SELECT COUNT(*) FROM oc_propuesta op WHERE op.id_oc = oc.id_oc AND op.eliminado_en IS NULL)
                                                                               AS propuestas_vinculadas,
        (SELECT IFNULL(SUM(op.monto_asignado), 0) FROM oc_propuesta op WHERE op.id_oc = oc.id_oc AND op.eliminado_en IS NULL)
                                                                               AS monto_asignado,
        (SELECT IFNULL(SUM(op.estado_validacion = 'validada'), 0) FROM oc_propuesta op
         WHERE op.id_oc = oc.id_oc AND op.eliminado_en IS NULL)                AS vinculaciones_validadas,
        (SELECT IFNULL(SUM(op.estado_validacion = 'observada'), 0) FROM oc_propuesta op
         WHERE op.id_oc = oc.id_oc AND op.eliminado_en IS NULL)                AS vinculaciones_observadas,
        (SELECT IFNULL(SUM(op.tipo_observacion = 'correccion_cliente'), 0) FROM oc_propuesta op
         WHERE op.id_oc = oc.id_oc AND op.eliminado_en IS NULL AND op.estado_validacion = 'observada')
                                                                               AS pendientes_correccion,
        (SELECT IFNULL(SUM(v.advertencias + v.criticas), 0) FROM oc_propuesta op
         JOIN orden_compra_validacion v ON v.id_validacion = op.id_validacion
         WHERE op.id_oc = oc.id_oc AND op.eliminado_en IS NULL)                AS alertas_ia,
        (SELECT CASE MAX(CASE op.resultado_ia WHEN 'critico' THEN 3 WHEN 'advertencia' THEN 2 WHEN 'ok' THEN 1 END)
                    WHEN 3 THEN 'critico' WHEN 2 THEN 'advertencia' WHEN 1 THEN 'ok' END
         FROM oc_propuesta op WHERE op.id_oc = oc.id_oc AND op.eliminado_en IS NULL)
                                                                               AS resultado_ia,
        FN_ExpedienteDePropuesta(oc.id_propuesta)                              AS id_expediente
    FROM orden_compra oc
    LEFT JOIN propuesta_comercial p ON p.id_propuesta = oc.id_propuesta
    JOIN usuario u ON u.id_usuario = COALESCE(p.id_responsable, p.id_creador, oc.creado_por)
    WHERE oc.eliminado_en IS NULL
      AND (v_todas = 1 OR u.area = v_area)
      AND (IFNULL(p_id_oc, 0) = 0 OR oc.id_oc = p_id_oc);

    DROP TEMPORARY TABLE IF EXISTS tmp_oc;
    CREATE TEMPORARY TABLE tmp_oc AS
    SELECT b.*,
        b.monto_oc - b.monto_asignado                                          AS saldo_oc,
        IF(b.monto_oc > 0, ROUND(b.monto_asignado * 100 / b.monto_oc, 2), 0)   AS asignado_pct,
        b.estado                                                               AS estado_visual,
        (b.estado IN ('autogenerada', 'pendiente_reemplazo') AND b.reemplazada_por IS NULL) AS pendiente_reemplazo
    FROM tmp_oc_base b;

    DROP TEMPORARY TABLE IF EXISTS tmp_oc_base;
END$$

DELIMITER ;
