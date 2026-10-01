-- HU-83 — Sedes operativas para asignar al usuario (catálogo 69)
DROP PROCEDURE IF EXISTS SP_ObtenerSedesOperativas;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerSedesOperativas()
BEGIN
    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT
        Num1    AS id_sede,
        String1 AS nombre,
        String2 AS ubicacion,
        String3 AS tipo
    FROM tabla_maestra
    WHERE IdMaestro = 69
      AND IdEmpresa = 1
      AND eliminado_en IS NULL
    ORDER BY Num1;
END$$

DELIMITER ;
