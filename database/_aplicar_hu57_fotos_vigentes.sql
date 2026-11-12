-- HU-57: el detalle y el contador de fotos del informe excluyen las lecturas del QR y los intentos descartados. Ejecutar completo y reiniciar la API.

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

-- HU-57 (Sprint 5) Revisión Técnica: modal "Detalle del Servicio Técnico" y pantalla de edición (HU-58).
-- Acceso: rt_bandeja (y el informe debe estar en el alcance del usuario, ver SP_ArmarBaseInformes).
-- Resultados:
--   1 mensaje
--   2 cabecera: Resumen (tarjetas, información general, validaciones, diagnóstico, trazabilidad), resultado global de los
--     ensayos, descripción complementaria, precotización (cabecera) y acciones permitidas
--   3 procedimiento ejecutado · 4 ensayos · 5 observaciones · 6 recomendaciones · 7 fotos · 8 ítems de la precotización
--   9 historial reciente (5 últimos eventos; el completo está en SP_ObtenerHistorialInforme)
DROP PROCEDURE IF EXISTS SP_ObtenerDetalleInformeTecnico;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerDetalleInformeTecnico(
    IN p_id_usuario BIGINT,
    IN p_id_informe BIGINT
)
proc: BEGIN
    DECLARE v_editar  TINYINT DEFAULT 0;
    DECLARE v_revisar TINYINT DEFAULT 0;
    DECLARE v_existe  INT DEFAULT 0;

    IF FN_PermisoAccion(p_id_usuario, 'rt_bandeja') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver la revisión de informes técnicos.' AS Mensaje;
        LEAVE proc;
    END IF;
    SET v_editar  = FN_PermisoAccion(p_id_usuario, 'rt_editar');
    SET v_revisar = FN_PermisoAccion(p_id_usuario, 'rt_revisar');

    CALL SP_ArmarBaseInformes(p_id_usuario, IFNULL(p_id_informe, 0));
    SELECT COUNT(*) INTO v_existe FROM tmp_rt_base;
    IF v_existe = 0 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;
        SELECT 1 AS IdTipoMensaje, 'El informe no existe o no está en tu alcance.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Cabecera
    SELECT b.id_informe, b.numero_informe, b.version, b.estado, b.grupo_estado,
           CASE b.grupo_estado
               WHEN 'pendiente_revision'      THEN IF(b.estado = 'en_revision', 'En revisión', 'Pendiente de revisión')
               WHEN 'pendiente_precotizacion' THEN 'Pendiente de precotización'
               WHEN 'revisado_sin_precot'     THEN 'Revisado'
               ELSE 'Revisado con precotización' END                  AS estado_label,
           b.url_pdf,
           b.id_os, b.numero_os, b.tipo_os,
           b.id_cliente, b.razon_social, b.ruc, b.id_sede, b.sede,
           b.id_equipo, b.equipo, b.codigo_tw, b.numero_serie, b.marca, b.modelo, b.tipo_equipo,
           b.id_tipo_servicio, b.tipo_servicio,
           b.id_tecnico, b.tecnico,
           b.fecha_ejecucion, b.hora_inicio, b.hora_fin, b.duracion_min,
           b.id_propuesta, b.numero_propuesta, b.version_propuesta,
           b.id_requerimiento, b.numero_rq, b.contacto,
           b.diagnostico,
           -- Validaciones
           b.n_fotos, b.n_fotos_validas, b.n_ensayos, b.n_ensayos_sin_resultado, b.n_ensayos_no_conformes,
           b.n_observaciones, b.n_recomendaciones, b.n_pasos, b.n_pasos_realizados,
           IF(b.n_pasos = 0, NULL, ROUND(100 * b.n_pasos_realizados / b.n_pasos, 0)) AS porcentaje_procedimiento,
           CASE WHEN b.n_ensayos = 0 THEN 'sin_registro'
                WHEN b.n_ensayos_sin_resultado > 0 THEN 'incompletos'
                ELSE 'completos' END                                   AS estado_ensayos,
           CASE WHEN b.n_observaciones = 0 THEN 'no_aplica'
                WHEN b.id_propuesta_derivada IS NOT NULL THEN 'convertida'
                WHEN IFNULL(b.n_items_precot, 0) > 0 THEN 'precotizacion_enviada'
                ELSE 'requiere_precotizacion' END                      AS oportunidad_comercial,
           -- Resultado global de los ensayos
           it.normativa, it.patron_ensayo, it.tolerancia_excentricidad, it.resultado_global,
           it.error_maximo, it.error_maximo_detalle, it.incertidumbre, it.factor_k, it.decision_tecnica,
           it.descripcion_complementaria,
           -- Trazabilidad
           b.fecha_envio_revision, b.fecha_inicio_revision, b.fecha_revision, b.id_revisor, b.revisor, b.nota_revision,
           b.horas_espera, b.sla_horas, b.sla_vencido,
           b.id_precotizacion, b.numero_precot, b.estado_precot, b.fecha_precot, b.autor_precot, b.n_items_precot,
           pc.nota_supervisor                                          AS nota_precotizacion,
           b.id_propuesta_derivada, b.numero_propuesta_derivada, b.version_propuesta_derivada, b.estado_propuesta_derivada,
           -- Acciones
           (v_editar = 1 AND b.estado NOT IN ('revisado', 'aprobado'))                                  AS puede_editar,
           (v_editar = 1 AND b.estado NOT IN ('revisado', 'aprobado') AND b.n_observaciones > 0)         AS puede_registrar_precotizacion,
           (v_revisar = 1 AND b.estado NOT IN ('revisado', 'aprobado')
            AND NOT (b.n_observaciones > 0 AND IFNULL(b.n_items_precot, 0) = 0))                         AS puede_registrar_revision,
           CASE WHEN b.estado IN ('revisado', 'aprobado') THEN NULL
                WHEN b.n_observaciones > 0 AND IFNULL(b.n_items_precot, 0) = 0
                    THEN 'Este servicio tiene observaciones registradas. Debes registrar la precotización antes de marcar el informe como revisado.'
                ELSE NULL END                                          AS mensaje_bloqueo,
           CASE WHEN b.estado IN ('revisado', 'aprobado') THEN NULL
                WHEN b.n_observaciones > 0 AND IFNULL(b.n_items_precot, 0) = 0 THEN 'registrar_precotizacion'
                ELSE 'registrar_revision' END                          AS accion_principal
    FROM tmp_rt_base b
    JOIN informe_tecnico it    ON it.id_informe = b.id_informe
    LEFT JOIN precotizacion pc ON pc.id_precotizacion = b.id_precotizacion;

    -- 3. Procedimiento ejecutado
    SELECT ip.id_paso, ip.orden, ip.titulo, ip.detalle, ip.realizado, ip.nota, ip.origen
    FROM informe_procedimiento ip
    WHERE ip.id_informe = p_id_informe AND ip.eliminado_en IS NULL
    ORDER BY ip.orden, ip.id_paso;

    -- 4. Ensayos
    SELECT en.id_ensayo, en.tipo, en.orden, en.punto, en.nota_punto, en.carga, en.lectura, en.error, en.tolerancia,
           en.resultado,
           CASE en.resultado WHEN 'conforme'    THEN IF(en.tipo = 'pesaje', 'Dentro', 'Conforme')
                             WHEN 'no_conforme' THEN IF(en.tipo = 'pesaje', 'Fuera', 'No conforme') END AS resultado_label,
           en.origen
    FROM informe_ensayo en
    WHERE en.id_informe = p_id_informe AND en.eliminado_en IS NULL
    ORDER BY (en.tipo = 'excentricidad'), en.orden, en.id_ensayo;

    -- 5. Observaciones
    SELECT o.id_observacion, o.codigo, o.orden, o.titulo, o.descripcion, o.ubicacion, o.detalle_extra,
           o.nivel_afectacion, o.id_evidencia, f.url_archivo AS url_foto, o.origen
    FROM informe_observacion o
    LEFT JOIN evidencia_fotografica f ON f.id_evidencia = o.id_evidencia AND f.eliminado_en IS NULL
    WHERE o.id_informe = p_id_informe AND o.eliminado_en IS NULL
    ORDER BY o.orden, o.id_observacion;

    -- 6. Recomendaciones
    SELECT r.id_recomendacion, r.codigo, r.orden, r.titulo, r.descripcion, r.prioridad, r.plazo,
           r.id_observacion, o.codigo AS codigo_observacion, r.origen
    FROM informe_recomendacion r
    LEFT JOIN informe_observacion o ON o.id_observacion = r.id_observacion AND o.eliminado_en IS NULL
    WHERE r.id_informe = p_id_informe AND r.eliminado_en IS NULL
    ORDER BY r.orden, r.id_recomendacion;

    -- 7. Fotos (subidas desde la app; solo lectura)
    SELECT f.id_evidencia, f.url_archivo, f.descripcion,
           tf.String2                                         AS momento,
           tf.String1                                         AS momento_label,
           f.timestamp_captura                                AS fecha_captura,
           f.latitud, f.longitud, (f.latitud IS NOT NULL AND f.longitud IS NOT NULL) AS georreferenciada,
           f.validacion_ia,
           f.es_video,
           COALESCE(f.id_observacion, o.id_observacion)       AS id_observacion,
           COALESCE(ov.codigo, o.codigo)                      AS codigo_observacion
    FROM evidencia_fotografica f
    JOIN tmp_rt_base b ON b.id_informe = p_id_informe
    LEFT JOIN tabla_maestra tf ON tf.IdMaestro = 30 AND tf.IdEmpresa = 1 AND tf.Num1 = f.id_tipo_evidencia
    LEFT JOIN informe_observacion ov ON ov.id_observacion = f.id_observacion AND ov.eliminado_en IS NULL
    LEFT JOIN informe_observacion o  ON o.id_evidencia = f.id_evidencia AND o.id_informe = p_id_informe AND o.eliminado_en IS NULL
    WHERE f.eliminado_en IS NULL AND f.id_tipo_evidencia NOT IN (6, 7)
      AND f.url_archivo NOT LIKE 'qr://%' AND IFNULL(f.vigente, 1) = 1   -- sin las lecturas del QR (no tienen archivo) ni los intentos descartados por retoma
      AND (f.id_informe = p_id_informe
           OR (f.id_informe IS NULL AND f.id_os = b.id_os AND (f.id_equipo = b.id_equipo OR f.id_equipo IS NULL)))
    ORDER BY f.timestamp_captura, f.id_evidencia;

    -- 8. Ítems de la precotización
    SELECT pi.id_item, pi.orden, pi.concepto, pi.codigo, pi.id_suministro, pi.descripcion_tecnica, pi.cantidad, pi.unidad,
           pi.prioridad, pi.id_observacion, o.codigo AS codigo_observacion
    FROM precotizacion_item pi
    JOIN tmp_rt_base b ON b.id_precotizacion = pi.id_precotizacion
    LEFT JOIN informe_observacion o ON o.id_observacion = pi.id_observacion AND o.eliminado_en IS NULL
    WHERE pi.eliminado_en IS NULL
    ORDER BY pi.orden, pi.id_item;

    -- 9. Historial reciente
    SELECT a.id_auditoria, a.accion, a.descripcion, a.registrado_en AS fecha,
           IF(a.id_usuario IS NULL, 'Sistema', TRIM(CONCAT(u.nombre, ' ', u.apellido))) AS usuario
    FROM auditoria_evento a
    LEFT JOIN usuario u ON u.id_usuario = a.id_usuario
    WHERE a.entidad_tipo = 'informe_tecnico' AND a.id_entidad = p_id_informe
    ORDER BY a.registrado_en DESC, a.id_auditoria DESC
    LIMIT 5;

    DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;
END$$

DELIMITER ;

-- ============================================================
-- SP_ObtenerArchivoFotoInforme  (Revisión Técnica HU-57 — ruta del archivo de una foto del informe, para mostrar la vista previa · lectura)
-- Acceso: rt_bandeja y el informe dentro del alcance del usuario (SP_ArmarBaseInformes). La evidencia debe ser del informe (id_informe) o, si no tiene informe asignado,
-- de la misma OS y equipo (la misma regla de SP_ObtenerDetalleInformeTecnico). Las del QR no tienen archivo.
-- Resultados: 1 mensaje; 2 (ruta, ruta_cuadro, es_video).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerArchivoFotoInforme;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerArchivoFotoInforme(
    IN p_id_usuario   BIGINT,
    IN p_id_informe   BIGINT,
    IN p_id_evidencia BIGINT
)
proc: BEGIN
    DECLARE v_ruta   VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_cuadro VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_video  TINYINT DEFAULT 0;

    IF FN_PermisoAccion(p_id_usuario, 'rt_bandeja') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver la revisión de informes técnicos.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_ArmarBaseInformes(p_id_usuario, IFNULL(p_id_informe, 0));

    SELECT f.url_archivo, f.ruta_cuadro, f.es_video INTO v_ruta, v_cuadro, v_video
    FROM   evidencia_fotografica f
    JOIN   tmp_rt_base b ON b.id_informe = p_id_informe
    WHERE  f.id_evidencia = p_id_evidencia AND f.eliminado_en IS NULL AND f.url_archivo NOT LIKE 'qr://%' AND IFNULL(f.vigente, 1) = 1
      AND  (f.id_informe = p_id_informe
            OR (f.id_informe IS NULL AND f.id_os = b.id_os AND (f.id_equipo = b.id_equipo OR f.id_equipo IS NULL)))
    LIMIT 1;

    DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;

    IF v_ruta IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Foto no encontrada.' AS Mensaje;
    ELSE
        SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;
        SELECT v_ruta AS ruta, v_cuadro AS ruta_cuadro, v_video AS es_video;
    END IF;
END$$

DELIMITER ;

