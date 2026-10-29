-- HU-40 (Sprint 4) Modal "Elegir Propuesta Aceptada": la última versión aceptada de cada propuesta mientras le queden
-- equipos cotizados sin OS/OM activa. Una propuesta puede ejecutarse en varias OS/OM (los equipos se dividen en lotes):
--   equipos_pendientes = equipos cotizados que no están en una OS/OM no anulada de la propuesta (de cualquier versión).
--   Una propuesta sin equipos cotizados (solo servicios) aparece mientras no tenga ninguna OS/OM activa.
-- Visibilidad: el comercial ve las propuestas de las que es responsable; quien tiene os_aprobar_edicion (Jefe Comercial)
-- o propuesta_seguimiento_todas ve todas.
-- p_busqueda: N° de propuesta, N° de RQ, cliente o RUC. p_tipo: vacío, OS u OM (lo define el área del RQ).
-- Resultados: 1 mensaje, 2 filas, 3 total.
DROP PROCEDURE IF EXISTS SP_ObtenerPropuestasDisponiblesOrdenServicio;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerPropuestasDisponiblesOrdenServicio(
    IN p_id_usuario BIGINT,
    IN p_busqueda   VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_tipo       VARCHAR(5)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_pagina     INT,
    IN p_por_pagina INT
)
proc: BEGIN
    DECLARE v_todas      TINYINT DEFAULT 0;
    DECLARE v_busqueda   VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tipo       VARCHAR(5)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_por_pagina INT;
    DECLARE v_offset     INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @msg = MESSAGE_TEXT;
        SELECT 3 AS IdTipoMensaje, CONCAT('Error al obtener las propuestas aceptadas: ', @msg) AS Mensaje;
    END;

    IF FN_PermisoAccion(p_id_usuario, 'os_guardar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tiene permiso para crear órdenes de servicio.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_todas      = IF(FN_PermisoAccion(p_id_usuario, 'os_aprobar_edicion') = 1
                          OR FN_PermisoAccion(p_id_usuario, 'propuesta_seguimiento_todas') = 1, 1, 0);
    SET v_busqueda   = TRIM(IFNULL(p_busqueda, ''));
    SET v_tipo       = UPPER(TRIM(IFNULL(p_tipo, '')));
    SET v_por_pagina = IF(IFNULL(p_por_pagina, 0) BETWEEN 1 AND 100, p_por_pagina, 10);
    SET v_offset     = (GREATEST(IFNULL(p_pagina, 1), 1) - 1) * v_por_pagina;

    DROP TEMPORARY TABLE IF EXISTS tmp_os_prop_disp;
    CREATE TEMPORARY TABLE tmp_os_prop_disp AS
    SELECT p.id_propuesta,
           p.numero,
           p.version,
           COALESCE(NULLIF(TRIM(IF(p.tipo_servicio REGEXP '^[0-9]+$',
                                   (SELECT ts.String1 FROM tabla_maestra ts WHERE ts.IdMaestro = 3 AND ts.IdEmpresa = 1
                                      AND ts.Num1 = CAST(p.tipo_servicio AS UNSIGNED) LIMIT 1), p.tipo_servicio)), ''),
                    (SELECT GROUP_CONCAT(DISTINCT ts.String1 ORDER BY ts.String1 SEPARATOR ', ')
                     FROM propuesta_item i JOIN tabla_maestra ts ON ts.IdMaestro = 3 AND ts.IdEmpresa = 1 AND ts.Num1 = i.id_tipo_servicio
                     WHERE i.id_propuesta = p.id_propuesta AND i.eliminado_en IS NULL))         AS tipo_servicio,
           IF(IFNULL(a.String1, '') LIKE '%metrolog%', 'OM', 'OS')                    AS tipo,
           p.id_cliente,
           c.razon_social,
           c.ruc,
           sc.nombre                                                                  AS sede,
           p.id_requerimiento,
           r.numero                                                                   AS numero_rq,
           a.String1                                                                  AS area,
           COALESCE(p.id_responsable, p.id_creador)                                   AS id_responsable,
           NULLIF(TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))), '') AS responsable,
           COALESCE((SELECT MIN(IFNULL(s.fecha_interaccion, s.creado_en)) FROM seguimiento_comercial s
                     WHERE s.id_propuesta = p.id_propuesta AND s.eliminado_en IS NULL AND s.estado = 'cerrado_aceptacion'),
                    (SELECT MIN(ae.registrado_en) FROM auditoria_evento ae
                     WHERE ae.entidad_tipo = 'propuesta' AND ae.id_entidad = p.id_propuesta AND ae.estado_nuevo = 'aceptado'),
                    p.modificado_en)                                                  AS fecha_aceptacion,
           p.total                                                                    AS monto_total,
           m.String2                                                                  AS simbolo_moneda,
           (SELECT COUNT(DISTINCT pe.id_equipo) FROM propuesta_equipo pe
            WHERE pe.id_propuesta = p.id_propuesta AND pe.id_equipo IS NOT NULL)      AS equipos_cotizados,
           (SELECT COUNT(DISTINCT pe.id_equipo) FROM propuesta_equipo pe
            WHERE pe.id_propuesta = p.id_propuesta AND pe.id_equipo IS NOT NULL
              AND NOT EXISTS (SELECT 1 FROM os_equipo oe
                              JOIN orden_servicio os ON os.id_os = oe.id_os AND os.eliminado_en IS NULL AND os.estado <> 'anulada'
                              JOIN propuesta_comercial po ON po.id_propuesta = os.id_propuesta AND po.numero = p.numero
                              WHERE oe.id_equipo = pe.id_equipo AND oe.eliminado_en IS NULL)) AS equipos_pendientes,
           (SELECT COUNT(*) FROM orden_servicio os
            JOIN propuesta_comercial po ON po.id_propuesta = os.id_propuesta AND po.numero = p.numero
            WHERE os.eliminado_en IS NULL AND os.estado <> 'anulada')                 AS os_activas,
           (SELECT COUNT(*) FROM propuesta_item i WHERE i.id_propuesta = p.id_propuesta AND i.seccion = 'principal'
              AND IFNULL(i.es_espaciado, 0) = 0 AND i.eliminado_en IS NULL)          AS conceptos_cotizados,
           p.fecha_creacion
    FROM propuesta_comercial p
    JOIN cliente c               ON c.id_cliente = p.id_cliente
    LEFT JOIN sede_cliente sc    ON sc.id_sede = p.id_sede
    LEFT JOIN requerimiento r    ON r.id_requerimiento = p.id_requerimiento
    LEFT JOIN tabla_maestra a    ON a.IdMaestro = 64 AND a.IdEmpresa = 1 AND a.Num1 = r.id_area
    LEFT JOIN tabla_maestra m    ON m.IdMaestro = 1 AND m.IdEmpresa = 1 AND m.Num1 = p.id_moneda
    LEFT JOIN usuario u          ON u.id_usuario = COALESCE(p.id_responsable, p.id_creador)
    WHERE p.eliminado_en IS NULL
      AND p.estado = 'aceptado'
      -- solo la última versión aceptada de cada número
      AND NOT EXISTS (SELECT 1 FROM propuesta_comercial p2
                      WHERE p2.numero = p.numero AND p2.estado = 'aceptado' AND p2.eliminado_en IS NULL AND p2.version > p.version)
      AND (v_todas = 1 OR COALESCE(p.id_responsable, p.id_creador) = p_id_usuario)
      AND (v_busqueda = ''
           OR p.numero       LIKE CONCAT('%', v_busqueda, '%')
           OR r.numero       LIKE CONCAT('%', v_busqueda, '%')
           OR c.razon_social LIKE CONCAT('%', v_busqueda, '%')
           OR c.ruc          LIKE CONCAT('%', v_busqueda, '%'));

    DELETE FROM tmp_os_prop_disp
    WHERE NOT (equipos_pendientes > 0 OR (equipos_cotizados = 0 AND os_activas = 0));

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT t.*
    FROM tmp_os_prop_disp t
    WHERE v_tipo IN ('', 'TODOS') OR t.tipo = v_tipo
    ORDER BY t.fecha_aceptacion DESC, t.id_propuesta DESC
    LIMIT v_por_pagina OFFSET v_offset;

    SELECT COUNT(*) AS total FROM tmp_os_prop_disp t WHERE v_tipo IN ('', 'TODOS') OR t.tipo = v_tipo;

    DROP TEMPORARY TABLE IF EXISTS tmp_os_prop_disp;
END$$

DELIMITER ;
