-- Servicio de correo — registra el resultado de un envío (sin contraseña ni cuerpo)
DROP PROCEDURE IF EXISTS SP_RegistrarCorreoEnvio;

DELIMITER $$

CREATE PROCEDURE SP_RegistrarCorreoEnvio(
    IN p_tipo         VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_destinatario VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_asunto       VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_entidad_tipo VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_entidad   BIGINT,
    IN p_proveedor    VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_estado       VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_mensaje   VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_error        VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_usuario   BIGINT
)
BEGIN
    DECLARE v_usu VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SELECT correo INTO v_usu FROM usuario WHERE id_usuario = p_id_usuario LIMIT 1;

    INSERT INTO correo_envio (tipo, destinatario, asunto, entidad_tipo, id_entidad, proveedor, estado,
                              id_mensaje, error, id_usuario, SoftDelete, UsuCre, FchCre)
    VALUES (p_tipo, p_destinatario, LEFT(p_asunto, 300), p_entidad_tipo, p_id_entidad, p_proveedor, p_estado,
            p_id_mensaje, LEFT(p_error, 500), p_id_usuario, 0, IFNULL(v_usu, 'sistema'), NOW());

    SELECT 2 AS IdTipoMensaje, 'Registrado.' AS Mensaje;
END$$

DELIMITER ;
