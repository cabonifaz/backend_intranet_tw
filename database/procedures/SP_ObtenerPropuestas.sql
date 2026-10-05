-- HU-07 / HU-08 — Bandeja de propuestas (listado paginado)
--   Filtros: requerimiento, estado (BD), grupo de estado (pestañas del front),
--   año, comercial, búsqueda y "solo versión actual" (por defecto sí).
--   Grupos: borrador | por_vb | en_seguimiento | aceptada | rechazada | cerrada | todas
--   ("por_enviar" y "por_consolidar" dependen del flujo de VB — HU-12, pendiente).
DROP PROCEDURE IF EXISTS SP_ObtenerPropuestas;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerPropuestas(
    IN p_id_requerimiento    BIGINT,
    IN p_estado              VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_busqueda            VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_pagina              INT,
    IN p_por_pagina          INT,
    IN p_grupo_estado        VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_anio                INT,
    IN p_id_comercial        BIGINT,
    IN p_solo_ultima_version TINYINT
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
        c.ruc,
        p.referencia,
        tm_mon.String3                          AS moneda,
        p.total,
        p.total_opcionales,
        p.estado,
        CASE p.estado
            WHEN 'borrador'     THEN 'borrador'
            WHEN 'pendiente_vb' THEN 'por_vb'
            WHEN 'enviado'      THEN 'en_seguimiento'
            WHEN 'aprobado'     THEN 'aceptada'
            WHEN 'rechazado'    THEN 'rechazada'
            ELSE 'cerrada'
        END                                     AS estado_grupo,
        CASE p.estado
            WHEN 'borrador'  THEN 'editar'
            WHEN 'enviado'   THEN 'nueva_version'
            WHEN 'aprobado'  THEN 'nueva_version'
            WHEN 'rechazado' THEN 'nueva_version'
            ELSE 'ver_detalle'
        END                                     AS accion,
        IF(p.fecha_expiracion IS NULL, NULL, DATEDIFF(p.fecha_expiracion, CURDATE())) AS sla_dias_restantes,
        p.fecha_creacion,
        COALESCE(p.modificado_en, p.fecha_creacion) AS fecha_modificacion,
        COALESCE(p.id_responsable, p.id_creador)    AS id_responsable,
        CONCAT(u.nombre, ' ', u.apellido)       AS responsable
    FROM propuesta_comercial p
    JOIN requerimiento r ON r.id_requerimiento = p.id_requerimiento
    JOIN cliente c       ON c.id_cliente       = p.id_cliente
    LEFT JOIN usuario u  ON u.id_usuario       = COALESCE(p.id_responsable, p.id_creador)
    LEFT JOIN tabla_maestra tm_mon ON tm_mon.IdMaestro = 1 AND tm_mon.IdEmpresa = 1 AND tm_mon.Num1 = p.id_moneda
    WHERE p.eliminado_en IS NULL
      AND (p_id_requerimiento IS NULL OR p_id_requerimiento = 0 OR p.id_requerimiento = p_id_requerimiento)
      AND (p_estado IS NULL OR p_estado = '' OR p.estado = LOWER(p_estado))
      AND (p_grupo_estado IS NULL OR p_grupo_estado = '' OR p_grupo_estado = 'todas'
           OR (p_grupo_estado = 'borrador'       AND p.estado = 'borrador')
           OR (p_grupo_estado = 'por_vb'         AND p.estado = 'pendiente_vb')
           OR (p_grupo_estado = 'en_seguimiento' AND p.estado = 'enviado')
           OR (p_grupo_estado = 'aceptada'       AND p.estado = 'aprobado')
           OR (p_grupo_estado = 'rechazada'      AND p.estado = 'rechazado')
           OR (p_grupo_estado = 'cerrada'        AND p.estado IN ('anulado', 'vencido')))
      AND (p_anio IS NULL OR p_anio = 0 OR YEAR(p.fecha_creacion) = p_anio)
      AND (p_id_comercial IS NULL OR p_id_comercial = 0 OR COALESCE(p.id_responsable, p.id_creador) = p_id_comercial)
      AND (IFNULL(p_solo_ultima_version, 1) = 0
           OR p.version = (SELECT MAX(p2.version) FROM propuesta_comercial p2
                           WHERE p2.numero = p.numero AND p2.eliminado_en IS NULL))
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
      AND (p_grupo_estado IS NULL OR p_grupo_estado = '' OR p_grupo_estado = 'todas'
           OR (p_grupo_estado = 'borrador'       AND p.estado = 'borrador')
           OR (p_grupo_estado = 'por_vb'         AND p.estado = 'pendiente_vb')
           OR (p_grupo_estado = 'en_seguimiento' AND p.estado = 'enviado')
           OR (p_grupo_estado = 'aceptada'       AND p.estado = 'aprobado')
           OR (p_grupo_estado = 'rechazada'      AND p.estado = 'rechazado')
           OR (p_grupo_estado = 'cerrada'        AND p.estado IN ('anulado', 'vencido')))
      AND (p_anio IS NULL OR p_anio = 0 OR YEAR(p.fecha_creacion) = p_anio)
      AND (p_id_comercial IS NULL OR p_id_comercial = 0 OR COALESCE(p.id_responsable, p.id_creador) = p_id_comercial)
      AND (IFNULL(p_solo_ultima_version, 1) = 0
           OR p.version = (SELECT MAX(p2.version) FROM propuesta_comercial p2
                           WHERE p2.numero = p.numero AND p2.eliminado_en IS NULL))
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
