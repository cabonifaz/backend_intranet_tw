-- ============================================================
-- SP_ObtenerSalidaHabilitadaMovil  (App Mobile HU-04 — apoyo, no es un endpoint)
-- Regla única: la salida (validar el checklist, pedir autorización e iniciar el traslado) solo se
-- habilita desde el DÍA programado de la OS. Antes, el técnico puede ver el detalle pero no validar la salida.
--   p_habilitada: 1 = hoy (o antes) es la fecha de ejecución, o la OS no tiene fecha; 0 = aún no es el día.
--   p_mensaje   : NULL si está habilitada; si no, "Aún no es el día del servicio. Podrás validar la salida el dd/mm/aaaa."
-- "Hoy" es la fecha de Lima (UTC-5, sin horario de verano), calculada desde UTC para no depender de la zona del servidor.
-- Lo usan SP_ObtenerChecklistSalidaMovil (lo informa a la app) y los SP que modifican (Marcar, Solicitar, IniciarTraslado).
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerSalidaHabilitadaMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerSalidaHabilitadaMovil(
    IN  p_id_os      BIGINT,
    OUT p_habilitada TINYINT,
    OUT p_mensaje    VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
BEGIN
    DECLARE v_fecha DATE DEFAULT NULL;
    DECLARE v_hoy   DATE;

    SET v_hoy = DATE(UTC_TIMESTAMP() - INTERVAL 5 HOUR);

    SELECT DATE(os.fecha_ejecucion) INTO v_fecha
    FROM   orden_servicio os
    WHERE  os.id_os = p_id_os AND os.eliminado_en IS NULL;

    IF v_fecha IS NOT NULL AND v_fecha > v_hoy THEN
        SET p_habilitada = 0;
        SET p_mensaje    = CONCAT('Aún no es el día del servicio. Podrás validar la salida el ', DATE_FORMAT(v_fecha, '%d/%m/%Y'), '.');
    ELSE
        SET p_habilitada = 1;
        SET p_mensaje    = NULL;
    END IF;
END$$

DELIMITER ;
