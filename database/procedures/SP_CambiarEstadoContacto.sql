-- ============================================================
-- SP_CambiarEstadoContacto
-- Activa o desactiva un contacto de cliente (HU-81)
-- ============================================================

DROP PROCEDURE IF EXISTS SP_CambiarEstadoContacto;

DELIMITER $$
CREATE PROCEDURE SP_CambiarEstadoContacto(
    IN p_id_contacto BIGINT,
    IN p_estado      VARCHAR(20),
    IN p_usu_mod     VARCHAR(100)
)
BEGIN
    DECLARE v_existe INT;

    SELECT COUNT(*) INTO v_existe
    FROM contacto_cliente
    WHERE id_contacto = p_id_contacto AND SoftDelete = 0;

    IF v_existe = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Contacto no encontrado.' AS Mensaje;
    ELSE
        UPDATE contacto_cliente
        SET estado  = p_estado,
            UsuMod  = p_usu_mod,
            FchMod  = NOW()
        WHERE id_contacto = p_id_contacto;

        SELECT 2 AS IdTipoMensaje, 'Estado actualizado correctamente.' AS Mensaje;
    END IF;
END$$
DELIMITER ;
