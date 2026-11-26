-- HU-57 (Sprint 5) Revisión Técnica: modal "Detalle del Servicio Técnico" y pantalla de edición (HU-58).
-- Acceso: rt_bandeja (y el informe debe estar en el alcance del usuario, ver SP_ArmarBaseInformes).
-- Resultados:
--   1 mensaje
--   2 cabecera: Resumen (tarjetas, información general, validaciones —incluida la rendición de viáticos de la OS: rendicion_estado
--     abierta | cerrada | sin_programacion, rendicion_saldo, rendicion_tipo reembolso | devolucion | cuadrado, gastos_por_revisar—,
--     diagnóstico, trazabilidad), resultado global de los
--     ensayos, descripción complementaria, precotización (cabecera) y acciones permitidas
--   3 procedimiento ejecutado · 4 ensayos · 5 observaciones · 6 recomendaciones · 7 fotos · 8 ítems de la precotización
--   9 historial reciente (5 últimos eventos; el completo está en SP_ObtenerHistorialInforme)
-- Informe Complementario (23/11/2026): el informe del técnico es INMUTABLE (puede_editar y puede_registrar_precotizacion quedan siempre en 0).
--   La cabecera trae id_informe_complementario / tiene_complementario / estado_complementario y puede_generar_complementario.
--   Los ítems de precotización (resultado 8) son los de la precotización vigente: la del complementario o, si es anterior al cambio, la del original.
-- PDF del informe del técnico (24/11/2026): también lo usa GET /informes/{id}/pdf. Acceso con SP_ArmarBaseInformeAcceso: rt_bandeja con el informe en su
--   alcance, o precot_ver (Comercial) si una precotización del informe o de su complementario está en su alcance (solo lectura, sin acciones).
--   url_pdf: el que dejó la app o, si no hay, el endpoint del PDF. La cabecera trae además lo que el técnico cargó en la app: N° de informe, quién
--   atendió en planta, detalle del servicio (JSON), comentario de las pruebas y diagnóstico final.
-- HU-55 (24/11/2026, requiere la migración 127): via (app · intranet) y, solo con via = 'intranet', id_registrado_por, registrado_por (nombre de quien lo
--   registró en nombre del técnico) y fecha_registro (primera vez, hora de Lima).
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
    DECLARE v_id_os       BIGINT;
    DECLARE v_prog        BIGINT;
    DECLARE v_id_rend     BIGINT;
    DECLARE v_rend_estado VARCHAR(20)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_rend_saldo  DECIMAL(12,2);
    DECLARE v_rend_tipo   VARCHAR(12)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_gastos_rev  INT DEFAULT 0;
    DECLARE v_acceso      VARCHAR(10)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    IF FN_PermisoAccion(p_id_usuario, 'rt_bandeja') = 0 AND FN_PermisoAccion(p_id_usuario, 'precot_ver') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver la revisión de informes técnicos.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_ArmarBaseInformeAcceso(p_id_usuario, p_id_informe, v_acceso);
    -- Comercial solo lee: sin acciones
    SET v_editar  = IF(v_acceso = 'rt', FN_PermisoAccion(p_id_usuario, 'rt_editar'), 0);
    SET v_revisar = IF(v_acceso = 'rt', FN_PermisoAccion(p_id_usuario, 'rt_revisar'), 0);
    SELECT COUNT(*) INTO v_existe FROM tmp_rt_base;
    IF v_existe = 0 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;
        SELECT 1 AS IdTipoMensaje, 'El informe no existe o no está en tu alcance.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Rendición de viáticos de la OS (Resumen de Validaciones): abierta | cerrada | sin_programacion, saldo, tipo y gastos por revisar
    SELECT MAX(id_os) INTO v_id_os FROM tmp_rt_base;
    SELECT MAX(id_programacion) INTO v_prog
    FROM programacion WHERE id_os = v_id_os AND estado <> 'cancelada' AND eliminado_en IS NULL;
    IF v_prog IS NULL THEN
        SET v_rend_estado = 'sin_programacion';
    ELSE
        SELECT MAX(id_rendicion) INTO v_id_rend FROM programacion_rendicion WHERE id_programacion = v_prog AND eliminado_en IS NULL;
        IF v_id_rend IS NOT NULL THEN
            SELECT 'cerrada', saldo, tipo_saldo INTO v_rend_estado, v_rend_saldo, v_rend_tipo
            FROM programacion_rendicion WHERE id_rendicion = v_id_rend;
        ELSE
            SELECT IFNULL(SUM(IF(g.tipo = 'gasto_solicitado' AND g.estado <> 'rechazado', g.monto, 0)), 0)
                 - IFNULL(SUM(IF(g.tipo = 'viatico_asignado', g.monto, 0)), 0)
              INTO v_rend_saldo
            FROM gasto_viatico g
            WHERE g.eliminado_en IS NULL AND g.tipo IN ('viatico_asignado', 'gasto_solicitado')
              AND (g.id_programacion = v_prog OR (g.id_programacion IS NULL AND g.id_os = v_id_os));
            SET v_rend_estado = 'abierta';
            SET v_rend_tipo = CASE WHEN v_rend_saldo > 0 THEN 'reembolso' WHEN v_rend_saldo < 0 THEN 'devolucion' ELSE 'cuadrado' END;
        END IF;
    END IF;
    SELECT COUNT(*) INTO v_gastos_rev
    FROM gasto_viatico
    WHERE id_os = v_id_os AND tipo = 'gasto_solicitado' AND estado IN ('pendiente', 'observado') AND eliminado_en IS NULL;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Cabecera
    SELECT b.id_informe, b.numero_informe, b.version, b.estado, b.grupo_estado,
           CASE b.grupo_estado
               WHEN 'pendiente_revision'          THEN CASE b.estado WHEN 'en_revision' THEN 'En revisión' WHEN 'observado' THEN 'Observado'
                                                                     ELSE 'Pendiente de revisión' END
               WHEN 'revisado_sin_complementario' THEN 'Revisado'
               ELSE 'Revisado con complementario' END                  AS estado_label,
           COALESCE(b.url_pdf, CONCAT('/api/servicio-tecnico/informes/', b.id_informe, '/pdf')) AS url_pdf,
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
           CASE WHEN b.id_propuesta_derivada IS NOT NULL THEN 'convertida'
                WHEN IFNULL(b.n_items_precot, 0) > 0 THEN 'precotizacion_enviada'
                ELSE 'no_aplica' END                                   AS oportunidad_comercial,
           v_rend_estado AS rendicion_estado, v_rend_saldo AS rendicion_saldo, v_rend_tipo AS rendicion_tipo, v_gastos_rev AS gastos_por_revisar,
           -- Resultado global de los ensayos
           it.normativa, it.patron_ensayo, it.tolerancia_excentricidad, it.resultado_global,
           it.error_maximo, it.error_maximo_detalle, it.incertidumbre, it.factor_k, it.decision_tecnica,
           it.descripcion_complementaria,
           -- Lo que cargó el técnico en la cabecera del informe de la app
           it.numero_informe                                            AS numero_informe_tecnico,
           it.generado_en                                               AS informe_generado_en,
           COALESCE(NULLIF(TRIM(it.responsable_nombre), ''), ct.nombres) AS responsable_nombre,
           COALESCE(NULLIF(TRIM(it.responsable_cargo), ''), ct.cargo)    AS responsable_cargo,
           COALESCE(NULLIF(TRIM(it.responsable_telefono), ''), NULLIF(TRIM(ct.telefono_movil), '')) AS responsable_telefono,
           it.detalle_servicio, it.comentario_pruebas, it.severidad_general, it.estado_equipo_final,
           IFNULL(it.rev_jefatura, 0) AS rev_jefatura, IFNULL(it.requiere_precotizacion, 0) AS requiere_precotizacion,
           IFNULL(it.segunda_visita, 0) AS segunda_visita, IFNULL(it.aplica_garantia, 0) AS aplica_garantia,
           it.error_critico_motivo AS error_critico,
           -- HU-55 (migración 127): registrado desde la intranet en nombre del técnico. registrado_en está en UTC → hora de Lima
           it.via,
           IF(it.via = 'intranet', it.id_registrado_por, NULL)          AS id_registrado_por,
           IF(it.via = 'intranet', NULLIF(TRIM(CONCAT(IFNULL(urg.nombre, ''), ' ', IFNULL(urg.apellido, ''))), ''), NULL) AS registrado_por,
           IF(it.via = 'intranet' AND it.registrado_en IS NOT NULL, CONVERT_TZ(it.registrado_en, '+00:00', '-05:00'), NULL) AS fecha_registro,
           -- Trazabilidad
           b.fecha_envio_revision, b.fecha_inicio_revision, b.fecha_revision, b.id_revisor, b.revisor, b.nota_revision,
           b.horas_espera, b.sla_horas, b.sla_vencido,
           b.id_precotizacion, b.numero_precot, b.estado_precot, b.fecha_precot, b.autor_precot, b.n_items_precot,
           pc.nota_supervisor                                          AS nota_precotizacion,
           b.id_propuesta_derivada, b.numero_propuesta_derivada, b.version_propuesta_derivada, b.estado_propuesta_derivada,
           -- Informe complementario
           b.id_complementario                                          AS id_informe_complementario,
           b.numero_complementario                                      AS numero_complementario,
           b.estado_complementario,
           (b.estado_complementario = 'complementario')                 AS tiene_complementario,
           -- Acciones (el informe del técnico es inmutable: se corrige con un complementario)
           0                                                            AS puede_editar,
           0                                                            AS puede_registrar_precotizacion,
           (v_editar = 1 AND b.estado NOT IN ('revisado', 'aprobado') AND b.id_complementario IS NULL)  AS puede_generar_complementario,
           (v_revisar = 1 AND b.estado NOT IN ('revisado', 'aprobado')
            AND IFNULL(b.estado_complementario, '') <> 'borrador')                                        AS puede_registrar_revision,
           CASE WHEN b.estado IN ('revisado', 'aprobado') THEN NULL
                WHEN b.estado_complementario = 'borrador'
                    THEN 'Tienes un informe complementario sin guardar. Guárdalo o descártalo antes de marcar el informe como revisado.'
                ELSE NULL END                                          AS mensaje_bloqueo,
           CASE WHEN b.estado IN ('revisado', 'aprobado') THEN NULL
                WHEN b.estado_complementario = 'borrador' THEN 'continuar_complementario'
                ELSE 'registrar_revision' END                          AS accion_principal
    FROM tmp_rt_base b
    JOIN informe_tecnico it       ON it.id_informe = b.id_informe
    LEFT JOIN orden_servicio os   ON os.id_os = b.id_os
    LEFT JOIN contacto_cliente ct ON ct.id_contacto = os.id_contacto
    LEFT JOIN usuario urg         ON urg.id_usuario = it.id_registrado_por
    LEFT JOIN precotizacion pc    ON pc.id_precotizacion = b.id_precotizacion;

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
    --    etapa / etapa_nombre / etapa_descripcion: la etapa del registro fotográfico de la app (placa, inicial, prueba…) con el mismo nombre y
    --    descripción que muestra el móvil (SP_CatalogoEvidenciasMovil). La app no guarda una descripción propia por foto.
    CALL SP_CatalogoEvidenciasMovil();
    SELECT f.id_evidencia, f.url_archivo, f.descripcion,
           f.codigo                                           AS etapa,
           COALESCE(ce.nombre, IF(f.codigo = 'falla', 'Falla', NULL)) AS etapa_nombre,
           ce.descripcion                                     AS etapa_descripcion,
           tf.String2                                         AS momento,
           IF(f.es_video = 1, 'Video de encendido', tf.String1) AS momento_label,
           CONVERT_TZ(f.timestamp_captura, '+00:00', '-05:00') AS fecha_captura,   -- hora de Lima
           f.latitud, f.longitud, (f.latitud IS NOT NULL AND f.longitud IS NOT NULL) AS georreferenciada,
           f.validacion_ia,
           f.es_video,
           IF(f.override_aprobado = 1, 1, 0)                  AS forzada,           -- HU-12: la IA la rechazó y el técnico la aceptó con un motivo
           f.motivo_forzado, f.motivo_rechazo_ia,
           NULLIF(TRIM(CONCAT(IFNULL(uf.nombre, ''), ' ', IFNULL(uf.apellido, ''))), '') AS forzada_por,
           IF(f.forzada_en IS NULL, NULL, CONVERT_TZ(f.forzada_en, '+00:00', '-05:00')) AS forzada_en,
           COALESCE(f.id_observacion, o.id_observacion)       AS id_observacion,
           COALESCE(ov.codigo, o.codigo)                      AS codigo_observacion
    FROM evidencia_fotografica f
    JOIN tmp_rt_base b ON b.id_informe = p_id_informe
    LEFT JOIN tabla_maestra tf ON tf.IdMaestro = 30 AND tf.IdEmpresa = 1 AND tf.Num1 = f.id_tipo_evidencia
    LEFT JOIN usuario uf ON uf.id_usuario = f.id_usuario_override
    LEFT JOIN informe_observacion ov ON ov.id_observacion = f.id_observacion AND ov.eliminado_en IS NULL
    LEFT JOIN informe_observacion o  ON o.id_evidencia = f.id_evidencia AND o.id_informe = p_id_informe AND o.eliminado_en IS NULL
    LEFT JOIN tmp_cat_evid ce        ON ce.codigo = f.codigo
    WHERE f.eliminado_en IS NULL AND f.id_tipo_evidencia NOT IN (6, 7)
      AND f.url_archivo NOT LIKE 'qr://%' AND IFNULL(f.vigente, 1) = 1   -- sin las lecturas del QR (no tienen archivo) ni los intentos descartados por retoma
      AND (f.id_informe = p_id_informe
           OR (f.id_informe IS NULL AND f.id_os = b.id_os AND (f.id_equipo = b.id_equipo OR f.id_equipo IS NULL)))
    ORDER BY f.timestamp_captura, f.id_evidencia;
    DROP TEMPORARY TABLE IF EXISTS tmp_cat_evid;

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
