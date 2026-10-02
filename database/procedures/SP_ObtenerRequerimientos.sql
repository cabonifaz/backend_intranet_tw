-- ============================================================
-- SP_ObtenerRequerimientos
-- Lista paginada de requerimientos con KPIs.
-- RBAC: comercial ve solo sus RQs (y los de quien es suplente).
--       jefe_comercial y admin ven todos.
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
    SET v_offset = (p_pagina - 1) * p_por_pagina;
    SET v_limit  = p_por_pagina;

    -- 1. Header
    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. KPIs (globales para jefe/admin, filtrados por usuario para comercial)
    SELECT
        (SELECT COUNT(*) FROM requerimiento
         WHERE estado NOT IN ('cerrado','anulado') AND SoftDelete = 0
           AND (p_rol IN ('jefe_comercial','admin')
                OR id_responsable = p_id_usuario
                OR EXISTS (
                    SELECT 1 FROM usuario_suplente us
                    WHERE us.id_titular  = id_responsable
                      AND us.id_suplente = p_id_usuario
                      AND us.activo = 1 AND us.SoftDelete = 0
                      AND us.fecha_inicio <= CURDATE()
                      AND (us.fecha_fin IS NULL OR us.fecha_fin >= CURDATE())
                ))) AS rq_activos,
        (SELECT COUNT(*) FROM requerimiento
         WHERE estado = 'nuevo' AND SoftDelete = 0
           AND (p_rol IN ('jefe_comercial','admin')
                OR id_responsable = p_id_usuario
                OR EXISTS (
                    SELECT 1 FROM usuario_suplente us
                    WHERE us.id_titular  = id_responsable
                      AND us.id_suplente = p_id_usuario
                      AND us.activo = 1 AND us.SoftDelete = 0
                      AND us.fecha_inicio <= CURDATE()
                      AND (us.fecha_fin IS NULL OR us.fecha_fin >= CURDATE())
                ))) AS sin_propuesta,
        (SELECT COUNT(*) FROM requerimiento
         WHERE estado NOT IN ('cerrado','anulado') AND SoftDelete = 0
           AND id_prioridad = 1 AND DATEDIFF(NOW(), fecha_creacion) >= 7
           AND (p_rol IN ('jefe_comercial','admin')
                OR id_responsable = p_id_usuario
                OR EXISTS (
                    SELECT 1 FROM usuario_suplente us
                    WHERE us.id_titular  = id_responsable
                      AND us.id_suplente = p_id_usuario
                      AND us.activo = 1 AND us.SoftDelete = 0
                      AND us.fecha_inicio <= CURDATE()
                      AND (us.fecha_fin IS NULL OR us.fecha_fin >= CURDATE())
                ))) AS sla_urgentes,
        (SELECT COUNT(*) FROM requerimiento
         WHERE estado IN ('nuevo','en_proceso','con_propuesta') AND SoftDelete = 0
           AND DATEDIFF(NOW(), fecha_creacion) > 15
           AND (p_rol IN ('jefe_comercial','admin')
                OR id_responsable = p_id_usuario
                OR EXISTS (
                    SELECT 1 FROM usuario_suplente us
                    WHERE us.id_titular  = id_responsable
                      AND us.id_suplente = p_id_usuario
                      AND us.activo = 1 AND us.SoftDelete = 0
                      AND us.fecha_inicio <= CURDATE()
                      AND (us.fecha_fin IS NULL OR us.fecha_fin >= CURDATE())
                ))) AS bloqueados;

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
      AND (
          p_rol IN ('jefe_comercial', 'admin')
          OR r.id_responsable = p_id_usuario
          OR EXISTS (
              SELECT 1 FROM usuario_suplente us
              WHERE us.id_titular  = r.id_responsable
                AND us.id_suplente = p_id_usuario
                AND us.activo      = 1
                AND us.SoftDelete  = 0
                AND us.fecha_inicio <= CURDATE()
                AND (us.fecha_fin IS NULL OR us.fecha_fin >= CURDATE())
          )
      )
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
      AND (
          p_rol IN ('jefe_comercial', 'admin')
          OR r.id_responsable = p_id_usuario
          OR EXISTS (
              SELECT 1 FROM usuario_suplente us
              WHERE us.id_titular  = r.id_responsable
                AND us.id_suplente = p_id_usuario
                AND us.activo      = 1
                AND us.SoftDelete  = 0
                AND us.fecha_inicio <= CURDATE()
                AND (us.fecha_fin IS NULL OR us.fecha_fin >= CURDATE())
          )
      );

END //

DELIMITER ;
