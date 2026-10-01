-- Catálogo genérico de tabla_maestra por Descripcion.
--   Devuelve además num2 y string3 (p.ej. CARGO_USUARIO los usa para
--   indicar el área a la que pertenece cada cargo).
DROP PROCEDURE IF EXISTS SP_ObtenerCatalogo;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerCatalogo(
    IN p_descripcion VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
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
            String2 AS codigo,
            Num2    AS num2,
            String3 AS string3
        FROM tabla_maestra
        WHERE Descripcion = p_descripcion
          AND IdEmpresa   = 1
        ORDER BY Num1;
    END IF;
END$$

DELIMITER ;
