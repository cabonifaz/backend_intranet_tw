-- HU-22: la intranet muestra los mismos equipos que la app (Avance por equipos, detalle y contadores del seguimiento). Ejecutar con Alt+X (No al aviso) y reiniciar la API.
-- ¿El equipo (fila de os_equipo) es un objetivo VISIBLE de su OS? (1 = sí, 0 = no)
-- Misma regla que la lista de objetivos de la app (SP_ArmarObjetivosMovil; si se cambia una, cambiar la otra): se ve si lo registró el técnico en campo
-- (ingresado_en_campo = 1), si la programación vigente de la OS no elige equipos (se trabajan todos) o si está entre los equipos de esa programación.
-- La usan los detalles de la intranet (Avance por equipos, detalle del servicio y contadores del seguimiento) para mostrar los mismos equipos que la app.
DROP FUNCTION IF EXISTS FN_ObjetivoVisible;

DELIMITER $$

CREATE FUNCTION FN_ObjetivoVisible(
    p_id_os_equipo BIGINT
) RETURNS TINYINT
READS SQL DATA
BEGIN
    DECLARE v_id_os     BIGINT DEFAULT NULL;
    DECLARE v_id_equipo BIGINT DEFAULT NULL;
    DECLARE v_campo     TINYINT DEFAULT 0;
    DECLARE v_id_prog   BIGINT DEFAULT NULL;
    DECLARE v_n         INT DEFAULT 0;
    DECLARE v_en        INT DEFAULT 0;

    SELECT oe.id_os, oe.id_equipo, IFNULL(oe.ingresado_en_campo, 0) INTO v_id_os, v_id_equipo, v_campo
    FROM   os_equipo oe WHERE oe.id = p_id_os_equipo;
    IF v_id_os IS NULL THEN RETURN 0; END IF;
    IF v_campo = 1 THEN RETURN 1; END IF;

    SELECT pr.id_programacion INTO v_id_prog
    FROM   programacion pr
    WHERE  pr.id_os = v_id_os AND pr.estado <> 'cancelada' AND pr.eliminado_en IS NULL
    ORDER BY pr.id_programacion DESC LIMIT 1;

    SELECT COUNT(*), IFNULL(SUM(pe.id_equipo = v_id_equipo), 0) INTO v_n, v_en
    FROM   programacion_equipo pe
    WHERE  pe.id_programacion = v_id_prog AND pe.eliminado_en IS NULL;

    RETURN IF(v_n = 0 OR v_en > 0, 1, 0);
END$$

DELIMITER ;

-- HU-52 (Sprint 5) Pestaña "Avance por Equipos": por equipo, mini-checklist Limpieza → Desmontaje → Pruebas → Montaje → Cierre con hora y estado
-- (pendiente | en_curso | completada) y chips de conteo (fotos, ensayos, certificado preliminar, observaciones, mediciones). SOLO LECTURA.
-- Resultados: 1 mensaje · 2 equipos (una fila por equipo) · 3 etapas (una fila por equipo y etapa; las 5 siempre).
-- Fix 06/11: los equipos de la OS son de equipo_cliente (os_equipo.id_equipo), no de la tabla equipo (activos TW).
DROP PROCEDURE IF EXISTS SP_ObtenerAvanceServicioRuta;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerAvanceServicioRuta(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT
)
proc: BEGIN
    DECLARE v_msg   VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_ahora DATETIME;

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
    CALL SP_LimpiarSeguimientoOperativo();
    SET v_ahora = CONVERT_TZ(UTC_TIMESTAMP(), '+00:00', '-05:00');

    SELECT 2 AS IdTipoMensaje, 'OK' AS Mensaje;

    SELECT e.id_equipo AS IdEquipo, e.codigo_tw AS Codigo, e.modelo AS Modelo, e.numero_serie AS Serie, oe.estado_ejecucion AS Estado,
           (SELECT COUNT(*) FROM evidencia_fotografica f WHERE f.id_os = oe.id_os AND f.id_equipo = oe.id_equipo AND f.eliminado_en IS NULL) AS Fotos,
           (SELECT COUNT(DISTINCT mm.id_tipo_prueba) FROM medicion_metrologica mm JOIN orden_metrologia om ON om.id_om = mm.id_om
             WHERE om.id_os = oe.id_os AND mm.id_equipo = oe.id_equipo AND mm.eliminado_en IS NULL AND om.eliminado_en IS NULL) AS Ensayos,
           (SELECT COUNT(*) FROM orden_metrologia om WHERE om.id_os = oe.id_os AND om.eliminado_en IS NULL AND om.estado IN ('pendiente_certificado', 'finalizada')
               AND EXISTS (SELECT 1 FROM medicion_metrologica mm WHERE mm.id_om = om.id_om AND mm.id_equipo = oe.id_equipo AND mm.eliminado_en IS NULL)) AS CertificadoPreliminar,
           (SELECT COUNT(*) FROM os_equipo_observacion b WHERE b.id_os = oe.id_os AND b.id_equipo = oe.id_equipo AND b.eliminado_en IS NULL)
             + IF(NULLIF(oe.observacion_ejecucion, '') IS NULL, 0, 1) AS Observaciones,
           (SELECT COUNT(*) FROM medicion_metrologica mm JOIN orden_metrologia om ON om.id_om = mm.id_om
             WHERE om.id_os = oe.id_os AND mm.id_equipo = oe.id_equipo AND mm.eliminado_en IS NULL AND om.eliminado_en IS NULL) AS Mediciones,
           (SELECT DATE_FORMAT(CONVERT_TZ(MIN(g.inicio_utc), '+00:00', '-05:00'), '%H:%i') FROM os_equipo_etapa g WHERE g.id_os = oe.id_os AND g.id_equipo = oe.id_equipo AND g.eliminado_en IS NULL) AS Iniciado,
           (SELECT DATE_FORMAT(CONVERT_TZ(MAX(g.fin_utc), '+00:00', '-05:00'), '%H:%i') FROM os_equipo_etapa g WHERE g.id_os = oe.id_os AND g.id_equipo = oe.id_equipo AND g.eliminado_en IS NULL
              AND oe.estado_ejecucion = 'ejecutado') AS Finalizado,
           (SELECT IF(MIN(g.inicio_utc) IS NULL, NULL, GREATEST(0, TIMESTAMPDIFF(MINUTE, MIN(g.inicio_utc),
                      IF(oe.estado_ejecucion = 'ejecutado', MAX(g.fin_utc), UTC_TIMESTAMP()))))
              FROM os_equipo_etapa g WHERE g.id_os = oe.id_os AND g.id_equipo = oe.id_equipo AND g.eliminado_en IS NULL) AS Minutos
    FROM os_equipo oe JOIN (SELECT ec.id_equipo, ec.codigo_tw, ec.modelo, ec.num_serie AS numero_serie, ec.estado_operativo FROM equipo_cliente ec) e ON e.id_equipo = oe.id_equipo
    WHERE oe.id_os = p_id_os AND oe.eliminado_en IS NULL AND FN_ObjetivoVisible(oe.id) = 1   -- mismos equipos que ve el técnico en la app
    ORDER BY oe.orden, oe.id;

    SELECT oe.id_equipo AS IdEquipo, s.etapa AS Etapa, s.n AS Orden,
           CASE WHEN g.fin_utc IS NOT NULL THEN 'completada' WHEN g.inicio_utc IS NOT NULL THEN 'en_curso' ELSE 'pendiente' END AS Estado,
           DATE_FORMAT(CONVERT_TZ(COALESCE(g.fin_utc, g.inicio_utc), '+00:00', '-05:00'), '%H:%i') AS Hora
    FROM os_equipo oe
    JOIN (SELECT 1 AS n, 'limpieza' AS etapa UNION ALL SELECT 2, 'desmontaje' UNION ALL SELECT 3, 'pruebas' UNION ALL SELECT 4, 'montaje' UNION ALL SELECT 5, 'cierre') s
    LEFT JOIN os_equipo_etapa g ON g.id_os = oe.id_os AND g.id_equipo = oe.id_equipo AND g.etapa = s.etapa AND g.eliminado_en IS NULL
    WHERE oe.id_os = p_id_os AND oe.eliminado_en IS NULL AND FN_ObjetivoVisible(oe.id) = 1   -- mismos equipos que ve el técnico en la app
    ORDER BY oe.orden, oe.id, s.n;
END$$

DELIMITER ;

-- HU-52 (Sprint 5) Detalle del Servicio en Ruta: cabecera fija, pestaña Resumen y contadores de las pestañas. SOLO LECTURA.
-- Resultados: 1 mensaje · 2 cabecera+programación+métricas (1 fila) · 3 equipos a intervenir · 4 responsables · 5 contacto en planta (0 o 1 fila).
-- Estado del servicio: el mismo de la bandeja (HU-51). "Cierre del Servicio" solo se muestra si el estado es finalizado (campo MostrarCierre).
-- Chips: AprobacionesPendientes (salida, llegada forzada, evidencias forzadas y ensayos con error sin resolver; requiere la migración 113) y
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
         + (SELECT COUNT(*) FROM evidencia_fotografica  WHERE id_os = p_id_os AND override_aprobado = 1 AND vigente = 1
                                                          AND revision_jefe IS NULL AND eliminado_en IS NULL)
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
    WHERE oe.id_os = p_id_os AND oe.eliminado_en IS NULL AND FN_ObjetivoVisible(oe.id) = 1   -- mismos equipos que ve el técnico en la app
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

-- HU-51 (Sprint 5) Arma el estado operativo del DÍA para la bandeja de seguimiento. Ayuda interna: NO devuelve resultados. Solo LEE datos.
-- Los SPs SP_Obtener*Seguimiento la llaman y al terminar ejecutan SP_LimpiarSeguimientoOperativo. "Hoy" y las horas son de Lima (UTC-05:00).
-- Universo: programaciones CONFIRMADAS (Programado) con fecha de ejecución de hoy, cuya OS/OM no esté anulada. La bandeja no escribe nada:
-- lee evento_campo (salida, llegada, inicio, cierre), orden_servicio, os_equipo, demora_registro, incidencia_operativa y ubicacion_tecnico.
-- Estado del servicio (estado_seg), por prioridad:
--   finalizado      OS finalizada
--   con_incidente   incidencia abierta de nivel Crítico o con impacto "detiene"
--   con_demora      demora registrada hoy, incidencia abierta no crítica, o servicio en pausa
--   en_ejecucion    OS en ejecución
--   en_planta       OS en ruta con llegada registrada (aún sin iniciar el trabajo)
--   en_ruta         OS en ruta, sin llegada
--   sin_salir       programada o reprogramada: el técnico aún no marcó "Salida"
-- Estado del técnico = el del servicio más urgente de su día (el finalizado solo si todos lo están).
-- Alertas automáticas (se calculan al consultar; umbrales en PARAMETRO_PROGRAMACION, migración 90):
--   perdida_contacto (crítica) · gps_parado (advertencia) · sin_movimiento (crítica, HU-20) · autorizacion_salida (crítica: el técnico pidió autorización para iniciar el traslado y el encargado aún no responde) · sin_ingreso_post_llegada (advertencia) · sin_iniciar_servicio (advertencia)
--   · proximidad (info) · incidente (crítica)
-- Tablas temporales (MySQL no permite abrir dos veces la misma temporal en una consulta):
--   tmp_sg_cfg (1 fila: hoy, ahora y umbrales) · tmp_sg_os (un servicio por fila) · tmp_sg_ev (eventos de campo del día por OS)
--   tmp_sg_ut (técnico x servicio) · tmp_sg_tec (un técnico por fila) · tmp_sg_pos (última posición GPS por técnico)
--   tmp_sg_alerta · tmp_sg_hito · tmp_sg_inc (demoras e incidencias unificadas; `fase` = momento de la demora de la app: llegada = en ruta, ingreso = ingreso a planta)
-- Demoras de la app (demora_registro, HU-05): las de llegada corren la hora esperada de llegada (hito) y las de ingreso, la hora esperada de inicio.
-- Jornada (HU-20): cada técnico trae su estado del Reloj marcador (jornada: en_labores | en_refrigerio | salio_planta | finalizada; NULL si no inició) y una frase de lo que
-- está haciendo (actividad). «Sin movimiento»: jornada en curso (no en refrigerio ni finalizada), con señal, GPS en el mismo punto SEG_SIN_MOVIMIENTO_MIN o más.
-- Destino y ETA (HU-20): la planta es la sede_cliente de la OS y, si no tiene datos, la del requerimiento (RQ); las coordenadas salen de sede_cliente.latitud/longitud (migración 110),
-- de la tabla sede o, sin ninguna, de la llegada registrada. eta_min / eta_est = estimación EN RUTA: distancia en línea recta × 1,3 (calles) a SEG_VELOCIDAD_PROMEDIO_KMH (30 por defecto); es referencial.
-- Requiere las migraciones 85 a 90 y 109.
DROP PROCEDURE IF EXISTS SP_ArmarSeguimientoOperativo;

DELIMITER $$

CREATE PROCEDURE SP_ArmarSeguimientoOperativo()
BEGIN
    DECLARE v_ahora_utc DATETIME;
    DECLARE v_ahora     DATETIME;
    DECLARE v_hoy       DATE;
    DECLARE v_ini_utc   DATETIME;
    DECLARE v_refresco  DECIMAL(18,6);
    DECLARE v_perdida   DECIMAL(18,6);
    DECLARE v_parado    DECIMAL(18,6);
    DECLARE v_sin_ing   DECIMAL(18,6);
    DECLARE v_sin_ini   DECIMAL(18,6);
    DECLARE v_prox      DECIMAL(18,6);
    DECLARE v_anticip   DECIMAL(18,6);
    DECLARE v_nueva     DECIMAL(18,6);
    DECLARE v_ventana   DECIMAL(18,6);
    DECLARE v_retorno   DECIMAL(18,6);
    DECLARE v_sin_mov   DECIMAL(18,6);
    DECLARE v_vel_prom  DECIMAL(18,6);

    CALL SP_LimpiarSeguimientoOperativo();

    SET v_ahora_utc = UTC_TIMESTAMP();
    SET v_ahora     = CONVERT_TZ(v_ahora_utc, '+00:00', '-05:00');
    SET v_hoy       = DATE(v_ahora);
    SET v_ini_utc   = CONVERT_TZ(TIMESTAMP(v_hoy), '-05:00', '+00:00');

    CALL SP_LeerParametroProgramacion('SEG_REFRESCO_SEGUNDOS',      30,  v_refresco);
    CALL SP_LeerParametroProgramacion('SEG_PERDIDA_CONTACTO_MIN',   10,  v_perdida);
    CALL SP_LeerParametroProgramacion('SEG_GPS_PARADO_MIN',         10,  v_parado);
    CALL SP_LeerParametroProgramacion('SEG_SIN_INGRESO_MIN',        15,  v_sin_ing);
    CALL SP_LeerParametroProgramacion('SEG_SIN_INICIAR_MIN',        15,  v_sin_ini);
    CALL SP_LeerParametroProgramacion('SEG_PROXIMIDAD_METROS',      300, v_prox);
    CALL SP_LeerParametroProgramacion('SEG_ANTICIPACION_SALIDA_MIN', 60, v_anticip);
    CALL SP_LeerParametroProgramacion('SEG_ALERTA_NUEVA_MIN',       15,  v_nueva);
    CALL SP_LeerParametroProgramacion('SEG_HITOS_VENTANA_MIN',      60,  v_ventana);
    CALL SP_LeerParametroProgramacion('SEG_RETORNO_MIN',            30,  v_retorno);
    CALL SP_LeerParametroProgramacion('SEG_SIN_MOVIMIENTO_MIN',     10,  v_sin_mov);
    CALL SP_LeerParametroProgramacion('SEG_VELOCIDAD_PROMEDIO_KMH', 30,  v_vel_prom);

    CREATE TEMPORARY TABLE tmp_sg_cfg (
        hoy DATE, ahora DATETIME, ahora_utc DATETIME, ini_utc DATETIME,
        refresco INT, perdida INT, parado INT, sin_ingreso INT, sin_iniciar INT, prox INT, anticip INT, nueva INT, ventana INT, retorno INT
    );
    INSERT INTO tmp_sg_cfg VALUES (v_hoy, v_ahora, v_ahora_utc, v_ini_utc, v_refresco, v_perdida, v_parado, v_sin_ing, v_sin_ini, v_prox,
                                   v_anticip, v_nueva, v_ventana, v_retorno);

    -- ── Servicios del día ─────────────────────────────────────────────────────────────────
    CREATE TEMPORARY TABLE tmp_sg_os (
        id_os BIGINT NOT NULL, id_programacion BIGINT, numero VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        tipo VARCHAR(5) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, id_cliente BIGINT,
        razon_social VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, ruc VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        id_sede BIGINT, sede_nombre VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        sede_direccion VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, lat_sede DECIMAL(10,7), lon_sede DECIMAL(10,7),
        planta_ubicada TINYINT DEFAULT 0,   -- 1 = lat/lon_sede son de la sede (mapa); 0 = no tiene, o es la llegada registrada del técnico (reemplazo)
        id_tecnico BIGINT, tecnico VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, nombre_pila VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        zona VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        hora_inicio TIME, hora_fin_est TIME, os_estado VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        propuesta VARCHAR(60) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        n_equipos INT DEFAULT 0, n_ejecutados INT DEFAULT 0,
        salida_utc DATETIME, llegada_dt DATETIME, inicio_dt DATETIME, fin_dt DATETIME,
        crit TINYINT DEFAULT 0, n_demoras INT DEFAULT 0, min_dem_lleg INT DEFAULT 0, ing_eta DATETIME,
        estado_seg VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, fase VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, prio INT DEFAULT 9, dist_m INT, eta_min INT, eta_est DATETIME,
        PRIMARY KEY (id_os)
    );

    INSERT INTO tmp_sg_os (id_os, id_programacion, numero, tipo, id_cliente, razon_social, ruc, id_sede, sede_nombre, sede_direccion, lat_sede, lon_sede, planta_ubicada,
                           id_tecnico, tecnico, nombre_pila, zona, hora_inicio, hora_fin_est, os_estado, propuesta, n_equipos, n_ejecutados,
                           llegada_dt, fin_dt)
    SELECT os.id_os, p.id_programacion, os.numero, os.tipo, os.id_cliente, c.razon_social, c.ruc, os.id_sede, COALESCE(NULLIF(sc.nombre, ''), sc2.nombre), COALESCE(NULLIF(sc.direccion_exacta, ''), sc2.direccion_exacta), COALESCE(sc.latitud, s.latitud, sc2.latitud, os.latitud_llegada), COALESCE(sc.longitud, s.longitud, sc2.longitud, os.longitud_llegada),
           IF(COALESCE(sc.latitud, s.latitud, sc2.latitud) IS NOT NULL AND COALESCE(sc.longitud, s.longitud, sc2.longitud) IS NOT NULL, 1, 0),
           p.id_tecnico_principal, TRIM(CONCAT(u.nombre, ' ', u.apellido)), u.nombre, COALESCE(zn.String1, u.sede_operativa),
           p.hora_inicio, p.hora_fin_estimada, os.estado,
           IF(pr.id_propuesta IS NULL, NULL, pr.numero),
           (SELECT COUNT(*) FROM os_equipo e WHERE e.id_os = os.id_os AND e.eliminado_en IS NULL AND FN_ObjetivoVisible(e.id) = 1),
           (SELECT COUNT(*) FROM os_equipo e WHERE e.id_os = os.id_os AND e.eliminado_en IS NULL AND FN_ObjetivoVisible(e.id) = 1 AND e.estado_ejecucion = 'ejecutado'),
           IF(os.hora_llegada_real IS NULL, NULL, TIMESTAMP(v_hoy, os.hora_llegada_real)),
           IF(os.hora_fin_real IS NULL, NULL, TIMESTAMP(v_hoy, os.hora_fin_real))
    FROM programacion p
    JOIN orden_servicio os ON os.id_os = p.id_os AND os.eliminado_en IS NULL
    JOIN cliente c ON c.id_cliente = os.id_cliente
    LEFT JOIN sede_cliente sc ON sc.id_sede = os.id_sede
    LEFT JOIN sede s ON s.id_sede = os.id_sede AND s.id_cliente = os.id_cliente AND s.eliminado_en IS NULL
    LEFT JOIN usuario u ON u.id_usuario = p.id_tecnico_principal
    LEFT JOIN tabla_maestra zn ON zn.IdMaestro = 69 AND zn.IdEmpresa = 1 AND zn.String2 = u.sede_operativa
    LEFT JOIN propuesta_comercial pr ON pr.id_propuesta = os.id_propuesta
    LEFT JOIN requerimiento rq ON rq.id_requerimiento = COALESCE(os.id_requerimiento, pr.id_requerimiento)
    LEFT JOIN sede_cliente sc2 ON sc2.id_sede = rq.id_sede AND sc2.SoftDelete = 0
    WHERE p.eliminado_en IS NULL AND p.estado = 'confirmada' AND p.fecha_ejecucion = v_hoy
      AND os.estado NOT IN ('anulada', 'borrador', 'emitida', 'finalizada');   -- finalizada: ya está en Revisión de Informes (el técnico sigue en el mapa por su jornada)

    -- Eventos de campo de hoy (una fila por OS)
    CREATE TEMPORARY TABLE tmp_sg_ev (id_os BIGINT NOT NULL, salida_utc DATETIME, llegada_utc DATETIME, inicio_utc DATETIME, cierre_utc DATETIME, PRIMARY KEY (id_os));
    INSERT INTO tmp_sg_ev
    SELECT e.id_os,
           MIN(IF(t.String2 = 'SALIDA_BASE',    e.timestamp_utc, NULL)), MIN(IF(t.String2 = 'LLEGADA', e.timestamp_utc, NULL)),
           MIN(IF(t.String2 = 'INICIO_TRABAJO', e.timestamp_utc, NULL)), MAX(IF(t.String2 = 'CIERRE',  e.timestamp_utc, NULL))
    FROM evento_campo e
    JOIN tabla_maestra t ON t.Descripcion = 'TIPO_EVENTO_CAMPO' AND t.IdEmpresa = 1 AND t.Num1 = e.id_tipo_evento
    JOIN tmp_sg_os o ON o.id_os = e.id_os
    WHERE e.eliminado_en IS NULL AND e.timestamp_utc >= v_ini_utc
    GROUP BY e.id_os;

    UPDATE tmp_sg_os o
    JOIN tmp_sg_ev v ON v.id_os = o.id_os
    SET o.salida_utc = v.salida_utc,
        o.llegada_dt = COALESCE(o.llegada_dt, CONVERT_TZ(v.llegada_utc, '+00:00', '-05:00')),
        o.inicio_dt  = CONVERT_TZ(v.inicio_utc, '+00:00', '-05:00'),
        o.fin_dt     = COALESCE(o.fin_dt, CONVERT_TZ(v.cierre_utc, '+00:00', '-05:00'));

    -- Incidencias y demoras de hoy
    UPDATE tmp_sg_os o
    SET o.crit = IF(EXISTS (SELECT 1 FROM incidencia_operativa i
                            LEFT JOIN tabla_maestra nv ON nv.Descripcion = 'NIVEL_ALERTA' AND nv.IdEmpresa = 1 AND nv.Num1 = i.id_nivel_alerta
                            WHERE i.id_os = o.id_os AND i.eliminado_en IS NULL AND i.estado <> 'resuelta' AND i.fecha_registro >= v_hoy
                              AND (i.impacto = 'detiene' OR nv.String3 = 'CRITICO'))
                    OR EXISTS (SELECT 1 FROM registro_asistente ra
                               WHERE ra.id_os = o.id_os AND ra.modo = 'demora' AND ra.impacto = 'detiene' AND ra.fecha_utc >= v_ini_utc), 1, 0),
        o.n_demoras = (SELECT COUNT(*) FROM demora_registro d WHERE d.id_os = o.id_os AND d.eliminado_en IS NULL AND d.fecha_registro >= v_hoy)
                    + (SELECT COUNT(*) FROM incidencia_operativa i WHERE i.id_os = o.id_os AND i.eliminado_en IS NULL AND i.estado <> 'resuelta'
                         AND i.fecha_registro >= v_hoy)
                    + (SELECT COUNT(*) FROM registro_asistente ra WHERE ra.id_os = o.id_os AND ra.modo = 'demora' AND ra.fecha_utc >= v_ini_utc);

    -- Demoras de la app de hoy: minutos acumulados en ruta y hora de inicio recalculada tras una demora de ingreso a planta
    UPDATE tmp_sg_os o
    SET o.min_dem_lleg = IFNULL((SELECT SUM(d.duracion_minutos) FROM demora_registro d
                                 WHERE d.id_os = o.id_os AND d.tipo = 'llegada' AND d.eliminado_en IS NULL AND d.fecha_registro >= v_hoy), 0),
        o.ing_eta      = (SELECT MAX(d.eta_recalculada) FROM demora_registro d
                          WHERE d.id_os = o.id_os AND d.tipo = 'ingreso' AND d.eliminado_en IS NULL AND d.fecha_registro >= v_hoy);

    UPDATE tmp_sg_os o
    SET o.estado_seg = CASE
            WHEN o.os_estado = 'finalizada'                             THEN 'finalizado'
            WHEN o.crit = 1                                             THEN 'con_incidente'
            WHEN o.n_demoras > 0 OR o.os_estado = 'pausada'             THEN 'con_demora'
            WHEN o.os_estado = 'en_ejecucion'                           THEN 'en_ejecucion'
            WHEN o.os_estado = 'en_ruta' AND o.llegada_dt IS NOT NULL   THEN 'en_planta'
            WHEN o.os_estado = 'en_ruta'                                THEN 'en_ruta'
            ELSE 'sin_salir' END;
    -- Fase del servicio según la OS (sin tener en cuenta demoras ni incidentes): se usa para alertas e hitos
    UPDATE tmp_sg_os o
    SET o.fase = CASE WHEN o.os_estado = 'finalizada' THEN 'finalizado' WHEN o.os_estado IN ('en_ejecucion', 'pausada') THEN 'en_ejecucion'
                      WHEN o.os_estado = 'en_ruta' AND o.llegada_dt IS NOT NULL THEN 'en_planta' WHEN o.os_estado = 'en_ruta' THEN 'en_ruta'
                      ELSE 'sin_salir' END;
    UPDATE tmp_sg_os o
    SET o.prio = CASE o.estado_seg WHEN 'con_incidente' THEN 1 WHEN 'con_demora' THEN 2 WHEN 'en_ejecucion' THEN 3 WHEN 'en_planta' THEN 4
                                   WHEN 'en_ruta' THEN 5 WHEN 'sin_salir' THEN 6 ELSE 7 END;

    -- ── Técnicos del día (principal y apoyo) ──────────────────────────────────────────────
    CREATE TEMPORARY TABLE tmp_sg_ut (id_usuario BIGINT NOT NULL, id_os BIGINT NOT NULL, rol VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, PRIMARY KEY (id_usuario, id_os));
    INSERT IGNORE INTO tmp_sg_ut
    SELECT pt.id_usuario, o.id_os, pt.rol
    FROM programacion_tecnico pt JOIN tmp_sg_os o ON o.id_programacion = pt.id_programacion
    WHERE pt.eliminado_en IS NULL;
    INSERT IGNORE INTO tmp_sg_ut SELECT o.id_tecnico, o.id_os, 'principal' FROM tmp_sg_os o WHERE o.id_tecnico IS NOT NULL;

    -- Copia (id_os, nombre) para la búsqueda por técnico: MySQL no abre dos veces la misma temporal en una consulta
    CREATE TEMPORARY TABLE tmp_sg_utn (id_os BIGINT NOT NULL, id_usuario BIGINT NOT NULL, nombre VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, KEY ix_utn (id_os));
    INSERT INTO tmp_sg_utn SELECT ut.id_os, ut.id_usuario, TRIM(CONCAT(u.nombre, ' ', u.apellido)) FROM tmp_sg_ut ut JOIN usuario u ON u.id_usuario = ut.id_usuario;

    CREATE TEMPORARY TABLE tmp_sg_tec (
        id_usuario BIGINT NOT NULL, nombre VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, nombre_pila VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        iniciales VARCHAR(4) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, cargo VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        zona VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, ssoma VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        prio INT, estado_seg VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, id_os_actual BIGINT,
        n_servicios INT, n_completados INT, n_en_curso INT,
        salida_utc DATETIME, salida_prog TIME, dist_m INT,
        jornada VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, jornada_n INT DEFAULT 0, jornada_desde DATETIME, actividad VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        actividad_tono VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, actividad_color CHAR(7) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        PRIMARY KEY (id_usuario)
    );
    INSERT INTO tmp_sg_tec (id_usuario, nombre, nombre_pila, iniciales, cargo, zona, prio, n_servicios, n_completados, n_en_curso, salida_utc, salida_prog)
    SELECT ut.id_usuario, TRIM(CONCAT(u.nombre, ' ', u.apellido)), u.nombre, UPPER(CONCAT(LEFT(u.nombre, 1), LEFT(u.apellido, 1))),
           COALESCE(cg.String1, u.cargo), COALESCE(zn.String1, u.sede_operativa),
           MIN(o.prio), COUNT(*), SUM(o.estado_seg = 'finalizado'),
           SUM(o.estado_seg IN ('en_ruta', 'en_planta', 'en_ejecucion', 'con_demora', 'con_incidente')),
           MIN(o.salida_utc), SEC_TO_TIME(GREATEST(0, TIME_TO_SEC(MIN(o.hora_inicio)) - v_anticip * 60))
    FROM tmp_sg_ut ut
    JOIN tmp_sg_os o ON o.id_os = ut.id_os
    JOIN usuario u ON u.id_usuario = ut.id_usuario
    LEFT JOIN tabla_maestra cg ON cg.IdMaestro = 80 AND cg.IdEmpresa = 1 AND cg.String2 = u.cargo
    LEFT JOIN tabla_maestra zn ON zn.IdMaestro = 69 AND zn.IdEmpresa = 1 AND zn.String2 = u.sede_operativa
    GROUP BY ut.id_usuario, u.nombre, u.apellido, cg.String1, u.cargo, zn.String1, u.sede_operativa;

    UPDATE tmp_sg_tec t
    SET t.estado_seg = CASE t.prio WHEN 1 THEN 'con_incidente' WHEN 2 THEN 'con_demora' WHEN 3 THEN 'en_ejecucion' WHEN 4 THEN 'en_planta'
                                   WHEN 5 THEN 'en_ruta' WHEN 6 THEN 'sin_salir' ELSE 'finalizado' END,
        t.id_os_actual = (SELECT o.id_os FROM tmp_sg_ut ut JOIN tmp_sg_os o ON o.id_os = ut.id_os
                          WHERE ut.id_usuario = t.id_usuario AND o.prio = t.prio ORDER BY o.hora_inicio, o.id_os LIMIT 1);
    UPDATE tmp_sg_tec t
    SET t.ssoma = (SELECT pt.estado_ssoma FROM programacion_tecnico pt JOIN tmp_sg_os o2 ON o2.id_programacion = pt.id_programacion
                   WHERE pt.id_usuario = t.id_usuario AND pt.eliminado_en IS NULL
                   ORDER BY FIELD(pt.estado_ssoma, 'bloqueado', 'incompleto', 'por_vencer', 'conforme') LIMIT 1);

    -- HU-20: técnicos con la jornada iniciada hoy que no tienen servicio programado: también salen en el mapa y en la lista (sin servicios; estado «sin salir»,
    -- lo que hacen lo dice «actividad»). Los que ya están por tener servicio no se repiten (clave primaria).
    INSERT IGNORE INTO tmp_sg_tec (id_usuario, nombre, nombre_pila, iniciales, cargo, zona, prio, estado_seg, n_servicios, n_completados, n_en_curso)
    SELECT u.id_usuario, TRIM(CONCAT(u.nombre, ' ', u.apellido)), u.nombre, UPPER(CONCAT(LEFT(u.nombre, 1), LEFT(u.apellido, 1))),
           COALESCE(cg.String1, u.cargo), COALESCE(zn.String1, u.sede_operativa), 6, 'sin_salir', 0, 0, 0
    FROM usuario u
    LEFT JOIN tabla_maestra cg ON cg.IdMaestro = 80 AND cg.IdEmpresa = 1 AND cg.String2 = u.cargo
    LEFT JOIN tabla_maestra zn ON zn.IdMaestro = 69 AND zn.IdEmpresa = 1 AND zn.String2 = u.sede_operativa
    WHERE u.eliminado_en IS NULL
      AND EXISTS (SELECT 1 FROM jornada_marcacion j WHERE j.id_usuario = u.id_usuario AND j.fecha = v_hoy);

    -- ── Última posición GPS de hoy (ubicacion_tecnico; si no hay, la última de evento_campo con coordenadas) ─────────────
    CREATE TEMPORARY TABLE tmp_sg_pos (
        id_usuario BIGINT NOT NULL, lat DECIMAL(10,7), lon DECIMAL(10,7), direccion VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        ts_utc DATETIME, parado_desde DATETIME, PRIMARY KEY (id_usuario)
    );
    INSERT IGNORE INTO tmp_sg_pos (id_usuario, lat, lon, direccion, ts_utc)
    SELECT x.id_usuario, x.latitud, x.longitud, x.direccion, x.timestamp_utc
    FROM ubicacion_tecnico x
    WHERE x.id_usuario IN (SELECT t.id_usuario FROM tmp_sg_tec t)
      AND x.id_ubicacion = (SELECT MAX(y.id_ubicacion) FROM ubicacion_tecnico y
                            WHERE y.id_usuario = x.id_usuario
                              AND y.timestamp_utc = (SELECT MAX(z.timestamp_utc) FROM ubicacion_tecnico z
                                                     WHERE z.id_usuario = x.id_usuario AND z.timestamp_utc >= v_ini_utc AND z.timestamp_utc <= v_ahora_utc));
    INSERT IGNORE INTO tmp_sg_pos (id_usuario, lat, lon, direccion, ts_utc)
    SELECT e.id_usuario, e.latitud, e.longitud, NULL, e.timestamp_utc
    FROM evento_campo e
    WHERE e.eliminado_en IS NULL AND e.latitud IS NOT NULL AND e.longitud IS NOT NULL AND e.timestamp_utc >= v_ini_utc AND e.timestamp_utc <= v_ahora_utc
      AND e.id_usuario IN (SELECT t.id_usuario FROM tmp_sg_tec t)
      AND e.id_evento = (SELECT MAX(w.id_evento) FROM evento_campo w WHERE w.id_usuario = e.id_usuario AND w.latitud IS NOT NULL AND w.timestamp_utc >= v_ini_utc
                         AND w.timestamp_utc <= v_ahora_utc AND w.eliminado_en IS NULL);

    -- Desde cuándo está el GPS en el mismo punto (~33 m): primera posición posterior a la última que quedó lejos
    UPDATE tmp_sg_pos p
    SET p.parado_desde = (SELECT MIN(a.timestamp_utc) FROM ubicacion_tecnico a
                          WHERE a.id_usuario = p.id_usuario AND a.timestamp_utc >= v_ini_utc AND a.timestamp_utc <= p.ts_utc
                            AND a.timestamp_utc > COALESCE((SELECT MAX(b.timestamp_utc) FROM ubicacion_tecnico b
                                                            WHERE b.id_usuario = p.id_usuario AND b.timestamp_utc >= v_ini_utc AND b.timestamp_utc <= p.ts_utc
                                                              AND (ABS(b.latitud - p.lat) > 0.0003 OR ABS(b.longitud - p.lon) > 0.0003)), '1000-01-01'));

    -- Jornada del técnico (HU-20): estado del Reloj marcador de hoy (la misma tabla de estados de SP_EstadoJornadaMovil) y lo que está haciendo.
    -- jornada_n = marcaciones de hoy (1 inicio · 2 refrigerio · 3 volvió del refrigerio · 4 salida de planta · 5 fin).
    UPDATE tmp_sg_tec t
    SET t.jornada_n = (SELECT COUNT(*) FROM jornada_marcacion j WHERE j.id_usuario = t.id_usuario AND j.fecha = v_hoy),
        t.jornada_desde = (SELECT MAX(j.marcado_utc) FROM jornada_marcacion j WHERE j.id_usuario = t.id_usuario AND j.fecha = v_hoy);
    UPDATE tmp_sg_tec t
    SET t.jornada = CASE t.jornada_n WHEN 0 THEN NULL WHEN 1 THEN 'en_labores' WHEN 2 THEN 'en_refrigerio' WHEN 3 THEN 'en_labores'
                                     WHEN 4 THEN 'salio_planta' ELSE 'finalizada' END;
    -- Actividad (texto) y actividad_tono / actividad_color (para diferenciar por colores a simple vista):
    --   trabajo (verde) ejecutando un equipo · planta (turquesa) en planta sin iniciar · ruta (azul) · refrigerio (ámbar) comiendo/descansando (fuera de sus responsabilidades) ·
    --   refrigerio_fin (lima) acaba de volver de comer (menos de 15 min) · salida_planta (morado) · finalizada (gris) · sin_iniciar (gris claro) · demora (naranja) · incidente (rojo)
    UPDATE tmp_sg_tec t
    LEFT JOIN tmp_sg_os o ON o.id_os = t.id_os_actual
    SET t.actividad = LEFT(CASE
            WHEN t.jornada = 'en_refrigerio' THEN CONCAT('En refrigerio (almuerzo/descanso) desde las ', TIME_FORMAT(CONVERT_TZ(t.jornada_desde, '+00:00', '-05:00'), '%H:%i'),
                 ' · hace ', TIMESTAMPDIFF(MINUTE, t.jornada_desde, v_ahora_utc), ' min · fuera de sus labores')
            WHEN t.jornada = 'salio_planta' THEN CONCAT('Salió de planta hace ', TIMESTAMPDIFF(MINUTE, t.jornada_desde, v_ahora_utc), ' min (',
                 TIME_FORMAT(CONVERT_TZ(t.jornada_desde, '+00:00', '-05:00'), '%H:%i'), ')', IF(o.id_os IS NULL, '', CONCAT(' · servicio ', o.numero)))
            WHEN t.jornada = 'finalizada' THEN CONCAT('Jornada finalizada a las ', TIME_FORMAT(CONVERT_TZ(t.jornada_desde, '+00:00', '-05:00'), '%H:%i'))
            WHEN t.jornada = 'en_labores' THEN CONCAT(
                 IF(t.jornada_n = 3, CONCAT('Volvió del refrigerio hace ', TIMESTAMPDIFF(MINUTE, t.jornada_desde, v_ahora_utc), ' min · '), 'En labores · '),
                 CASE o.fase WHEN 'en_ruta'      THEN CONCAT('en ruta a ', o.razon_social, IF(o.eta_min IS NULL, '', CONCAT(' · llega en ~', o.eta_min, ' min')), ' · ', o.numero)
                             WHEN 'en_planta'    THEN CONCAT('en planta de ', o.razon_social, IF(o.llegada_dt IS NULL, '', CONCAT(' desde hace ', TIMESTAMPDIFF(MINUTE, o.llegada_dt, v_ahora), ' min')), ' · ', o.numero)
                             WHEN 'en_ejecucion' THEN CONCAT('ejecutando ', o.numero, ' en ', o.razon_social, ' · ', o.n_ejecutados, ' de ', o.n_equipos, ' equipos',
                                                             IFNULL((SELECT CONCAT(' · trabajando en ', COALESCE(NULLIF(ec.codigo_cliente, ''), ec.codigo_tw))
                                                                     FROM os_equipo oe JOIN equipo_cliente ec ON ec.id_equipo = oe.id_equipo
                                                                     WHERE oe.id_os = o.id_os AND oe.eliminado_en IS NULL AND oe.estado_ejecucion = 'en_proceso' AND oe.pausado = 0
                                                                     ORDER BY oe.id LIMIT 1), ''))
                             WHEN 'finalizado'   THEN CONCAT('servicio ', o.numero, ' finalizado · ', o.n_ejecutados, ' de ', o.n_equipos, ' equipos')
                             WHEN 'sin_salir'    THEN CONCAT('aún en base · servicio ', o.numero, ' programado ', IFNULL(TIME_FORMAT(o.hora_inicio, '%H:%i'), ''))
                             ELSE 'sin servicio asignado hoy' END,
                 IF(t.estado_seg = 'con_incidente', ' · CON INCIDENTE', IF(t.estado_seg = 'con_demora', ' · con demora', '')))
            ELSE CASE o.fase WHEN 'en_ruta' THEN CONCAT('En ruta a ', o.razon_social, ' (sin marcar el Reloj) · ', o.numero) ELSE 'Jornada sin iniciar (no marcó el Reloj)' END
        END, 250),
        t.actividad_tono = CASE
            WHEN t.jornada = 'en_refrigerio' THEN 'refrigerio'
            WHEN t.jornada = 'salio_planta' AND o.fase = 'en_ejecucion' THEN 'trabajo'
            WHEN t.jornada = 'salio_planta'  THEN 'activo'
            WHEN t.jornada = 'finalizada'    THEN 'finalizada'
            WHEN t.estado_seg = 'con_incidente' THEN 'incidente'
            WHEN t.estado_seg = 'con_demora'    THEN 'demora'
            WHEN t.jornada = 'en_labores' AND t.jornada_n = 3 AND TIMESTAMPDIFF(MINUTE, t.jornada_desde, v_ahora_utc) < 15 THEN 'refrigerio_fin'
            WHEN o.fase = 'en_ejecucion' THEN 'trabajo'
            WHEN o.fase = 'en_planta'    THEN 'planta'
            WHEN o.fase = 'en_ruta'      THEN 'ruta'
            WHEN t.jornada = 'en_labores' THEN 'activo'
            ELSE 'sin_iniciar' END;
    UPDATE tmp_sg_tec t
    SET t.actividad_color = CASE t.actividad_tono
            WHEN 'trabajo' THEN '#EAB308' WHEN 'activo' THEN '#16A34A' WHEN 'planta' THEN '#14B8A6' WHEN 'ruta' THEN '#2563EB' WHEN 'refrigerio' THEN '#F97316' WHEN 'refrigerio_fin' THEN '#84CC16'
            WHEN 'salida_planta' THEN '#7C3AED' WHEN 'finalizada' THEN '#64748B' WHEN 'demora' THEN '#EA580C' WHEN 'incidente' THEN '#DC2626' ELSE '#94A3B8' END;

    -- Distancia (m) al cliente: técnico principal de cada servicio y técnico (servicio actual)
    UPDATE tmp_sg_os o
    JOIN tmp_sg_pos p ON p.id_usuario = o.id_tecnico
    SET o.dist_m = IF(o.lat_sede IS NULL OR o.lon_sede IS NULL, NULL,
        ROUND(6371000 * 2 * ASIN(SQRT(POW(SIN(RADIANS(o.lat_sede - p.lat) / 2), 2)
                       + COS(RADIANS(p.lat)) * COS(RADIANS(o.lat_sede)) * POW(SIN(RADIANS(o.lon_sede - p.lon) / 2), 2)))));
    UPDATE tmp_sg_tec t
    JOIN tmp_sg_os o ON o.id_os = t.id_os_actual
    JOIN tmp_sg_pos p ON p.id_usuario = t.id_usuario
    SET t.dist_m = IF(o.lat_sede IS NULL OR o.lon_sede IS NULL, NULL,
        ROUND(6371000 * 2 * ASIN(SQRT(POW(SIN(RADIANS(o.lat_sede - p.lat) / 2), 2)
                       + COS(RADIANS(p.lat)) * COS(RADIANS(o.lat_sede)) * POW(SIN(RADIANS(o.lon_sede - p.lon) / 2), 2)))));

    -- ETA estimada en ruta (HU-20): línea recta × 1,3 a la velocidad promedio (mínimo 5 km/h); al menos 1 minuto
    UPDATE tmp_sg_os o
    SET o.eta_min = GREATEST(1, CEIL(o.dist_m * 1.3 / 1000 / GREATEST(v_vel_prom, 5) * 60))
    WHERE o.fase = 'en_ruta' AND o.dist_m IS NOT NULL;
    UPDATE tmp_sg_os o SET o.eta_est = DATE_ADD(v_ahora, INTERVAL o.eta_min MINUTE) WHERE o.eta_min IS NOT NULL;

    -- ── Alertas automáticas ───────────────────────────────────────────────────────────────
    CREATE TEMPORARY TABLE tmp_sg_alerta (
        clave VARCHAR(60) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, tipo VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        severidad VARCHAR(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, titulo VARCHAR(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        detalle VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, minutos INT, id_usuario BIGINT,
        tecnico VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, id_os BIGINT, numero VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        PRIMARY KEY (clave)
    );

    -- Pérdida de contacto: servicio en curso y sin señal (o sin ninguna posición desde la salida) por más del umbral
    INSERT INTO tmp_sg_alerta
    SELECT CONCAT('perdida_contacto:', t.id_usuario, ':', o.id_os), 'perdida_contacto', 'critica', 'Pérdida de contacto',
           CONCAT(t.nombre, ' · ', o.numero), TIMESTAMPDIFF(MINUTE, COALESCE(p.ts_utc, t.salida_utc), v_ahora_utc), t.id_usuario, t.nombre, o.id_os, o.numero
    FROM tmp_sg_tec t
    JOIN tmp_sg_os o ON o.id_os = t.id_os_actual
    LEFT JOIN tmp_sg_pos p ON p.id_usuario = t.id_usuario
    WHERE t.estado_seg IN ('en_ruta', 'en_planta', 'en_ejecucion', 'con_demora', 'con_incidente')
      AND COALESCE(p.ts_utc, t.salida_utc) IS NOT NULL
      AND TIMESTAMPDIFF(MINUTE, COALESCE(p.ts_utc, t.salida_utc), v_ahora_utc) > v_perdida;

    -- GPS parado: en ruta, con señal reciente, en el mismo punto por el umbral o más
    INSERT INTO tmp_sg_alerta
    SELECT CONCAT('gps_parado:', t.id_usuario, ':', o.id_os), 'gps_parado', 'advertencia', 'GPS parado',
           CONCAT(t.nombre, ' · ', o.numero), TIMESTAMPDIFF(MINUTE, p.parado_desde, v_ahora_utc), t.id_usuario, t.nombre, o.id_os, o.numero
    FROM tmp_sg_tec t
    JOIN tmp_sg_os o ON o.id_os = t.id_os_actual
    JOIN tmp_sg_pos p ON p.id_usuario = t.id_usuario
    WHERE o.fase = 'en_ruta' AND p.parado_desde IS NOT NULL
      AND TIMESTAMPDIFF(MINUTE, p.ts_utc, v_ahora_utc) <= v_perdida
      AND TIMESTAMPDIFF(MINUTE, p.parado_desde, p.ts_utc) >= v_parado;

    -- Sin movimiento (HU-20): jornada en curso (no en refrigerio ni finalizada), con señal reciente y el GPS en el mismo punto por el umbral o más.
    -- El tiempo sin movimiento se cuenta desde el último «Inicio de labores» o «Fin de refrigerio» (no desde antes de marcar). Severidad crítica (aparece en «Alertas críticas»). En ruta lo cubre «GPS parado»; con el servicio ya finalizado o con el trabajo en ejecución no se alerta. Se asocia al servicio del día del técnico (la notificación lo exige).
    INSERT INTO tmp_sg_alerta
    SELECT CONCAT('sin_movimiento:', t.id_usuario, ':', o.id_os), 'sin_movimiento', 'critica', 'Técnico sin movimiento',
           CONCAT(t.nombre, ' · ', o.numero), TIMESTAMPDIFF(MINUTE, GREATEST(p.parado_desde, jd.desde_utc), v_ahora_utc), t.id_usuario, t.nombre, o.id_os, o.numero
    FROM tmp_sg_tec t
    JOIN tmp_sg_os o ON o.id_os = t.id_os_actual
    JOIN tmp_sg_pos p ON p.id_usuario = t.id_usuario
    JOIN (SELECT j.id_usuario, MAX(j.marcado_utc) AS desde_utc
          FROM   jornada_marcacion j
          WHERE  j.fecha = v_hoy AND j.tipo IN ('inicio_labores', 'fin_refrigerio')
          GROUP BY j.id_usuario) jd ON jd.id_usuario = t.id_usuario
    WHERE t.jornada IN ('en_labores', 'salio_planta') AND o.fase NOT IN ('en_ruta', 'en_ejecucion', 'finalizado') AND p.parado_desde IS NOT NULL
      AND TIMESTAMPDIFF(MINUTE, p.ts_utc, v_ahora_utc) <= v_perdida
      AND TIMESTAMPDIFF(MINUTE, GREATEST(p.parado_desde, jd.desde_utc), p.ts_utc) >= v_sin_mov;

    -- Autorización de salida pendiente: el técnico pidió el visto bueno para iniciar el traslado y el encargado aún no responde (crítica: sale en «Alertas críticas»)
    INSERT INTO tmp_sg_alerta
    SELECT CONCAT('autorizacion_salida:', a.id_tecnico, ':', o.id_os), 'autorizacion_salida', 'critica', 'Autorización de salida pendiente',
           CONCAT(t.nombre, ' · ', o.numero), GREATEST(0, TIMESTAMPDIFF(MINUTE, a.solicitado_en, NOW())), t.id_usuario, t.nombre, o.id_os, o.numero
    FROM tmp_sg_os o
    JOIN tmp_sg_tec t ON t.id_usuario = o.id_tecnico
    JOIN autorizacion_salida_os a ON a.id_os = o.id_os AND a.estado = 'pendiente'
    WHERE o.fase = 'sin_salir';

    -- Sin ingreso post-llegada: llegó a planta y no inicia el trabajo
    INSERT INTO tmp_sg_alerta
    SELECT CONCAT('sin_ingreso:', t.id_usuario, ':', o.id_os), 'sin_ingreso_post_llegada', 'advertencia', 'Sin ingreso post-llegada',
           CONCAT(t.nombre, ' · ', o.numero), TIMESTAMPDIFF(MINUTE, o.llegada_dt, v_ahora), t.id_usuario, t.nombre, o.id_os, o.numero
    FROM tmp_sg_tec t
    JOIN tmp_sg_os o ON o.id_os = t.id_os_actual
    WHERE o.fase = 'en_planta' AND o.llegada_dt IS NOT NULL AND TIMESTAMPDIFF(MINUTE, o.llegada_dt, v_ahora) >= v_sin_ing;

    -- Sin iniciar servicio: pasó la hora de salida programada (más la tolerancia) y no marcó "Salida"
    INSERT INTO tmp_sg_alerta
    SELECT CONCAT('sin_iniciar:', t.id_usuario, ':', o.id_os), 'sin_iniciar_servicio', 'advertencia', 'Sin iniciar servicio',
           CONCAT(t.nombre, ' · ', o.numero),
           TIMESTAMPDIFF(MINUTE, TIMESTAMP(v_hoy, SEC_TO_TIME(GREATEST(0, TIME_TO_SEC(o.hora_inicio) - v_anticip * 60))), v_ahora),
           t.id_usuario, t.nombre, o.id_os, o.numero
    FROM tmp_sg_tec t
    JOIN tmp_sg_os o ON o.id_os = t.id_os_actual
    WHERE o.fase = 'sin_salir' AND o.hora_inicio IS NOT NULL
      AND TIMESTAMPDIFF(MINUTE, TIMESTAMP(v_hoy, SEC_TO_TIME(GREATEST(0, TIME_TO_SEC(o.hora_inicio) - v_anticip * 60))), v_ahora) >= v_sin_ini;

    -- Proximidad: en ruta, con señal reciente y a menos de N metros del cliente
    INSERT INTO tmp_sg_alerta
    SELECT CONCAT('proximidad:', t.id_usuario, ':', o.id_os), 'proximidad', 'info', CONCAT('Proximidad (a ', CAST(v_prox AS UNSIGNED), 'm)'),
           CONCAT(t.nombre, ' · ', o.numero), TIMESTAMPDIFF(MINUTE, p.ts_utc, v_ahora_utc), t.id_usuario, t.nombre, o.id_os, o.numero
    FROM tmp_sg_tec t
    JOIN tmp_sg_os o ON o.id_os = t.id_os_actual
    JOIN tmp_sg_pos p ON p.id_usuario = t.id_usuario
    WHERE o.fase = 'en_ruta' AND t.dist_m IS NOT NULL AND t.dist_m <= v_prox AND TIMESTAMPDIFF(MINUTE, p.ts_utc, v_ahora_utc) <= v_perdida;

    -- Incidente crítico abierto (o que detiene el servicio)
    INSERT INTO tmp_sg_alerta
    SELECT CONCAT('incidente:', i.id_incidencia), 'incidente', 'critica', 'Incidente crítico',
           CONCAT(TRIM(CONCAT(u.nombre, ' ', u.apellido)), ' · ', o.numero),
           GREATEST(0, TIMESTAMPDIFF(MINUTE, i.fecha_registro, v_ahora)), i.id_usuario, TRIM(CONCAT(u.nombre, ' ', u.apellido)), o.id_os, o.numero
    FROM incidencia_operativa i
    JOIN tmp_sg_os o ON o.id_os = i.id_os
    JOIN usuario u ON u.id_usuario = i.id_usuario
    LEFT JOIN tabla_maestra nv ON nv.Descripcion = 'NIVEL_ALERTA' AND nv.IdEmpresa = 1 AND nv.Num1 = i.id_nivel_alerta
    WHERE i.eliminado_en IS NULL AND i.estado <> 'resuelta' AND i.fecha_registro >= v_hoy AND o.estado_seg <> 'finalizado'
      AND (i.impacto = 'detiene' OR nv.String3 = 'CRITICO');

    -- ── Próximos hitos esperados ──────────────────────────────────────────────────────────
    CREATE TEMPORARY TABLE tmp_sg_hito (
        id_os BIGINT, numero VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, tipo VARCHAR(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        esperado DATETIME, texto VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, detalle VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        id_tecnico BIGINT, PRIMARY KEY (id_os)
    );
    INSERT INTO tmp_sg_hito
    SELECT o.id_os, o.numero,
           CASE o.fase WHEN 'sin_salir' THEN 'salida' WHEN 'en_ruta' THEN 'llegada' WHEN 'en_planta' THEN 'inicio'
                             WHEN 'finalizado' THEN 'retorno' ELSE 'termino' END,
           CASE o.fase
               WHEN 'sin_salir'  THEN TIMESTAMP(v_hoy, SEC_TO_TIME(GREATEST(0, TIME_TO_SEC(o.hora_inicio) - v_anticip * 60)))
               WHEN 'en_ruta'    THEN DATE_ADD(TIMESTAMP(v_hoy, o.hora_inicio), INTERVAL o.min_dem_lleg MINUTE)
               WHEN 'en_planta'  THEN GREATEST(TIMESTAMP(v_hoy, o.hora_inicio), o.llegada_dt, COALESCE(o.ing_eta, o.llegada_dt))
               WHEN 'finalizado' THEN DATE_ADD(COALESCE(o.fin_dt, TIMESTAMP(v_hoy, o.hora_fin_est)), INTERVAL v_retorno MINUTE)
               ELSE TIMESTAMP(v_hoy, COALESCE(o.hora_fin_est, o.hora_inicio)) END,
           CASE o.fase
               WHEN 'sin_salir'  THEN CONCAT(o.nombre_pila, ' debería salir de base hacia ', o.razon_social)
               WHEN 'en_ruta'    THEN CONCAT(o.nombre_pila, ' debería llegar a ', o.razon_social)
               WHEN 'en_planta'  THEN CONCAT(o.nombre_pila, ' debería iniciar el servicio en ', o.razon_social)
               WHEN 'finalizado' THEN CONCAT(o.nombre_pila, ' debería iniciar el retorno a Total Weight')
               ELSE CONCAT(o.nombre_pila, ' debería terminar el servicio en ', o.razon_social) END,
           CONCAT(CASE o.fase
                      WHEN 'sin_salir'  THEN 'Sin salir aún'
                      WHEN 'en_ruta'    THEN CONCAT('En ruta', IF(o.dist_m IS NULL, '', CONCAT(' · a ', FORMAT(o.dist_m / 1000, 1), ' km')),
                                                   IF(o.min_dem_lleg > 0, CONCAT(' · con demora (+', o.min_dem_lleg, ' min)'), ''))
                      WHEN 'en_planta'  THEN CONCAT('En planta', IF(o.llegada_dt IS NULL, '', CONCAT(' · llegó hace ', TIMESTAMPDIFF(MINUTE, o.llegada_dt, v_ahora), ' min')),
                                                   IF(o.ing_eta IS NULL, '', ' · con demora en el ingreso'))
                      WHEN 'finalizado' THEN CONCAT('Finalizó servicio', IF(o.fin_dt IS NULL, '', CONCAT(' hace ', TIMESTAMPDIFF(MINUTE, o.fin_dt, v_ahora), ' min')))
                                            ELSE 'En ejecución' END, ' · ', o.numero),
           o.id_tecnico
    FROM tmp_sg_os o
    WHERE o.hora_inicio IS NOT NULL;

    -- ── Demoras e incidencias del día (unificadas) ────────────────────────────────────────
    CREATE TEMPORARY TABLE tmp_sg_inc (
        clave VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, fecha DATETIME, id_usuario BIGINT,
        tecnico VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, iniciales VARCHAR(4) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        id_os BIGINT, numero VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, cliente VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        tipo_codigo VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, tipo VARCHAR(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        descripcion VARCHAR(400) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, duracion_min INT, impacto VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        origen VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, fase VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, PRIMARY KEY (clave)
    );
    INSERT INTO tmp_sg_inc
    SELECT CONCAT('d', d.id_demora), d.fecha_registro, d.id_usuario, TRIM(CONCAT(u.nombre, ' ', u.apellido)), UPPER(CONCAT(LEFT(u.nombre, 1), LEFT(u.apellido, 1))),
           d.id_os, os.numero, c.razon_social, COALESCE(m.String2, 'OTRO'), COALESCE(m.String1, 'Demora'), LEFT(IFNULL(d.descripcion, ''), 400),
           d.duracion_minutos, d.impacto, IF(d.creado_por IS NULL OR d.creado_por = d.id_usuario, 'tecnico', 'asistente'), d.tipo
    FROM demora_registro d
    JOIN orden_servicio os ON os.id_os = d.id_os
    JOIN cliente c ON c.id_cliente = os.id_cliente
    JOIN usuario u ON u.id_usuario = d.id_usuario
    LEFT JOIN tabla_maestra m ON m.Descripcion = 'MOTIVO_DEMORA_RUTA' AND m.IdEmpresa = 1 AND m.Num1 = d.id_motivo
    WHERE d.eliminado_en IS NULL AND d.fecha_registro >= v_hoy AND d.fecha_registro < DATE_ADD(v_hoy, INTERVAL 1 DAY);
    INSERT INTO tmp_sg_inc
    SELECT CONCAT('i', i.id_incidencia), i.fecha_registro, i.id_usuario, TRIM(CONCAT(u.nombre, ' ', u.apellido)), UPPER(CONCAT(LEFT(u.nombre, 1), LEFT(u.apellido, 1))),
           i.id_os, os.numero, c.razon_social, COALESCE(m.String2, 'OTRO'), COALESCE(m.String1, 'Incidencia'), LEFT(IFNULL(i.descripcion, ''), 400),
           i.duracion_estimada_min, IF(nv.String3 = 'CRITICO', 'detiene', i.impacto), IF(i.creado_por IS NULL OR i.creado_por = i.id_usuario, 'tecnico', 'asistente'), NULL
    FROM incidencia_operativa i
    JOIN orden_servicio os ON os.id_os = i.id_os
    JOIN cliente c ON c.id_cliente = os.id_cliente
    JOIN usuario u ON u.id_usuario = i.id_usuario
    LEFT JOIN tabla_maestra m ON m.Descripcion = 'TIPO_INCIDENCIA_OPERATIVA' AND m.IdEmpresa = 1 AND m.Num1 = i.id_tipo
    LEFT JOIN tabla_maestra nv ON nv.Descripcion = 'NIVEL_ALERTA' AND nv.IdEmpresa = 1 AND nv.Num1 = i.id_nivel_alerta
    WHERE i.eliminado_en IS NULL AND i.fecha_registro >= v_hoy AND i.fecha_registro < DATE_ADD(v_hoy, INTERVAL 1 DAY);
    -- HU-53: demoras/incidentes registrados por el Asistente desde la intranet (clave 'a<id>')
    INSERT INTO tmp_sg_inc
    SELECT CONCAT('a', ra.id_registro), CONVERT_TZ(ra.fecha_utc, '+00:00', '-05:00'), COALESCE(ra.id_tecnico, ra.id_usuario),
           TRIM(CONCAT(ut.nombre, ' ', ut.apellido)), UPPER(CONCAT(LEFT(ut.nombre, 1), LEFT(ut.apellido, 1))),
           ra.id_os, os.numero, c.razon_social, COALESCE(m.String2, 'OTROS'), COALESCE(m.String1, 'Demora'), LEFT(IFNULL(ra.descripcion, ''), 400),
           ra.duracion_min, ra.impacto, 'asistente', NULL
    FROM registro_asistente ra
    JOIN orden_servicio os ON os.id_os = ra.id_os
    JOIN cliente c ON c.id_cliente = os.id_cliente
    JOIN usuario ut ON ut.id_usuario = COALESCE(ra.id_tecnico, ra.id_usuario)
    LEFT JOIN tabla_maestra m ON m.Descripcion = 'TIPO_DEMORA_INCIDENTE' AND m.IdEmpresa = 1 AND m.Num1 = ra.id_tipo
    WHERE ra.modo = 'demora' AND ra.fecha_utc >= v_ini_utc AND ra.fecha_utc < DATE_ADD(v_ini_utc, INTERVAL 1 DAY);
END$$

DELIMITER ;
