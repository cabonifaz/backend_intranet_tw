-- HU-08 — Tarjetas resumen de la bandeja de propuestas (solo versión actual de cada propuesta)
--   pendientes      : abiertas sin enviar (borrador + pendiente de VB)
--   variacion_pct   : pendientes creadas este mes vs. el mes anterior (%)
--   por_visto_bueno : pendiente_vb
--   por_enviar      : aprobado (VB aprobado, falta enviar al cliente) y sin orden de compra
--   en_seguimiento  : enviado y aún sin orden de compra
--   sla_vencidos    : abiertas (borrador / pendiente_vb / enviado) con vigencia vencida
--   Filtros opcionales: año y comercial (los mismos del listado).
DROP PROCEDURE IF EXISTS SP_ObtenerKpisPropuestas;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerKpisPropuestas(
    IN p_anio         INT,
    IN p_id_comercial BIGINT
)
BEGIN
    DECLARE v_mes_actual   INT;
    DECLARE v_mes_anterior INT;

    DROP TEMPORARY TABLE IF EXISTS tmp_kpi_prop;
    CREATE TEMPORARY TABLE tmp_kpi_prop AS
        SELECT p.estado, p.fecha_creacion, p.fecha_expiracion,
               EXISTS (SELECT 1 FROM orden_compra oc
                       WHERE oc.eliminado_en IS NULL AND oc.estado <> 'anulada'
                         AND (oc.id_propuesta = p.id_propuesta
                              OR oc.id_oc IN (SELECT op.id_oc FROM oc_propuesta op
                                              WHERE op.id_propuesta = p.id_propuesta AND op.eliminado_en IS NULL))) AS tiene_oc
        FROM propuesta_comercial p
        WHERE p.eliminado_en IS NULL
          AND (p_anio IS NULL OR p_anio = 0 OR YEAR(p.fecha_creacion) = p_anio)
          AND (p_id_comercial IS NULL OR p_id_comercial = 0 OR COALESCE(p.id_responsable, p.id_creador) = p_id_comercial)
          AND p.version = (SELECT MAX(p2.version) FROM propuesta_comercial p2
                           WHERE p2.numero = p.numero AND p2.eliminado_en IS NULL);

    SELECT COUNT(*) INTO v_mes_actual FROM tmp_kpi_prop
    WHERE estado IN ('borrador', 'pendiente_vb')
      AND fecha_creacion >= DATE_FORMAT(CURDATE(), '%Y-%m-01');

    SELECT COUNT(*) INTO v_mes_anterior FROM tmp_kpi_prop
    WHERE estado IN ('borrador', 'pendiente_vb')
      AND fecha_creacion >= DATE_FORMAT(CURDATE() - INTERVAL 1 MONTH, '%Y-%m-01')
      AND fecha_creacion <  DATE_FORMAT(CURDATE(), '%Y-%m-01');

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT
        SUM(estado IN ('borrador', 'pendiente_vb'))  AS pendientes,
        IF(v_mes_anterior = 0, IF(v_mes_actual > 0, 100, 0),
           ROUND((v_mes_actual - v_mes_anterior) * 100 / v_mes_anterior, 1)) AS variacion_pendientes,
        SUM(estado = 'pendiente_vb')                 AS por_visto_bueno,
        SUM(estado = 'aprobado' AND tiene_oc = 0)   AS por_enviar,
        SUM(estado = 'enviado'  AND tiene_oc = 0)   AS en_seguimiento,
        SUM(estado IN ('borrador', 'pendiente_vb', 'enviado')
            AND fecha_expiracion IS NOT NULL AND fecha_expiracion < CURDATE()) AS sla_vencidos
    FROM tmp_kpi_prop;

    DROP TEMPORARY TABLE IF EXISTS tmp_kpi_prop;
END$$

DELIMITER ;
