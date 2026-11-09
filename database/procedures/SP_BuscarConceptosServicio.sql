-- HU-43 (Sprint 4) Modal "Agregar Concepto del Servicio": catálogo maestro de Suministros de clase Servicio (activos).
-- Sin precios: la OS/OM no maneja montos. Filtros: p_busqueda (descripción o código), p_tipo (tipo del suministro).
-- p_id_propuesta (opcional, #4435): devuelve SOLO los conceptos de esa propuesta, una fila por línea (propuesta_item) de
--   suministros de clase Servicio, con id_item, alcance, cantidad, frecuencia y precio unitario para precargar en la OS.
--   El mismo suministro con distinto alcance sale en filas separadas. Sin p_id_propuesta: catálogo maestro (como antes).
-- Resultados: 1 mensaje, 2 conceptos, 3 total, 4 tipos de servicio (filtro).
DROP PROCEDURE IF EXISTS SP_BuscarConceptosServicio;

DELIMITER $$

CREATE PROCEDURE SP_BuscarConceptosServicio(
    IN p_id_usuario BIGINT,
    IN p_busqueda   VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_tipo       VARCHAR(60)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_pagina     INT,
    IN p_por_pagina INT,
    IN p_id_propuesta BIGINT
)
proc: BEGIN
    DECLARE v_por_pagina INT;
    DECLARE v_offset     INT;
    DECLARE v_busqueda   VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    IF FN_PermisoAccion(p_id_usuario, 'os_guardar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para crear o editar órdenes de servicio.' AS Mensaje; LEAVE proc;
    END IF;

    SET v_por_pagina = IF(IFNULL(p_por_pagina, 0) < 1, 20, LEAST(p_por_pagina, 1000));
    SET v_offset     = (GREATEST(IFNULL(p_pagina, 1), 1) - 1) * v_por_pagina;
    SET v_busqueda   = TRIM(IFNULL(p_busqueda, ''));

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    IF IFNULL(p_id_propuesta, 0) > 0 THEN
        -- Conceptos de la propuesta de origen: una fila por línea
        SELECT i.id_item, s.id_suministro, s.codigo,
               COALESCE(NULLIF(TRIM(s.descripcion), ''), i.descripcion) AS descripcion,
               s.tipo, tt.String1 AS tipo_label, s.subtipo, ts.String1 AS subtipo_label,
               IFNULL(s.aplica_servicio, 0) AS aplica_servicio, IFNULL(s.aplica_metrologia, 0) AS aplica_metrologia,
               1 AS de_la_propuesta,
               i.alcance, i.cantidad, i.frecuencia, i.precio_unitario, i.seccion
        FROM propuesta_item i
        JOIN suministros s ON s.id_suministro = i.id_catalogo_item AND s.clase = 'servicio' AND s.eliminado_en IS NULL
        LEFT JOIN tabla_maestra tt ON tt.IdMaestro = 72 AND tt.IdEmpresa = 1 AND tt.String2 = s.tipo
        LEFT JOIN tabla_maestra ts ON ts.IdMaestro = 73 AND ts.IdEmpresa = 1 AND ts.String2 = s.subtipo
        WHERE i.id_propuesta = p_id_propuesta AND i.eliminado_en IS NULL AND IFNULL(i.es_espaciado, 0) = 0
          AND (IFNULL(p_tipo, '') = '' OR s.tipo = p_tipo)
          AND (v_busqueda = '' OR s.descripcion LIKE CONCAT('%', v_busqueda, '%') OR s.codigo LIKE CONCAT('%', v_busqueda, '%')
               OR i.alcance LIKE CONCAT('%', v_busqueda, '%'))
        ORDER BY (i.seccion = 'opcional'), i.orden, i.id_item
        LIMIT v_por_pagina OFFSET v_offset;

        SELECT COUNT(*) AS total
        FROM propuesta_item i
        JOIN suministros s ON s.id_suministro = i.id_catalogo_item AND s.clase = 'servicio' AND s.eliminado_en IS NULL
        WHERE i.id_propuesta = p_id_propuesta AND i.eliminado_en IS NULL AND IFNULL(i.es_espaciado, 0) = 0
          AND (IFNULL(p_tipo, '') = '' OR s.tipo = p_tipo)
          AND (v_busqueda = '' OR s.descripcion LIKE CONCAT('%', v_busqueda, '%') OR s.codigo LIKE CONCAT('%', v_busqueda, '%')
               OR i.alcance LIKE CONCAT('%', v_busqueda, '%'));

        SELECT tt.String2 AS codigo, tt.String1 AS nombre
        FROM tabla_maestra tt
        WHERE tt.IdMaestro = 72 AND tt.IdEmpresa = 1 AND tt.eliminado_en IS NULL AND tt.String3 = 'servicio'
        ORDER BY tt.Num1;
        LEAVE proc;
    END IF;

    SELECT s.id_suministro, s.codigo, s.descripcion, s.tipo, tt.String1 AS tipo_label, s.subtipo, ts.String1 AS subtipo_label,
           IFNULL(s.aplica_servicio, 0) AS aplica_servicio, IFNULL(s.aplica_metrologia, 0) AS aplica_metrologia,
           0 AS de_la_propuesta
    FROM suministros s
    LEFT JOIN tabla_maestra tt ON tt.IdMaestro = 72 AND tt.IdEmpresa = 1 AND tt.String2 = s.tipo
    LEFT JOIN tabla_maestra ts ON ts.IdMaestro = 73 AND ts.IdEmpresa = 1 AND ts.String2 = s.subtipo
    WHERE s.clase = 'servicio' AND s.estado = 'activo' AND s.eliminado_en IS NULL
      AND (IFNULL(p_tipo, '') = '' OR s.tipo = p_tipo)
      AND (v_busqueda = '' OR s.descripcion LIKE CONCAT('%', v_busqueda, '%') OR s.codigo LIKE CONCAT('%', v_busqueda, '%'))
    ORDER BY s.descripcion
    LIMIT v_por_pagina OFFSET v_offset;

    SELECT COUNT(*) AS total
    FROM suministros s
    WHERE s.clase = 'servicio' AND s.estado = 'activo' AND s.eliminado_en IS NULL
      AND (IFNULL(p_tipo, '') = '' OR s.tipo = p_tipo)
      AND (v_busqueda = '' OR s.descripcion LIKE CONCAT('%', v_busqueda, '%') OR s.codigo LIKE CONCAT('%', v_busqueda, '%'));

    SELECT tt.String2 AS codigo, tt.String1 AS nombre
    FROM tabla_maestra tt
    WHERE tt.IdMaestro = 72 AND tt.IdEmpresa = 1 AND tt.eliminado_en IS NULL AND tt.String3 = 'servicio'
    ORDER BY tt.Num1;
END$$

DELIMITER ;
