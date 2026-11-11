-- ============================================================
-- SP_ObtenerRutaServicioJefaturaMovil  (App Mobile HU-30 — "Ubicación y ruta" de un servicio · solo lectura)
-- Posición y recorrido GPS del técnico en un servicio de HOY dentro del alcance del jefe (SP_ResolverJefaturaMovil + SP_ArmarAlcanceJefaturaMovil), con la
-- demora registrada por el técnico y los eventos en ruta. Datos del motor de Seguimiento Operativo (HU-51): ubicacion_tecnico, evento_campo, demora_registro.
-- Resultados: 1 mensaje · 2 resumen (1 fila) · 3 recorrido GPS (máx. 120 puntos, en orden) · 4 eventos en ruta (cronológicos).
--   Resumen: lat/lon = última posición; minutos_ubicacion = antigüedad de esa posición; destino_* = planta del cliente (sede); origen_* = coordenada del evento de
--     salida (si la app la envió). distancia_m = distancia EN LÍNEA RECTA de la última posición a la planta (no es la distancia por calle).
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
           (SELECT e.latitud FROM evento_campo e JOIN tabla_maestra m ON m.Descripcion = 'TIPO_EVENTO_CAMPO' AND m.IdEmpresa = 1 AND m.Num1 = e.id_tipo_evento AND m.String2 = 'SALIDA_BASE'
             WHERE e.id_os = o.id_os AND e.eliminado_en IS NULL AND e.latitud IS NOT NULL AND e.timestamp_utc >= c.ini_utc ORDER BY e.id_evento LIMIT 1) AS origen_latitud,
           (SELECT e.longitud FROM evento_campo e JOIN tabla_maestra m ON m.Descripcion = 'TIPO_EVENTO_CAMPO' AND m.IdEmpresa = 1 AND m.Num1 = e.id_tipo_evento AND m.String2 = 'SALIDA_BASE'
             WHERE e.id_os = o.id_os AND e.eliminado_en IS NULL AND e.latitud IS NOT NULL AND e.timestamp_utc >= c.ini_utc ORDER BY e.id_evento LIMIT 1) AS origen_longitud,
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
