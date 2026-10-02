-- ============================================================
-- SP_ObtenerCategorias
-- Lista de categorías de cliente para Mantenimiento de Maestros.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerCategorias;

DELIMITER //

CREATE PROCEDURE SP_ObtenerCategorias()
BEGIN
    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT
        id_categoria,
        nombre,
        descripcion,
        prioridad_atencion,
        pct_ganancia_min,
        pct_ganancia_max,
        estado
    FROM categoria_cliente
    WHERE SoftDelete = 0
    ORDER BY COALESCE(prioridad_atencion, 9999) ASC, nombre ASC;
END //

DELIMITER ;
