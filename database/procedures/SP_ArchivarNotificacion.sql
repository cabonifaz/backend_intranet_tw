-- ============================================================
-- SP_ArchivarNotificacion  (HU-90 Centro de Notificaciones — botón "Archivar" del panel de detalle)
-- Solo se puede archivar una notificación LEÍDA. Sale de la bandeja activa y queda en el filtro "archivadas".
-- Solo una notificación del usuario que inició sesión (el id sale del token): una ajena responde "no encontrada" (sin IDOR).
-- Requiere la migración 102.
-- Resultados: 1 mensaje · 2 id_notificacion y no_leidas.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ArchivarNotificacion;

DELIMITER $$

CREATE PROCEDURE SP_ArchivarNotificacion(
    IN p_id_usuario      BIGINT,
    IN p_id_notificacion BIGINT
)
proc: BEGIN
    DECLARE v_leido     TINYINT;
    DECLARE v_archivado TINYINT;
    DECLARE v_no_leidas INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no encontrado.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT leido, archivado INTO v_leido, v_archivado
    FROM   notificacion
    WHERE  id_notificacion = p_id_notificacion AND id_usuario_destino = p_id_usuario AND eliminado_en IS NULL
    LIMIT 1;

    IF v_leido IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Notificación no encontrada.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_archivado = 1 THEN
        SELECT 1 AS IdTipoMensaje, 'La notificación ya está archivada.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_leido = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Solo se pueden archivar notificaciones leídas.' AS Mensaje;
        LEAVE proc;
    END IF;

    UPDATE notificacion
    SET    archivado = 1, fecha_archivado = NOW(), modificado_por = p_id_usuario
    WHERE  id_notificacion = p_id_notificacion AND id_usuario_destino = p_id_usuario AND eliminado_en IS NULL AND archivado = 0;

    SELECT COUNT(*) INTO v_no_leidas
    FROM   notificacion
    WHERE  id_usuario_destino = p_id_usuario AND eliminado_en IS NULL AND archivado = 0 AND leido = 0;

    SELECT 2 AS IdTipoMensaje, 'Notificación archivada.' AS Mensaje;
    SELECT p_id_notificacion AS id_notificacion, v_no_leidas AS no_leidas;
END$$

DELIMITER ;
