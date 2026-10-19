-- Áreas por cliente (nombres libres, estado activo/inactivo).
--   Alimenta el modal "Áreas del Cliente" en la ficha y el dropdown de
--   "Ubicación" en la ficha de equipos.
--   p_solo_activas = 1 → solo las activas (default usado por el dropdown).
--                  = 0 → todas (modal de mantenimiento).
--   Devuelve también el conteo de equipos del cliente que usan cada área
--   (para que la UI muestre el badge "N equipos" y advierta antes de
--   desactivar un área en uso).
--   Reescrito por la migración 37 — volvió al modelo por cliente tras
--   revertir la decisión de la migración 35.
DROP PROCEDURE IF EXISTS SP_ObtenerAreasCliente;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerAreasCliente(
    IN p_id_cliente   BIGINT,
    IN p_solo_activas TINYINT
)
BEGIN
    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT a.id_area,
           a.id_cliente,
           a.nombre,
           IF(a.estado = 'activo', 'Activo', 'Inactivo') AS estado,
           (SELECT COUNT(*) FROM equipo_cliente e
            WHERE e.id_cliente = a.id_cliente
              AND e.ubicacion_especifica = a.nombre
              AND e.SoftDelete = 0) AS equipos
    FROM area_cliente a
    WHERE a.id_cliente = p_id_cliente
      AND a.SoftDelete = 0
      AND (IFNULL(p_solo_activas, 1) = 0 OR a.estado = 'activo')
    ORDER BY a.nombre;
END$$

DELIMITER ;
