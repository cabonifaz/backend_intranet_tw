-- Permisos por módulo para una combinación ÁREA + ROL (ticket #4301).
-- Todo sale de la tabla permiso_area_rol: si no hay fila, el acceso es 'ninguno'.
-- es_excepcion = 1 cuando el acceso está configurado en la tabla.
DROP PROCEDURE IF EXISTS SP_ObtenerPermisosAreaRol;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerPermisosAreaRol(
    IN p_area VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_rol  VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
BEGIN
    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT
        m.String2                         AS modulo,
        m.String1                         AS modulo_label,
        m.String3                         AS area_modulo,
        IFNULL(p.acceso, 'ninguno')       AS acceso,
        (p.acceso IS NOT NULL)            AS es_excepcion
    FROM tabla_maestra m
    LEFT JOIN permiso_area_rol p
           ON p.area = p_area AND p.rol = p_rol AND p.modulo = m.String2
    WHERE m.IdMaestro = 85 AND m.IdEmpresa = 1
    ORDER BY m.Num1;
END$$

DELIMITER ;
