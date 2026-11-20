-- ============================================================
-- SP_GuardarConstanciaRecepcionOmMovil  (App Mobile HU-23 Recepción de instrumentos (OM) — guarda la ruta del PDF de la constancia y si se envió por correo · escritura)
-- El back genera el PDF al registrar la recepción (o lo vuelve a generar si el archivo ya no está) y guarda aquí su ruta en el almacén y si se envió al contacto del cliente.
-- La OM de la recepción debe ser del técnico (SP_ArmarOmTecnicoMovil).
-- Resultados: 1 mensaje; 2 (ruta_anterior = el PDF que reemplaza, para que el back lo borre del almacén; NULL si no había).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_GuardarConstanciaRecepcionOmMovil;

DELIMITER $$

CREATE PROCEDURE SP_GuardarConstanciaRecepcionOmMovil(
    IN p_id_usuario     BIGINT,
    IN p_id_recepcion   BIGINT,
    IN p_ruta           VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_correo_enviado TINYINT
)
proc: BEGIN
    DECLARE v_os       BIGINT DEFAULT NULL;
    DECLARE v_anterior VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_existe   INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_os;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_recepcion, 0) <= 0 OR NULLIF(TRIM(IFNULL(p_ruta, '')), '') IS NULL OR CHAR_LENGTH(p_ruta) > 500 THEN
        SELECT 1 AS IdTipoMensaje, 'Constancia no válida.' AS Mensaje; LEAVE proc;
    END IF;

    START TRANSACTION;

    SELECT r.id_os, r.ruta_constancia INTO v_os, v_anterior FROM om_recepcion r WHERE r.id_recepcion = p_id_recepcion AND r.eliminado_en IS NULL FOR UPDATE;
    IF v_os IS NOT NULL THEN
        CALL SP_ArmarOmTecnicoMovil(p_id_usuario, v_os);
        SELECT COUNT(*) INTO v_existe FROM tmp_rom_os;
        DROP TEMPORARY TABLE IF EXISTS tmp_rom_os;
    END IF;
    IF v_os IS NULL OR v_existe = 0 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Constancia no encontrada.' AS Mensaje; LEAVE proc;
    END IF;

    UPDATE om_recepcion
    SET    ruta_constancia = TRIM(p_ruta), correo_enviado = IF(IFNULL(p_correo_enviado, 0) = 1, 1, 0), modificado_por = p_id_usuario
    WHERE  id_recepcion = p_id_recepcion;

    COMMIT;

    SELECT 2 AS IdTipoMensaje, 'Constancia guardada.' AS Mensaje;
    SELECT IF(v_anterior = TRIM(p_ruta), NULL, v_anterior) AS ruta_anterior;
END$$

DELIMITER ;
