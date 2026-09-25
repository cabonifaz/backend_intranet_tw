-- ============================================================
-- SP_CambiarEstadoCliente
-- Activa o desactiva (soft-toggle) un cliente.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_CambiarEstadoCliente;

DELIMITER //

CREATE PROCEDURE SP_CambiarEstadoCliente(
    IN p_id_cliente BIGINT,
    IN p_estado     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci,
    IN p_usu_mod    VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci
)
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM cliente
        WHERE id_cliente = p_id_cliente AND SoftDelete = 0
    ) THEN
        SELECT 1 AS IdTipoMensaje, 'Cliente no encontrado.' AS Mensaje;
    ELSE
        UPDATE cliente
        SET estado  = p_estado,
            UsuMod  = p_usu_mod,
            FchMod  = NOW()
        WHERE id_cliente = p_id_cliente AND SoftDelete = 0;

        SELECT 2 AS IdTipoMensaje, 'Estado actualizado correctamente.' AS Mensaje;
    END IF;
END //

DELIMITER ;
