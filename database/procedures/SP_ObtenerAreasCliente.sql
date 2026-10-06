-- Áreas asignadas a un cliente (catálogo AREA_USUARIO). Alimenta el dropdown
-- "Ubicación" de la ficha de equipos. p_solo_activas se mantiene por compatibilidad.
DROP PROCEDURE IF EXISTS SP_ObtenerAreasCliente;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerAreasCliente(
    IN p_id_cliente   BIGINT,
    IN p_solo_activas TINYINT
)
BEGIN
    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT t.String2 AS codigo, t.String1 AS nombre
    FROM cliente_area ca
    JOIN tabla_maestra t
      ON t.IdMaestro = 79 AND t.IdEmpresa = 1 AND t.String2 = ca.area
    WHERE ca.id_cliente = p_id_cliente
    ORDER BY t.String1;
END$$

DELIMITER ;
