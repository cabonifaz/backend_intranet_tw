-- ============================================================
-- SP_RegistrarLlegadaMovil  (App Mobile HU-06 — Registro de llegada y Hard Stop · escritura)
-- El técnico confirma su llegada a la planta del cliente. Se registra el GPS, su precisión y la hora (nada más).
--   - El técnico sale del token; la OS debe ser suya (principal o personal) y estar EN RUTA (traslado iniciado).
--   - La ubicación se evalúa AQUÍ (SP_EvaluarLlegadaMovil), no se confía en lo que la app mostró: fuera del radio permitido o con la
--     precisión del GPS demasiado baja NO se registra (el técnico puede volver a capturar). Sin coordenada de la planta se registra
--     sin validar la distancia y queda anotado en el evento.
--   - Escribe lo mismo que el cambio manual "llegada" del Asistente, para que la bandeja de Seguimiento Operativo lo lea igual:
--     evento_campo LLEGADA (GPS, precisión, distancia), orden_servicio.hora_llegada_real y latitud/longitud_llegada. La OS sigue "en ruta"
--     (la bandeja la muestra "en planta"); pasa a "en ejecución" al iniciar el trabajo.
--   - Fuera del radio SOLO se registra si Jefatura aprobó la llegada forzada (SP_SolicitarLlegadaForzadaMovil / SP_ResolverLlegadaForzada): la nota del evento lo dice y la aprobación se usa una vez.
--   - Una sola llegada por viaje (evento posterior a la última SALIDA_BASE): repetir el envío responde éxito con la ya registrada
--     (la app reintenta si la respuesta no le llegó).
--   - Sin conexión: la app guarda la llegada en el teléfono y la envía al recuperar la señal con la hora en que se confirmó
--     (p_capturado_utc, UTC del teléfono; solo se respeta si no es futura —tolerancia 5 min— ni tiene más de 24 h). La distancia se evalúa
--     con el GPS capturado, así que el resultado es el mismo que habría tenido en el momento.
--   - Deja el registro en auditoria_evento.
-- Resultados: 1 mensaje; 2 la llegada (id_evento, llegada_en, distancia_m, precision_m, resultado, ya_registrada, diferida).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_RegistrarLlegadaMovil;

DELIMITER $$

CREATE PROCEDURE SP_RegistrarLlegadaMovil(
    IN p_id_usuario    BIGINT,
    IN p_id_os         BIGINT,
    IN p_latitud       DECIMAL(10,7),
    IN p_longitud      DECIMAL(10,7),
    IN p_precision     DECIMAL(8,1),
    IN p_capturado_utc DATETIME
)
proc: BEGIN
    DECLARE v_estado     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_numero     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tipo_evt   INT;
    DECLARE v_salida_utc DATETIME;
    DECLARE v_id_evt     BIGINT DEFAULT NULL;
    DECLARE v_ll_utc     DATETIME;
    DECLARE v_ll_dist    INT;
    DECLARE v_ll_prec    DECIMAL(8,1);
    DECLARE v_ahora_utc  DATETIME;
    DECLARE v_capt_utc   DATETIME;
    DECLARE v_reg_utc    DATETIME;
    DECLARE v_reg_lima   DATETIME;
    DECLARE v_diferida   TINYINT DEFAULT 0;
    DECLARE v_ya         TINYINT DEFAULT 0;
    DECLARE v_resultado  VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_registrable TINYINT;
    DECLARE v_distancia  INT;
    DECLARE v_radio      INT;
    DECLARE v_pmax       INT;
    DECLARE v_lat_ref    DECIMAL(10,7);
    DECLARE v_lon_ref    DECIMAL(10,7);
    DECLARE v_mensaje    VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_notas      VARCHAR(1000) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    -- ── Datos que llegan ─────────────────────────────────────────────────────────────────────────
    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio no encontrado o no asignado a tu usuario.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF p_latitud IS NULL OR p_longitud IS NULL OR p_latitud NOT BETWEEN -90 AND 90 OR p_longitud NOT BETWEEN -180 AND 180
       OR (p_latitud = 0 AND p_longitud = 0) THEN
        SELECT 1 AS IdTipoMensaje, 'La ubicación GPS no es válida: activa el GPS e inténtalo de nuevo.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF p_precision IS NULL OR p_precision < 0 OR p_precision > 5000 THEN
        SELECT 1 AS IdTipoMensaje, 'La precisión del GPS no es válida.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Hora de registro: la del servidor, salvo una llegada guardada sin conexión (la hora del teléfono, sin futuro ni más de 24 h)
    SET v_ahora_utc = UTC_TIMESTAMP();
    SET v_capt_utc  = v_ahora_utc;
    IF p_capturado_utc IS NOT NULL AND p_capturado_utc >= v_ahora_utc - INTERVAL 24 HOUR AND p_capturado_utc <= v_ahora_utc + INTERVAL 5 MINUTE THEN
        SET v_capt_utc = LEAST(p_capturado_utc, v_ahora_utc);
    END IF;
    SET v_diferida = IF(v_capt_utc < v_ahora_utc - INTERVAL 2 MINUTE, 1, 0);
    SET v_reg_utc  = IF(v_diferida = 1, v_capt_utc, v_ahora_utc);
    SET v_reg_lima = v_reg_utc - INTERVAL 5 HOUR;

    START TRANSACTION;

    -- La OS debe ser del técnico del token
    SELECT os.estado, os.numero INTO v_estado, v_numero
    FROM   orden_servicio os
    WHERE  os.id_os = p_id_os AND os.eliminado_en IS NULL
      AND  (os.id_tecnico_principal = p_id_usuario
            OR EXISTS (SELECT 1 FROM os_personal op
                       WHERE op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL))
    FOR UPDATE;

    IF v_estado IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Servicio no encontrado o no asignado a tu usuario.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT m.Num1 INTO v_tipo_evt
    FROM   tabla_maestra m
    WHERE  m.IdMaestro = 29 AND m.IdEmpresa = 1 AND m.String2 = 'LLEGADA' AND m.eliminado_en IS NULL
    LIMIT 1;
    IF v_tipo_evt IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'El hito de campo "Llegada a planta" no está configurado.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- ¿Ya hay llegada en este viaje? (posterior a la última salida)
    SELECT MAX(e.timestamp_utc) INTO v_salida_utc
    FROM   evento_campo e
    JOIN   tabla_maestra m ON m.IdMaestro = 29 AND m.IdEmpresa = 1 AND m.Num1 = e.id_tipo_evento AND m.String2 = 'SALIDA_BASE'
    WHERE  e.id_os = p_id_os AND e.eliminado_en IS NULL;

    SELECT e.id_evento, e.timestamp_utc, e.distancia_metros, e.precision_metros INTO v_id_evt, v_ll_utc, v_ll_dist, v_ll_prec
    FROM   evento_campo e
    WHERE  e.id_os = p_id_os AND e.id_tipo_evento = v_tipo_evt AND e.eliminado_en IS NULL
      AND  e.timestamp_utc >= IFNULL(v_salida_utc, '1000-01-01')
    ORDER BY e.timestamp_utc DESC, e.id_evento DESC LIMIT 1;

    IF v_id_evt IS NOT NULL THEN
        SET v_ya = 1;
        SET v_resultado = IF(v_ll_dist IS NULL, 'sin_referencia', 'valida');
        SET v_distancia = v_ll_dist;
    ELSE
        IF v_estado IN ('programada', 'reprogramada') THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, 'Primero inicia el traslado desde la validación antes de salir.' AS Mensaje;
            LEAVE proc;
        END IF;
        IF v_estado <> 'en_ruta' THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje,
                   IF(v_estado IN ('en_ejecucion', 'pausada'), 'El servicio ya está en ejecución.', 'La llegada solo se registra con el servicio en ruta.') AS Mensaje;
            LEAVE proc;
        END IF;

        -- Hard Stop: la ubicación se evalúa aquí
        CALL SP_EvaluarLlegadaMovil(p_id_os, p_latitud, p_longitud, p_precision, v_resultado, v_registrable, v_distancia, v_radio, v_pmax,
                                    v_lat_ref, v_lon_ref, v_mensaje);
        IF v_registrable = 0 THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, v_mensaje AS Mensaje;
            LEAVE proc;
        END IF;

        SET v_notas = LEFT(CONCAT(
            CASE v_resultado
                WHEN 'valida'     THEN CONCAT('Llegada validada por GPS a ', v_distancia, ' m de la planta (± ', ROUND(p_precision), ' m).')
                WHEN 'autorizada' THEN CONCAT('Llegada FORZADA: a ', v_distancia, ' m de la planta (fuera del radio de ', v_radio, ' m), autorizada por Jefatura.')
                ELSE 'Llegada sin referencia GPS de la planta: no se validó la distancia.' END,
            IF(v_diferida = 1, ' Registrada sin conexión y enviada después.', '')), 1000);

        INSERT INTO evento_campo (id_os, id_usuario, id_tipo_evento, latitud, longitud, precision_metros, distancia_metros, timestamp_utc, sincronizado, notas, creado_por)
        VALUES (p_id_os, p_id_usuario, v_tipo_evt, p_latitud, p_longitud, p_precision, v_distancia, v_reg_utc, 1, v_notas, p_id_usuario);
        SET v_id_evt = LAST_INSERT_ID();
        SET v_ll_utc = v_reg_utc;
        SET v_ll_prec = p_precision;

        UPDATE orden_servicio
        SET    hora_llegada_real = TIME(v_reg_lima), latitud_llegada = p_latitud, longitud_llegada = p_longitud,
               modificado_por = p_id_usuario, modificado_en = NOW()
        WHERE  id_os = p_id_os;

        -- La aprobación de la llegada forzada se usa una sola vez
        IF v_resultado = 'autorizada' THEN
            UPDATE llegada_forzada_os SET usada_en = NOW(), modificado_por = p_id_usuario
            WHERE  id_os = p_id_os AND estado = 'aprobada' AND usada_en IS NULL AND eliminado_en IS NULL;
        END IF;

        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
        VALUES ('orden_servicio', p_id_os, 'registrar_llegada', v_estado, v_estado,
                LEFT(CONCAT('Llegada a planta registrada en ', v_numero, ': ', v_notas), 900),
                p_id_usuario, NOW(),
                JSON_OBJECT('id_evento', v_id_evt, 'resultado', v_resultado, 'distancia_m', v_distancia, 'precision_m', p_precision, 'diferida', v_diferida = 1));
    END IF;

    COMMIT;

    SELECT 2 AS IdTipoMensaje, IF(v_ya = 1, 'Ya registraste tu llegada.', 'Llegada registrada. Ya puedes ver tus objetivos.') AS Mensaje;
    SELECT v_id_evt AS id_evento, CONVERT_TZ(v_ll_utc, '+00:00', '-05:00') AS llegada_en, v_distancia AS distancia_m, v_ll_prec AS precision_m,
           v_resultado AS resultado, v_ya AS ya_registrada, v_diferida AS diferida;
END$$

DELIMITER ;
