-- ============================================================
-- SP_GuardarSede  (Maestros › Clientes › Sedes · crear/editar)
-- p_id_sede = 0 crea; > 0 edita. Ubicación exacta de la planta (sede_cliente.latitud/longitud, migración 110): la usan la llegada validada por
-- GPS (SP_EvaluarLlegadaMovil), el mapa, la distancia y la ETA del seguimiento.
--   Ubicación: van las dos o ninguna; dentro del recuadro de Perú (latitud -18.5..-0.5, longitud -82..-68). Al EDITAR, si no llegan (NULL) se conserva la que había
--   (el front viejo no las envía y no debe borrarlas); para quitarla, p_quitar_ubicacion = 1.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_GuardarSede;

DELIMITER //
CREATE PROCEDURE SP_GuardarSede(
    IN p_id_sede          BIGINT,
    IN p_id_cliente       BIGINT,
    IN p_nombre           VARCHAR(200),
    IN p_tipo_instalacion VARCHAR(100),
    IN p_region           VARCHAR(100),
    IN p_provincia        VARCHAR(100),
    IN p_distrito         VARCHAR(100),
    IN p_urbanizacion     VARCHAR(200),
    IN p_direccion_exacta VARCHAR(500),
    IN p_latitud          DECIMAL(10,7),
    IN p_longitud         DECIMAL(10,7),
    IN p_quitar_ubicacion TINYINT,
    IN p_usu_cre          VARCHAR(100)
)
proc: BEGIN
    IF (p_latitud IS NULL) <> (p_longitud IS NULL) THEN
        SELECT 1 AS IdTipoMensaje, 'Envía la latitud y la longitud de la sede juntas.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF p_latitud IS NOT NULL AND (p_latitud NOT BETWEEN -18.5 AND -0.5 OR p_longitud NOT BETWEEN -82 AND -68) THEN
        SELECT 1 AS IdTipoMensaje, 'La ubicación debe estar dentro del Perú.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF p_id_sede = 0 THEN
        -- Nueva sede
        INSERT INTO sede_cliente (
            id_cliente, nombre, tipo_instalacion, region, provincia,
            distrito, urbanizacion, direccion_exacta, latitud, longitud, estado, UsuCre, FchCre
        ) VALUES (
            p_id_cliente, p_nombre, p_tipo_instalacion, p_region, p_provincia,
            p_distrito, p_urbanizacion, p_direccion_exacta, p_latitud, p_longitud, 'Activo', p_usu_cre, NOW()
        );

        SELECT 2 AS IdTipoMensaje, 'Sede registrada correctamente.' AS Mensaje;
        SELECT LAST_INSERT_ID() AS id_sede;
    ELSE
        -- Editar sede existente
        IF NOT EXISTS (SELECT 1 FROM sede_cliente WHERE id_sede = p_id_sede AND SoftDelete = 0) THEN
            SELECT 1 AS IdTipoMensaje, 'Sede no encontrada.' AS Mensaje;
        ELSE
            UPDATE sede_cliente
            SET nombre           = p_nombre,
                tipo_instalacion = p_tipo_instalacion,
                region           = p_region,
                provincia        = p_provincia,
                distrito         = p_distrito,
                urbanizacion     = p_urbanizacion,
                direccion_exacta = p_direccion_exacta,
                latitud          = IF(IFNULL(p_quitar_ubicacion, 0) = 1, NULL, COALESCE(p_latitud, latitud)),
                longitud         = IF(IFNULL(p_quitar_ubicacion, 0) = 1, NULL, COALESCE(p_longitud, longitud)),
                UsuMod           = p_usu_cre,
                FchMod           = NOW()
            WHERE id_sede = p_id_sede AND SoftDelete = 0;

            SELECT 2 AS IdTipoMensaje, 'Sede actualizada correctamente.' AS Mensaje;
            SELECT p_id_sede AS id_sede;
        END IF;
    END IF;
END //
DELIMITER ;
