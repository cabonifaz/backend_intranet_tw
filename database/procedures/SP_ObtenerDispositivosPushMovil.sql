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
