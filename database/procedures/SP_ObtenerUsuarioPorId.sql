-- HU-83 — Ficha de usuario: detalle + sedes autorizadas
DROP PROCEDURE IF EXISTS SP_ObtenerUsuarioPorId;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerUsuarioPorId(
    IN p_id_usuario BIGINT
)
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM usuario
        WHERE id_usuario = p_id_usuario AND eliminado_en IS NULL
    ) THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no encontrado.' AS Mensaje;
    ELSE
        -- 1. Header
        SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

        -- 2. Datos del usuario
        SELECT
            u.id_usuario,
            u.nombre,
            u.apellido,
            u.correo,
            u.rol_sistema,
            COALESCE(tm_rol.String1, u.rol_sistema) AS rol_sistema_label,
            u.area_comercial,
            u.telefono,
            CASE u.estado
                WHEN 'activo'     THEN 'Activo'
                WHEN 'inactivo'   THEN 'Inactivo'
                WHEN 'suspendido' THEN 'Suspendido'
                WHEN 'borrador'   THEN 'Borrador'
                ELSE u.estado
            END                                     AS estado,
            u.ultimo_login                          AS ultimo_acceso,
            u.creado_en                             AS fecha_creacion,
            u.tipo_documento,
            u.numero_documento,
            u.cargo,
            u.base_operativa,
            u.id_supervisor,
            u.habilitado_firma_inacal,
            u.numero_registro_inacal,
            u.fecha_expiracion_certificacion,
            u.requiere_induccion_sctr,
            u.forzar_cambio_contrasena,
            u.enviar_credenciales_correo,
            u.autenticacion_2fa
        FROM usuario u
        LEFT JOIN tabla_maestra tm_rol
               ON tm_rol.IdMaestro = 68
              AND tm_rol.IdEmpresa = 1
              AND tm_rol.String2   = u.rol_sistema
        WHERE u.id_usuario = p_id_usuario;

        -- 3. Sedes autorizadas
        SELECT id_sede_operativa
        FROM usuario_sede_autorizada
        WHERE id_usuario = p_id_usuario
        ORDER BY id_sede_operativa;
    END IF;
END$$

DELIMITER ;
