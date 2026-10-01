-- HU-83 — Combo "Supervisor directo": usuarios activos con rol de jefatura
DROP PROCEDURE IF EXISTS SP_ObtenerJefesDisponibles;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerJefesDisponibles()
BEGIN
    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT
        u.id_usuario,
        u.nombre,
        u.apellido,
        u.correo,
        u.rol_sistema,
        tm_rol.String1      AS rol_sistema_label,
        u.area_comercial,
        u.telefono,
        'Activo'            AS estado,
        u.ultimo_login      AS ultimo_acceso,
        u.creado_en         AS fecha_creacion
    FROM usuario u
    JOIN tabla_maestra tm_rol
      ON tm_rol.IdMaestro = 68
     AND tm_rol.IdEmpresa = 1
     AND tm_rol.String2   = u.rol_sistema
     AND tm_rol.Num3      = 1
    WHERE u.eliminado_en IS NULL
      AND u.estado = 'activo'
    ORDER BY u.nombre ASC, u.apellido ASC;
END$$

DELIMITER ;
