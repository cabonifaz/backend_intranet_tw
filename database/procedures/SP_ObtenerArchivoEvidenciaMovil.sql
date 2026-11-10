-- ============================================================
-- SP_ObtenerArchivoEvidenciaMovil  (App Mobile HU-11 — ruta del archivo de una evidencia para mostrarla · lectura)
-- Devuelve dónde está guardada una evidencia (foto, video o cuadro) SOLO si la OS es del técnico del token y la evidencia es de esa OS y ese equipo
-- (misma respuesta si no existe o no es suya). No exige llegada: el técnico puede ver lo que ya capturó.
-- Resultados: 1 mensaje; 2 (ruta, ruta_cuadro, es_video). Las evidencias del QR no tienen archivo.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerArchivoEvidenciaMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerArchivoEvidenciaMovil(
    IN p_id_usuario   BIGINT,
    IN p_id_os        BIGINT,
    IN p_id_os_equipo BIGINT,
    IN p_id_evidencia BIGINT
)
BEGIN
    DECLARE v_ruta   VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_cuadro VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_video  TINYINT DEFAULT 0;

    SELECT f.url_archivo, f.ruta_cuadro, f.es_video INTO v_ruta, v_cuadro, v_video
    FROM   evidencia_fotografica f
    JOIN   os_equipo oe ON oe.id = p_id_os_equipo AND oe.id_os = f.id_os AND oe.id_equipo = f.id_equipo AND oe.eliminado_en IS NULL
    JOIN   orden_servicio os ON os.id_os = f.id_os AND os.eliminado_en IS NULL
    WHERE  f.id_evidencia = p_id_evidencia AND f.id_os = p_id_os AND f.eliminado_en IS NULL
      AND  f.url_archivo NOT LIKE 'qr://%'
      AND  (os.id_tecnico_principal = p_id_usuario
            OR EXISTS (SELECT 1 FROM os_personal op WHERE op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL));

    IF v_ruta IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Evidencia no encontrada.' AS Mensaje;
    ELSE
        SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;
        SELECT v_ruta AS ruta, v_cuadro AS ruta_cuadro, v_video AS es_video;
    END IF;
END$$

DELIMITER ;
