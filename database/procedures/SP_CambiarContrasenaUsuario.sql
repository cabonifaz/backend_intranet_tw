-- ============================================================
-- SP_CambiarContrasenaUsuario
-- Actualiza el password_hash del usuario y limpia el flag
-- forzar_cambio_contrasena. La verificación del hash actual
-- se hace en el caso de uso (bcrypt vive en el adapter C#).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_CambiarContrasenaUsuario;

DELIMITER $$

CREATE PROCEDURE SP_CambiarContrasenaUsuario(
    IN p_id_usuario          BIGINT,
    IN p_password_hash_nuevo VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        DECLARE v_err_code INT;
        DECLARE v_err_msg  TEXT;
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1
            v_err_msg  = MESSAGE_TEXT,
            v_err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje,
               CONCAT('[MySQL ', IFNULL(v_err_code, 0), '] ', IFNULL(v_err_msg, 'error desconocido')) AS Mensaje;
    END;

    -- Validación: usuario existe
    IF NOT EXISTS (
        SELECT 1 FROM usuario
        WHERE id_usuario = p_id_usuario AND eliminado_en IS NULL
    ) THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no encontrado.' AS Mensaje;
        LEAVE proc;
    END IF;

    START TRANSACTION;

    UPDATE usuario
    SET password_hash            = p_password_hash_nuevo,
        forzar_cambio_contrasena = 0,
        modificado_en            = NOW(),
        modificado_por           = p_id_usuario
    WHERE id_usuario = p_id_usuario;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en)
    VALUES ('usuario', p_id_usuario, 'cambio_contrasena', NULL, NULL,
            'El usuario cambió su contraseña.', p_id_usuario, NOW());

    COMMIT;

    SELECT 2 AS IdTipoMensaje, 'Contraseña actualizada correctamente.' AS Mensaje;
END$$

DELIMITER ;
