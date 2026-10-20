-- Expediente Digital (interno, HU-29/30/34): cálculo compartido de los expedientes.
-- Llena la tabla temporal tmp_exp. El que llama hace DROP TEMPORARY TABLE tmp_exp al terminar.
-- p_id_expediente NULL = todos (bandeja). Un id que no existe (o 0) no devuelve filas.
--
-- Etapa (etapa):
--   Hasta la Orden de Compra la etapa se deduce de los módulos comerciales (no se guarda):
--     requerimiento  sin propuesta vigente (o la última fue anulada)
--     propuesta      propuesta en borrador, devuelta para corrección, rechazada en VB, revocada o vencida
--     visto_bueno    propuesta pendiente de VB o de revocación
--     orden_compra   VB aprobado (envío al cliente, aceptación y OC)
--     cerrado        RQ anulado o cerrado, o el cliente rechazó la propuesta
--   Desde Programación (OC validada o autogenerada, Sprint 4) la etapa es la guardada en el expediente y avanza
--   desde el expediente (HU-34).
--
-- Estado (estado), por prioridad: cerrado, bloqueado (bloqueos abiertos), sla_vencido,
--   con_excepcion (excepciones abiertas), listo_para_avanzar (cumple los requisitos de la etapa), activo.
--
-- Requisitos que se verifican solos (para "listo para avanzar" y el panel de validaciones):
--   oc_valida, os_generada, cliente_confirmado, sctr_vigente, ats_cargado, os_finalizada,
--   informe_tecnico, acta_conformidad, factura (documento interno de ese tipo, cargado para su etapa y visible
--   para el área responsable de esa etapa: interno o de su área).
DROP PROCEDURE IF EXISTS SP_CalcularExpedientes;

DELIMITER $$

CREATE PROCEDURE SP_CalcularExpedientes(
    IN p_id_usuario    BIGINT,
    IN p_id_expediente BIGINT
)
BEGIN
    -- ── Paso 1: expediente, RQ, cliente y propuesta vigente ──────────────────
    DROP TEMPORARY TABLE IF EXISTS tmp_exp_1;
    CREATE TEMPORARY TABLE tmp_exp_1 AS
    SELECT
        e.id_expediente, e.numero, e.id_requerimiento, e.etapa_actual AS etapa_guardada, e.estado AS estado_guardado,
        e.id_responsable_actual, e.area_responsable AS area_guardada, e.fecha_etapa, e.sla_horas AS sla_guardado,
        e.fecha_limite_sla, e.fecha_creacion, e.fecha_cierre, e.modificado_en, e.id_orden_compra AS id_oc_expediente,
        COALESCE(e.id_cliente, r.id_cliente)                              AS id_cliente,
        r.numero AS numero_rq, r.estado AS estado_rq, r.fecha_creacion AS fecha_rq, r.id_responsable AS id_responsable_rq,
        r.id_prioridad, r.id_sede, r.descripcion AS descripcion_rq,
        COALESCE(
            (SELECT p.id_propuesta FROM propuesta_comercial p
             WHERE p.id_requerimiento = e.id_requerimiento AND p.eliminado_en IS NULL
             ORDER BY (p.estado <> 'anulado') DESC, p.id_propuesta DESC LIMIT 1),
            e.id_propuesta)                                                AS id_propuesta,
        (SELECT MIN(p.fecha_creacion) FROM propuesta_comercial p
         WHERE p.id_requerimiento = e.id_requerimiento AND p.eliminado_en IS NULL) AS fecha_primera_propuesta
    FROM expediente_digital e
    LEFT JOIN requerimiento r ON r.id_requerimiento = e.id_requerimiento
    WHERE e.eliminado_en IS NULL
      AND (p_id_expediente IS NULL OR e.id_expediente = p_id_expediente);

    -- ── Paso 2: datos de la propuesta, VB, OC, OS/OM, bloqueos y requisitos ──
    DROP TEMPORARY TABLE IF EXISTS tmp_exp_2;
    CREATE TEMPORARY TABLE tmp_exp_2 AS
    SELECT b.*,
        p.numero AS numero_propuesta, p.version AS version_propuesta, p.estado AS estado_propuesta,
        p.tipo_servicio, p.id_responsable AS id_responsable_propuesta, p.fecha_creacion AS fecha_propuesta,
        p.fecha_anulacion, p.modificado_en AS propuesta_modificada,
        (SELECT COUNT(*) FROM propuesta_equipo pe WHERE pe.id_propuesta = b.id_propuesta)            AS equipos,
        (SELECT s.estado FROM seguimiento_comercial s
         WHERE s.id_propuesta = b.id_propuesta AND s.eliminado_en IS NULL
         ORDER BY s.id_seguimiento DESC LIMIT 1)                                                     AS estado_seguimiento,
        (SELECT v.id_aprobador FROM visto_bueno v
         WHERE v.id_propuesta = b.id_propuesta AND v.tipo = 'aprobacion' AND v.estado = 'pendiente' AND v.eliminado_en IS NULL
         ORDER BY v.id_vb DESC LIMIT 1)                                                              AS id_aprobador_vb,
        (SELECT MAX(v.fecha_solicitud) FROM visto_bueno v
         WHERE v.id_propuesta = b.id_propuesta AND v.tipo = 'aprobacion' AND v.eliminado_en IS NULL)  AS fecha_solicitud_vb,
        (SELECT MAX(v.fecha_respuesta) FROM visto_bueno v
         WHERE v.id_propuesta = b.id_propuesta AND v.tipo = 'aprobacion' AND v.estado = 'aprobado' AND v.eliminado_en IS NULL) AS fecha_aprobacion_vb,
        -- OC que cubren la propuesta (vinculaciones activas de OC no anuladas)
        (SELECT GROUP_CONCAT(DISTINCT oc.numero_oc ORDER BY oc.id_oc SEPARATOR ', ')
         FROM orden_compra oc
         JOIN oc_propuesta op ON op.id_oc = oc.id_oc AND op.id_propuesta = b.id_propuesta AND op.eliminado_en IS NULL
         WHERE oc.eliminado_en IS NULL AND oc.estado <> 'anulada')                                  AS numeros_oc,
        (SELECT MIN(oc.fecha_registro) FROM orden_compra oc
         JOIN oc_propuesta op ON op.id_oc = oc.id_oc AND op.id_propuesta = b.id_propuesta AND op.eliminado_en IS NULL
         WHERE oc.eliminado_en IS NULL AND oc.estado <> 'anulada')                                  AS fecha_primera_oc,
        -- Fin de la etapa OC: la vinculación validada (o la OC autogenerada) que habilitó la programación
        (SELECT MIN(IF(oc.es_autogenerada = 1, oc.fecha_registro, op.fecha_decision)) FROM orden_compra oc
         JOIN oc_propuesta op ON op.id_oc = oc.id_oc AND op.id_propuesta = b.id_propuesta AND op.eliminado_en IS NULL
         WHERE oc.eliminado_en IS NULL AND oc.estado <> 'anulada'
           AND (op.estado_validacion = 'validada' OR (oc.es_autogenerada = 1 AND oc.reemplazada_por IS NULL)))
                                                                                                    AS fecha_liberacion_oc,
        EXISTS (SELECT 1 FROM orden_compra oc
                JOIN oc_propuesta op ON op.id_oc = oc.id_oc AND op.id_propuesta = b.id_propuesta AND op.eliminado_en IS NULL
                WHERE oc.eliminado_en IS NULL AND oc.estado <> 'anulada'
                  AND (op.estado_validacion = 'validada' OR (oc.es_autogenerada = 1 AND oc.reemplazada_por IS NULL)))
                                                                                                    AS oc_valida,
        (SELECT GROUP_CONCAT(os.numero ORDER BY os.id_os SEPARATOR ', ') FROM orden_servicio os
         WHERE os.id_expediente = b.id_expediente AND os.eliminado_en IS NULL AND os.estado <> 'anulada')   AS numeros_os,
        (SELECT GROUP_CONCAT(om.numero ORDER BY om.id_om SEPARATOR ', ') FROM orden_metrologia om
         WHERE om.id_expediente = b.id_expediente AND om.eliminado_en IS NULL AND om.estado <> 'anulada')   AS numeros_om,
        EXISTS (SELECT 1 FROM orden_servicio os
                WHERE os.id_expediente = b.id_expediente AND os.eliminado_en IS NULL AND os.estado <> 'anulada') AS os_generada,
        EXISTS (SELECT 1 FROM orden_servicio os
                WHERE os.id_expediente = b.id_expediente AND os.eliminado_en IS NULL AND os.estado <> 'anulada'
                  AND os.confirmacion_cliente = 1)                                                   AS cliente_confirmado,
        EXISTS (SELECT 1 FROM orden_servicio os
                WHERE os.id_expediente = b.id_expediente AND os.eliminado_en IS NULL AND os.estado = 'finalizada')
        AND NOT EXISTS (SELECT 1 FROM orden_servicio os
                        WHERE os.id_expediente = b.id_expediente AND os.eliminado_en IS NULL
                          AND os.estado NOT IN ('finalizada', 'anulada'))                            AS os_finalizada,
        -- Personal de las OS: cuántos son y cuántos no tienen SCTR vigente (TIPO_DOCUMENTO_SSOMA 1 = SCTR)
        (SELECT COUNT(*) FROM os_personal op
         JOIN orden_servicio os ON os.id_os = op.id_os AND os.eliminado_en IS NULL AND os.estado <> 'anulada'
         WHERE os.id_expediente = b.id_expediente AND op.eliminado_en IS NULL)                        AS personal_os,
        (SELECT COUNT(*) FROM os_personal op
         JOIN orden_servicio os ON os.id_os = op.id_os AND os.eliminado_en IS NULL AND os.estado <> 'anulada'
         WHERE os.id_expediente = b.id_expediente AND op.eliminado_en IS NULL
           AND NOT EXISTS (SELECT 1 FROM ssoma_documento sd
                           WHERE sd.id_os = op.id_os AND sd.id_usuario = op.id_usuario AND sd.id_requisito = 1
                             AND sd.eliminado_en IS NULL AND sd.estado IN ('cargado', 'aprobado')
                             AND (sd.fecha_vencimiento IS NULL OR sd.fecha_vencimiento >= CURDATE())))  AS personal_sin_sctr,
        EXISTS (SELECT 1 FROM ssoma_documento sd
                JOIN orden_servicio os ON os.id_os = sd.id_os AND os.eliminado_en IS NULL AND os.estado <> 'anulada'
                WHERE os.id_expediente = b.id_expediente AND sd.id_requisito = 2 AND sd.eliminado_en IS NULL
                  AND sd.estado IN ('cargado', 'aprobado'))                                          AS ats_cargado,
        EXISTS (SELECT 1 FROM documento_adjunto d
                JOIN tabla_maestra t ON t.IdMaestro = 96 AND t.IdEmpresa = 1 AND t.Num1 = d.id_tipo_documento
                WHERE d.entidad_tipo = 'expediente' AND d.id_entidad = b.id_expediente AND d.eliminado_en IS NULL
                  AND t.String2 = 'INFORME_TECNICO'
                  AND JSON_UNQUOTE(JSON_EXTRACT(d.metadatos, '$.etapa')) = 'revision'
                  AND (d.id_visibilidad IN (1, 5)
                       OR d.id_visibilidad IN (SELECT v.Num1 FROM tabla_maestra v
                                               WHERE v.IdMaestro = 35 AND v.IdEmpresa = 1 AND LOWER(v.String2) = 'servicio_tecnico')))                                                 AS informe_tecnico,
        EXISTS (SELECT 1 FROM documento_adjunto d
                JOIN tabla_maestra t ON t.IdMaestro = 96 AND t.IdEmpresa = 1 AND t.Num1 = d.id_tipo_documento
                WHERE d.entidad_tipo = 'expediente' AND d.id_entidad = b.id_expediente AND d.eliminado_en IS NULL
                  AND t.String2 = 'ACTA_CONFORMIDAD'
                  AND JSON_UNQUOTE(JSON_EXTRACT(d.metadatos, '$.etapa')) = 'conformidad'
                  AND (d.id_visibilidad IN (1, 5)
                       OR d.id_visibilidad IN (SELECT v.Num1 FROM tabla_maestra v
                                               WHERE v.IdMaestro = 35 AND v.IdEmpresa = 1 AND LOWER(v.String2) = 'comercial')))                                                AS acta_conformidad,
        EXISTS (SELECT 1 FROM documento_adjunto d
                JOIN tabla_maestra t ON t.IdMaestro = 96 AND t.IdEmpresa = 1 AND t.Num1 = d.id_tipo_documento
                WHERE d.entidad_tipo = 'expediente' AND d.id_entidad = b.id_expediente AND d.eliminado_en IS NULL
                  AND t.String2 = 'FACTURA'
                  AND JSON_UNQUOTE(JSON_EXTRACT(d.metadatos, '$.etapa')) = 'facturacion'
                  AND (d.id_visibilidad IN (1, 5)
                       OR d.id_visibilidad IN (SELECT v.Num1 FROM tabla_maestra v
                                               WHERE v.IdMaestro = 35 AND v.IdEmpresa = 1 AND LOWER(v.String2) = 'administracion')))                                                         AS factura,
        (SELECT COUNT(*) FROM expediente_bloqueador x
         WHERE x.id_expediente = b.id_expediente AND x.resuelto = 0 AND x.eliminado_en IS NULL AND x.clase = 'bloqueo')   AS bloqueos,
        (SELECT COUNT(*) FROM expediente_bloqueador x
         WHERE x.id_expediente = b.id_expediente AND x.resuelto = 0 AND x.eliminado_en IS NULL AND x.clase = 'excepcion') AS excepciones,
        (SELECT x.descripcion FROM expediente_bloqueador x
         WHERE x.id_expediente = b.id_expediente AND x.resuelto = 0 AND x.eliminado_en IS NULL AND x.clase = 'bloqueo'
         ORDER BY x.critico DESC, x.id_bloqueador LIMIT 1)                                           AS motivo_bloqueo
    FROM tmp_exp_1 b
    LEFT JOIN propuesta_comercial p ON p.id_propuesta = b.id_propuesta;

    DROP TEMPORARY TABLE IF EXISTS tmp_exp_1;

    -- ── Paso 3: etapa, inicio de la etapa y responsable ───────────────────────
    DROP TEMPORARY TABLE IF EXISTS tmp_exp_3;
    CREATE TEMPORARY TABLE tmp_exp_3 AS
    SELECT c.*,
        CASE
            WHEN c.etapa_guardada NOT IN ('requerimiento', 'propuesta', 'visto_bueno', 'orden_compra') THEN c.etapa_guardada
            WHEN c.estado_rq IN ('anulado', 'cerrado')                                              THEN 'cerrado'
            WHEN c.estado_seguimiento = 'cerrado_rechazo'                    THEN 'cerrado'
            WHEN c.id_propuesta IS NULL OR c.estado_propuesta = 'anulado'                             THEN 'requerimiento'
            WHEN c.estado_propuesta IN ('pendiente_vb', 'pendiente_revocacion')                       THEN 'visto_bueno'
            WHEN c.estado_propuesta IN ('aprobado', 'enviado')                                        THEN 'orden_compra'
            ELSE 'propuesta'
        END AS etapa
    FROM tmp_exp_2 c;

    DROP TEMPORARY TABLE IF EXISTS tmp_exp_2;

    DROP TEMPORARY TABLE IF EXISTS tmp_exp_4;
    CREATE TEMPORARY TABLE tmp_exp_4 AS
    SELECT d.*,
        et.Num1                                         AS orden_etapa,
        et.String1                                      AS etapa_nombre,
        IFNULL(et.Num2, 0)                              AS etapa_manual,
        (d.etapa NOT IN ('requerimiento', 'propuesta', 'visto_bueno', 'orden_compra', 'cerrado')) AS etapa_guardada_vigente,
        CASE d.etapa
            WHEN 'requerimiento' THEN IF(d.estado_propuesta = 'anulado', IFNULL(d.fecha_anulacion, d.propuesta_modificada), d.fecha_rq)
            WHEN 'propuesta'     THEN d.fecha_propuesta
            WHEN 'visto_bueno'   THEN IFNULL(d.fecha_solicitud_vb, d.propuesta_modificada)
            WHEN 'orden_compra'  THEN IFNULL(d.fecha_aprobacion_vb, d.propuesta_modificada)
            WHEN 'cerrado'       THEN IFNULL(d.fecha_cierre, d.modificado_en)
            ELSE IFNULL(d.fecha_etapa, IFNULL(d.modificado_en, d.fecha_creacion))
        END                                             AS inicio_etapa,
        CASE
            WHEN d.etapa NOT IN ('requerimiento', 'propuesta', 'visto_bueno', 'orden_compra', 'cerrado')
                THEN IFNULL(d.area_guardada, et.String3)
            ELSE et.String3
        END                                             AS area,
        CASE d.etapa
            WHEN 'requerimiento' THEN d.id_responsable_rq
            WHEN 'propuesta'     THEN d.id_responsable_propuesta
            WHEN 'visto_bueno'   THEN IFNULL(d.id_aprobador_vb, d.id_responsable_propuesta)
            WHEN 'orden_compra'  THEN d.id_responsable_propuesta
            WHEN 'cerrado'       THEN NULL
            ELSE d.id_responsable_actual
        END                                             AS id_responsable,
        IFNULL(CASE WHEN d.etapa NOT IN ('requerimiento', 'propuesta', 'visto_bueno', 'orden_compra', 'cerrado')
                    THEN d.sla_guardado END,
               (SELECT CAST(MAX(s.Num2) AS SIGNED) FROM tabla_maestra s
                WHERE s.IdMaestro = 49 AND s.IdEmpresa = 1 AND s.String1 = 'expediente' AND s.String2 = d.etapa)) AS sla_horas,
        (SELECT CAST(MAX(s.Num3) AS SIGNED) FROM tabla_maestra s
         WHERE s.IdMaestro = 49 AND s.IdEmpresa = 1 AND s.String1 = 'expediente' AND s.String2 = d.etapa)        AS sla_alerta_horas
    FROM tmp_exp_3 d
    LEFT JOIN tabla_maestra et ON et.IdMaestro = 97 AND et.IdEmpresa = 1 AND et.String2 = d.etapa;

    DROP TEMPORARY TABLE IF EXISTS tmp_exp_3;

    -- ── Paso 4: SLA, requisitos de la etapa y estado ──────────────────────────
    DROP TEMPORARY TABLE IF EXISTS tmp_exp_5;
    CREATE TEMPORARY TABLE tmp_exp_5 AS
    SELECT f.*,
        CASE WHEN f.etapa = 'cerrado' THEN NULL
             WHEN f.etapa_guardada_vigente = 1 AND f.fecha_limite_sla IS NOT NULL THEN f.fecha_limite_sla
             WHEN f.sla_horas IS NULL OR f.inicio_etapa IS NULL THEN NULL
             ELSE f.inicio_etapa + INTERVAL f.sla_horas HOUR END                                     AS fecha_limite,
        (f.personal_os > 0 AND f.personal_sin_sctr = 0)                                              AS sctr_vigente,
        CASE f.etapa
            WHEN 'orden_compra' THEN f.oc_valida = 1
            WHEN 'programacion' THEN f.oc_valida = 1 AND f.os_generada = 1 AND f.cliente_confirmado = 1
            WHEN 'ssoma'        THEN f.oc_valida = 1 AND f.os_generada = 1 AND f.cliente_confirmado = 1
                                     AND f.personal_os > 0 AND f.personal_sin_sctr = 0 AND f.ats_cargado = 1
            WHEN 'ejecucion'    THEN f.os_finalizada = 1
            WHEN 'revision'     THEN f.informe_tecnico = 1
            WHEN 'conformidad'  THEN f.acta_conformidad = 1
            WHEN 'facturacion'  THEN f.factura = 1
            ELSE 0
        END                                                                                          AS requisitos_cumplidos
    FROM tmp_exp_4 f;

    DROP TEMPORARY TABLE IF EXISTS tmp_exp_4;

    DROP TEMPORARY TABLE IF EXISTS tmp_exp;
    CREATE TEMPORARY TABLE tmp_exp AS
    SELECT g.*,
        (g.fecha_limite IS NOT NULL AND NOW() > g.fecha_limite)                                      AS sla_vencido,
        CASE WHEN g.fecha_limite IS NULL                                  THEN NULL
             WHEN NOW() > g.fecha_limite                                  THEN 'vencido'
             -- CONFIG_SLA Num3 = horas antes del vencimiento en que se alerta (igual que el seguimiento comercial)
             WHEN g.sla_alerta_horas IS NOT NULL
                  AND NOW() >= g.fecha_limite - INTERVAL g.sla_alerta_horas HOUR  THEN 'en_riesgo'
             ELSE 'en_plazo' END                                                                     AS sla_estado,
        IF(g.fecha_limite IS NULL, NULL, TIMESTAMPDIFF(MINUTE, NOW(), g.fecha_limite))               AS sla_minutos_restantes,
        (g.etapa <> 'cerrado' AND g.bloqueos = 0 AND g.requisitos_cumplidos = 1)                     AS listo,
        CASE
            WHEN g.etapa = 'cerrado'                                    THEN 'cerrado'
            WHEN g.bloqueos > 0                                         THEN 'bloqueado'
            WHEN g.fecha_limite IS NOT NULL AND NOW() > g.fecha_limite  THEN 'sla_vencido'
            WHEN g.excepciones > 0                                      THEN 'con_excepcion'
            WHEN g.requisitos_cumplidos = 1                             THEN 'listo_para_avanzar'
            ELSE 'activo'
        END                                                                                          AS estado,
        IF(g.etapa = 'cerrado', 100, ROUND((IFNULL(g.orden_etapa, 1) - 1) * 100 / 10))               AS progreso
    FROM tmp_exp_5 g;

    DROP TEMPORARY TABLE IF EXISTS tmp_exp_5;
END$$

DELIMITER ;
