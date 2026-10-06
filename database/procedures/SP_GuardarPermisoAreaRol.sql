-- Define una excepción de acceso para ÁREA + ROL + MÓDULO.
--   p_acceso: ninguno | ver | editar | supervisar | administrar.
--   Vacío o NULL → elimina la excepción (vuelve a la regla general).
DROP PROCEDURE IF EXISTS SP_GuardarPermisoAreaRol;

DELIMITER $$

CREATE PROCEDURE SP_GuardarPermisoAreaRol(
    IN p_area       VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_rol        VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_modulo     VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_acceso     VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_usuario BIGINT
)
proc: BEGIN
    DECLARE v_usu VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    IF NOT EXISTS (SELECT 1 FROM tabla_maestra WHERE IdMaestro = 79 AND IdEmpresa = 1 AND String2 = p_area) THEN
        SELECT 1 AS IdTipoMensaje, 'El área no es válida.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM tabla_maestra WHERE IdMaestro = 68 AND IdEmpresa = 1 AND String2 = p_rol) THEN
        SELECT 1 AS IdTipoMensaje, 'El rol no es válido.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM tabla_maestra WHERE IdMaestro = 85 AND IdEmpresa = 1 AND String2 = p_modulo) THEN
        SELECT 1 AS IdTipoMensaje, 'El módulo no es válido.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF IFNULL(p_acceso, '') <> '' AND p_acceso NOT IN ('ninguno', 'ver', 'editar', 'supervisar', 'administrar') THEN
        SELECT 1 AS IdTipoMensaje, 'Acceso no válido. Use ninguno, ver, editar, supervisar o administrar.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT correo INTO v_usu FROM usuario WHERE id_usuario = p_id_usuario LIMIT 1;

    IF IFNULL(p_acceso, '') = '' THEN
        DELETE FROM permiso_area_rol WHERE area = p_area AND rol = p_rol AND modulo = p_modulo;
        SELECT 2 AS IdTipoMensaje, 'Se restableció el acceso por defecto.' AS Mensaje;
    ELSE
        INSERT INTO permiso_area_rol (area, rol, modulo, acceso, UsuMod, FchMod)
        VALUES (p_area, p_rol, p_modulo, p_acceso, v_usu, NOW())
        ON DUPLICATE KEY UPDATE acceso = p_acceso, UsuMod = v_usu, FchMod = NOW();
        SELECT 2 AS IdTipoMensaje, 'Permiso guardado correctamente.' AS Mensaje;
    END IF;
END$$

DELIMITER ;
