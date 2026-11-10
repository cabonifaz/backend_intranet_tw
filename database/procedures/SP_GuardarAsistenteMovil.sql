-- ============================================================
-- SP_GuardarAsistenteMovil  (App Mobile HU-19 — "Guardar offline" / "Fragmento" · escritura)
-- Guarda una copia de la respuesta (tipo 'respuesta', n = 0) o de uno de los fragmentos citados (tipo 'fragmento', n = número de la fuente, 1 a 20) de una consulta
-- del técnico, para que la app la lea sin conexión (la "descarga de sección" es el fragmento citado con su fuente, no un PDF recortado).
--   - La consulta debe ser del técnico y tener respuesta. El contenido (JSON) lo arma el back a partir de la consulta guardada, no la app.
--   - Idempotente: guardar dos veces lo mismo devuelve el guardado existente. Máx. 300 guardados por técnico.
-- Resultados: 1 mensaje · 2 guardado (id_guardado, tipo, titulo, subtitulo, creado_en en hora de Lima, tamano_bytes, contenido_json).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_GuardarAsistenteMovil;

DELIMITER $$

CREATE PROCEDURE SP_GuardarAsistenteMovil(
    IN p_id_usuario     BIGINT,
    IN p_id_consulta    BIGINT,
    IN p_tipo           VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_n              INT,
    IN p_titulo         VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_subtitulo      VARCHAR(400) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_contenido_json LONGTEXT     CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_tipo     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_titulo   VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_subt     VARCHAR(400) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_n        INT;
    DECLARE v_consulta BIGINT DEFAULT NULL;
    DECLARE v_resp     TINYINT DEFAULT 0;
    DECLARE v_id       BIGINT DEFAULT NULL;
    DECLARE v_total    INT DEFAULT 0;
    DECLARE v_creado   DATETIME;
    DECLARE v_bytes    INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_consulta, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Consulta no encontrada.' AS Mensaje; LEAVE proc;
    END IF;
    SET v_tipo = LOWER(TRIM(IFNULL(p_tipo, '')));
    IF v_tipo NOT IN ('respuesta', 'fragmento') THEN
        SELECT 1 AS IdTipoMensaje, 'Lo que quieres guardar no es válido.' AS Mensaje; LEAVE proc;
    END IF;
    SET v_n = IF(v_tipo = 'respuesta', 0, IFNULL(p_n, 0));
    IF v_tipo = 'fragmento' AND (v_n < 1 OR v_n > 20) THEN
        SELECT 1 AS IdTipoMensaje, 'La fuente indicada no existe.' AS Mensaje; LEAVE proc;
    END IF;
    SET v_titulo = NULLIF(TRIM(IFNULL(p_titulo, '')), '');
    SET v_subt   = NULLIF(TRIM(IFNULL(p_subtitulo, '')), '');
    IF v_titulo IS NULL OR CHAR_LENGTH(v_titulo) > 200 OR (v_subt IS NOT NULL AND CHAR_LENGTH(v_subt) > 300) THEN
        SELECT 1 AS IdTipoMensaje, 'El título o el subtítulo del guardado no son válidos.' AS Mensaje; LEAVE proc;
    END IF;
    IF p_contenido_json IS NULL OR NOT JSON_VALID(p_contenido_json) OR CHAR_LENGTH(p_contenido_json) > 60000 THEN
        SELECT 1 AS IdTipoMensaje, 'El contenido a guardar no es válido.' AS Mensaje; LEAVE proc;
    END IF;

    START TRANSACTION;

    SELECT c.id_consulta, IF(c.respuesta_json IS NULL, 0, 1) INTO v_consulta, v_resp
    FROM   asistente_consulta c
    WHERE  c.id_consulta = p_id_consulta AND c.id_usuario = p_id_usuario
    FOR UPDATE;
    IF v_consulta IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Consulta no encontrada.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_resp = 0 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Esta consulta no tiene respuesta que guardar.' AS Mensaje; LEAVE proc;
    END IF;

    SELECT g.id_guardado INTO v_id
    FROM   asistente_guardado g
    WHERE  g.id_usuario = p_id_usuario AND g.id_consulta = p_id_consulta AND g.tipo = v_tipo AND g.n = v_n AND g.eliminado_en IS NULL
    ORDER BY g.id_guardado LIMIT 1;

    IF v_id IS NULL THEN
        SELECT COUNT(*) INTO v_total FROM asistente_guardado g WHERE g.id_usuario = p_id_usuario AND g.eliminado_en IS NULL;
        IF v_total >= 300 THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, 'Llegaste al máximo de 300 guardados. Elimina alguno para guardar otro.' AS Mensaje; LEAVE proc;
        END IF;
        SET v_creado = UTC_TIMESTAMP();
        SET v_bytes  = LENGTH(p_contenido_json);
        INSERT INTO asistente_guardado (id_usuario, id_consulta, tipo, n, titulo, subtitulo, contenido_json, tamano_bytes, creado_en)
        VALUES (p_id_usuario, p_id_consulta, v_tipo, v_n, v_titulo, v_subt, p_contenido_json, v_bytes, v_creado);
        SET v_id = LAST_INSERT_ID();
    END IF;
    COMMIT;

    SELECT 2 AS IdTipoMensaje, 'Guardado en el teléfono: ya puedes leerlo sin conexión.' AS Mensaje;
    SELECT g.id_guardado, g.tipo, g.titulo, g.subtitulo, CONVERT_TZ(g.creado_en, '+00:00', '-05:00') AS creado_en, g.tamano_bytes, CAST(g.contenido_json AS CHAR) AS contenido_json
    FROM   asistente_guardado g WHERE g.id_guardado = v_id;
END$$

DELIMITER ;
