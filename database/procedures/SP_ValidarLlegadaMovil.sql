-- ============================================================
-- SP_ValidarLlegadaMovil  (App Mobile HU-06 — compara la ubicación con la de la planta; NO registra nada)
-- La app lo llama cada vez que captura una ubicación para pintar "Ubicación válida" / "Fuera del rango permitido" y habilitar o bloquear
-- "Confirmar llegada". La OS debe ser del técnico del token. La regla vive en SP_EvaluarLlegadaMovil; al confirmar, SP_RegistrarLlegadaMovil
-- vuelve a evaluar (la app nunca decide).
-- Resultados: 1 mensaje · 2 una fila (resultado, registrable, distancia_m, radio_m, precision_m, mensaje).
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ValidarLlegadaMovil;

DELIMITER $$

CREATE PROCEDURE SP_ValidarLlegadaMovil(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT,
    IN p_latitud    DECIMAL(10,7),
    IN p_longitud   DECIMAL(10,7),
    IN p_precision  DECIMAL(8,1)
)
proc: BEGIN
    DECLARE v_existe     TINYINT DEFAULT 0;
    DECLARE v_resultado  VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_registrable TINYINT;
    DECLARE v_distancia  INT;
    DECLARE v_radio      INT;
    DECLARE v_pmax       INT;
    DECLARE v_lat_ref    DECIMAL(10,7);
    DECLARE v_lon_ref    DECIMAL(10,7);
    DECLARE v_mensaje    VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    SELECT IF(COUNT(*) > 0, 1, 0) INTO v_existe
    FROM   orden_servicio os
    WHERE  os.id_os = p_id_os AND os.eliminado_en IS NULL
      AND  (os.id_tecnico_principal = p_id_usuario
            OR EXISTS (SELECT 1 FROM os_personal op
                       WHERE op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL));
    IF v_existe = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio no encontrado o no asignado a tu usuario.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF p_latitud IS NULL OR p_longitud IS NULL OR p_latitud NOT BETWEEN -90 AND 90 OR p_longitud NOT BETWEEN -180 AND 180
       OR (p_latitud = 0 AND p_longitud = 0) THEN
        SELECT 1 AS IdTipoMensaje, 'La ubicación GPS no es válida: activa el GPS e inténtalo de nuevo.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF p_precision IS NULL OR p_precision < 0 OR p_precision > 5000 THEN
        SELECT 1 AS IdTipoMensaje, 'La precisión del GPS no es válida.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_EvaluarLlegadaMovil(p_id_os, p_latitud, p_longitud, p_precision, v_resultado, v_registrable, v_distancia, v_radio, v_pmax,
                                v_lat_ref, v_lon_ref, v_mensaje);

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;
    SELECT v_resultado AS resultado, v_registrable AS registrable, v_distancia AS distancia_m, v_radio AS radio_m,
           p_precision AS precision_m, v_mensaje AS mensaje;
END$$

DELIMITER ;
