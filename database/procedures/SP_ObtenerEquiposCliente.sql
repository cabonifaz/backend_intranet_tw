DROP PROCEDURE IF EXISTS SP_ObtenerEquiposCliente;
DELIMITER $$
CREATE PROCEDURE SP_ObtenerEquiposCliente(
    IN p_busqueda                VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_cliente              BIGINT,
    IN p_id_sede                 BIGINT,
    IN p_clasificacion           VARCHAR(60)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_estado                  VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_solo_vigentes_servicio  TINYINT,
    IN p_pagina                  INT,
    IN p_por_pagina              INT
)
BEGIN
    DECLARE v_por_pagina INT;
    DECLARE v_offset     INT;
    SET v_por_pagina = IF(p_por_pagina IS NULL OR p_por_pagina < 1, 10, p_por_pagina);
    SET v_offset     = (GREATEST(IFNULL(p_pagina, 1), 1) - 1) * v_por_pagina;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT ec.id_equipo,
           ec.num_serie,
           ec.id_cliente,
           c.razon_social                        AS cliente_razon_social,
           ec.id_sede,
           s.nombre                              AS sede_nombre,
           IFNULL(ec.codigo_cliente, '')         AS codigo_cliente,
           ec.codigo_tw,
           ec.clasificacion,
           COALESCE(tm_cl.String1, ec.clasificacion) AS clasificacion_label,
           ec.marca,
           ec.modelo,
           CASE ec.estado
               WHEN 'activo'   THEN 'Activo'
               WHEN 'inactivo' THEN 'Inactivo'
               WHEN 'borrador' THEN 'Borrador'
               ELSE ec.estado
           END                                   AS estado,
           ec.es_activo
    FROM   equipo_cliente ec
    LEFT   JOIN cliente c  ON c.id_cliente = ec.id_cliente
    LEFT   JOIN sede_cliente s ON s.id_sede = ec.id_sede
    LEFT   JOIN tabla_maestra tm_cl
             ON tm_cl.IdMaestro = 71 AND tm_cl.IdEmpresa = 1 AND tm_cl.String2 = ec.clasificacion
    WHERE  ec.SoftDelete = 0
      AND  (p_busqueda IS NULL OR p_busqueda = ''
            OR ec.num_serie      LIKE CONCAT('%', p_busqueda, '%')
            OR ec.codigo_tw      LIKE CONCAT('%', p_busqueda, '%')
            OR ec.codigo_cliente LIKE CONCAT('%', p_busqueda, '%')
            OR ec.marca          LIKE CONCAT('%', p_busqueda, '%')
            OR ec.modelo         LIKE CONCAT('%', p_busqueda, '%'))
      AND  (p_id_cliente     IS NULL OR p_id_cliente = 0     OR ec.id_cliente     = p_id_cliente)
      AND  (p_id_sede        IS NULL OR p_id_sede = 0        OR ec.id_sede        = p_id_sede)
      AND  (p_clasificacion  IS NULL OR p_clasificacion = '' OR ec.clasificacion  = p_clasificacion)
      AND  (p_estado         IS NULL OR p_estado = ''        OR ec.estado         = LOWER(p_estado))
      AND  (IFNULL(p_solo_vigentes_servicio, 0) = 0
            OR (ec.es_activo = 1 AND ec.bloqueado_para_servicios = 0))
    ORDER  BY ec.FchCre DESC, ec.id_equipo DESC
    LIMIT  v_por_pagina OFFSET v_offset;

    SELECT COUNT(*) AS total
    FROM   equipo_cliente ec
    WHERE  ec.SoftDelete = 0
      AND  (p_busqueda IS NULL OR p_busqueda = ''
            OR ec.num_serie      LIKE CONCAT('%', p_busqueda, '%')
            OR ec.codigo_tw      LIKE CONCAT('%', p_busqueda, '%')
            OR ec.codigo_cliente LIKE CONCAT('%', p_busqueda, '%')
            OR ec.marca          LIKE CONCAT('%', p_busqueda, '%')
            OR ec.modelo         LIKE CONCAT('%', p_busqueda, '%'))
      AND  (p_id_cliente     IS NULL OR p_id_cliente = 0     OR ec.id_cliente     = p_id_cliente)
      AND  (p_id_sede        IS NULL OR p_id_sede = 0        OR ec.id_sede        = p_id_sede)
      AND  (p_clasificacion  IS NULL OR p_clasificacion = '' OR ec.clasificacion  = p_clasificacion)
      AND  (p_estado         IS NULL OR p_estado = ''        OR ec.estado         = LOWER(p_estado))
      AND  (IFNULL(p_solo_vigentes_servicio, 0) = 0
            OR (ec.es_activo = 1 AND ec.bloqueado_para_servicios = 0));
END$$
DELIMITER ;
