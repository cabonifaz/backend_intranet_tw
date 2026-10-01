-- HU-83 — Crear (p_id_usuario = 0) o editar un usuario
--   p_password_hash: NULL = no cambia la contraseña (solo en edición)
--   p_sedes_json:    arreglo JSON de ids de sede, ej. '[1,3,4]'
DROP PROCEDURE IF EXISTS SP_GuardarUsuario;

DELIMITER $$

CREATE PROCEDURE SP_GuardarUsuario(
    IN p_id_usuario                     BIGINT,
    IN p_nombre                         VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_apellido                       VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_tipo_documento                 VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_numero_documento               VARCHAR(15)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_correo                         VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_telefono                       VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_cargo                          VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_rol_sistema                    VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_area_comercial                 VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_base_operativa                 VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_supervisor                  BIGINT,
    IN p_sedes_json                     TEXT,
    IN p_habilitado_firma_inacal        TINYINT,
    IN p_numero_registro_inacal         VARCHAR(50)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_fecha_expiracion_certificacion DATE,
    IN p_requiere_induccion_sctr        TINYINT,
    IN p_password_hash                  VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_forzar_cambio_contrasena       TINYINT,
    IN p_enviar_credenciales_correo     TINYINT,
    IN p_autenticacion_2fa              TINYINT,
    IN p_guardar_como_borrador          TINYINT,
    IN p_id_usuario_ejecutor            BIGINT
)
proc: BEGIN
    DECLARE v_id      BIGINT;
    DECLARE v_usu     VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1
            @err_msg  = MESSAGE_TEXT,
            @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje,
               CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    -- ── Validaciones ─────────────────────────────────────────────────────
    IF EXISTS (
        SELECT 1 FROM usuario
        WHERE correo = p_correo
          AND eliminado_en IS NULL
          AND (p_id_usuario = 0 OR id_usuario <> p_id_usuario)
    ) THEN
        SELECT 1 AS IdTipoMensaje, 'El correo ya está registrado para otro usuario.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM tabla_maestra
        WHERE IdMaestro = 68 AND IdEmpresa = 1 AND String2 = p_rol_sistema
    ) THEN
        SELECT 1 AS IdTipoMensaje, 'El rol seleccionado no es válido.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF p_id_supervisor IS NOT NULL AND p_id_usuario <> 0 AND p_id_supervisor = p_id_usuario THEN
        SELECT 1 AS IdTipoMensaje, 'Un usuario no puede ser su propio supervisor.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF p_id_usuario = 0 AND (p_password_hash IS NULL OR p_password_hash = '') THEN
        SELECT 1 AS IdTipoMensaje, 'La contraseña temporal es obligatoria para un usuario nuevo.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF p_id_usuario <> 0 AND NOT EXISTS (
        SELECT 1 FROM usuario WHERE id_usuario = p_id_usuario AND eliminado_en IS NULL
    ) THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no encontrado.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT correo INTO v_usu FROM usuario WHERE id_usuario = p_id_usuario_ejecutor LIMIT 1;

    START TRANSACTION;

    -- ── Crear o actualizar ───────────────────────────────────────────────
    IF p_id_usuario = 0 THEN
        INSERT INTO usuario (
            nombre, apellido, tipo_documento, numero_documento, correo,
            telefono, cargo, rol_sistema, area_comercial, base_operativa,
            id_supervisor, habilitado_firma_inacal, numero_registro_inacal,
            fecha_expiracion_certificacion, requiere_induccion_sctr,
            password_hash, forzar_cambio_contrasena, enviar_credenciales_correo,
            autenticacion_2fa, canal_acceso, estado, creado_en, creado_por
        ) VALUES (
            p_nombre, p_apellido, p_tipo_documento, p_numero_documento, p_correo,
            p_telefono, p_cargo, p_rol_sistema, p_area_comercial, p_base_operativa,
            p_id_supervisor, IFNULL(p_habilitado_firma_inacal, 0), p_numero_registro_inacal,
            p_fecha_expiracion_certificacion, IFNULL(p_requiere_induccion_sctr, 0),
            p_password_hash, IFNULL(p_forzar_cambio_contrasena, 0), IFNULL(p_enviar_credenciales_correo, 1),
            IFNULL(p_autenticacion_2fa, 0), 'intranet',
            IF(p_guardar_como_borrador = 1, 'borrador', 'activo'),
            NOW(), p_id_usuario_ejecutor
        );
        SET v_id = LAST_INSERT_ID();
    ELSE
        UPDATE usuario SET
            nombre                         = p_nombre,
            apellido                       = p_apellido,
            tipo_documento                 = p_tipo_documento,
            numero_documento               = p_numero_documento,
            correo                         = p_correo,
            telefono                       = p_telefono,
            cargo                          = p_cargo,
            rol_sistema                    = p_rol_sistema,
            area_comercial                 = p_area_comercial,
            base_operativa                 = p_base_operativa,
            id_supervisor                  = p_id_supervisor,
            habilitado_firma_inacal        = IFNULL(p_habilitado_firma_inacal, 0),
            numero_registro_inacal         = p_numero_registro_inacal,
            fecha_expiracion_certificacion = p_fecha_expiracion_certificacion,
            requiere_induccion_sctr        = IFNULL(p_requiere_induccion_sctr, 0),
            password_hash                  = COALESCE(NULLIF(p_password_hash, ''), password_hash),
            forzar_cambio_contrasena       = IFNULL(p_forzar_cambio_contrasena, 0),
            enviar_credenciales_correo     = IFNULL(p_enviar_credenciales_correo, 1),
            autenticacion_2fa              = IFNULL(p_autenticacion_2fa, 0),
            estado = CASE
                         WHEN p_guardar_como_borrador = 1 THEN 'borrador'
                         WHEN estado = 'borrador'         THEN 'activo'
                         ELSE estado
                     END,
            modificado_en                  = NOW(),
            modificado_por                 = p_id_usuario_ejecutor
        WHERE id_usuario = p_id_usuario;
        SET v_id = p_id_usuario;
    END IF;

    -- ── Sedes autorizadas: se reemplazan por la lista recibida ───────────
    IF p_sedes_json IS NOT NULL AND p_sedes_json <> '' THEN
        DELETE FROM usuario_sede_autorizada WHERE id_usuario = v_id;

        INSERT IGNORE INTO usuario_sede_autorizada (id_usuario, id_sede_operativa, UsuCre, FchCre)
        SELECT v_id, j.id_sede, v_usu, NOW()
        FROM JSON_TABLE(p_sedes_json, '$[*]' COLUMNS (id_sede INT PATH '$')) AS j
        WHERE j.id_sede IS NOT NULL;
    END IF;

    COMMIT;

    SELECT 2 AS IdTipoMensaje,
           IF(p_id_usuario = 0, 'Usuario registrado correctamente.', 'Usuario actualizado correctamente.') AS Mensaje;
    SELECT v_id AS id_usuario;
END$$

DELIMITER ;
