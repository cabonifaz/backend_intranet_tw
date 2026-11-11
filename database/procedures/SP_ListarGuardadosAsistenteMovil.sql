-- ============================================================
-- SP_ListarGuardadosAsistenteMovil  (App Mobile HU-19 — "Guardados" del Asistente IA · lectura)
-- Respuestas y fragmentos que el técnico guardó (sin los eliminados), los más recientes primero, máx. 100. p_busqueda filtra por título o subtítulo
-- (los comodines % y _ del texto se tratan como texto). Horas de Lima.
-- Resultados: 1 mensaje · 2 guardados (id_guardado, tipo, titulo, subtitulo, creado_en, tamano_bytes).
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ListarGuardadosAsistenteMovil;

DELIMITER $$

CREATE PROCEDURE SP_ListarGuardadosAsistenteMovil(
    IN p_id_usuario BIGINT,
    IN p_busqueda   VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_texto VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no válido.' AS Mensaje; LEAVE proc;
    END IF;

    SET v_texto = NULLIF(TRIM(IFNULL(p_busqueda, '')), '');
    IF v_texto IS NOT NULL THEN
        SET v_texto = CONCAT('%', REPLACE(REPLACE(REPLACE(v_texto, '\\', '\\\\'), '%', '\\%'), '_', '\\_'), '%');
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT g.id_guardado, g.tipo, g.titulo, g.subtitulo, CONVERT_TZ(g.creado_en, '+00:00', '-05:00') AS creado_en, g.tamano_bytes
    FROM   asistente_guardado g
    WHERE  g.id_usuario = p_id_usuario AND g.eliminado_en IS NULL
      AND  (v_texto IS NULL OR g.titulo LIKE v_texto OR g.subtitulo LIKE v_texto)
    ORDER BY g.creado_en DESC, g.id_guardado DESC
    LIMIT 100;
END$$

DELIMITER ;
