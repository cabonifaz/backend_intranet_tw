-- HU-83 / HU-84 — Sección 05 de la ficha
--   p_perspectiva = 'titular'  → "Suplentes que lo cubren"
--   p_perspectiva = 'suplente' → "Personas a las que suple"
DROP PROCEDURE IF EXISTS SP_ObtenerSuplenciasPorUsuario;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerSuplenciasPorUsuario(
    IN p_id_usuario  BIGINT,
    IN p_perspectiva VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
BEGIN
    IF p_perspectiva NOT IN ('titular', 'suplente') THEN
        SELECT 1 AS IdTipoMensaje, 'Perspectiva no válida. Use titular o suplente.' AS Mensaje;
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
        WHERE us.SoftDelete = 0
          AND (
              (p_perspectiva = 'titular'  AND us.id_titular  = p_id_usuario)
           OR (p_perspectiva = 'suplente' AND us.id_suplente = p_id_usuario)
          )
        ORDER BY us.activo DESC, us.fecha_inicio DESC;
    END IF;
END$$

DELIMITER ;
