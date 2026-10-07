-- Carga del PDF aprobado de Procedimientos (HU-87)
--   Ruta interna y nombre original del PDF para descargarlo o verlo.
DROP PROCEDURE IF EXISTS SP_ObtenerPdfProcedimiento;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerPdfProcedimiento(
    IN p_id_procedimiento BIGINT
)
proc: BEGIN
    DECLARE v_ruta   VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_nombre VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_existe TINYINT DEFAULT 0;

    SELECT 1, url_pdf_aprobado, pdf_nombre_original
      INTO v_existe, v_ruta, v_nombre
    FROM procedimiento_metrologico
    WHERE id_procedimiento = p_id_procedimiento AND SoftDelete = 0;

    IF v_existe = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Procedimiento no encontrado.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF v_ruta IS NULL OR v_ruta = '' THEN
        SELECT 1 AS IdTipoMensaje, 'El procedimiento aún no tiene un PDF aprobado cargado.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;
    SELECT v_ruta AS ruta, IFNULL(v_nombre, 'procedimiento.pdf') AS nombre_archivo;
END$$

DELIMITER ;
