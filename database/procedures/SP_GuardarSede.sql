DROP PROCEDURE IF EXISTS SP_GuardarSede;

DELIMITER //
CREATE PROCEDURE SP_GuardarSede(
    IN p_id_sede         BIGINT,
    IN p_id_cliente      BIGINT,
    IN p_nombre          VARCHAR(200),
    IN p_tipo_instalacion VARCHAR(100),
    IN p_region          VARCHAR(100),
    IN p_provincia       VARCHAR(100),
    IN p_distrito        VARCHAR(100),
    IN p_urbanizacion    VARCHAR(200),
    IN p_direccion_exacta VARCHAR(500),
    IN p_usu_cre         VARCHAR(100)
)
BEGIN
    IF p_id_sede = 0 THEN
        -- Nueva sede
        INSERT INTO sede_cliente (
            id_cliente, nombre, tipo_instalacion, region, provincia,
            distrito, urbanizacion, direccion_exacta, estado, UsuCre, FchCre
        ) VALUES (
            p_id_cliente, p_nombre, p_tipo_instalacion, p_region, p_provincia,
            p_distrito, p_urbanizacion, p_direccion_exacta, 'Activo', p_usu_cre, NOW()
        );

        SELECT 2 AS IdTipoMensaje, 'Sede registrada correctamente.' AS Mensaje;
        SELECT LAST_INSERT_ID() AS id_sede;
    ELSE
        -- Editar sede existente
        IF NOT EXISTS (SELECT 1 FROM sede_cliente WHERE id_sede = p_id_sede AND SoftDelete = 0) THEN
            SELECT 1 AS IdTipoMensaje, 'Sede no encontrada.' AS Mensaje;
        ELSE
            UPDATE sede_cliente
            SET nombre           = p_nombre,
                tipo_instalacion = p_tipo_instalacion,
                region           = p_region,
                provincia        = p_provincia,
                distrito         = p_distrito,
                urbanizacion     = p_urbanizacion,
                direccion_exacta = p_direccion_exacta,
                UsuMod           = p_usu_cre,
                FchMod           = NOW()
            WHERE id_sede = p_id_sede AND SoftDelete = 0;

            SELECT 2 AS IdTipoMensaje, 'Sede actualizada correctamente.' AS Mensaje;
            SELECT p_id_sede AS id_sede;
        END IF;
    END IF;
END //
DELIMITER ;
