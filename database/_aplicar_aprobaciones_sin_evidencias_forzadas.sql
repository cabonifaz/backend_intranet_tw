-- Aprobaciones del detalle del servicio: las evidencias fotográficas forzadas ya no se listan ni se cuentan. Ejecutar con Alt+X (No al aviso) y reiniciar la API.
-- HU-52 (Sprint 5) Pestaña Aprobaciones del Detalle del Servicio en Ruta: una sola lista con todo lo que el encargado aprueba en esa OS. SOLO LECTURA.
--   salida    autorizacion_salida_os (App Mobile HU-04)
--   llegada   llegada_forzada_os (migración 111, HU-06)
--   (las evidencias fotográficas forzadas ya NO se listan aquí: se ven en Avance por equipos > Fotos)
--   ensayo    informe_tecnico guardado con error crítico (error_critico_motivo, migraciones 100 y 107); revisión en error_critico_revision (113)
-- Acceso: seg_bandeja y el servicio en la jornada de hoy (SP_PrepararDetalleServicioRuta), igual que las demás pestañas.
-- puede_resolver: misma regla de área que SP_ObtenerAutorizacionesSalida / SP_ResolverLlegadaForzada: el encargado del área de la solicitud (o de la RQ
--   si la solicitud no la tiene), Jefe o Coordinador de Operaciones, supervisor de Operaciones o administrador. Salida y llegada: solo la última
--   solicitud pendiente de la OS (los SP de resolver actúan sobre esa); la salida, además, mientras la OS siga programada.
-- Resultados: 1 mensaje · 2 aprobaciones · 3 totales (total, pendientes, aprobadas, rechazadas).
DROP PROCEDURE IF EXISTS SP_ObtenerAprobacionesServicioRuta;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerAprobacionesServicioRuta(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT
)
proc: BEGIN
    DECLARE v_msg         VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_area_jefe   VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_general     TINYINT DEFAULT 0;
    DECLARE v_area_os     VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado_os   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_ult_salida  BIGINT;
    DECLARE v_ult_llegada BIGINT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_apr;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    CALL SP_PrepararDetalleServicioRuta(p_id_usuario, p_id_os, v_msg);
    IF v_msg IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje;
        LEAVE proc;
    END IF;
    CALL SP_LimpiarSeguimientoOperativo();

    -- Quién consulta: encargado de un área (v_area_jefe) o supervisión general (v_general)
    SELECT COALESCE(IF(c.String2 LIKE 'jefe\_%' AND c.String3 IN ('servicio_tecnico', 'metrologia'), c.String3, NULL),
                    IF(u.rol_sistema = 'supervisor' AND u.area = 'metrologia', 'metrologia', NULL)),
           (u.cargo IN ('jefe_operaciones', 'coordinador_operaciones') OR u.rol_sistema IN ('administrador', 'admin')
            OR (u.rol_sistema = 'supervisor' AND u.area = 'operaciones'))
    INTO   v_area_jefe, v_general
    FROM   usuario u
    LEFT JOIN tabla_maestra c ON c.IdMaestro = 80 AND c.IdEmpresa = 1 AND c.String2 = u.cargo
    WHERE  u.id_usuario = p_id_usuario AND u.eliminado_en IS NULL AND u.estado = 'activo'
    LIMIT 1;
    SET v_general = IFNULL(v_general, 0);

    -- Área de la OS (la de la RQ) y estado
    SELECT os.estado, asr.area_usuario INTO v_estado_os, v_area_os
    FROM   orden_servicio os
    LEFT JOIN expediente_digital ed  ON ed.id_expediente    = os.id_expediente
    LEFT JOIN requerimiento      rq  ON rq.id_requerimiento = ed.id_requerimiento
    LEFT JOIN area_servicio_rq   asr ON asr.id_area_rq      = rq.id_area
    WHERE  os.id_os = p_id_os;

    SELECT MAX(id_autorizacion) INTO v_ult_salida  FROM autorizacion_salida_os WHERE id_os = p_id_os AND eliminado_en IS NULL;
    SELECT MAX(id_solicitud)    INTO v_ult_llegada FROM llegada_forzada_os     WHERE id_os = p_id_os AND eliminado_en IS NULL;

    DROP TEMPORARY TABLE IF EXISTS tmp_apr;
    CREATE TEMPORARY TABLE tmp_apr (
        tipo           VARCHAR(12)  NOT NULL,
        id             BIGINT       NOT NULL,
        titulo         VARCHAR(200) NULL,
        solicitante    VARCHAR(210) NULL,
        solicitado_en  DATETIME     NULL,
        motivo         VARCHAR(500) NULL,
        detalle        VARCHAR(500) NULL,
        estado         VARCHAR(12)  NOT NULL,
        resuelto_por   VARCHAR(210) NULL,
        cargo          VARCHAR(150) NULL,
        resuelto_en    DATETIME     NULL,
        comentario     VARCHAR(500) NULL,
        urgente        TINYINT      NOT NULL DEFAULT 0,
        puede_resolver TINYINT      NOT NULL DEFAULT 0
    ) DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;

    -- Salida
    INSERT INTO tmp_apr
    SELECT 'salida', a.id_autorizacion, 'Autorización de salida',
           NULLIF(TRIM(CONCAT(IFNULL(t.nombre, ''), ' ', IFNULL(t.apellido, ''))), ''),
           a.solicitado_en, a.motivo, a.pendientes, a.estado,
           NULLIF(TRIM(CONCAT(IFNULL(j.nombre, ''), ' ', IFNULL(j.apellido, ''))), ''), IFNULL(cj.String1, NULLIF(j.cargo, '')),
           a.resuelto_en, a.comentario,
           IF(a.estado = 'pendiente', 1, 0),
           IF(a.estado = 'pendiente' AND a.id_autorizacion = v_ult_salida AND v_estado_os IN ('programada', 'reprogramada')
              AND (v_general = 1 OR (v_area_jefe IS NOT NULL
                                     AND (COALESCE(a.area_destino, v_area_os) IS NULL OR COALESCE(a.area_destino, v_area_os) = v_area_jefe))), 1, 0)
    FROM   autorizacion_salida_os a
    LEFT JOIN usuario t        ON t.id_usuario = a.id_tecnico
    LEFT JOIN usuario j        ON j.id_usuario = a.id_jefe
    LEFT JOIN tabla_maestra cj ON cj.IdMaestro = 80 AND cj.IdEmpresa = 1 AND cj.String2 = j.cargo
    WHERE  a.id_os = p_id_os AND a.eliminado_en IS NULL;

    -- Llegada forzada
    INSERT INTO tmp_apr
    SELECT 'llegada', s.id_solicitud, 'Llegada forzada',
           NULLIF(TRIM(CONCAT(IFNULL(t.nombre, ''), ' ', IFNULL(t.apellido, ''))), ''),
           s.solicitado_en, s.motivo,
           NULLIF(CONCAT_WS(' · ', IF(s.distancia_metros IS NULL, NULL, CONCAT('A ', s.distancia_metros, ' m de la planta')),
                                   IF(IFNULL(s.intentos, 0) = 0, NULL, CONCAT(s.intentos, ' capturas fuera de rango'))), ''),
           s.estado,
           NULLIF(TRIM(CONCAT(IFNULL(j.nombre, ''), ' ', IFNULL(j.apellido, ''))), ''), IFNULL(cj.String1, NULLIF(j.cargo, '')),
           s.resuelto_en, s.comentario,
           IF(s.estado = 'pendiente', 1, 0),
           IF(s.estado = 'pendiente' AND s.id_solicitud = v_ult_llegada
              AND (v_general = 1 OR (v_area_jefe IS NOT NULL AND (s.area_destino IS NULL OR s.area_destino = v_area_jefe))), 1, 0)
    FROM   llegada_forzada_os s
    LEFT JOIN usuario t        ON t.id_usuario = s.id_tecnico
    LEFT JOIN usuario j        ON j.id_usuario = s.id_jefe
    LEFT JOIN tabla_maestra cj ON cj.IdMaestro = 80 AND cj.IdEmpresa = 1 AND cj.String2 = j.cargo
    WHERE  s.id_os = p_id_os AND s.eliminado_en IS NULL;

    -- Las evidencias fotográficas forzadas NO se aprueban aquí: se ven en Avance por equipos > Fotos (marcadas como «Forzada por el técnico»).

    -- Ensayos guardados con error crítico
    INSERT INTO tmp_apr
    SELECT 'ensayo', it.id_informe,
           LEFT(CONCAT('Ensayo con error crítico', IF(ec.codigo_tw IS NULL, '', CONCAT(' · ', ec.codigo_tw))), 200),
           NULLIF(TRIM(CONCAT(IFNULL(t.nombre, ''), ' ', IFNULL(t.apellido, ''))), ''),
           COALESCE(it.error_critico_notificado_en, it.ensayos_finalizado_en, it.modificado_en, it.creado_en),
           it.error_critico_motivo,
           CONCAT((SELECT COUNT(*) FROM informe_ensayo ie WHERE ie.id_informe = it.id_informe AND ie.critico = 1 AND ie.eliminado_en IS NULL),
                  ' lectura(s) fuera del EMP'),
           IFNULL(it.error_critico_revision, 'pendiente'),
           NULLIF(TRIM(CONCAT(IFNULL(j.nombre, ''), ' ', IFNULL(j.apellido, ''))), ''), IFNULL(cj.String1, NULLIF(j.cargo, '')),
           it.error_critico_revisado_en, it.error_critico_comentario,
           IF(it.error_critico_revision IS NULL, 1, 0),
           IF(it.error_critico_revision IS NULL
              AND (v_general = 1 OR (v_area_jefe IS NOT NULL AND (v_area_os IS NULL OR v_area_os = v_area_jefe))), 1, 0)
    FROM   informe_tecnico it
    LEFT JOIN equipo_cliente ec ON ec.id_equipo = it.id_equipo
    LEFT JOIN usuario t         ON t.id_usuario = it.id_tecnico
    LEFT JOIN usuario j         ON j.id_usuario = it.error_critico_revisado_por
    LEFT JOIN tabla_maestra cj  ON cj.IdMaestro = 80 AND cj.IdEmpresa = 1 AND cj.String2 = j.cargo
    WHERE  it.id_os = p_id_os AND it.eliminado_en IS NULL AND it.error_critico_motivo IS NOT NULL;

    SELECT 2 AS IdTipoMensaje, 'OK' AS Mensaje;

    SELECT tipo, id, titulo, solicitante, solicitado_en, motivo, detalle, estado, resuelto_por, cargo, resuelto_en, comentario,
           urgente, puede_resolver
    FROM   tmp_apr
    ORDER BY (estado = 'pendiente') DESC, urgente DESC, solicitado_en DESC, id DESC;

    SELECT COUNT(*) AS total,
           IFNULL(SUM(estado = 'pendiente'), 0) AS pendientes,
           IFNULL(SUM(estado = 'aprobada'), 0)  AS aprobadas,
           IFNULL(SUM(estado = 'rechazada'), 0) AS rechazadas
    FROM   tmp_apr;

    DROP TEMPORARY TABLE IF EXISTS tmp_apr;
END$$

DELIMITER ;

-- HU-52 (Sprint 5) Detalle del Servicio en Ruta: cabecera fija, pestaña Resumen y contadores de las pestañas. SOLO LECTURA.
-- Resultados: 1 mensaje · 2 cabecera+programación+métricas (1 fila) · 3 equipos a intervenir · 4 responsables · 5 contacto en planta (0 o 1 fila).
-- Estado del servicio: el mismo de la bandeja (HU-51). "Cierre del Servicio" solo se muestra si el estado es finalizado (campo MostrarCierre).
-- Chips: AprobacionesPendientes (salida, llegada forzada y ensayos con error sin resolver; requiere la migración 113) y
--   GastosPorRevisar (gastos rendidos pendientes u observados).
-- Fix 06/11: los equipos de la OS son de equipo_cliente (os_equipo.id_equipo), no de la tabla equipo (activos TW).
DROP PROCEDURE IF EXISTS SP_ObtenerDetalleServicioRuta;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerDetalleServicioRuta(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT
)
proc: BEGIN
    DECLARE v_msg      VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_refresco DECIMAL(18,6);
    DECLARE v_ahora    DATETIME;
    DECLARE v_ahora_utc DATETIME;
    DECLARE v_incid    INT DEFAULT 0;
    DECLARE v_min_dem  INT DEFAULT 0;
    DECLARE v_alertas  INT DEFAULT 0;
    DECLARE v_eq       INT DEFAULT 0;
    DECLARE v_eq_ok    INT DEFAULT 0;
    DECLARE v_pct      INT DEFAULT 0;
    DECLARE v_motivo   VARCHAR(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_ini_srv  DATETIME;
    DECLARE v_fin_srv  DATETIME;
    DECLARE v_min_srv  INT;
    DECLARE v_min_est  INT;
    DECLARE v_apr_pend   INT DEFAULT 0;
    DECLARE v_gastos_rev INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        CALL SP_LimpiarSeguimientoOperativo();
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    CALL SP_PrepararDetalleServicioRuta(p_id_usuario, p_id_os, v_msg);
    IF v_msg IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_ahora_utc = UTC_TIMESTAMP();
    SET v_ahora = CONVERT_TZ(v_ahora_utc, '+00:00', '-05:00');
    CALL SP_LeerParametroProgramacion('SEG_DETALLE_REFRESCO_SEGUNDOS', 15, v_refresco);

    -- Métricas rápidas
    SELECT COUNT(*) INTO v_incid FROM tmp_sg_inc WHERE id_os = p_id_os;
    SELECT IFNULL(SUM(duracion_min), 0) INTO v_min_dem FROM tmp_sg_inc WHERE id_os = p_id_os;
    SELECT COUNT(*) INTO v_alertas FROM tmp_sg_alerta WHERE id_os = p_id_os;
    SELECT n_equipos, n_ejecutados INTO v_eq, v_eq_ok FROM tmp_sg_os WHERE id_os = p_id_os;
    SET v_pct = IF(v_eq = 0, 0, ROUND(100 * v_eq_ok / v_eq));
    SELECT m.String1 INTO v_motivo FROM tmp_sg_inc i JOIN tabla_maestra m ON m.Descripcion IN ('MOTIVO_DEMORA_RUTA', 'TIPO_INCIDENCIA_OPERATIVA')
        AND m.IdEmpresa = 1 AND m.String2 = i.tipo_codigo WHERE i.id_os = p_id_os ORDER BY i.fecha DESC LIMIT 1;
    SELECT COALESCE(inicio_dt, llegada_dt), COALESCE(fin_dt, v_ahora) INTO v_ini_srv, v_fin_srv FROM tmp_sg_os WHERE id_os = p_id_os;
    SET v_min_srv = IF(v_ini_srv IS NULL, 0, GREATEST(0, TIMESTAMPDIFF(MINUTE, v_ini_srv, v_fin_srv)));
    SELECT IF(hora_inicio IS NULL OR hora_fin_est IS NULL, NULL, GREATEST(0, TIME_TO_SEC(TIMEDIFF(hora_fin_est, hora_inicio)) DIV 60))
      INTO v_min_est FROM tmp_sg_os WHERE id_os = p_id_os;

    -- Chips de las pestañas Aprobaciones y Viáticos (mismo universo que SP_ObtenerAprobacionesServicioRuta / SP_ObtenerViaticosServicioRuta)
    SELECT (SELECT COUNT(*) FROM autorizacion_salida_os WHERE id_os = p_id_os AND estado = 'pendiente' AND eliminado_en IS NULL)
         + (SELECT COUNT(*) FROM llegada_forzada_os     WHERE id_os = p_id_os AND estado = 'pendiente' AND eliminado_en IS NULL)
         + (SELECT COUNT(*) FROM informe_tecnico        WHERE id_os = p_id_os AND error_critico_motivo IS NOT NULL
                                                          AND error_critico_revision IS NULL AND eliminado_en IS NULL)
      INTO v_apr_pend;
    SELECT COUNT(*) INTO v_gastos_rev
    FROM gasto_viatico WHERE id_os = p_id_os AND tipo = 'gasto_solicitado' AND estado IN ('pendiente', 'observado') AND eliminado_en IS NULL;

    SELECT 2 AS IdTipoMensaje, 'OK' AS Mensaje;

    SELECT o.id_os AS IdOs, o.numero AS Numero, o.tipo AS Tipo, o.propuesta AS Propuesta, pg.codigo AS CodigoProgramacion, ex.numero AS Expediente,
           o.id_cliente AS IdCliente, o.razon_social AS Cliente, o.ruc AS Ruc, o.sede_nombre AS Sede, o.sede_direccion AS DireccionSede,
           ts.String1 AS TipoServicio, v_min_est AS MinutosEstimados, o.n_equipos AS EquiposProgramados,
           (SELECT nm.String1 FROM orden_metrologia om JOIN tabla_maestra nm ON nm.IdEmpresa = 1 AND nm.Num1 = om.id_norma AND nm.Descripcion IN ('NORMA_METROLOGICA', 'NORMA')
             WHERE om.id_os = o.id_os AND om.eliminado_en IS NULL LIMIT 1) AS Norma,
           osr.observaciones AS NotaProcedimiento,
           o.id_tecnico AS IdTecnicoLider, o.tecnico AS TecnicoLider, tl.cargo AS CargoTecnico, tl.ssoma AS EstadoSsoma,
           TIME_FORMAT(o.hora_inicio, '%H:%i') AS HoraInicio, TIME_FORMAT(o.hora_fin_est, '%H:%i') AS HoraFin,
           DATE_FORMAT(CONVERT_TZ(o.salida_utc, '+00:00', '-05:00'), '%H:%i') AS SalidaReal,
           IF(o.salida_utc IS NULL, NULL, IF(CONVERT_TZ(o.salida_utc, '+00:00', '-05:00') <= TIMESTAMP(DATE(v_ahora), SEC_TO_TIME(TIME_TO_SEC(o.hora_inicio))), 'puntual', 'tardia')) AS PuntualidadSalida,
           o.estado_seg AS Estado, DATE_FORMAT(v_ahora, '%Y-%m-%d') AS FechaEjecucion, DATE_FORMAT(v_ahora, '%H:%i:%s') AS UltimaActualizacion,
           CAST(v_refresco AS SIGNED) AS RefrescoSegundos,
           IF(o.estado_seg = 'finalizado', 1, 0) AS MostrarCierre,
           utec.telefono AS TelefonoTecnico,
           v_pct AS AvancePct, v_eq_ok AS EquiposCompletados, v_eq AS EquiposTotal,
           v_incid AS DemorasIncidencias, v_min_dem AS MinutosDemora, v_motivo AS MotivoDemora, v_alertas AS AlertasActivas,
           v_min_srv AS MinutosServicio,
           v_apr_pend AS AprobacionesPendientes, v_gastos_rev AS GastosPorRevisar
    FROM tmp_sg_os o
    JOIN orden_servicio osr ON osr.id_os = o.id_os
    LEFT JOIN programacion pg ON pg.id_programacion = o.id_programacion
    LEFT JOIN expediente_digital ex ON ex.id_expediente = osr.id_expediente
    LEFT JOIN tabla_maestra ts ON ts.IdEmpresa = 1 AND ts.Descripcion = 'TIPO_SERVICIO' AND ts.Num1 = osr.id_tipo_servicio
    LEFT JOIN tmp_sg_tec tl ON tl.id_usuario = o.id_tecnico
    LEFT JOIN usuario utec ON utec.id_usuario = o.id_tecnico
    WHERE o.id_os = p_id_os;

    -- Equipos a intervenir
    SELECT e.id_equipo AS IdEquipo, e.codigo_tw AS Codigo, e.modelo AS Modelo, e.numero_serie AS Serie, oe.estado_ejecucion AS EstadoEjecucion,
           (SELECT g.etapa FROM os_equipo_etapa g WHERE g.id_os = oe.id_os AND g.id_equipo = oe.id_equipo AND g.eliminado_en IS NULL AND g.inicio_utc IS NOT NULL AND g.fin_utc IS NULL
              ORDER BY g.inicio_utc DESC LIMIT 1) AS EtapaActual,
           DATE_FORMAT(CONVERT_TZ(oe.fecha_ejecucion, '+00:00', '-05:00'), '%H:%i') AS HoraCompletado,
           IF(e.estado_operativo = 'observado', 1, 0) AS Observado
    FROM os_equipo oe JOIN (SELECT ec.id_equipo, ec.codigo_tw, ec.modelo, ec.num_serie AS numero_serie, ec.estado_operativo FROM equipo_cliente ec) e ON e.id_equipo = oe.id_equipo
    WHERE oe.id_os = p_id_os AND oe.eliminado_en IS NULL AND EXISTS (SELECT 1 FROM vw_objetivo_visible vv WHERE vv.id_os_equipo = oe.id)   -- mismos equipos que ve el técnico en la app
    ORDER BY oe.orden, oe.id;

    -- Responsables: líder, apoyo y supervisión técnica
    SELECT x.IdUsuario, x.Nombre, x.Rol, x.Cargo, x.Nota FROM (
        SELECT u.id_usuario AS IdUsuario, TRIM(CONCAT(u.nombre, ' ', u.apellido)) AS Nombre, ut.rol AS Rol, u.cargo AS Cargo,
               (SELECT CONCAT('Reasignado hoy ', DATE_FORMAT(CONVERT_TZ(r.registrado_en, '+00:00', '-05:00'), '%H:%i'), ' por ', IFNULL(TRIM(CONCAT(ur.nombre, ' ', ur.apellido)), 'Operaciones'))
                  FROM expediente_reasignacion r LEFT JOIN usuario ur ON ur.id_usuario = r.registrado_por
                 WHERE r.id_expediente = osr.id_expediente AND r.SoftDelete = 0 AND r.id_responsable_nuevo = u.id_usuario
                   AND DATE(CONVERT_TZ(r.registrado_en, '+00:00', '-05:00')) = DATE(v_ahora) ORDER BY r.registrado_en DESC LIMIT 1) AS Nota,
               IF(ut.rol = 'principal', 0, 1) AS ord
        FROM tmp_sg_ut ut JOIN usuario u ON u.id_usuario = ut.id_usuario JOIN orden_servicio osr ON osr.id_os = ut.id_os
        WHERE ut.id_os = p_id_os
        UNION ALL
        SELECT s.id_usuario, TRIM(CONCAT(s.nombre, ' ', s.apellido)), 'supervisor', s.cargo, NULL, 2
        FROM tmp_sg_os o2 JOIN usuario t ON t.id_usuario = o2.id_tecnico JOIN usuario s ON s.id_usuario = t.id_supervisor
        WHERE o2.id_os = p_id_os
    ) x ORDER BY x.ord, x.Nombre;

    -- Contacto en planta (teléfono y correo solo viajan por este endpoint autorizado)
    SELECT cc.nombres AS Nombre, cc.cargo AS Cargo, cc.telefono_movil AS Telefono, cc.correo AS Correo,
           DATE_FORMAT(o.llegada_dt, '%H:%i') AS ConfirmadoA,
           IF(o.llegada_dt IS NULL, NULL, GREATEST(0, TIMESTAMPDIFF(MINUTE, o.llegada_dt, v_ahora))) AS HaceMinutos
    FROM tmp_sg_os o JOIN orden_servicio osr ON osr.id_os = o.id_os
    JOIN contacto_cliente cc ON cc.id_contacto = osr.id_contacto AND cc.SoftDelete = 0
    WHERE o.id_os = p_id_os;

    CALL SP_LimpiarSeguimientoOperativo();
END$$

DELIMITER ;
