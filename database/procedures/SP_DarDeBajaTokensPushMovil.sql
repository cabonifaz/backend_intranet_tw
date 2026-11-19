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
