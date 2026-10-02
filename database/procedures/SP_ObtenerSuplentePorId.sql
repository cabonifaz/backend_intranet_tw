-- HU-84 — Una asignación de suplencia
DROP PROCEDURE IF EXISTS SP_ObtenerSuplentePorId;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerSuplentePorId(
    IN p_id_asignacion INT
)
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM usuario_suplente WHERE id = p_id_asignacion AND SoftDelete = 0
    ) THEN
        SELECT 1 AS IdTipoMensaje, 'Asignación no encontrada.' AS Mensaje;
    ELSE
        SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

        SELECT
            us.id                                            AS id_asignacion,
            us.id_titular,
            t.nombre                                         AS titular_nombre,
            t.apellido                                       AS titular_apellido,
            t.cargo                                          AS titular_cargo,
            us.id_suplente,
            s.nombre                                         AS suplente_nombre,
            s.apellido                                       AS suplente_apellido,
            s.cargo                                          AS suplente_cargo,
            us.fecha_inicio,
            us.fecha_fin,
            IF(us.activo = 1, 'Activo', 'Inactivo')          AS estado,
            us.FchCre                                        AS fecha_creacion
        FROM usuario_suplente us
        LEFT JOIN usuario t ON t.id_usuario = us.id_titular
        LEFT JOIN usuario s ON s.id_usuario = us.id_suplente
        WHERE us.id = p_id_asignacion;
    END IF;
END$$

DELIMITER ;
