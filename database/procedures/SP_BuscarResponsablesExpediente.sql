-- HU-33 Búsqueda del nuevo responsable del expediente.
-- Acción expediente_reasignar. Usuarios activos del área responsable de la etapa (o de Gerencia / TI) que pueden
-- trabajar el expediente (acción expediente_avanzar), distintos del responsable actual, filtrados por nombre, correo
-- o cargo. Primero los del área de la etapa.
-- Resultados: 1 mensaje · 2 usuarios (máximo 20)
DROP PROCEDURE IF EXISTS SP_BuscarResponsablesExpediente;

DELIMITER $$

CREATE PROCEDURE SP_BuscarResponsablesExpediente(
    IN p_id_usuario    BIGINT,
    IN p_id_expediente BIGINT,
    IN p_busqueda      VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_area     VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_actual   BIGINT;
    DECLARE v_busqueda VARCHAR(102) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    IF FN_PermisoAccion(p_id_usuario, 'expediente_reasignar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para reasignar el responsable del expediente.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT IFNULL(area_responsable, ''), id_responsable_actual INTO v_area, v_actual
    FROM expediente_digital WHERE id_expediente = p_id_expediente AND eliminado_en IS NULL;
    SET v_busqueda = IF(NULLIF(TRIM(IFNULL(p_busqueda, '')), '') IS NULL, NULL, CONCAT('%', TRIM(p_busqueda), '%'));

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT u.id_usuario, CONCAT(u.nombre, ' ', u.apellido) AS nombre, u.correo, u.cargo, u.area, a.String1 AS area_nombre,
           u.rol_sistema
    FROM usuario u
    LEFT JOIN tabla_maestra a ON a.IdMaestro = 79 AND a.IdEmpresa = 1 AND a.String2 = u.area
    WHERE u.eliminado_en IS NULL AND u.estado = 'activo'
      AND u.id_usuario <> IFNULL(v_actual, 0)
      AND (u.area = v_area OR u.area IN ('gerencia', 'ti'))
      AND FN_PermisoAccion(u.id_usuario, 'expediente_avanzar') = 1
      AND (v_busqueda IS NULL OR CONCAT(u.nombre, ' ', u.apellido) LIKE v_busqueda
           OR u.correo LIKE v_busqueda OR u.cargo LIKE v_busqueda)
    ORDER BY (u.area = v_area) DESC, u.nombre, u.apellido
    LIMIT 20;
END$$

DELIMITER ;
