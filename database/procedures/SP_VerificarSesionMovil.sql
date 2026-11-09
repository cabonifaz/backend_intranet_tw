-- ============================================================
-- SP_VerificarSesionMovil  (App Mobile HU-01)
-- Se ejecuta en cada request con un JWT de la app (claim canal = movil).
-- La sesión es válida si sigue activa, no venció y el usuario sigue
-- activo con acceso a la app. Si no, la app vuelve al login.
-- Sesión única por cuenta: al ingresar desde otro equipo, SP_IniciarSesionMovil cierra la sesión del
-- equipo anterior (motivo_revocacion = 'REEMPLAZADA_POR_OTRO_EQUIPO'). Cuando ese primer equipo vuelve
-- a preguntar, la respuesta (IdTipoMensaje 1) trae el motivo para mostrarlo en el login:
--   REEMPLAZADA_POR_OTRO_EQUIPO ... "Tu sesión se cerró porque se inició sesión con tu usuario en otro equipo."
--   LIBERADA_POR_JEFE .............. "Tu jefe cerró tu sesión. Vuelve a iniciar sesión."
--   venció (fecha_expiracion) ...... "Tu sesión venció. Vuelve a iniciar sesión."
--   usuario/acceso desactivado ..... "Tu acceso a la app ya no está habilitado. Consulta con tu jefe."
--   cualquier otro caso ............ "Tu sesión terminó. Vuelve a iniciar sesión."
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_VerificarSesionMovil;

DELIMITER //

CREATE PROCEDURE SP_VerificarSesionMovil(
    IN p_id_usuario   BIGINT,
    IN p_sesion_token VARCHAR(36) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
BEGIN
    DECLARE v_activo      TINYINT      DEFAULT NULL;
    DECLARE v_expira      DATETIME     DEFAULT NULL;
    DECLARE v_motivo      VARCHAR(60)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_usuario_ok  TINYINT      DEFAULT 0;

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
        -- Motivo por el que la sesión ya no sirve (el token pertenece a una sesión que existió)
        SELECT s.activo, s.fecha_expiracion, s.motivo_revocacion
        INTO   v_activo, v_expira, v_motivo
        FROM   sesion_usuario s
        WHERE  s.id_usuario      = p_id_usuario
          AND  s.token_jti       = p_sesion_token
          AND  s.id_canal_acceso = 2
        ORDER BY s.id_sesion DESC
        LIMIT 1;

        SELECT COUNT(*) INTO v_usuario_ok
        FROM   usuario u
        WHERE  u.id_usuario     = p_id_usuario
          AND  u.eliminado_en   IS NULL
          AND  u.estado         = 'activo'
          AND  u.nombre_usuario IS NOT NULL
          AND  u.canal_acceso   IN ('movil', 'todos');

        SELECT 1 AS IdTipoMensaje,
               CASE
                   WHEN v_usuario_ok = 0
                       THEN 'Tu acceso a la app ya no está habilitado. Consulta con tu jefe.'
                   WHEN v_activo = 0 AND v_motivo = 'REEMPLAZADA_POR_OTRO_EQUIPO'
                       THEN 'Tu sesión se cerró porque se inició sesión con tu usuario en otro equipo.'
                   WHEN v_activo = 0 AND v_motivo = 'LIBERADA_POR_JEFE'
                       THEN 'Tu jefe cerró tu sesión. Vuelve a iniciar sesión.'
                   WHEN v_activo = 1 AND v_expira <= NOW()
                       THEN 'Tu sesión venció. Vuelve a iniciar sesión.'
                   ELSE 'Tu sesión terminó. Vuelve a iniciar sesión.'
               END AS Mensaje;
    END IF;
END //

DELIMITER ;
