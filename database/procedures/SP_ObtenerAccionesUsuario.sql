-- Acciones que puede ejecutar el usuario (ticket #4301). Las usa el back para validar
-- cada endpoint y el front para habilitar o esconder botones.
DROP PROCEDURE IF EXISTS SP_ObtenerAccionesUsuario;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerAccionesUsuario(
    IN p_id_usuario BIGINT
)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM usuario WHERE id_usuario = p_id_usuario AND eliminado_en IS NULL AND estado = 'activo') THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no encontrado o inactivo.' AS Mensaje;
    ELSE
        SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

        SELECT a.String2  AS accion,
               a.String1  AS accion_label,
               a.String3  AS modulo,
               CASE a.Num1 WHEN 1 THEN 'ver' WHEN 2 THEN 'editar' WHEN 3 THEN 'supervisar' ELSE 'administrar' END AS nivel_requerido,
               FN_PermisoAccion(p_id_usuario, a.String2) AS permitido
        FROM tabla_maestra a
        WHERE a.IdMaestro = 88 AND a.IdEmpresa = 1
        ORDER BY a.String3, a.Num1, a.String2;
    END IF;
END$$

DELIMITER ;
