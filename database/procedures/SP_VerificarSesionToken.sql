-- ============================================================
-- SP_VerificarSesionToken
-- Valida que el sesion_token del JWT coincida con el almacenado
-- en la BD para el usuario. Si no coincide, la sesión fue
-- reemplazada por un login más reciente.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_VerificarSesionToken;

DELIMITER //

CREATE PROCEDURE SP_VerificarSesionToken(
    IN p_id_usuario   BIGINT,
    IN p_sesion_token VARCHAR(36)
)
BEGIN
    IF EXISTS (
        SELECT 1 FROM usuario
        WHERE  id_usuario   = p_id_usuario
          AND  sesion_token = p_sesion_token
    ) THEN
        SELECT 2 AS IdTipoMensaje, 'Token válido.' AS Mensaje;
    ELSE
        SELECT 1 AS IdTipoMensaje, 'Sesión invalidada por un acceso más reciente.' AS Mensaje;
    END IF;
END //

DELIMITER ;
