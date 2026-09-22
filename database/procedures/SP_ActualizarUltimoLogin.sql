-- ============================================================
-- SP_ActualizarUltimoLogin
-- Registra la fecha/hora del último inicio de sesión del usuario.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ActualizarUltimoLogin;

DELIMITER //

CREATE PROCEDURE SP_ActualizarUltimoLogin(
    IN p_id_usuario BIGINT
)
BEGIN
    UPDATE usuario
    SET    ultimo_login   = NOW(),
           modificado_en  = NOW()
    WHERE  id_usuario = p_id_usuario;

    SELECT 2 AS IdTipoMensaje, 'Login registrado.' AS Mensaje;
END //

DELIMITER ;
