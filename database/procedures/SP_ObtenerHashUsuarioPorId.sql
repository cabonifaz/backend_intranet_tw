-- ============================================================
-- SP_ObtenerHashUsuarioPorId
-- Devuelve el password_hash de un usuario por su id.
-- Lo usa el caso de uso CambiarContrasena para verificar la
-- contraseña actual antes de aceptar el cambio.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerHashUsuarioPorId;

DELIMITER //

CREATE PROCEDURE SP_ObtenerHashUsuarioPorId(
    IN p_id_usuario BIGINT
)
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM usuario
        WHERE id_usuario = p_id_usuario AND eliminado_en IS NULL
    ) THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no encontrado.' AS Mensaje;
    ELSE
        SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

        SELECT password_hash
        FROM   usuario
        WHERE  id_usuario = p_id_usuario;
    END IF;
END //

DELIMITER ;
