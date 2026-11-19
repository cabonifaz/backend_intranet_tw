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
