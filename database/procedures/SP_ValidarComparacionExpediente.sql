-- HU-30 Tab Propuestas, botón "Comparar versiones": valida que las dos versiones pertenezcan al expediente y sean de
-- la misma propuesta (la comparación la arma SP_CompararVersionesPropuesta). Acción expediente_bandeja.
-- Resultados: 1 mensaje
DROP PROCEDURE IF EXISTS SP_ValidarComparacionExpediente;

DELIMITER $$

CREATE PROCEDURE SP_ValidarComparacionExpediente(
    IN p_id_usuario    BIGINT,
    IN p_id_expediente BIGINT,
    IN p_id_base       BIGINT,
    IN p_id_destino    BIGINT
)
proc: BEGIN
    DECLARE v_id_rq BIGINT;
    DECLARE v_n     INT DEFAULT 0;

    IF FN_PermisoAccion(p_id_usuario, 'expediente_bandeja') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver los expedientes digitales.' AS Mensaje;
        LEAVE proc;
    END IF;
    SELECT id_requerimiento INTO v_id_rq FROM expediente_digital WHERE id_expediente = p_id_expediente AND eliminado_en IS NULL;
    IF v_id_rq IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'El expediente no existe.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT COUNT(*) INTO v_n FROM propuesta_comercial
    WHERE id_propuesta IN (p_id_base, p_id_destino) AND id_requerimiento = v_id_rq AND eliminado_en IS NULL;
    IF v_n < 2 THEN
        SELECT 1 AS IdTipoMensaje, 'Las versiones a comparar deben ser de una propuesta de este expediente.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;
END$$

DELIMITER ;
