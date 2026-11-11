-- ============================================================
-- SP_ObtenerConsultaAsistenteMovil  (App Mobile HU-19 — reabrir una consulta reciente · lectura)
-- Una consulta con su respuesta (pregunta, advertencia, pasos y fuentes en `respuesta_json`) y la valoración del técnico. Solo la consulta es del propio técnico y
-- debe tener respuesta (las que se quedaron en proceso o terminaron en error de la IA no se pueden abrir). Horas de Lima.
-- Resultados: 1 mensaje · 2 consulta (1 fila).
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerConsultaAsistenteMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerConsultaAsistenteMovil(
    IN p_id_usuario  BIGINT,
    IN p_id_consulta BIGINT
)
proc: BEGIN
    DECLARE v_id     BIGINT DEFAULT NULL;
    DECLARE v_resp   TINYINT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_consulta, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Consulta no encontrada.' AS Mensaje; LEAVE proc;
    END IF;

    SELECT c.id_consulta, IF(c.respuesta_json IS NULL, 0, 1) INTO v_id, v_resp
    FROM   asistente_consulta c
    WHERE  c.id_consulta = p_id_consulta AND c.id_usuario = p_id_usuario;
    IF v_id IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Consulta no encontrada.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_resp = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Esta consulta no tiene respuesta.' AS Mensaje; LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;
    SELECT c.id_consulta, c.id_os, c.id_os_equipo, c.pregunta, c.origen, c.estado, CONVERT_TZ(c.creado_en, '+00:00', '-05:00') AS creado_en,
           CAST(c.respuesta_json AS CHAR) AS respuesta_json, c.util
    FROM   asistente_consulta c
    WHERE  c.id_consulta = p_id_consulta AND c.id_usuario = p_id_usuario;
END$$

DELIMITER ;
