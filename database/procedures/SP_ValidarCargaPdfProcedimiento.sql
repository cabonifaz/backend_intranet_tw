-- Carga del PDF aprobado de Procedimientos (HU-87)
--   Indica si el usuario puede cargar o reemplazar el PDF.
--   Usa el sistema de permisos por acción (#4301): FN_PermisoAccion con la acción
--   procedimiento_pdf_cargar (módulo calidad). Por defecto área Calidad y administradores.
--   Con p_id_procedimiento = 0 solo evalúa el permiso (formulario de nuevo registro).
--   Con un id, además valida que el procedimiento exista y no esté inactivo.
DROP PROCEDURE IF EXISTS SP_ValidarCargaPdfProcedimiento;

DELIMITER $$

CREATE PROCEDURE SP_ValidarCargaPdfProcedimiento(
    IN p_id_procedimiento BIGINT,
    IN p_id_usuario       BIGINT
)
proc: BEGIN
    DECLARE v_estado    VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_permitido TINYINT DEFAULT 0;
    DECLARE v_motivo    VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;

    IF IFNULL(p_id_procedimiento, 0) > 0 THEN
        SELECT estado INTO v_estado
        FROM procedimiento_metrologico
        WHERE id_procedimiento = p_id_procedimiento AND SoftDelete = 0;

        IF v_estado IS NULL THEN
            SELECT 1 AS IdTipoMensaje, 'Procedimiento no encontrado.' AS Mensaje;
            LEAVE proc;
        END IF;
    END IF;

    SET v_permitido = FN_PermisoAccion(p_id_usuario, 'procedimiento_pdf_cargar');
    IF v_permitido = 0 THEN
        SET v_motivo = 'No tiene permiso para cargar el PDF aprobado. Solo el área de Calidad o un administrador.';
    END IF;

    IF v_permitido = 1 AND v_estado = 'inactivo' THEN
        SET v_permitido = 0;
        SET v_motivo = 'El procedimiento está inactivo. Actívelo antes de cargar el PDF.';
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;
    SELECT v_permitido AS puede_subir_pdf, v_motivo AS motivo;
END$$

DELIMITER ;
