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
