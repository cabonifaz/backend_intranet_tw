-- HU-52 (Sprint 5) Pestaña "Timeline del Día": eventos cronológicos del servicio. SOLO LECTURA.
-- Categorías: hito (eventos del técnico: salida, llegada, inicio, fin…) · alerta (automáticas del sistema) · incidencia (demoras/incidencias)
--             · asistente (registros manuales del Asistente, HU-53). Origen: tecnico (app móvil) | sistema (automático) | asistente (manual).
-- p_categoria: '' (todas) | hito | alerta | incidencia | asistente. p_orden: reciente (por defecto) | antiguo.
-- HU-53: las observaciones y los cambios manuales de estado del Asistente (registro_asistente) aparecen con su Badge ([NOTA DEL ASISTENTE],
--   [DEMORA — REGISTRO DEL ASISTENTE], [CAMBIO MANUAL CRÍTICO — ASISTENTE]), el nombre de quien registró y, si aplica, el evento al que se vinculan.
-- Resultados: 1 mensaje · 2 conteos por categoría + total · 3 eventos (Hora, Categoria, Origen, Titulo, Detalle, Clave, Badge, Registrador, Vinculo).
DROP PROCEDURE IF EXISTS SP_ObtenerTimelineServicioRuta;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerTimelineServicioRuta(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT,
    IN p_categoria  VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_orden      VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_msg      VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_ahora    DATETIME;
    DECLARE v_ahora_utc DATETIME;
    DECLARE v_ini_utc  DATETIME;
    DECLARE v_prox     INT;
    DECLARE v_tec      BIGINT;
    DECLARE v_lat_s    DECIMAL(10,7);
    DECLARE v_lon_s    DECIMAL(10,7);
    DECLARE v_pre_utc  DATETIME;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_dt_ev;
        CALL SP_LimpiarSeguimientoOperativo();
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_categoria, '') NOT IN ('', 'hito', 'alerta', 'incidencia', 'asistente') OR IFNULL(NULLIF(p_orden, ''), 'reciente') NOT IN ('reciente', 'antiguo') THEN
        SELECT 1 AS IdTipoMensaje, 'La categoría o el orden no es válido.' AS Mensaje;
        LEAVE proc;
    END IF;
    CALL SP_PrepararDetalleServicioRuta(p_id_usuario, p_id_os, v_msg);
    IF v_msg IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT ahora, ahora_utc, ini_utc, prox INTO v_ahora, v_ahora_utc, v_ini_utc, v_prox FROM tmp_sg_cfg LIMIT 1;
    SELECT id_tecnico, lat_sede, lon_sede INTO v_tec, v_lat_s, v_lon_s FROM tmp_sg_os WHERE id_os = p_id_os;
    SELECT MIN(x.timestamp_utc) INTO v_pre_utc FROM ubicacion_tecnico x
    WHERE v_lat_s IS NOT NULL AND v_lon_s IS NOT NULL AND x.id_usuario = v_tec AND x.timestamp_utc >= v_ini_utc AND x.timestamp_utc <= v_ahora_utc
      AND 6371000 * 2 * ASIN(SQRT(POW(SIN(RADIANS(v_lat_s - x.latitud) / 2), 2) + COS(RADIANS(x.latitud)) * COS(RADIANS(v_lat_s)) * POW(SIN(RADIANS(v_lon_s - x.longitud) / 2), 2))) <= v_prox;

    DROP TEMPORARY TABLE IF EXISTS tmp_dt_ev;
    CREATE TEMPORARY TABLE tmp_dt_ev (
        id INT NOT NULL AUTO_INCREMENT, hora DATETIME, categoria VARCHAR(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        origen VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, titulo VARCHAR(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        detalle VARCHAR(400) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, clave VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        badge VARCHAR(60) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, registrador VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        vinculo VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, PRIMARY KEY (id)
    );
    -- Hitos del técnico (las demoras e incidencias se listan aparte, desde sus propios registros)
    INSERT INTO tmp_dt_ev (hora, categoria, origen, titulo, detalle, clave)
    SELECT CONVERT_TZ(e.timestamp_utc, '+00:00', '-05:00'), 'hito', 'tecnico', m.String1, LEFT(e.notas, 400), CONCAT('e', e.id_evento)
    FROM evento_campo e JOIN tabla_maestra m ON m.Descripcion = 'TIPO_EVENTO_CAMPO' AND m.IdEmpresa = 1 AND m.Num1 = e.id_tipo_evento
    WHERE e.id_os = p_id_os AND e.eliminado_en IS NULL AND e.timestamp_utc >= v_ini_utc AND m.String2 NOT IN ('DEMORA', 'INCIDENCIA')
      AND NOT EXISTS (SELECT 1 FROM registro_asistente ra WHERE ra.id_evento_campo = e.id_evento);
    IF v_pre_utc IS NOT NULL THEN
        INSERT INTO tmp_dt_ev (hora, categoria, origen, titulo, detalle, clave)
        VALUES (CONVERT_TZ(v_pre_utc, '+00:00', '-05:00'), 'hito', 'sistema', 'Pre-llegada por proximidad', CONCAT('A menos de ', v_prox, ' m del cliente'), 'pre');
    END IF;
    INSERT INTO tmp_dt_ev (hora, categoria, origen, titulo, detalle, clave)
    SELECT DATE_SUB(v_ahora, INTERVAL IFNULL(a.minutos, 0) MINUTE), 'alerta', 'sistema', a.titulo, a.detalle, CONCAT('a', a.tipo)
    FROM tmp_sg_alerta a WHERE a.id_os = p_id_os;
    INSERT INTO tmp_dt_ev (hora, categoria, origen, titulo, detalle, clave, badge, registrador)
    SELECT i.fecha, IF(i.origen = 'asistente', 'asistente', 'incidencia'), i.origen,
           LEFT(CONCAT(CASE i.fase WHEN 'llegada' THEN 'Demora en ruta: ' WHEN 'ingreso' THEN 'Demora en ingreso a planta: ' ELSE '' END, i.tipo), 120),
           i.descripcion, i.clave,
           IF(i.origen = 'asistente', '[DEMORA — REGISTRO DEL ASISTENTE]', NULL),
           (SELECT TRIM(CONCAT(ua.nombre, ' ', ua.apellido)) FROM registro_asistente ra JOIN usuario ua ON ua.id_usuario = ra.id_usuario
            WHERE i.clave = CONCAT('a', ra.id_registro))
    FROM tmp_sg_inc i WHERE i.id_os = p_id_os;
    -- HU-53: observaciones y cambios manuales de estado del Asistente
    INSERT INTO tmp_dt_ev (hora, categoria, origen, titulo, detalle, clave, badge, registrador, vinculo)
    SELECT CONVERT_TZ(ra.fecha_utc, '+00:00', '-05:00'), 'asistente', 'asistente',
           IF(ra.modo = 'observacion', 'Nota del Asistente',
              CONCAT('Cambio manual de estado: ', IFNULL(ra.estado_nuevo, ''))),
           LEFT(ra.descripcion, 400), CONCAT('a', ra.id_registro),
           IF(ra.modo = 'observacion', '[NOTA DEL ASISTENTE]', '[CAMBIO MANUAL CRÍTICO — ASISTENTE]'),
           TRIM(CONCAT(ua.nombre, ' ', ua.apellido)), ra.vinculo_clave
    FROM registro_asistente ra JOIN usuario ua ON ua.id_usuario = ra.id_usuario
    WHERE ra.id_os = p_id_os AND ra.modo IN ('observacion', 'cambio_estado') AND ra.fecha_utc >= v_ini_utc;

    SELECT 2 AS IdTipoMensaje, 'OK' AS Mensaje;
    SELECT IFNULL(SUM(categoria = 'hito'), 0) AS Hitos, IFNULL(SUM(categoria = 'alerta'), 0) AS Alertas, IFNULL(SUM(categoria = 'incidencia'), 0) AS Incidencias,
           IFNULL(SUM(categoria = 'asistente'), 0) AS Asistente, COUNT(*) AS Total FROM tmp_dt_ev;
    IF IFNULL(NULLIF(p_orden, ''), 'reciente') = 'reciente' THEN
        SELECT DATE_FORMAT(hora, '%H:%i') AS Hora, categoria AS Categoria, origen AS Origen, titulo AS Titulo, detalle AS Detalle, clave AS Clave,
               badge AS Badge, registrador AS Registrador, vinculo AS Vinculo
        FROM tmp_dt_ev WHERE p_categoria = '' OR categoria = p_categoria ORDER BY hora DESC, id DESC LIMIT 500;
    ELSE
        SELECT DATE_FORMAT(hora, '%H:%i') AS Hora, categoria AS Categoria, origen AS Origen, titulo AS Titulo, detalle AS Detalle, clave AS Clave,
               badge AS Badge, registrador AS Registrador, vinculo AS Vinculo
        FROM tmp_dt_ev WHERE p_categoria = '' OR categoria = p_categoria ORDER BY hora ASC, id ASC LIMIT 500;
    END IF;

    DROP TEMPORARY TABLE IF EXISTS tmp_dt_ev;
    CALL SP_LimpiarSeguimientoOperativo();
END$$

DELIMITER ;
