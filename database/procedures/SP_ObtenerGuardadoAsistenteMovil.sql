-- ============================================================
-- SP_ObtenerGuardadoAsistenteMovil  (App Mobile HU-19 — abrir un guardado · lectura)
-- Un guardado del propio técnico (no eliminado) con su contenido completo (JSON: la respuesta o el fragmento citado con su fuente). Horas de Lima.
-- Resultados: 1 mensaje · 2 guardado (id_guardado, tipo, titulo, subtitulo, creado_en, tamano_bytes, contenido_json).
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerGuardadoAsistenteMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerGuardadoAsistenteMovil(
    IN p_id_usuario  BIGINT,
    IN p_id_guardado BIGINT
)
proc: BEGIN
    DECLARE v_id BIGINT DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_guardado, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Guardado no encontrado.' AS Mensaje; LEAVE proc;
    END IF;

    SELECT g.id_guardado INTO v_id
    FROM   asistente_guardado g
    WHERE  g.id_guardado = p_id_guardado AND g.id_usuario = p_id_usuario AND g.eliminado_en IS NULL;
    IF v_id IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Guardado no encontrado.' AS Mensaje; LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;
    SELECT g.id_guardado, g.tipo, g.titulo, g.subtitulo, CONVERT_TZ(g.creado_en, '+00:00', '-05:00') AS creado_en, g.tamano_bytes, CAST(g.contenido_json AS CHAR) AS contenido_json
    FROM   asistente_guardado g WHERE g.id_guardado = v_id;
END$$

DELIMITER ;
