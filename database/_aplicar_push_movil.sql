-- Notificaciones push de la app móvil (migración 120 + 4 SPs). Ejecutar completo en DBeaver (Alt+X). Idempotente.

-- ============================================================
-- Migración 120 — Notificaciones push de la app móvil
--   Tabla dispositivo_push_movil: el token de Expo Push de cada teléfono donde un usuario inició sesión en la app.
--   Con eso la API envía cada notificación nueva (tabla `notificacion`) a la bandeja de notificaciones del teléfono,
--   aunque la app esté cerrada. Un token pertenece a UN usuario a la vez (si otro usuario inicia sesión en el mismo teléfono,
--   el token pasa a él: SP_RegistrarDispositivoPushMovil). Soft delete + auditoría. Sin FK. IDEMPOTENTE.
-- ============================================================
CREATE TABLE IF NOT EXISTS dispositivo_push_movil (
    id_dispositivo_push BIGINT       NOT NULL AUTO_INCREMENT,
    id_usuario          BIGINT       NOT NULL,
    id_dispositivo      VARCHAR(100) NOT NULL,
    token               VARCHAR(255) NOT NULL,
    plataforma          VARCHAR(10)  NOT NULL DEFAULT 'android',
    ultimo_registro     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    -- AUDITORÍA
    creado_en           DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por          BIGINT       NULL,
    modificado_en       DATETIME     NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por      BIGINT       NULL,
    eliminado_en        DATETIME     NULL,
    eliminado_por       BIGINT       NULL,
    PRIMARY KEY (id_dispositivo_push)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'dispositivo_push_movil' AND INDEX_NAME = 'ix_dispositivo_push_usuario'),
    'ALTER TABLE dispositivo_push_movil ADD KEY ix_dispositivo_push_usuario (id_usuario, eliminado_en)', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'dispositivo_push_movil' AND INDEX_NAME = 'ix_dispositivo_push_token'),
    'ALTER TABLE dispositivo_push_movil ADD KEY ix_dispositivo_push_token (token)', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SELECT 'Migración 120 (debe ser 1)' AS verificacion,
       (SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'dispositivo_push_movil') AS valor;

-- ============================================================
-- SP_RegistrarDispositivoPushMovil  (App Mobile — notificaciones push)
-- La app registra el token de Expo Push del teléfono al iniciar sesión (y cada vez que abre con sesión). El usuario sale del token.
--   · Un mismo usuario + teléfono (p_id_dispositivo) deja UNA fila: si ya existía, se actualiza el token.
--   · Un token pertenece a un solo usuario: si otro usuario lo tenía (mismo teléfono, otra persona), esa fila se da de baja.
--   · Sesión única: los otros teléfonos que ese usuario tenía registrados se dan de baja.
-- Valida el formato del token ("ExponentPushToken[...]" o "ExpoPushToken[...]") y los largos.
-- Resultados: 1 mensaje; 2 nada más (la API responde true).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_RegistrarDispositivoPushMovil;

DELIMITER $$

CREATE PROCEDURE SP_RegistrarDispositivoPushMovil(
    IN p_id_usuario     BIGINT,
    IN p_id_dispositivo VARCHAR(100),
    IN p_token          VARCHAR(255),
    IN p_plataforma     VARCHAR(10)
)
proc: BEGIN
    DECLARE v_id BIGINT DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SET p_id_dispositivo = TRIM(p_id_dispositivo);
    SET p_token          = TRIM(p_token);
    SET p_plataforma     = LOWER(IFNULL(NULLIF(TRIM(p_plataforma), ''), 'android'));

    IF IFNULL(p_id_usuario, 0) <= 0 OR NOT EXISTS (SELECT 1 FROM usuario WHERE id_usuario = p_id_usuario) THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no encontrado.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF IFNULL(p_id_dispositivo, '') = '' OR CHAR_LENGTH(p_id_dispositivo) > 100 THEN
        SELECT 1 AS IdTipoMensaje, 'Identificador de dispositivo no válido.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF IFNULL(p_token, '') = '' OR CHAR_LENGTH(p_token) > 255
       OR NOT (p_token LIKE 'ExponentPushToken[%]' OR p_token LIKE 'ExpoPushToken[%]') THEN
        SELECT 1 AS IdTipoMensaje, 'Token de notificaciones no válido.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF p_plataforma NOT IN ('android', 'ios') THEN
        SET p_plataforma = 'android';
    END IF;

    START TRANSACTION;

    -- El token pasa al usuario actual: se da de baja en cualquier otro usuario
    UPDATE dispositivo_push_movil
    SET    eliminado_en = NOW(), eliminado_por = p_id_usuario
    WHERE  token = p_token AND id_usuario <> p_id_usuario AND eliminado_en IS NULL;

    SELECT MAX(id_dispositivo_push) INTO v_id
    FROM   dispositivo_push_movil
    WHERE  id_usuario = p_id_usuario AND id_dispositivo = p_id_dispositivo AND eliminado_en IS NULL;

    IF v_id IS NULL THEN
        INSERT INTO dispositivo_push_movil (id_usuario, id_dispositivo, token, plataforma, creado_por)
        VALUES (p_id_usuario, p_id_dispositivo, p_token, p_plataforma, p_id_usuario);
    ELSE
        UPDATE dispositivo_push_movil
        SET    token = p_token, plataforma = p_plataforma, ultimo_registro = NOW(), modificado_por = p_id_usuario
        WHERE  id_dispositivo_push = v_id;
    END IF;

    -- Sesión única (HU-01): un usuario está en UN teléfono; los demás teléfonos que tuvo registrados dejan de recibir sus avisos
    UPDATE dispositivo_push_movil
    SET    eliminado_en = NOW(), eliminado_por = p_id_usuario
    WHERE  id_usuario = p_id_usuario AND id_dispositivo <> p_id_dispositivo AND eliminado_en IS NULL;

    COMMIT;

    SELECT 2 AS IdTipoMensaje, 'Listo.' AS Mensaje;
END$$

DELIMITER ;

-- ============================================================
-- SP_QuitarDispositivoPushMovil  (App Mobile — notificaciones push)
-- Al cerrar sesión la app da de baja el token de ESE teléfono para ese usuario (el usuario sale del token de sesión): a un teléfono sin sesión
-- no le llegan avisos. Si no existía, responde igual (éxito): cerrar sesión no debe fallar por esto.
-- Resultados: 1 mensaje; 2 nada más.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_QuitarDispositivoPushMovil;

DELIMITER $$

CREATE PROCEDURE SP_QuitarDispositivoPushMovil(
    IN p_id_usuario     BIGINT,
    IN p_id_dispositivo VARCHAR(100)
)
proc: BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(TRIM(p_id_dispositivo), '') = '' THEN
        SELECT 1 AS IdTipoMensaje, 'Datos no válidos.' AS Mensaje;
        LEAVE proc;
    END IF;

    UPDATE dispositivo_push_movil
    SET    eliminado_en = NOW(), eliminado_por = p_id_usuario
    WHERE  id_usuario = p_id_usuario AND id_dispositivo = TRIM(p_id_dispositivo) AND eliminado_en IS NULL;

    SELECT 2 AS IdTipoMensaje, 'Listo.' AS Mensaje;
END$$

DELIMITER ;

-- ============================================================
-- SP_ObtenerDispositivosPushMovil  (App Mobile — notificaciones push)
-- Lo llama el worker de la API (PushNotificacionesWorker): dado un grupo de usuarios (ids separados por coma, máximo 500), devuelve los tokens
-- de Expo Push de sus teléfonos con sesión de la app vigente. Proceso del sistema: no valida permisos.
-- Resultados: 1 mensaje; 2 filas (id_usuario, token).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerDispositivosPushMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerDispositivosPushMovil(
    IN p_ids_usuario TEXT
)
proc: BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(TRIM(p_ids_usuario), '') = '' OR CHAR_LENGTH(p_ids_usuario) > 5000 THEN
        SELECT 1 AS IdTipoMensaje, 'Sin usuarios.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT d.id_usuario, d.token
    FROM   dispositivo_push_movil d
    WHERE  d.eliminado_en IS NULL
      AND  FIND_IN_SET(d.id_usuario, REPLACE(p_ids_usuario, ' ', '')) > 0
      -- solo teléfonos de quien tiene la sesión de la app abierta (canal 2): si la sesión terminó (cierre, vencimiento, otro equipo), no se le envía
      AND  EXISTS (SELECT 1 FROM sesion_usuario s
                   WHERE  s.id_usuario = d.id_usuario AND s.id_canal_acceso = 2 AND s.activo = 1
                     AND  s.eliminado_en IS NULL AND s.fecha_expiracion > NOW())
    ORDER BY d.id_usuario, d.id_dispositivo_push;
END$$

DELIMITER ;

-- ============================================================
-- SP_DarDeBajaTokensPushMovil  (App Mobile — notificaciones push)
-- Lo llama el worker de la API cuando Expo responde "DeviceNotRegistered" (la app se desinstaló o el token venció): se da de baja ese token
-- para no seguir enviándole. Recibe los tokens separados por coma (máximo 100). Proceso del sistema: no valida permisos.
-- Resultados: 1 mensaje; 2 la cantidad dada de baja.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_DarDeBajaTokensPushMovil;

DELIMITER $$

CREATE PROCEDURE SP_DarDeBajaTokensPushMovil(
    IN p_tokens TEXT
)
proc: BEGIN
    DECLARE v_bajas INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(TRIM(p_tokens), '') = '' OR CHAR_LENGTH(p_tokens) > 10000 THEN
        SELECT 1 AS IdTipoMensaje, 'Sin tokens.' AS Mensaje;
        LEAVE proc;
    END IF;

    UPDATE dispositivo_push_movil
    SET    eliminado_en = NOW()
    WHERE  eliminado_en IS NULL
      AND  FIND_IN_SET(token, REPLACE(p_tokens, ' ', '')) > 0;
    SET v_bajas = ROW_COUNT();

    SELECT 2 AS IdTipoMensaje, 'Listo.' AS Mensaje;
    SELECT v_bajas AS bajas;
END$$

DELIMITER ;

