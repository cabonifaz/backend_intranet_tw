-- ============================================================
-- SP_ObtenerArchivoEvidenciaInformeMovil  (App Mobile HU-33 — ruta del archivo de una evidencia del informe, para verla en la app · lectura)
-- Acceso: rt_bandeja + alcance de la app (regla ÁREA + ROL: SP_FijarAlcanceInformesMovil → SP_ArmarBaseInformes). La evidencia debe ser del informe (id_informe) o, si no tiene
-- informe asignado, de la misma OS y equipo (la misma regla de SP_ObtenerInformeRevisionMovil y del detalle de la intranet). Las lecturas del QR no tienen archivo.
-- Resultados: 1 mensaje · 2 (ruta, ruta_cuadro = miniatura del video, es_video).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerArchivoEvidenciaInformeMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerArchivoEvidenciaInformeMovil(
    IN p_id_usuario   BIGINT,
    IN p_id_informe   BIGINT,
    IN p_id_evidencia BIGINT
)
proc: BEGIN
    DECLARE v_tiene  TINYINT DEFAULT 0;
    DECLARE v_ruta   VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_cuadro VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_video  TINYINT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SET @tw_inf_usuario = NULL, @tw_inf_ver_todo = NULL, @tw_inf_area = NULL;
        DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF FN_PermisoAccion(p_id_usuario, 'rt_bandeja') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver la revisión de informes técnicos.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF IFNULL(p_id_informe, 0) <= 0 OR IFNULL(p_id_evidencia, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Foto no encontrada.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_FijarAlcanceInformesMovil(p_id_usuario, v_tiene);
    IF v_tiene = 0 THEN
        SET @tw_inf_usuario = NULL, @tw_inf_ver_todo = NULL, @tw_inf_area = NULL;
        SELECT 1 AS IdTipoMensaje, 'Tu cargo no tiene el menú de Jefatura.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_ArmarBaseInformes(p_id_usuario, p_id_informe);
    SET @tw_inf_usuario = NULL, @tw_inf_ver_todo = NULL, @tw_inf_area = NULL;

    SELECT f.url_archivo, f.ruta_cuadro, f.es_video INTO v_ruta, v_cuadro, v_video
    FROM   evidencia_fotografica f
    JOIN   tmp_rt_base b ON b.id_informe = p_id_informe
    WHERE  f.id_evidencia = p_id_evidencia AND f.eliminado_en IS NULL AND f.url_archivo NOT LIKE 'qr://%' AND IFNULL(f.vigente, 1) = 1
      AND  (f.id_informe = p_id_informe
            OR (f.id_informe IS NULL AND f.id_os = b.id_os AND (f.id_equipo = b.id_equipo OR f.id_equipo IS NULL)))
    LIMIT 1;

    DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;

    IF v_ruta IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Foto no encontrada.' AS Mensaje;
    ELSE
        SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;
        SELECT v_ruta AS ruta, v_cuadro AS ruta_cuadro, v_video AS es_video;
    END IF;
END$$

DELIMITER ;
