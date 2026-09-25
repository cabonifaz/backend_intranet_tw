-- ============================================================
-- SP_ObtenerCatalogo
-- Devuelve los items de un catálogo de tabla_maestra por Descripcion.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerCatalogo;

DELIMITER //

CREATE PROCEDURE SP_ObtenerCatalogo(
    IN p_descripcion VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci
)
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM tabla_maestra
        WHERE Descripcion = p_descripcion AND IdEmpresa = 1
    ) THEN
        SELECT 1 AS IdTipoMensaje, CONCAT('Catálogo no encontrado: ', p_descripcion) AS Mensaje;
    ELSE
        SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

        SELECT
            Num1    AS id,
            String1 AS nombre,
            String2 AS codigo
        FROM tabla_maestra
        WHERE Descripcion = p_descripcion
          AND IdEmpresa   = 1
        ORDER BY Num1;
    END IF;
END //

DELIMITER ;
