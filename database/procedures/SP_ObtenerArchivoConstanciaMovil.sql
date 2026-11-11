-- ============================================================
-- SP_ObtenerArchivoConstanciaMovil  (App Mobile HU-17 — descarga del PDF o de la foto del formato físico · solo lectura)
-- Ruta interna del archivo de la constancia de una OS del técnico. p_tipo = pdf | foto.
-- Resultados: 1 mensaje · 2 (solo éxito) ruta.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerArchivoConstanciaMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerArchivoConstanciaMovil(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT,
    IN p_tipo       VARCHAR(5) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_msg  VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_num  VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_ruta VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;

    IF IFNULL(p_tipo, '') NOT IN ('pdf', 'foto') THEN
        SELECT 1 AS IdTipoMensaje, 'El archivo pedido no es válido.' AS Mensaje; LEAVE proc;
    END IF;
    CALL SP_ContextoFirmaMovil(p_id_usuario, p_id_os, v_msg, v_num);
    IF v_msg IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje; LEAVE proc;
    END IF;
    SELECT IF(p_tipo = 'pdf', k.ruta_pdf, k.ruta_foto) INTO v_ruta FROM os_constancia k WHERE k.id_os = p_id_os;
    IF v_ruta IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'La constancia todavía no tiene ese archivo.' AS Mensaje; LEAVE proc;
    END IF;
    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;
    SELECT v_ruta AS ruta;
END$$

DELIMITER ;
