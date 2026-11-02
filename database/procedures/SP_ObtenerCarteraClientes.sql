-- Observaciones 31/10 (#4) — Cartera de clientes: qué clientes tiene asignados cada comercial.
-- El Administrador (acción cartera_asignar) ve todos los clientes y puede filtrar por comercial; el resto de usuarios
-- con acceso a Requerimientos (rq_ver) ve solo su propia cartera.
-- Filtros: p_id_comercial, p_busqueda (razón social o RUC), p_asignacion ('' | todos | asignados | sin_asignar).
-- Resultados: 1 mensaje, 2 clientes, 3 total, 4 comerciales (con cantidad de clientes), 5 puede_asignar.
DROP PROCEDURE IF EXISTS SP_ObtenerCarteraClientes;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerCarteraClientes(
    IN p_id_usuario   BIGINT,
    IN p_id_comercial BIGINT,
    IN p_busqueda     VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_asignacion   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_pagina       INT,
    IN p_por_pagina   INT
)
proc: BEGIN
    DECLARE v_admin      TINYINT DEFAULT 0;
    DECLARE v_busqueda   VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_asignacion VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_por_pagina INT;
    DECLARE v_offset     INT;

    SET v_admin = FN_PermisoAccion(p_id_usuario, 'cartera_asignar');
    IF v_admin = 0 AND FN_PermisoAccion(p_id_usuario, 'rq_ver') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver la cartera de clientes.' AS Mensaje; LEAVE proc;
    END IF;

    -- Sin permiso de administrar: solo su cartera
    IF v_admin = 0 THEN
        SET p_id_comercial = p_id_usuario;
        SET p_asignacion   = 'asignados';
    END IF;

    SET v_busqueda   = TRIM(IFNULL(p_busqueda, ''));
    SET v_asignacion = LOWER(TRIM(IFNULL(p_asignacion, '')));
    SET v_por_pagina = IF(IFNULL(p_por_pagina, 0) BETWEEN 1 AND 500, p_por_pagina, 20);
    SET v_offset     = (GREATEST(IFNULL(p_pagina, 1), 1) - 1) * v_por_pagina;

    DROP TEMPORARY TABLE IF EXISTS tmp_cartera_cli;
    CREATE TEMPORARY TABLE tmp_cartera_cli AS
    SELECT c.id_cliente, c.razon_social, c.ruc, c.estado, c.id_comercial_cartera AS id_comercial,
           NULLIF(TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))), '') AS comercial,
           c.cartera_asignado_en AS asignado_en,
           NULLIF(TRIM(CONCAT(IFNULL(ua.nombre, ''), ' ', IFNULL(ua.apellido, ''))), '') AS asignado_por
    FROM cliente c
    LEFT JOIN usuario u  ON u.id_usuario  = c.id_comercial_cartera
    LEFT JOIN usuario ua ON ua.id_usuario = c.cartera_asignado_por
    WHERE c.SoftDelete = 0 AND c.eliminado_en IS NULL
      AND (IFNULL(p_id_comercial, 0) = 0 OR c.id_comercial_cartera = p_id_comercial)
      AND (v_asignacion IN ('', 'todos')
           OR (v_asignacion = 'asignados'   AND c.id_comercial_cartera IS NOT NULL)
           OR (v_asignacion = 'sin_asignar' AND c.id_comercial_cartera IS NULL))
      AND (v_busqueda = '' OR c.razon_social LIKE CONCAT('%', v_busqueda, '%') OR c.ruc LIKE CONCAT('%', v_busqueda, '%'));

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT * FROM tmp_cartera_cli ORDER BY razon_social LIMIT v_por_pagina OFFSET v_offset;
    SELECT COUNT(*) AS total FROM tmp_cartera_cli;
    DROP TEMPORARY TABLE IF EXISTS tmp_cartera_cli;

    -- Comerciales activos del área comercial (para asignar y filtrar)
    SELECT u.id_usuario AS id, CONCAT(u.nombre, ' ', u.apellido) AS nombre, u.cargo,
           (SELECT COUNT(*) FROM cliente c WHERE c.id_comercial_cartera = u.id_usuario
              AND c.SoftDelete = 0 AND c.eliminado_en IS NULL) AS clientes
    FROM usuario u
    WHERE u.eliminado_en IS NULL AND u.estado = 'activo' AND u.area = 'comercial'
      AND (v_admin = 1 OR u.id_usuario = p_id_usuario)
    ORDER BY nombre;

    SELECT v_admin AS puede_asignar;
END$$

DELIMITER ;
