-- HU-87 — Activar / desactivar un procedimiento (no se elimina) + auditoría
DROP PROCEDURE IF EXISTS SP_CambiarEstadoProcedimiento;

DELIMITER $$

CREATE PROCEDURE SP_CambiarEstadoProcedimiento(
    IN p_id_procedimiento BIGINT,
    IN p_estado           VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_usuario       BIGINT
)
BEGIN
    DECLARE v_estado     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado_ant VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_codigo     VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_usu        VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    SET v_estado = LOWER(TRIM(p_estado));

    SELECT estado, codigo INTO v_estado_ant, v_codigo
    FROM procedimiento_metrologico
    WHERE id_procedimiento = p_id_procedimiento AND SoftDelete = 0 LIMIT 1;

    IF v_estado NOT IN ('activo', 'inactivo') THEN
        SELECT 1 AS IdTipoMensaje, 'Estado no válido. Use Activo o Inactivo.' AS Mensaje;
    ELSEIF v_estado_ant IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Procedimiento no encontrado.' AS Mensaje;
    ELSEIF v_estado = 'activo' AND EXISTS (
        SELECT 1 FROM procedimiento_metrologico
        WHERE codigo = v_codigo AND estado = 'activo'
          AND SoftDelete = 0 AND id_procedimiento <> p_id_procedimiento
    ) THEN
        SELECT 1 AS IdTipoMensaje, 'No se puede activar: ya existe otro procedimiento activo con el mismo código.' AS Mensaje;
    ELSE
        SELECT correo INTO v_usu FROM usuario WHERE id_usuario = p_id_usuario LIMIT 1;

        UPDATE procedimiento_metrologico SET
            estado = v_estado,
            UsuMod = v_usu,
            FchMod = NOW()
        WHERE id_procedimiento = p_id_procedimiento;

        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en)
        VALUES ('procedimiento', p_id_procedimiento, 'cambio_estado', v_estado_ant, v_estado,
                CONCAT('Procedimiento ', v_codigo, ': ', v_estado_ant, ' → ', v_estado, '.'), p_id_usuario, NOW());

        SELECT 2 AS IdTipoMensaje, 'Estado actualizado correctamente.' AS Mensaje;
    END IF;
END$$

DELIMITER ;
