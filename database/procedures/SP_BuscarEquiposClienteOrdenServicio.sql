-- HU-43 (Sprint 4) Modal "Agregar Equipo / Instrumento": catálogo de equipos registrados del cliente (activos), con
-- la advertencia de doble registro si el equipo ya está en otra OS/OM activa (emitida, programada o en ejecución).
-- Filtros: p_busqueda (código TW, marca, modelo, N° serie, código del cliente o ubicación), p_clasificacion
-- (equipo | instrumento | pesa), p_ubicacion (ubicación exacta, de la lista que devuelve el mismo SP).
-- Resultados: 1 mensaje, 2 equipos, 3 total, 4 ubicaciones (filtro), 5 clasificaciones (filtro).
DROP PROCEDURE IF EXISTS SP_BuscarEquiposClienteOrdenServicio;

DELIMITER $$

CREATE PROCEDURE SP_BuscarEquiposClienteOrdenServicio(
    IN p_id_usuario    BIGINT,
    IN p_id_cliente    BIGINT,
    IN p_id_os         BIGINT,
    IN p_busqueda      VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_clasificacion VARCHAR(60)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_ubicacion     VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_pagina        INT,
    IN p_por_pagina    INT
)
proc: BEGIN
    DECLARE v_por_pagina INT;
    DECLARE v_offset     INT;
    DECLARE v_busqueda   VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    IF FN_PermisoAccion(p_id_usuario, 'os_guardar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para crear o editar órdenes de servicio.' AS Mensaje; LEAVE proc;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM cliente WHERE id_cliente = p_id_cliente AND SoftDelete = 0) THEN
        SELECT 1 AS IdTipoMensaje, 'Cliente no encontrado.' AS Mensaje; LEAVE proc;
    END IF;

    SET v_por_pagina = IF(IFNULL(p_por_pagina, 0) < 1, 20, LEAST(p_por_pagina, 200));
    SET v_offset     = (GREATEST(IFNULL(p_pagina, 1), 1) - 1) * v_por_pagina;
    SET v_busqueda   = TRIM(IFNULL(p_busqueda, ''));

    DROP TEMPORARY TABLE IF EXISTS tmp_os_buscar_eq;
    CREATE TEMPORARY TABLE tmp_os_buscar_eq AS
    SELECT ec.id_equipo, ec.codigo_tw, ec.num_serie, ec.codigo_cliente, ec.clasificacion,
           COALESCE(tc.String1, ec.clasificacion) AS clasificacion_label,
           ec.marca, ec.modelo, ec.alcance_maximo, ec.ubicacion_especifica, sc.nombre AS sede,
           ec.division_minima, ec.division_verif, ec.clase_exactitud, ec.escala_graduacion, ec.puntos_calibracion, ec.valor_nominal,
           (SELECT CONCAT(o2.numero, '|', o2.estado) FROM os_equipo e2
            JOIN orden_servicio o2 ON o2.id_os = e2.id_os AND o2.eliminado_en IS NULL
            WHERE e2.id_equipo = ec.id_equipo AND e2.eliminado_en IS NULL AND o2.id_os <> IFNULL(p_id_os, 0)
              AND o2.estado NOT IN ('borrador', 'finalizada', 'anulada')
            ORDER BY o2.id_os DESC LIMIT 1) AS otra_os
    FROM equipo_cliente ec
    LEFT JOIN sede_cliente sc  ON sc.id_sede = ec.id_sede
    LEFT JOIN tabla_maestra tc ON tc.IdMaestro = 71 AND tc.IdEmpresa = 1 AND tc.String2 = ec.clasificacion
    WHERE ec.id_cliente = p_id_cliente AND ec.SoftDelete = 0 AND ec.estado = 'activo'
      AND (IFNULL(p_clasificacion, '') = '' OR ec.clasificacion = p_clasificacion)
      AND (IFNULL(p_ubicacion, '') = '' OR ec.ubicacion_especifica = p_ubicacion)
      AND (v_busqueda = ''
           OR ec.codigo_tw            LIKE CONCAT('%', v_busqueda, '%')
           OR ec.num_serie            LIKE CONCAT('%', v_busqueda, '%')
           OR ec.codigo_cliente       LIKE CONCAT('%', v_busqueda, '%')
           OR ec.marca                LIKE CONCAT('%', v_busqueda, '%')
           OR ec.modelo               LIKE CONCAT('%', v_busqueda, '%')
           OR ec.ubicacion_especifica LIKE CONCAT('%', v_busqueda, '%'));

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT * FROM tmp_os_buscar_eq ORDER BY codigo_tw LIMIT v_por_pagina OFFSET v_offset;
    SELECT COUNT(*) AS total FROM tmp_os_buscar_eq;
    DROP TEMPORARY TABLE IF EXISTS tmp_os_buscar_eq;

    SELECT DISTINCT ec.ubicacion_especifica AS nombre
    FROM equipo_cliente ec
    WHERE ec.id_cliente = p_id_cliente AND ec.SoftDelete = 0 AND ec.estado = 'activo' AND IFNULL(ec.ubicacion_especifica, '') <> ''
    ORDER BY nombre;

    SELECT tm.String2 AS codigo, tm.String1 AS nombre
    FROM tabla_maestra tm WHERE tm.IdMaestro = 71 AND tm.IdEmpresa = 1 AND tm.String2 <> 'servicio' AND tm.eliminado_en IS NULL
    ORDER BY tm.Num1;
END$$

DELIMITER ;
