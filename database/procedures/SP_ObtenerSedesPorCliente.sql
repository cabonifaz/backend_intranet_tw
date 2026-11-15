-- SP_ObtenerSedesPorCliente: sedes del cliente con su ubicación exacta (latitud/longitud, NULL si no se ha marcado) y su referencia (antes urbanizacion, migración 116). Solo lectura.
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
        referencia,
        referencia AS urbanizacion,   -- TRANSICIÓN: lo lee el back anterior mientras termina de desplegarse; quitar después
        direccion_exacta,
        latitud,
        longitud,
        estado
    FROM sede_cliente
    WHERE id_cliente = p_id_cliente
      AND SoftDelete = 0
    ORDER BY id_sede ASC;
END //
DELIMITER ;
