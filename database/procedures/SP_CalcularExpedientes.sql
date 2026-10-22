-- Expediente Digital (interno, HU-29/30/33): cálculo compartido de los expedientes (refinamiento Sprint 4).
-- Llena la tabla temporal tmp_exp. El que llama hace DROP TEMPORARY TABLE tmp_exp al terminar.
-- p_id_expediente NULL = todos (bandeja). Un id que no existe (o 0) no devuelve filas.
-- También deja tmp_exp_blq (bloqueos y excepciones, ver SP_CargarBloqueosExpediente): el que llama la borra.
--
-- El expediente nace con el RQ y es de consulta: la etapa se calcula sola desde los módulos origen (no se guarda ni se
-- avanza a mano). Propuesta activa del RQ: la más avanzada entre la última versión de cada propuesta
-- (aceptada > enviada/aprobada > en VB > en elaboración > rechazada por el cliente; las anuladas no cuentan).
--   requerimiento   sin propuesta vigente
--   propuesta       en borrador, devuelta o rechazada en VB, revocada o vencida
--   visto_bueno     pendiente de VB o de revocación
--   seguimiento     VB aprobado o enviada al cliente (seguimiento comercial)
--   orden_compra    aceptada por el cliente, sin OC validada
--   orden_servicio  OC validada (o autogenerada vigente): se genera la OS y se coordina con el cliente (hasta su
--                   confirmación)
--   programacion    OS confirmada por el cliente, sin personal asignado (calendario y recursos)
--   ssoma           OS confirmada con personal asignado, antes de salir a campo (habilitación SSOMA)
--   ejecucion       OS en ruta, en ejecución o pausada
--   cierre          todas las OS finalizadas, sin conformidad del cliente
--   cerrado         RQ anulado o cerrado, propuesta rechazada por el cliente o conformidad registrada en todas las OS
--
-- Estado global: cerrado, bloqueado (bloqueos abiertos), con_excepcion (excepciones abiertas) o activo.
-- listo_para_avanzar: sin bloqueos ni excepciones, SLA no vencido y la etapa ya cumple lo suyo y solo espera la acción
--   del responsable: propuesta con ítems lista para pedir VB, VB aprobado aún no enviado al cliente, OC registrada
--   pendiente de decisión, personal de la OS habilitado por SSOMA, o informe técnico aprobado esperando conformidad.
-- SLA de la etapa: CONFIG_SLA (49) String1 = 'expediente'. Si se reasignó con "Reiniciar SLA" en la etapa actual,
--   el plazo se cuenta desde la reasignación (expediente_digital.sla_reinicio).
DROP PROCEDURE IF EXISTS SP_CalcularExpedientes;

DELIMITER $$

CREATE PROCEDURE SP_CalcularExpedientes(
    IN p_id_usuario    BIGINT,
    IN p_id_expediente BIGINT
)
BEGIN
    SET SESSION group_concat_max_len = 1000000;

    -- ── 1. Expediente y RQ ──────────────────────────────────────────────────
    DROP TEMPORARY TABLE IF EXISTS tmp_exp_1;
    CREATE TEMPORARY TABLE tmp_exp_1 (PRIMARY KEY (id_expediente)) AS
    SELECT e.id_expediente, e.numero, e.id_requerimiento, e.fecha_creacion, e.id_responsable_actual,
           e.sla_reinicio, e.sla_reinicio_etapa, e.id_propuesta AS id_propuesta_exp,
           COALESCE(e.id_cliente, r.id_cliente)                    AS id_cliente,
           r.numero AS numero_rq, r.estado AS estado_rq, r.descripcion AS descripcion_rq,
           IFNULL(r.fecha_creacion, e.fecha_creacion)              AS fecha_rq,
           r.fecha_cierre AS fecha_cierre_rq, r.modificado_en AS rq_modificado,
           COALESCE(r.id_responsable, r.id_usuario_creador)        AS id_responsable_rq,
           r.id_prioridad, r.id_sede, r.id_area AS id_area_rq
    FROM expediente_digital e
    LEFT JOIN requerimiento r ON r.id_requerimiento = e.id_requerimiento
    WHERE e.eliminado_en IS NULL
      AND (p_id_expediente IS NULL OR e.id_expediente = p_id_expediente);

    -- ── 2. Propuestas: última versión de cada número, con su rango ──────────
    DROP TEMPORARY TABLE IF EXISTS tmp_exp_prop;
    CREATE TEMPORARY TABLE tmp_exp_prop AS
    WITH versiones AS (
        SELECT b.id_expediente, p.id_propuesta, p.numero, p.version, p.estado,
               ROW_NUMBER() OVER (PARTITION BY b.id_expediente, p.numero ORDER BY p.version DESC, p.id_propuesta DESC) AS rn
        FROM tmp_exp_1 b
        JOIN propuesta_comercial p ON p.eliminado_en IS NULL
             AND (p.id_requerimiento = b.id_requerimiento OR (b.id_requerimiento IS NULL AND p.id_propuesta = b.id_propuesta_exp))
    )
    SELECT v.id_expediente, v.id_propuesta, v.numero, v.version, v.estado,
           CASE
               WHEN v.estado = 'aceptado'                                THEN 1
               WHEN v.estado IN ('enviado', 'aprobado')                  THEN 2
               WHEN v.estado IN ('pendiente_vb', 'pendiente_revocacion') THEN 3
               WHEN v.estado = 'anulado'                                 THEN 9
               WHEN v.estado = 'rechazado' AND EXISTS (
                        SELECT 1 FROM seguimiento_comercial s
                        WHERE s.id_propuesta = v.id_propuesta AND s.eliminado_en IS NULL AND s.estado = 'cerrado_rechazo')
                                                                         THEN 6
               ELSE 4
           END AS rango
    FROM versiones v
    WHERE v.rn = 1;

    DROP TEMPORARY TABLE IF EXISTS tmp_exp_act;
    CREATE TEMPORARY TABLE tmp_exp_act (PRIMARY KEY (id_expediente)) AS
    SELECT s.id_expediente,
           MAX(CASE WHEN s.rn = 1 THEN s.id_propuesta END) AS id_propuesta,
           MAX(CASE WHEN s.rn = 1 THEN s.rango END)        AS rango,
           COUNT(*)                                        AS propuestas_vigentes
    FROM (SELECT x.*, ROW_NUMBER() OVER (PARTITION BY x.id_expediente ORDER BY x.rango, x.id_propuesta DESC) AS rn
          FROM tmp_exp_prop x WHERE x.rango < 9) s
    GROUP BY s.id_expediente;

    -- ── 3. Datos de la propuesta activa, VB, seguimiento, OC y OS ───────────
    DROP TEMPORARY TABLE IF EXISTS tmp_exp_2;
    CREATE TEMPORARY TABLE tmp_exp_2 AS
    SELECT b.*,
        a.id_propuesta, IFNULL(a.rango, 0) AS rango_propuesta, GREATEST(IFNULL(a.propuestas_vigentes, 0) - 1, 0) AS propuestas_otras,
        p.numero AS numero_propuesta, p.version AS version_propuesta, p.estado AS estado_propuesta, p.tipo_servicio,
        COALESCE(p.id_responsable, p.id_creador) AS id_responsable_propuesta, p.id_moneda, p.total AS total_propuesta,
        p.fecha_envio, p.modificado_en AS propuesta_modificada,
        (SELECT MIN(p2.fecha_creacion) FROM propuesta_comercial p2
         WHERE p2.eliminado_en IS NULL AND p2.id_requerimiento = b.id_requerimiento)                       AS fecha_primera_propuesta,
        ((SELECT COUNT(*) FROM propuesta_item i WHERE i.id_propuesta = a.id_propuesta AND i.eliminado_en IS NULL)
         + (SELECT COUNT(*) FROM propuesta_equipo pe WHERE pe.id_propuesta = a.id_propuesta))           AS items_propuesta,
        -- VB de la propuesta activa (todas sus versiones)
        (SELECT MIN(v.fecha_solicitud) FROM visto_bueno v JOIN propuesta_comercial pv ON pv.id_propuesta = v.id_propuesta
         WHERE pv.numero = p.numero AND v.tipo = 'aprobacion' AND v.eliminado_en IS NULL)                AS fecha_primera_vb,
        (SELECT MAX(v.fecha_respuesta) FROM visto_bueno v
         WHERE v.id_propuesta = a.id_propuesta AND v.tipo = 'aprobacion' AND v.estado = 'aprobado' AND v.eliminado_en IS NULL)
                                                                                                         AS fecha_aprobacion_vb,
        (SELECT IFNULL(v.resuelto_por, v.id_aprobador) FROM visto_bueno v
         WHERE v.id_propuesta = a.id_propuesta AND v.tipo = 'aprobacion' AND v.eliminado_en IS NULL
           AND v.estado IN ('pendiente', 'aprobado')
         ORDER BY v.id_vb DESC LIMIT 1)                                                                  AS id_aprobador_vb,
        -- Seguimiento comercial
        (SELECT s.estado FROM seguimiento_comercial s
         WHERE s.id_propuesta = a.id_propuesta AND s.eliminado_en IS NULL
         ORDER BY s.id_seguimiento DESC LIMIT 1)                                                         AS estado_seguimiento,
        (SELECT MIN(IFNULL(s.fecha_interaccion, s.creado_en)) FROM seguimiento_comercial s
         WHERE s.id_propuesta = a.id_propuesta AND s.eliminado_en IS NULL AND s.estado = 'cerrado_aceptacion') AS fecha_aceptacion,
        (SELECT MIN(IFNULL(s.fecha_interaccion, s.creado_en)) FROM seguimiento_comercial s
         WHERE s.id_propuesta = a.id_propuesta AND s.eliminado_en IS NULL AND s.estado = 'cerrado_rechazo')    AS fecha_rechazo_cliente,
        -- OC de las propuestas del RQ (vigentes: no anuladas ni reemplazadas)
        (SELECT COUNT(DISTINCT oc.id_oc) FROM orden_compra oc
         JOIN oc_propuesta op ON op.id_oc = oc.id_oc AND op.eliminado_en IS NULL
         JOIN propuesta_comercial po ON po.id_propuesta = op.id_propuesta AND po.id_requerimiento = b.id_requerimiento
         WHERE oc.eliminado_en IS NULL AND oc.estado <> 'anulada' AND oc.reemplazada_por IS NULL)        AS cantidad_oc,
        (SELECT MIN(IF(oc.es_autogenerada = 1, oc.fecha_registro, op.fecha_decision)) FROM orden_compra oc
         JOIN oc_propuesta op ON op.id_oc = oc.id_oc AND op.eliminado_en IS NULL
         JOIN propuesta_comercial po ON po.id_propuesta = op.id_propuesta AND po.id_requerimiento = b.id_requerimiento
         WHERE oc.eliminado_en IS NULL AND oc.estado <> 'anulada'
           AND (op.estado_validacion = 'validada' OR (oc.es_autogenerada = 1 AND oc.reemplazada_por IS NULL))) AS fecha_liberacion_oc,
        EXISTS (SELECT 1 FROM orden_compra oc
                JOIN oc_propuesta op ON op.id_oc = oc.id_oc AND op.eliminado_en IS NULL
                JOIN propuesta_comercial po ON po.id_propuesta = op.id_propuesta AND po.id_requerimiento = b.id_requerimiento
                WHERE oc.eliminado_en IS NULL AND oc.estado <> 'anulada' AND oc.reemplazada_por IS NULL
                  AND op.estado_validacion = 'pendiente' AND oc.es_autogenerada = 0)                     AS oc_pendiente_decision,
        EXISTS (SELECT 1 FROM orden_compra oc
                JOIN oc_propuesta op ON op.id_oc = oc.id_oc AND op.eliminado_en IS NULL
                JOIN propuesta_comercial po ON po.id_propuesta = op.id_propuesta AND po.id_requerimiento = b.id_requerimiento
                WHERE oc.eliminado_en IS NULL AND oc.estado <> 'anulada'
                  AND (op.estado_validacion = 'validada' OR (oc.es_autogenerada = 1 AND oc.reemplazada_por IS NULL)))
                                                                                                         AS oc_valida,
        (SELECT COALESCE(oc.id_responsable, po.id_responsable, po.id_creador) FROM orden_compra oc
         JOIN oc_propuesta op ON op.id_oc = oc.id_oc AND op.eliminado_en IS NULL
         JOIN propuesta_comercial po ON po.id_propuesta = op.id_propuesta AND po.id_requerimiento = b.id_requerimiento
         WHERE oc.eliminado_en IS NULL AND oc.estado <> 'anulada' AND oc.reemplazada_por IS NULL
         ORDER BY oc.id_oc LIMIT 1)                                                                      AS id_responsable_oc,
        -- OS / OM del expediente
        (SELECT COUNT(*) FROM orden_servicio os
         WHERE os.id_expediente = b.id_expediente AND os.eliminado_en IS NULL AND os.estado <> 'anulada')  AS cantidad_os,
        COALESCE(
            (SELECT os.numero FROM orden_servicio os
             WHERE os.id_expediente = b.id_expediente AND os.eliminado_en IS NULL AND os.estado <> 'anulada'
             ORDER BY os.id_os LIMIT 1),
            (SELECT om.numero FROM orden_metrologia om
             WHERE om.id_expediente = b.id_expediente AND om.eliminado_en IS NULL AND om.estado <> 'anulada'
             ORDER BY om.id_om LIMIT 1))                                                                 AS numero_os_om,
        (SELECT GROUP_CONCAT(os.numero ORDER BY os.id_os SEPARATOR ', ') FROM orden_servicio os
         WHERE os.id_expediente = b.id_expediente AND os.eliminado_en IS NULL AND os.estado <> 'anulada')  AS numeros_os,
        (SELECT GROUP_CONCAT(om.numero ORDER BY om.id_om SEPARATOR ', ') FROM orden_metrologia om
         WHERE om.id_expediente = b.id_expediente AND om.eliminado_en IS NULL AND om.estado <> 'anulada')  AS numeros_om,
        (SELECT MIN(os.fecha_creacion) FROM orden_servicio os
         WHERE os.id_expediente = b.id_expediente AND os.eliminado_en IS NULL AND os.estado <> 'anulada')  AS fecha_primera_os,
        (SELECT os.id_tecnico_principal FROM orden_servicio os
         WHERE os.id_expediente = b.id_expediente AND os.eliminado_en IS NULL AND os.estado <> 'anulada'
         ORDER BY os.id_os LIMIT 1)                                                                      AS id_tecnico_principal,
        (SELECT os.id_responsable_comercial FROM orden_servicio os
         WHERE os.id_expediente = b.id_expediente AND os.eliminado_en IS NULL AND os.estado <> 'anulada'
         ORDER BY os.id_os LIMIT 1)                                                                      AS id_responsable_os,
        (SELECT MIN(os.fecha_confirmacion_cliente) FROM orden_servicio os
         WHERE os.id_expediente = b.id_expediente AND os.eliminado_en IS NULL AND os.estado <> 'anulada'
           AND os.confirmacion_cliente = 1)                                                              AS fecha_confirmacion,
        EXISTS (SELECT 1 FROM orden_servicio os
                WHERE os.id_expediente = b.id_expediente AND os.eliminado_en IS NULL
                  AND os.estado NOT IN ('anulada', 'finalizada') AND os.confirmacion_cliente = 1)        AS os_confirmada,
        EXISTS (SELECT 1 FROM orden_servicio os
                WHERE os.id_expediente = b.id_expediente AND os.eliminado_en IS NULL
                  AND os.estado IN ('en_ruta', 'en_ejecucion', 'pausada'))                               AS os_en_ejecucion,
        NOT EXISTS (SELECT 1 FROM orden_servicio os
                    WHERE os.id_expediente = b.id_expediente AND os.eliminado_en IS NULL
                      AND os.estado NOT IN ('anulada', 'finalizada'))                                    AS os_sin_pendientes,
        COALESCE(
            (SELECT MIN(ec.timestamp_utc) FROM evento_campo ec
             JOIN orden_servicio os ON os.id_os = ec.id_os AND os.eliminado_en IS NULL AND os.estado <> 'anulada'
             WHERE os.id_expediente = b.id_expediente AND ec.eliminado_en IS NULL),
            (SELECT MIN(TIMESTAMP(os.fecha_ejecucion, IFNULL(os.hora_llegada_real, os.hora_inicio))) FROM orden_servicio os
             WHERE os.id_expediente = b.id_expediente AND os.eliminado_en IS NULL
               AND os.estado IN ('en_ruta', 'en_ejecucion', 'pausada', 'finalizada')))                   AS fecha_inicio_ejecucion,
        (SELECT MAX(IF(os.hora_fin_real IS NULL, os.modificado_en, TIMESTAMP(os.fecha_ejecucion, os.hora_fin_real)))
         FROM orden_servicio os
         WHERE os.id_expediente = b.id_expediente AND os.eliminado_en IS NULL AND os.estado = 'finalizada') AS fecha_fin_ejecucion,
        (SELECT MIN(op.creado_en) FROM os_personal op
         JOIN orden_servicio os ON os.id_os = op.id_os AND os.eliminado_en IS NULL AND os.estado NOT IN ('anulada', 'finalizada')
         WHERE os.id_expediente = b.id_expediente AND op.eliminado_en IS NULL)                           AS fecha_primer_personal,
        -- SSOMA: personal de las OS abiertas y cuántos no están habilitados
        (SELECT COUNT(*) FROM os_personal op
         JOIN orden_servicio os ON os.id_os = op.id_os AND os.eliminado_en IS NULL AND os.estado NOT IN ('anulada', 'finalizada')
         WHERE os.id_expediente = b.id_expediente AND op.eliminado_en IS NULL)                           AS personal_os,
        (SELECT COUNT(*) FROM os_personal op
         JOIN orden_servicio os ON os.id_os = op.id_os AND os.eliminado_en IS NULL AND os.estado NOT IN ('anulada', 'finalizada')
         WHERE os.id_expediente = b.id_expediente AND op.eliminado_en IS NULL AND op.estado_ssoma <> 'habilitado') AS personal_no_habilitado,
        -- Cierre: informe técnico aprobado y conformidad del cliente en cada OS finalizada
        EXISTS (SELECT 1 FROM informe_tecnico it
                JOIN orden_servicio os ON os.id_os = it.id_os AND os.eliminado_en IS NULL AND os.estado <> 'anulada'
                WHERE os.id_expediente = b.id_expediente AND it.eliminado_en IS NULL AND it.estado = 'aprobado') AS informe_aprobado,
        (SELECT MAX(cd.registrado_en) FROM conformidad_digital cd
         JOIN informe_tecnico it ON it.id_informe = cd.id_informe AND it.eliminado_en IS NULL
         JOIN orden_servicio os ON os.id_os = it.id_os AND os.eliminado_en IS NULL AND os.estado <> 'anulada'
         WHERE os.id_expediente = b.id_expediente AND cd.eliminado_en IS NULL AND cd.estado = 'conforme') AS fecha_conformidad,
        NOT EXISTS (SELECT 1 FROM orden_servicio os
                    WHERE os.id_expediente = b.id_expediente AND os.eliminado_en IS NULL AND os.estado = 'finalizada'
                      AND NOT EXISTS (SELECT 1 FROM conformidad_digital cd
                                      JOIN informe_tecnico it ON it.id_informe = cd.id_informe AND it.eliminado_en IS NULL
                                      WHERE it.id_os = os.id_os AND cd.eliminado_en IS NULL AND cd.estado = 'conforme'))
                                                                                                         AS conformidad_completa
    FROM tmp_exp_1 b
    LEFT JOIN tmp_exp_act a ON a.id_expediente = b.id_expediente
    LEFT JOIN propuesta_comercial p ON p.id_propuesta = a.id_propuesta;

    DROP TEMPORARY TABLE IF EXISTS tmp_exp_1;
    DROP TEMPORARY TABLE IF EXISTS tmp_exp_act;
    DROP TEMPORARY TABLE IF EXISTS tmp_exp_prop;

    -- ── 4. Bloqueos y excepciones abiertos ──────────────────────────────────
    CALL SP_CargarBloqueosExpediente(p_id_expediente);

    -- Un VB rechazado o devuelto de otra propuesta del RQ deja de contar cuando la propuesta activa ya fue enviada o
    -- aceptada (esa otra quedó abandonada; su historial se conserva en la auditoría)
    UPDATE tmp_exp_blq b
    JOIN propuesta_comercial p ON p.id_propuesta = b.id_entidad
    JOIN tmp_exp_2 c ON c.id_expediente = b.id_expediente
    SET b.activo = 0, b.resolucion = IFNULL(b.resolucion, CONCAT('Sin efecto: el expediente continúa con la propuesta ', c.numero_propuesta, '.'))
    WHERE b.activo = 1 AND b.tipo IN ('vb_rechazado', 'vb_devuelto') AND b.entidad_tipo = 'propuesta'
      AND c.rango_propuesta IN (1, 2) AND p.numero <> c.numero_propuesta;

    DROP TEMPORARY TABLE IF EXISTS tmp_exp_blq_cnt;
    CREATE TEMPORARY TABLE tmp_exp_blq_cnt (PRIMARY KEY (id_expediente)) AS
    SELECT x.id_expediente,
           SUM(x.clase = 'bloqueo')   AS bloqueos,
           SUM(x.clase = 'excepcion') AS excepciones,
           SUBSTRING_INDEX(GROUP_CONCAT(IF(x.clase = 'bloqueo', CONCAT(x.tipo_nombre, ': ', x.entidad), NULL)
                                        ORDER BY x.critico DESC, x.fecha SEPARATOR '||'), '||', 1) AS motivo_bloqueo
    FROM tmp_exp_blq x
    WHERE x.activo = 1
    GROUP BY x.id_expediente;

    -- ── 5. Etapa ────────────────────────────────────────────────────────────
    DROP TEMPORARY TABLE IF EXISTS tmp_exp_3;
    CREATE TEMPORARY TABLE tmp_exp_3 AS
    SELECT c.*,
        IFNULL(k.bloqueos, 0) AS bloqueos, IFNULL(k.excepciones, 0) AS excepciones, k.motivo_bloqueo,
        CASE
            WHEN c.estado_rq IN ('anulado', 'cerrado')                                     THEN 'cerrado'
            WHEN c.id_propuesta IS NULL                                                    THEN 'requerimiento'
            WHEN c.rango_propuesta = 6                                                     THEN 'cerrado'
            WHEN c.cantidad_os > 0 AND c.os_sin_pendientes = 1 AND c.conformidad_completa = 1 THEN 'cerrado'
            WHEN c.cantidad_os > 0 AND c.os_sin_pendientes = 1                             THEN 'cierre'
            WHEN c.cantidad_os > 0 AND c.os_en_ejecucion = 1                               THEN 'ejecucion'
            WHEN c.cantidad_os > 0 AND c.os_confirmada = 1 AND c.personal_os > 0           THEN 'ssoma'
            WHEN c.cantidad_os > 0 AND c.os_confirmada = 1                                 THEN 'programacion'
            WHEN c.oc_valida = 1 OR c.cantidad_os > 0                                      THEN 'orden_servicio'
            WHEN c.estado_propuesta = 'aceptado'                                           THEN 'orden_compra'
            WHEN c.estado_propuesta IN ('aprobado', 'enviado')                             THEN 'seguimiento'
            WHEN c.estado_propuesta IN ('pendiente_vb', 'pendiente_revocacion')            THEN 'visto_bueno'
            ELSE 'propuesta'
        END AS etapa
    FROM tmp_exp_2 c
    LEFT JOIN tmp_exp_blq_cnt k ON k.id_expediente = c.id_expediente;

    DROP TEMPORARY TABLE IF EXISTS tmp_exp_2;
    DROP TEMPORARY TABLE IF EXISTS tmp_exp_blq_cnt;

    -- ── 6. Inicio de la etapa, responsables, área y SLA ─────────────────────
    DROP TEMPORARY TABLE IF EXISTS tmp_exp_4;
    CREATE TEMPORARY TABLE tmp_exp_4 AS
    SELECT d.*,
        et.Num1                                   AS orden_etapa,
        et.String1                                AS etapa_nombre,
        et.String3                                AS area,
        (IFNULL(et.Num3, 0) = 1)                  AS etapa_comercial,
        CASE d.etapa
            WHEN 'requerimiento'  THEN d.fecha_rq
            WHEN 'propuesta'      THEN COALESCE(d.fecha_primera_propuesta, d.fecha_rq)
            WHEN 'visto_bueno'    THEN COALESCE(d.fecha_primera_vb, d.propuesta_modificada)
            WHEN 'seguimiento'    THEN COALESCE(d.fecha_aprobacion_vb, d.fecha_envio, d.propuesta_modificada)
            WHEN 'orden_compra'   THEN COALESCE(d.fecha_aceptacion, d.propuesta_modificada)
            WHEN 'orden_servicio' THEN COALESCE(d.fecha_liberacion_oc, d.fecha_primera_os)
            WHEN 'programacion'   THEN COALESCE(d.fecha_confirmacion, d.fecha_primera_os)
            WHEN 'ssoma'          THEN COALESCE(d.fecha_primer_personal, d.fecha_confirmacion, d.fecha_primera_os)
            WHEN 'ejecucion'      THEN COALESCE(d.fecha_inicio_ejecucion, d.fecha_primera_os)
            WHEN 'cierre'         THEN COALESCE(d.fecha_fin_ejecucion, d.fecha_primera_os)
            ELSE NULL
        END                                       AS inicio_etapa_base,
        CASE
            WHEN d.estado_rq IN ('anulado', 'cerrado') THEN COALESCE(d.fecha_cierre_rq, d.rq_modificado)
            WHEN d.rango_propuesta = 6                 THEN COALESCE(d.fecha_rechazo_cliente, d.propuesta_modificada)
            WHEN d.etapa = 'cerrado'                   THEN d.fecha_conformidad
            ELSE NULL
        END                                       AS fecha_cierre,
        -- Responsable principal (comercial) y responsable de la etapa
        COALESCE(d.id_responsable_propuesta, d.id_responsable_rq) AS id_responsable,
        CASE d.etapa
            WHEN 'requerimiento'  THEN d.id_responsable_rq
            WHEN 'propuesta'      THEN d.id_responsable_propuesta
            WHEN 'visto_bueno'    THEN IFNULL(d.id_aprobador_vb, d.id_responsable_propuesta)
            WHEN 'seguimiento'    THEN d.id_responsable_propuesta
            WHEN 'orden_compra'   THEN IFNULL(d.id_responsable_oc, d.id_responsable_propuesta)
            WHEN 'orden_servicio' THEN COALESCE(d.id_responsable_os, d.id_responsable_oc, d.id_responsable_propuesta)
            WHEN 'programacion'   THEN d.id_responsable_actual
            WHEN 'ssoma'          THEN d.id_responsable_actual
            WHEN 'ejecucion'      THEN IFNULL(d.id_tecnico_principal, d.id_responsable_actual)
            WHEN 'cierre'         THEN COALESCE(d.id_responsable_os, d.id_responsable_propuesta)
            ELSE NULL
        END                                       AS id_responsable_etapa,
        (SELECT CAST(MAX(s.Num2) AS SIGNED) FROM tabla_maestra s
         WHERE s.IdMaestro = 49 AND s.IdEmpresa = 1 AND s.String1 = 'expediente' AND s.String2 = d.etapa AND s.eliminado_en IS NULL) AS sla_horas,
        (SELECT CAST(MAX(s.Num3) AS SIGNED) FROM tabla_maestra s
         WHERE s.IdMaestro = 49 AND s.IdEmpresa = 1 AND s.String1 = 'expediente' AND s.String2 = d.etapa AND s.eliminado_en IS NULL) AS sla_alerta_horas
    FROM tmp_exp_3 d
    LEFT JOIN tabla_maestra et ON et.IdMaestro = 97 AND et.IdEmpresa = 1 AND et.String2 = d.etapa AND et.eliminado_en IS NULL;

    DROP TEMPORARY TABLE IF EXISTS tmp_exp_3;

    -- ── 7. SLA, estado global, listo para avanzar y progreso ────────────────
    DROP TEMPORARY TABLE IF EXISTS tmp_exp_5;
    CREATE TEMPORARY TABLE tmp_exp_5 AS
    SELECT f.*,
        -- El reinicio del SLA por reasignación solo vale para la etapa en la que se hizo
        IF(f.sla_reinicio IS NOT NULL AND f.sla_reinicio_etapa = f.etapa AND f.sla_reinicio > IFNULL(f.inicio_etapa_base, f.sla_reinicio - INTERVAL 1 SECOND),
           f.sla_reinicio, f.inicio_etapa_base)                                                       AS inicio_etapa
    FROM tmp_exp_4 f;

    DROP TEMPORARY TABLE IF EXISTS tmp_exp_4;

    DROP TEMPORARY TABLE IF EXISTS tmp_exp;
    CREATE TEMPORARY TABLE tmp_exp AS
    SELECT g.*,
        IF(g.etapa = 'cerrado' OR g.sla_horas IS NULL OR g.inicio_etapa IS NULL, NULL,
           g.inicio_etapa + INTERVAL g.sla_horas HOUR)                                                 AS fecha_limite
    FROM tmp_exp_5 g;

    DROP TEMPORARY TABLE IF EXISTS tmp_exp_5;

    ALTER TABLE tmp_exp
        ADD COLUMN sla_vencido TINYINT NULL,
        ADD COLUMN sla_estado VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        ADD COLUMN sla_minutos_restantes INT NULL,
        ADD COLUMN listo TINYINT NULL,
        ADD COLUMN estado VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        ADD COLUMN progreso INT NULL,
        ADD COLUMN dias_transcurridos INT NULL,
        ADD PRIMARY KEY (id_expediente);

    UPDATE tmp_exp SET
        sla_vencido           = (fecha_limite IS NOT NULL AND NOW() > fecha_limite),
        sla_estado            = CASE WHEN fecha_limite IS NULL THEN NULL
                                     WHEN NOW() > fecha_limite THEN 'vencido'
                                     WHEN sla_alerta_horas IS NOT NULL AND NOW() >= fecha_limite - INTERVAL sla_alerta_horas HOUR THEN 'en_riesgo'
                                     ELSE 'en_plazo' END,
        sla_minutos_restantes = IF(fecha_limite IS NULL, NULL, TIMESTAMPDIFF(MINUTE, NOW(), fecha_limite)),
        estado                = CASE WHEN etapa = 'cerrado' THEN 'cerrado'
                                     WHEN bloqueos > 0      THEN 'bloqueado'
                                     WHEN excepciones > 0   THEN 'con_excepcion'
                                     ELSE 'activo' END,
        progreso              = IF(etapa = 'cerrado', 100, ROUND((IFNULL(orden_etapa, 1) - 1) * 10)),
        dias_transcurridos    = GREATEST(DATEDIFF(IFNULL(fecha_cierre, NOW()), fecha_creacion), 0);

    UPDATE tmp_exp SET
        listo = (estado = 'activo' AND IFNULL(sla_vencido, 0) = 0 AND CASE etapa
                    WHEN 'propuesta'    THEN estado_propuesta = 'borrador' AND items_propuesta > 0
                    WHEN 'seguimiento'  THEN estado_propuesta = 'aprobado'
                    WHEN 'orden_compra' THEN oc_pendiente_decision = 1
                    WHEN 'ssoma'        THEN personal_os > 0 AND personal_no_habilitado = 0
                    WHEN 'cierre'       THEN informe_aprobado = 1
                    ELSE 0 END);
END$$

DELIMITER ;
