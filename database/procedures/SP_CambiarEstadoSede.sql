DROP PROCEDURE IF EXISTS SP_CambiarEstadoSede;

DELIMITER //
CREATE PROCEDURE SP_CambiarEstadoSede(
    IN p_id_sede  BIGINT,
    IN p_estado   VARCHAR(20),
    IN p_usu_mod  VARCHAR(100)
)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM sede_cliente WHERE id_sede = p_id_sede AND SoftDelete = 0) THEN
        SELECT 1 AS IdTipoMensaje, 'Sede no encontrada.' AS Mensaje;
    ELSE
        UPDATE sede_cliente
        SET estado  = p_estado,
            UsuMod  = p_usu_mod,
            FchMod  = NOW()
        WHERE id_sede = p_id_sede AND SoftDelete = 0;

        SELECT 2 AS IdTipoMensaje, 'Estado de sede actualizado.' AS Mensaje;
    END IF;
END //
DELIMITER ;
