-- Expediente Digital (interno): recalcula el estado guardado del expediente según sus bloqueos y excepciones.
--   bloqueado      hay bloqueos abiertos
--   con_excepcion  sin bloqueos, pero con excepciones abiertas
--   activo         sin pendientes
-- Un expediente cerrado no cambia. El SLA vencido y "listo para avanzar" se calculan al consultar
-- (SP_CalcularExpedientes) porque dependen de la hora y de los requisitos de la etapa.
-- No devuelve resultados.
DROP PROCEDURE IF EXISTS SP_ActualizarEstadoExpediente;

DELIMITER $$

CREATE PROCEDURE SP_ActualizarEstadoExpediente(
    IN p_id_expediente BIGINT,
    IN p_id_usuario    BIGINT
)
BEGIN
    DECLARE v_bloqueos    INT DEFAULT 0;
    DECLARE v_excepciones INT DEFAULT 0;

    SELECT IFNULL(SUM(clase = 'bloqueo'), 0), IFNULL(SUM(clase = 'excepcion'), 0)
      INTO v_bloqueos, v_excepciones
    FROM expediente_bloqueador
    WHERE id_expediente = p_id_expediente AND resuelto = 0 AND eliminado_en IS NULL;

    UPDATE expediente_digital
    SET estado = CASE WHEN v_bloqueos > 0    THEN 'bloqueado'
                      WHEN v_excepciones > 0 THEN 'con_excepcion'
                      ELSE 'activo' END,
        modificado_por = p_id_usuario
    WHERE id_expediente = p_id_expediente
      AND estado <> 'cerrado'
      AND estado <> CASE WHEN v_bloqueos > 0    THEN 'bloqueado'
                         WHEN v_excepciones > 0 THEN 'con_excepcion'
                         ELSE 'activo' END;
END$$

DELIMITER ;
