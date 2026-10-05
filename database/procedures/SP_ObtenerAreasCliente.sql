-- Áreas del cliente (por empresa): lista para "ubicación específica" del equipo
DROP PROCEDURE IF EXISTS SP_ObtenerAreasCliente;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerAreasCliente(
    IN p_id_cliente   BIGINT,
    IN p_solo_activas TINYINT
)
BEGIN
    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT a.id_area, a.id_cliente, a.nombre,
           IF(a.estado = 'activo', 'Activo', 'Inactivo') AS estado,
           (SELECT COUNT(*) FROM equipo_cliente e
            WHERE e.id_cliente = a.id_cliente AND e.ubicacion_especifica = a.nombre AND e.SoftDelete = 0) AS equipos
    FROM area_cliente a
    WHERE a.id_cliente = p_id_cliente
      AND a.SoftDelete = 0
      AND (IFNULL(p_solo_activas, 1) = 0 OR a.estado = 'activo')
    ORDER BY a.nombre;
END$$

DELIMITER ;
