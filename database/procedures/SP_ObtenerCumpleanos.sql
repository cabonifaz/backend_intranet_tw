-- Cumpleaños del mes (ticket #4303, uso de RR. HH.). Solo día y mes, nunca el año.
DROP PROCEDURE IF EXISTS SP_ObtenerCumpleanos;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerCumpleanos(
    IN p_mes INT
)
BEGIN
    IF IFNULL(p_mes, 0) NOT BETWEEN 1 AND 12 THEN
        SELECT 1 AS IdTipoMensaje, 'El mes debe estar entre 1 y 12.' AS Mensaje;
    ELSE
        SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

        SELECT
            u.id_usuario,
            CONCAT(u.nombre, ' ', u.apellido) AS nombre_completo,
            IFNULL(ta.String1, '')            AS area_label,
            DAY(u.fecha_nacimiento)           AS dia,
            DATE_FORMAT(u.fecha_nacimiento, '%d/%m') AS cumpleanos
        FROM usuario u
        LEFT JOIN tabla_maestra ta ON ta.IdMaestro = 79 AND ta.IdEmpresa = 1 AND ta.String2 = u.area
        WHERE u.eliminado_en IS NULL
          AND u.estado = 'activo'
          AND u.fecha_nacimiento IS NOT NULL
          AND MONTH(u.fecha_nacimiento) = p_mes
        ORDER BY DAY(u.fecha_nacimiento), u.apellido;
    END IF;
END$$

DELIMITER ;
