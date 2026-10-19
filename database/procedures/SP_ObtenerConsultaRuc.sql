-- Consulta de RUC — lee la caché local y si el RUC ya es cliente
--   p_dias_vigencia = días que la caché se considera válida (0 = ignorar caché)
--   Result sets: 1 mensaje, 2 caché vigente (0 o 1 fila), 3 cliente existente (0 o 1 fila)
DROP PROCEDURE IF EXISTS SP_ObtenerConsultaRuc;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerConsultaRuc(
    IN p_ruc           CHAR(11) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_dias_vigencia INT
)
BEGIN
    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT c.ruc, c.razon_social, c.estado, c.condicion, c.direccion, c.ubigeo,
           u.departamento, u.provincia, u.distrito,
           c.fuente, c.fecha_dato, c.proveedor, c.consultado_en
    FROM consulta_ruc c
    LEFT JOIN ubigeo u ON u.codigo = c.ubigeo
    WHERE c.ruc = p_ruc
      AND c.SoftDelete = 0
      AND IFNULL(p_dias_vigencia, 0) > 0
      AND c.consultado_en >= NOW() - INTERVAL p_dias_vigencia DAY
    ORDER BY c.consultado_en DESC
    LIMIT 1;

    SELECT cl.id_cliente, cl.razon_social, cl.estado
    FROM cliente cl
    WHERE cl.ruc = p_ruc
      AND cl.SoftDelete = 0
      AND cl.eliminado_en IS NULL
    ORDER BY cl.id_cliente
    LIMIT 1;
END$$

DELIMITER ;
