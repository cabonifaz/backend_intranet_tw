-- ============================================================
-- SP_ObtenerAccesoMovil  (App Mobile HU-01)
-- Estado del acceso a la app de un usuario: su nombre de usuario,
-- si está habilitado y, si la tiene, la sesión vigente (equipo y fechas).
-- Para mostrarlo en la ficha del usuario de la intranet.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerAccesoMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerAccesoMovil(
    IN p_id_usuario BIGINT
)
proc: BEGIN
    IF NOT EXISTS (SELECT 1 FROM usuario WHERE id_usuario = p_id_usuario AND eliminado_en IS NULL) THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no encontrado.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT u.id_usuario,
           u.nombre_usuario,
           u.canal_acceso,
           (u.nombre_usuario IS NOT NULL AND u.canal_acceso IN ('movil', 'todos')) AS habilitado,
           s.nombre_dispositivo AS sesion_equipo,
           s.fecha_inicio       AS sesion_inicio,
           s.fecha_expiracion   AS sesion_expira
    FROM   usuario u
    LEFT JOIN sesion_usuario s
           ON s.id_sesion = (
                SELECT x.id_sesion
                FROM   sesion_usuario x
                WHERE  x.id_usuario       = u.id_usuario
                  AND  x.id_canal_acceso  = 2
                  AND  x.activo           = 1
                  AND  x.eliminado_en     IS NULL
                  AND  x.fecha_expiracion > NOW()
                ORDER BY x.fecha_inicio DESC
                LIMIT 1)
    WHERE  u.id_usuario = p_id_usuario;
END$$

DELIMITER ;
