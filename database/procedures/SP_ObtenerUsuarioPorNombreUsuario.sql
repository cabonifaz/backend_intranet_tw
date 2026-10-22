-- ============================================================
-- SP_ObtenerUsuarioPorNombreUsuario  (App Mobile HU-01)
-- Obtiene los datos de acceso de un usuario por su nombre de usuario
-- de la app móvil. La app NO acepta correo.
-- Por seguridad devuelve el mismo mensaje genérico si el usuario
-- no existe o fue dado de baja (anti-enumeración).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerUsuarioPorNombreUsuario;

DELIMITER //

CREATE PROCEDURE SP_ObtenerUsuarioPorNombreUsuario(
    IN p_nombre_usuario VARCHAR(50) CHARSET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
BEGIN
    DECLARE v_id BIGINT DEFAULT NULL;

    SELECT id_usuario
    INTO   v_id
    FROM   usuario
    WHERE  nombre_usuario = LOWER(TRIM(p_nombre_usuario))
      AND  eliminado_en   IS NULL
    LIMIT 1;

    IF v_id IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario o contraseña incorrectos.' AS Mensaje;
    ELSE
        SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

        SELECT id_usuario,
               nombre_usuario,
               nombre,
               apellido,
               correo,
               password_hash,
               rol_sistema,
               canal_acceso,
               estado,
               cargo,
               area,
               forzar_cambio_contrasena
        FROM   usuario
        WHERE  id_usuario = v_id;
    END IF;
END //

DELIMITER ;
