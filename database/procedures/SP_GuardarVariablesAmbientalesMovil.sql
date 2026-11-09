-- ============================================================
-- SP_GuardarVariablesAmbientalesMovil  (App Mobile HU-09 — Registro de variables ambientales · escritura)
-- El técnico registra las condiciones del entorno del equipo antes de proceder con el pesaje.
--   - El técnico sale del token; la OS debe ser suya. Hard Stop (HU-06): solo con la llegada registrada y la OS en curso.
--   - El equipo debe estar EN EJECUCIÓN (primero se inicia desde los objetivos).
--   - Obligatorios: temperatura (°C, de -20 a 60) y humedad relativa (%, de 0 a 100). Procedencia opcional: vacía = "N.I" (no indicado).
--   - Fecha y hora las pone el servidor (UTC); el técnico no las edita. Sin conexión la app envía p_capturado_utc (hora del teléfono, solo se
--     respeta si no es futura —tolerancia 5 min— ni tiene más de 24 h).
--   - Una fila vigente por OS + equipo: guardar otra vez la actualiza (y el cambio queda en auditoria_evento con lo anterior y lo nuevo).
--     Repetir exactamente el mismo envío responde éxito sin cambiar nada.
--   - Habilita "Ensayos y Calibración" (SP_ObtenerTrabajoEquipoMovil la desbloquea al existir la fila).
-- Resultados: 1 mensaje; 2 (temperatura_c, humedad_pct, procedencia, registrado_en en Lima, actualizada, repetida).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_GuardarVariablesAmbientalesMovil;

DELIMITER $$

CREATE PROCEDURE SP_GuardarVariablesAmbientalesMovil(
    IN p_id_usuario    BIGINT,
    IN p_id_os         BIGINT,
    IN p_id_os_equipo  BIGINT,
    IN p_temperatura   DECIMAL(6,2),
    IN p_humedad       DECIMAL(5,2),
    IN p_procedencia   VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_capturado_utc DATETIME
)
proc: BEGIN
    DECLARE v_estado_os   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_numero_os   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_salida_utc  DATETIME;
    DECLARE v_llegada_utc DATETIME;
    DECLARE v_habilitado  TINYINT;
    DECLARE v_motivo      VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_equipo   BIGINT DEFAULT NULL;
    DECLARE v_estado      VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_proc        VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_var      BIGINT DEFAULT NULL;
    DECLARE v_t_ant       DECIMAL(6,2);
    DECLARE v_h_ant       DECIMAL(5,2);
    DECLARE v_p_ant       VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_ahora_utc   DATETIME;
    DECLARE v_t_utc       DATETIME;
    DECLARE v_repetida    TINYINT DEFAULT 0;
    DECLARE v_actualiza   TINYINT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 OR IFNULL(p_id_os_equipo, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio o equipo no encontrado.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF p_temperatura IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Ingresa la temperatura (°C).' AS Mensaje; LEAVE proc;
    END IF;
    IF p_humedad IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Ingresa la humedad relativa (%).' AS Mensaje; LEAVE proc;
    END IF;
    IF p_temperatura < -20 OR p_temperatura > 60 THEN
        SELECT 1 AS IdTipoMensaje, 'La temperatura debe estar entre -20 y 60 °C.' AS Mensaje; LEAVE proc;
    END IF;
    IF p_humedad < 0 OR p_humedad > 100 THEN
        SELECT 1 AS IdTipoMensaje, 'La humedad relativa debe estar entre 0 y 100 %.' AS Mensaje; LEAVE proc;
    END IF;
    IF CHAR_LENGTH(TRIM(IFNULL(p_procedencia, ''))) > 100 THEN
        SELECT 1 AS IdTipoMensaje, 'La procedencia puede tener hasta 100 caracteres.' AS Mensaje; LEAVE proc;
    END IF;
    SET v_proc = IFNULL(NULLIF(TRIM(IFNULL(p_procedencia, '')), ''), 'N.I');

    SET v_ahora_utc = UTC_TIMESTAMP();
    SET v_t_utc     = v_ahora_utc;
    IF p_capturado_utc IS NOT NULL AND p_capturado_utc >= v_ahora_utc - INTERVAL 24 HOUR AND p_capturado_utc <= v_ahora_utc + INTERVAL 5 MINUTE THEN
        SET v_t_utc = LEAST(p_capturado_utc, v_ahora_utc);
    END IF;

    START TRANSACTION;

    SELECT os.estado, os.numero INTO v_estado_os, v_numero_os
    FROM   orden_servicio os
    WHERE  os.id_os = p_id_os AND os.eliminado_en IS NULL
      AND  (os.id_tecnico_principal = p_id_usuario
            OR EXISTS (SELECT 1 FROM os_personal op
                       WHERE op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL))
    FOR UPDATE;
    IF v_estado_os IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Servicio no encontrado o no asignado a tu usuario.' AS Mensaje; LEAVE proc;
    END IF;

    CALL SP_ArmarObjetivosMovil(p_id_os, v_estado_os, v_salida_utc, v_llegada_utc, v_habilitado, v_motivo);
    SELECT t.id_equipo, t.estado INTO v_id_equipo, v_estado FROM tmp_obj_mov t WHERE t.id_os_equipo = p_id_os_equipo;
    DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;

    IF v_habilitado = 0 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, v_motivo AS Mensaje; LEAVE proc;
    END IF;
    IF v_id_equipo IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'El equipo no forma parte de los objetivos de este servicio.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_estado <> 'en_ejecucion' THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje,
               IF(v_estado = 'pausado', 'El equipo está pausado: reanúdalo para registrar las variables ambientales.',
                  IF(v_estado = 'completado', 'Este equipo ya está completado.', 'Primero inicia el trabajo en este equipo desde los objetivos.')) AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT va.id_variable, va.temperatura_c, va.humedad_pct, IFNULL(va.procedencia, 'N.I') INTO v_id_var, v_t_ant, v_h_ant, v_p_ant
    FROM   variable_ambiental va
    WHERE  va.id_os = p_id_os AND va.id_equipo = v_id_equipo AND va.eliminado_en IS NULL
    ORDER BY va.id_variable DESC LIMIT 1
    FOR UPDATE;

    IF v_id_var IS NOT NULL AND v_t_ant = p_temperatura AND v_h_ant = p_humedad AND v_p_ant = v_proc THEN
        SET v_repetida = 1;
    ELSEIF v_id_var IS NOT NULL THEN
        SET v_actualiza = 1;
        UPDATE variable_ambiental
        SET    temperatura_c = p_temperatura, humedad_pct = p_humedad, procedencia = v_proc, id_usuario = p_id_usuario,
               registrado_en = v_t_utc, modificado_por = p_id_usuario
        WHERE  id_variable = v_id_var;
    ELSE
        INSERT INTO variable_ambiental (id_om, id_os, id_equipo, id_usuario, temperatura_c, humedad_pct, procedencia, registrado_en, creado_por)
        VALUES (NULL, p_id_os, v_id_equipo, p_id_usuario, p_temperatura, p_humedad, v_proc, v_t_utc, p_id_usuario);
        SET v_id_var = LAST_INSERT_ID();
    END IF;

    IF v_repetida = 0 THEN
        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
        VALUES ('os_equipo', p_id_os_equipo, IF(v_actualiza = 1, 'actualizar_variables_ambientales', 'registrar_variables_ambientales'),
                IF(v_actualiza = 1, CONCAT(v_t_ant, ' °C · ', v_h_ant, ' % · ', v_p_ant), NULL),
                CONCAT(p_temperatura, ' °C · ', p_humedad, ' % · ', v_proc),
                LEFT(CONCAT('Variables ambientales de ', v_numero_os, ': ', p_temperatura, ' °C, ', p_humedad, ' %, procedencia ', v_proc), 300),
                p_id_usuario, NOW(),
                JSON_OBJECT('id_os', p_id_os, 'id_variable', v_id_var));
    END IF;

    COMMIT;

    SELECT 2 AS IdTipoMensaje,
           IF(v_repetida = 1, 'Las variables ambientales ya estaban registradas.', 'Variables ambientales guardadas. Ya puedes continuar con Ensayos y Calibración.') AS Mensaje;
    SELECT p_temperatura AS temperatura_c, p_humedad AS humedad_pct, v_proc AS procedencia,
           CONVERT_TZ(IF(v_repetida = 1, (SELECT va.registrado_en FROM variable_ambiental va WHERE va.id_variable = v_id_var), v_t_utc), '+00:00', '-05:00') AS registrado_en,
           v_actualiza AS actualizada, v_repetida AS repetida;
END$$

DELIMITER ;
