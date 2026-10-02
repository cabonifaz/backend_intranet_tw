-- HU-87 / HU-86 — Procedimientos activos para el combo de Suministros (clase Servicio)
DROP PROCEDURE IF EXISTS SP_ObtenerProcedimientosOpciones;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerProcedimientosOpciones()
BEGIN
    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT
        codigo AS value,
        CONCAT(codigo, ' · ',
               LEFT(descripcion, 70),
               IF(CHAR_LENGTH(descripcion) > 70, '…', '')) AS label
    FROM procedimiento_metrologico
    WHERE SoftDelete = 0 AND estado = 'activo'
    ORDER BY codigo ASC, anio DESC;
END$$

DELIMITER ;
