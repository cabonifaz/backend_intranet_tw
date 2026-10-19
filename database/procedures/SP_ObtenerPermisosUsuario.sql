-- Permisos del usuario que inició sesión (para armar el menú y habilitar acciones en el front).
DROP PROCEDURE IF EXISTS SP_ObtenerPermisosUsuario;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerPermisosUsuario(
    IN p_id_usuario BIGINT
)
BEGIN
    DECLARE v_area VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_rol  VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    SELECT IFNULL(area, ''), rol_sistema INTO v_area, v_rol
    FROM usuario
    WHERE id_usuario = p_id_usuario AND eliminado_en IS NULL AND estado = 'activo';

    IF v_rol IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no encontrado o inactivo.' AS Mensaje;
    ELSE
        CALL SP_ObtenerPermisosAreaRol(v_area, v_rol);
    END IF;
END$$

DELIMITER ;
