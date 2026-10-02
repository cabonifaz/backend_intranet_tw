-- HU-86 — Listado maestro paginado de suministros
DROP PROCEDURE IF EXISTS SP_ObtenerSuministros;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerSuministros(
    IN p_busqueda           VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_clase              VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_tipo               VARCHAR(60)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_estado             VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_solo_en_propuestas TINYINT,
    IN p_pagina             INT,
    IN p_por_pagina         INT
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
        ci.id_suministro                               AS id_suministro,
        ci.codigo,
        ci.clase,
        COALESCE(t_cla.String1, ci.clase)                 AS clase_label,
        ci.tipo,
        COALESCE(t_tip.String1, ci.tipo)                  AS tipo_label,
        ci.subtipo,
        COALESCE(t_sub.String1, ci.subtipo)               AS subtipo_label,
        ci.descripcion,
        ci.marca,
        ci.modelo,
        ci.cta_contable,
        ci.procedencia,
        COALESCE(t_pro.String1, ci.procedencia)           AS procedencia_label,
        CASE ci.estado
            WHEN 'activo'   THEN 'Activo'
            WHEN 'inactivo' THEN 'Inactivo'
            WHEN 'borrador' THEN 'Borrador'
            ELSE ci.estado
        END                                               AS estado,
        IF(ci.estado = 'activo', 1, 0)                    AS es_activo_en_catalogo,
        ci.usar_en_propuestas
    FROM suministros ci
    LEFT JOIN tabla_maestra t_cla ON t_cla.IdMaestro = 71 AND t_cla.IdEmpresa = 1 AND t_cla.String2 = ci.clase
    LEFT JOIN tabla_maestra t_tip ON t_tip.IdMaestro = 72 AND t_tip.IdEmpresa = 1 AND t_tip.String2 = ci.tipo
    LEFT JOIN tabla_maestra t_sub ON t_sub.IdMaestro = 73 AND t_sub.IdEmpresa = 1 AND t_sub.String2 = ci.subtipo
    LEFT JOIN tabla_maestra t_pro ON t_pro.IdMaestro = 74 AND t_pro.IdEmpresa = 1 AND t_pro.String2 = ci.procedencia
    WHERE ci.eliminado_en IS NULL
      AND (p_clase  IS NULL OR p_clase  = '' OR ci.clase = p_clase)
      AND (p_tipo   IS NULL OR p_tipo   = '' OR ci.tipo  = p_tipo)
      AND (p_estado IS NULL OR p_estado = '' OR ci.estado = LOWER(p_estado))
      AND (IFNULL(p_solo_en_propuestas, 0) = 0 OR ci.usar_en_propuestas = 1)
      AND (
          p_busqueda IS NULL OR p_busqueda = ''
          OR ci.descripcion        LIKE CONCAT('%', p_busqueda, '%')
          OR ci.descripcion_manual LIKE CONCAT('%', p_busqueda, '%')
          OR ci.marca              LIKE CONCAT('%', p_busqueda, '%')
          OR ci.modelo             LIKE CONCAT('%', p_busqueda, '%')
          OR ci.codigo             LIKE CONCAT('%', p_busqueda, '%')
          OR CAST(ci.id_suministro AS CHAR) = p_busqueda
      )
    ORDER BY ci.id_suministro DESC
    LIMIT v_por_pagina OFFSET v_offset;

    -- 3. Total sin paginar
    SELECT COUNT(*) AS total
    FROM suministros ci
    WHERE ci.eliminado_en IS NULL
      AND (p_clase  IS NULL OR p_clase  = '' OR ci.clase = p_clase)
      AND (p_tipo   IS NULL OR p_tipo   = '' OR ci.tipo  = p_tipo)
      AND (p_estado IS NULL OR p_estado = '' OR ci.estado = LOWER(p_estado))
      AND (IFNULL(p_solo_en_propuestas, 0) = 0 OR ci.usar_en_propuestas = 1)
      AND (
          p_busqueda IS NULL OR p_busqueda = ''
          OR ci.descripcion        LIKE CONCAT('%', p_busqueda, '%')
          OR ci.descripcion_manual LIKE CONCAT('%', p_busqueda, '%')
          OR ci.marca              LIKE CONCAT('%', p_busqueda, '%')
          OR ci.modelo             LIKE CONCAT('%', p_busqueda, '%')
          OR ci.codigo             LIKE CONCAT('%', p_busqueda, '%')
          OR CAST(ci.id_suministro AS CHAR) = p_busqueda
      );
END$$

DELIMITER ;
