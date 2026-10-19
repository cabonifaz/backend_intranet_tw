-- Consulta de RUC — registra cada llamada a un proveedor externo (consumo y errores)
DROP PROCEDURE IF EXISTS SP_RegistrarConsultaRucLog;

DELIMITER $$

CREATE PROCEDURE SP_RegistrarConsultaRucLog(
    IN p_ruc         CHAR(11)     CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_proveedor   VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_resultado   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_codigo_http INT,
    IN p_detalle     VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_duracion_ms INT,
    IN p_id_usuario  BIGINT
)
BEGIN
    DECLARE v_usu VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SELECT correo INTO v_usu FROM usuario WHERE id_usuario = p_id_usuario LIMIT 1;

    INSERT INTO consulta_ruc_log (ruc, proveedor, resultado, codigo_http, detalle, duracion_ms,
                                  id_usuario, SoftDelete, UsuCre, FchCre)
    VALUES (p_ruc, p_proveedor, p_resultado, p_codigo_http, LEFT(p_detalle, 500), p_duracion_ms,
            p_id_usuario, 0, IFNULL(v_usu, 'sistema'), NOW());

    SELECT 2 AS IdTipoMensaje, 'Registrado.' AS Mensaje;
END$$

DELIMITER ;
