-- ============================================================
-- SP_ObtenerUsuarioPorCorreo
-- Obtiene los datos de un usuario activo por su correo.
-- Por seguridad, devuelve el mismo mensaje genérico tanto si
-- el usuario no existe como si está dado de baja.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerUsuarioPorCorreo;

DELIMITER //

CREATE PROCEDURE SP_ObtenerUsuarioPorCorreo(
    IN p_correo VARCHAR(150) CHARSET utf8mb4 COLLATE utf8mb4_unicode_ci
)
BEGIN
    DECLARE v_id BIGINT DEFAULT NULL;

    SELECT id_usuario
    INTO   v_id
    FROM   usuario
    WHERE  correo        = p_correo
      AND  eliminado_en  IS NULL
    LIMIT 1;

    IF v_id IS NULL THEN
        -- Usuario no encontrado o dado de baja: mensaje genérico (anti-enumeración)
        SELECT 1 AS IdTipoMensaje, 'Correo o contraseña incorrectos.' AS Mensaje;
    ELSE
        SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

        SELECT id_usuario,
               nombre,
               apellido,
               correo,
               password_hash,
               rol_sistema,
               canal_acceso,
               estado
        FROM   usuario
        WHERE  id_usuario = v_id;
    END IF;
END //

DELIMITER ;
