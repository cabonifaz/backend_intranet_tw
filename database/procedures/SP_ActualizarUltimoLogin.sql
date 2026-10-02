	-- ============================================================
-- SP_ActualizarUltimoLogin
-- Registra el último inicio de sesión y genera un nuevo token
-- de sesión único, invalidando sesiones previas del mismo usuario.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ActualizarUltimoLogin;

DELIMITER //

CREATE PROCEDURE SP_ActualizarUltimoLogin(
    IN p_id_usuario BIGINT
)
BEGIN
    DECLARE v_token VARCHAR(36);
    SET v_token = UUID();

    UPDATE usuario
    SET    sesion_token  = v_token,
           ultimo_login  = NOW(),
           modificado_en = NOW()
    WHERE  id_usuario = p_id_usuario;

    SELECT 2        AS IdTipoMensaje, 'Login registrado.' AS Mensaje;
    SELECT v_token  AS sesion_token;
END //

DELIMITER ;
