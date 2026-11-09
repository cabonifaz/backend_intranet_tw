-- HU-51 (Sprint 5) Bandeja de Seguimiento Operativo: KPIs superiores, pestaña 1 Vista Principal (mapa operativo, alertas críticas, próximos hitos) y contadores de las pestañas.
-- Acceso: seg_bandeja (observacional: solo lectura; la bandeja no cambia datos). Los KPIs y contadores del día NO dependen de los filtros;
-- el mapa y las alertas sí respetan los filtros globales. "Hoy" es la fecha de Lima.
-- Resultados: 1 mensaje, 2 KPIs y contadores, 3 pines del mapa, 4 alertas críticas (más recientes), 5 totales de alertas, 6 próximos hitos, 7 resumen de hitos.
DROP PROCEDURE IF EXISTS SP_ObtenerResumenSeguimiento;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerResumenSeguimiento(
    IN p_id_usuario BIGINT,
    IN p_id_tecnico BIGINT,
    IN p_id_cliente BIGINT,
    IN p_estado     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_zona       VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_busqueda   VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_prog, v_ruta, v_planta, v_ejec, v_dem, v_fin, v_sinsalir, v_filtrados, v_tecs, v_incs INT DEFAULT 0;
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
    CALL SP_FiltrarSeguimientoOperativo(p_id_tecnico, p_id_cliente, NULLIF(p_estado, ''), NULLIF(p_zona, ''), NULLIF(TRIM(p_busqueda), ''));

    SELECT 2 AS IdTipoMensaje, 'OK' AS Mensaje;

    -- 2 KPIs del día (sin filtros) y contadores de pestañas (con filtros)
    SELECT COUNT(*), IFNULL(SUM(estado_seg = 'en_planta'), 0), IFNULL(SUM(estado_seg = 'en_ejecucion'), 0),
           IFNULL(SUM(estado_seg IN ('con_demora', 'con_incidente')), 0), IFNULL(SUM(estado_seg = 'finalizado'), 0), IFNULL(SUM(estado_seg = 'sin_salir'), 0)
      INTO v_prog, v_planta, v_ejec, v_dem, v_fin, v_sinsalir FROM tmp_sg_os;
    SELECT IFNULL(SUM(estado_seg = 'en_ruta'), 0), COUNT(*) INTO v_ruta, v_tecs FROM tmp_sg_tec;
    SELECT COUNT(*) INTO v_filtrados FROM tmp_sg_f;
    SELECT COUNT(*) INTO v_incs FROM tmp_sg_inc;
    SELECT v_prog AS Programados, v_ruta AS TecnicosEnRuta, v_planta AS EnPlanta, v_ejec AS EnEjecucion, v_dem AS ConDemoraIncidente, v_fin AS Finalizados,
           v_sinsalir AS SinSalir, v_filtrados AS ServiciosFiltrados, v_tecs AS TecnicosActivos, v_incs AS IncidenciasDelDia,
           DATE_FORMAT(c.ahora, '%H:%i') AS Actualizado, c.refresco AS RefrescoSegundos
    FROM tmp_sg_cfg c;

    -- 3 Pines del mapa: un pin por técnico con servicios en el filtro; el color lo da el estado
    CREATE TEMPORARY TABLE tmp_sg_tf (id_usuario BIGINT NOT NULL, PRIMARY KEY (id_usuario));
    INSERT INTO tmp_sg_tf SELECT DISTINCT ut.id_usuario FROM tmp_sg_ut ut JOIN tmp_sg_f f ON f.id_os = ut.id_os;
    SELECT t.id_usuario AS IdUsuario, t.nombre AS Tecnico, t.iniciales AS Iniciales, t.estado_seg AS Estado, p.lat AS Latitud, p.lon AS Longitud,
           COALESCE(p.direccion, '') AS Direccion, IF(p.ts_utc IS NULL, NULL, TIMESTAMPDIFF(MINUTE, p.ts_utc, c.ahora_utc)) AS MinutosUbicacion,
           t.id_os_actual AS IdOs, o.numero AS NumeroOs, o.razon_social AS Cliente
    FROM tmp_sg_tec t
    JOIN tmp_sg_tf tf ON tf.id_usuario = t.id_usuario
    LEFT JOIN tmp_sg_pos p ON p.id_usuario = t.id_usuario
    LEFT JOIN tmp_sg_os o ON o.id_os = t.id_os_actual
    JOIN tmp_sg_cfg c
    ORDER BY t.nombre;

    -- 4 Alertas críticas: las más recientes del día (menos minutos = más reciente), críticas primero
    SELECT a.clave AS Clave, a.tipo AS Tipo, a.severidad AS Severidad, a.titulo AS Titulo, a.detalle AS Detalle, a.minutos AS Minutos,
           IF(a.minutos <= c.nueva, 1, 0) AS Nueva, a.id_usuario AS IdUsuario, a.tecnico AS Tecnico, a.id_os AS IdOs, a.numero AS NumeroOs
    FROM tmp_sg_alerta a JOIN tmp_sg_f f ON f.id_os = a.id_os JOIN tmp_sg_cfg c
    ORDER BY FIELD(a.severidad, 'critica', 'advertencia', 'info'), a.minutos, a.clave
    LIMIT 10;
    -- 5 Totales
    SELECT COUNT(*) AS Total, IFNULL(SUM(a.minutos <= c.nueva), 0) AS Nuevas, IFNULL(SUM(a.severidad = 'critica'), 0) AS Criticas
    FROM tmp_sg_alerta a JOIN tmp_sg_f f ON f.id_os = a.id_os JOIN tmp_sg_cfg c;

    -- 6 Próximos hitos (ventana configurable; los vencidos sin ocurrir se muestran primero como atrasados)
    SELECT h.id_os AS IdOs, h.numero AS NumeroOs, h.tipo AS Tipo, DATE_FORMAT(h.esperado, '%H:%i') AS Hora, h.texto AS Texto, h.detalle AS Detalle,
           IF(h.esperado < c.ahora, 1, 0) AS Atrasado, h.id_tecnico AS IdTecnico
    FROM tmp_sg_hito h JOIN tmp_sg_f f ON f.id_os = h.id_os JOIN tmp_sg_cfg c
    WHERE NOT (h.tipo = 'retorno' AND h.esperado <= c.ahora) AND h.esperado <= DATE_ADD(c.ahora, INTERVAL c.ventana MINUTE)
    ORDER BY h.esperado, h.id_os
    LIMIT 6;
    -- 7 Resumen: "Todos los hitos del día ya ocurrieron" cuando no queda ninguno pendiente
    SELECT IF(COUNT(*) = 0, 1, 0) AS TodosOcurrieron, COUNT(*) AS Pendientes
    FROM tmp_sg_hito h JOIN tmp_sg_cfg c WHERE NOT (h.tipo = 'retorno' AND h.esperado <= c.ahora);

    CALL SP_LimpiarSeguimientoOperativo();
END$$

DELIMITER ;
