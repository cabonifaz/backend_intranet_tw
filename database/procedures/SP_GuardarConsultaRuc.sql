-- Consulta de RUC — guarda (o refresca) la respuesta del proveedor en la caché
--   Una sola fila viva por RUC: si existe se actualiza, si no se inserta.
DROP PROCEDURE IF EXISTS SP_GuardarConsultaRuc;

DELIMITER $$

CREATE PROCEDURE SP_GuardarConsultaRuc(
    IN p_ruc          CHAR(11)     CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_razon_social VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_estado       VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_condicion    VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_direccion    VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_ubigeo       CHAR(6)      CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_fuente       VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_fecha_dato   DATE,
    IN p_proveedor    VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_usuario   BIGINT
)
proc: BEGIN
    DECLARE v_id  BIGINT;
    DECLARE v_usu VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF p_ruc IS NULL OR p_ruc NOT REGEXP '^[0-9]{11}$' OR IFNULL(TRIM(p_razon_social), '') = '' THEN
        SELECT 1 AS IdTipoMensaje, 'Datos de RUC incompletos.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT correo INTO v_usu FROM usuario WHERE id_usuario = p_id_usuario LIMIT 1;

    SELECT id_consulta_ruc INTO v_id
    FROM consulta_ruc WHERE ruc = p_ruc AND SoftDelete = 0
    ORDER BY id_consulta_ruc LIMIT 1;

    IF v_id IS NULL THEN
        INSERT INTO consulta_ruc (ruc, razon_social, estado, condicion, direccion, ubigeo, fuente,
                                  fecha_dato, proveedor, consultado_en, SoftDelete, UsuCre, FchCre)
        VALUES (p_ruc, TRIM(p_razon_social), p_estado, p_condicion, p_direccion,
                NULLIF(p_ubigeo, ''), p_fuente, p_fecha_dato, p_proveedor, NOW(), 0, IFNULL(v_usu, 'sistema'), NOW());
    ELSE
        UPDATE consulta_ruc SET
            razon_social  = TRIM(p_razon_social),
            estado        = p_estado,
            condicion     = p_condicion,
            direccion     = p_direccion,
            ubigeo        = NULLIF(p_ubigeo, ''),
            fuente        = p_fuente,
            fecha_dato    = p_fecha_dato,
            proveedor     = p_proveedor,
            consultado_en = NOW(),
            UsuMod        = IFNULL(v_usu, 'sistema'),
            FchMod        = NOW()
        WHERE id_consulta_ruc = v_id;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Consulta de RUC guardada.' AS Mensaje;
END$$

DELIMITER ;
