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
