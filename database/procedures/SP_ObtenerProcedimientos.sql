-- HU-87 — Listado maestro paginado de procedimientos
DROP PROCEDURE IF EXISTS SP_ObtenerProcedimientos;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerProcedimientos(
    IN p_busqueda   VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_anio       INT,
    IN p_estado     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_pagina     INT,
    IN p_por_pagina INT
)
BEGIN
    DECLARE v_por_pagina INT;
    DECLARE v_offset     INT;
    SET v_por_pagina = IF(p_por_pagina IS NULL OR p_por_pagina < 1, 15, p_por_pagina);
    SET v_offset     = (GREATEST(IFNULL(p_pagina, 1), 1) - 1) * v_por_pagina;

    -- 1. Header
    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Datos paginados
    SELECT
        p.id_procedimiento,
        p.codigo,
        p.anio,
        p.version,
        p.es_formato_digital_iso,
        p.norma_base,
        p.autor_norma,
        p.descripcion,
        CASE p.estado
            WHEN 'activo'   THEN 'Activo'
            WHEN 'inactivo' THEN 'Inactivo'
            WHEN 'borrador' THEN 'Borrador'
            ELSE p.estado
        END                    AS estado,
        p.FchCre               AS fecha_registro
    FROM procedimiento_metrologico p
    WHERE p.SoftDelete = 0
      AND (p_anio   IS NULL OR p_anio = 0    OR p.anio = p_anio)
      AND (p_estado IS NULL OR p_estado = '' OR p.estado = LOWER(p_estado))
      AND (
          p_busqueda IS NULL OR p_busqueda = ''
          OR p.codigo      LIKE CONCAT('%', p_busqueda, '%')
          OR p.descripcion LIKE CONCAT('%', p_busqueda, '%')
          OR p.autor_norma LIKE CONCAT('%', p_busqueda, '%')
          OR p.norma_base  LIKE CONCAT('%', p_busqueda, '%')
          OR CAST(p.id_procedimiento AS CHAR) = p_busqueda
      )
    ORDER BY p.codigo ASC, p.anio DESC
    LIMIT v_por_pagina OFFSET v_offset;

    -- 3. Total sin paginar
    SELECT COUNT(*) AS total
    FROM procedimiento_metrologico p
    WHERE p.SoftDelete = 0
      AND (p_anio   IS NULL OR p_anio = 0    OR p.anio = p_anio)
      AND (p_estado IS NULL OR p_estado = '' OR p.estado = LOWER(p_estado))
      AND (
          p_busqueda IS NULL OR p_busqueda = ''
          OR p.codigo      LIKE CONCAT('%', p_busqueda, '%')
          OR p.descripcion LIKE CONCAT('%', p_busqueda, '%')
          OR p.autor_norma LIKE CONCAT('%', p_busqueda, '%')
          OR p.norma_base  LIKE CONCAT('%', p_busqueda, '%')
          OR CAST(p.id_procedimiento AS CHAR) = p_busqueda
      );
END$$

DELIMITER ;
