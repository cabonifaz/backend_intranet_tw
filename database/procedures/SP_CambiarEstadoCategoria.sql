-- ============================================================
-- SP_CambiarEstadoCategoria
-- Activa o inactiva una categoría de cliente.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_CambiarEstadoCategoria;

DELIMITER //

CREATE PROCEDURE SP_CambiarEstadoCategoria(
    IN p_id_categoria INT,
    IN p_estado       VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_usu_mod      VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM categoria_cliente
        WHERE id_categoria = p_id_categoria AND SoftDelete = 0
    ) THEN
        SELECT 1 AS IdTipoMensaje, 'Categoría no encontrada.' AS Mensaje;
    ELSE
        UPDATE categoria_cliente SET
            estado = p_estado,
            UsuMod = p_usu_mod,
            FchMod = NOW()
        WHERE id_categoria = p_id_categoria AND SoftDelete = 0;

        SELECT 2 AS IdTipoMensaje, 'Estado actualizado correctamente.' AS Mensaje;
    END IF;
END //

DELIMITER ;
