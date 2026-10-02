-- HU-07 — Listado paginado de propuestas
DROP PROCEDURE IF EXISTS SP_ObtenerPropuestas;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerPropuestas(
    IN p_id_requerimiento BIGINT,
    IN p_estado           VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_busqueda         VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_pagina           INT,
    IN p_por_pagina       INT
)
BEGIN
    DECLARE v_por_pagina INT;
    DECLARE v_offset     INT;
    SET v_por_pagina = IF(p_por_pagina IS NULL OR p_por_pagina < 1, 10, p_por_pagina);
    SET v_offset     = (GREATEST(IFNULL(p_pagina, 1), 1) - 1) * v_por_pagina;

    -- 1. Header
    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Datos paginados
    SELECT
        p.id_propuesta,
        p.numero,
        p.version,
        p.id_requerimiento,
        r.numero                                AS numero_requerimiento,
        p.id_cliente,
        c.razon_social,
        p.referencia,
        tm_mon.String3                          AS moneda,
        p.total,
        p.total_opcionales,
        p.estado,
        p.fecha_creacion,
        CONCAT(u.nombre, ' ', u.apellido)       AS responsable
    FROM propuesta_comercial p
    JOIN requerimiento r ON r.id_requerimiento = p.id_requerimiento
    JOIN cliente c       ON c.id_cliente       = p.id_cliente
    LEFT JOIN usuario u  ON u.id_usuario       = COALESCE(p.id_responsable, p.id_creador)
    LEFT JOIN tabla_maestra tm_mon ON tm_mon.IdMaestro = 1 AND tm_mon.IdEmpresa = 1 AND tm_mon.Num1 = p.id_moneda
    WHERE p.eliminado_en IS NULL
      AND (p_id_requerimiento IS NULL OR p_id_requerimiento = 0 OR p.id_requerimiento = p_id_requerimiento)
      AND (p_estado IS NULL OR p_estado = '' OR p.estado = LOWER(p_estado))
      AND (
          p_busqueda IS NULL OR p_busqueda = ''
          OR p.numero       LIKE CONCAT('%', p_busqueda, '%')
          OR p.referencia   LIKE CONCAT('%', p_busqueda, '%')
          OR c.razon_social LIKE CONCAT('%', p_busqueda, '%')
          OR c.ruc          LIKE CONCAT('%', p_busqueda, '%')
          OR r.numero       LIKE CONCAT('%', p_busqueda, '%')
      )
    ORDER BY p.fecha_creacion DESC, p.id_propuesta DESC
    LIMIT v_por_pagina OFFSET v_offset;

    -- 3. Total sin paginar
    SELECT COUNT(*) AS total
    FROM propuesta_comercial p
    JOIN requerimiento r ON r.id_requerimiento = p.id_requerimiento
    JOIN cliente c       ON c.id_cliente       = p.id_cliente
    WHERE p.eliminado_en IS NULL
      AND (p_id_requerimiento IS NULL OR p_id_requerimiento = 0 OR p.id_requerimiento = p_id_requerimiento)
      AND (p_estado IS NULL OR p_estado = '' OR p.estado = LOWER(p_estado))
      AND (
          p_busqueda IS NULL OR p_busqueda = ''
          OR p.numero       LIKE CONCAT('%', p_busqueda, '%')
          OR p.referencia   LIKE CONCAT('%', p_busqueda, '%')
          OR c.razon_social LIKE CONCAT('%', p_busqueda, '%')
          OR c.ruc          LIKE CONCAT('%', p_busqueda, '%')
          OR r.numero       LIKE CONCAT('%', p_busqueda, '%')
      );
END$$

DELIMITER ;
