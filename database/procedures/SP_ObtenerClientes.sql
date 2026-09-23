-- ============================================================
-- SP_ObtenerClientes
-- Lista de clientes para el módulo de Mantenimiento de Maestros.
-- Soporta búsqueda por RUC/razón social y filtro por estado.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerClientes;

DELIMITER //

CREATE PROCEDURE SP_ObtenerClientes(
    IN p_busqueda  VARCHAR(300),
    IN p_estado    VARCHAR(20)
)
BEGIN
    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT
        c.id_cliente,
        c.ruc,
        c.razon_social,
        c.nombre_comercial,
        c.tipo_cliente,
        c.condicion_fiscal,
        c.condicion_contribuyente,
        c.es_vip,
        c.estado
    FROM clientes c
    WHERE c.SoftDelete = 0
      AND (p_estado IS NULL OR p_estado = '' OR c.estado = p_estado)
      AND (
          p_busqueda IS NULL OR p_busqueda = ''
          OR c.ruc          LIKE CONCAT('%', p_busqueda, '%')
          OR c.razon_social  LIKE CONCAT('%', p_busqueda, '%')
          OR c.nombre_comercial LIKE CONCAT('%', p_busqueda, '%')
      )
    ORDER BY c.razon_social ASC;
END //

DELIMITER ;
