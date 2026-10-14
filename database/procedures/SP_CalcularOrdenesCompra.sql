-- HU-23 Cálculo compartido de las órdenes de compra (bandeja y detalle).
-- Llena la tabla temporal tmp_oc. El que llama debe hacer DROP TEMPORARY TABLE tmp_oc al terminar.
-- p_id_oc NULL = todas las OC en alcance.
--
-- Alcance: OC cuya propuesta principal pertenece a un responsable del área del usuario.
--   Con la acción propuesta_seguimiento_todas (admins de Gerencia y TI) todas las áreas.
--
-- Montos (en la moneda de la OC):
--   monto_propuesta      = total de la propuesta principal + lo asignado a las propuestas distribuidas (HU-27)
--   HU-27 cobertura_otros      = lo que otras OC no anuladas (misma moneda) ya asignaron a la propuesta principal
--   HU-27 monto_requerido_neto = monto_propuesta - cobertura_otros (lo que esta OC debe cubrir)
--   HU-27 monto_asignado_oc    = lo que esta OC asignó (oc_propuesta) y saldo_disponible = monto_oc - asignado
--   HU-27 faltante             = lo que aún falta cubrir de sus propuestas entre todas las OC
--   monto_aplicado  = 0 mientras la OC está pendiente de validación, luego el monto requerido neto
--   saldo           = monto_oc - monto_aplicado (negativo = saldo insuficiente)
--
-- Cobertura (cobertura_codigo):
--   pendiente        OC aún sin validar (cobertura_proyectada dice cómo quedará)
--   completa         la OC cubre exactamente la propuesta (saldo 0)
--   con_saldo        la OC cubre la propuesta y le queda saldo (se muestra como "Parcial")
--   insuficiente     el monto de la OC no alcanza para la propuesta (saldo negativo)
--   moneda_diferente la OC y la propuesta están en monedas distintas
--
-- lista_programacion: validada, vigente, sin observación, con cobertura, sin OS, sin liberar, el expediente
--   aún en la etapa de OC y sin otras OC de la propuesta pendientes de validación (complementarias).
--
-- estado (BD) guarda solo el resultado de la validación: pendiente_validacion, vigente, cobertura_parcial,
--   saldo_insuficiente, vencida, anulada. Lo que se muestra es estado_visual, que además considera la observación
--   abierta, la liberación y la cobertura.
-- estado_visual: anulada, vencida, observada, pendiente_validacion, liberada (HU-28), bloqueada, validada_parcial, validada
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

    -- ── Paso 1: datos crudos de las OC en alcance ─────────────────────────
    DROP TEMPORARY TABLE IF EXISTS tmp_oc_base;
    CREATE TEMPORARY TABLE tmp_oc_base AS
    SELECT
        oc.id_oc, oc.numero_oc, oc.id_cliente, oc.id_moneda,
        oc.monto_total                                              AS monto_oc,
        oc.estado                                                   AS estado_bd,
        oc.id_motivo_observacion, oc.id_validado_por, oc.fecha_liberacion, oc.liberado_por,
        -- Observada = tiene una observación abierta (la observación es la fuente, no id_motivo_observacion)
        EXISTS (SELECT 1 FROM orden_compra_observacion ob
                WHERE ob.id_oc = oc.id_oc AND ob.estado = 'abierta' AND ob.eliminado_en IS NULL) AS obs_abierta,
        oc.fecha_oc, oc.fecha_recepcion, oc.vigencia_desde, oc.vigencia_hasta, oc.vigencia_dias,
        oc.observaciones, oc.fecha_registro, oc.creado_por,
        (oc.url_archivo_pdf IS NOT NULL)                            AS tiene_pdf,
        oc.tipo_oc, oc.id_oc_origen,
        p.id_propuesta, p.numero AS numero_propuesta, p.version AS version_propuesta,
        p.id_requerimiento,
        COALESCE(p.id_responsable, p.id_creador, oc.creado_por)     AS id_responsable,
        -- HU-27: total de la propuesta principal + lo asignado a las propuestas distribuidas
        (SELECT IFNULL(SUM(pv.total), 0) FROM propuesta_comercial pv WHERE pv.id_propuesta = oc.id_propuesta)
        + (SELECT IFNULL(SUM(op.monto_asignado), 0) FROM oc_propuesta op
           WHERE op.id_oc = oc.id_oc AND op.eliminado_en IS NULL
             AND op.id_propuesta <> IFNULL(oc.id_propuesta, 0))                          AS monto_propuesta,
        (SELECT COUNT(*) FROM propuesta_comercial pv
         WHERE (pv.id_propuesta = oc.id_propuesta
                OR pv.id_propuesta IN (SELECT op.id_propuesta FROM oc_propuesta op
                                       WHERE op.id_oc = oc.id_oc AND op.eliminado_en IS NULL))
           AND pv.id_moneda <> oc.id_moneda)                        AS propuestas_otra_moneda,
        (SELECT IFNULL(SUM(op.monto_asignado), 0) FROM oc_propuesta op
         WHERE op.id_oc = oc.id_oc AND op.eliminado_en IS NULL)                           AS monto_asignado_oc,
        (SELECT IFNULL(SUM(op2.monto_asignado), 0) FROM oc_propuesta op2
         JOIN orden_compra o2 ON o2.id_oc = op2.id_oc AND o2.eliminado_en IS NULL AND o2.estado <> 'anulada'
             AND o2.id_moneda = (SELECT pz.id_moneda FROM propuesta_comercial pz WHERE pz.id_propuesta = op2.id_propuesta)
         WHERE op2.eliminado_en IS NULL AND op2.id_oc <> oc.id_oc
           AND op2.id_propuesta = oc.id_propuesta)                                       AS cobertura_otros,
        -- Expediente del RQ de la propuesta principal (nace con el RQ, migración 71)
        FN_ExpedienteDePropuesta(oc.id_propuesta)                                         AS id_expediente,
        -- OS de los expedientes de todas las propuestas que cubre la OC (principal y distribuidas)
        (SELECT COUNT(*) FROM orden_servicio os
         WHERE os.eliminado_en IS NULL AND os.estado <> 'anulada'
           AND (os.id_expediente = FN_ExpedienteDePropuesta(oc.id_propuesta)
                OR os.id_expediente IN (SELECT FN_ExpedienteDePropuesta(op.id_propuesta) FROM oc_propuesta op
                                        WHERE op.id_oc = oc.id_oc AND op.eliminado_en IS NULL)))  AS ordenes_servicio,
        -- El expediente ya pasó de la etapa de OC (liberado con esta u otra OC, o más avanzado)
        IFNULL((SELECT e.etapa_actual NOT IN ('requerimiento', 'propuesta', 'visto_bueno', 'orden_compra')
                FROM expediente_digital e WHERE e.id_expediente = FN_ExpedienteDePropuesta(oc.id_propuesta)), 0)
                                                                                           AS expediente_liberado,
        -- Otras OC no anuladas que también cubren la propuesta principal y aún no están validadas
        -- (pendientes u observadas): su monto se proyecta en la cobertura, pero no se puede liberar sin ellas
        (SELECT GROUP_CONCAT(o3.numero_oc ORDER BY o3.id_oc SEPARATOR ', ')
         FROM orden_compra o3
         JOIN oc_propuesta op3 ON op3.id_oc = o3.id_oc AND op3.eliminado_en IS NULL AND op3.id_propuesta = oc.id_propuesta
         WHERE o3.eliminado_en IS NULL AND o3.id_oc <> oc.id_oc AND o3.estado <> 'anulada'
           AND (o3.estado = 'pendiente_validacion'
                OR EXISTS (SELECT 1 FROM orden_compra_observacion ob3
                           WHERE ob3.id_oc = o3.id_oc AND ob3.estado = 'abierta' AND ob3.eliminado_en IS NULL)))
                                                                                           AS otras_oc_pendientes
    FROM orden_compra oc
    LEFT JOIN propuesta_comercial p ON p.id_propuesta = oc.id_propuesta
    JOIN usuario u ON u.id_usuario = COALESCE(p.id_responsable, p.id_creador, oc.creado_por)
    WHERE oc.eliminado_en IS NULL
      AND (v_todas = 1 OR u.area = v_area)
      AND (IFNULL(p_id_oc, 0) = 0 OR oc.id_oc = p_id_oc);

    -- ── Paso 2: cobertura, montos y estado visual ─────────────────────────
    DROP TEMPORARY TABLE IF EXISTS tmp_oc_cob;
    CREATE TEMPORARY TABLE tmp_oc_cob AS
    SELECT b.*,
        GREATEST(b.monto_propuesta - b.cobertura_otros, 0)                                 AS monto_requerido_neto,
        b.monto_oc - b.monto_asignado_oc                                                   AS saldo_disponible,
        GREATEST(b.monto_propuesta - b.cobertura_otros - b.monto_asignado_oc, 0)           AS faltante,
        (b.estado_bd IN ('vigente', 'cobertura_parcial', 'saldo_insuficiente'))           AS validada,
        (b.estado_bd = 'vencida'
         OR (b.estado_bd <> 'anulada' AND b.vigencia_hasta IS NOT NULL AND b.vigencia_hasta < CURDATE())) AS vencida,
        CASE
            WHEN b.propuestas_otra_moneda > 0      THEN 'moneda_diferente'
            WHEN ABS(b.monto_oc - GREATEST(b.monto_propuesta - b.cobertura_otros, 0)) < 0.01 THEN 'completa'
            WHEN b.monto_oc > GREATEST(b.monto_propuesta - b.cobertura_otros, 0)          THEN 'con_saldo'
            ELSE                                        'insuficiente'
        END                                                                                AS cobertura_proyectada,
        IF(b.monto_propuesta - b.cobertura_otros > 0 AND b.propuestas_otra_moneda = 0,
           ROUND(b.monto_oc * 100 / (b.monto_propuesta - b.cobertura_otros), 2), NULL)     AS cobertura_pct
    FROM tmp_oc_base b;

    DROP TEMPORARY TABLE IF EXISTS tmp_oc;
    CREATE TEMPORARY TABLE tmp_oc AS
    SELECT c.*,
        IF(c.validada = 1 AND c.cobertura_proyectada <> 'moneda_diferente', c.monto_requerido_neto, 0) AS monto_aplicado,
        c.monto_oc - IF(c.validada = 1 AND c.cobertura_proyectada <> 'moneda_diferente', c.monto_requerido_neto, 0) AS saldo,
        IF(c.validada = 1, c.cobertura_proyectada, 'pendiente')                            AS cobertura_codigo,
        IF(c.validada = 1 AND c.monto_oc > 0 AND c.cobertura_proyectada <> 'moneda_diferente',
           ROUND(c.monto_requerido_neto * 100 / c.monto_oc, 2), 0)                         AS utilizacion_pct,
        CASE
            WHEN c.estado_bd = 'anulada'                              THEN 'anulada'
            WHEN c.vencida = 1                                        THEN 'vencida'
            WHEN c.obs_abierta = 1                                    THEN 'observada'
            WHEN c.validada = 0                                       THEN 'pendiente_validacion'
            WHEN c.fecha_liberacion IS NOT NULL                       THEN 'liberada'
            WHEN c.cobertura_proyectada IN ('insuficiente', 'moneda_diferente')
                 OR c.estado_bd = 'saldo_insuficiente'                THEN 'bloqueada'
            WHEN c.cobertura_proyectada = 'con_saldo'
                 OR c.estado_bd = 'cobertura_parcial'                 THEN 'validada_parcial'
            ELSE                                                           'validada'
        END                                                                                AS estado_visual,
        (c.estado_bd <> 'anulada' AND c.vencida = 0 AND c.validada = 1
         AND c.obs_abierta = 0
         AND c.cobertura_proyectada IN ('completa', 'con_saldo')
         AND c.estado_bd <> 'saldo_insuficiente'
         AND c.ordenes_servicio = 0
         AND c.fecha_liberacion IS NULL
         AND c.expediente_liberado = 0
         AND c.otras_oc_pendientes IS NULL)                                                AS lista_programacion
    FROM tmp_oc_cob c;

    DROP TEMPORARY TABLE IF EXISTS tmp_oc_cob;
    DROP TEMPORARY TABLE IF EXISTS tmp_oc_base;
END$$

DELIMITER ;
