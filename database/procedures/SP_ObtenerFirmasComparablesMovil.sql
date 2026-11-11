-- ============================================================
-- SP_ObtenerFirmasComparablesMovil  (App Mobile HU-17 — apoyo del caso de uso, solo lectura)
-- Lo que necesita el servicio de similitud antes de aceptar una firma por dispositivo: el umbral (FIRMA_SIMILITUD_MAXIMA_PCT, 90 por defecto) y las firmas
-- por dispositivo YA registradas en la misma OS por OTROS responsables (nombre y trazos). La comparación la hace el servicio .NET ComparadorFirmas.
-- Resultados: 1 mensaje · 2 umbral (1 fila) · 3 firmas de otros responsables.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerFirmasComparablesMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerFirmasComparablesMovil(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT,
    IN p_clave      VARCHAR(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_msg    VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_num    VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_umbral INT DEFAULT 90;

    CALL SP_ContextoFirmaMovil(p_id_usuario, p_id_os, v_msg, v_num);
    IF v_msg IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje;
        LEAVE proc;
    END IF;
    SELECT IFNULL(MAX(m.Num2), 90) INTO v_umbral
    FROM   tabla_maestra m WHERE m.Descripcion = 'PARAMETRO_PROGRAMACION' AND m.String2 = 'FIRMA_SIMILITUD_MAXIMA_PCT' AND m.eliminado_en IS NULL;
    IF v_umbral < 50 OR v_umbral > 100 THEN SET v_umbral = 90; END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;
    SELECT v_umbral AS umbral_pct;
    SELECT f.nombre AS nombre, CAST(f.trazos AS CHAR) AS trazos
    FROM   os_firma_responsable f
    WHERE  f.id_os = p_id_os AND f.clave <> IFNULL(p_clave, '') AND f.modo = 'dispositivo' AND f.trazos IS NOT NULL
    ORDER BY f.id_firma;
END$$

DELIMITER ;
