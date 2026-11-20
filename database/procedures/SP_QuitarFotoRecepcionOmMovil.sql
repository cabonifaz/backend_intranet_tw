-- ============================================================
-- SP_QuitarFotoRecepcionOmMovil  (App Mobile HU-23 Recepción de instrumentos (OM) — quita una foto de recepción aún NO registrada · escritura)
-- El técnico quita una de sus fotos pendientes de un instrumento (id_recepcion_equipo NULL): borrado lógico y las que quedan se renumeran 1..n. Una foto ya ligada a una
-- recepción registrada no se puede quitar. La OM debe ser del técnico (SP_ArmarOmTecnicoMovil).
-- Resultados: 1 mensaje; 2 (ruta = archivo de la foto, para que el back lo borre del almacén). Deja el archivo si el SP falla.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_QuitarFotoRecepcionOmMovil;

DELIMITER $$

CREATE PROCEDURE SP_QuitarFotoRecepcionOmMovil(
    IN p_id_usuario   BIGINT,
    IN p_id_os        BIGINT,
    IN p_id_os_equipo BIGINT,
    IN p_id_foto      BIGINT
)
proc: BEGIN
    DECLARE v_existe INT DEFAULT 0;
    DECLARE v_ruta   VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_os;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 OR IFNULL(p_id_os_equipo, 0) <= 0 OR IFNULL(p_id_foto, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Foto no encontrada.' AS Mensaje; LEAVE proc;
    END IF;

    START TRANSACTION;

    CALL SP_ArmarOmTecnicoMovil(p_id_usuario, p_id_os);
    SELECT COUNT(*) INTO v_existe FROM tmp_rom_os;
    DROP TEMPORARY TABLE IF EXISTS tmp_rom_os;
    IF v_existe = 0 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Orden de metrología no encontrada o no asignada a tu usuario.' AS Mensaje; LEAVE proc;
    END IF;

    SELECT f.ruta INTO v_ruta
    FROM   om_recepcion_foto f
    JOIN   os_equipo oe ON oe.id = f.id_os_equipo AND oe.id_os = p_id_os AND oe.eliminado_en IS NULL
    WHERE  f.id_foto = p_id_foto AND f.id_os_equipo = p_id_os_equipo AND f.id_usuario = p_id_usuario
      AND  f.id_recepcion_equipo IS NULL AND f.eliminado_en IS NULL
    FOR UPDATE;
    IF v_ruta IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'La foto no existe o ya forma parte de una recepción registrada.' AS Mensaje; LEAVE proc;
    END IF;

    UPDATE om_recepcion_foto SET eliminado_en = NOW() WHERE id_foto = p_id_foto;

    -- Las que quedan se renumeran 1..n (el n.º de foto es siempre el de la lista)
    UPDATE om_recepcion_foto f
    JOIN  (SELECT x.id_foto, ROW_NUMBER() OVER (ORDER BY x.orden, x.id_foto) AS rn
           FROM   om_recepcion_foto x
           WHERE  x.id_os_equipo = p_id_os_equipo AND x.id_usuario = p_id_usuario AND x.id_recepcion_equipo IS NULL AND x.eliminado_en IS NULL) n ON n.id_foto = f.id_foto
    SET    f.orden = n.rn;

    COMMIT;

    SELECT 2 AS IdTipoMensaje, 'Foto quitada.' AS Mensaje;
    SELECT v_ruta AS ruta;
END$$

DELIMITER ;
