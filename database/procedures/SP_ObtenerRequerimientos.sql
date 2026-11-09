-- ============================================================
-- SP_ObtenerRequerimientos
-- Lista paginada de requerimientos con KPIs.
-- Alcance (pedido 14, SP_ObtenerAlcanceCrm): usuario → sus RQs + suplencias vigentes;
--       supervisor / administrador / visor → su área; gerencia / TI → todo. KPIs sobre el mismo subconjunto.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerRequerimientos;

DELIMITER //

CREATE PROCEDURE SP_ObtenerRequerimientos(
    IN p_estado      VARCHAR(50)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_busqueda    VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_pagina      INT,
    IN p_por_pagina  INT,
    IN p_id_usuario  BIGINT,
    IN p_rol         VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
BEGIN
    DECLARE v_offset INT;
    DECLARE v_limit  INT;
    DECLARE v_ver_todo    TINYINT DEFAULT 0;
    DECLARE v_solo_propio TINYINT DEFAULT 1;
    DECLARE v_ids         TEXT;
    DECLARE v_area        VARCHAR(40);
    SET v_offset = (p_pagina - 1) * p_por_pagina;
    SET v_limit  = p_por_pagina;

    -- Pedido 14: alcance por usuario autenticado (p_rol queda solo por compatibilidad)
    CALL SP_ObtenerAlcanceCrm(p_id_usuario, v_ver_todo, v_solo_propio, v_ids, v_area);

    -- 1. Header
    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. KPIs (globales para jefe/admin, filtrados por usuario para comercial)
    SELECT
        (SELECT COUNT(*) FROM requerimiento
         WHERE estado NOT IN ('cerrado','anulado') AND SoftDelete = 0
           AND (v_ver_todo = 1 OR FIND_IN_SET(id_responsable, v_ids) > 0
                OR (id_responsable IS NULL AND v_solo_propio = 0))) AS rq_activos,
        (SELECT COUNT(*) FROM requerimiento
         WHERE estado = 'nuevo' AND SoftDelete = 0
           AND (v_ver_todo = 1 OR FIND_IN_SET(id_responsable, v_ids) > 0
                OR (id_responsable IS NULL AND v_solo_propio = 0))) AS sin_propuesta,
        (SELECT COUNT(*) FROM requerimiento
         WHERE estado NOT IN ('cerrado','anulado') AND SoftDelete = 0
           AND id_prioridad = 1 AND DATEDIFF(NOW(), fecha_creacion) >= 7
           AND (v_ver_todo = 1 OR FIND_IN_SET(id_responsable, v_ids) > 0
                OR (id_responsable IS NULL AND v_solo_propio = 0))) AS sla_urgentes,
        (SELECT COUNT(*) FROM requerimiento
         WHERE estado IN ('nuevo','en_proceso','con_propuesta') AND SoftDelete = 0
           AND DATEDIFF(NOW(), fecha_creacion) > 15
           AND (v_ver_todo = 1 OR FIND_IN_SET(id_responsable, v_ids) > 0
                OR (id_responsable IS NULL AND v_solo_propio = 0))) AS bloqueados;

    -- 3. Lista paginada
    SELECT
        r.id_requerimiento,
        r.numero,
        c.razon_social,
        c.ruc,
        sc.nombre                         AS nombre_sede,
        co.nombres                        AS nombre_contacto,
        tm_area.String1                   AS tipo_label,
        tm_orig.String1                   AS origen_label,
        tm_prio.String1                   AS prioridad_label,
        r.id_prioridad,
        CONCAT(u.nombre, ' ', u.apellido) AS responsable,
        r.fecha_creacion,
        r.fecha_necesidad,
        r.estado,
        CASE r.estado
            WHEN 'nuevo'         THEN 'Nueva'
            WHEN 'en_proceso'    THEN 'En proceso'
            WHEN 'con_propuesta' THEN 'Con propuesta'
            WHEN 'cerrado'       THEN 'Cerrado'
            WHEN 'anulado'       THEN 'Anulado'
            ELSE r.estado
        END AS estado_label
    FROM requerimiento r
    JOIN cliente c ON c.id_cliente = r.id_cliente
    LEFT JOIN contacto_cliente co ON co.id_contacto = r.id_contacto
    LEFT JOIN sede_cliente sc ON sc.id_sede = r.id_sede AND sc.SoftDelete = 0
    LEFT JOIN usuario u ON u.id_usuario = r.id_responsable
    LEFT JOIN tabla_maestra tm_orig ON tm_orig.IdMaestro = 63 AND tm_orig.Num1 = r.id_origen     AND tm_orig.IdEmpresa = 1
    LEFT JOIN tabla_maestra tm_area ON tm_area.IdMaestro = 64 AND tm_area.Num1 = r.id_area       AND tm_area.IdEmpresa = 1
    LEFT JOIN tabla_maestra tm_prio ON tm_prio.IdMaestro = 65 AND tm_prio.Num1 = r.id_prioridad  AND tm_prio.IdEmpresa = 1
    WHERE r.SoftDelete = 0
      AND (p_estado   IS NULL OR p_estado   = '' OR r.estado      = p_estado)
      AND (p_busqueda IS NULL OR p_busqueda = ''
           OR r.numero        LIKE CONCAT('%', p_busqueda, '%')
           OR c.razon_social  LIKE CONCAT('%', p_busqueda, '%')
           OR c.ruc           LIKE CONCAT('%', p_busqueda, '%'))
      AND (v_ver_todo = 1 OR FIND_IN_SET(r.id_responsable, v_ids) > 0
           OR (r.id_responsable IS NULL AND v_solo_propio = 0))
    ORDER BY r.fecha_creacion DESC
    LIMIT v_limit OFFSET v_offset;

    -- 4. Total filtrado
    SELECT COUNT(*) AS total
    FROM requerimiento r
    JOIN cliente c ON c.id_cliente = r.id_cliente
    WHERE r.SoftDelete = 0
      AND (p_estado   IS NULL OR p_estado   = '' OR r.estado      = p_estado)
      AND (p_busqueda IS NULL OR p_busqueda = ''
           OR r.numero        LIKE CONCAT('%', p_busqueda, '%')
           OR c.razon_social  LIKE CONCAT('%', p_busqueda, '%')
           OR c.ruc           LIKE CONCAT('%', p_busqueda, '%'))
      AND (v_ver_todo = 1 OR FIND_IN_SET(r.id_responsable, v_ids) > 0
           OR (r.id_responsable IS NULL AND v_solo_propio = 0));

END //

DELIMITER ;
