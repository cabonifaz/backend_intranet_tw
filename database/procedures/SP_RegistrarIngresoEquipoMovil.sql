-- ============================================================
-- SP_RegistrarIngresoEquipoMovil  (App Mobile HU-22 — "Registrar equipo" del Ingreso de equipos (OS) · escritura)
-- El técnico registra el ingreso formal de un equipo de su OS: estado de ingreso, observación y fotos.
--   - El técnico sale del token; la OS debe ser suya. Hard Stop (HU-06): solo con la llegada registrada y la OS en curso (SP_ArmarObjetivosMovil).
--   - Estado de ingreso obligatorio: operativo · con_observaciones · inoperativo.
--     Con observaciones o inoperativo: observación (mínimo 3 caracteres, máximo 500) y al menos una foto (máximo 5) obligatorias.
--     Operativo: la observación es opcional y no se guardan fotos.
--   - Un equipo se ingresa UNA sola vez en la misma OS: si ya tiene ingreso se bloquea y se dice cómo y cuándo se registró.
--   - Los equipos bloqueados (inactivos o en evaluación) no se pueden ingresar. Un equipo nuevo (NEW) en borrador SÍ se ingresa (queda pendiente de validar en la intranet).
--   - p_fotos: arreglo JSON con las rutas ya guardadas por el back (["ingresos-equipos/12/….jpg", …]).
--   - Deja el ingreso en auditoria_evento (entidad 'os_equipo').
-- Resultados: 1 mensaje; 2 (id_ingreso, id_os_equipo, estado_ingreso, ingresado_en, fotos).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_RegistrarIngresoEquipoMovil;

DELIMITER $$

CREATE PROCEDURE SP_RegistrarIngresoEquipoMovil(
    IN p_id_usuario   BIGINT,
    IN p_id_os        BIGINT,
    IN p_id_os_equipo BIGINT,
    IN p_estado       VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_observacion  VARCHAR(600) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_fotos        JSON
)
proc: BEGIN
    DECLARE v_estado      VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_obs         VARCHAR(600) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado_os   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_salida_utc  DATETIME;
    DECLARE v_llegada_utc DATETIME;
    DECLARE v_habilitado  TINYINT;
    DECLARE v_motivo_no   VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_bloqueado   TINYINT DEFAULT 0;
    DECLARE v_nombre      VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_n_fotos     INT DEFAULT 0;
    DECLARE v_ahora_utc   DATETIME;
    DECLARE v_id          BIGINT;
    DECLARE v_prev_estado VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_prev_utc    DATETIME DEFAULT NULL;
    DECLARE v_oe          BIGINT DEFAULT NULL;

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

    SET v_estado = LOWER(TRIM(IFNULL(p_estado, '')));
    IF v_estado NOT IN ('operativo', 'con_observaciones', 'inoperativo') THEN
        SELECT 1 AS IdTipoMensaje, 'Selecciona el estado de ingreso del equipo.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_obs = NULLIF(TRIM(IFNULL(p_observacion, '')), '');
    IF CHAR_LENGTH(IFNULL(v_obs, '')) > 500 THEN
        SELECT 1 AS IdTipoMensaje, 'La observación puede tener hasta 500 caracteres.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_n_fotos = IF(p_fotos IS NULL OR JSON_TYPE(p_fotos) <> 'ARRAY', 0, JSON_LENGTH(p_fotos));
    IF v_estado <> 'operativo' THEN
        IF v_obs IS NULL OR CHAR_LENGTH(v_obs) < 3 THEN
            SELECT 1 AS IdTipoMensaje, 'Escribe la observación del estado del equipo (mínimo 3 caracteres).' AS Mensaje;
            LEAVE proc;
        END IF;
        IF v_n_fotos < 1 THEN
            SELECT 1 AS IdTipoMensaje, 'Toma al menos una foto de evidencia (solo cámara).' AS Mensaje;
            LEAVE proc;
        END IF;
        IF v_n_fotos > 5 THEN
            SELECT 1 AS IdTipoMensaje, 'Puedes adjuntar hasta 5 fotos.' AS Mensaje;
            LEAVE proc;
        END IF;
    ELSE
        SET v_n_fotos = 0;
    END IF;

    START TRANSACTION;

    -- La OS debe ser del técnico del token
    SELECT os.estado INTO v_estado_os
    FROM   orden_servicio os
    WHERE  os.id_os = p_id_os AND os.eliminado_en IS NULL
      AND  (os.id_tecnico_principal = p_id_usuario
            OR EXISTS (SELECT 1 FROM os_personal op
                       WHERE op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL))
    FOR UPDATE;
    IF v_estado_os IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Servicio no encontrado o no asignado a tu usuario.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- El equipo debe ser de esa OS (se bloquea la fila: dos envíos a la vez no ingresan dos veces)
    SELECT oe.id INTO v_oe FROM os_equipo oe WHERE oe.id = p_id_os_equipo AND oe.id_os = p_id_os AND oe.eliminado_en IS NULL FOR UPDATE;
    IF v_oe IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'El equipo no pertenece a este servicio.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Hard Stop (HU-06) y datos del equipo
    CALL SP_ArmarObjetivosMovil(p_id_os, v_estado_os, v_salida_utc, v_llegada_utc, v_habilitado, v_motivo_no);
    SELECT t.bloqueado, CONCAT(IFNULL(t.codigo_cliente, IFNULL(t.num_serie, t.codigo_tw)), ' · ', IFNULL(t.nombre, 'Equipo'))
    INTO   v_bloqueado, v_nombre
    FROM   tmp_obj_mov t
    WHERE  t.id_os_equipo = p_id_os_equipo;
    DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;

    IF v_llegada_utc IS NULL OR v_habilitado = 0 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, v_motivo_no AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_nombre IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'El equipo no forma parte de los objetivos de este servicio.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_bloqueado = 1 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Este equipo no se puede ingresar (está inactivo o en evaluación).' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Un equipo se ingresa una sola vez en la misma OS
    SELECT i.estado_ingreso, i.ingresado_utc INTO v_prev_estado, v_prev_utc
    FROM   os_equipo_ingreso i
    WHERE  i.id_os_equipo = p_id_os_equipo AND i.eliminado_en IS NULL
    ORDER BY i.id LIMIT 1;
    IF v_prev_estado IS NOT NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje,
               CONCAT(v_nombre, ' ya se registró hoy a las ', DATE_FORMAT(CONVERT_TZ(v_prev_utc, '+00:00', '-05:00'), '%H:%i'), ' como ',
                      CASE v_prev_estado WHEN 'operativo' THEN 'Operativo' WHEN 'con_observaciones' THEN 'Operativo con observaciones' ELSE 'Inoperativo' END,
                      '. No se puede ingresar dos veces en la misma OS.') AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_ahora_utc = UTC_TIMESTAMP();
    INSERT INTO os_equipo_ingreso (id_os, id_os_equipo, estado_ingreso, observacion, ingresado_utc, id_usuario)
    VALUES (p_id_os, p_id_os_equipo, v_estado, v_obs, v_ahora_utc, p_id_usuario);
    SET v_id = LAST_INSERT_ID();

    IF v_n_fotos > 0 THEN
        INSERT INTO os_equipo_ingreso_foto (id_ingreso, orden, ruta)
        SELECT v_id, jt.orden, jt.ruta
        FROM   JSON_TABLE(p_fotos, '$[*]' COLUMNS (orden FOR ORDINALITY, ruta VARCHAR(500) PATH '$')) jt
        WHERE  NULLIF(TRIM(jt.ruta), '') IS NOT NULL;
    END IF;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('os_equipo', p_id_os_equipo, 'ingreso_equipo', NULL,
            CASE v_estado WHEN 'operativo' THEN 'Operativo' WHEN 'con_observaciones' THEN 'Operativo con observaciones' ELSE 'Inoperativo' END,
            LEFT(CONCAT('Ingreso del equipo', IF(v_obs IS NULL, '', CONCAT(': ', v_obs))), 300),
            p_id_usuario, NOW(),
            JSON_OBJECT('id_os', p_id_os, 'id_ingreso', v_id, 'fotos', v_n_fotos));

    COMMIT;

    SELECT 2 AS IdTipoMensaje, CONCAT(v_nombre, ' registrado como ',
           CASE v_estado WHEN 'operativo' THEN 'Operativo' WHEN 'con_observaciones' THEN 'Operativo con observaciones' ELSE 'Inoperativo' END, '.') AS Mensaje;
    SELECT v_id AS id_ingreso, p_id_os_equipo AS id_os_equipo, v_estado AS estado_ingreso,
           CONVERT_TZ(v_ahora_utc, '+00:00', '-05:00') AS ingresado_en, v_n_fotos AS fotos;
END$$

DELIMITER ;
