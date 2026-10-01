-- HU-82 — Activar / desactivar un usuario desde el listado
--   Al desactivar se invalida su sesión (sesion_token = NULL)
DROP PROCEDURE IF EXISTS SP_CambiarEstadoUsuario;

DELIMITER $$

CREATE PROCEDURE SP_CambiarEstadoUsuario(
    IN p_id_usuario          BIGINT,
    IN p_estado              VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_usuario_ejecutor BIGINT
)
BEGIN
    DECLARE v_estado VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    SET v_estado = LOWER(TRIM(p_estado));

    IF v_estado NOT IN ('activo', 'inactivo') THEN
        SELECT 1 AS IdTipoMensaje, 'Estado no válido. Use Activo o Inactivo.' AS Mensaje;
    ELSEIF NOT EXISTS (
        SELECT 1 FROM usuario WHERE id_usuario = p_id_usuario AND eliminado_en IS NULL
    ) THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no encontrado.' AS Mensaje;
    ELSEIF v_estado = 'inactivo' AND p_id_usuario = p_id_usuario_ejecutor THEN
        SELECT 1 AS IdTipoMensaje, 'No puedes desactivar tu propio usuario.' AS Mensaje;
    ELSE
        UPDATE usuario SET
            estado         = v_estado,
            sesion_token   = IF(v_estado = 'inactivo', NULL, sesion_token),
            modificado_en  = NOW(),
            modificado_por = p_id_usuario_ejecutor
        WHERE id_usuario = p_id_usuario;

        SELECT 2 AS IdTipoMensaje, 'Estado actualizado correctamente.' AS Mensaje;
    END IF;
END$$

DELIMITER ;
