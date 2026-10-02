-- HU-88 — Activar / desactivar un equipo del cliente (sin eliminar).
DROP PROCEDURE IF EXISTS SP_CambiarEstadoEquipoCliente;

DELIMITER $$

CREATE PROCEDURE SP_CambiarEstadoEquipoCliente(
    IN p_id_equipo  BIGINT,
    IN p_estado     VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_usuario BIGINT
)
BEGIN
    DECLARE v_estado         VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado_ant     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_codigo_tw      VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_usuario_login  VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    SET v_estado = LOWER(TRIM(p_estado));

    SELECT estado, codigo_tw INTO v_estado_ant, v_codigo_tw
    FROM equipo_cliente WHERE id_equipo = p_id_equipo AND SoftDelete = 0 LIMIT 1;

    IF v_estado NOT IN ('activo', 'inactivo') THEN
        SELECT 1 AS IdTipoMensaje, 'Estado no válido. Use Activo o Inactivo.' AS Mensaje;
    ELSEIF v_estado_ant IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Equipo no encontrado.' AS Mensaje;
    ELSE
        SELECT correo INTO v_usuario_login FROM usuario WHERE id_usuario = p_id_usuario LIMIT 1;

        UPDATE equipo_cliente SET
            estado    = v_estado,
            es_activo = IF(v_estado = 'activo', 1, 0),
            UsuMod    = v_usuario_login,
            FchMod    = NOW()
        WHERE id_equipo = p_id_equipo;

        SELECT 2 AS IdTipoMensaje, 'Estado actualizado correctamente.' AS Mensaje;
    END IF;
END$$

DELIMITER ;
