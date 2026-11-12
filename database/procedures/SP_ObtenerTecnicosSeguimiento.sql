-- HU-51 (Sprint 5) Pestaña 3 "Técnicos Activos": una tarjeta por técnico con servicios hoy (estado, SSOMA, salida real vs programada, última ubicación y servicios del día).
-- El filtro "Estado" es el del TÉCNICO (el de su servicio más urgente). "Agrupar por zona" lo resuelve la pantalla con el campo Zona.
-- Resultados: 1 mensaje, 2 resumen, 3 tarjetas, 4 servicios de cada técnico.
DROP PROCEDURE IF EXISTS SP_ObtenerTecnicosSeguimiento;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerTecnicosSeguimiento(
    IN p_id_usuario BIGINT,
    IN p_id_tecnico BIGINT,
    IN p_id_cliente BIGINT,
    IN p_estado     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_zona       VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_busqueda   VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_estados VARCHAR(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT ',sin_salir,en_ruta,en_planta,en_ejecucion,con_demora,con_incidente,finalizado,';
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            @err_msg  = MESSAGE_TEXT,
            @err_code = MYSQL_ERRNO;
        CALL SP_LimpiarSeguimientoOperativo();
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF FN_PermisoAccion(p_id_usuario, 'seg_bandeja') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver la bandeja de seguimiento operativo.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF (p_id_tecnico IS NOT NULL AND p_id_tecnico <= 0) OR (p_id_cliente IS NOT NULL AND p_id_cliente <= 0) THEN
        SELECT 1 AS IdTipoMensaje, 'El técnico o el cliente del filtro no es válido.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF NULLIF(p_estado, '') IS NOT NULL AND LOCATE(CONCAT(',', p_estado, ','), v_estados) = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El estado del servicio no es válido.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF CHAR_LENGTH(IFNULL(p_zona, '')) > 100 OR CHAR_LENGTH(IFNULL(p_busqueda, '')) > 100 THEN
        SELECT 1 AS IdTipoMensaje, 'La zona o la búsqueda superan los 100 caracteres.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_ArmarSeguimientoOperativo();
    CALL SP_FiltrarSeguimientoOperativo(p_id_tecnico, p_id_cliente, NULL, NULLIF(p_zona, ''), NULLIF(TRIM(p_busqueda), ''));

    CREATE TEMPORARY TABLE tmp_sg_tf (id_usuario BIGINT NOT NULL, PRIMARY KEY (id_usuario));
    INSERT INTO tmp_sg_tf
    SELECT DISTINCT ut.id_usuario FROM tmp_sg_ut ut JOIN tmp_sg_f f ON f.id_os = ut.id_os
    WHERE p_id_tecnico IS NULL OR ut.id_usuario = p_id_tecnico
    UNION
    -- HU-20: técnicos con la jornada iniciada y sin servicio programado hoy (solo cuando no hay filtros que los excluyan)
    SELECT t.id_usuario FROM tmp_sg_tec t
    WHERE t.n_servicios = 0 AND p_id_cliente IS NULL AND (p_id_tecnico IS NULL OR t.id_usuario = p_id_tecnico)
      AND NULLIF(p_zona, '') IS NULL AND NULLIF(TRIM(p_busqueda), '') IS NULL;
    IF NULLIF(p_estado, '') IS NOT NULL THEN
        DELETE tf FROM tmp_sg_tf tf JOIN tmp_sg_tec t ON t.id_usuario = tf.id_usuario WHERE t.estado_seg <> p_estado;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'OK' AS Mensaje;
    SELECT (SELECT COUNT(*) FROM tmp_sg_tf) AS Total,
           (SELECT COUNT(*) FROM tmp_sg_tec WHERE estado_seg = 'sin_salir') AS AdicionalesSinIniciar,
           DATE_FORMAT(c.ahora, '%H:%i') AS Actualizado
    FROM tmp_sg_cfg c;

    SELECT t.id_usuario AS IdUsuario, t.nombre AS Tecnico, t.iniciales AS Iniciales, t.cargo AS Cargo, t.zona AS Zona, t.estado_seg AS Estado,
           t.ssoma AS Ssoma, t.n_servicios AS Servicios, t.n_completados AS Completados, t.n_en_curso AS EnCurso,
           DATE_FORMAT(CONVERT_TZ(t.salida_utc, '+00:00', '-05:00'), '%H:%i') AS SalidaReal, DATE_FORMAT(t.salida_prog, '%H:%i') AS SalidaProgramada,
           IF(t.salida_utc IS NULL, NULL,
              TIMESTAMPDIFF(MINUTE, TIMESTAMP(c.hoy, t.salida_prog), CONVERT_TZ(t.salida_utc, '+00:00', '-05:00'))) AS DiferenciaSalidaMin,
           COALESCE(NULLIF(p.direccion, ''), IF(p.lat IS NULL, NULL, CONCAT(FORMAT(p.lat, 5), ', ', FORMAT(p.lon, 5)))) AS UltimaUbicacion,
           IF(p.ts_utc IS NULL, NULL, TIMESTAMPDIFF(MINUTE, p.ts_utc, c.ahora_utc)) AS MinutosUbicacion,
           t.jornada AS Jornada, t.actividad AS Actividad
    FROM tmp_sg_tec t
    JOIN tmp_sg_tf tf ON tf.id_usuario = t.id_usuario
    LEFT JOIN tmp_sg_pos p ON p.id_usuario = t.id_usuario
    JOIN tmp_sg_cfg c
    ORDER BY t.zona, t.nombre;

    SELECT ut.id_usuario AS IdUsuario, o.id_os AS IdOs, o.numero AS Numero, o.razon_social AS Cliente, o.estado_seg AS Estado,
           DATE_FORMAT(o.hora_inicio, '%H:%i') AS HoraInicio, DATE_FORMAT(o.hora_fin_est, '%H:%i') AS HoraFin, ut.rol AS Rol,
           o.n_equipos AS Equipos, o.n_ejecutados AS Ejecutados
    FROM tmp_sg_ut ut
    JOIN tmp_sg_tf tf ON tf.id_usuario = ut.id_usuario
    JOIN tmp_sg_os o ON o.id_os = ut.id_os
    ORDER BY ut.id_usuario, o.hora_inicio, o.id_os;

    CALL SP_LimpiarSeguimientoOperativo();
END$$

DELIMITER ;
