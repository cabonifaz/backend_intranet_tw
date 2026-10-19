-- Directorio interno (ticket #4303): datos de CONTACTO de los usuarios activos.
-- Lo puede consultar todo el personal. No expone documento, rol, estado ni contraseñas.
-- Búsqueda por nombre, apellido, correo, cargo, anexo o nombre del área. Filtro opcional por área.
DROP PROCEDURE IF EXISTS SP_ObtenerDirectorio;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerDirectorio(
    IN p_busqueda   VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_area       VARCHAR(60)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_pagina     INT,
    IN p_por_pagina INT
)
BEGIN
    DECLARE v_por_pagina INT;
    DECLARE v_offset     INT;
    SET v_por_pagina = IF(IFNULL(p_por_pagina, 0) < 1, 50, LEAST(p_por_pagina, 200));
    SET v_offset     = (GREATEST(IFNULL(p_pagina, 1), 1) - 1) * v_por_pagina;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT
        u.id_usuario,
        CONCAT(u.nombre, ' ', u.apellido)                 AS nombre_completo,
        IFNULL(u.area, '')                                AS area,
        IFNULL(ta.String1, '')                            AS area_label,
        IFNULL(u.cargo, '')                               AS cargo,
        u.correo,
        IFNULL(u.telefono, '')                            AS telefono,
        IFNULL(u.anexo, '')                               AS anexo,
        IFNULL(u.troncal, '')                             AS troncal,
        IF(u.fecha_nacimiento IS NULL, '', DATE_FORMAT(u.fecha_nacimiento, '%d/%m')) AS cumpleanos
    FROM usuario u
    LEFT JOIN tabla_maestra ta ON ta.IdMaestro = 79 AND ta.IdEmpresa = 1 AND ta.String2 = u.area
    WHERE u.eliminado_en IS NULL
      AND u.estado = 'activo'
      AND (IFNULL(p_area, '') = '' OR u.area = p_area)
      AND (
          IFNULL(p_busqueda, '') = ''
          OR CONCAT(u.nombre, ' ', u.apellido) LIKE CONCAT('%', p_busqueda, '%')
          OR u.correo LIKE CONCAT('%', p_busqueda, '%')
          OR u.cargo  LIKE CONCAT('%', p_busqueda, '%')
          OR u.anexo  LIKE CONCAT('%', p_busqueda, '%')
          OR ta.String1 LIKE CONCAT('%', p_busqueda, '%')
      )
    ORDER BY u.apellido, u.nombre
    LIMIT v_por_pagina OFFSET v_offset;

    SELECT COUNT(*) AS total
    FROM usuario u
    LEFT JOIN tabla_maestra ta ON ta.IdMaestro = 79 AND ta.IdEmpresa = 1 AND ta.String2 = u.area
    WHERE u.eliminado_en IS NULL
      AND u.estado = 'activo'
      AND (IFNULL(p_area, '') = '' OR u.area = p_area)
      AND (
          IFNULL(p_busqueda, '') = ''
          OR CONCAT(u.nombre, ' ', u.apellido) LIKE CONCAT('%', p_busqueda, '%')
          OR u.correo LIKE CONCAT('%', p_busqueda, '%')
          OR u.cargo  LIKE CONCAT('%', p_busqueda, '%')
          OR u.anexo  LIKE CONCAT('%', p_busqueda, '%')
          OR ta.String1 LIKE CONCAT('%', p_busqueda, '%')
      );
END$$

DELIMITER ;
