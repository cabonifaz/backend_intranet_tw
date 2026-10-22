-- ============================================================
-- SP_LiberarSesionMovil  (App Mobile HU-01)
-- El jefe/administrador cierra la sesión de la app de un usuario
-- (p. ej. equipo perdido o cambio de celular) para que pueda
-- ingresar desde otro equipo.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_LiberarSesionMovil;

DELIMITER $$

CREATE PROCEDURE SP_LiberarSesionMovil(
    IN p_id_usuario  BIGINT,
    IN p_id_ejecutor BIGINT
)
proc: BEGIN
    DECLARE v_filas INT DEFAULT 0;

    IF NOT EXISTS (SELECT 1 FROM usuario WHERE id_usuario = p_id_usuario AND eliminado_en IS NULL) THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no encontrado.' AS Mensaje;
        LEAVE proc;
    END IF;

    UPDATE sesion_usuario
    SET    activo            = 0,
           fecha_revocacion  = NOW(),
           motivo_revocacion = 'LIBERADA_POR_JEFE',
           modificado_en     = NOW(),
           modificado_por    = p_id_ejecutor
    WHERE  id_usuario       = p_id_usuario
      AND  id_canal_acceso  = 2
      AND  activo           = 1
      AND  fecha_expiracion > NOW();

    SET v_filas = ROW_COUNT();

    SELECT 2 AS IdTipoMensaje,
           IF(v_filas > 0,
              'Se cerró la sesión de la app. El usuario ya puede ingresar desde otro equipo.',
              'El usuario no tenía una sesión activa en la app.') AS Mensaje;
END$$

DELIMITER ;
