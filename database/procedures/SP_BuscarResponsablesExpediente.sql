-- HU-33 Buscador del nuevo responsable (filtrado por rol Comercial). Acción expediente_reasignar.
-- Usuarios activos del área Comercial, distintos del responsable que se reemplaza (p_id_excluir), filtrados por
-- nombre, correo o cargo. Sirve para el nuevo responsable y para elegir el comercial de la Opción C.
-- Resultados: 1 mensaje · 2 usuarios (máximo 20)
DROP PROCEDURE IF EXISTS SP_BuscarResponsablesExpediente;

DELIMITER $$

CREATE PROCEDURE SP_BuscarResponsablesExpediente(
    IN p_id_usuario BIGINT,
    IN p_busqueda   VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_excluir BIGINT
)
proc: BEGIN
    DECLARE v_busqueda VARCHAR(102) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    IF FN_PermisoAccion(p_id_usuario, 'expediente_reasignar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para reasignar responsables.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_busqueda = IF(NULLIF(TRIM(IFNULL(p_busqueda, '')), '') IS NULL, NULL, CONCAT('%', TRIM(p_busqueda), '%'));

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT u.id_usuario, CONCAT(u.nombre, ' ', u.apellido) AS nombre, u.correo, u.cargo, u.area, a.String1 AS area_nombre,
           u.rol_sistema, u.sede_operativa
    FROM usuario u
    LEFT JOIN tabla_maestra a ON a.IdMaestro = 79 AND a.IdEmpresa = 1 AND a.String2 = u.area
    WHERE u.eliminado_en IS NULL AND u.estado = 'activo' AND u.area = 'comercial'
      AND u.id_usuario <> IFNULL(p_id_excluir, 0)
      AND (v_busqueda IS NULL OR CONCAT(u.nombre, ' ', u.apellido) LIKE v_busqueda
           OR u.correo LIKE v_busqueda OR u.cargo LIKE v_busqueda)
    ORDER BY u.nombre, u.apellido
    LIMIT 20;
END$$

DELIMITER ;
