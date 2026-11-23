-- ============================================================
-- SP_RegistrarFotoRecepcionOmMovil  (App Mobile HU-23 Recepción de instrumentos (OM) — guarda una foto de recepción (solo cámara) · escritura)
-- El técnico sube una foto de un instrumento ANTES de registrar la recepción. Queda «pendiente» (id_recepcion_equipo NULL) y se liga al registrar la recepción.
--   - La OM debe ser del técnico y estar activa (SP_ArmarOmTecnicoMovil); el instrumento debe ser de esa OM y seguir pendiente de recibir (SP_ArmarInstrumentosRecepcionOmMovil).
--   - Máximo 8 fotos pendientes por instrumento y por técnico. Sin IA.
--   - p_ruta: ruta ya guardada por el back en el almacén (recepcion-om/{idOs}/{idOsEquipo}/….jpg).
-- Resultados: 1 mensaje; 2 (id_foto, orden = n.º de fotos pendientes del instrumento, 1..8).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_RegistrarFotoRecepcionOmMovil;

DELIMITER $$

CREATE PROCEDURE SP_RegistrarFotoRecepcionOmMovil(
    IN p_id_usuario   BIGINT,
    IN p_id_os        BIGINT,
    IN p_id_os_equipo BIGINT,
    IN p_ruta         VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_existe   INT DEFAULT 0;
    DECLARE v_activa   TINYINT DEFAULT 0;
    DECLARE v_oe       BIGINT DEFAULT NULL;
    DECLARE v_recibido TINYINT DEFAULT 0;
    DECLARE v_nombre   VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_n        INT DEFAULT 0;
    DECLARE v_id       BIGINT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_os;
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_inst;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 OR IFNULL(p_id_os_equipo, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Instrumento no encontrado.' AS Mensaje; LEAVE proc;
    END IF;
    IF NULLIF(TRIM(IFNULL(p_ruta, '')), '') IS NULL OR CHAR_LENGTH(p_ruta) > 500 THEN
        SELECT 1 AS IdTipoMensaje, 'Falta la foto.' AS Mensaje; LEAVE proc;
    END IF;

    START TRANSACTION;

    CALL SP_ArmarOmTecnicoMovil(p_id_usuario, p_id_os);
    SELECT COUNT(*), IFNULL(MAX(o.activa), 0) INTO v_existe, v_activa FROM tmp_rom_os o;
    IF v_existe = 0 THEN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_os;
        SELECT 1 AS IdTipoMensaje, 'Orden de metrología no encontrada o no asignada a tu usuario.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_activa = 0 THEN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_os;
        SELECT 1 AS IdTipoMensaje, 'La orden ya no está activa: no se pueden registrar fotos de recepción.' AS Mensaje; LEAVE proc;
    END IF;

    -- Se bloquea el instrumento: dos subidas a la vez no pasan del tope de 8
    SELECT oe.id INTO v_oe FROM os_equipo oe WHERE oe.id = p_id_os_equipo AND oe.id_os = p_id_os AND oe.eliminado_en IS NULL FOR UPDATE;
    IF v_oe IS NULL THEN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_os;
        SELECT 1 AS IdTipoMensaje, 'El instrumento no pertenece a esta orden.' AS Mensaje; LEAVE proc;
    END IF;

    CALL SP_ArmarInstrumentosRecepcionOmMovil();
    SELECT i.recibido, CONCAT_WS(' ', i.nombre, i.marca, i.modelo) INTO v_recibido, v_nombre FROM tmp_rom_inst i WHERE i.id_os_equipo = p_id_os_equipo;
    DROP TEMPORARY TABLE IF EXISTS tmp_rom_inst;
    DROP TEMPORARY TABLE IF EXISTS tmp_rom_os;
    IF v_recibido = 1 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, CONCAT(IFNULL(v_nombre, 'El instrumento'), ' ya se recibió: no admite más fotos de recepción.') AS Mensaje; LEAVE proc;
    END IF;

    SELECT COUNT(*) INTO v_n
    FROM   om_recepcion_foto f
    WHERE  f.id_os_equipo = p_id_os_equipo AND f.id_usuario = p_id_usuario AND f.id_recepcion_equipo IS NULL AND f.eliminado_en IS NULL;
    IF v_n >= 8 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Un instrumento admite hasta 8 fotos de recepción. Quita alguna para tomar otra.' AS Mensaje; LEAVE proc;
    END IF;

    INSERT INTO om_recepcion_foto (id_os_equipo, id_usuario, orden, ruta) VALUES (p_id_os_equipo, p_id_usuario, v_n + 1, TRIM(p_ruta));
    SET v_id = LAST_INSERT_ID();

    COMMIT;

    SELECT 2 AS IdTipoMensaje, 'Foto guardada.' AS Mensaje;
    SELECT v_id AS id_foto, v_n + 1 AS orden;
END$$

DELIMITER ;
