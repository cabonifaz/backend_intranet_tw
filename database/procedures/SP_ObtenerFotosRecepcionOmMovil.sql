-- ============================================================
-- SP_ObtenerFotosRecepcionOmMovil  (App Mobile HU-23 Recepción de instrumentos (OM) — fotos pendientes de un instrumento · lectura)
-- Las fotos de recepción que el técnico del token ya subió para un instrumento y que aún NO están ligadas a una recepción registrada (para reanudar si cerró la pantalla a medias).
-- La OM debe ser del técnico (SP_ArmarOmTecnicoMovil) y el instrumento de esa OM.
-- Resultados: 1 mensaje · 2 (id_foto, orden) de la 1 a la 8. Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerFotosRecepcionOmMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerFotosRecepcionOmMovil(
    IN p_id_usuario   BIGINT,
    IN p_id_os        BIGINT,
    IN p_id_os_equipo BIGINT
)
proc: BEGIN
    DECLARE v_existe INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_os;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 OR IFNULL(p_id_os_equipo, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Instrumento no encontrado.' AS Mensaje; LEAVE proc;
    END IF;

    CALL SP_ArmarOmTecnicoMovil(p_id_usuario, p_id_os);
    SELECT COUNT(*) INTO v_existe FROM tmp_rom_os;
    DROP TEMPORARY TABLE IF EXISTS tmp_rom_os;
    IF v_existe = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Orden de metrología no encontrada o no asignada a tu usuario.' AS Mensaje; LEAVE proc;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM os_equipo oe WHERE oe.id = p_id_os_equipo AND oe.id_os = p_id_os AND oe.eliminado_en IS NULL) THEN
        SELECT 1 AS IdTipoMensaje, 'El instrumento no pertenece a esta orden.' AS Mensaje; LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT f.id_foto, f.orden
    FROM   om_recepcion_foto f
    WHERE  f.id_os_equipo = p_id_os_equipo AND f.id_usuario = p_id_usuario AND f.id_recepcion_equipo IS NULL AND f.eliminado_en IS NULL
    ORDER BY f.orden, f.id_foto
    LIMIT 8;
END$$

DELIMITER ;
