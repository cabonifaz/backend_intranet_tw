-- HU-82 — Pestaña "Usuarios": listado paginado con filtros
DROP PROCEDURE IF EXISTS SP_ObtenerUsuarios;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerUsuarios(
    IN p_busqueda   VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_rol        VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
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
        u.id_usuario,
        u.nombre,
        u.apellido,
        u.correo,
        u.rol_sistema,
        COALESCE(tm_rol.String1, u.rol_sistema) AS rol_sistema_label,
        u.area,
        u.telefono,
        CASE u.estado
            WHEN 'activo'     THEN 'Activo'
            WHEN 'inactivo'   THEN 'Inactivo'
            WHEN 'suspendido' THEN 'Suspendido'
            WHEN 'borrador'   THEN 'Borrador'
            ELSE u.estado
        END                                     AS estado,
        u.ultimo_login                          AS ultimo_acceso,
        u.creado_en                             AS fecha_creacion
    FROM usuario u
    LEFT JOIN tabla_maestra tm_rol
           ON tm_rol.IdMaestro = 68
          AND tm_rol.IdEmpresa = 1
          AND tm_rol.String2   = u.rol_sistema
    WHERE u.eliminado_en IS NULL
      AND (p_rol    IS NULL OR p_rol    = '' OR u.rol_sistema = p_rol)
      AND (p_estado IS NULL OR p_estado = '' OR u.estado = LOWER(p_estado))
      AND (
          p_busqueda IS NULL OR p_busqueda = ''
          OR CONCAT(u.nombre, ' ', u.apellido) LIKE CONCAT('%', p_busqueda, '%')
          OR u.correo                          LIKE CONCAT('%', p_busqueda, '%')
          OR u.numero_documento                LIKE CONCAT('%', p_busqueda, '%')
      )
    ORDER BY u.nombre ASC, u.apellido ASC
    LIMIT v_por_pagina OFFSET v_offset;

    -- 3. Total sin paginar
    SELECT COUNT(*) AS total
    FROM usuario u
    WHERE u.eliminado_en IS NULL
      AND (p_rol    IS NULL OR p_rol    = '' OR u.rol_sistema = p_rol)
      AND (p_estado IS NULL OR p_estado = '' OR u.estado = LOWER(p_estado))
      AND (
          p_busqueda IS NULL OR p_busqueda = ''
          OR CONCAT(u.nombre, ' ', u.apellido) LIKE CONCAT('%', p_busqueda, '%')
          OR u.correo                          LIKE CONCAT('%', p_busqueda, '%')
          OR u.numero_documento                LIKE CONCAT('%', p_busqueda, '%')
      );
END$$

DELIMITER ;
