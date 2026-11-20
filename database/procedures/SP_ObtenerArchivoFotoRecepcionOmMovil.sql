-- ============================================================
-- SP_ObtenerArchivoFotoRecepcionOmMovil  (App Mobile HU-23 Recepción de instrumentos (OM) — ruta del archivo de una foto de recepción · lectura)
-- Devuelve la ruta de una foto SOLO si la OM del instrumento es del técnico (SP_ArmarOmTecnicoMovil) y, además:
--   · la foto aún no está registrada y es del propio técnico, o
--   · la foto ya forma parte de una recepción registrada de esa OM (la puede ver cualquier técnico asignado a la OM).
-- Misma respuesta si no existe o no es suya.
-- Resultados: 1 mensaje; 2 (ruta). Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerArchivoFotoRecepcionOmMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerArchivoFotoRecepcionOmMovil(
    IN p_id_usuario BIGINT,
    IN p_id_foto    BIGINT
)
proc: BEGIN
    DECLARE v_os        BIGINT DEFAULT NULL;
    DECLARE v_ruta      VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_dueno     BIGINT DEFAULT NULL;
    DECLARE v_pendiente TINYINT DEFAULT 0;
    DECLARE v_existe    INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_os;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_foto, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Foto no encontrada.' AS Mensaje; LEAVE proc;
    END IF;

    SELECT oe.id_os, f.ruta, f.id_usuario, IF(f.id_recepcion_equipo IS NULL, 1, 0) INTO v_os, v_ruta, v_dueno, v_pendiente
    FROM   om_recepcion_foto f
    JOIN   os_equipo oe ON oe.id = f.id_os_equipo AND oe.eliminado_en IS NULL
    WHERE  f.id_foto = p_id_foto AND f.eliminado_en IS NULL;

    IF v_os IS NOT NULL THEN
        CALL SP_ArmarOmTecnicoMovil(p_id_usuario, v_os);
        SELECT COUNT(*) INTO v_existe FROM tmp_rom_os;
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_os;
    END IF;

    IF v_os IS NULL OR v_existe = 0 OR (v_pendiente = 1 AND v_dueno <> p_id_usuario) THEN
        SELECT 1 AS IdTipoMensaje, 'Foto no encontrada.' AS Mensaje; LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;
    SELECT v_ruta AS ruta;
END$$

DELIMITER ;
