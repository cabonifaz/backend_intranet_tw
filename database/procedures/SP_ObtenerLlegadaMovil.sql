-- ============================================================
-- SP_ObtenerLlegadaMovil  (App Mobile HU-06 — Registro de llegada · lectura)
-- Contexto de la pantalla "Registrar llegada" de una OS del técnico que inició sesión (el id sale del token):
--   cliente, ubicación esperada (sede + coordenada de referencia + radio permitido), hora programada, salida y la llegada ya registrada.
--   Se puede registrar con la OS EN RUTA (traslado iniciado) y sin llegada en este viaje. La llegada de "este viaje" es el último evento
--   LLEGADA posterior a la última SALIDA_BASE (una OS reprogramada que sale otra vez no hereda la llegada anterior).
--   Horas en Lima (UTC-5). Las reglas de la distancia están en SP_EvaluarLlegadaMovil.
-- Resultados: 1 mensaje · 2 una fila (id_os, numero_os, estado_os, cliente, sede, direccion, hora_programada, lat_ref, lon_ref, radio_m,
--   precision_max_m, salida_en, llegada_en, llegada_lat, llegada_lon, llegada_precision, llegada_distancia, llegada_resultado,
--   puede_registrar, motivo_no_registra).
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerLlegadaMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerLlegadaMovil(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT
)
proc: BEGIN
    DECLARE v_estado     VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_salida_utc DATETIME;
    DECLARE v_radio      DECIMAL(18,6);
    DECLARE v_pmax       DECIMAL(18,6);
    DECLARE v_lat_ref    DECIMAL(10,7);
    DECLARE v_lon_ref    DECIMAL(10,7);
    DECLARE v_o_lat      DECIMAL(10,7) DEFAULT NULL;
    DECLARE v_o_lon      DECIMAL(10,7) DEFAULT NULL;
    DECLARE v_ll_utc     DATETIME;
    DECLARE v_ll_lat     DECIMAL(10,7);
    DECLARE v_ll_lon     DECIMAL(10,7);
    DECLARE v_ll_prec    DECIMAL(8,1);
    DECLARE v_ll_dist    INT;
    DECLARE v_puede      TINYINT DEFAULT 0;

    SELECT os.estado INTO v_estado
    FROM   orden_servicio os
    WHERE  os.id_os = p_id_os AND os.eliminado_en IS NULL
      AND  (os.id_tecnico_principal = p_id_usuario
            OR EXISTS (SELECT 1 FROM os_personal op
                       WHERE op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL));

    IF v_estado IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio no encontrado o no asignado a tu usuario.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_LeerParametroProgramacion('LLEGADA_RADIO_METROS', 200, v_radio);
    CALL SP_LeerParametroProgramacion('LLEGADA_PRECISION_MAX_METROS', 100, v_pmax);

    SELECT MAX(e.timestamp_utc) INTO v_salida_utc
    FROM   evento_campo e
    JOIN   tabla_maestra m ON m.IdMaestro = 29 AND m.IdEmpresa = 1 AND m.Num1 = e.id_tipo_evento AND m.String2 = 'SALIDA_BASE'
    WHERE  e.id_os = p_id_os AND e.eliminado_en IS NULL;

    SELECT COALESCE(sc.latitud, s.latitud, sc2.latitud, os.latitud_llegada), COALESCE(sc.longitud, s.longitud, sc2.longitud, os.longitud_llegada) INTO v_lat_ref, v_lon_ref
    FROM   orden_servicio os
    LEFT JOIN sede_cliente sc  ON sc.id_sede = os.id_sede AND sc.SoftDelete = 0
    LEFT JOIN sede s           ON s.id_sede = os.id_sede AND s.id_cliente = os.id_cliente AND s.eliminado_en IS NULL
    LEFT JOIN requerimiento rq ON rq.id_requerimiento = os.id_requerimiento
    LEFT JOIN sede_cliente sc2 ON sc2.id_sede = rq.id_sede AND sc2.SoftDelete = 0
    WHERE  os.id_os = p_id_os;

    -- Punto de salida (HU-20): la coordenada del evento «Salida» de este viaje
    SELECT e.latitud, e.longitud INTO v_o_lat, v_o_lon
    FROM   evento_campo e
    JOIN   tabla_maestra m ON m.IdMaestro = 29 AND m.IdEmpresa = 1 AND m.Num1 = e.id_tipo_evento AND m.String2 = 'SALIDA_BASE'
    WHERE  e.id_os = p_id_os AND e.eliminado_en IS NULL AND e.latitud IS NOT NULL AND e.longitud IS NOT NULL
    ORDER BY e.timestamp_utc DESC, e.id_evento DESC LIMIT 1;

    SELECT e.timestamp_utc, e.latitud, e.longitud, e.precision_metros, e.distancia_metros INTO v_ll_utc, v_ll_lat, v_ll_lon, v_ll_prec, v_ll_dist
    FROM   evento_campo e
    JOIN   tabla_maestra m ON m.IdMaestro = 29 AND m.IdEmpresa = 1 AND m.Num1 = e.id_tipo_evento AND m.String2 = 'LLEGADA'
    WHERE  e.id_os = p_id_os AND e.eliminado_en IS NULL AND e.timestamp_utc >= IFNULL(v_salida_utc, '1000-01-01')
    ORDER BY e.timestamp_utc DESC, e.id_evento DESC LIMIT 1;

    SET v_puede = IF(v_estado = 'en_ruta' AND v_ll_utc IS NULL, 1, 0);

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT os.id_os,
           os.numero                                                         AS numero_os,
           os.estado                                                         AS estado_os,
           COALESCE(NULLIF(c.nombre_comercial, ''), c.razon_social)          AS cliente,
           sc.nombre                                                         AS sede,
           sc.direccion_exacta                                               AS direccion,
           TIME_FORMAT(os.hora_inicio, '%H:%i')                              AS hora_programada,
           v_lat_ref                                                         AS lat_ref,
           v_lon_ref                                                         AS lon_ref,
           v_o_lat                                                           AS origen_lat,
           v_o_lon                                                           AS origen_lon,
           ROUND(v_radio)                                                    AS radio_m,
           ROUND(v_pmax)                                                     AS precision_max_m,
           IF(v_salida_utc IS NULL, NULL, CONVERT_TZ(v_salida_utc, '+00:00', '-05:00')) AS salida_en,
           IF(v_ll_utc IS NULL, NULL, CONVERT_TZ(v_ll_utc, '+00:00', '-05:00'))         AS llegada_en,
           v_ll_lat                                                          AS llegada_lat,
           v_ll_lon                                                          AS llegada_lon,
           v_ll_prec                                                         AS llegada_precision,
           v_ll_dist                                                         AS llegada_distancia,
           IF(v_ll_utc IS NULL, NULL, IF(v_ll_dist IS NULL, 'sin_referencia', 'valida')) AS llegada_resultado,
           v_puede                                                           AS puede_registrar,
           CASE WHEN v_puede = 1 THEN NULL
                WHEN v_ll_utc IS NOT NULL THEN 'Ya registraste tu llegada.'
                WHEN v_estado IN ('programada', 'reprogramada') THEN 'Primero inicia el traslado desde la validación antes de salir.'
                ELSE 'La llegada se registra durante el traslado (servicio en ruta).' END AS motivo_no_registra
    FROM   orden_servicio os
    LEFT JOIN cliente      c  ON c.id_cliente = os.id_cliente
    LEFT JOIN sede_cliente sc ON sc.id_sede   = os.id_sede
    WHERE  os.id_os = p_id_os;
END$$

DELIMITER ;
