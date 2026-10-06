-- Permisos por módulo para una combinación ÁREA + ROL (reunión 02-oct).
--   Regla general (si no hay excepción en permiso_area_rol):
--     · Administrador de Gerencia o TI ........ administrar en todos los módulos
--     · Módulo común ('*', dashboard) ......... ver
--     · Módulo de su propia área .............. según el rol:
--         administrador = administrar · supervisor = supervisar · usuario = editar · visor = ver
--     · Módulo de otra área ................... ninguno
--   es_excepcion = 1 cuando el acceso viene de permiso_area_rol (configurable).
DROP PROCEDURE IF EXISTS SP_ObtenerPermisosAreaRol;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerPermisosAreaRol(
    IN p_area VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_rol  VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
BEGIN
    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT
        m.String2  AS modulo,
        m.String1  AS modulo_label,
        m.String3  AS area_modulo,
        COALESCE(
            p.acceso,
            CASE
                WHEN p_rol = 'administrador' AND p_area IN ('gerencia', 'ti') THEN 'administrar'
                WHEN m.String3 = '*'                                         THEN 'ver'
                WHEN m.String3 = p_area THEN
                    CASE p_rol
                        WHEN 'administrador' THEN 'administrar'
                        WHEN 'supervisor'    THEN 'supervisar'
                        WHEN 'usuario'       THEN 'editar'
                        WHEN 'visor'         THEN 'ver'
                        ELSE 'ninguno'
                    END
                ELSE 'ninguno'
            END
        )          AS acceso,
        (p.acceso IS NOT NULL) AS es_excepcion
    FROM tabla_maestra m
    LEFT JOIN permiso_area_rol p
           ON p.area = p_area AND p.rol = p_rol AND p.modulo = m.String2
    WHERE m.IdMaestro = 85 AND m.IdEmpresa = 1
    ORDER BY m.Num1;
END$$

DELIMITER ;
