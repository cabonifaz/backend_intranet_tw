-- ============================================================
-- SP_CerrarSesionMovil  (App Mobile HU-01)
-- Cierra la sesión de la app del equipo actual y deja libre al
-- usuario para ingresar desde otro equipo.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_CerrarSesionMovil;

DELIMITER //

CREATE PROCEDURE SP_CerrarSesionMovil(
    IN p_id_usuario   BIGINT,
    IN p_sesion_token VARCHAR(36) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
BEGIN
    UPDATE sesion_usuario
    SET    activo            = 0,
           fecha_revocacion  = NOW(),
           motivo_revocacion = 'CIERRE_SESION',
           modificado_en     = NOW(),
           modificado_por    = p_id_usuario
    WHERE  id_usuario      = p_id_usuario
      AND  token_jti       = p_sesion_token
      AND  id_canal_acceso = 2
      AND  activo          = 1;

    SELECT 2 AS IdTipoMensaje, 'Sesión cerrada.' AS Mensaje;
END //

DELIMITER ;
