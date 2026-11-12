-- ============================================================
-- SP_RegistrarUbicacionJornadaMovil  (App Mobile HU-20 — posición GPS del técnico MIENTRAS LA JORNADA ESTÁ EN CURSO)
-- Igual que SP_RegistrarUbicacionMovil (HU-51) pero sin exigir un servicio en curso: basta que la jornada de hoy esté iniciada y no finalizada
-- (inicio de labores marcado, incluso en refrigerio o ya fuera de planta). Alimenta el mapa, la alerta «Sin movimiento» y «Pérdida de contacto».
-- Antirrebote: si ya hay una posición del técnico de hace menos de 10 s no se guarda otra (responde OK). Si tiene un servicio en curso, la posición
-- se guarda con ese servicio. Limpieza: máx. 500 posiciones de más de 3 días. Resultados: 1 mensaje · 2 Guardada.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_RegistrarUbicacionJornadaMovil;

DELIMITER $$

CREATE PROCEDURE SP_RegistrarUbicacionJornadaMovil(
    IN p_id_usuario BIGINT,
    IN p_latitud    DECIMAL(10,7),
    IN p_longitud   DECIMAL(10,7),
    IN p_precision  DECIMAL(8,1),
    IN p_velocidad  DECIMAL(6,1),
    IN p_altitud    DECIMAL(8,1)
)
proc: BEGIN
    DECLARE v_n         INT;
    DECLARE v_estado    VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_sig       VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_ult       DATETIME;
    DECLARE v_ultima    DATETIME;
    DECLARE v_os        BIGINT DEFAULT NULL;
    DECLARE v_guardada  TINYINT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no válido.' AS Mensaje; LEAVE proc;
    END IF;
    IF p_latitud IS NULL OR p_longitud IS NULL OR p_latitud NOT BETWEEN -90 AND 90 OR p_longitud NOT BETWEEN -180 AND 180
       OR (p_latitud = 0 AND p_longitud = 0) THEN
        SELECT 1 AS IdTipoMensaje, 'La ubicación no es válida.' AS Mensaje; LEAVE proc;
    END IF;
    IF p_precision IS NOT NULL AND (p_precision < 0 OR p_precision > 5000) THEN
        SELECT 1 AS IdTipoMensaje, 'La precisión de la ubicación no es válida.' AS Mensaje; LEAVE proc;
    END IF;

    CALL SP_EstadoJornadaMovil(p_id_usuario, DATE(CONVERT_TZ(UTC_TIMESTAMP(), '+00:00', '-05:00')), v_n, v_estado, v_sig, v_ult);
    IF v_n < 1 OR v_n > 4 THEN
        SELECT 1 AS IdTipoMensaje, 'La ubicación solo se registra con la jornada en curso.' AS Mensaje; LEAVE proc;
    END IF;

    SELECT MAX(timestamp_utc) INTO v_ultima FROM ubicacion_tecnico WHERE id_usuario = p_id_usuario;
    IF v_ultima IS NULL OR v_ultima < DATE_SUB(UTC_TIMESTAMP(), INTERVAL 10 SECOND) THEN
        SELECT os.id_os INTO v_os
        FROM orden_servicio os
        WHERE os.eliminado_en IS NULL AND os.estado IN ('en_ruta', 'en_ejecucion', 'pausada')
          AND (os.id_tecnico_principal = p_id_usuario
               OR EXISTS (SELECT 1 FROM os_personal op WHERE op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL))
        ORDER BY os.id_os DESC LIMIT 1;

        INSERT INTO ubicacion_tecnico (id_usuario, id_os, latitud, longitud, precision_m, velocidad_kmh, altitud_m, timestamp_utc)
        VALUES (p_id_usuario, v_os, p_latitud, p_longitud, IF(p_precision IS NULL, NULL, ROUND(p_precision)),
                IF(p_velocidad BETWEEN 0 AND 400, p_velocidad, NULL), IF(p_altitud BETWEEN -500 AND 9000, p_altitud, NULL), UTC_TIMESTAMP());
        SET v_guardada = 1;
        DELETE FROM ubicacion_tecnico WHERE id_usuario = p_id_usuario AND timestamp_utc < DATE_SUB(UTC_TIMESTAMP(), INTERVAL 3 DAY) LIMIT 500;
    END IF;

    SELECT 2 AS IdTipoMensaje, IF(v_guardada = 1, 'Ubicación registrada.', 'Ubicación reciente ya registrada.') AS Mensaje;
    SELECT v_guardada AS Guardada;
END$$

DELIMITER ;
