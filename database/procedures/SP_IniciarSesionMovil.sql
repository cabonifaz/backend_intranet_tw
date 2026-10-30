-- ============================================================
-- SP_IniciarSesionMovil  (App Mobile HU-01)
-- Abre la sesión de la app móvil (canal 2 = App móvil de campo).
-- Regla: 1 usuario = 1 equipo a la vez.
--   · Si hay una sesión vigente en OTRO equipo y p_reemplazar_sesion = 0,
--     se rechaza el ingreso (IdTipoMensaje 1) indicando en qué equipo está.
--   · Si la sesión vigente es del MISMO equipo (o p_reemplazar_sesion = 1),
--     se cierra la anterior y se abre una nueva.
-- No toca usuario.sesion_token: la sesión de la intranet sigue intacta.
-- Devuelve el token de sesión (va dentro del JWT) y su vencimiento.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_IniciarSesionMovil;

DELIMITER $$

CREATE PROCEDURE SP_IniciarSesionMovil(
    IN p_id_usuario         BIGINT,
    IN p_id_dispositivo     VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_nombre_dispositivo VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_ip_origen          VARCHAR(45)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_horas_expiracion   INT,
    IN p_reemplazar_sesion  TINYINT
)
proc: BEGIN
    DECLARE v_id_usuario   BIGINT DEFAULT NULL;
    DECLARE v_id_sesion    BIGINT DEFAULT NULL;
    DECLARE v_equipo       VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_inicio       DATETIME;
    DECLARE v_token        VARCHAR(36)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_expira       DATETIME;
    DECLARE v_dispositivo  VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SET v_dispositivo = TRIM(IFNULL(p_id_dispositivo, ''));
    IF v_dispositivo = '' THEN
        SELECT 1 AS IdTipoMensaje, 'No se pudo identificar el equipo. Vuelve a intentarlo.' AS Mensaje;
        LEAVE proc;
    END IF;

    START TRANSACTION;

    -- Bloquea la fila del usuario: dos equipos que ingresan a la vez se atienden en orden.
    SELECT id_usuario INTO v_id_usuario
    FROM   usuario
    WHERE  id_usuario = p_id_usuario AND eliminado_en IS NULL
    FOR UPDATE;

    IF v_id_usuario IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Usuario o contraseña incorrectos.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- ¿Sesión vigente en otro equipo?
    SELECT id_sesion, nombre_dispositivo, fecha_inicio
    INTO   v_id_sesion, v_equipo, v_inicio
    FROM   sesion_usuario
    WHERE  id_usuario       = p_id_usuario
      AND  id_canal_acceso  = 2
      AND  activo           = 1
      AND  eliminado_en     IS NULL
      AND  fecha_expiracion > NOW()
      AND  IFNULL(id_dispositivo, '') <> v_dispositivo
    ORDER BY fecha_inicio DESC
    LIMIT 1;

    IF v_id_sesion IS NOT NULL AND IFNULL(p_reemplazar_sesion, 0) = 0 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje,
               CONCAT('Tu usuario ya tiene una sesión activa en otro equipo (',
                      IFNULL(NULLIF(v_equipo, ''), 'equipo no identificado'),
                      ') desde el ', DATE_FORMAT(v_inicio, '%d/%m/%Y %H:%i'),
                      '. Cierra sesión en ese equipo o pide a tu jefe que libere la sesión.') AS Mensaje;
        LEAVE proc;
    END IF;

    -- Cierra cualquier sesión móvil anterior del usuario (mismo equipo, vencidas o reemplazadas).
    UPDATE sesion_usuario
    SET    activo            = 0,
           fecha_revocacion  = NOW(),
           motivo_revocacion = IF(IFNULL(id_dispositivo, '') = v_dispositivo, 'NUEVO_INICIO_MISMO_EQUIPO', 'REEMPLAZADA_POR_OTRO_EQUIPO'),
           modificado_en     = NOW(),
           modificado_por    = p_id_usuario
    WHERE  id_usuario      = p_id_usuario
      AND  id_canal_acceso = 2
      AND  activo          = 1;

    SET v_token  = UUID();
    SET v_expira = DATE_ADD(NOW(), INTERVAL GREATEST(IFNULL(p_horas_expiracion, 12), 1) HOUR);

    INSERT INTO sesion_usuario (
        id_usuario, token_jti, id_canal_acceso, id_dispositivo, nombre_dispositivo,
        ip_origen, user_agent, activo, fecha_inicio, fecha_expiracion, creado_en, creado_por
    ) VALUES (
        p_id_usuario, v_token, 2, v_dispositivo, NULLIF(TRIM(IFNULL(p_nombre_dispositivo, '')), ''),
        NULLIF(TRIM(IFNULL(p_ip_origen, '')), ''), 'app_movil', 1, NOW(), v_expira, NOW(), p_id_usuario
    );

    UPDATE usuario SET ultimo_login = NOW() WHERE id_usuario = p_id_usuario;

    COMMIT;

    SELECT 2 AS IdTipoMensaje, 'Sesión iniciada.' AS Mensaje;
    SELECT v_token AS sesion_token, v_expira AS fecha_expiracion;
END$$

DELIMITER ;
