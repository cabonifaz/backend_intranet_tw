-- Reenviar credenciales — asigna una nueva contraseña temporal (solo el hash)
--   y obliga a cambiarla en el siguiente inicio de sesión.
--   Devuelve los datos para armar el correo. Registra auditoría sin la contraseña.
DROP PROCEDURE IF EXISTS SP_RestablecerContrasenaTemporal;

DELIMITER $$

CREATE PROCEDURE SP_RestablecerContrasenaTemporal(
    IN p_id_usuario    BIGINT,
    IN p_password_hash VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_ejecutor   BIGINT
)
proc: BEGIN
    DECLARE v_estado VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_correo VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_usu    VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_password_hash, '') = '' THEN
        SELECT 1 AS IdTipoMensaje, 'La contraseña temporal es obligatoria.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT estado, correo INTO v_estado, v_correo
    FROM usuario
    WHERE id_usuario = p_id_usuario AND eliminado_en IS NULL
    LIMIT 1;

    IF v_correo IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no encontrado.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF v_estado <> 'activo' THEN
        SELECT 1 AS IdTipoMensaje, 'El usuario no está activo. Actívelo antes de reenviar sus credenciales.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT correo INTO v_usu FROM usuario WHERE id_usuario = p_id_ejecutor LIMIT 1;

    START TRANSACTION;

    UPDATE usuario SET
        password_hash            = p_password_hash,
        forzar_cambio_contrasena = 1,
        modificado_en            = NOW(),
        modificado_por           = p_id_ejecutor
    WHERE id_usuario = p_id_usuario;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en)
    VALUES ('usuario', p_id_usuario, 'reenvio_credenciales', NULL, NULL,
            CONCAT('Contraseña temporal regenerada para ', v_correo, ' por ', IFNULL(v_usu, 'sistema'), '.'),
            p_id_ejecutor, NOW());

    COMMIT;

    SELECT 2 AS IdTipoMensaje, 'Contraseña temporal asignada.' AS Mensaje;
    SELECT id_usuario, correo, nombre, apellido
    FROM usuario WHERE id_usuario = p_id_usuario;
END$$

DELIMITER ;
