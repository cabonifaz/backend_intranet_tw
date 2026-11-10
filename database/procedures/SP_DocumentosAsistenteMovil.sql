-- ============================================================
-- SP_DocumentosAsistenteMovil  (App Mobile HU-19 — contexto y documentos oficiales del equipo · lectura)
-- Lo que necesita el back para consultar al Asistente IA: el equipo en contexto (SP_ContextoAsistenteMovil) y los documentos oficiales que se le dan a la
-- IA (SP_ArmarDocumentosAsistenteMovil: manual del suministro y PDF aprobado de los procedimientos del servicio).
-- Resultados: 1 mensaje · 2 contexto (1 fila) · 3 documentos (0 a N filas: id_documento, tipo, titulo, version, entidad, actualizado, ubicacion, disponible).
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_DocumentosAsistenteMovil;

DELIMITER $$

CREATE PROCEDURE SP_DocumentosAsistenteMovil(
    IN p_id_usuario   BIGINT,
    IN p_id_os        BIGINT,
    IN p_id_os_equipo BIGINT
)
proc: BEGIN
    DECLARE v_msg       VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_eq     BIGINT;
    DECLARE v_id_sum    BIGINT;
    DECLARE v_estado    VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_numero    INT;
    DECLARE v_nombre    VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_num_os    VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_servicio  VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_marca     VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_modelo    VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cod_cli   VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_serie     VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tipo_eq   VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
        DROP TEMPORARY TABLE IF EXISTS tmp_doc_asist;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 OR IFNULL(p_id_os_equipo, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio o equipo no encontrado.' AS Mensaje; LEAVE proc;
    END IF;

    CALL SP_ContextoAsistenteMovil(p_id_usuario, p_id_os, p_id_os_equipo, v_msg, v_id_eq, v_id_sum, v_estado, v_numero, v_nombre, v_num_os, v_servicio,
                                   v_marca, v_modelo, v_cod_cli, v_serie);
    IF v_msg IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje; LEAVE proc;
    END IF;

    SELECT NULLIF(TRIM(su.descripcion), '') INTO v_tipo_eq FROM suministros su WHERE su.id_suministro = v_id_sum LIMIT 1;
    CALL SP_ArmarDocumentosAsistenteMovil(p_id_os, p_id_os_equipo, v_id_sum);

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT p_id_os AS id_os, v_num_os AS numero_os, p_id_os_equipo AS id_os_equipo, v_nombre AS nombre, v_numero AS numero, v_marca AS marca, v_modelo AS modelo,
           v_cod_cli AS codigo_cliente, v_serie AS numero_serie, v_servicio AS servicio_sigla, v_estado AS estado, v_tipo_eq AS tipo_equipo;

    SELECT d.id_documento, d.tipo, d.titulo, d.version, d.entidad, d.actualizado, d.ubicacion, d.disponible
    FROM   tmp_doc_asist d ORDER BY d.orden;

    DROP TEMPORARY TABLE IF EXISTS tmp_doc_asist;
END$$

DELIMITER ;
