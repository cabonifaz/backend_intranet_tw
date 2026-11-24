-- ============================================================
-- SP_ObtenerArchivoFotoInformeComplementario  (Revisión Técnica — ruta del archivo de una foto o video del Informe Complementario · lectura)
-- Acceso: el mismo de SP_ObtenerInformeComplementario (rt_bandeja con el original en su alcance, o precot_ver con la precotización del
-- complementario en su alcance del CRM). Las del QR no tienen archivo.
-- Resultados: 1 mensaje; 2 (ruta, ruta_cuadro, es_video).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerArchivoFotoInformeComplementario;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerArchivoFotoInformeComplementario(
    IN p_id_usuario        BIGINT,
    IN p_id_complementario BIGINT,
    IN p_id_evidencia      BIGINT
)
proc: BEGIN
    DECLARE v_msg       VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_padre     BIGINT;
    DECLARE v_estado    VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_est_padre VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_editable  TINYINT;
    DECLARE v_n         INT DEFAULT 0;
    DECLARE v_ruta      VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_cuadro    VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_video     TINYINT DEFAULT 0;

    CALL SP_ContextoInformeComplementario(p_id_usuario, p_id_complementario, 'rt_bandeja', v_msg, v_padre, v_estado, v_est_padre, v_editable);
    -- Comercial: la precotización del complementario en su alcance
    IF v_msg IS NOT NULL AND FN_PermisoAccion(p_id_usuario, 'precot_ver') = 1 THEN
        CALL SP_ArmarBasePrecotizaciones(p_id_usuario, NULL);
        SELECT COUNT(*) INTO v_n FROM tmp_pct_base WHERE id_informe = p_id_complementario;
        DROP TEMPORARY TABLE IF EXISTS tmp_pct_base;
        IF v_n > 0 THEN SET v_msg = NULL; END IF;
    END IF;
    IF v_msg IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Foto no encontrada.' AS Mensaje; LEAVE proc;
    END IF;

    SELECT f.url_archivo, f.ruta_cuadro, f.es_video INTO v_ruta, v_cuadro, v_video
    FROM evidencia_fotografica f
    WHERE f.id_evidencia = p_id_evidencia AND f.id_informe = p_id_complementario AND f.eliminado_en IS NULL AND f.url_archivo NOT LIKE 'qr://%'
    LIMIT 1;

    IF v_ruta IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Foto no encontrada.' AS Mensaje;
    ELSE
        SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;
        SELECT v_ruta AS ruta, v_cuadro AS ruta_cuadro, v_video AS es_video;
    END IF;
END$$

DELIMITER ;
