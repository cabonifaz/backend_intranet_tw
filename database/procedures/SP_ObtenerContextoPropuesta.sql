-- HU-09 — Contexto del modal "Detalle de Propuesta"
--   Complementa a SP_ObtenerPropuestaPorId (que ya devuelve cabecera, ítems,
--   textos, formas de pago y equipos) con lo que solo necesita el detalle:
--   2. Situación: versión vigente, PDF, SLA, contrato marco y si tiene OC
--   3. Documentos vinculados (RQ, expediente, OC y adjuntos de la propuesta)
--   4. Versiones (todas las de la misma numeración)
--   5. Actividad (auditoria_evento de esta versión, más reciente primero)
--   SLA: en 'pendiente_vb' se mide contra el VB pendiente (o CONFIG_SLA si aún
--   no hay registro); en 'enviado' contra la fecha de expiración (vigencia).
DROP PROCEDURE IF EXISTS SP_ObtenerContextoPropuesta;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerContextoPropuesta(
    IN p_id_propuesta BIGINT
)
proc: BEGIN
    DECLARE v_numero      VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_version     INT;
    DECLARE v_estado      VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_rq       BIGINT;
    DECLARE v_id_cliente  BIGINT;

    SELECT numero, version, estado, id_requerimiento, id_cliente
      INTO v_numero, v_version, v_estado, v_id_rq, v_id_cliente
    FROM propuesta_comercial
    WHERE id_propuesta = p_id_propuesta AND eliminado_en IS NULL;

    IF v_numero IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Propuesta no encontrada.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- 1. Header
    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Situación
    SELECT
        p.estado,
        p.fecha_pdf,
        p.fecha_envio,
        p.fecha_expiracion,
        NOT EXISTS (SELECT 1 FROM propuesta_comercial x
                    WHERE x.numero = v_numero AND x.version > v_version
                      AND x.eliminado_en IS NULL)                       AS es_ultima_version,
        EXISTS (SELECT 1 FROM orden_compra oc
                WHERE oc.eliminado_en IS NULL AND oc.estado <> 'anulada'
                  AND (oc.id_propuesta = p.id_propuesta
                       OR oc.id_oc IN (SELECT op.id_oc FROM oc_propuesta op
                                       WHERE op.id_propuesta = p.id_propuesta
                                         AND op.eliminado_en IS NULL)))  AS tiene_oc,
        -- SLA
        CASE
            WHEN p.estado = 'pendiente_vb' THEN 'visto_bueno'
            WHEN p.estado = 'enviado' AND p.fecha_expiracion IS NOT NULL THEN 'vigencia'
            ELSE NULL
        END AS sla_tipo,
        CASE
            WHEN p.estado = 'pendiente_vb' THEN
                COALESCE(
                    (SELECT DATE_ADD(vb.fecha_solicitud, INTERVAL vb.sla_horas HOUR)
                     FROM visto_bueno vb
                     WHERE vb.id_propuesta = p.id_propuesta AND vb.estado = 'pendiente'
                       AND vb.eliminado_en IS NULL
                     ORDER BY vb.fecha_solicitud DESC LIMIT 1),
                    DATE_ADD(COALESCE(p.modificado_en, p.fecha_creacion), INTERVAL
                        (SELECT CAST(tm.Num2 AS SIGNED) FROM tabla_maestra tm
                         WHERE tm.IdMaestro = 49 AND tm.IdEmpresa = 1
                           AND tm.String1 = 'propuesta' AND tm.String2 = 'pendiente_vb'
                         LIMIT 1) HOUR))
            WHEN p.estado = 'enviado' AND p.fecha_expiracion IS NOT NULL THEN
                TIMESTAMP(p.fecha_expiracion, '23:59:59')
            ELSE NULL
        END AS sla_vence_en,
        -- Contrato marco vigente del cliente
        (SELECT cm.numero FROM contrato_marco cm
         WHERE cm.id_cliente = v_id_cliente AND cm.estado = 'vigente'
           AND cm.eliminado_en IS NULL
           AND cm.fecha_inicio <= CURDATE()
           AND (cm.fecha_fin IS NULL OR cm.fecha_fin >= CURDATE())
         ORDER BY cm.fecha_inicio DESC LIMIT 1)                         AS numero_contrato_marco,
        NOW() AS ahora
    FROM propuesta_comercial p
    WHERE p.id_propuesta = p_id_propuesta;

    -- 3. Documentos vinculados
    SELECT 'requerimiento' AS tipo, r.id_requerimiento AS id_entidad, r.numero AS codigo,
           'Solicitud de cotización' AS descripcion, r.estado, NULL AS url, r.fecha_creacion AS fecha
    FROM requerimiento r
    WHERE r.id_requerimiento = v_id_rq

    UNION ALL
    SELECT 'expediente', e.id_expediente, e.numero, 'Expediente digital', e.estado, NULL, e.fecha_creacion
    FROM expediente_digital e
    WHERE e.eliminado_en IS NULL
      AND (e.id_propuesta = p_id_propuesta OR e.id_requerimiento = v_id_rq)

    UNION ALL
    SELECT 'orden_compra', oc.id_oc, oc.numero_oc, 'Orden de compra', oc.estado,
           oc.url_archivo_pdf, oc.fecha_registro
    FROM orden_compra oc
    WHERE oc.eliminado_en IS NULL
      AND (oc.id_propuesta = p_id_propuesta
           OR oc.id_oc IN (SELECT op.id_oc FROM oc_propuesta op
                           WHERE op.id_propuesta = p_id_propuesta AND op.eliminado_en IS NULL))

    UNION ALL
    SELECT 'adjunto', d.id_documento, d.nombre_archivo, 'Documento adjunto', NULL,
           d.url_archivo, d.fecha_carga
    FROM documento_adjunto d
    WHERE d.entidad_tipo = 'propuesta' AND d.id_entidad = p_id_propuesta
      AND d.eliminado_en IS NULL
    ORDER BY fecha;

    -- 4. Versiones
    SELECT v.id_propuesta, v.version, v.estado, v.total,
           v.fecha_creacion, v.fecha_envio,
           CONCAT(u.nombre, ' ', u.apellido) AS nombre_creador,
           tm.String1                       AS motivo_nueva_version
    FROM propuesta_comercial v
    LEFT JOIN usuario u        ON u.id_usuario = v.id_creador
    LEFT JOIN tabla_maestra tm ON tm.IdMaestro = 11 AND tm.IdEmpresa = 1
                              AND tm.Num1 = v.id_motivo_nueva_version
    WHERE v.numero = v_numero AND v.eliminado_en IS NULL
    ORDER BY v.version DESC;

    -- 5. Actividad
    SELECT a.id_auditoria, a.accion, a.estado_anterior, a.estado_nuevo, a.descripcion,
           a.registrado_en, CONCAT(u.nombre, ' ', u.apellido) AS nombre_usuario
    FROM auditoria_evento a
    LEFT JOIN usuario u ON u.id_usuario = a.id_usuario
    WHERE a.entidad_tipo = 'propuesta' AND a.id_entidad = p_id_propuesta
    ORDER BY a.registrado_en DESC, a.id_auditoria DESC
    LIMIT 100;
END$$

DELIMITER ;
