-- Revisión Técnica (Sprint 5, HU-56 a HU-59): cálculo compartido de los informes de servicio técnico.
-- Llena tmp_rt_base (una fila por informe; el que llama hace DROP TEMPORARY TABLE tmp_rt_base al terminar).
--   p_id_informe NULL = todos (bandeja). Solo informes ya enviados por el técnico (no borradores).
--   Alcance: gerencia / TI ven todo; el resto, los informes de los técnicos de su área ("informes de mis técnicos").
-- grupo_estado (bandeja y tarjetas):
--   pendiente_revision       enviado o en revisión, sin observaciones o con la precotización ya registrada
--   pendiente_precotizacion  enviado o en revisión, con observaciones y sin precotización (no se puede marcar revisado)
--   revisado_sin_precot      revisado sin precotización
--   revisado_con_precot      revisado con precotización (generó oportunidad comercial)
-- SLA: horas desde que llegó a la bandeja (fecha_envio_revision) contra RT_SLA_REVISION_HORAS (48 h por defecto).
DROP PROCEDURE IF EXISTS SP_ArmarBaseInformes;

DELIMITER $$

CREATE PROCEDURE SP_ArmarBaseInformes(
    IN p_id_usuario BIGINT,
    IN p_id_informe BIGINT
)
BEGIN
    DECLARE v_area     VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_ver_todo TINYINT DEFAULT 0;
    DECLARE v_sla      INT DEFAULT 48;

    SELECT area INTO v_area FROM usuario
    WHERE id_usuario = p_id_usuario AND eliminado_en IS NULL AND estado = 'activo' LIMIT 1;
    SET v_ver_todo = IF(IFNULL(v_area, '') IN ('gerencia', 'ti'), 1, 0);

    SELECT CAST(IFNULL(MAX(Num2), 48) AS SIGNED) INTO v_sla
    FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROGRAMACION' AND String2 = 'RT_SLA_REVISION_HORAS';

    DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;
    CREATE TEMPORARY TABLE tmp_rt_base (PRIMARY KEY (id_informe)) AS
    SELECT it.id_informe,
           it.numero                                                   AS numero_informe,
           it.version,
           it.estado,
           it.url_pdf,
           it.diagnostico_principal                                    AS diagnostico,
           it.id_os,
           os.numero                                                   AS numero_os,
           os.tipo                                                     AS tipo_os,
           it.id_equipo,
           COALESCE(NULLIF(TRIM(su.descripcion), ''), NULLIF(TRIM(CONCAT_WS(' ', ec.marca, ec.modelo)), ''), ec.codigo_tw) AS equipo,
           ec.codigo_tw                                                AS codigo_tw,
           ec.num_serie                                                AS numero_serie,
           ec.marca, ec.modelo,
           COALESCE(cl.String1, ec.clasificacion)                      AS tipo_equipo,
           os.id_cliente,
           c.razon_social,
           c.ruc,
           os.id_sede,
           sc.nombre                                                   AS sede,
           os.id_tipo_servicio,
           ts.String1                                                  AS tipo_servicio,
           it.id_tecnico,
           TRIM(CONCAT(ut.nombre, ' ', ut.apellido))                   AS tecnico,
           ut.area                                                     AS area_tecnico,
           COALESCE(os.fecha_ejecucion, DATE(it.fecha_creacion))       AS fecha_ejecucion,
           TIME_FORMAT(COALESCE(os.hora_llegada_real, os.hora_inicio), '%H:%i')  AS hora_inicio,
           TIME_FORMAT(COALESCE(os.hora_fin_real, os.hora_fin_estimada), '%H:%i') AS hora_fin,
           IF(COALESCE(os.hora_llegada_real, os.hora_inicio) IS NULL OR COALESCE(os.hora_fin_real, os.hora_fin_estimada) IS NULL, NULL,
              GREATEST(TIMESTAMPDIFF(MINUTE, COALESCE(os.hora_llegada_real, os.hora_inicio),
                                             COALESCE(os.hora_fin_real, os.hora_fin_estimada)), 0)) AS duracion_min,
           COALESCE(os.id_propuesta, e.id_propuesta)                   AS id_propuesta,
           pr.numero                                                   AS numero_propuesta,
           pr.version                                                  AS version_propuesta,
           rq.id_requerimiento,
           rq.numero                                                   AS numero_rq,
           rq.id_responsable                                           AS id_responsable_rq,
           COALESCE(NULLIF(TRIM(it.responsable_nombre), ''), co.nombres) AS contacto,
           it.fecha_envio_revision,
           it.fecha_inicio_revision,
           it.fecha_revision,
           it.nota_revision,
           it.id_revisor,
           TRIM(CONCAT(ur.nombre, ' ', ur.apellido))                   AS revisor,
           v_sla                                                       AS sla_horas,
           TIMESTAMPDIFF(HOUR, COALESCE(it.fecha_envio_revision, it.fecha_creacion),
                         IF(it.estado IN ('revisado', 'aprobado'), IFNULL(it.fecha_revision, NOW()), NOW())) AS horas_espera,
           (SELECT COUNT(*) FROM informe_observacion o WHERE o.id_informe = it.id_informe AND o.eliminado_en IS NULL)    AS n_observaciones,
           (SELECT COUNT(*) FROM informe_recomendacion r WHERE r.id_informe = it.id_informe AND r.eliminado_en IS NULL)  AS n_recomendaciones,
           (SELECT COUNT(*) FROM evidencia_fotografica f
            WHERE f.eliminado_en IS NULL AND f.id_tipo_evidencia NOT IN (6, 7) AND f.url_archivo NOT LIKE 'qr://%' AND IFNULL(f.vigente, 1) = 1
              AND (f.id_informe = it.id_informe
                   OR (f.id_informe IS NULL AND f.id_os = it.id_os AND (f.id_equipo = it.id_equipo OR f.id_equipo IS NULL)))) AS n_fotos,
           (SELECT COUNT(*) FROM evidencia_fotografica f
            WHERE f.eliminado_en IS NULL AND f.id_tipo_evidencia NOT IN (6, 7) AND f.url_archivo NOT LIKE 'qr://%' AND IFNULL(f.vigente, 1) = 1 AND f.validacion_ia <> 'rechazada'
              AND (f.id_informe = it.id_informe
                   OR (f.id_informe IS NULL AND f.id_os = it.id_os AND (f.id_equipo = it.id_equipo OR f.id_equipo IS NULL)))) AS n_fotos_validas,
           (SELECT COUNT(*) FROM informe_ensayo en WHERE en.id_informe = it.id_informe AND en.eliminado_en IS NULL)      AS n_ensayos,
           (SELECT COUNT(*) FROM informe_ensayo en WHERE en.id_informe = it.id_informe AND en.eliminado_en IS NULL
              AND en.resultado IS NULL)                                                                                  AS n_ensayos_sin_resultado,
           (SELECT COUNT(*) FROM informe_ensayo en WHERE en.id_informe = it.id_informe AND en.eliminado_en IS NULL
              AND en.resultado = 'no_conforme')                                                                          AS n_ensayos_no_conformes,
           (SELECT COUNT(*) FROM informe_procedimiento ip WHERE ip.id_informe = it.id_informe AND ip.eliminado_en IS NULL) AS n_pasos,
           (SELECT COUNT(*) FROM informe_procedimiento ip WHERE ip.id_informe = it.id_informe AND ip.eliminado_en IS NULL
              AND ip.realizado = 1)                                                                                       AS n_pasos_realizados,
           pc.id_precotizacion,
           pc.numero                                                   AS numero_precot,
           pc.estado                                                   AS estado_precot,
           pc.fecha_envio                                              AS fecha_precot,
           pc.id_creador                                               AS id_autor_precot,
           TRIM(CONCAT(up.nombre, ' ', up.apellido))                   AS autor_precot,
           (SELECT COUNT(*) FROM precotizacion_item pi WHERE pi.id_precotizacion = pc.id_precotizacion AND pi.eliminado_en IS NULL) AS n_items_precot,
           pd.id_propuesta                                             AS id_propuesta_derivada,
           pd.numero                                                   AS numero_propuesta_derivada,
           pd.version                                                  AS version_propuesta_derivada,
           pd.estado                                                   AS estado_propuesta_derivada
    FROM informe_tecnico it
    LEFT JOIN orden_servicio os      ON os.id_os = it.id_os
    LEFT JOIN expediente_digital e   ON e.id_expediente = os.id_expediente
    LEFT JOIN propuesta_comercial pr ON pr.id_propuesta = COALESCE(os.id_propuesta, e.id_propuesta)
    LEFT JOIN requerimiento rq       ON rq.id_requerimiento = COALESCE(os.id_requerimiento, pr.id_requerimiento, e.id_requerimiento)
    LEFT JOIN cliente c              ON c.id_cliente = os.id_cliente
    LEFT JOIN sede_cliente sc        ON sc.id_sede = os.id_sede
    LEFT JOIN contacto_cliente co    ON co.id_contacto = os.id_contacto
    LEFT JOIN equipo_cliente ec      ON ec.id_equipo = it.id_equipo
    LEFT JOIN suministros su         ON su.id_suministro = ec.id_suministro
    LEFT JOIN tabla_maestra cl       ON cl.IdMaestro = 71 AND cl.IdEmpresa = 1 AND cl.String2 = ec.clasificacion
    LEFT JOIN tabla_maestra ts       ON ts.IdMaestro = 3 AND ts.IdEmpresa = 1 AND ts.Num1 = os.id_tipo_servicio
    LEFT JOIN usuario ut             ON ut.id_usuario = it.id_tecnico
    LEFT JOIN usuario ur             ON ur.id_usuario = it.id_revisor
    LEFT JOIN precotizacion pc       ON pc.id_precotizacion = (SELECT MAX(p2.id_precotizacion) FROM precotizacion p2
                                                               WHERE p2.id_informe = it.id_informe AND p2.eliminado_en IS NULL)
    LEFT JOIN usuario up             ON up.id_usuario = pc.id_creador
    LEFT JOIN propuesta_comercial pd ON pd.id_propuesta = pc.id_propuesta_generada
    WHERE it.eliminado_en IS NULL
      AND it.estado <> 'borrador'
      AND (p_id_informe IS NULL OR it.id_informe = p_id_informe)
      -- solo la última versión del informe de cada OS + equipo
      AND NOT EXISTS (SELECT 1 FROM informe_tecnico i2
                      WHERE i2.eliminado_en IS NULL AND i2.id_os <=> it.id_os AND i2.id_equipo <=> it.id_equipo
                        AND i2.estado <> 'borrador' AND i2.id_os IS NOT NULL
                        AND (i2.version > it.version OR (i2.version = it.version AND i2.id_informe > it.id_informe)))
      AND (v_ver_todo = 1 OR (v_area IS NOT NULL AND ut.area = v_area));

    ALTER TABLE tmp_rt_base
        ADD COLUMN grupo_estado VARCHAR(30) NULL,
        ADD COLUMN sla_vencido  TINYINT     NOT NULL DEFAULT 0;

    UPDATE tmp_rt_base SET
        grupo_estado = CASE
            WHEN estado IN ('revisado', 'aprobado') AND id_precotizacion IS NOT NULL THEN 'revisado_con_precot'
            WHEN estado IN ('revisado', 'aprobado')                                  THEN 'revisado_sin_precot'
            WHEN n_observaciones > 0 AND IFNULL(n_items_precot, 0) = 0               THEN 'pendiente_precotizacion'
            ELSE 'pendiente_revision' END,
        sla_vencido = IF(estado NOT IN ('revisado', 'aprobado') AND horas_espera > sla_horas, 1, 0);
END$$

DELIMITER ;
