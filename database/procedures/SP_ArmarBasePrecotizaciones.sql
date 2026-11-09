-- HU-60 (Sprint 5) Precotizaciones Técnicas (CRM): cálculo compartido. Llena tmp_pct_base (el que llama la borra).
--   p_id_precotizacion NULL = todas (bandeja). Solo precotizaciones enviadas o convertidas (no borradores).
--   Alcance (pedido 14, SP_ObtenerAlcanceCrm) sobre el responsable del RQ de origen: el comercial ve las de sus RQ y suplencias,
--   supervisor / visor las de su área, gerencia / TI todas.
--   estado_grupo: pendiente (enviada, aún sin propuesta) · convertida (ya generó la propuesta)
DROP PROCEDURE IF EXISTS SP_ArmarBasePrecotizaciones;

DELIMITER $$

CREATE PROCEDURE SP_ArmarBasePrecotizaciones(
    IN p_id_usuario       BIGINT,
    IN p_id_precotizacion BIGINT
)
BEGIN
    DECLARE v_ver_todo    TINYINT DEFAULT 0;
    DECLARE v_solo_propio TINYINT DEFAULT 1;
    DECLARE v_ids         TEXT;
    DECLARE v_area        VARCHAR(40);

    CALL SP_ObtenerAlcanceCrm(p_id_usuario, v_ver_todo, v_solo_propio, v_ids, v_area);

    DROP TEMPORARY TABLE IF EXISTS tmp_pct_base;
    CREATE TEMPORARY TABLE tmp_pct_base (PRIMARY KEY (id_precotizacion)) AS
    SELECT pc.id_precotizacion, pc.numero, pc.estado,
           IF(pc.estado = 'convertido_propuesta', 'convertida', 'pendiente')  AS estado_grupo,
           IF(pc.estado = 'convertido_propuesta', 'Propuesta', 'Pendiente')   AS estado_label,
           COALESCE(pc.fecha_envio, pc.fecha_creacion)                          AS fecha,
           pc.nota_supervisor, pc.descripcion_servicio                          AS diagnostico,
           pc.id_requerimiento, rq.numero AS numero_rq, rq.fecha_creacion AS fecha_rq, rq.id_responsable AS id_responsable_rq,
           pc.id_cliente, c.razon_social, c.ruc,
           os.id_sede, sc.nombre AS sede,
           pc.id_equipo,
           COALESCE(NULLIF(TRIM(su.descripcion), ''), NULLIF(TRIM(CONCAT_WS(' ', ec.marca, ec.modelo)), ''), ec.codigo_tw) AS equipo,
           ec.marca, ec.modelo, ec.codigo_tw, ec.num_serie AS numero_serie,
           pc.id_creador AS id_supervisor, TRIM(CONCAT(us.nombre, ' ', us.apellido)) AS supervisor,
           IF(us.rol_sistema IN ('supervisor', 'administrador'),
              CONCAT('Supervisor ', IF(us.area = 'metrologia', 'de Metrología', 'Técnico')), 'Servicio Técnico') AS cargo_supervisor,
           pc.id_informe, it.version AS version_informe,
           pc.id_os, os.numero AS numero_os, os.fecha_ejecucion, os.id_tipo_servicio, ts.String1 AS tipo_servicio,
           (SELECT COUNT(*) FROM precotizacion_item pi WHERE pi.id_precotizacion = pc.id_precotizacion AND pi.eliminado_en IS NULL) AS items,
           (SELECT COUNT(*) FROM informe_observacion o WHERE o.id_informe = pc.id_informe AND o.eliminado_en IS NULL)                AS observaciones,
           pc.id_propuesta_generada, pd.numero AS numero_propuesta_generada, pd.version AS version_propuesta_generada,
           pd.estado AS estado_propuesta_generada, pd.total AS total_propuesta_generada, mo.String2 AS moneda_propuesta_generada,
           TRIM(CONCAT(uc.nombre, ' ', uc.apellido)) AS comercial_propuesta_generada,
           pc.fecha_conversion, pc.id_convertido_por, TRIM(CONCAT(ucv.nombre, ' ', ucv.apellido)) AS convertido_por,
           IF(pc.fecha_conversion IS NULL, NULL,
              ROUND(TIMESTAMPDIFF(MINUTE, COALESCE(pc.fecha_envio, pc.fecha_creacion), pc.fecha_conversion) / 60, 1)) AS horas_atencion,
           -- Propuesta de origen del servicio (trazabilidad)
           po.id_propuesta AS id_propuesta_origen, po.numero AS numero_propuesta_origen, po.version AS version_propuesta_origen
    FROM precotizacion pc
    LEFT JOIN requerimiento rq       ON rq.id_requerimiento = pc.id_requerimiento
    LEFT JOIN cliente c              ON c.id_cliente = pc.id_cliente
    LEFT JOIN orden_servicio os      ON os.id_os = pc.id_os
    LEFT JOIN expediente_digital e   ON e.id_expediente = os.id_expediente
    LEFT JOIN propuesta_comercial po ON po.id_propuesta = COALESCE(os.id_propuesta, e.id_propuesta)
    LEFT JOIN sede_cliente sc        ON sc.id_sede = os.id_sede
    LEFT JOIN tabla_maestra ts       ON ts.IdMaestro = 3 AND ts.IdEmpresa = 1 AND ts.Num1 = os.id_tipo_servicio
    LEFT JOIN informe_tecnico it     ON it.id_informe = pc.id_informe
    LEFT JOIN equipo_cliente ec      ON ec.id_equipo = pc.id_equipo
    LEFT JOIN suministros su         ON su.id_suministro = ec.id_suministro
    LEFT JOIN usuario us             ON us.id_usuario = pc.id_creador
    LEFT JOIN propuesta_comercial pd ON pd.id_propuesta = pc.id_propuesta_generada
    LEFT JOIN tabla_maestra mo       ON mo.IdMaestro = 1 AND mo.IdEmpresa = 1 AND mo.Num1 = pd.id_moneda
    LEFT JOIN usuario uc             ON uc.id_usuario = COALESCE(pd.id_responsable, pd.id_creador)
    LEFT JOIN usuario ucv            ON ucv.id_usuario = pc.id_convertido_por
    WHERE pc.eliminado_en IS NULL
      AND pc.estado IN ('enviado', 'aceptado', 'convertido_propuesta')
      AND (p_id_precotizacion IS NULL OR pc.id_precotizacion = p_id_precotizacion)
      AND (v_ver_todo = 1 OR FIND_IN_SET(rq.id_responsable, v_ids) > 0
           OR (rq.id_responsable IS NULL AND v_solo_propio = 0));
END$$

DELIMITER ;
