-- ============================================================
-- SP_CambiarEstadoEquipoMovil  (App Mobile HU-07 — "Trabajar en el equipo" / "Pausar" / "Reanudar" · escritura)
-- El técnico inicia, pausa o reanuda el trabajo en un objetivo (equipo) de su OS.
--   - El técnico sale del token; la OS debe ser suya. Hard Stop (HU-06): solo con la llegada registrada y la OS en curso.
--   - Qué acción está permitida lo decide SP_ArmarObjetivosMovil (puede_iniciar / puede_pausar / puede_reanudar): aquí no se repite la regla.
--       iniciar  : por iniciar u observado → en ejecución. Un técnico trabaja en UN solo equipo a la vez (pausa el otro primero).
--                  El primer inicio de la OS la pasa a "en ejecución" y registra el evento INICIO_TRABAJO (la bandeja de seguimiento lo lee).
--       pausar   : en ejecución → pausado. Exige un motivo (3 a 300 caracteres). Cierra el tramo de tiempo y registra el evento PAUSA.
--       reanudar : pausado → en ejecución (evento REANUDA). Si la pausa espera aprobación del supervisor, NO se puede reanudar.
--   - Repetir una acción que ya está aplicada (reintento de la app) responde éxito sin duplicar nada.
--   - Sin conexión: la app guarda la acción con la hora en que se tocó (p_capturado_utc, UTC del teléfono; solo se respeta si no es futura
--     —tolerancia 5 min— ni tiene más de 24 h) y la envía al recuperar la señal EN ORDEN; el tiempo trabajado usa esa hora.
--   - Deja el cambio de estado en auditoria_evento (entidad 'os_equipo'), que la tarjeta muestra como Campo / Anterior / Actual.
-- Resultados: 1 mensaje; 2 (id_os_equipo, accion, estado, repetida, diferida).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_CambiarEstadoEquipoMovil;

DELIMITER $$

CREATE PROCEDURE SP_CambiarEstadoEquipoMovil(
    IN p_id_usuario    BIGINT,
    IN p_id_os         BIGINT,
    IN p_id_os_equipo  BIGINT,
    IN p_accion        VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_motivo        VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_capturado_utc DATETIME
)
proc: BEGIN
    DECLARE v_accion      VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_motivo      VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado_os   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_numero_os   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_salida_utc  DATETIME;
    DECLARE v_llegada_utc DATETIME;
    DECLARE v_habilitado  TINYINT;
    DECLARE v_motivo_no   VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado      VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_p_iniciar   TINYINT DEFAULT 0;
    DECLARE v_p_pausar    TINYINT DEFAULT 0;
    DECLARE v_p_reanudar  TINYINT DEFAULT 0;
    DECLARE v_bloqueado   TINYINT DEFAULT 0;
    DECLARE v_req_aprob   TINYINT DEFAULT 0;
    DECLARE v_nombre      VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_otro        VARCHAR(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_reanudado   DATETIME;
    DECLARE v_ahora_utc   DATETIME;
    DECLARE v_capt_utc    DATETIME;
    DECLARE v_t_utc       DATETIME;
    DECLARE v_diferida    TINYINT DEFAULT 0;
    DECLARE v_repetida    TINYINT DEFAULT 0;
    DECLARE v_nuevo       VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tipo_evt    INT DEFAULT NULL;
    DECLARE v_hay_inicio  TINYINT DEFAULT 0;
    DECLARE v_cod_evt     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_ant_txt     VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_nue_txt     VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

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
    SET v_accion = LOWER(TRIM(IFNULL(p_accion, '')));
    IF v_accion NOT IN ('iniciar', 'pausar', 'reanudar') THEN
        SELECT 1 AS IdTipoMensaje, 'La acción no es válida.' AS Mensaje;
        LEAVE proc;
    END IF;
    SET v_motivo = NULLIF(TRIM(IFNULL(p_motivo, '')), '');
    IF v_accion = 'pausar' AND (v_motivo IS NULL OR CHAR_LENGTH(v_motivo) < 3) THEN
        SELECT 1 AS IdTipoMensaje, 'Indica el motivo de la pausa (mínimo 3 caracteres).' AS Mensaje;
        LEAVE proc;
    END IF;
    IF CHAR_LENGTH(IFNULL(p_motivo, '')) > 300 THEN
        SELECT 1 AS IdTipoMensaje, 'El motivo puede tener hasta 300 caracteres.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Hora de la acción: la del servidor, salvo una guardada sin conexión (la hora del teléfono, sin futuro ni más de 24 h)
    SET v_ahora_utc = UTC_TIMESTAMP();
    SET v_capt_utc  = v_ahora_utc;
    IF p_capturado_utc IS NOT NULL AND p_capturado_utc >= v_ahora_utc - INTERVAL 24 HOUR AND p_capturado_utc <= v_ahora_utc + INTERVAL 5 MINUTE THEN
        SET v_capt_utc = LEAST(p_capturado_utc, v_ahora_utc);
    END IF;
    SET v_diferida = IF(v_capt_utc < v_ahora_utc - INTERVAL 2 MINUTE, 1, 0);
    SET v_t_utc    = IF(v_diferida = 1, v_capt_utc, v_ahora_utc);

    START TRANSACTION;

    -- La OS debe ser del técnico del token
    SELECT os.estado, os.numero INTO v_estado_os, v_numero_os
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

    -- El objetivo debe ser de esa OS (se bloquea la fila para que dos envíos no se pisen)
    SELECT oe.reanudado_utc INTO v_reanudado
    FROM   os_equipo oe
    WHERE  oe.id = p_id_os_equipo AND oe.id_os = p_id_os AND oe.eliminado_en IS NULL
    FOR UPDATE;
    IF NOT EXISTS (SELECT 1 FROM os_equipo oe WHERE oe.id = p_id_os_equipo AND oe.id_os = p_id_os AND oe.eliminado_en IS NULL) THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'El equipo no pertenece a este servicio.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Estado y permisos del objetivo: una sola vez, en SP_ArmarObjetivosMovil
    CALL SP_ArmarObjetivosMovil(p_id_os, v_estado_os, v_salida_utc, v_llegada_utc, v_habilitado, v_motivo_no);
    SELECT t.estado, t.puede_iniciar, t.puede_pausar, t.puede_reanudar, t.bloqueado, t.requiere_aprobacion,
           CONCAT(IFNULL(t.codigo_cliente, IFNULL(t.num_serie, t.codigo_tw)), ' · ', IFNULL(t.nombre, 'Equipo'))
    INTO   v_estado, v_p_iniciar, v_p_pausar, v_p_reanudar, v_bloqueado, v_req_aprob, v_nombre
    FROM   tmp_obj_mov t
    WHERE  t.id_os_equipo = p_id_os_equipo;
    DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;

    IF v_llegada_utc IS NULL OR v_habilitado = 0 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, v_motivo_no AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_estado IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'El equipo no forma parte de los objetivos de este servicio.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Validación por acción (idempotente: lo que ya está aplicado responde éxito)
    IF v_accion = 'iniciar' THEN
        IF v_estado = 'en_ejecucion' THEN
            SET v_repetida = 1;
        ELSEIF v_estado = 'completado' THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, 'Este equipo ya está completado.' AS Mensaje;
            LEAVE proc;
        ELSEIF v_estado = 'pausado' THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, 'El equipo está pausado: usa "Reanudar".' AS Mensaje;
            LEAVE proc;
        ELSEIF v_bloqueado = 1 THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, 'Este equipo está bloqueado y no se puede intervenir.' AS Mensaje;
            LEAVE proc;
        ELSEIF v_p_iniciar = 0 THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, 'No se puede iniciar el trabajo en este equipo.' AS Mensaje;
            LEAVE proc;
        END IF;
    ELSEIF v_accion = 'pausar' THEN
        IF v_estado = 'pausado' THEN
            SET v_repetida = 1;
        ELSEIF v_p_pausar = 0 THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, 'Solo se puede pausar un equipo que está en ejecución.' AS Mensaje;
            LEAVE proc;
        END IF;
    ELSE
        IF v_estado = 'en_ejecucion' THEN
            SET v_repetida = 1;
        ELSEIF v_estado = 'pausado' AND v_req_aprob = 1 THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, 'Esperando aprobación de supervisor: este equipo no se puede reanudar todavía.' AS Mensaje;
            LEAVE proc;
        ELSEIF v_p_reanudar = 0 THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, 'Solo se puede reanudar un equipo pausado.' AS Mensaje;
            LEAVE proc;
        END IF;
    END IF;

    -- Un técnico trabaja en un solo equipo a la vez
    IF v_repetida = 0 AND v_accion IN ('iniciar', 'reanudar') THEN
        SELECT CONCAT(IFNULL(NULLIF(ec.codigo_cliente, ''), ec.codigo_tw), ' (', o2.numero, ')') INTO v_otro
        FROM   os_equipo x
        JOIN   equipo_cliente ec ON ec.id_equipo = x.id_equipo
        JOIN   orden_servicio o2 ON o2.id_os = x.id_os
        WHERE  x.id_usuario_ejecucion = p_id_usuario AND x.estado_ejecucion = 'en_proceso' AND x.pausado = 0
          AND  x.id <> p_id_os_equipo AND x.eliminado_en IS NULL
        LIMIT 1;
        IF v_otro IS NOT NULL THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, CONCAT('Ya estás trabajando en el equipo ', v_otro, ': pausa ese equipo antes de continuar con otro.') AS Mensaje;
            LEAVE proc;
        END IF;
    END IF;

    IF v_repetida = 0 THEN
        SET v_nuevo = CASE v_accion WHEN 'pausar' THEN 'pausado' ELSE 'en_ejecucion' END;
        SET v_ant_txt = CASE v_estado WHEN 'por_iniciar' THEN 'por iniciar' WHEN 'en_ejecucion' THEN 'en ejecución' WHEN 'pausado' THEN 'pausado'
                                      WHEN 'observado' THEN 'observado' ELSE v_estado END;
        SET v_nue_txt = CASE v_nuevo WHEN 'pausado' THEN 'pausado' ELSE 'en ejecución' END;

        IF v_accion = 'iniciar' THEN
            UPDATE os_equipo
            SET    estado_ejecucion = 'en_proceso', iniciado_utc = IFNULL(iniciado_utc, v_t_utc), reanudado_utc = v_t_utc,
                   pausado = 0, motivo_pausa = NULL, pausa_requiere_aprobacion = 0, id_usuario_ejecucion = p_id_usuario, modificado_por = p_id_usuario
            WHERE  id = p_id_os_equipo;

            -- El primer equipo iniciado pone la OS "en ejecución" y marca el inicio del trabajo (lo lee la bandeja de seguimiento)
            IF v_estado_os = 'en_ruta' THEN
                UPDATE orden_servicio SET estado = 'en_ejecucion', modificado_por = p_id_usuario, modificado_en = NOW() WHERE id_os = p_id_os;
            END IF;
            SELECT IF(COUNT(*) > 0, 1, 0) INTO v_hay_inicio
            FROM   evento_campo e
            JOIN   tabla_maestra m ON m.IdMaestro = 29 AND m.IdEmpresa = 1 AND m.Num1 = e.id_tipo_evento AND m.String2 = 'INICIO_TRABAJO'
            WHERE  e.id_os = p_id_os AND e.eliminado_en IS NULL AND e.timestamp_utc >= IFNULL(v_salida_utc, '1000-01-01');
            SET v_cod_evt = IF(v_hay_inicio = 0, 'INICIO_TRABAJO', 'REANUDA');
        ELSEIF v_accion = 'pausar' THEN
            UPDATE os_equipo
            SET    acumulado_seg = acumulado_seg + IF(reanudado_utc IS NULL, 0, GREATEST(0, TIMESTAMPDIFF(SECOND, reanudado_utc, v_t_utc))),
                   reanudado_utc = NULL, pausado = 1, motivo_pausa = v_motivo, pausa_requiere_aprobacion = 0, modificado_por = p_id_usuario
            WHERE  id = p_id_os_equipo;
            SET v_cod_evt = 'PAUSA';
        ELSE
            UPDATE os_equipo
            SET    reanudado_utc = v_t_utc, pausado = 0, motivo_pausa = NULL, pausa_requiere_aprobacion = 0, id_usuario_ejecucion = p_id_usuario,
                   modificado_por = p_id_usuario
            WHERE  id = p_id_os_equipo;
            SET v_cod_evt = 'REANUDA';
        END IF;

        -- Evento de campo (la bandeja de seguimiento lo muestra en el timeline del día)
        SELECT m.Num1 INTO v_tipo_evt FROM tabla_maestra m
        WHERE  m.IdMaestro = 29 AND m.IdEmpresa = 1 AND m.String2 = v_cod_evt AND m.eliminado_en IS NULL LIMIT 1;
        IF v_tipo_evt IS NOT NULL THEN
            INSERT INTO evento_campo (id_os, id_usuario, id_tipo_evento, timestamp_utc, sincronizado, notas, creado_por)
            VALUES (p_id_os, p_id_usuario, v_tipo_evt, v_t_utc, 1,
                    LEFT(CONCAT(CASE v_accion WHEN 'iniciar' THEN 'Trabajo iniciado en ' WHEN 'pausar' THEN 'Pausa en ' ELSE 'Trabajo reanudado en ' END, v_nombre,
                                IF(v_accion = 'pausar', CONCAT('. Motivo: ', v_motivo), ''),
                                IF(v_diferida = 1, '. Registrado sin conexión y enviado después.', '')), 1000),
                    p_id_usuario);
        END IF;

        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
        VALUES ('os_equipo', p_id_os_equipo, CONCAT(v_accion, '_equipo'), v_ant_txt, v_nue_txt,
                LEFT(CASE v_accion WHEN 'iniciar' THEN 'Inicio' WHEN 'pausar' THEN CONCAT('Pausa: ', v_motivo) ELSE 'Reanudación' END, 300),
                p_id_usuario, NOW(),
                JSON_OBJECT('id_os', p_id_os, 'accion', v_accion, 'diferida', v_diferida = 1));
    END IF;

    COMMIT;

    SELECT 2 AS IdTipoMensaje,
           IF(v_repetida = 1, 'El equipo ya estaba en ese estado.',
              CASE v_accion WHEN 'iniciar' THEN 'Trabajo iniciado.' WHEN 'pausar' THEN 'Equipo pausado.' ELSE 'Trabajo reanudado.' END) AS Mensaje;
    SELECT p_id_os_equipo AS id_os_equipo, v_accion AS accion,
           IF(v_accion = 'pausar', 'pausado', 'en_ejecucion') AS estado, v_repetida AS repetida, v_diferida AS diferida;
END$$

DELIMITER ;
