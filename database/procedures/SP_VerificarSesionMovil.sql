-- ============================================================
-- SP_VerificarSesionMovil  (App Mobile HU-01)
-- Se ejecuta en cada request con un JWT de la app (claim canal = movil).
-- La sesión es válida si sigue activa, no venció y el usuario sigue
-- activo con acceso a la app. Si no, la app vuelve al login.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_VerificarSesionMovil;

DELIMITER //

CREATE PROCEDURE SP_VerificarSesionMovil(
    IN p_id_usuario   BIGINT,
    IN p_sesion_token VARCHAR(36) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
BEGIN
    IF EXISTS (
        SELECT 1
        FROM   sesion_usuario s
        JOIN   usuario u ON u.id_usuario = s.id_usuario
        WHERE  s.id_usuario       = p_id_usuario
          AND  s.token_jti        = p_sesion_token
          AND  s.id_canal_acceso  = 2
          AND  s.activo           = 1
          AND  s.eliminado_en     IS NULL
          AND  s.fecha_expiracion > NOW()
          AND  u.eliminado_en     IS NULL
          AND  u.estado           = 'activo'
          AND  u.nombre_usuario   IS NOT NULL
          AND  u.canal_acceso     IN ('movil', 'todos')
    ) THEN
        SELECT 2 AS IdTipoMensaje, 'Sesión válida.' AS Mensaje;
    ELSE
        SELECT 1 AS IdTipoMensaje, 'Tu sesión terminó. Vuelve a iniciar sesión.' AS Mensaje;
    END IF;
END //

DELIMITER ;
