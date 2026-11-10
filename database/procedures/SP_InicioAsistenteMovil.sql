-- ============================================================
-- SP_InicioAsistenteMovil  (App Mobile HU-19 — inicio del Asistente IA · lectura)
-- La pantalla de inicio: el equipo en contexto, los documentos oficiales que consultará el asistente, las sugerencias y las consultas recientes.
--   - Sin p_id_os ni p_id_os_equipo: el equipo EN EJECUCIÓN del técnico (trabaja uno a la vez); si no hay ninguno el contexto va vacío y la app
--     ofrece "Cambiar". Con ambos: ese equipo (SP_ContextoAsistenteMovil: OS del técnico, objetivo de la OS, OS activa). Con uno solo: error.
--   - Fuentes = SP_ArmarDocumentosAsistenteMovil (manual del suministro y PDF aprobado de los procedimientos del servicio).
--   - Sugerencias (máx. 6) = hasta 2 procedimientos del equipo ("Procedimiento PC-001") y el catálogo SUGERENCIA_ASISTENTE hasta completar; una sugerencia con
--     palabra clave (String3) solo aplica a equipos cuyo suministro (tipo, subtipo o descripción) la contenga.
--   - Recientes (máx. 5) = las últimas consultas con respuesta del técnico, del equipo en contexto o, sin contexto, de cualquiera. Horas de Lima.
-- Resultados: 1 mensaje · 2 contexto (0 o 1 fila) · 3 fuentes · 4 sugerencias · 5 recientes.
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_InicioAsistenteMovil;

DELIMITER $$

CREATE PROCEDURE SP_InicioAsistenteMovil(
    IN p_id_usuario   BIGINT,
    IN p_id_os        BIGINT,
    IN p_id_os_equipo BIGINT
)
proc: BEGIN
    DECLARE v_msg       VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_os     BIGINT DEFAULT NULL;
    DECLARE v_id_oe     BIGINT DEFAULT NULL;
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
    DECLARE v_clave_su  VARCHAR(400) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT '';

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
        DROP TEMPORARY TABLE IF EXISTS tmp_doc_asist;
        DROP TEMPORARY TABLE IF EXISTS tmp_sug_asist;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no válido.' AS Mensaje; LEAVE proc;
    END IF;
    IF IFNULL(p_id_os, 0) > 0 AND IFNULL(p_id_os_equipo, 0) > 0 THEN
        SET v_id_os = p_id_os, v_id_oe = p_id_os_equipo;
    ELSEIF IFNULL(p_id_os, 0) > 0 OR IFNULL(p_id_os_equipo, 0) > 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio o equipo no encontrado.' AS Mensaje; LEAVE proc;
    ELSE
        -- El equipo en ejecución del técnico (uno a la vez)
        SELECT oe.id_os, oe.id INTO v_id_os, v_id_oe
        FROM   os_equipo oe
        JOIN   orden_servicio os ON os.id_os = oe.id_os AND os.eliminado_en IS NULL AND os.estado NOT IN ('finalizada', 'anulada')
        WHERE  oe.eliminado_en IS NULL AND oe.estado_ejecucion = 'en_proceso' AND oe.pausado = 0
          AND  (os.id_tecnico_principal = p_id_usuario
                OR EXISTS (SELECT 1 FROM os_personal op WHERE op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL))
        ORDER BY oe.iniciado_utc DESC, oe.id DESC LIMIT 1;
    END IF;

    DROP TEMPORARY TABLE IF EXISTS tmp_sug_asist;
    CREATE TEMPORARY TABLE tmp_sug_asist (orden INT NOT NULL AUTO_INCREMENT, texto VARCHAR(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL, PRIMARY KEY (orden));

    IF v_id_oe IS NOT NULL THEN
        CALL SP_ContextoAsistenteMovil(p_id_usuario, v_id_os, v_id_oe, v_msg, v_id_eq, v_id_sum, v_estado, v_numero, v_nombre, v_num_os, v_servicio,
                                       v_marca, v_modelo, v_cod_cli, v_serie);
        IF v_msg IS NOT NULL THEN
            DROP TEMPORARY TABLE IF EXISTS tmp_sug_asist;
            SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje; LEAVE proc;
        END IF;
        SELECT LOWER(CONCAT_WS(' ', su.tipo, su.subtipo, su.descripcion)) INTO v_clave_su FROM suministros su WHERE su.id_suministro = v_id_sum LIMIT 1;
        SET v_clave_su = IFNULL(v_clave_su, '');
        CALL SP_ArmarDocumentosAsistenteMovil(v_id_os, v_id_oe, v_id_sum);

        -- Sugerencias: primero los procedimientos del equipo (máx. 2)
        INSERT INTO tmp_sug_asist (texto)
        SELECT LEFT(CONCAT('Procedimiento ', TRIM(SUBSTRING_INDEX(d.titulo, ' · ', 1))), 120) FROM tmp_doc_asist d WHERE d.tipo = 'procedimiento' ORDER BY d.orden LIMIT 2;
    END IF;

    INSERT INTO tmp_sug_asist (texto)
    SELECT LEFT(t.String1, 120)
    FROM   tabla_maestra t
    WHERE  t.Descripcion = 'SUGERENCIA_ASISTENTE' AND t.IdEmpresa = 1 AND NULLIF(TRIM(t.String1), '') IS NOT NULL
      AND  (NULLIF(TRIM(t.String3), '') IS NULL OR LOCATE(LOWER(TRIM(t.String3)), v_clave_su) > 0)
    ORDER BY t.Num1, t.IdTablaMaestra
    LIMIT 6;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Contexto (vacío si el técnico no tiene un equipo en trabajo)
    IF v_id_oe IS NOT NULL THEN
        SELECT v_id_os AS id_os, v_num_os AS numero_os, v_id_oe AS id_os_equipo, v_nombre AS nombre, v_numero AS numero, v_marca AS marca, v_modelo AS modelo,
               v_cod_cli AS codigo_cliente, v_serie AS numero_serie, v_servicio AS servicio_sigla, v_estado AS estado;
    ELSE
        SELECT NULL AS id_os, NULL AS numero_os, NULL AS id_os_equipo, NULL AS nombre, NULL AS numero, NULL AS marca, NULL AS modelo,
               NULL AS codigo_cliente, NULL AS numero_serie, NULL AS servicio_sigla, NULL AS estado FROM DUAL WHERE 1 = 0;
    END IF;

    -- 3. Fuentes
    IF v_id_oe IS NOT NULL THEN
        SELECT d.id_documento, d.tipo, d.titulo, d.version, d.entidad, DATE_FORMAT(d.actualizado, '%Y-%m-%d') AS actualizado, d.disponible
        FROM   tmp_doc_asist d ORDER BY d.orden;
    ELSE
        SELECT NULL AS id_documento, NULL AS tipo, NULL AS titulo, NULL AS version, NULL AS entidad, NULL AS actualizado, NULL AS disponible FROM DUAL WHERE 1 = 0;
    END IF;

    -- 4. Sugerencias (máx. 6: los procedimientos y el catálogo hasta completar)
    SELECT s.texto FROM tmp_sug_asist s ORDER BY s.orden LIMIT 6;

    -- 5. Consultas recientes con respuesta
    SELECT c.id_consulta, c.pregunta,
           NULLIF(CONCAT(IFNULL(NULLIF(JSON_UNQUOTE(JSON_EXTRACT(c.respuesta_json, '$.fuentes[0].documento')), 'null'), ''),
                         IF(JSON_UNQUOTE(JSON_EXTRACT(c.respuesta_json, '$.fuentes[0].seccion')) REGEXP '^[0-9]',
                            CONCAT(' §', SUBSTRING_INDEX(JSON_UNQUOTE(JSON_EXTRACT(c.respuesta_json, '$.fuentes[0].seccion')), ' ', 1)), '')), '') AS fuente,
           CONVERT_TZ(c.creado_en, '+00:00', '-05:00') AS creado_en
    FROM   asistente_consulta c
    WHERE  c.id_usuario = p_id_usuario AND c.respuesta_json IS NOT NULL AND c.estado IN ('respondida', 'sin_respuesta', 'sin_fuentes')
      AND  (v_id_oe IS NULL OR c.id_os_equipo = v_id_oe)
    ORDER BY c.creado_en DESC, c.id_consulta DESC LIMIT 5;

    DROP TEMPORARY TABLE IF EXISTS tmp_doc_asist;
    DROP TEMPORARY TABLE IF EXISTS tmp_sug_asist;
END$$

DELIMITER ;
