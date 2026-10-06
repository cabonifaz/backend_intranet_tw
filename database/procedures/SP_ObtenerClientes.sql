-- Listado de clientes. Incluye el contacto principal (reunión 02-oct).
DROP PROCEDURE IF EXISTS SP_ObtenerClientes;
DELIMITER $$
CREATE PROCEDURE SP_ObtenerClientes(
    IN p_busqueda   VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_estado     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_pagina     INT,
    IN p_por_pagina INT
)
BEGIN
    DECLARE v_offset INT;
    SET v_offset = (p_pagina - 1) * p_por_pagina;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT
        c.id_cliente,
        c.ruc,
        CONCAT('CLI-', LPAD(c.id_cliente, 3, '0')) AS codigo,
        c.razon_social,
        c.nombre_comercial,
        c.tipo_cliente,
        c.condicion_fiscal,
        c.condicion_contribuyente,
        c.es_vip,
        c.estado,
        (SELECT s.nombre FROM sede_cliente s
         WHERE s.id_cliente = c.id_cliente AND s.SoftDelete = 0
         ORDER BY s.id_sede ASC LIMIT 1) AS sede_nombre,
        (SELECT s.region FROM sede_cliente s
         WHERE s.id_cliente = c.id_cliente AND s.SoftDelete = 0
         ORDER BY s.id_sede ASC LIMIT 1) AS sede_region,
        (SELECT COUNT(*) FROM contacto_cliente cc
         WHERE cc.id_cliente = c.id_cliente AND cc.SoftDelete = 0
           AND cc.estado = 'Activo') AS cantidad_contactos,
        (SELECT cc.nombres FROM contacto_cliente cc
         WHERE cc.id_cliente = c.id_cliente AND cc.SoftDelete = 0 AND cc.estado = 'Activo'
         ORDER BY cc.es_contacto_principal DESC, cc.id_contacto ASC LIMIT 1) AS contacto_principal,
        (SELECT cc.correo FROM contacto_cliente cc
         WHERE cc.id_cliente = c.id_cliente AND cc.SoftDelete = 0 AND cc.estado = 'Activo'
         ORDER BY cc.es_contacto_principal DESC, cc.id_contacto ASC LIMIT 1) AS contacto_principal_correo,
        (SELECT COALESCE(NULLIF(cc.telefono_movil, ''), cc.telefono_anexo) FROM contacto_cliente cc
         WHERE cc.id_cliente = c.id_cliente AND cc.SoftDelete = 0 AND cc.estado = 'Activo'
         ORDER BY cc.es_contacto_principal DESC, cc.id_contacto ASC LIMIT 1) AS contacto_principal_telefono
    FROM cliente c
    WHERE c.SoftDelete = 0
      AND (p_estado IS NULL OR p_estado = '' OR c.estado = p_estado)
      AND (
          p_busqueda IS NULL OR p_busqueda = ''
          OR c.ruc             LIKE CONCAT('%', p_busqueda, '%')
          OR c.razon_social     LIKE CONCAT('%', p_busqueda, '%')
          OR c.nombre_comercial LIKE CONCAT('%', p_busqueda, '%')
      )
    ORDER BY c.razon_social ASC
    LIMIT p_por_pagina OFFSET v_offset;

    SELECT COUNT(*) AS total
    FROM cliente c
    WHERE c.SoftDelete = 0
      AND (p_estado IS NULL OR p_estado = '' OR c.estado = p_estado)
      AND (
          p_busqueda IS NULL OR p_busqueda = ''
          OR c.ruc             LIKE CONCAT('%', p_busqueda, '%')
          OR c.razon_social     LIKE CONCAT('%', p_busqueda, '%')
          OR c.nombre_comercial LIKE CONCAT('%', p_busqueda, '%')
      );
END$$
DELIMITER ;
