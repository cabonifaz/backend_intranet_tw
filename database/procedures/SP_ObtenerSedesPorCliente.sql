DROP PROCEDURE IF EXISTS SP_ObtenerSedesPorCliente;

DELIMITER //
CREATE PROCEDURE SP_ObtenerSedesPorCliente(
    IN p_id_cliente BIGINT
)
BEGIN
    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT
        id_sede,
        id_cliente,
        nombre,
        tipo_instalacion,
        region,
        provincia,
        distrito,
        urbanizacion,
        direccion_exacta,
        estado
    FROM sede_cliente
    WHERE id_cliente = p_id_cliente
      AND SoftDelete = 0
    ORDER BY id_sede ASC;
END //
DELIMITER ;
