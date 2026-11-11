-- ============================================================
-- SP_MarcarNotificacionesLeidas  (HU-90 Centro de Notificaciones)
--   Popover "✓ Marcar las 5 como leídas" → p_ids = los ids visibles en el popover (lista separada por comas, máx. 100; el caso de uso la valida).
--   Bandeja "Marcar todas como leídas"   → p_todas = 1 (todas las no leídas y no archivadas del usuario).
-- Solo toca notificaciones del usuario que inició sesión (el id sale del token): los ids ajenos se ignoran (sin IDOR).
-- Requiere la migración 102.
-- Resultados: 1 mensaje · 2 marcadas y no_leidas (contador del badge después del cambio).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_MarcarNotificacionesLeidas;

DELIMITER $$

CREATE PROCEDURE SP_MarcarNotificacionesLeidas(
    IN p_id_usuario BIGINT,
    IN p_ids        VARCHAR(2100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_todas      TINYINT
)
proc: BEGIN
    DECLARE v_marcadas  INT DEFAULT 0;
    DECLARE v_no_leidas INT DEFAULT 0;
    DECLARE v_ids       VARCHAR(2100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no encontrado.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_ids = NULLIF(REPLACE(TRIM(p_ids), ' ', ''), '');

    IF IFNULL(p_todas, 0) = 0 AND v_ids IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Indica las notificaciones a marcar o marca todas.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF IFNULL(p_todas, 0) = 1 THEN
        UPDATE notificacion
        SET    leido = 1, fecha_lectura = NOW(), modificado_por = p_id_usuario
        WHERE  id_usuario_destino = p_id_usuario AND eliminado_en IS NULL AND archivado = 0 AND leido = 0;
    ELSE
        UPDATE notificacion
        SET    leido = 1, fecha_lectura = NOW(), modificado_por = p_id_usuario
        WHERE  id_usuario_destino = p_id_usuario AND eliminado_en IS NULL AND leido = 0
          AND  FIND_IN_SET(id_notificacion, v_ids) > 0;
    END IF;
    SET v_marcadas = ROW_COUNT();

    SELECT COUNT(*) INTO v_no_leidas
    FROM   notificacion
    WHERE  id_usuario_destino = p_id_usuario AND eliminado_en IS NULL AND archivado = 0 AND leido = 0;

    SELECT 2 AS IdTipoMensaje, IF(v_marcadas = 1, '1 notificación marcada como leída.', CONCAT(v_marcadas, ' notificaciones marcadas como leídas.')) AS Mensaje;
    SELECT v_marcadas AS marcadas, v_no_leidas AS no_leidas;
END$$

DELIMITER ;
