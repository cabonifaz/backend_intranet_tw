-- HU-83 — Sedes de Total Weight (catálogo 69 SEDE_OPERATIVA_TW).
--   Se mantiene por compatibilidad; el front puede usar también
--   GET /api/maestros/catalogos/SEDE_OPERATIVA_TW.
DROP PROCEDURE IF EXISTS SP_ObtenerSedesOperativas;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerSedesOperativas()
BEGIN
    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT
        Num1    AS id_sede,
        String1 AS nombre,
        String3 AS ubicacion,
        'Sede TW' AS tipo,
        String2 AS codigo
    FROM tabla_maestra
    WHERE IdMaestro = 69
      AND IdEmpresa = 1
      AND eliminado_en IS NULL
    ORDER BY Num1;
END$$

DELIMITER ;
