-- HU-51 (Sprint 5) / App Mobile: registra la posición GPS del técnico mientras su servicio está en curso. Alimenta la bandeja de seguimiento
-- (ubicacion_tecnico): última ubicación "hace X min", Pérdida de contacto, GPS parado y Proximidad.
-- Reglas: la OS debe ser del técnico del token (principal o personal) y estar en ruta, en ejecución o en pausa; coordenadas dentro de rango y
-- distintas de (0,0); precisión 0 a 5000 m. Antirrebote: si ya hay una posición del técnico de hace menos de 10 s no se guarda otra (responde OK).
-- Limpieza: al guardar se borran (máx. 500) las posiciones de ese técnico con más de 3 días. NO cambia el estado de la OS.
-- Opcionales (los envía la app; un valor fuera de rango se guarda como NULL, no rechaza la posición): velocidad (km/h) y altitud (m).
DROP PROCEDURE IF EXISTS SP_RegistrarUbicacionMovil;

DELIMITER $$

CREATE PROCEDURE SP_RegistrarUbicacionMovil(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT,
    IN p_latitud    DECIMAL(10,7),
    IN p_longitud   DECIMAL(10,7),
    IN p_precision  DECIMAL(8,1),
    IN p_velocidad  DECIMAL(6,1),
    IN p_altitud    DECIMAL(8,1)
)
proc: BEGIN
    DECLARE v_estado  VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_ultima  DATETIME;
    DECLARE v_guardada TINYINT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio no encontrado o no asignado a tu usuario.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF p_latitud IS NULL OR p_longitud IS NULL OR p_latitud NOT BETWEEN -90 AND 90 OR p_longitud NOT BETWEEN -180 AND 180
       OR (p_latitud = 0 AND p_longitud = 0) THEN
        SELECT 1 AS IdTipoMensaje, 'La ubicación no es válida.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF p_precision IS NOT NULL AND (p_precision < 0 OR p_precision > 5000) THEN
        SELECT 1 AS IdTipoMensaje, 'La precisión de la ubicación no es válida.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT os.estado INTO v_estado
    FROM orden_servicio os
    WHERE os.id_os = p_id_os AND os.eliminado_en IS NULL
      AND (os.id_tecnico_principal = p_id_usuario
           OR EXISTS (SELECT 1 FROM os_personal op WHERE op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL));
    IF v_estado IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio no encontrado o no asignado a tu usuario.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_estado NOT IN ('en_ruta', 'en_ejecucion', 'pausada') THEN
        SELECT 1 AS IdTipoMensaje, 'La ubicación solo se registra mientras el servicio está en curso.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT MAX(timestamp_utc) INTO v_ultima FROM ubicacion_tecnico WHERE id_usuario = p_id_usuario;
    IF v_ultima IS NULL OR v_ultima < DATE_SUB(UTC_TIMESTAMP(), INTERVAL 10 SECOND) THEN
        INSERT INTO ubicacion_tecnico (id_usuario, id_os, latitud, longitud, precision_m, velocidad_kmh, altitud_m, timestamp_utc)
        VALUES (p_id_usuario, p_id_os, p_latitud, p_longitud, IF(p_precision IS NULL, NULL, ROUND(p_precision)),
                IF(p_velocidad BETWEEN 0 AND 400, p_velocidad, NULL), IF(p_altitud BETWEEN -500 AND 9000, p_altitud, NULL), UTC_TIMESTAMP());
        SET v_guardada = 1;
        DELETE FROM ubicacion_tecnico WHERE id_usuario = p_id_usuario AND timestamp_utc < DATE_SUB(UTC_TIMESTAMP(), INTERVAL 3 DAY) LIMIT 500;
    END IF;

    SELECT 2 AS IdTipoMensaje, IF(v_guardada = 1, 'Ubicación registrada.', 'Ubicación reciente ya registrada.') AS Mensaje;
    SELECT v_guardada AS Guardada;
END$$

DELIMITER ;
