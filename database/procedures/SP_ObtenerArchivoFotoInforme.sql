-- ============================================================
-- SP_ObtenerArchivoFotoInforme  (Revisión Técnica HU-57 — ruta del archivo de una foto del informe, para mostrar la vista previa · lectura)
-- Acceso: rt_bandeja y el informe dentro del alcance del usuario (SP_ArmarBaseInformes). La evidencia debe ser del informe (id_informe) o, si no tiene informe asignado,
-- de la misma OS y equipo (la misma regla de SP_ObtenerDetalleInformeTecnico). Las del QR no tienen archivo.
-- Resultados: 1 mensaje; 2 (ruta, ruta_cuadro, es_video).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerArchivoFotoInforme;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerArchivoFotoInforme(
    IN p_id_usuario   BIGINT,
    IN p_id_informe   BIGINT,
    IN p_id_evidencia BIGINT
)
proc: BEGIN
    DECLARE v_ruta   VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_cuadro VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_video  TINYINT DEFAULT 0;

    IF FN_PermisoAccion(p_id_usuario, 'rt_bandeja') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver la revisión de informes técnicos.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_ArmarBaseInformes(p_id_usuario, IFNULL(p_id_informe, 0));

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
