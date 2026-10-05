-- Activar / desactivar un área del cliente (no se elimina)
DROP PROCEDURE IF EXISTS SP_CambiarEstadoAreaCliente;

DELIMITER $$

CREATE PROCEDURE SP_CambiarEstadoAreaCliente(
    IN p_id_area    BIGINT,
    IN p_estado     VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_usuario BIGINT
)
BEGIN
    DECLARE v_usu VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    IF LOWER(TRIM(p_estado)) NOT IN ('activo', 'inactivo') THEN
        SELECT 1 AS IdTipoMensaje, 'Estado no válido. Use Activo o Inactivo.' AS Mensaje;
    ELSEIF NOT EXISTS (SELECT 1 FROM area_cliente WHERE id_area = p_id_area AND SoftDelete = 0) THEN
        SELECT 1 AS IdTipoMensaje, 'Área no encontrada.' AS Mensaje;
    ELSE
        SELECT correo INTO v_usu FROM usuario WHERE id_usuario = p_id_usuario LIMIT 1;
        UPDATE area_cliente SET estado = LOWER(TRIM(p_estado)), UsuMod = v_usu, FchMod = NOW()
        WHERE id_area = p_id_area;
        SELECT 2 AS IdTipoMensaje, 'Estado actualizado correctamente.' AS Mensaje;
    END IF;
END$$

DELIMITER ;
