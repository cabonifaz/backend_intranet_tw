-- HU-52 (Sprint 5) Pestaña "Mapa GPS": posición actual del técnico, ruta recorrida hoy, pin del cliente con radio de proximidad y panel GPS. SOLO LECTURA.
-- Conexión: sin_senal (sin posición o más del umbral SEG_PERDIDA_CONTACTO_MIN) | gps_parado (mismo punto por SEG_GPS_PARADO_MIN o más) | gps_activo.
-- Velocidad, altitud, satélites y latencia salen de ubicacion_tecnico (migración 91; los envía la app; NULL si no los envía).
-- OrigenLat/OrigenLon (HU-20) = punto de salida del recorrido. La ruta (resultado 3) va de la posición más reciente a la más antigua.
-- Resultados: 1 mensaje · 2 panel (1 fila) · 3 ruta (puntos del día, máx. 300) · 4 cronograma GPS (salida, pre-llegada, llegada)
--   · 5 demoras de la app con su GPS (Fase: llegada = en ruta, ingreso = ingreso a planta).
DROP PROCEDURE IF EXISTS SP_ObtenerMapaServicioRuta;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerMapaServicioRuta(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT
)
proc: BEGIN
    DECLARE v_msg      VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_ahora_utc DATETIME;
    DECLARE v_ini_utc  DATETIME;
    DECLARE v_perdida  INT;
    DECLARE v_parado   INT;
    DECLARE v_prox     INT;
    DECLARE v_tec      BIGINT;
    DECLARE v_lat_s    DECIMAL(10,7);
    DECLARE v_lon_s    DECIMAL(10,7);
    DECLARE v_id_ub    BIGINT;
    DECLARE v_pre_utc  DATETIME;
    DECLARE v_olat     DECIMAL(10,7) DEFAULT NULL;
    DECLARE v_olon     DECIMAL(10,7) DEFAULT NULL;

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

    SELECT ahora_utc, ini_utc, perdida, parado, prox INTO v_ahora_utc, v_ini_utc, v_perdida, v_parado, v_prox FROM tmp_sg_cfg LIMIT 1;
    SELECT id_tecnico, lat_sede, lon_sede INTO v_tec, v_lat_s, v_lon_s FROM tmp_sg_os WHERE id_os = p_id_os;
    SELECT MAX(id_ubicacion) INTO v_id_ub FROM ubicacion_tecnico WHERE id_usuario = v_tec AND timestamp_utc >= v_ini_utc AND timestamp_utc <= v_ahora_utc;

    -- Primera posición dentro del radio de proximidad (pre-llegada)
    SELECT MIN(x.timestamp_utc) INTO v_pre_utc FROM ubicacion_tecnico x
    WHERE v_lat_s IS NOT NULL AND v_lon_s IS NOT NULL AND x.id_usuario = v_tec AND x.timestamp_utc >= v_ini_utc AND x.timestamp_utc <= v_ahora_utc
      AND 6371000 * 2 * ASIN(SQRT(POW(SIN(RADIANS(v_lat_s - x.latitud) / 2), 2) + COS(RADIANS(x.latitud)) * COS(RADIANS(v_lat_s)) * POW(SIN(RADIANS(v_lon_s - x.longitud) / 2), 2))) <= v_prox;

    -- Punto de salida (HU-20): la coordenada del evento «Salida» de la app o, si no la envió, la primera posición GPS del técnico hoy
    SELECT e.latitud, e.longitud INTO v_olat, v_olon
    FROM evento_campo e JOIN tabla_maestra m ON m.Descripcion = 'TIPO_EVENTO_CAMPO' AND m.IdEmpresa = 1 AND m.Num1 = e.id_tipo_evento AND m.String2 = 'SALIDA_BASE'
    WHERE e.id_os = p_id_os AND e.eliminado_en IS NULL AND e.latitud IS NOT NULL AND e.longitud IS NOT NULL AND e.timestamp_utc >= v_ini_utc
    ORDER BY e.id_evento LIMIT 1;
    IF v_olat IS NULL THEN
        SELECT x.latitud, x.longitud INTO v_olat, v_olon
        FROM ubicacion_tecnico x WHERE x.id_usuario = v_tec AND x.timestamp_utc >= v_ini_utc AND x.timestamp_utc <= v_ahora_utc
        ORDER BY x.timestamp_utc, x.id_ubicacion LIMIT 1;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'OK' AS Mensaje;

    SELECT o.id_os AS IdOs, o.estado_seg AS Estado, o.tecnico AS Tecnico, o.razon_social AS Cliente, o.sede_nombre AS Sede, o.sede_direccion AS DireccionSede,
           o.lat_sede AS LatSede, o.lon_sede AS LonSede, v_prox AS RadioProximidadM,
           IF(o.fase IN ('en_planta', 'en_ejecucion', 'finalizado') OR (o.dist_m IS NOT NULL AND o.dist_m <= v_prox), 1, 0) AS MostrarRadio,
           p.lat AS Latitud, p.lon AS Longitud, p.direccion AS UltimaUbicacion, o.dist_m AS DistanciaM,
           DATE_FORMAT(CONVERT_TZ(p.ts_utc, '+00:00', '-05:00'), '%H:%i:%s') AS UltimaActualizacion,
           IF(p.ts_utc IS NULL, NULL, GREATEST(0, TIMESTAMPDIFF(SECOND, p.ts_utc, v_ahora_utc))) AS SegundosDesdeUltima,
           CASE WHEN p.ts_utc IS NULL OR TIMESTAMPDIFF(MINUTE, p.ts_utc, v_ahora_utc) > v_perdida THEN 'sin_senal'
                WHEN p.parado_desde IS NOT NULL AND TIMESTAMPDIFF(MINUTE, p.parado_desde, p.ts_utc) >= v_parado THEN 'gps_parado'
                ELSE 'gps_activo' END AS Conexion,
           IF(p.parado_desde IS NULL, 0, GREATEST(0, TIMESTAMPDIFF(MINUTE, p.parado_desde, v_ahora_utc))) AS MinutosEnPunto,
           u.precision_m AS PrecisionM, u.velocidad_kmh AS VelocidadKmh, u.altitud_m AS AltitudM, u.satelites AS Satelites, u.latencia_ms AS LatenciaMs,
           o.eta_min AS EtaMinutos, DATE_FORMAT(o.eta_est, '%H:%i') AS EtaHora, v_olat AS OrigenLat, v_olon AS OrigenLon
    FROM tmp_sg_os o
    LEFT JOIN tmp_sg_pos p ON p.id_usuario = o.id_tecnico
    LEFT JOIN ubicacion_tecnico u ON u.id_ubicacion = v_id_ub
    WHERE o.id_os = p_id_os;

    SELECT x.latitud AS Latitud, x.longitud AS Longitud, DATE_FORMAT(CONVERT_TZ(x.timestamp_utc, '+00:00', '-05:00'), '%H:%i:%s') AS Hora
    FROM ubicacion_tecnico x
    WHERE x.id_usuario = v_tec AND x.timestamp_utc >= v_ini_utc AND x.timestamp_utc <= v_ahora_utc
    ORDER BY x.timestamp_utc DESC, x.id_ubicacion DESC LIMIT 300;

    SELECT c.hito AS Hito, DATE_FORMAT(CONVERT_TZ(c.t, '+00:00', '-05:00'), '%H:%i') AS Hora, c.n AS Orden FROM (
        SELECT 'salida' AS hito, MIN(e.timestamp_utc) AS t, 1 AS n FROM evento_campo e JOIN tabla_maestra m ON m.Descripcion = 'TIPO_EVENTO_CAMPO' AND m.IdEmpresa = 1 AND m.Num1 = e.id_tipo_evento
          WHERE e.id_os = p_id_os AND e.eliminado_en IS NULL AND e.timestamp_utc >= v_ini_utc AND m.String2 = 'SALIDA_BASE'
        UNION ALL SELECT 'pre_llegada', v_pre_utc, 2
        UNION ALL SELECT 'llegada', MIN(e.timestamp_utc), 3 FROM evento_campo e JOIN tabla_maestra m ON m.Descripcion = 'TIPO_EVENTO_CAMPO' AND m.IdEmpresa = 1 AND m.Num1 = e.id_tipo_evento
          WHERE e.id_os = p_id_os AND e.eliminado_en IS NULL AND e.timestamp_utc >= v_ini_utc AND m.String2 = 'LLEGADA'
    ) c ORDER BY c.n;

    SELECT d.latitud AS Latitud, d.longitud AS Longitud, DATE_FORMAT(d.fecha_registro, '%H:%i') AS Hora, d.tipo AS Fase,
           COALESCE(m.String1, 'Demora') AS Motivo, d.duracion_minutos AS DuracionMin
    FROM demora_registro d
    LEFT JOIN tabla_maestra m ON m.Descripcion = 'MOTIVO_DEMORA_RUTA' AND m.IdEmpresa = 1 AND m.Num1 = d.id_motivo
    WHERE d.id_os = p_id_os AND d.eliminado_en IS NULL AND d.latitud IS NOT NULL AND d.longitud IS NOT NULL
      AND d.fecha_registro >= CONVERT_TZ(v_ini_utc, '+00:00', '-05:00')
    ORDER BY d.fecha_registro, d.id_demora;

    CALL SP_LimpiarSeguimientoOperativo();
END$$

DELIMITER ;
