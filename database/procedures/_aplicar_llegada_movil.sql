-- Aplicar en la base (migración 97 + procedimientos de la HU-06 y del Seguimiento Operativo, sin datos de prueba). Ejecutar completo con Alt+X. NO subir al repositorio.

-- ============================================================
-- Migración 97 — Registro de llegada con validación GPS desde la app móvil (App Mobile HU-06)
--   1. evento_campo: precisión del GPS (± m) y distancia (m) a la planta del cliente al registrar la llegada.
--      La llegada es un evento LLEGADA (TIPO_EVENTO_CAMPO) con la hora, el GPS y estos dos datos; la bandeja de Seguimiento Operativo
--      ya lee ese evento (fase "en planta", hito "Llegada confirmada", mapa GPS).
--   2. Parámetros (PARAMETRO_PROGRAMACION): radio permitido para confirmar la llegada (200 m) y precisión máxima del GPS (100 m).
--   No borra ni cambia datos existentes. IDEMPOTENTE. Requiere la migración 90.
-- ============================================================

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'evento_campo' AND COLUMN_NAME = 'precision_metros'),
    'ALTER TABLE evento_campo ADD COLUMN precision_metros DECIMAL(8,1) NULL AFTER longitud', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'evento_campo' AND COLUMN_NAME = 'distancia_metros'),
    'ALTER TABLE evento_campo ADD COLUMN distancia_metros INT NULL AFTER precision_metros', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- ── Parámetros ────────────────────────────────────────────────────────────────────────────
SET @id_param := (SELECT MAX(IdMaestro) FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROGRAMACION');
SET @id_param := IFNULL(@id_param, (SELECT MAX(IdMaestro) + 1 FROM tabla_maestra));

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, Num2, String1, String2)
SELECT 1, @id_param, 'PARAMETRO_PROGRAMACION',
       (SELECT IFNULL(MAX(t.Num1), 0) + 1 FROM tabla_maestra t WHERE t.IdMaestro = @id_param AND t.IdEmpresa = 1),
       200, 'Metros máximos a la planta del cliente para confirmar la llegada desde la app', 'LLEGADA_RADIO_METROS'
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra t WHERE t.Descripcion = 'PARAMETRO_PROGRAMACION' AND t.IdEmpresa = 1 AND t.String2 = 'LLEGADA_RADIO_METROS');

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, Num2, String1, String2)
SELECT 1, @id_param, 'PARAMETRO_PROGRAMACION',
       (SELECT IFNULL(MAX(t.Num1), 0) + 1 FROM tabla_maestra t WHERE t.IdMaestro = @id_param AND t.IdEmpresa = 1),
       100, 'Precisión máxima del GPS (± metros) para confirmar la llegada desde la app', 'LLEGADA_PRECISION_MAX_METROS'
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra t WHERE t.Descripcion = 'PARAMETRO_PROGRAMACION' AND t.IdEmpresa = 1 AND t.String2 = 'LLEGADA_PRECISION_MAX_METROS');

-- ── Verificación ─────────────────────────────────────────────────────────────
SELECT 'Migración 97 (debe ser 4)' AS verificacion,
       (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'evento_campo' AND COLUMN_NAME IN ('precision_metros', 'distancia_metros'))
     + (SELECT COUNT(*) FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROGRAMACION' AND IdEmpresa = 1 AND String2 IN ('LLEGADA_RADIO_METROS', 'LLEGADA_PRECISION_MAX_METROS')) AS valor;

-- ============================================================
-- SP_EvaluarLlegadaMovil  (App Mobile HU-06 — apoyo, no es un endpoint)
-- Regla de la llegada validada por GPS, UNA sola vez (la usan la validación y el registro). Solo lectura.
--   Referencia = coordenada de la sede del cliente (sede.latitud/longitud); si la sede no la tiene, la llegada ya registrada de la OS
--   (orden_servicio.latitud_llegada/longitud_llegada), igual que la bandeja de Seguimiento Operativo.
--   Parámetros (PARAMETRO_PROGRAMACION, migración 97): LLEGADA_RADIO_METROS (200) y LLEGADA_PRECISION_MAX_METROS (100).
--   Resultado:
--     precision_baja  ± de la precisión supera el máximo: no se puede registrar (hay que volver a capturar en un lugar abierto)
--     sin_referencia  la planta no tiene coordenada: se puede registrar, queda sin validar distancia
--     valida          dentro del radio permitido
--     fuera_rango     fuera del radio: no se puede registrar
--   p_registrable: 1 = se puede confirmar la llegada. p_mensaje: texto para el técnico. Distancia por Haversine (m).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_EvaluarLlegadaMovil;

DELIMITER $$

CREATE PROCEDURE SP_EvaluarLlegadaMovil(
    IN  p_id_os          BIGINT,
    IN  p_latitud        DECIMAL(10,7),
    IN  p_longitud       DECIMAL(10,7),
    IN  p_precision      DECIMAL(8,1),
    OUT p_resultado      VARCHAR(20),
    OUT p_registrable    TINYINT,
    OUT p_distancia      INT,
    OUT p_radio          INT,
    OUT p_precision_max  INT,
    OUT p_lat_ref        DECIMAL(10,7),
    OUT p_lon_ref        DECIMAL(10,7),
    OUT p_mensaje        VARCHAR(250)
)
BEGIN
    DECLARE v_radio DECIMAL(18,6);
    DECLARE v_pmax  DECIMAL(18,6);

    CALL SP_LeerParametroProgramacion('LLEGADA_RADIO_METROS', 200, v_radio);
    CALL SP_LeerParametroProgramacion('LLEGADA_PRECISION_MAX_METROS', 100, v_pmax);
    SET p_radio         = ROUND(v_radio);
    SET p_precision_max = ROUND(v_pmax);
    SET p_distancia     = NULL;
    SET p_lat_ref       = NULL;
    SET p_lon_ref       = NULL;

    SELECT COALESCE(s.latitud, os.latitud_llegada), COALESCE(s.longitud, os.longitud_llegada) INTO p_lat_ref, p_lon_ref
    FROM   orden_servicio os
    LEFT JOIN sede s ON s.id_sede = os.id_sede AND s.id_cliente = os.id_cliente AND s.eliminado_en IS NULL
    WHERE  os.id_os = p_id_os;

    IF p_precision IS NOT NULL AND p_precision > p_precision_max THEN
        SET p_resultado   = 'precision_baja';
        SET p_registrable = 0;
        SET p_mensaje     = CONCAT('La señal GPS es débil (± ', ROUND(p_precision), ' m; máximo ', p_precision_max,
                                   ' m). Sal a un lugar abierto y vuelve a capturar tu ubicación.');
    ELSEIF p_lat_ref IS NULL OR p_lon_ref IS NULL THEN
        SET p_resultado   = 'sin_referencia';
        SET p_registrable = 1;
        SET p_mensaje     = 'La planta no tiene coordenadas registradas: tu llegada se registrará sin validar la distancia y quedará marcada para Operaciones.';
    ELSE
        SET p_distancia = ROUND(6371000 * 2 * ASIN(SQRT(POW(SIN(RADIANS(p_lat_ref - p_latitud) / 2), 2)
                          + COS(RADIANS(p_latitud)) * COS(RADIANS(p_lat_ref)) * POW(SIN(RADIANS(p_lon_ref - p_longitud) / 2), 2))));
        IF p_distancia <= p_radio THEN
            SET p_resultado   = 'valida';
            SET p_registrable = 1;
            SET p_mensaje     = CONCAT('Te encuentras dentro del rango permitido (a ', FORMAT(p_distancia, 0), ' m de la planta).');
        ELSE
            SET p_resultado   = 'fuera_rango';
            SET p_registrable = 0;
            SET p_mensaje     = CONCAT('Estás a ', FORMAT(p_distancia, 0), ' m de la planta (máximo ', p_radio, ' m). Acércate para registrar tu llegada.');
        END IF;
    END IF;
END$$

DELIMITER ;

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

    SELECT COALESCE(s.latitud, os.latitud_llegada), COALESCE(s.longitud, os.longitud_llegada) INTO v_lat_ref, v_lon_ref
    FROM   orden_servicio os
    LEFT JOIN sede s ON s.id_sede = os.id_sede AND s.id_cliente = os.id_cliente AND s.eliminado_en IS NULL
    WHERE  os.id_os = p_id_os;

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

-- ============================================================
-- SP_ValidarLlegadaMovil  (App Mobile HU-06 — compara la ubicación con la de la planta; NO registra nada)
-- La app lo llama cada vez que captura una ubicación para pintar "Ubicación válida" / "Fuera del rango permitido" y habilitar o bloquear
-- "Confirmar llegada". La OS debe ser del técnico del token. La regla vive en SP_EvaluarLlegadaMovil; al confirmar, SP_RegistrarLlegadaMovil
-- vuelve a evaluar (la app nunca decide).
-- Resultados: 1 mensaje · 2 una fila (resultado, registrable, distancia_m, radio_m, precision_m, mensaje).
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ValidarLlegadaMovil;

DELIMITER $$

CREATE PROCEDURE SP_ValidarLlegadaMovil(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT,
    IN p_latitud    DECIMAL(10,7),
    IN p_longitud   DECIMAL(10,7),
    IN p_precision  DECIMAL(8,1)
)
proc: BEGIN
    DECLARE v_existe     TINYINT DEFAULT 0;
    DECLARE v_resultado  VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_registrable TINYINT;
    DECLARE v_distancia  INT;
    DECLARE v_radio      INT;
    DECLARE v_pmax       INT;
    DECLARE v_lat_ref    DECIMAL(10,7);
    DECLARE v_lon_ref    DECIMAL(10,7);
    DECLARE v_mensaje    VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    SELECT IF(COUNT(*) > 0, 1, 0) INTO v_existe
    FROM   orden_servicio os
    WHERE  os.id_os = p_id_os AND os.eliminado_en IS NULL
      AND  (os.id_tecnico_principal = p_id_usuario
            OR EXISTS (SELECT 1 FROM os_personal op
                       WHERE op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL));
    IF v_existe = 0 THEN
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

    CALL SP_EvaluarLlegadaMovil(p_id_os, p_latitud, p_longitud, p_precision, v_resultado, v_registrable, v_distancia, v_radio, v_pmax,
                                v_lat_ref, v_lon_ref, v_mensaje);

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;
    SELECT v_resultado AS resultado, v_registrable AS registrable, v_distancia AS distancia_m, v_radio AS radio_m,
           p_precision AS precision_m, v_mensaje AS mensaje;
END$$

DELIMITER ;

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
            IF(v_resultado = 'valida',
               CONCAT('Llegada validada por GPS a ', v_distancia, ' m de la planta (± ', ROUND(p_precision), ' m).'),
               'Llegada sin referencia GPS de la planta: no se validó la distancia.'),
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

-- ============================================================
-- SP_ObtenerEtaDemorasMovil  (App Mobile HU-05 — apoyo, no es un endpoint)
-- Reglas de la hora estimada de llegada (ETA) y del inicio del trabajo, UNA sola vez (las usan la consulta y el registro de demoras).
-- Todas las horas son de Lima (UTC-5).
--   p_eta_original   : hora programada del servicio (fecha_ejecucion + hora_inicio). Es la ETA de llegada original.
--   p_minutos_llegada: suma de las demoras de tipo "llegada" ya registradas. ETA vigente = ETA original + estos minutos.
--   p_llegada_en     : cuándo el técnico registró su llegada a la planta (evento LLEGADA, HU-06) en este viaje (posterior a la última
--                      SALIDA_BASE); NULL si aún no la registró.
--   p_inicio_vigente : hora de inicio del trabajo prevista tras la última demora de tipo "ingreso"; NULL si no hay.
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerEtaDemorasMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerEtaDemorasMovil(
    IN  p_id_os           BIGINT,
    OUT p_eta_original    DATETIME,
    OUT p_minutos_llegada INT,
    OUT p_llegada_en      DATETIME,
    OUT p_inicio_vigente  DATETIME
)
BEGIN
    SET p_eta_original    = NULL;
    SET p_minutos_llegada = 0;
    SET p_llegada_en      = NULL;
    SET p_inicio_vigente  = NULL;

    SELECT TIMESTAMP(os.fecha_ejecucion, os.hora_inicio) INTO p_eta_original
    FROM   orden_servicio os
    WHERE  os.id_os = p_id_os AND os.eliminado_en IS NULL;

    SELECT IFNULL(SUM(d.duracion_minutos), 0) INTO p_minutos_llegada
    FROM   demora_registro d
    WHERE  d.id_os = p_id_os AND d.tipo = 'llegada' AND d.eliminado_en IS NULL;

    SELECT MAX(CONVERT_TZ(e.timestamp_utc, '+00:00', '-05:00')) INTO p_llegada_en
    FROM   evento_campo e
    JOIN   tabla_maestra m ON m.IdMaestro = 29 AND m.IdEmpresa = 1 AND m.Num1 = e.id_tipo_evento AND m.String2 = 'LLEGADA'
    WHERE  e.id_os = p_id_os AND e.eliminado_en IS NULL
      AND  e.timestamp_utc >= IFNULL((SELECT MAX(s.timestamp_utc) FROM evento_campo s
                                      JOIN tabla_maestra ms ON ms.IdMaestro = 29 AND ms.IdEmpresa = 1 AND ms.Num1 = s.id_tipo_evento AND ms.String2 = 'SALIDA_BASE'
                                      WHERE s.id_os = p_id_os AND s.eliminado_en IS NULL), '1000-01-01');

    SELECT d.eta_recalculada INTO p_inicio_vigente
    FROM   demora_registro d
    WHERE  d.id_os = p_id_os AND d.tipo = 'ingreso' AND d.eliminado_en IS NULL
    ORDER BY d.id_demora DESC LIMIT 1;
END$$

DELIMITER ;

-- HU-51 (Sprint 5) / App Mobile: registra la posición GPS del técnico mientras su servicio está en curso. Alimenta la bandeja de seguimiento
-- (ubicacion_tecnico): última ubicación "hace X min", Pérdida de contacto, GPS parado y Proximidad.
-- Reglas: la OS debe ser del técnico del token (principal o personal) y estar en ruta, en ejecución o en pausa; coordenadas dentro de rango y
-- distintas de (0,0); precisión 0 a 5000 m. Antirrebote: si ya hay una posición del técnico de hace menos de 10 s no se guarda otra (responde OK).
-- Limpieza: al guardar se borran (máx. 500) las posiciones de ese técnico con más de 3 días. NO cambia el estado de la OS.
-- Opcionales (los envía la app; un valor fuera de rango se guarda como NULL, no rechaza la posición): velocidad (km/h) y altitud (m).
DROP PROCEDURE IF EXISTS SP_RegistrarUbicacionMovil;

DELIMITER $$

CREATE PROCEDURE SP_RegistrarUbicacionMovil(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT,
    IN p_latitud    DECIMAL(10,7),
    IN p_longitud   DECIMAL(10,7),
    IN p_precision  DECIMAL(8,1),
    IN p_velocidad  DECIMAL(6,1),
    IN p_altitud    DECIMAL(8,1)
)
proc: BEGIN
    DECLARE v_estado  VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_ultima  DATETIME;
    DECLARE v_guardada TINYINT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio no encontrado o no asignado a tu usuario.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF p_latitud IS NULL OR p_longitud IS NULL OR p_latitud NOT BETWEEN -90 AND 90 OR p_longitud NOT BETWEEN -180 AND 180
       OR (p_latitud = 0 AND p_longitud = 0) THEN
        SELECT 1 AS IdTipoMensaje, 'La ubicación no es válida.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF p_precision IS NOT NULL AND (p_precision < 0 OR p_precision > 5000) THEN
        SELECT 1 AS IdTipoMensaje, 'La precisión de la ubicación no es válida.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT os.estado INTO v_estado
    FROM orden_servicio os
    WHERE os.id_os = p_id_os AND os.eliminado_en IS NULL
      AND (os.id_tecnico_principal = p_id_usuario
           OR EXISTS (SELECT 1 FROM os_personal op WHERE op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL));
    IF v_estado IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio no encontrado o no asignado a tu usuario.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_estado NOT IN ('en_ruta', 'en_ejecucion', 'pausada') THEN
        SELECT 1 AS IdTipoMensaje, 'La ubicación solo se registra mientras el servicio está en curso.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT MAX(timestamp_utc) INTO v_ultima FROM ubicacion_tecnico WHERE id_usuario = p_id_usuario;
    IF v_ultima IS NULL OR v_ultima < DATE_SUB(UTC_TIMESTAMP(), INTERVAL 10 SECOND) THEN
        INSERT INTO ubicacion_tecnico (id_usuario, id_os, latitud, longitud, precision_m, velocidad_kmh, altitud_m, timestamp_utc)
        VALUES (p_id_usuario, p_id_os, p_latitud, p_longitud, IF(p_precision IS NULL, NULL, ROUND(p_precision)),
                IF(p_velocidad BETWEEN 0 AND 400, p_velocidad, NULL), IF(p_altitud BETWEEN -500 AND 9000, p_altitud, NULL), UTC_TIMESTAMP());
        SET v_guardada = 1;
        DELETE FROM ubicacion_tecnico WHERE id_usuario = p_id_usuario AND timestamp_utc < DATE_SUB(UTC_TIMESTAMP(), INTERVAL 3 DAY) LIMIT 500;
    END IF;

    SELECT 2 AS IdTipoMensaje, IF(v_guardada = 1, 'Ubicación registrada.', 'Ubicación reciente ya registrada.') AS Mensaje;
    SELECT v_guardada AS Guardada;
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
--   perdida_contacto (crítica) · gps_parado (advertencia) · sin_ingreso_post_llegada (advertencia) · sin_iniciar_servicio (advertencia)
--   · proximidad (info) · incidente (crítica)
-- Tablas temporales (MySQL no permite abrir dos veces la misma temporal en una consulta):
--   tmp_sg_cfg (1 fila: hoy, ahora y umbrales) · tmp_sg_os (un servicio por fila) · tmp_sg_ev (eventos de campo del día por OS)
--   tmp_sg_ut (técnico x servicio) · tmp_sg_tec (un técnico por fila) · tmp_sg_pos (última posición GPS por técnico)
--   tmp_sg_alerta · tmp_sg_hito · tmp_sg_inc (demoras e incidencias unificadas; `fase` = momento de la demora de la app: llegada = en ruta, ingreso = ingreso a planta)
-- Demoras de la app (demora_registro, HU-05): las de llegada corren la hora esperada de llegada (hito) y las de ingreso, la hora esperada de inicio.
-- Requiere las migraciones 85 a 90.
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
        id_tecnico BIGINT, tecnico VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, nombre_pila VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        zona VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        hora_inicio TIME, hora_fin_est TIME, os_estado VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        propuesta VARCHAR(60) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        n_equipos INT DEFAULT 0, n_ejecutados INT DEFAULT 0,
        salida_utc DATETIME, llegada_dt DATETIME, inicio_dt DATETIME, fin_dt DATETIME,
        crit TINYINT DEFAULT 0, n_demoras INT DEFAULT 0, min_dem_lleg INT DEFAULT 0, ing_eta DATETIME,
        estado_seg VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, fase VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, prio INT DEFAULT 9, dist_m INT,
        PRIMARY KEY (id_os)
    );

    INSERT INTO tmp_sg_os (id_os, id_programacion, numero, tipo, id_cliente, razon_social, ruc, id_sede, sede_nombre, sede_direccion, lat_sede, lon_sede,
                           id_tecnico, tecnico, nombre_pila, zona, hora_inicio, hora_fin_est, os_estado, propuesta, n_equipos, n_ejecutados,
                           llegada_dt, fin_dt)
    SELECT os.id_os, p.id_programacion, os.numero, os.tipo, os.id_cliente, c.razon_social, c.ruc, os.id_sede, sc.nombre, sc.direccion_exacta, COALESCE(s.latitud, os.latitud_llegada), COALESCE(s.longitud, os.longitud_llegada),
           p.id_tecnico_principal, TRIM(CONCAT(u.nombre, ' ', u.apellido)), u.nombre, COALESCE(zn.String1, u.sede_operativa),
           p.hora_inicio, p.hora_fin_estimada, os.estado,
           IF(pr.id_propuesta IS NULL, NULL, pr.numero),
           (SELECT COUNT(*) FROM os_equipo e WHERE e.id_os = os.id_os AND e.eliminado_en IS NULL),
           (SELECT COUNT(*) FROM os_equipo e WHERE e.id_os = os.id_os AND e.eliminado_en IS NULL AND e.estado_ejecucion = 'ejecutado'),
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
    WHERE p.eliminado_en IS NULL AND p.estado = 'confirmada' AND p.fecha_ejecucion = v_hoy
      AND os.estado NOT IN ('anulada', 'borrador', 'emitida');

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

-- HU-52 (Sprint 5) Pestaña "Demoras / Incidencias" (solo de esta OS, de hoy): mini-KPIs, tabla y detalle de un registro. SOLO LECTURA.
-- p_clave (opcional): 'd<id>' demora, 'i<id>' incidencia o 'a<id>' demora registrada por el Asistente (HU-53); con clave devuelve solo ese registro con la descripción completa y la foto.
-- Impacto: retrasa | detiene (incidencia crítica = detiene). Origen: tecnico | asistente. La tabla alimenta también la exportación CSV.
-- Momento (demoras de la app): "En ruta (llegar a planta)" o "Ingreso a planta"; Latitud/Longitud = GPS desde donde el técnico la registró.
-- Resultados: 1 mensaje · 2 KPIs (1 fila) · 3 filas.
DROP PROCEDURE IF EXISTS SP_ObtenerIncidenciasServicioRuta;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerIncidenciasServicioRuta(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT,
    IN p_clave      VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_msg VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        CALL SP_LimpiarSeguimientoOperativo();
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF NULLIF(p_clave, '') IS NOT NULL AND p_clave NOT REGEXP '^[dia][0-9]{1,18}$' THEN
        SELECT 1 AS IdTipoMensaje, 'El registro indicado no es válido.' AS Mensaje;
        LEAVE proc;
    END IF;
    CALL SP_PrepararDetalleServicioRuta(p_id_usuario, p_id_os, v_msg);
    IF v_msg IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje;
        LEAVE proc;
    END IF;
    IF NULLIF(p_clave, '') IS NOT NULL AND NOT EXISTS (SELECT 1 FROM tmp_sg_inc i WHERE i.id_os = p_id_os AND i.clave = p_clave) THEN
        CALL SP_LimpiarSeguimientoOperativo();
        SELECT 1 AS IdTipoMensaje, 'El registro no existe en este servicio.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'OK' AS Mensaje;
    SELECT COUNT(*) AS Total, IFNULL(SUM(impacto = 'retrasa'), 0) AS Retrasan, IFNULL(SUM(impacto = 'detiene'), 0) AS Detienen,
           IFNULL(SUM(origen = 'tecnico'), 0) AS PorTecnico, IFNULL(SUM(origen = 'asistente'), 0) AS PorAsistente
    FROM tmp_sg_inc WHERE id_os = p_id_os;

    SELECT i.clave AS Clave, DATE_FORMAT(i.fecha, '%H:%i') AS Hora, i.tipo_codigo AS TipoCodigo, i.tipo AS Tipo,
           IF(NULLIF(p_clave, '') IS NULL, i.descripcion, COALESCE(d.descripcion, n.descripcion, ra.descripcion, i.descripcion)) AS Descripcion,
           i.duracion_min AS DuracionMin, i.impacto AS Impacto, i.origen AS Origen, COALESCE((SELECT TRIM(CONCAT(ua.nombre, ' ', ua.apellido)) FROM usuario ua WHERE ua.id_usuario = ra.id_usuario), i.tecnico) AS Registrador,
           IF(NULLIF(p_clave, '') IS NULL, NULL, COALESCE(d.fotografia_url, ra.evidencia_url)) AS Evidencia, IF(COALESCE(d.fotografia_url, ra.evidencia_url) IS NULL, 0, 1) AS TieneEvidencia,
           CASE i.fase WHEN 'llegada' THEN 'En ruta (llegar a planta)' WHEN 'ingreso' THEN 'Ingreso a planta' END AS Momento,
           d.latitud AS Latitud, d.longitud AS Longitud
    FROM tmp_sg_inc i
    LEFT JOIN demora_registro d ON i.clave = CONCAT('d', d.id_demora)
    LEFT JOIN incidencia_operativa n ON i.clave = CONCAT('i', n.id_incidencia)
    LEFT JOIN registro_asistente ra ON i.clave = CONCAT('a', ra.id_registro)
    WHERE i.id_os = p_id_os AND (NULLIF(p_clave, '') IS NULL OR i.clave = p_clave)
    ORDER BY i.fecha DESC, i.clave;

    CALL SP_LimpiarSeguimientoOperativo();
END$$

DELIMITER ;

-- HU-51 (Sprint 5) Pestaña 4 "Incidencias del Día": demoras e incidencias de hoy en orden cronológico, de todos los técnicos, con sus tarjetas resumen.
-- Origen: Técnico (lo registró el propio técnico desde la app) o Asistente (registro del Asistente de Seguimiento, HU-53). Impacto: Retrasa o Detiene.
-- Filtros: Técnico, Cliente, Zona/Sede, buscador, Tipo (código del catálogo) e Impacto. Las demoras sin impacto registrado cuentan como "Retrasa".
-- Momento (demoras de la app): "En ruta (llegar a planta)" o "Ingreso a planta".
-- Resultados: 1 mensaje, 2 tarjetas, 3 filas.
DROP PROCEDURE IF EXISTS SP_ObtenerIncidenciasSeguimiento;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerIncidenciasSeguimiento(
    IN p_id_usuario BIGINT,
    IN p_id_tecnico BIGINT,
    IN p_id_cliente BIGINT,
    IN p_zona       VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_busqueda   VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_tipo       VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_impacto    VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
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
    IF CHAR_LENGTH(IFNULL(p_zona, '')) > 100 OR CHAR_LENGTH(IFNULL(p_busqueda, '')) > 100 OR CHAR_LENGTH(IFNULL(p_tipo, '')) > 40 THEN
        SELECT 1 AS IdTipoMensaje, 'La zona, la búsqueda o el tipo superan el largo permitido.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF NULLIF(p_impacto, '') IS NOT NULL AND p_impacto NOT IN ('retrasa', 'detiene') THEN
        SELECT 1 AS IdTipoMensaje, 'El impacto no es válido.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_ArmarSeguimientoOperativo();
    CALL SP_FiltrarSeguimientoOperativo(NULL, p_id_cliente, NULL, NULLIF(p_zona, ''), NULLIF(TRIM(p_busqueda), ''));

    DELETE i FROM tmp_sg_inc i
    WHERE (p_id_tecnico IS NOT NULL AND i.id_usuario <> p_id_tecnico)
       OR (NULLIF(p_tipo, '') IS NOT NULL AND i.tipo_codigo <> p_tipo)
       OR (NULLIF(p_impacto, '') IS NOT NULL AND i.impacto <> p_impacto)
       OR i.id_os NOT IN (SELECT f.id_os FROM tmp_sg_f f);

    SELECT 2 AS IdTipoMensaje, 'OK' AS Mensaje;
    SELECT IFNULL(SUM(impacto = 'retrasa'), 0) AS Retrasan, IFNULL(SUM(impacto = 'detiene'), 0) AS Detienen,
           IFNULL(SUM(origen = 'tecnico'), 0) AS RegistradasTecnico, IFNULL(SUM(origen = 'asistente'), 0) AS RegistradasAsistente,
           COUNT(*) AS Total
    FROM tmp_sg_inc;
    SELECT i.clave AS Clave, DATE_FORMAT(i.fecha, '%H:%i') AS Hora, i.id_usuario AS IdUsuario, i.tecnico AS Tecnico, i.iniciales AS Iniciales,
           i.id_os AS IdOs, i.numero AS Numero, i.cliente AS Cliente, i.tipo_codigo AS TipoCodigo, i.tipo AS Tipo, i.descripcion AS Descripcion,
           i.duracion_min AS DuracionMin, i.impacto AS Impacto, i.origen AS Origen,
           CASE i.fase WHEN 'llegada' THEN 'En ruta (llegar a planta)' WHEN 'ingreso' THEN 'Ingreso a planta' END AS Momento
    FROM tmp_sg_inc i
    ORDER BY i.fecha, i.clave
    LIMIT 500;

    CALL SP_LimpiarSeguimientoOperativo();
END$$

DELIMITER ;

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

-- HU-52 (Sprint 5) Pestaña "Mapa GPS": posición actual del técnico, ruta recorrida hoy, pin del cliente con radio de proximidad y panel GPS. SOLO LECTURA.
-- Conexión: sin_senal (sin posición o más del umbral SEG_PERDIDA_CONTACTO_MIN) | gps_parado (mismo punto por SEG_GPS_PARADO_MIN o más) | gps_activo.
-- Velocidad, altitud, satélites y latencia salen de ubicacion_tecnico (migración 91; los envía la app; NULL si no los envía).
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
           u.precision_m AS PrecisionM, u.velocidad_kmh AS VelocidadKmh, u.altitud_m AS AltitudM, u.satelites AS Satelites, u.latencia_ms AS LatenciaMs
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
-- Verificación (solo lectura)
-- ============================================================
-- 1) Columnas y parámetros de la migración 97 (debe salir 4)
SELECT (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'evento_campo' AND COLUMN_NAME IN ('precision_metros', 'distancia_metros'))
     + (SELECT COUNT(*) FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROGRAMACION' AND IdEmpresa = 1 AND String2 IN ('LLEGADA_RADIO_METROS', 'LLEGADA_PRECISION_MAX_METROS')) AS migracion_97_debe_ser_4;

-- 2) Parámetros de la llegada
SELECT String2 AS codigo, Num2 AS valor, String1 AS descripcion
FROM   tabla_maestra
WHERE  Descripcion = 'PARAMETRO_PROGRAMACION' AND IdEmpresa = 1 AND String2 IN ('LLEGADA_RADIO_METROS', 'LLEGADA_PRECISION_MAX_METROS');

-- 3) Procedimientos aplicados (deben salir 11)
SELECT ROUTINE_NAME, LAST_ALTERED
FROM   information_schema.ROUTINES
WHERE  ROUTINE_SCHEMA = DATABASE() AND ROUTINE_TYPE = 'PROCEDURE'
  AND  ROUTINE_NAME IN ('SP_EvaluarLlegadaMovil', 'SP_ObtenerLlegadaMovil', 'SP_ValidarLlegadaMovil', 'SP_RegistrarLlegadaMovil', 'SP_ObtenerEtaDemorasMovil',
                        'SP_RegistrarUbicacionMovil', 'SP_ArmarSeguimientoOperativo', 'SP_ObtenerIncidenciasServicioRuta', 'SP_ObtenerIncidenciasSeguimiento',
                        'SP_ObtenerTimelineServicioRuta', 'SP_ObtenerMapaServicioRuta')
ORDER BY ROUTINE_NAME;

-- 4) SP_RegistrarUbicacionMovil debe tener 7 parámetros (con p_velocidad y p_altitud)
SELECT COUNT(*) AS parametros_de_ubicacion_debe_ser_7
FROM   information_schema.PARAMETERS
WHERE  SPECIFIC_SCHEMA = DATABASE() AND SPECIFIC_NAME = 'SP_RegistrarUbicacionMovil';
