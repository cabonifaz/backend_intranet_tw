-- HU-82 / HU-84 — Pestaña "Suplentes": maestro global paginado
DROP PROCEDURE IF EXISTS SP_ObtenerSuplentes;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerSuplentes(
    IN p_busqueda   VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_estado     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_pagina     INT,
    IN p_por_pagina INT
)
BEGIN
    DECLARE v_por_pagina INT;
    DECLARE v_offset     INT;
    SET v_por_pagina = IF(p_por_pagina IS NULL OR p_por_pagina < 1, 20, p_por_pagina);
    SET v_offset     = (GREATEST(IFNULL(p_pagina, 1), 1) - 1) * v_por_pagina;

    -- 1. Header
    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Datos paginados
    SELECT
        us.id                                            AS id_asignacion,
        us.id_titular,
        t.nombre                                         AS titular_nombre,
        t.apellido                                       AS titular_apellido,
        t.cargo                                          AS titular_cargo,
        us.id_suplente,
        s.nombre                                         AS suplente_nombre,
        s.apellido                                       AS suplente_apellido,
        s.cargo                                          AS suplente_cargo,
        us.fecha_inicio,
        us.fecha_fin,
        IF(us.activo = 1, 'Activo', 'Inactivo')          AS estado,
        us.FchCre                                        AS fecha_creacion
    FROM usuario_suplente us
    LEFT JOIN usuario t ON t.id_usuario = us.id_titular
    LEFT JOIN usuario s ON s.id_usuario = us.id_suplente
    WHERE us.SoftDelete = 0
      AND (p_estado IS NULL OR p_estado = ''
           OR us.activo = IF(LOWER(p_estado) = 'activo', 1, 0))
      AND (
          p_busqueda IS NULL OR p_busqueda = ''
          OR CONCAT(t.nombre, ' ', t.apellido) LIKE CONCAT('%', p_busqueda, '%')
          OR CONCAT(s.nombre, ' ', s.apellido) LIKE CONCAT('%', p_busqueda, '%')
      )
    ORDER BY us.activo DESC, us.fecha_inicio DESC
    LIMIT v_por_pagina OFFSET v_offset;

    -- 3. Total sin paginar
    SELECT COUNT(*) AS total
    FROM usuario_suplente us
    LEFT JOIN usuario t ON t.id_usuario = us.id_titular
    LEFT JOIN usuario s ON s.id_usuario = us.id_suplente
    WHERE us.SoftDelete = 0
      AND (p_estado IS NULL OR p_estado = ''
           OR us.activo = IF(LOWER(p_estado) = 'activo', 1, 0))
      AND (
          p_busqueda IS NULL OR p_busqueda = ''
          OR CONCAT(t.nombre, ' ', t.apellido) LIKE CONCAT('%', p_busqueda, '%')
          OR CONCAT(s.nombre, ' ', s.apellido) LIKE CONCAT('%', p_busqueda, '%')
      );
END$$

DELIMITER ;
