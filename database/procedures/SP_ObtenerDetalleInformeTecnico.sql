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
           COALESCE(f.id_observacion, o.id_observacion)       AS id_observacion,
           COALESCE(ov.codigo, o.codigo)                      AS codigo_observacion
    FROM evidencia_fotografica f
    JOIN tmp_rt_base b ON b.id_informe = p_id_informe
    LEFT JOIN tabla_maestra tf ON tf.IdMaestro = 30 AND tf.IdEmpresa = 1 AND tf.Num1 = f.id_tipo_evidencia
    LEFT JOIN informe_observacion ov ON ov.id_observacion = f.id_observacion AND ov.eliminado_en IS NULL
    LEFT JOIN informe_observacion o  ON o.id_evidencia = f.id_evidencia AND o.id_informe = p_id_informe AND o.eliminado_en IS NULL
    WHERE f.eliminado_en IS NULL AND f.id_tipo_evidencia NOT IN (6, 7)
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
