-- ============================================================
-- SP_AsignarAccesoMovil  (App Mobile HU-01)
-- El jefe asigna (o quita) el usuario con el que la persona entra a la app.
--   p_habilitar = 1: guarda nombre_usuario y habilita el canal móvil
--                    (intranet -> todos; movil/todos se mantienen).
--   p_habilitar = 0: quita el usuario, deja solo la intranet y cierra
--                    la sesión de la app si la hubiera.
-- El nombre de usuario se guarda en minúsculas y debe ser único entre
-- los usuarios vigentes (no hay UNIQUE en la tabla por el borrado lógico).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_AsignarAccesoMovil;

DELIMITER $$

CREATE PROCEDURE SP_AsignarAccesoMovil(
    IN p_id_usuario     BIGINT,
    IN p_nombre_usuario VARCHAR(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_habilitar      TINYINT,
    IN p_id_ejecutor    BIGINT
)
proc: BEGIN
    DECLARE v_canal   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_usuario VARCHAR(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SELECT canal_acceso INTO v_canal
    FROM   usuario
    WHERE  id_usuario = p_id_usuario AND eliminado_en IS NULL;

    IF v_canal IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no encontrado.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF v_canal = 'extranet' THEN
        SELECT 1 AS IdTipoMensaje, 'Los usuarios del portal del cliente no pueden usar la app de campo.' AS Mensaje;
        LEAVE proc;
    END IF;

    START TRANSACTION;

    IF IFNULL(p_habilitar, 1) = 1 THEN
        SET v_usuario = LOWER(TRIM(IFNULL(p_nombre_usuario, '')));

        IF CHAR_LENGTH(v_usuario) < 4 THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, 'El usuario debe tener al menos 4 caracteres.' AS Mensaje;
            LEAVE proc;
        END IF;

        IF EXISTS (
            SELECT 1 FROM usuario
            WHERE  nombre_usuario = v_usuario
              AND  eliminado_en   IS NULL
              AND  id_usuario    <> p_id_usuario
        ) THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, CONCAT('El usuario "', v_usuario, '" ya está asignado a otra persona.') AS Mensaje;
            LEAVE proc;
        END IF;

        UPDATE usuario
        SET    nombre_usuario = v_usuario,
               canal_acceso   = IF(canal_acceso = 'intranet', 'todos', canal_acceso),
               modificado_en  = NOW(),
               modificado_por = p_id_ejecutor
        WHERE  id_usuario = p_id_usuario;

        COMMIT;
        SELECT 2 AS IdTipoMensaje, CONCAT('Acceso a la app habilitado con el usuario "', v_usuario, '".') AS Mensaje;
    ELSE
        UPDATE usuario
        SET    nombre_usuario = NULL,
               canal_acceso   = IF(canal_acceso = 'todos', 'intranet', canal_acceso),
               modificado_en  = NOW(),
               modificado_por = p_id_ejecutor
        WHERE  id_usuario = p_id_usuario;

        UPDATE sesion_usuario
        SET    activo            = 0,
               fecha_revocacion  = NOW(),
               motivo_revocacion = 'ACCESO_DESHABILITADO',
               modificado_en     = NOW(),
               modificado_por    = p_id_ejecutor
        WHERE  id_usuario      = p_id_usuario
          AND  id_canal_acceso = 2
          AND  activo          = 1;

        COMMIT;
        SELECT 2 AS IdTipoMensaje, 'Acceso a la app deshabilitado.' AS Mensaje;
    END IF;
END$$

DELIMITER ;
