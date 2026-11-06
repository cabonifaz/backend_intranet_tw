-- Aplicar en la base (migración 96 + procedimientos, sin datos de prueba). Ejecutar completo con Alt+X. NO subir al repositorio.

-- ============================================================
-- Migración 96 — Registro de demoras en ruta desde la app móvil (App Mobile HU-05)
--   1. demora_registro: tipo de demora (llegada | ingreso), GPS de quien la registra, y la hora estimada (ETA) antes y después.
--        tipo             llegada = demora durante el traslado (recalcula la ETA de llegada)
--                         ingreso = ya llegó pero no puede ingresar (recalcula el inicio del trabajo)
--        latitud/longitud/precision_metros   GPS capturado al registrar (la hora la pone el servidor)
--        eta_anterior / eta_recalculada      hora de llegada (o de inicio del trabajo) antes y después de esta demora (hora de Lima)
--      La foto (opcional, solo cámara) ya tenía su columna: fotografia_url guarda la ruta en el almacenamiento de archivos.
--   2. Catálogo MOTIVO_DEMORA_RUTA: el ámbito de cada motivo va en String3 (traslado | ingreso | ambos; vacío = ambos).
--      Solo se completa si está vacío, por código (no pisa lo que ya se haya configurado).
--   3. Índice por servicio para listar las demoras de una OS.
--   No borra ni cambia datos existentes. IDEMPOTENTE.
-- ============================================================

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'demora_registro' AND COLUMN_NAME = 'tipo'),
    'ALTER TABLE demora_registro ADD COLUMN tipo ENUM(''llegada'',''ingreso'') NOT NULL DEFAULT ''llegada'' AFTER id_motivo', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'demora_registro' AND COLUMN_NAME = 'latitud'),
    'ALTER TABLE demora_registro ADD COLUMN latitud DECIMAL(10,7) NULL AFTER fotografia_url', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'demora_registro' AND COLUMN_NAME = 'longitud'),
    'ALTER TABLE demora_registro ADD COLUMN longitud DECIMAL(10,7) NULL AFTER latitud', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'demora_registro' AND COLUMN_NAME = 'precision_metros'),
    'ALTER TABLE demora_registro ADD COLUMN precision_metros DECIMAL(8,1) NULL AFTER longitud', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'demora_registro' AND COLUMN_NAME = 'eta_anterior'),
    'ALTER TABLE demora_registro ADD COLUMN eta_anterior DATETIME NULL AFTER precision_metros', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'demora_registro' AND COLUMN_NAME = 'eta_recalculada'),
    'ALTER TABLE demora_registro ADD COLUMN eta_recalculada DATETIME NULL AFTER eta_anterior', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'demora_registro' AND INDEX_NAME = 'ix_demora_os'),
    'CREATE INDEX ix_demora_os ON demora_registro (id_os, tipo, eliminado_en)', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- ── Ámbito de los motivos de demora (String3) ─────────────────────────────────────────────
UPDATE tabla_maestra
SET    String3 = CASE String2
                     WHEN 'TRAFICO'           THEN 'traslado'
                     WHEN 'ACCIDENTE_RUTA'    THEN 'traslado'
                     WHEN 'PROBLEMA_VEHICULO' THEN 'traslado'
                     WHEN 'CLIMA'             THEN 'traslado'
                     WHEN 'ACCESO_DENEGADO'   THEN 'ingreso'
                     WHEN 'ESPERA_CLIENTE'    THEN 'ingreso'
                     WHEN 'OTRO'              THEN 'ambos'
                 END
WHERE  Descripcion = 'MOTIVO_DEMORA_RUTA' AND IdEmpresa = 1
  AND  (String3 IS NULL OR String3 = '')
  AND  String2 IN ('TRAFICO', 'ACCIDENTE_RUTA', 'PROBLEMA_VEHICULO', 'CLIMA', 'ACCESO_DENEGADO', 'ESPERA_CLIENTE', 'OTRO');

-- ============================================================
-- SP_ObtenerEtaDemorasMovil  (App Mobile HU-05 — apoyo, no es un endpoint)
-- Reglas de la hora estimada de llegada (ETA) y del inicio del trabajo, UNA sola vez (las usan la consulta y el registro de demoras).
-- Todas las horas son de Lima (UTC-5).
--   p_eta_original   : hora programada del servicio (fecha_ejecucion + hora_inicio). Es la ETA de llegada original.
--   p_minutos_llegada: suma de las demoras de tipo "llegada" ya registradas. ETA vigente = ETA original + estos minutos.
--   p_llegada_en     : cuándo el técnico registró su llegada a la planta (evento LLEGADA, HU-06); NULL si aún no la registró.
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
    WHERE  e.id_os = p_id_os AND e.eliminado_en IS NULL;

    SELECT d.eta_recalculada INTO p_inicio_vigente
    FROM   demora_registro d
    WHERE  d.id_os = p_id_os AND d.tipo = 'ingreso' AND d.eliminado_en IS NULL
    ORDER BY d.id_demora DESC LIMIT 1;
END$$

DELIMITER ;

-- ============================================================
-- SP_ObtenerDemorasMovil  (App Mobile HU-05 — Registro de demoras en ruta · lectura)
-- Contexto para la pantalla "Registrar demora" de una OS del técnico que inició sesión (el id sale del token):
--   - Quién puede registrar y de qué tipo: "llegada" (llegar a planta) con el servicio EN RUTA y sin llegada registrada;
--     "ingreso" (ingreso a planta) con el servicio en ruta o en ejecución, llegada registrada y sin inicio del trabajo.
--   - Horas (Lima): ETA original, ETA vigente (con las demoras de llegada) e inicio de trabajo previsto (para las de ingreso).
--     Las reglas de las horas están en SP_ObtenerEtaDemorasMovil.
-- Resultados:
--   1. Mensaje
--   2. Contexto (1 fila): id_os, numero_os, estado_os, cliente, sede, salida_en, en_ruta_minutos, llegada_en, en_planta_minutos,
--        eta_original, minutos_demora, eta_vigente, inicio_previsto, ahora, puede_llegada, puede_ingreso, motivo_no_registra
--   3. Motivos del catálogo MOTIVO_DEMORA_RUTA con su ámbito (traslado | ingreso | ambos)
--   4. Demoras ya registradas de la OS (la más reciente primero)
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerDemorasMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerDemorasMovil(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT
)
proc: BEGIN
    DECLARE v_estado     VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_eta_orig   DATETIME;
    DECLARE v_min_lleg   INT DEFAULT 0;
    DECLARE v_llegada    DATETIME;
    DECLARE v_inicio_vig DATETIME;
    DECLARE v_salida     DATETIME;
    DECLARE v_ahora      DATETIME;
    DECLARE v_inicio_trab TINYINT DEFAULT 0;
    DECLARE v_puede_lleg TINYINT DEFAULT 0;
    DECLARE v_puede_ing  TINYINT DEFAULT 0;

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

    SET v_ahora = UTC_TIMESTAMP() - INTERVAL 5 HOUR;

    CALL SP_ObtenerEtaDemorasMovil(p_id_os, v_eta_orig, v_min_lleg, v_llegada, v_inicio_vig);

    SELECT MAX(CONVERT_TZ(e.timestamp_utc, '+00:00', '-05:00')) INTO v_salida
    FROM   evento_campo e
    JOIN   tabla_maestra m ON m.IdMaestro = 29 AND m.IdEmpresa = 1 AND m.Num1 = e.id_tipo_evento AND m.String2 = 'SALIDA_BASE'
    WHERE  e.id_os = p_id_os AND e.eliminado_en IS NULL;

    SELECT IF(COUNT(*) > 0, 1, 0) INTO v_inicio_trab
    FROM   evento_campo e
    JOIN   tabla_maestra m ON m.IdMaestro = 29 AND m.IdEmpresa = 1 AND m.Num1 = e.id_tipo_evento AND m.String2 = 'INICIO_TRABAJO'
    WHERE  e.id_os = p_id_os AND e.eliminado_en IS NULL;

    SET v_puede_lleg = IF(v_estado = 'en_ruta' AND v_llegada IS NULL, 1, 0);
    SET v_puede_ing  = IF(v_estado IN ('en_ruta', 'en_ejecucion') AND v_llegada IS NOT NULL AND v_inicio_trab = 0, 1, 0);

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Contexto
    SELECT os.id_os,
           os.numero                                                         AS numero_os,
           os.estado                                                         AS estado_os,
           COALESCE(NULLIF(c.nombre_comercial, ''), c.razon_social)          AS cliente,
           s.nombre                                                          AS sede,
           v_salida                                                          AS salida_en,
           IF(v_salida IS NOT NULL AND v_llegada IS NULL, GREATEST(TIMESTAMPDIFF(MINUTE, v_salida, v_ahora), 0),
              IF(v_salida IS NOT NULL AND v_llegada IS NOT NULL, GREATEST(TIMESTAMPDIFF(MINUTE, v_salida, v_llegada), 0), NULL)) AS en_ruta_minutos,
           v_llegada                                                         AS llegada_en,
           IF(v_llegada IS NOT NULL, GREATEST(TIMESTAMPDIFF(MINUTE, v_llegada, v_ahora), 0), NULL)                              AS en_planta_minutos,
           v_eta_orig                                                        AS eta_original,
           v_min_lleg                                                        AS minutos_demora,
           IF(v_eta_orig IS NULL, NULL, v_eta_orig + INTERVAL v_min_lleg MINUTE)                                                AS eta_vigente,
           GREATEST(IFNULL(v_inicio_vig, v_ahora), v_ahora)                  AS inicio_previsto,
           v_ahora                                                           AS ahora,
           v_puede_lleg                                                      AS puede_llegada,
           v_puede_ing                                                       AS puede_ingreso,
           CASE WHEN v_puede_lleg = 1 OR v_puede_ing = 1 THEN NULL
                WHEN v_estado IN ('programada', 'reprogramada') THEN 'Las demoras se registran durante el traslado: primero inicia el traslado.'
                WHEN v_estado = 'en_ruta' THEN 'Ya registraste tu llegada: solo puedes registrar demoras de ingreso a planta, si todavía no inicias el trabajo.'
                ELSE 'Las demoras se registran durante el traslado o al ingresar a la planta, antes de iniciar el trabajo.' END AS motivo_no_registra
    FROM   orden_servicio os
    LEFT JOIN cliente      c ON c.id_cliente = os.id_cliente
    LEFT JOIN sede_cliente s ON s.id_sede    = os.id_sede
    WHERE  os.id_os = p_id_os;

    -- 3. Motivos y su ámbito
    SELECT t.Num1 AS id_motivo, t.String1 AS nombre, t.String2 AS codigo, IFNULL(NULLIF(t.String3, ''), 'ambos') AS ambito
    FROM   tabla_maestra t
    WHERE  t.IdMaestro = 15 AND t.IdEmpresa = 1 AND t.eliminado_en IS NULL
    ORDER BY t.Num1;

    -- 4. Demoras de la OS
    SELECT d.id_demora,
           d.tipo,
           m.String1                          AS motivo,
           d.duracion_minutos,
           d.descripcion,
           d.fecha_registro,
           d.eta_anterior,
           d.eta_recalculada,
           IF(d.fotografia_url IS NULL OR d.fotografia_url = '', 0, 1) AS tiene_foto,
           d.latitud,
           d.longitud
    FROM   demora_registro d
    LEFT JOIN tabla_maestra m ON m.IdMaestro = 15 AND m.IdEmpresa = 1 AND m.Num1 = d.id_motivo
    WHERE  d.id_os = p_id_os AND d.eliminado_en IS NULL
    ORDER BY d.fecha_registro DESC, d.id_demora DESC;
END$$

DELIMITER ;

-- ============================================================
-- SP_RegistrarDemoraMovil  (App Mobile HU-05 — Registro de demoras en ruta · escritura)
-- El técnico reporta una demora durante el traslado ("llegar a planta") o al ingresar a la planta ("ingreso a planta").
--   - El técnico sale del token; la OS debe ser suya (principal o personal) y estar en el estado que permite ese tipo:
--       llegada : OS EN RUTA y sin llegada registrada. Recalcula la ETA de llegada.
--       ingreso : OS en ruta o en ejecución, con la llegada registrada y sin inicio del trabajo. Recalcula el inicio del trabajo.
--   - Solo se captura el GPS y la hora (en Lima, UTC-5): la pone el servidor, salvo una demora guardada sin conexión (ver más abajo).
--     Foto opcional (la ruta ya guardada en el almacenamiento de archivos; la valida y guarda el back antes de llamar a este SP).
--   - El tipo de demora (motivo) debe existir en MOTIVO_DEMORA_RUTA y corresponder al ámbito (traslado | ingreso | ambos).
--   - Duración de 1 a 480 minutos. Las horas se recalculan con las reglas de SP_ObtenerEtaDemorasMovil.
--   - Antirrebote: la misma demora (mismo tipo, motivo y duración) del mismo técnico en los últimos 20 s no se duplica: se responde
--     con la ya registrada y sin avisar de nuevo.
--   - Sin conexión: la app guarda la demora en el teléfono y la envía al recuperar la señal, con la hora en que se registró
--     (p_capturado_utc, hora UTC del teléfono). Esa hora solo se respeta si no es futura (tolerancia 5 min) ni tiene más de 24 h; si no,
--     vale la hora del servidor. Una demora "diferida" (llegó más de 2 min después) queda con la hora en que ocurrió y, si el envío se
--     repite (la respuesta se perdió), se reconoce como la misma y no se duplica ni se avisa de nuevo.
--   - Avisa a Operaciones (supervisor o administrador del área Operaciones, o Jefe/Coordinador de Operaciones; si no hay, a los
--     administradores) y deja el registro en auditoria_evento. El impacto queda en 'retrasa' (lo lee el Seguimiento Operativo).
-- Resultados: 1 mensaje; 2 la demora (id_demora, tipo, eta_original, eta_anterior, eta_recalculada, notificados, repetida, diferida).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_RegistrarDemoraMovil;

DELIMITER $$

CREATE PROCEDURE SP_RegistrarDemoraMovil(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT,
    IN p_tipo       VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_motivo  INT,
    IN p_duracion   INT,
    IN p_descripcion VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_latitud    DECIMAL(10,7),
    IN p_longitud   DECIMAL(10,7),
    IN p_precision  DECIMAL(8,1),
    IN p_foto       VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_capturado_utc DATETIME
)
proc: BEGIN
    DECLARE v_tipo       VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_numero     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_motivo     VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_ambito     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tecnico    VARCHAR(210) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_texto      VARCHAR(400) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_eta_orig   DATETIME;
    DECLARE v_min_lleg   INT DEFAULT 0;
    DECLARE v_llegada    DATETIME;
    DECLARE v_inicio_vig DATETIME;
    DECLARE v_ahora      DATETIME;
    DECLARE v_capt       DATETIME;
    DECLARE v_registro   DATETIME;
    DECLARE v_diferida   TINYINT DEFAULT 0;
    DECLARE v_eta_ant    DATETIME DEFAULT NULL;
    DECLARE v_eta_nueva  DATETIME DEFAULT NULL;
    DECLARE v_inicio_trab TINYINT DEFAULT 0;
    DECLARE v_id_dem     BIGINT DEFAULT NULL;
    DECLARE v_notif      INT DEFAULT 0;
    DECLARE v_repetida   TINYINT DEFAULT 0;

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

    SET v_tipo = LOWER(TRIM(IFNULL(p_tipo, '')));
    IF v_tipo NOT IN ('llegada', 'ingreso') THEN
        SELECT 1 AS IdTipoMensaje, 'Elige dónde se presenta la demora: llegar a planta o ingreso a planta.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF IFNULL(p_id_motivo, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Selecciona el tipo de demora.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF p_duracion IS NULL OR p_duracion < 1 OR p_duracion > 480 THEN
        SELECT 1 AS IdTipoMensaje, 'La duración estimada debe estar entre 1 y 480 minutos.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF CHAR_LENGTH(IFNULL(p_descripcion, '')) > 500 THEN
        SELECT 1 AS IdTipoMensaje, 'La descripción puede tener hasta 500 caracteres.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF p_latitud IS NULL OR p_longitud IS NULL OR p_latitud NOT BETWEEN -90 AND 90 OR p_longitud NOT BETWEEN -180 AND 180
       OR (p_latitud = 0 AND p_longitud = 0) THEN
        SELECT 1 AS IdTipoMensaje, 'La ubicación GPS no es válida: activa el GPS e inténtalo de nuevo.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF p_precision IS NOT NULL AND (p_precision < 0 OR p_precision > 5000) THEN
        SELECT 1 AS IdTipoMensaje, 'La precisión del GPS no es válida.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_ahora = UTC_TIMESTAMP() - INTERVAL 5 HOUR;

    -- Hora en que el técnico registró la demora (la marca el teléfono, en UTC). Se respeta solo si no es futura ni muy antigua
    SET v_capt = v_ahora;
    IF p_capturado_utc IS NOT NULL THEN
        SET v_capt = p_capturado_utc - INTERVAL 5 HOUR;
        IF v_capt > v_ahora + INTERVAL 5 MINUTE OR v_capt < v_ahora - INTERVAL 24 HOUR THEN
            SET v_capt = v_ahora;
        ELSEIF v_capt > v_ahora THEN
            SET v_capt = v_ahora;
        END IF;
    END IF;
    -- Diferida = llegó más de 2 min después de ocurrir (se guardó sin conexión): vale la hora del teléfono; si no, la del servidor
    SET v_diferida = IF(v_capt < v_ahora - INTERVAL 2 MINUTE, 1, 0);
    SET v_registro = IF(v_diferida = 1, v_capt, v_ahora);

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

    -- El motivo debe existir y corresponder al tipo de demora
    SELECT t.String1, IFNULL(NULLIF(t.String3, ''), 'ambos') INTO v_motivo, v_ambito
    FROM   tabla_maestra t
    WHERE  t.IdMaestro = 15 AND t.IdEmpresa = 1 AND t.Num1 = p_id_motivo AND t.eliminado_en IS NULL;

    IF v_motivo IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'El tipo de demora seleccionado no es válido.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_ambito <> 'ambos' AND v_ambito <> IF(v_tipo = 'llegada', 'traslado', 'ingreso') THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje,
               IF(v_tipo = 'llegada', 'Ese tipo de demora es de ingreso a planta: no aplica al traslado.',
                                      'Ese tipo de demora es del traslado: no aplica al ingreso a planta.') AS Mensaje;
        LEAVE proc;
    END IF;

    -- Estado de la OS y de la llegada
    CALL SP_ObtenerEtaDemorasMovil(p_id_os, v_eta_orig, v_min_lleg, v_llegada, v_inicio_vig);

    SELECT IF(COUNT(*) > 0, 1, 0) INTO v_inicio_trab
    FROM   evento_campo e
    JOIN   tabla_maestra m ON m.IdMaestro = 29 AND m.IdEmpresa = 1 AND m.Num1 = e.id_tipo_evento AND m.String2 = 'INICIO_TRABAJO'
    WHERE  e.id_os = p_id_os AND e.eliminado_en IS NULL;

    IF v_tipo = 'llegada' THEN
        IF v_estado IN ('programada', 'reprogramada') THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, 'Las demoras se registran durante el traslado: primero inicia el traslado.' AS Mensaje;
            LEAVE proc;
        END IF;
        IF v_estado <> 'en_ruta' THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, 'Las demoras de llegada solo se registran con el servicio en ruta.' AS Mensaje;
            LEAVE proc;
        END IF;
        IF v_llegada IS NOT NULL THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, 'Ya registraste tu llegada: reporta la demora como ingreso a planta.' AS Mensaje;
            LEAVE proc;
        END IF;
    ELSE
        IF v_estado NOT IN ('en_ruta', 'en_ejecucion') THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, 'Las demoras de ingreso solo se registran al llegar a la planta, antes de iniciar el trabajo.' AS Mensaje;
            LEAVE proc;
        END IF;
        IF v_llegada IS NULL THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, 'Registra primero tu llegada a la planta para reportar una demora de ingreso.' AS Mensaje;
            LEAVE proc;
        END IF;
        IF v_inicio_trab = 1 THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, 'El trabajo ya inició: no se registran demoras de ingreso.' AS Mensaje;
            LEAVE proc;
        END IF;
    END IF;

    -- Antirrebote: la misma demora hace menos de 20 s ya está registrada. Si llegó diferida (sin conexión), también cuenta la que
    -- quedó registrada alrededor de la hora en que ocurrió (el envío se repitió porque la respuesta no llegó al teléfono).
    SELECT d.id_demora, d.eta_anterior, d.eta_recalculada INTO v_id_dem, v_eta_ant, v_eta_nueva
    FROM   demora_registro d
    WHERE  d.id_os = p_id_os AND d.id_usuario = p_id_usuario AND d.tipo = v_tipo AND d.id_motivo = p_id_motivo
      AND  d.duracion_minutos = p_duracion AND d.eliminado_en IS NULL
      AND  (d.fecha_registro >= v_ahora - INTERVAL 20 SECOND
            OR (v_diferida = 1 AND d.fecha_registro BETWEEN v_capt - INTERVAL 2 MINUTE AND v_capt + INTERVAL 2 MINUTE))
    ORDER BY d.id_demora DESC LIMIT 1;

    IF v_id_dem IS NOT NULL THEN
        SET v_repetida = 1;
    ELSE
        -- Horas: llegada → ETA de llegada; ingreso → inicio del trabajo previsto (nunca antes de "ahora")
        IF v_tipo = 'llegada' THEN
            SET v_eta_ant   = IF(v_eta_orig IS NULL, NULL, v_eta_orig + INTERVAL v_min_lleg MINUTE);
            SET v_eta_nueva = IF(v_eta_ant IS NULL, NULL, v_eta_ant + INTERVAL p_duracion MINUTE);
        ELSE
            SET v_eta_ant   = GREATEST(IFNULL(v_inicio_vig, v_registro), v_registro);
            SET v_eta_nueva = v_eta_ant + INTERVAL p_duracion MINUTE;
        END IF;

        INSERT INTO demora_registro
            (id_os, id_usuario, id_motivo, tipo, descripcion, duracion_minutos, impacto, fotografia_url,
             latitud, longitud, precision_metros, eta_anterior, eta_recalculada, fecha_registro, creado_por)
        VALUES
            (p_id_os, p_id_usuario, p_id_motivo, v_tipo, NULLIF(TRIM(IFNULL(p_descripcion, '')), ''), p_duracion, 'retrasa',
             NULLIF(TRIM(IFNULL(p_foto, '')), ''), p_latitud, p_longitud, p_precision, v_eta_ant, v_eta_nueva, v_registro, p_id_usuario);
        SET v_id_dem = LAST_INSERT_ID();

        -- Aviso a Operaciones
        SELECT TRIM(CONCAT(IFNULL(nombre, ''), ' ', IFNULL(apellido, ''))) INTO v_tecnico FROM usuario WHERE id_usuario = p_id_usuario;
        SET v_texto = LEFT(CONCAT(v_numero, ' · ', IF(v_tipo = 'llegada', 'Llegar a planta', 'Ingreso a planta'), ' +', p_duracion, ' min · ',
                                  v_motivo, ' · ', IFNULL(v_tecnico, ''),
                                  IF(v_diferida = 1, CONCAT(' · sin conexión, reportada ', TIME_FORMAT(v_registro, '%H:%i')), '')), 400);

        INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
        SELECT u.id_usuario, 5, 'Demora en ruta', v_texto, 'orden_servicio', p_id_os, NOW(), p_id_usuario
        FROM   usuario u
        WHERE  u.eliminado_en IS NULL AND u.estado = 'activo' AND u.id_usuario <> p_id_usuario
          AND  ((u.area = 'operaciones' AND u.rol_sistema IN ('supervisor', 'administrador'))
                OR u.cargo IN ('jefe_operaciones', 'coordinador_operaciones'));
        SET v_notif = ROW_COUNT();

        -- Respaldo: si no hay nadie en Operaciones, los administradores
        IF v_notif = 0 THEN
            INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
            SELECT u.id_usuario, 5, 'Demora en ruta', v_texto, 'orden_servicio', p_id_os, NOW(), p_id_usuario
            FROM   usuario u
            WHERE  u.eliminado_en IS NULL AND u.estado = 'activo' AND u.id_usuario <> p_id_usuario
              AND  u.rol_sistema IN ('administrador', 'admin');
            SET v_notif = ROW_COUNT();
        END IF;

        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
        VALUES ('orden_servicio', p_id_os, 'registrar_demora', v_estado, v_estado,
                LEFT(CONCAT('Demora ', IF(v_tipo = 'llegada', 'al llegar a planta', 'en el ingreso a planta'), ': ', v_motivo, ', ', p_duracion, ' min.'), 900),
                p_id_usuario, NOW(),
                JSON_OBJECT('id_demora', v_id_dem, 'tipo', v_tipo, 'minutos', p_duracion, 'notificados', v_notif, 'diferida', v_diferida = 1));
    END IF;

    COMMIT;

    SELECT 2 AS IdTipoMensaje,
           CONCAT('Demora registrada. ',
                  IF(v_tipo = 'llegada', 'ETA recalculada: ', 'Inicio de trabajo recalculado: '),
                  IFNULL(TIME_FORMAT(v_eta_nueva, '%H:%i'), '—'), '. ',
                  IF(v_repetida = 1, 'Ya estaba registrada.',
                     IF(v_notif > 0, 'Se avisó a Operaciones.', 'No hay un responsable de Operaciones activo para avisar: informa a tu jefe.'))) AS Mensaje;

    SELECT v_id_dem AS id_demora, v_tipo AS tipo, v_eta_orig AS eta_original, v_eta_ant AS eta_anterior, v_eta_nueva AS eta_recalculada, v_notif AS notificados,
           v_repetida AS repetida, v_diferida AS diferida;
END$$

DELIMITER ;

-- ============================================================
-- SP_ObtenerNotificacionesMovil  (App Mobile HU-02 / HU-04 — pestaña Notificaciones)
-- Avisos del usuario que inició sesión (el id sale del token): las 60 más recientes, no eliminadas.
-- Son las mismas de la campana de la intranet (tabla notificacion), con el tipo ya clasificado para el ícono y la acción de la app.
--   tipo (según el título que dejan los demás SP):
--     autorizacion_aprobada   "Autorización de salida aprobada" (y el texto anterior "Visto bueno de salida: …")
--     autorizacion_rechazada  "Autorización de salida rechazada" (y "Salida no autorizada: …")
--     autorizacion_solicitud  "Autorización de salida · …" (le llega al jefe cuando un técnico pide su visto bueno)
--     solicitud_enviada       "Solicitud de autorización enviada" (confirmación para el técnico)
--     gasto_aprobado | gasto_observado | gasto_rechazado   gastos revisados por el Jefe de Operaciones
--     servicio                "Nueva programación: …" (se asignó un servicio)
--     demora                  "Demora en ruta" (le llega a Operaciones)
--     general                 cualquier otro
--   pendientes_aprobados: solo en autorizacion_aprobada, los pendientes con los que el jefe autorizó la salida.
--   entidad_tipo / id_entidad: a qué abre la app ('orden_servicio' = el detalle del servicio).
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerNotificacionesMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerNotificacionesMovil(
    IN p_id_usuario BIGINT
)
proc: BEGIN
    IF NOT EXISTS (SELECT 1 FROM usuario WHERE id_usuario = p_id_usuario AND eliminado_en IS NULL) THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no encontrado.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT x.id_notificacion, x.tipo, x.titulo, x.cuerpo, x.entidad_tipo, x.id_entidad, x.leida, x.fecha_creacion,
           CASE WHEN x.tipo = 'autorizacion_aprobada' AND x.entidad_tipo = 'orden_servicio'
                THEN (SELECT a.pendientes FROM autorizacion_salida_os a
                      WHERE  a.id_os = x.id_entidad AND a.eliminado_en IS NULL
                      ORDER BY a.id_autorizacion DESC LIMIT 1)
           END AS pendientes_aprobados
    FROM (
        SELECT n.id_notificacion,
               CASE WHEN n.titulo LIKE 'Autorización de salida aprobada%' OR n.titulo LIKE 'Visto bueno de salida%'     THEN 'autorizacion_aprobada'
                    WHEN n.titulo LIKE 'Autorización de salida rechazada%' OR n.titulo LIKE 'Salida no autorizada%'     THEN 'autorizacion_rechazada'
                    WHEN n.titulo LIKE 'Solicitud de autorización enviada%'                                             THEN 'solicitud_enviada'
                    WHEN n.titulo LIKE 'Autorización de salida%'                                                        THEN 'autorizacion_solicitud'
                    WHEN n.titulo LIKE 'Gasto aprobado%'                                                                THEN 'gasto_aprobado'
                    WHEN n.titulo LIKE 'Gasto observado%'                                                               THEN 'gasto_observado'
                    WHEN n.titulo LIKE 'Gasto rechazado%'                                                               THEN 'gasto_rechazado'
                    WHEN n.titulo LIKE 'Nueva programación%' OR n.titulo LIKE 'Nuevo servicio%'                         THEN 'servicio'
                    WHEN n.titulo LIKE 'Demora en ruta%'                                                                THEN 'demora'
                    ELSE 'general' END AS tipo,
               n.titulo,
               n.cuerpo,
               n.entidad_tipo,
               n.id_entidad,
               n.leido                AS leida,
               n.fecha_creacion
        FROM   notificacion n
        WHERE  n.id_usuario_destino = p_id_usuario AND n.eliminado_en IS NULL
        ORDER BY n.fecha_creacion DESC, n.id_notificacion DESC
        LIMIT 60
    ) x
    ORDER BY x.fecha_creacion DESC, x.id_notificacion DESC;
END$$

DELIMITER ;

-- ============================================================
-- SP_MarcarNotificacionMovil  (App Mobile HU-02 / HU-04 — marcar avisos como leídos)
-- Marca como leída UNA notificación (p_id_notificacion) o TODAS las no leídas del usuario (p_id_notificacion = 0 o NULL).
-- Solo toca las del usuario que inició sesión (el id sale del token): una notificación ajena responde como inexistente (sin IDOR).
-- Resultados: 1 mensaje; 2 la cantidad marcada.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_MarcarNotificacionMovil;

DELIMITER $$

CREATE PROCEDURE SP_MarcarNotificacionMovil(
    IN p_id_usuario      BIGINT,
    IN p_id_notificacion BIGINT
)
proc: BEGIN
    DECLARE v_marcadas INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no encontrado.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF IFNULL(p_id_notificacion, 0) > 0 THEN
        IF NOT EXISTS (SELECT 1 FROM notificacion
                       WHERE id_notificacion = p_id_notificacion AND id_usuario_destino = p_id_usuario AND eliminado_en IS NULL) THEN
            SELECT 1 AS IdTipoMensaje, 'Notificación no encontrada.' AS Mensaje;
            LEAVE proc;
        END IF;

        UPDATE notificacion
        SET    leido = 1, modificado_por = p_id_usuario
        WHERE  id_notificacion = p_id_notificacion AND id_usuario_destino = p_id_usuario AND eliminado_en IS NULL AND leido = 0;
    ELSE
        UPDATE notificacion
        SET    leido = 1, modificado_por = p_id_usuario
        WHERE  id_usuario_destino = p_id_usuario AND eliminado_en IS NULL AND leido = 0;
    END IF;
    SET v_marcadas = ROW_COUNT();

    SELECT 2 AS IdTipoMensaje, 'Listo.' AS Mensaje;
    SELECT v_marcadas AS marcadas;
END$$

DELIMITER ;

-- ============================================================
-- SP_SolicitarAutorizacionSalidaMovil  (App Mobile HU-04)
-- El técnico pide el visto bueno para salir con pendientes al ENCARGADO DEL ÁREA del servicio.
--   - El área sale de la RQ de la OS: orden_servicio → expediente_digital → requerimiento.id_area
--     (catálogo AREA_REQUERIMIENTO 64) → area_servicio_rq → servicio_tecnico | metrologia.
--   - Encargado = usuario activo cuyo cargo es el "jefe_*" de esa área en CARGO_USUARIO (80):
--     Jefe de Servicio Técnico o Jefe de Metrología.
--   - Si la RQ no tiene área (o no está mapeada) se notifica a ambos encargados.
--   - Respaldo si el área no tiene encargado activo: supervisores/administradores del área;
--     si tampoco, Jefe/Coordinador de Operaciones; si tampoco, administradores.
--   - Una sola solicitud pendiente por OS (evita duplicados y spam de notificaciones).
--   - Solo desde el día programado de la OS (SP_ObtenerSalidaHabilitadaMovil).
--   - Deja también una notificación al propio técnico ("Solicitud de autorización enviada") para que la vea en la app.
--   - Deja registro en autorizacion_salida_os (con area_destino) y auditoria_evento.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_SolicitarAutorizacionSalidaMovil;

DELIMITER $$

CREATE PROCEDURE SP_SolicitarAutorizacionSalidaMovil(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT,
    IN p_motivo     VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_pendientes VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_estado      VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_numero      VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cliente     VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tecnico     VARCHAR(210) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_aut_estado  VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_aut      BIGINT;
    DECLARE v_destinos    INT DEFAULT 0;
    DECLARE v_area        VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_area_nombre VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_notificados VARCHAR(600) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_salida_ok   TINYINT DEFAULT 1;
    DECLARE v_salida_msg  VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    START TRANSACTION;

    SELECT os.estado, os.numero, COALESCE(NULLIF(cl.nombre_comercial, ''), cl.razon_social), asr.area_usuario
    INTO   v_estado, v_numero, v_cliente, v_area
    FROM   orden_servicio os
    LEFT JOIN cliente            cl  ON cl.id_cliente        = os.id_cliente
    LEFT JOIN expediente_digital ed  ON ed.id_expediente     = os.id_expediente
    LEFT JOIN requerimiento      rq  ON rq.id_requerimiento  = ed.id_requerimiento
    LEFT JOIN area_servicio_rq   asr ON asr.id_area_rq       = rq.id_area
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

    IF v_estado NOT IN ('programada', 'reprogramada') THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'El servicio ya no está programado: no hace falta autorización de salida.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- La salida (y su autorización) solo se gestiona desde el día programado
    CALL SP_ObtenerSalidaHabilitadaMovil(p_id_os, v_salida_ok, v_salida_msg);
    IF v_salida_ok = 0 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, v_salida_msg AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT a.estado INTO v_aut_estado
    FROM   autorizacion_salida_os a
    WHERE  a.id_os = p_id_os AND a.eliminado_en IS NULL
    ORDER BY a.id_autorizacion DESC LIMIT 1;

    IF v_aut_estado = 'pendiente' THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Ya enviaste una solicitud: espera la respuesta del encargado del área.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF v_aut_estado = 'aprobada' THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Ya tienes el visto bueno: puedes iniciar el traslado.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT TRIM(CONCAT(IFNULL(nombre, ''), ' ', IFNULL(apellido, ''))) INTO v_tecnico
    FROM usuario WHERE id_usuario = p_id_usuario;

    SET v_area_nombre = (SELECT t.String1 FROM tabla_maestra t
                         WHERE t.IdMaestro = 79 AND t.IdEmpresa = 1 AND t.String2 = v_area LIMIT 1);

    INSERT INTO autorizacion_salida_os (id_os, id_tecnico, motivo, pendientes, estado, area_destino, solicitado_en, creado_por)
    VALUES (p_id_os, p_id_usuario, NULLIF(TRIM(p_motivo), ''), NULLIF(TRIM(p_pendientes), ''), 'pendiente', v_area, NOW(), p_id_usuario);
    SET v_id_aut = LAST_INSERT_ID();

    -- Destinatarios (en una tabla temporal para notificar y responder con los nombres)
    DROP TEMPORARY TABLE IF EXISTS tmp_aut_destino;
    CREATE TEMPORARY TABLE tmp_aut_destino (
        id_usuario BIGINT PRIMARY KEY,
        nombre     VARCHAR(210) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        cargo      VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
    );

    -- 1) Encargado(s) del área: cargo jefe_* del área (si la RQ no tiene área: de ambas áreas)
    INSERT IGNORE INTO tmp_aut_destino
    SELECT u.id_usuario, TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))), c.String1
    FROM   usuario u
    JOIN   tabla_maestra c ON c.IdMaestro = 80 AND c.IdEmpresa = 1 AND c.String2 = u.cargo
    WHERE  u.eliminado_en IS NULL AND u.estado = 'activo'
      AND  c.String2 LIKE 'jefe\_%'
      AND  ((v_area IS NOT NULL AND c.String3 = v_area)
            OR (v_area IS NULL AND c.String3 IN ('servicio_tecnico', 'metrologia')));

    -- 2) Respaldo: supervisores / administradores del área
    IF (SELECT COUNT(*) FROM tmp_aut_destino) = 0 THEN
        INSERT IGNORE INTO tmp_aut_destino
        SELECT u.id_usuario, TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))), NULL
        FROM   usuario u
        WHERE  u.eliminado_en IS NULL AND u.estado = 'activo'
          AND  u.rol_sistema IN ('supervisor', 'administrador')
          AND  ((v_area IS NOT NULL AND u.area = v_area)
                OR (v_area IS NULL AND u.area IN ('servicio_tecnico', 'metrologia')));
    END IF;

    -- 3) Respaldo: Jefe / Coordinador de Operaciones
    IF (SELECT COUNT(*) FROM tmp_aut_destino) = 0 THEN
        INSERT IGNORE INTO tmp_aut_destino
        SELECT u.id_usuario, TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))), c.String1
        FROM   usuario u
        LEFT JOIN tabla_maestra c ON c.IdMaestro = 80 AND c.IdEmpresa = 1 AND c.String2 = u.cargo
        WHERE  u.eliminado_en IS NULL AND u.estado = 'activo'
          AND  u.cargo IN ('jefe_operaciones', 'coordinador_operaciones');
    END IF;

    -- 4) Respaldo final: administradores
    IF (SELECT COUNT(*) FROM tmp_aut_destino) = 0 THEN
        INSERT IGNORE INTO tmp_aut_destino
        SELECT u.id_usuario, TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))), NULL
        FROM   usuario u
        WHERE  u.eliminado_en IS NULL AND u.estado = 'activo' AND u.rol_sistema IN ('administrador', 'admin');
    END IF;

    INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
    SELECT d.id_usuario, 5,
           CONCAT('Autorización de salida', IF(v_area_nombre IS NULL, '', CONCAT(' · ', v_area_nombre)), ': ', v_numero),
           CONCAT(v_tecnico, ' solicita tu visto bueno para salir a ', IFNULL(v_cliente, 'el cliente'), ' (', v_numero, ').',
                  IF(v_area_nombre IS NULL, ' La RQ no indica el área del servicio.', CONCAT(' Área del servicio según la RQ: ', v_area_nombre, '.')),
                  IF(NULLIF(TRIM(p_pendientes), '') IS NULL, '', CONCAT(' Pendientes: ', TRIM(p_pendientes), '.')),
                  IF(NULLIF(TRIM(p_motivo), '') IS NULL, '', CONCAT(' Motivo: ', TRIM(p_motivo)))),
           'orden_servicio', p_id_os, NOW(), p_id_usuario
    FROM   tmp_aut_destino d;
    SET v_destinos = ROW_COUNT();

    SELECT GROUP_CONCAT(CONCAT(d.nombre, IFNULL(CONCAT(' (', d.cargo, ')'), '')) ORDER BY d.nombre SEPARATOR ', ')
    INTO   v_notificados
    FROM   tmp_aut_destino d;
    DROP TEMPORARY TABLE IF EXISTS tmp_aut_destino;

    -- Confirmación para el propio técnico (HU-04: "Solicitud de autorización enviada · avisado al Jefe …")
    INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
    VALUES (p_id_usuario, 5, 'Solicitud de autorización enviada',
            LEFT(CONCAT(v_numero, ' · ', IF(v_notificados IS NULL, 'sin un encargado activo para avisar', CONCAT('avisado a ', v_notificados))), 3000),
            'orden_servicio', p_id_os, NOW(), p_id_usuario);

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('orden_servicio', p_id_os, 'solicitar_autorizacion_salida', IFNULL(v_aut_estado, 'sin_solicitud'), 'pendiente',
            CONCAT('El técnico solicita visto bueno para salir.',
                   IF(NULLIF(TRIM(p_pendientes), '') IS NULL, '', CONCAT(' Pendientes: ', TRIM(p_pendientes), '.'))),
            p_id_usuario, NOW(), JSON_OBJECT('id_autorizacion', v_id_aut, 'area_destino', v_area, 'notificados', v_destinos));

    COMMIT;

    SELECT 2 AS IdTipoMensaje,
           IF(v_destinos > 0,
              CONCAT('Solicitud enviada a ', v_notificados, '.'),
              'Solicitud registrada, pero no hay un encargado activo para notificar: avisa a tu jefe.') AS Mensaje;
END$$

DELIMITER ;

-- ============================================================
-- SP_ResolverAutorizacionSalida  (Intranet · App Mobile HU-04)
-- El encargado del área da (o niega) el visto bueno de salida de una OS desde la intranet.
--   - Área de la OS: la de la solicitud (area_destino) o, si no hay solicitud, la de la RQ
--     (requerimiento.id_area → area_servicio_rq).
--   - Pueden resolver: el encargado de ESA área (cargo jefe_* del área: Jefe de Servicio Técnico
--     o Jefe de Metrología; y también el SUPERVISOR del área Metrología, que es su jefe en la app móvil;
--     si la RQ no tiene área, cualquiera de los dos), el Jefe/Coordinador
--     de Operaciones o el supervisor del área Operaciones (supervisión general) o un administrador. El encargado de la otra área NO.
--   - Si hay una solicitud pendiente del técnico, la resuelve; si no, registra el visto bueno igual.
--   - Solo mientras la OS siga programada/reprogramada.
--   - Notifica al técnico principal y al personal de la OS ("Autorización de salida aprobada/rechazada" con el jefe, su cargo y la
--     condición o el motivo). Deja registro en auditoria_evento.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ResolverAutorizacionSalida;

DELIMITER $$

CREATE PROCEDURE SP_ResolverAutorizacionSalida(
    IN p_id_jefe    BIGINT,
    IN p_id_os      BIGINT,
    IN p_aprobar    TINYINT,
    IN p_comentario VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_estado     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_numero     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_jefe       VARCHAR(210) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_principal  BIGINT;
    DECLARE v_id_aut     BIGINT;
    DECLARE v_aut_estado VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_nuevo      VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_area       VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_area_jefe  VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_general    TINYINT DEFAULT 0;
    DECLARE v_area_sol   VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cargo_jefe VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cliente    VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    -- Quién es: encargado de un área (v_area_jefe) o supervisión general (v_general)
    SELECT TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))),
           IFNULL(c.String1, NULLIF(u.cargo, '')),
           COALESCE(IF(c.String2 LIKE 'jefe\_%' AND c.String3 IN ('servicio_tecnico', 'metrologia'), c.String3, NULL),
                    IF(u.rol_sistema = 'supervisor' AND u.area = 'metrologia', 'metrologia', NULL)),
           (u.cargo IN ('jefe_operaciones', 'coordinador_operaciones') OR u.rol_sistema IN ('administrador', 'admin')
            OR (u.rol_sistema = 'supervisor' AND u.area = 'operaciones'))
    INTO   v_jefe, v_cargo_jefe, v_area_jefe, v_general
    FROM   usuario u
    LEFT JOIN tabla_maestra c ON c.IdMaestro = 80 AND c.IdEmpresa = 1 AND c.String2 = u.cargo
    WHERE  u.id_usuario = p_id_jefe AND u.eliminado_en IS NULL AND u.estado = 'activo'
    LIMIT 1;

    IF v_jefe IS NULL OR (v_area_jefe IS NULL AND v_general = 0) THEN
        SELECT 1 AS IdTipoMensaje, 'Solo el encargado del área (Servicio Técnico o Metrología) puede dar el visto bueno de salida.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_nuevo = IF(p_aprobar = 1, 'aprobada', 'rechazada');

    START TRANSACTION;

    SELECT os.estado, os.numero, os.id_tecnico_principal, asr.area_usuario, COALESCE(NULLIF(cl.nombre_comercial, ''), cl.razon_social)
    INTO   v_estado, v_numero, v_principal, v_area, v_cliente
    FROM   orden_servicio os
    LEFT JOIN cliente            cl  ON cl.id_cliente       = os.id_cliente
    LEFT JOIN expediente_digital ed  ON ed.id_expediente    = os.id_expediente
    LEFT JOIN requerimiento      rq  ON rq.id_requerimiento = ed.id_requerimiento
    LEFT JOIN area_servicio_rq   asr ON asr.id_area_rq      = rq.id_area
    WHERE  os.id_os = p_id_os AND os.eliminado_en IS NULL
    FOR UPDATE;

    IF v_estado IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Orden de servicio no encontrada.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF v_estado NOT IN ('programada', 'reprogramada') THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, CONCAT('La OS ya no está programada (', REPLACE(v_estado, '_', ' '), '): no requiere visto bueno.') AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT a.id_autorizacion, a.estado, IF(a.estado = 'pendiente', a.area_destino, NULL)
    INTO   v_id_aut, v_aut_estado, v_area_sol
    FROM   autorizacion_salida_os a
    WHERE  a.id_os = p_id_os AND a.eliminado_en IS NULL
    ORDER BY a.id_autorizacion DESC LIMIT 1;

    -- La solicitud pendiente manda: es el área a la que se notificó
    IF v_aut_estado = 'pendiente' AND v_area_sol IS NOT NULL THEN
        SET v_area = v_area_sol;
    END IF;

    -- El encargado de la otra área no puede resolver (sí la supervisión general)
    IF v_general = 0 AND v_area IS NOT NULL AND v_area <> v_area_jefe THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Este servicio no es de tu área: lo autoriza el encargado del área indicada en la RQ.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF v_aut_estado = 'pendiente' THEN
        UPDATE autorizacion_salida_os
        SET    estado = v_nuevo, id_jefe = p_id_jefe, resuelto_en = NOW(),
               comentario = NULLIF(TRIM(p_comentario), ''), modificado_por = p_id_jefe
        WHERE  id_autorizacion = v_id_aut;
    ELSE
        INSERT INTO autorizacion_salida_os (id_os, id_tecnico, estado, area_destino, id_jefe, resuelto_en, comentario, creado_por)
        VALUES (p_id_os, v_principal, v_nuevo, v_area, p_id_jefe, NOW(), NULLIF(TRIM(p_comentario), ''), p_id_jefe);
        SET v_id_aut = LAST_INSERT_ID();
    END IF;

    -- Aviso al técnico principal y al personal de la OS
    INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
    SELECT d.id_usuario, 5,
           IF(p_aprobar = 1, 'Autorización de salida aprobada', 'Autorización de salida rechazada'),
           LEFT(CONCAT(v_numero, IF(v_cliente IS NULL, '', CONCAT(' · ', v_cliente)), ' · ', v_jefe,
                       IF(v_cargo_jefe IS NULL, '', CONCAT(' (', v_cargo_jefe, ')')),
                       IF(p_aprobar = 1, ' dio el visto bueno.', ' no autorizó tu salida.'),
                       IF(NULLIF(TRIM(p_comentario), '') IS NULL, '', CONCAT(IF(p_aprobar = 1, ' Condición: ', ' Motivo: '), TRIM(p_comentario)))), 3000),
           'orden_servicio', p_id_os, NOW(), p_id_jefe
    FROM (
        SELECT v_principal AS id_usuario FROM DUAL WHERE v_principal IS NOT NULL
        UNION
        SELECT op.id_usuario FROM os_personal op WHERE op.id_os = p_id_os AND op.eliminado_en IS NULL
    ) d;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('orden_servicio', p_id_os, 'visto_bueno_salida', IFNULL(v_aut_estado, 'sin_solicitud'), v_nuevo,
            CONCAT(v_jefe, IF(p_aprobar = 1, ' dio el visto bueno de salida.', ' no autorizó la salida.'),
                   IF(NULLIF(TRIM(p_comentario), '') IS NULL, '', CONCAT(' ', TRIM(p_comentario)))),
            p_id_jefe, NOW(), JSON_OBJECT('id_autorizacion', v_id_aut, 'area', v_area));

    COMMIT;

    SELECT 2 AS IdTipoMensaje, IF(p_aprobar = 1, 'Visto bueno de salida registrado.', 'Salida no autorizada.') AS Mensaje;
END$$

DELIMITER ;

-- ============================================================
-- Verificación (solo lectura)
-- ============================================================
-- 1) Columnas nuevas de demora_registro (deben salir 6: tipo, latitud, longitud, precision_metros, eta_anterior, eta_recalculada)
SELECT COLUMN_NAME, COLUMN_TYPE
FROM   information_schema.COLUMNS
WHERE  TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'demora_registro'
  AND  COLUMN_NAME IN ('tipo', 'latitud', 'longitud', 'precision_metros', 'eta_anterior', 'eta_recalculada');

-- 2) Ámbito de cada motivo de demora (String3: traslado | ingreso | ambos)
SELECT Num1 AS id_motivo, String1 AS nombre, String2 AS codigo, String3 AS ambito
FROM   tabla_maestra
WHERE  IdMaestro = 15 AND IdEmpresa = 1 AND eliminado_en IS NULL
ORDER BY Num1;

-- 3) Procedimientos aplicados (deben salir 7)
SELECT ROUTINE_NAME, LAST_ALTERED
FROM   information_schema.ROUTINES
WHERE  ROUTINE_SCHEMA = DATABASE() AND ROUTINE_TYPE = 'PROCEDURE'
  AND  ROUTINE_NAME IN ('SP_ObtenerEtaDemorasMovil', 'SP_ObtenerDemorasMovil', 'SP_RegistrarDemoraMovil', 'SP_ObtenerNotificacionesMovil',
                        'SP_MarcarNotificacionMovil', 'SP_SolicitarAutorizacionSalidaMovil', 'SP_ResolverAutorizacionSalida')
ORDER BY ROUTINE_NAME;
