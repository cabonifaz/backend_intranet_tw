-- ============================================================
-- SP_RegistrarConsultaAsistenteMovil  (App Mobile HU-19 — consulta al Asistente IA · escritura en dos fases)
-- La consulta se registra ANTES de llamar a la IA (para que el límite de uso se cuente aunque la IA falle) y se completa al terminar:
--   Fase 1 (p_id_consulta NULL): valida la pregunta (3 a 500 caracteres) y el origen (texto | voz | sugerencia), el equipo en contexto
--     (SP_ContextoAsistenteMovil: OS del técnico) y el LÍMITE DE USO: máx. 10 consultas por minuto y 200 por 24 horas por técnico (las consultas en
--     proceso, respondidas y con error cuentan). El técnico se bloquea (FOR UPDATE) para que dos consultas simultáneas no se salten el límite.
--     Inserta la consulta en estado 'procesando'.
--   Fase 2 (p_id_consulta con valor): completa SU consulta (del mismo técnico, aún 'procesando') con el resultado: p_estado = respondida | sin_respuesta
--     (la IA no lo encontró en los documentos) | sin_fuentes (el equipo no tiene documentos oficiales) | error_ia, los documentos usados, la respuesta
--     (JSON), el motor de IA y la duración. El texto del error de la IA NO se guarda como respuesta.
-- Resultados: 1 mensaje · 2 (id_consulta, creado_en en hora de Lima).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_RegistrarConsultaAsistenteMovil;

DELIMITER $$

CREATE PROCEDURE SP_RegistrarConsultaAsistenteMovil(
    IN p_id_usuario      BIGINT,
    IN p_id_consulta     BIGINT,
    IN p_id_os           BIGINT,
    IN p_id_os_equipo    BIGINT,
    IN p_pregunta        VARCHAR(600) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_origen          VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_estado          VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_documentos_json LONGTEXT     CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_respuesta_json  LONGTEXT     CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_motor           VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_duracion_ms     INT
)
proc: BEGIN
    DECLARE v_msg      VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_eq    BIGINT;
    DECLARE v_id_sum   BIGINT;
    DECLARE v_estado   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_numero   INT;
    DECLARE v_nombre   VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_num_os   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_servicio VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_marca    VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_modelo   VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cod_cli  VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_serie    VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_pregunta VARCHAR(600) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_origen   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_usuario  BIGINT DEFAULT NULL;
    DECLARE v_minuto   INT DEFAULT 0;
    DECLARE v_dia      INT DEFAULT 0;
    DECLARE v_id       BIGINT DEFAULT NULL;
    DECLARE v_actual   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_creado   DATETIME;
    DECLARE v_docs     LONGTEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_resp     LONGTEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no válido.' AS Mensaje; LEAVE proc;
    END IF;

    -- ══════════ Fase 2: completar la consulta ══════════
    IF p_id_consulta IS NOT NULL THEN
        IF p_estado IS NULL OR p_estado NOT IN ('respondida', 'sin_respuesta', 'sin_fuentes', 'error_ia') THEN
            SELECT 1 AS IdTipoMensaje, 'Estado de la consulta no válido.' AS Mensaje; LEAVE proc;
        END IF;
        SET v_docs = IF(p_documentos_json IS NOT NULL AND JSON_VALID(p_documentos_json) AND CHAR_LENGTH(p_documentos_json) <= 8000, p_documentos_json, NULL);
        SET v_resp = IF(p_estado <> 'error_ia' AND p_respuesta_json IS NOT NULL AND JSON_VALID(p_respuesta_json) AND CHAR_LENGTH(p_respuesta_json) <= 60000, p_respuesta_json, NULL);

        START TRANSACTION;
        SELECT c.id_consulta, c.estado, c.creado_en INTO v_id, v_actual, v_creado
        FROM   asistente_consulta c
        WHERE  c.id_consulta = p_id_consulta AND c.id_usuario = p_id_usuario
        FOR UPDATE;
        IF v_id IS NULL THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, 'Consulta no encontrada.' AS Mensaje; LEAVE proc;
        END IF;
        IF v_actual <> 'procesando' THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, 'La consulta ya fue completada.' AS Mensaje; LEAVE proc;
        END IF;

        UPDATE asistente_consulta
        SET    estado = p_estado, documentos_json = v_docs, respuesta_json = v_resp, motor_ia = LEFT(NULLIF(TRIM(IFNULL(p_motor, '')), ''), 60),
               duracion_ms = IF(p_duracion_ms BETWEEN 0 AND 2000000, p_duracion_ms, NULL)
        WHERE  id_consulta = p_id_consulta;
        COMMIT;

        SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;
        SELECT p_id_consulta AS id_consulta, CONVERT_TZ(v_creado, '+00:00', '-05:00') AS creado_en;
        LEAVE proc;
    END IF;

    -- ══════════ Fase 1: validar, aplicar el límite y registrar ══════════
    IF IFNULL(p_id_os, 0) <= 0 OR IFNULL(p_id_os_equipo, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio o equipo no encontrado.' AS Mensaje; LEAVE proc;
    END IF;
    SET v_pregunta = NULLIF(TRIM(IFNULL(p_pregunta, '')), '');
    IF v_pregunta IS NULL OR CHAR_LENGTH(v_pregunta) < 3 THEN
        SELECT 1 AS IdTipoMensaje, 'Escribe tu consulta (mínimo 3 caracteres).' AS Mensaje; LEAVE proc;
    END IF;
    IF CHAR_LENGTH(v_pregunta) > 500 THEN
        SELECT 1 AS IdTipoMensaje, 'La consulta puede tener hasta 500 caracteres.' AS Mensaje; LEAVE proc;
    END IF;
    SET v_origen = LOWER(TRIM(IFNULL(p_origen, 'texto')));
    IF v_origen NOT IN ('texto', 'voz', 'sugerencia') THEN
        SELECT 1 AS IdTipoMensaje, 'El origen de la consulta no es válido.' AS Mensaje; LEAVE proc;
    END IF;

    START TRANSACTION;

    SELECT u.id_usuario INTO v_usuario FROM usuario u WHERE u.id_usuario = p_id_usuario AND u.eliminado_en IS NULL FOR UPDATE;
    IF v_usuario IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Usuario no válido.' AS Mensaje; LEAVE proc;
    END IF;

    CALL SP_ContextoAsistenteMovil(p_id_usuario, p_id_os, p_id_os_equipo, v_msg, v_id_eq, v_id_sum, v_estado, v_numero, v_nombre, v_num_os, v_servicio,
                                   v_marca, v_modelo, v_cod_cli, v_serie);
    IF v_msg IS NOT NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje; LEAVE proc;
    END IF;

    SELECT COUNT(*) INTO v_minuto FROM asistente_consulta c WHERE c.id_usuario = p_id_usuario AND c.creado_en >= UTC_TIMESTAMP() - INTERVAL 1 MINUTE;
    IF v_minuto >= 10 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Hiciste muchas consultas seguidas. Espera un minuto e inténtalo de nuevo.' AS Mensaje; LEAVE proc;
    END IF;
    SELECT COUNT(*) INTO v_dia FROM asistente_consulta c WHERE c.id_usuario = p_id_usuario AND c.creado_en >= UTC_TIMESTAMP() - INTERVAL 24 HOUR;
    IF v_dia >= 200 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Llegaste al límite de 200 consultas al día. Podrás volver a consultar mañana.' AS Mensaje; LEAVE proc;
    END IF;

    SET v_creado = UTC_TIMESTAMP();
    INSERT INTO asistente_consulta (id_usuario, id_os, id_os_equipo, id_equipo, pregunta, origen, estado, creado_en)
    VALUES (p_id_usuario, p_id_os, p_id_os_equipo, v_id_eq, v_pregunta, v_origen, 'procesando', v_creado);
    SET v_id = LAST_INSERT_ID();
    COMMIT;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;
    SELECT v_id AS id_consulta, CONVERT_TZ(v_creado, '+00:00', '-05:00') AS creado_en;
END$$

DELIMITER ;
