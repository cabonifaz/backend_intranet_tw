-- HU-82 / HU-84 — Activar / desactivar una asignación de suplencia
DROP PROCEDURE IF EXISTS SP_CambiarEstadoSuplente;

DELIMITER $$

CREATE PROCEDURE SP_CambiarEstadoSuplente(
    IN p_id_asignacion INT,
    IN p_estado        VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_usuario       VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
BEGIN
    DECLARE v_estado VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    SET v_estado = LOWER(TRIM(p_estado));

    IF v_estado NOT IN ('activo', 'inactivo') THEN
        SELECT 1 AS IdTipoMensaje, 'Estado no válido. Use Activo o Inactivo.' AS Mensaje;
    ELSEIF NOT EXISTS (
        SELECT 1 FROM usuario_suplente WHERE id = p_id_asignacion AND SoftDelete = 0
    ) THEN
        SELECT 1 AS IdTipoMensaje, 'Asignación no encontrada.' AS Mensaje;
    ELSE
        UPDATE usuario_suplente SET
            activo = IF(v_estado = 'activo', 1, 0),
            UsuMod = p_usuario,
            FchMod = NOW()
        WHERE id = p_id_asignacion;

        SELECT 2 AS IdTipoMensaje, 'Estado de la suplencia actualizado.' AS Mensaje;
    END IF;
END$$

DELIMITER ;
