-- ============================================================
-- SP_ObtenerInformeComplementario  (Revisión Técnica — detalle del Informe Complementario, 23/11/2026 · lectura)
-- Lo usan la pantalla del complementario y su PDF. Acceso:
--   · rt_bandeja con el informe original en su alcance (SP_ArmarBaseInformes), o
--   · precot_ver si la precotización del complementario está en su alcance del CRM (Comercial abre el PDF desde el modal de la precotización).
-- Resultados:
--   1 mensaje
--   2 cabecera: el complementario (número, estado, observaciones generales, supervisor, precotización y acciones) y los datos del informe
--     original en solo lectura (OS, cliente, equipo, técnico, fechas, diagnóstico y resultado global de los ensayos)
--   3 procedimiento del original (solo lectura) · 4 ensayos del original (solo lectura)
--   5 observaciones · 6 recomendaciones · 7 fotos y videos (copiada = viene del original; si no, la subió el supervisor) · 8 ítems de la precotización
--   9 opciones de las listas (tipo de equipo, clasificación y componente de las fallas: las mismas de la cabecera del informe en la app)
-- Ampliado el 24/11/2026 (ficha de 5 pestañas): la cabecera trae además lo que el técnico cargó en la app —quién atendió en planta, detalle del
--   servicio (JSON detalle_servicio), comentario de las pruebas y diagnóstico final— y las observaciones su clasificación y componente.
--   fotos.origen: tecnico (copiada del informe del técnico) · supervisor (subida al complementario).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerInformeComplementario;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerInformeComplementario(
    IN p_id_usuario        BIGINT,
    IN p_id_complementario BIGINT
)
proc: BEGIN
    DECLARE v_padre    BIGINT DEFAULT NULL;
    DECLARE v_existe   INT DEFAULT 0;
    DECLARE v_editar   TINYINT DEFAULT 0;
    DECLARE v_prev_usr BIGINT;
    DECLARE v_prev_tod TINYINT;
    DECLARE v_prev_are VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_pc    BIGINT DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SET @tw_inf_usuario = v_prev_usr, @tw_inf_ver_todo = v_prev_tod, @tw_inf_area = v_prev_are;
        DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;
        DROP TEMPORARY TABLE IF EXISTS tmp_pct_base;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SELECT c.id_informe_padre INTO v_padre
    FROM informe_tecnico c
    WHERE c.id_informe = p_id_complementario AND c.id_informe_padre IS NOT NULL AND c.eliminado_en IS NULL;
    IF v_padre IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'El informe complementario no existe.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Supervisor / Jefe: el original en su alcance
    IF FN_PermisoAccion(p_id_usuario, 'rt_bandeja') = 1 THEN
        CALL SP_ArmarBaseInformes(p_id_usuario, v_padre);
        SELECT COUNT(*) INTO v_existe FROM tmp_rt_base;
        SET v_editar = FN_PermisoAccion(p_id_usuario, 'rt_editar');
    END IF;

    -- Comercial: la precotización del complementario en su alcance del CRM; los datos del original se leen sin el filtro de área
    IF v_existe = 0 AND FN_PermisoAccion(p_id_usuario, 'precot_ver') = 1 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;
        CALL SP_ArmarBasePrecotizaciones(p_id_usuario, NULL);
        SELECT COUNT(*) INTO v_existe FROM tmp_pct_base WHERE id_informe = p_id_complementario;
        DROP TEMPORARY TABLE IF EXISTS tmp_pct_base;
        IF v_existe > 0 THEN
            SET v_prev_usr = @tw_inf_usuario, v_prev_tod = @tw_inf_ver_todo, v_prev_are = @tw_inf_area;
            SET @tw_inf_usuario = p_id_usuario, @tw_inf_ver_todo = 1, @tw_inf_area = NULL;
            CALL SP_ArmarBaseInformes(p_id_usuario, v_padre);
            SET @tw_inf_usuario = v_prev_usr, @tw_inf_ver_todo = v_prev_tod, @tw_inf_area = v_prev_are;
            SELECT COUNT(*) INTO v_existe FROM tmp_rt_base;
        END IF;
        SET v_editar = 0;
    END IF;

    IF v_existe = 0 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;
        SELECT 1 AS IdTipoMensaje, 'El informe complementario no existe o no está en tu alcance.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT MAX(p.id_precotizacion) INTO v_id_pc FROM precotizacion p WHERE p.id_informe = p_id_complementario AND p.eliminado_en IS NULL;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Cabecera
    SELECT c.id_informe                                                  AS id_informe_complementario,
           c.numero                                                      AS numero_complementario,
           c.estado,
           IF(c.estado = 'borrador', 'Borrador (sin guardar)', 'Guardado') AS estado_label,
           c.descripcion_complementaria                                  AS observaciones_generales,
           c.id_tecnico                                                  AS id_supervisor,
           TRIM(CONCAT(us.nombre, ' ', us.apellido))                     AS supervisor,
           c.fecha_creacion, c.modificado_en AS fecha_actualizacion, c.fecha_revision AS fecha_cierre,
           -- Informe original (solo lectura)
           b.id_informe                                                  AS id_informe_original,
           b.numero_informe                                              AS numero_informe_original,
           b.estado                                                      AS estado_original,
           b.grupo_estado                                                AS grupo_estado_original,
           COALESCE(o.url_pdf, CONCAT('/api/servicio-tecnico/informes/', o.id_informe, '/pdf')) AS pdf_informe_original_url,
           CONCAT('/api/servicio-tecnico/informes/complementarios/', c.id_informe, '/pdf') AS pdf_informe_complementario_url,
           b.id_os, b.numero_os, b.tipo_os,
           b.id_cliente, b.razon_social, b.ruc, b.id_sede, b.sede,
           b.id_equipo, b.equipo, b.codigo_tw, b.numero_serie, b.marca, b.modelo, b.tipo_equipo,
           b.id_tipo_servicio, b.tipo_servicio,
           b.id_tecnico, b.tecnico,
           b.fecha_ejecucion, b.hora_inicio, b.hora_fin, b.duracion_min,
           b.id_propuesta, b.numero_propuesta, b.version_propuesta,
           b.id_requerimiento, b.numero_rq, b.contacto,
           b.diagnostico,
           o.normativa, o.patron_ensayo, o.tolerancia_excentricidad, o.resultado_global,
           o.error_maximo, o.error_maximo_detalle, o.incertidumbre, o.factor_k, o.decision_tecnica,
           -- Lo que cargó el técnico en la cabecera del informe de la app (solo lectura)
           o.numero_informe                                              AS numero_informe_tecnico,
           o.generado_en                                                 AS informe_generado_en,
           COALESCE(NULLIF(TRIM(o.responsable_nombre), ''), ct.nombres)  AS responsable_nombre,
           COALESCE(NULLIF(TRIM(o.responsable_cargo), ''), ct.cargo)     AS responsable_cargo,
           COALESCE(NULLIF(TRIM(o.responsable_telefono), ''), NULLIF(TRIM(ct.telefono_movil), '')) AS responsable_telefono,
           o.detalle_servicio, o.comentario_pruebas,
           o.severidad_general, o.estado_equipo_final,
           IFNULL(o.rev_jefatura, 0) AS rev_jefatura, IFNULL(o.requiere_precotizacion, 0) AS requiere_precotizacion,
           IFNULL(o.segunda_visita, 0) AS segunda_visita, IFNULL(o.aplica_garantia, 0) AS aplica_garantia,
           o.error_critico_motivo AS error_critico,
           -- Contadores del complementario
           (SELECT COUNT(*) FROM evidencia_fotografica f WHERE f.id_informe = c.id_informe AND f.eliminado_en IS NULL)                      AS n_fotos,
           (SELECT COUNT(*) FROM evidencia_fotografica f WHERE f.id_informe = c.id_informe AND f.eliminado_en IS NULL
              AND f.id_evidencia_origen IS NULL)                                                                                             AS n_fotos_agregadas,
           (SELECT COUNT(*) FROM informe_observacion x WHERE x.id_informe = c.id_informe AND x.eliminado_en IS NULL)                        AS n_observaciones,
           (SELECT COUNT(*) FROM informe_recomendacion x WHERE x.id_informe = c.id_informe AND x.eliminado_en IS NULL)                      AS n_recomendaciones,
           -- Precotización
           pc.id_precotizacion, pc.numero AS numero_precot, pc.estado AS estado_precot, pc.fecha_envio AS fecha_precot,
           pc.nota_supervisor AS nota_precotizacion,
           (SELECT COUNT(*) FROM precotizacion_item pi WHERE pi.id_precotizacion = pc.id_precotizacion AND pi.eliminado_en IS NULL)          AS n_items_precot,
           pd.id_propuesta AS id_propuesta_derivada, pd.numero AS numero_propuesta_derivada, pd.version AS version_propuesta_derivada,
           pd.estado AS estado_propuesta_derivada,
           -- Acciones: se edita mientras el original no esté revisado; la precotización convertida en propuesta ya no se edita
           (v_editar = 1 AND b.estado NOT IN ('revisado', 'aprobado'))                                                 AS puede_editar,
           (v_editar = 1 AND b.estado NOT IN ('revisado', 'aprobado') AND IFNULL(pc.estado, '') <> 'convertido_propuesta') AS puede_editar_precotizacion,
           (v_editar = 1 AND b.estado NOT IN ('revisado', 'aprobado') AND c.estado = 'borrador')                       AS puede_descartar
    FROM tmp_rt_base b
    JOIN informe_tecnico o           ON o.id_informe = b.id_informe
    JOIN informe_tecnico c           ON c.id_informe = p_id_complementario
    LEFT JOIN orden_servicio os      ON os.id_os = b.id_os
    LEFT JOIN contacto_cliente ct    ON ct.id_contacto = os.id_contacto
    LEFT JOIN usuario us             ON us.id_usuario = c.id_tecnico
    LEFT JOIN precotizacion pc       ON pc.id_precotizacion = v_id_pc
    LEFT JOIN propuesta_comercial pd ON pd.id_propuesta = pc.id_propuesta_generada;

    -- 3. Procedimiento del original (solo lectura)
    SELECT ip.id_paso, ip.orden, ip.titulo, ip.detalle, ip.realizado, ip.nota, ip.origen
    FROM informe_procedimiento ip
    WHERE ip.id_informe = v_padre AND ip.eliminado_en IS NULL
    ORDER BY ip.orden, ip.id_paso;

    -- 4. Ensayos del original (solo lectura)
    SELECT en.id_ensayo, en.tipo, en.orden, en.punto, en.nota_punto, en.carga, en.lectura, en.error, en.tolerancia,
           en.resultado,
           CASE en.resultado WHEN 'conforme'    THEN IF(en.tipo = 'pesaje', 'Dentro', 'Conforme')
                             WHEN 'no_conforme' THEN IF(en.tipo = 'pesaje', 'Fuera', 'No conforme') END AS resultado_label,
           en.origen
    FROM informe_ensayo en
    WHERE en.id_informe = v_padre AND en.eliminado_en IS NULL
    ORDER BY (en.tipo = 'excentricidad'), en.orden, en.id_ensayo;

    -- 5. Observaciones del complementario
    SELECT x.id_observacion, x.codigo, x.orden, x.titulo, x.descripcion, x.ubicacion, x.detalle_extra,
           x.nivel_afectacion, x.id_evidencia, f.url_archivo AS url_foto, x.origen,
           (x.id_observacion_origen IS NOT NULL) AS copiada,
           x.clasificacion, cf.String1 AS clasificacion_nombre, x.componente, mf.String1 AS componente_nombre
    FROM informe_observacion x
    LEFT JOIN evidencia_fotografica f ON f.id_evidencia = x.id_evidencia AND f.eliminado_en IS NULL
    LEFT JOIN tabla_maestra cf ON cf.IdTablaMaestra = (SELECT MIN(m.IdTablaMaestra) FROM tabla_maestra m
                                                      WHERE m.Descripcion = 'CLASIFICACION_FALLA' AND m.IdEmpresa = 1 AND m.String2 = x.clasificacion AND m.eliminado_en IS NULL)
    LEFT JOIN tabla_maestra mf ON mf.IdTablaMaestra = (SELECT MIN(m.IdTablaMaestra) FROM tabla_maestra m
                                                      WHERE m.Descripcion = 'COMPONENTE_FALLA' AND m.IdEmpresa = 1 AND m.String2 = x.componente AND m.eliminado_en IS NULL)
    WHERE x.id_informe = p_id_complementario AND x.eliminado_en IS NULL
    ORDER BY x.orden, x.id_observacion;

    -- 6. Recomendaciones del complementario
    SELECT r.id_recomendacion, r.codigo, r.orden, r.titulo, r.descripcion, r.prioridad, r.plazo,
           r.id_observacion, x.codigo AS codigo_observacion, r.origen
    FROM informe_recomendacion r
    LEFT JOIN informe_observacion x ON x.id_observacion = r.id_observacion AND x.eliminado_en IS NULL
    WHERE r.id_informe = p_id_complementario AND r.eliminado_en IS NULL
    ORDER BY r.orden, r.id_recomendacion;

    -- 7. Fotos y videos del complementario (etapa*: la etapa de la app de las fotos copiadas del técnico, como en el móvil)
    CALL SP_CatalogoEvidenciasMovil();
    SELECT f.id_evidencia, f.url_archivo, f.descripcion,
           IF(f.id_evidencia_origen IS NULL, NULL, f.codigo)  AS etapa,
           IF(f.id_evidencia_origen IS NULL, NULL, COALESCE(ce.nombre, IF(f.codigo = 'falla', 'Falla', NULL))) AS etapa_nombre,
           IF(f.id_evidencia_origen IS NULL, NULL, ce.descripcion) AS etapa_descripcion,
           tf.String2                                         AS momento,
           IF(f.es_video = 1, 'Video', tf.String1)            AS momento_label,
           CONVERT_TZ(f.timestamp_captura, '+00:00', '-05:00') AS fecha_captura,   -- hora de Lima
           f.latitud, f.longitud, (f.latitud IS NOT NULL AND f.longitud IS NOT NULL) AS georreferenciada,
           f.validacion_ia, f.es_video,
           IF(f.override_aprobado = 1, 1, 0)                  AS forzada,
           f.motivo_forzado, f.motivo_rechazo_ia,
           (f.id_evidencia_origen IS NOT NULL)                AS copiada,
           IF(f.id_evidencia_origen IS NOT NULL, 'tecnico', 'supervisor') AS origen,
           NULLIF(TRIM(CONCAT(IFNULL(uf.nombre, ''), ' ', IFNULL(uf.apellido, ''))), '') AS subida_por,
           COALESCE(f.id_observacion, x.id_observacion)       AS id_observacion,
           COALESCE(xv.codigo, x.codigo)                      AS codigo_observacion
    FROM evidencia_fotografica f
    LEFT JOIN tabla_maestra tf       ON tf.IdMaestro = 30 AND tf.IdEmpresa = 1 AND tf.Num1 = f.id_tipo_evidencia
    LEFT JOIN usuario uf             ON uf.id_usuario = f.id_usuario
    LEFT JOIN informe_observacion xv ON xv.id_observacion = f.id_observacion AND xv.eliminado_en IS NULL
    LEFT JOIN informe_observacion x  ON x.id_evidencia = f.id_evidencia AND x.id_informe = p_id_complementario AND x.eliminado_en IS NULL
    LEFT JOIN tmp_cat_evid ce        ON ce.codigo = f.codigo
    WHERE f.id_informe = p_id_complementario AND f.eliminado_en IS NULL
    ORDER BY (f.id_evidencia_origen IS NULL), f.timestamp_captura, f.id_evidencia;
    DROP TEMPORARY TABLE IF EXISTS tmp_cat_evid;

    -- 8. Ítems de la precotización
    SELECT pi.id_item, pi.orden, pi.concepto, pi.codigo, pi.id_suministro, pi.descripcion_tecnica, pi.cantidad, pi.unidad,
           pi.prioridad, pi.id_observacion, x.codigo AS codigo_observacion
    FROM precotizacion_item pi
    LEFT JOIN informe_observacion x ON x.id_observacion = pi.id_observacion AND x.eliminado_en IS NULL
    WHERE pi.id_precotizacion = v_id_pc AND pi.eliminado_en IS NULL
    ORDER BY pi.orden, pi.id_item;

    -- 9. Opciones de las listas (las mismas de la cabecera del informe en la app)
    SELECT 'tipo_equipo' AS lista, m.String2 AS codigo, m.String1 AS nombre, NULL AS padre
    FROM   tabla_maestra m WHERE m.Descripcion = 'CLASIFICACION_EQUIPO' AND m.IdEmpresa = 1 AND m.eliminado_en IS NULL
    UNION ALL
    SELECT 'clasificacion', m.String2, m.String1, NULL
    FROM   tabla_maestra m WHERE m.Descripcion = 'CLASIFICACION_FALLA' AND m.IdEmpresa = 1 AND m.eliminado_en IS NULL
    UNION ALL
    SELECT 'componente', m.String2, m.String1, m.String3
    FROM   tabla_maestra m WHERE m.Descripcion = 'COMPONENTE_FALLA' AND m.IdEmpresa = 1 AND m.eliminado_en IS NULL
    ORDER BY lista, nombre;

    DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;
END$$

DELIMITER ;
