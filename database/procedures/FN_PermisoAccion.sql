-- ¿El usuario puede ejecutar la acción? (1 = sí, 0 = no). Ticket #4301.
-- Lee solo datos: ACCION_SISTEMA (88) dice el módulo y el nivel exigido, y
-- permiso_area_rol dice el acceso del área + rol del usuario en ese módulo.
-- Usuario inactivo, sin área, acción inexistente o sin fila en la matriz → 0.
DROP FUNCTION IF EXISTS FN_PermisoAccion;

DELIMITER $$

CREATE FUNCTION FN_PermisoAccion(
    p_id_usuario BIGINT,
    p_accion     VARCHAR(60) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
) RETURNS TINYINT
READS SQL DATA
BEGIN
    DECLARE v_area    VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_rol     VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_modulo  VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_nivel   INT;
    DECLARE v_acceso  VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    SELECT area, rol_sistema INTO v_area, v_rol
    FROM usuario
    WHERE id_usuario = p_id_usuario AND eliminado_en IS NULL AND estado = 'activo'
    LIMIT 1;

    SELECT String3, Num1 INTO v_modulo, v_nivel
    FROM tabla_maestra
    WHERE IdMaestro = 88 AND IdEmpresa = 1 AND String2 = p_accion
    LIMIT 1;

    IF v_rol IS NULL OR v_modulo IS NULL THEN
        RETURN 0;
    END IF;

    SELECT acceso INTO v_acceso
    FROM permiso_area_rol
    WHERE area = IFNULL(v_area, '') AND rol = v_rol AND modulo = v_modulo
    LIMIT 1;

    RETURN IF(
        CASE IFNULL(v_acceso, 'ninguno')
            WHEN 'administrar' THEN 4 WHEN 'supervisar' THEN 3
            WHEN 'editar'      THEN 2 WHEN 'ver'        THEN 1 ELSE 0
        END >= IFNULL(v_nivel, 99), 1, 0);
END$$

DELIMITER ;
