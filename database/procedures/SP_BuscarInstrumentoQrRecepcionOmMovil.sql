-- ============================================================
-- SP_BuscarInstrumentoQrRecepcionOmMovil  (App Mobile HU-23 Recepción de instrumentos (OM) — «Escanear etiqueta del instrumento» · lectura)
-- Resuelve el texto leído por la cámara (QR, N/S, código del cliente o COD TW) al instrumento de ESTA OM. Mismas reglas de coincidencia que la búsqueda por QR de la HU-07 / el
-- registro fotográfico: coincidencia exacta (sin distinguir mayúsculas) con N/S, código del cliente o COD TW; o un texto más largo (una URL) que contenga el COD TW o el código del
-- cliente (de 5 o más caracteres); o una etiqueta QR de TW (SP_NormalizarQrMovil) ya vinculada a un equipo de la OM (equipo_qr). NO exige llegada: el instrumento está en el taller.
--   La OM debe ser del técnico (SP_ArmarOmTecnicoMovil). Si hay varios que coinciden se prefiere el que aún está pendiente.
--   Si el instrumento ya se recibió responde la regla de negocio indicando cuándo.
-- Resultados: 1 mensaje; 2 (id_os_equipo, nombre). Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_BuscarInstrumentoQrRecepcionOmMovil;

DELIMITER $$

CREATE PROCEDURE SP_BuscarInstrumentoQrRecepcionOmMovil(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT,
    IN p_texto      VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_existe   INT DEFAULT 0;
    DECLARE v_t        VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_clave    VARCHAR(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_oe       BIGINT DEFAULT NULL;
    DECLARE v_nombre   VARCHAR(320) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_recibido TINYINT DEFAULT 0;
    DECLARE v_cuando   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_os;
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_inst;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Orden de metrología no encontrada o no asignada a tu usuario.' AS Mensaje; LEAVE proc;
    END IF;
    SET v_t = UPPER(TRIM(IFNULL(p_texto, '')));
    IF v_t = '' OR CHAR_LENGTH(v_t) > 300 THEN
        SELECT 1 AS IdTipoMensaje, 'El código leído no es válido.' AS Mensaje; LEAVE proc;
    END IF;

    CALL SP_ArmarOmTecnicoMovil(p_id_usuario, p_id_os);
    SELECT COUNT(*) INTO v_existe FROM tmp_rom_os;
    IF v_existe = 0 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_os;
        SELECT 1 AS IdTipoMensaje, 'Orden de metrología no encontrada o no asignada a tu usuario.' AS Mensaje; LEAVE proc;
    END IF;
    CALL SP_ArmarInstrumentosRecepcionOmMovil();
    CALL SP_NormalizarQrMovil(p_texto, v_clave);

    SELECT i.id_os_equipo, CONCAT_WS(' ', i.nombre, i.marca, i.modelo), i.recibido,
           DATE_FORMAT(CONVERT_TZ(i.recibido_utc, '+00:00', '-05:00'), '%d/%m a las %H:%i')
    INTO   v_oe, v_nombre, v_recibido, v_cuando
    FROM   tmp_rom_inst i
    WHERE  UPPER(IFNULL(i.serie, '')) = v_t OR UPPER(IFNULL(i.codigo_cliente, '')) = v_t OR UPPER(IFNULL(i.codigo_tw, '')) = v_t
        OR (CHAR_LENGTH(IFNULL(i.codigo_tw, '')) >= 5 AND LOCATE(UPPER(i.codigo_tw), v_t) > 0)
        OR (CHAR_LENGTH(IFNULL(i.codigo_cliente, '')) >= 5 AND LOCATE(UPPER(i.codigo_cliente), v_t) > 0)
        OR (v_clave IS NOT NULL AND i.id_equipo IN (SELECT q.id_equipo FROM equipo_qr q WHERE q.clave = v_clave AND q.eliminado_en IS NULL))
    ORDER BY i.recibido, i.numero
    LIMIT 1;

    DROP TEMPORARY TABLE IF EXISTS tmp_rom_inst;
    DROP TEMPORARY TABLE IF EXISTS tmp_rom_os;

    IF v_oe IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'El código leído no corresponde a ningún instrumento de esta orden.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_recibido = 1 THEN
        SELECT 1 AS IdTipoMensaje, CONCAT(v_nombre, ' ya se recibió el ', v_cuando, '.') AS Mensaje; LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;
    SELECT v_oe AS id_os_equipo, v_nombre AS nombre;
END$$

DELIMITER ;
