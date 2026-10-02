-- HU-85 — Listado maestro paginado de textos base
DROP PROCEDURE IF EXISTS SP_ObtenerTextosBase;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerTextosBase(
    IN p_busqueda             VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_tipo_categoria       VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_estado               VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_solo_predeterminados TINYINT,
    IN p_pagina               INT,
    IN p_por_pagina           INT
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
        tb.id_texto_base,
        tb.codigo_corto,
        tb.tipo_categoria,
        COALESCE(tm.String1, tb.tipo_categoria)        AS tipo_categoria_label,
        tb.nombre,
        tb.texto_clausula,
        CASE tb.estado
            WHEN 'activo'   THEN 'Activo'
            WHEN 'inactivo' THEN 'Inactivo'
            WHEN 'borrador' THEN 'Borrador'
            ELSE tb.estado
        END                                             AS estado,
        tb.es_predeterminado,
        tb.es_negrita_por_defecto,
        tb.FchCre                                       AS fecha_creacion,
        COALESCE(CONCAT(u.nombre, ' ', u.apellido), tb.UsuCre) AS usuario_creador
    FROM texto_base tb
    LEFT JOIN tabla_maestra tm
           ON tm.IdMaestro = 70 AND tm.IdEmpresa = 1 AND tm.String2 = tb.tipo_categoria
    LEFT JOIN usuario u ON u.id_usuario = tb.id_usuario_creador
    WHERE tb.SoftDelete = 0
      AND (p_tipo_categoria IS NULL OR p_tipo_categoria = '' OR tb.tipo_categoria = p_tipo_categoria)
      AND (p_estado         IS NULL OR p_estado         = '' OR tb.estado = LOWER(p_estado))
      AND (IFNULL(p_solo_predeterminados, 0) = 0 OR tb.es_predeterminado = 1)
      AND (
          p_busqueda IS NULL OR p_busqueda = ''
          OR tb.nombre         LIKE CONCAT('%', p_busqueda, '%')
          OR tb.codigo_corto   LIKE CONCAT('%', p_busqueda, '%')
          OR tb.texto_clausula LIKE CONCAT('%', p_busqueda, '%')
      )
    ORDER BY tb.tipo_categoria ASC, tb.orden_aparicion ASC, tb.nombre ASC
    LIMIT v_por_pagina OFFSET v_offset;

    -- 3. Total sin paginar
    SELECT COUNT(*) AS total
    FROM texto_base tb
    WHERE tb.SoftDelete = 0
      AND (p_tipo_categoria IS NULL OR p_tipo_categoria = '' OR tb.tipo_categoria = p_tipo_categoria)
      AND (p_estado         IS NULL OR p_estado         = '' OR tb.estado = LOWER(p_estado))
      AND (IFNULL(p_solo_predeterminados, 0) = 0 OR tb.es_predeterminado = 1)
      AND (
          p_busqueda IS NULL OR p_busqueda = ''
          OR tb.nombre         LIKE CONCAT('%', p_busqueda, '%')
          OR tb.codigo_corto   LIKE CONCAT('%', p_busqueda, '%')
          OR tb.texto_clausula LIKE CONCAT('%', p_busqueda, '%')
      );
END$$

DELIMITER ;
