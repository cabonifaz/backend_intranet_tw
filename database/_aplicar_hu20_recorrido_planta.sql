-- HU-20 (planta y recorrido en el mapa): Alt+X, responder No al aviso Large script. Reiniciar la API. Idempotente.

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

-- ============================================================
-- SP_ObtenerRutaServicioJefaturaMovil  (App Mobile HU-30 — "Ubicación y ruta" de un servicio · solo lectura)
-- Posición y recorrido GPS del técnico en un servicio de HOY dentro del alcance del jefe (SP_ResolverJefaturaMovil + SP_ArmarAlcanceJefaturaMovil), con la
-- demora registrada por el técnico y los eventos en ruta. Datos del motor de Seguimiento Operativo (HU-51): ubicacion_tecnico, evento_campo, demora_registro.
-- Resultados: 1 mensaje · 2 resumen (1 fila) · 3 recorrido GPS (máx. 120 puntos, en orden) · 4 eventos en ruta (cronológicos).
--   Resumen: lat/lon = última posición; minutos_ubicacion = antigüedad de esa posición; destino_* = planta del cliente (sede); origen_* = coordenada del evento de
--     salida (si la app no la envió, la primera posición GPS del técnico hoy). distancia_m = distancia EN LÍNEA RECTA de la última posición a la planta (no es la distancia por calle).
--     velocidad_kmh = entre las dos últimas posiciones de hoy (solo si distan entre 20 s y 10 min; NULL si no hay datos suficientes).
--     eta_estimada / eta_minutos = estimación en ruta desde la posición actual (línea recta × 1,3 a la velocidad promedio configurada; referencial). destino_direccion = dirección de la planta.
--     eta (HH:MM) = solo en ruta: la hora de llegada recalculada por la última demora de la app (demora_registro.eta_recalculada) o, si no hay, la hora esperada de
--     la bandeja de seguimiento (hora programada + demoras en ruta). eta_programada = hora programada del servicio.
--     demora_* = la última demora/incidencia de hoy (texto armado para la tarjeta amarilla). contacto_* = contacto en planta del cliente (para avisarle).
--   Eventos: tono (verde · naranja · amarillo): hito del técnico (OK) · demora (+N MIN) · alerta automática de la bandeja (ALERTA).
-- Requiere las migraciones 90 a 92 y 97.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerRutaServicioJefaturaMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerRutaServicioJefaturaMovil(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT
)
proc: BEGIN
    DECLARE v_area        VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_sede        VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_aut_area    VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_aut_general TINYINT DEFAULT 0;
    DECLARE v_existe      INT DEFAULT 0;
    DECLARE v_ini_utc     DATETIME;
    DECLARE v_ahora_utc   DATETIME;
    DECLARE v_tec         BIGINT;
    DECLARE v_la1 DECIMAL(10,7) DEFAULT NULL;
    DECLARE v_lo1 DECIMAL(10,7) DEFAULT NULL;
    DECLARE v_t1  DATETIME      DEFAULT NULL;
    DECLARE v_la2 DECIMAL(10,7) DEFAULT NULL;
    DECLARE v_lo2 DECIMAL(10,7) DEFAULT NULL;
    DECLARE v_t2  DATETIME      DEFAULT NULL;
    DECLARE v_dt_seg  INT DEFAULT NULL;
    DECLARE v_dist_m  DOUBLE DEFAULT NULL;
    DECLARE v_kmh     DECIMAL(6,1) DEFAULT NULL;
    DECLARE v_dem_txt VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_dem_org VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_jf_alc;
        DROP TEMPORARY TABLE IF EXISTS tmp_jf_ev;
        CALL SP_LimpiarSeguimientoOperativo();
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_os, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El servicio indicado no es válido.' AS Mensaje;
        LEAVE proc;
    END IF;
    CALL SP_ResolverJefaturaMovil(p_id_usuario, v_area, v_sede, v_aut_area, v_aut_general);
    IF v_area IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Tu cargo no tiene el menú de Jefatura.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_ArmarSeguimientoOperativo();
    CALL SP_ArmarAlcanceJefaturaMovil(v_area, p_id_os);
    SELECT COUNT(*) INTO v_existe FROM tmp_sg_os o JOIN tmp_jf_alc a ON a.id_os = o.id_os WHERE o.id_os = p_id_os;
    IF v_existe = 0 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_jf_alc;
        CALL SP_LimpiarSeguimientoOperativo();
        SELECT 1 AS IdTipoMensaje, 'El servicio no existe, no es de hoy o no pertenece a tu área.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT ini_utc, ahora_utc INTO v_ini_utc, v_ahora_utc FROM tmp_sg_cfg LIMIT 1;
    SELECT id_tecnico INTO v_tec FROM tmp_sg_os WHERE id_os = p_id_os;

    -- Velocidad: entre las dos últimas posiciones del técnico en este servicio (hoy)
    SELECT x.latitud, x.longitud, x.timestamp_utc INTO v_la1, v_lo1, v_t1
    FROM   ubicacion_tecnico x
    WHERE  x.id_usuario = v_tec AND x.timestamp_utc >= v_ini_utc AND x.timestamp_utc <= v_ahora_utc AND (x.id_os IS NULL OR x.id_os = p_id_os)
    ORDER BY x.timestamp_utc DESC, x.id_ubicacion DESC LIMIT 1;
    SELECT x.latitud, x.longitud, x.timestamp_utc INTO v_la2, v_lo2, v_t2
    FROM   ubicacion_tecnico x
    WHERE  x.id_usuario = v_tec AND x.timestamp_utc >= v_ini_utc AND x.timestamp_utc <= v_ahora_utc AND (x.id_os IS NULL OR x.id_os = p_id_os)
    ORDER BY x.timestamp_utc DESC, x.id_ubicacion DESC LIMIT 1 OFFSET 1;
    IF v_t1 IS NOT NULL AND v_t2 IS NOT NULL THEN
        SET v_dt_seg = TIMESTAMPDIFF(SECOND, v_t2, v_t1);
        IF v_dt_seg BETWEEN 20 AND 600 THEN
            SET v_dist_m = 6371000 * 2 * ASIN(SQRT(POW(SIN(RADIANS(v_la1 - v_la2) / 2), 2)
                                                 + COS(RADIANS(v_la2)) * COS(RADIANS(v_la1)) * POW(SIN(RADIANS(v_lo1 - v_lo2) / 2), 2)));
            SET v_kmh = ROUND(v_dist_m / v_dt_seg * 3.6, 1);
        END IF;
    END IF;

    -- Eventos en ruta: hitos del técnico, demoras/incidencias y alertas automáticas de este servicio
    DROP TEMPORARY TABLE IF EXISTS tmp_jf_ev;
    CREATE TEMPORARY TABLE tmp_jf_ev (
        id      INT NOT NULL AUTO_INCREMENT,
        hora    DATETIME,
        titulo  VARCHAR(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        detalle VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        badge   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        tono    VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        PRIMARY KEY (id)
    );
    INSERT INTO tmp_jf_ev (hora, titulo, detalle, badge, tono)
    SELECT CONVERT_TZ(e.timestamp_utc, '+00:00', '-05:00'), m.String1,
           IF(e.latitud IS NULL, NULL, CONCAT('GPS ', ROUND(e.latitud, 2), ', ', ROUND(e.longitud, 2))), 'OK', 'verde'
    FROM   evento_campo e
    JOIN   tabla_maestra m ON m.Descripcion = 'TIPO_EVENTO_CAMPO' AND m.IdEmpresa = 1 AND m.Num1 = e.id_tipo_evento
    WHERE  e.id_os = p_id_os AND e.eliminado_en IS NULL AND e.timestamp_utc >= v_ini_utc AND m.String2 IN ('SALIDA_BASE', 'EN_RUTA', 'LLEGADA', 'INGRESO_PLANTA');
    INSERT INTO tmp_jf_ev (hora, titulo, detalle, badge, tono)
    SELECT i.fecha, LEFT(CONCAT(CASE i.fase WHEN 'llegada' THEN 'Demora registrada' WHEN 'ingreso' THEN 'Demora en ingreso a planta' ELSE i.tipo END), 120),
           LEFT(IFNULL(NULLIF(i.descripcion, ''), i.tipo), 300),
           IF(i.duracion_min IS NULL, 'DEMORA', CONCAT('+', i.duracion_min, ' MIN')), IF(i.impacto = 'detiene', 'rojo', 'naranja')
    FROM   tmp_sg_inc i WHERE i.id_os = p_id_os;
    INSERT INTO tmp_jf_ev (hora, titulo, detalle, badge, tono)
    SELECT DATE_SUB(c.ahora, INTERVAL IFNULL(a.minutos, 0) MINUTE), a.titulo, a.detalle, 'ALERTA', 'amarillo'
    FROM   tmp_sg_alerta a JOIN tmp_sg_cfg c
    WHERE  a.id_os = p_id_os AND a.tipo <> 'proximidad';

    -- Última demora/incidencia de hoy (se precalcula: una tabla temporal no puede abrirse dos veces en la misma consulta)
    SELECT LEFT(CONCAT(CASE i.fase WHEN 'llegada' THEN 'Llegada a planta' WHEN 'ingreso' THEN 'Ingreso a planta' ELSE i.tipo END,
                       IF(i.duracion_min IS NULL, '', CONCAT(' · +', i.duracion_min, ' min')),
                       IF(IFNULL(i.descripcion, '') = '', '', CONCAT(' · "', i.descripcion, '"')),
                       ' · Impacto: ', IF(i.impacto = 'detiene', 'detiene el servicio', 'retrasa el servicio')), 300),
           IF(i.origen = 'asistente', 'asistente', 'tecnico')
    INTO   v_dem_txt, v_dem_org
    FROM   tmp_sg_inc i WHERE i.id_os = p_id_os ORDER BY i.fecha DESC LIMIT 1;

    SELECT 2 AS IdTipoMensaje, 'OK' AS Mensaje;

    -- 2 Resumen
    SELECT o.id_os AS id_os, o.numero AS numero, o.razon_social AS cliente, o.estado_seg AS estado,
           o.id_tecnico AS id_tecnico, o.tecnico AS tecnico, NULLIF(TRIM(ut.telefono), '') AS telefono_tecnico,
           p.lat AS latitud, p.lon AS longitud,
           IF(p.ts_utc IS NULL, NULL, GREATEST(0, TIMESTAMPDIFF(MINUTE, p.ts_utc, c.ahora_utc))) AS minutos_ubicacion,
           v_kmh AS velocidad_kmh, o.dist_m AS distancia_m,
           o.lat_sede AS destino_latitud, o.lon_sede AS destino_longitud,
           COALESCE(NULLIF(o.sede_nombre, ''), NULLIF(o.sede_direccion, '')) AS destino_nombre,
           COALESCE((SELECT e.latitud FROM evento_campo e JOIN tabla_maestra m ON m.Descripcion = 'TIPO_EVENTO_CAMPO' AND m.IdEmpresa = 1 AND m.Num1 = e.id_tipo_evento AND m.String2 = 'SALIDA_BASE'
             WHERE e.id_os = o.id_os AND e.eliminado_en IS NULL AND e.latitud IS NOT NULL AND e.timestamp_utc >= c.ini_utc ORDER BY e.id_evento LIMIT 1),
             (SELECT x.latitud FROM ubicacion_tecnico x WHERE x.id_usuario = o.id_tecnico AND x.timestamp_utc >= c.ini_utc ORDER BY x.timestamp_utc, x.id_ubicacion LIMIT 1)) AS origen_latitud,
           COALESCE((SELECT e.longitud FROM evento_campo e JOIN tabla_maestra m ON m.Descripcion = 'TIPO_EVENTO_CAMPO' AND m.IdEmpresa = 1 AND m.Num1 = e.id_tipo_evento AND m.String2 = 'SALIDA_BASE'
             WHERE e.id_os = o.id_os AND e.eliminado_en IS NULL AND e.latitud IS NOT NULL AND e.timestamp_utc >= c.ini_utc ORDER BY e.id_evento LIMIT 1),
             (SELECT x.longitud FROM ubicacion_tecnico x WHERE x.id_usuario = o.id_tecnico AND x.timestamp_utc >= c.ini_utc ORDER BY x.timestamp_utc, x.id_ubicacion LIMIT 1)) AS origen_longitud,
           IF(o.fase = 'en_ruta', DATE_FORMAT(COALESCE((SELECT MAX(d.eta_recalculada) FROM demora_registro d
                                                          WHERE d.id_os = o.id_os AND d.tipo = 'llegada' AND d.eliminado_en IS NULL AND d.fecha_registro >= c.hoy), h.esperado), '%H:%i'), NULL) AS eta,
           TIME_FORMAT(o.hora_inicio, '%H:%i') AS eta_programada,
           o.eta_min AS eta_minutos, DATE_FORMAT(o.eta_est, '%H:%i') AS eta_estimada, NULLIF(o.sede_direccion, '') AS destino_direccion,
           v_dem_txt AS demora_texto, v_dem_org AS demora_origen,
           cc.nombres AS contacto_nombre, NULLIF(TRIM(cc.telefono_movil), '') AS contacto_telefono,
           DATE_FORMAT(c.ahora, '%H:%i') AS actualizado
    FROM   tmp_sg_os o
    JOIN   tmp_sg_cfg c
    JOIN   orden_servicio osr ON osr.id_os = o.id_os
    LEFT JOIN tmp_sg_pos  p ON p.id_usuario = o.id_tecnico
    LEFT JOIN tmp_sg_hito h ON h.id_os = o.id_os
    LEFT JOIN usuario ut ON ut.id_usuario = o.id_tecnico
    LEFT JOIN contacto_cliente cc ON cc.id_contacto = osr.id_contacto AND cc.SoftDelete = 0
    WHERE  o.id_os = p_id_os;

    -- 3 Recorrido GPS (hasta 120 puntos repartidos en todo el trayecto)
    SELECT t.latitud AS latitud, t.longitud AS longitud, DATE_FORMAT(CONVERT_TZ(t.timestamp_utc, '+00:00', '-05:00'), '%H:%i') AS hora
    FROM (SELECT x.latitud, x.longitud, x.timestamp_utc,
                 ROW_NUMBER() OVER (ORDER BY x.timestamp_utc, x.id_ubicacion) AS rn,
                 COUNT(*) OVER () AS n
          FROM   ubicacion_tecnico x
          WHERE  x.id_usuario = v_tec AND x.timestamp_utc >= v_ini_utc AND x.timestamp_utc <= v_ahora_utc AND (x.id_os IS NULL OR x.id_os = p_id_os)) t
    WHERE  t.n <= 120 OR MOD(t.rn, CEIL(t.n / 120)) = 0 OR t.rn = t.n
    ORDER BY t.rn;

    -- 4 Eventos en ruta
    SELECT DATE_FORMAT(ev.hora, '%H:%i') AS hora, ev.titulo AS titulo, ev.detalle AS detalle, ev.badge AS badge, ev.tono AS tono
    FROM   tmp_jf_ev ev ORDER BY ev.hora, ev.id;

    DROP TEMPORARY TABLE IF EXISTS tmp_jf_ev;
    DROP TEMPORARY TABLE IF EXISTS tmp_jf_alc;
    CALL SP_LimpiarSeguimientoOperativo();
END$$

DELIMITER ;
