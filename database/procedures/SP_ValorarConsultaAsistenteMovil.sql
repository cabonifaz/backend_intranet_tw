-- ============================================================
-- SP_ValorarConsultaAsistenteMovil  (App Mobile HU-19 — "¿Te sirvió la respuesta?" · escritura)
-- El técnico marca su consulta como útil (1) o no útil (0). Solo su propia consulta y solo si tiene respuesta. Se puede cambiar de opinión.
-- Resultados: 1 mensaje.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ValorarConsultaAsistenteMovil;

DELIMITER $$

CREATE PROCEDURE SP_ValorarConsultaAsistenteMovil(
    IN p_id_usuario  BIGINT,
    IN p_id_consulta BIGINT,
    IN p_util        TINYINT
)
proc: BEGIN
    DECLARE v_id   BIGINT DEFAULT NULL;
    DECLARE v_resp TINYINT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_consulta, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Consulta no encontrada.' AS Mensaje; LEAVE proc;
    END IF;
    IF p_util IS NULL OR p_util NOT IN (0, 1) THEN
        SELECT 1 AS IdTipoMensaje, 'La valoración no es válida.' AS Mensaje; LEAVE proc;
    END IF;

    START TRANSACTION;
    SELECT c.id_consulta, IF(c.respuesta_json IS NULL, 0, 1) INTO v_id, v_resp
    FROM   asistente_consulta c
    WHERE  c.id_consulta = p_id_consulta AND c.id_usuario = p_id_usuario
    FOR UPDATE;
    IF v_id IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Consulta no encontrada.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_resp = 0 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Esta consulta no tiene respuesta que valorar.' AS Mensaje; LEAVE proc;
    END IF;

    UPDATE asistente_consulta SET util = p_util, valorada_en = UTC_TIMESTAMP() WHERE id_consulta = p_id_consulta;
    COMMIT;

    SELECT 2 AS IdTipoMensaje, 'Gracias por tu valoración.' AS Mensaje;
END$$

DELIMITER ;
