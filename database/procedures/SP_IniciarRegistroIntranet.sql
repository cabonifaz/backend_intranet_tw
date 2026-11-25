-- ============================================================
-- SP_IniciarRegistroIntranet  (HU-55 — "Comenzar registro" del informe de un equipo desde la intranet · escritura)
-- La Asistente de Seguimiento / el Jefe de Operaciones abren el registro del trabajo del técnico en un equipo cuando éste no puede usar el celular en planta.
-- Una sola transacción, con bloqueo en orden fijo (orden_servicio → os_equipo → registro_informe_intranet), que:
--   · valida el permiso (acción seg_registrar_informe), las horas, el motivo y el estado de la OS y del equipo;
--   · toma el bloqueo del equipo (registro_informe_intranet): si otra persona lo tiene con actividad en los últimos 30 min responde regla de negocio con el prefijo "[409] "
--     (la API lo convierte en HTTP 409); si su actividad es anterior a 30 min lo marca 'caducado' y lo toma;
--   · marca la LLEGADA del servicio (evento de campo con la hora de inicio, sin GPS) solo si falta, y el INICIO_TRABAJO solo si la OS aún no tiene uno (un INICIO posterior al CIERRE
--     haría que SP_ConsolidarHorasTecnicoMovil deje el día "sin cierre");
--   · pasa la OS de programada / reprogramada / en_ruta / pausada a en_ejecucion (SP_EvaluarCampoMovil solo deja operar en en_ruta, en_ejecucion o pausada);
--   · deja el equipo en proceso a nombre del técnico asignado (id_usuario_ejecucion) con el tiempo trabajado = fin − inicio (acumulado_seg) y reanudado_utc = NULL, para que
--     SP_GenerarInformeEquipoMovil (que suma ahora − reanudado_utc) no distorsione el tiempo real. Si el técnico ya había iniciado el equipo desde su app, se CONSERVA su iniciado_utc y se
--     suma su tramo en curso hasta la hora de fin (no se pisa lo que registró el técnico);
--   · guarda la sesión (horas indicadas, motivo del catálogo MOTIVO_CAMBIO_MANUAL, comentario) y la auditoría (equipo y expediente) con quién registró y en nombre de quién.
-- IDEMPOTENTE: si quien llama ya tiene el registro activo de ese equipo, solo renueva su actividad (idempotente = 1; no duplica eventos ni cambia los tiempos).
-- Horas: p_inicio_utc y p_fin_utc en UTC (la API recibe la hora de Lima y la convierte). Reglas: inicio < fin, fin no futuro (tolerancia de 5 min; se recorta a ahora), duración
--   mayor que 0 y menor de 7 días. Motivo obligatorio y del catálogo; con el motivo OTRO el comentario es obligatorio (mínimo 10 caracteres); comentario hasta 300.
-- Estados de la OS que NO permiten iniciar: anulada, borrador, emitida, bloqueada (SSOMA) y finalizada (pendiente de decisión). Del equipo: informe ya generado (usar el informe
--   complementario), completado, bloqueado, pausado esperando aprobación, fuera de los objetivos de la OS, o si el técnico tiene OTRO equipo en ejecución (pausarlo con
--   SP_PausarEquipoAbiertoIntranet).
-- Resultados: 1 mensaje (1 regla de negocio · 2 éxito · 3 error) · solo con 2: id_registro, idempotente, estado_os, estado_equipo, id_tecnico, tiempo_aplicado_min.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_IniciarRegistroIntranet;

DELIMITER $$

CREATE PROCEDURE SP_IniciarRegistroIntranet(
    IN p_id_registrador BIGINT,
    IN p_id_os          BIGINT,
    IN p_id_os_equipo   BIGINT,
    IN p_inicio_utc     DATETIME,
    IN p_fin_utc        DATETIME,
    IN p_motivo         VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_comentario     VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_ahora       DATETIME;
    DECLARE v_fin         DATETIME;
    DECLARE v_dur         BIGINT;
    DECLARE v_motivo_cod  VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_motivo_nom  VARCHAR(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_com         VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_estado_os   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_estado_nue  VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_estado_chk  VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_numero_os   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_tecnico     BIGINT       DEFAULT NULL;
    DECLARE v_exp         BIGINT       DEFAULT NULL;
    DECLARE v_id_equipo   BIGINT       DEFAULT NULL;
    DECLARE v_estado_ej   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_pausado     TINYINT      DEFAULT 0;
    DECLARE v_req_aprob   TINYINT      DEFAULT 0;
    DECLARE v_iniciado    DATETIME     DEFAULT NULL;
    DECLARE v_reanudado   DATETIME     DEFAULT NULL;
    DECLARE v_acum        INT          DEFAULT 0;
    DECLARE v_estado_eq   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_ant_txt     VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_reg_id      BIGINT       DEFAULT NULL;
    DECLARE v_reg_user    BIGINT       DEFAULT NULL;
    DECLARE v_reg_act     DATETIME     DEFAULT NULL;
    DECLARE v_reg_seg     INT          DEFAULT NULL;
    DECLARE v_reg_nombre  VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_asistente   VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_nom_tec     VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_nom_eq      VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_informe     BIGINT       DEFAULT NULL;
    DECLARE v_gen         DATETIME     DEFAULT NULL;
    DECLARE v_salida      DATETIME     DEFAULT NULL;
    DECLARE v_llegada     DATETIME     DEFAULT NULL;
    DECLARE v_hab         TINYINT      DEFAULT 0;
    DECLARE v_motivo_obj  VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_bloqueado   TINYINT      DEFAULT NULL;
    DECLARE v_otro        VARCHAR(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_tipo_lleg   INT          DEFAULT NULL;
    DECLARE v_tipo_ini    INT          DEFAULT NULL;
    DECLARE v_t_lleg      DATETIME;
    DECLARE v_hay_inicio  TINYINT      DEFAULT 0;
    DECLARE v_tiempo_seg  INT          DEFAULT 0;
    DECLARE v_id_reg      BIGINT       DEFAULT NULL;
    DECLARE v_notas       VARCHAR(1000) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_ini_txt     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_fin_txt     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    -- ── Validaciones de entrada (antes de tocar datos) ───────────────────────────────────
    IF IFNULL(p_id_registrador, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 OR IFNULL(p_id_os_equipo, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio o equipo no encontrado.' AS Mensaje; LEAVE proc;
    END IF;
    IF FN_PermisoAccion(p_id_registrador, 'seg_registrar_informe') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para registrar informes desde la intranet.' AS Mensaje; LEAVE proc;
    END IF;
    IF p_inicio_utc IS NULL OR p_fin_utc IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Indica la hora de inicio y la de fin del trabajo en el equipo.' AS Mensaje; LEAVE proc;
    END IF;

    SET v_ahora = UTC_TIMESTAMP();
    IF p_fin_utc > v_ahora + INTERVAL 5 MINUTE THEN
        SELECT 1 AS IdTipoMensaje, 'La hora de fin no puede ser futura.' AS Mensaje; LEAVE proc;
    END IF;
    SET v_fin = LEAST(p_fin_utc, v_ahora);
    IF p_inicio_utc >= v_fin THEN
        SELECT 1 AS IdTipoMensaje, 'La hora de inicio debe ser anterior a la de fin.' AS Mensaje; LEAVE proc;
    END IF;
    SET v_dur = TIMESTAMPDIFF(SECOND, p_inicio_utc, v_fin);
    IF v_dur >= 7 * 86400 THEN
        SELECT 1 AS IdTipoMensaje, 'El trabajo en el equipo no puede durar 7 días o más.' AS Mensaje; LEAVE proc;
    END IF;

    IF NULLIF(TRIM(IFNULL(p_motivo, '')), '') IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Elige el motivo por el que se registra desde la intranet.' AS Mensaje; LEAVE proc;
    END IF;
    SELECT m.String2, m.String1 INTO v_motivo_cod, v_motivo_nom
    FROM   tabla_maestra m
    WHERE  m.Descripcion = 'MOTIVO_CAMBIO_MANUAL' AND m.IdEmpresa = 1 AND m.String2 = TRIM(p_motivo) AND m.eliminado_en IS NULL
    LIMIT 1;
    IF v_motivo_cod IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'El motivo no es válido.' AS Mensaje; LEAVE proc;
    END IF;
    SET v_com = NULLIF(TRIM(IFNULL(p_comentario, '')), '');
    IF CHAR_LENGTH(IFNULL(p_comentario, '')) > 300 THEN
        SELECT 1 AS IdTipoMensaje, 'El comentario puede tener hasta 300 caracteres.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_motivo_cod = 'OTRO' AND (v_com IS NULL OR CHAR_LENGTH(v_com) < 10) THEN
        SELECT 1 AS IdTipoMensaje, 'Cuando el motivo es "Otro" escribe un comentario (mínimo 10 caracteres).' AS Mensaje; LEAVE proc;
    END IF;

    -- ── Escritura (una transacción) ──────────────────────────────────────────────────────
    START TRANSACTION;

    SELECT os.estado, os.numero, os.id_tecnico_principal, os.id_expediente INTO v_estado_os, v_numero_os, v_tecnico, v_exp
    FROM   orden_servicio os
    WHERE  os.id_os = p_id_os AND os.eliminado_en IS NULL
    FOR UPDATE;
    IF v_estado_os IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Servicio no encontrado.' AS Mensaje; LEAVE proc;
    END IF;

    SELECT oe.id_equipo, oe.estado_ejecucion, oe.pausado, oe.pausa_requiere_aprobacion, oe.iniciado_utc, oe.reanudado_utc, oe.acumulado_seg
    INTO   v_id_equipo, v_estado_ej, v_pausado, v_req_aprob, v_iniciado, v_reanudado, v_acum
    FROM   os_equipo oe
    WHERE  oe.id = p_id_os_equipo AND oe.id_os = p_id_os AND oe.eliminado_en IS NULL
    FOR UPDATE;
    IF v_id_equipo IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'El equipo no pertenece a este servicio.' AS Mensaje; LEAVE proc;
    END IF;

    -- Estado actual del equipo (la misma lectura que SP_ArmarObjetivosMovil)
    SET v_estado_eq = CASE WHEN v_estado_ej = 'ejecutado' THEN 'completado' WHEN v_pausado = 1 THEN 'pausado' WHEN v_estado_ej = 'observado' THEN 'observado'
                           WHEN v_estado_ej = 'en_proceso' THEN 'en_ejecucion' ELSE 'por_iniciar' END;
    SET v_ant_txt = CASE v_estado_eq WHEN 'por_iniciar' THEN 'por iniciar' WHEN 'en_ejecucion' THEN 'en ejecución' ELSE v_estado_eq END;

    SELECT TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))) INTO v_asistente FROM usuario u WHERE u.id_usuario = p_id_registrador LIMIT 1;

    -- Bloqueo del equipo: una sesión activa por equipo
    SELECT r.id_registro, r.id_registrador, r.ultima_actividad, r.tiempo_aplicado_seg INTO v_reg_id, v_reg_user, v_reg_act, v_reg_seg
    FROM   registro_informe_intranet r
    WHERE  r.id_os_equipo = p_id_os_equipo AND r.estado = 'activo'
    ORDER BY r.id_registro DESC LIMIT 1
    FOR UPDATE;
    IF v_reg_id IS NOT NULL THEN
        IF v_reg_user = p_id_registrador THEN
            -- Idempotente: ya lo tenía abierto; solo se renueva la actividad
            UPDATE registro_informe_intranet SET ultima_actividad = v_ahora WHERE id_registro = v_reg_id;
            COMMIT;
            SELECT 2 AS IdTipoMensaje, 'Ya tenías abierto el registro de este equipo.' AS Mensaje;
            SELECT v_reg_id AS id_registro, 1 AS idempotente, v_estado_os AS estado_os, v_estado_eq AS estado_equipo, v_tecnico AS id_tecnico,
                   FLOOR(IFNULL(v_reg_seg, 0) / 60) AS tiempo_aplicado_min;
            LEAVE proc;
        ELSEIF v_reg_act >= v_ahora - INTERVAL 30 MINUTE THEN
            SELECT TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))) INTO v_reg_nombre FROM usuario u WHERE u.id_usuario = v_reg_user LIMIT 1;
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje,
                   CONCAT('[409] ', IFNULL(NULLIF(v_reg_nombre, ''), 'Otra persona'), ' está registrando el informe de este equipo. Inténtalo cuando termine o pasen 30 minutos sin actividad.') AS Mensaje;
            LEAVE proc;
        ELSE
            -- La sesión de la otra persona caducó (más de 30 min sin actividad): se libera y se toma
            UPDATE registro_informe_intranet SET estado = 'caducado', liberado_en = v_ahora WHERE id_registro = v_reg_id;
        END IF;
    END IF;

    -- Reglas del servicio y del equipo
    IF v_tecnico IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'El servicio no tiene un técnico asignado.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_estado_os = 'finalizada' THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'La OS ya está finalizada: esta función aún no cubre ese caso.' AS Mensaje; LEAVE proc;
    ELSEIF v_estado_os = 'anulada' THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'La OS está anulada.' AS Mensaje; LEAVE proc;
    ELSEIF v_estado_os = 'bloqueada' THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'La OS está bloqueada por SSOMA.' AS Mensaje; LEAVE proc;
    ELSEIF v_estado_os IN ('borrador', 'emitida') THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'La OS todavía no está programada ni tiene técnico asignado.' AS Mensaje; LEAVE proc;
    ELSEIF v_estado_os NOT IN ('programada', 'reprogramada', 'en_ruta', 'en_ejecucion', 'pausada') THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'El estado de la OS no permite registrar el informe.' AS Mensaje; LEAVE proc;
    END IF;

    SELECT it.id_informe, it.generado_en INTO v_informe, v_gen
    FROM   informe_tecnico it
    WHERE  it.id_os = p_id_os AND it.id_equipo = v_id_equipo AND it.eliminado_en IS NULL
    ORDER BY it.id_informe DESC LIMIT 1;
    IF v_gen IS NOT NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Este equipo ya tiene el informe generado. Para corregirlo usa el informe complementario.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_estado_eq = 'completado' THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Este equipo ya está completado.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_estado_eq = 'pausado' AND v_req_aprob = 1 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'El equipo está pausado esperando la aprobación de un supervisor.' AS Mensaje; LEAVE proc;
    END IF;

    -- Objetivos de la OS: el equipo debe ser uno de ellos y no estar bloqueado (inactivo o en evaluación). También da la llegada y la salida de la OS.
    CALL SP_ArmarObjetivosMovil(p_id_os, v_estado_chk, v_salida, v_llegada, v_hab, v_motivo_obj);
    SELECT t.bloqueado, CONCAT(IFNULL(t.codigo_cliente, IFNULL(t.num_serie, t.codigo_tw)), ' · ', IFNULL(t.nombre, 'Equipo'))
    INTO   v_bloqueado, v_nom_eq
    FROM   tmp_obj_mov t
    WHERE  t.id_os_equipo = p_id_os_equipo;
    DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
    IF v_bloqueado IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'El equipo no forma parte de los objetivos de este servicio.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_bloqueado = 1 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Este equipo está bloqueado y no se puede intervenir.' AS Mensaje; LEAVE proc;
    END IF;

    -- Un técnico trabaja en un solo equipo a la vez (la misma regla que SP_CambiarEstadoEquipoMovil)
    SELECT CONCAT(IFNULL(NULLIF(ec.codigo_cliente, ''), ec.codigo_tw), ' (', o2.numero, ')') INTO v_otro
    FROM   os_equipo x
    JOIN   equipo_cliente ec ON ec.id_equipo = x.id_equipo
    JOIN   orden_servicio o2 ON o2.id_os = x.id_os
    WHERE  x.id_usuario_ejecucion = v_tecnico AND x.estado_ejecucion = 'en_proceso' AND x.pausado = 0
      AND  x.id <> p_id_os_equipo AND x.eliminado_en IS NULL
    LIMIT 1;
    IF v_otro IS NOT NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje,
               CONCAT('El técnico ya tiene en ejecución el equipo ', v_otro, ': pausa ese equipo antes de continuar con otro.') AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))) INTO v_nom_tec FROM usuario u WHERE u.id_usuario = v_tecnico LIMIT 1;
    SET v_ini_txt = DATE_FORMAT(CONVERT_TZ(p_inicio_utc, '+00:00', '-05:00'), '%d/%m/%Y %H:%i');
    SET v_fin_txt = DATE_FORMAT(CONVERT_TZ(v_fin, '+00:00', '-05:00'), '%d/%m/%Y %H:%i');
    SET v_notas = LEFT(CONCAT('Registrado desde la intranet por ', IFNULL(v_asistente, ''), ' en nombre de ', IFNULL(v_nom_tec, ''), '. Motivo: ', v_motivo_nom,
                              IF(v_com IS NULL, '', CONCAT('. ', v_com))), 1000);

    -- LLEGADA: solo si falta (SP_EvaluarCampoMovil exige una LLEGADA posterior a la última SALIDA_BASE). Sin GPS.
    IF v_llegada IS NULL THEN
        SELECT m.Num1 INTO v_tipo_lleg FROM tabla_maestra m
        WHERE  m.IdMaestro = 29 AND m.IdEmpresa = 1 AND m.String2 = 'LLEGADA' AND m.eliminado_en IS NULL LIMIT 1;
        IF v_tipo_lleg IS NULL THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, 'El hito de campo LLEGADA no está configurado.' AS Mensaje; LEAVE proc;
        END IF;
        SET v_t_lleg = GREATEST(p_inicio_utc, IFNULL(v_salida, p_inicio_utc));
        INSERT INTO evento_campo (id_os, id_usuario, id_tipo_evento, timestamp_utc, sincronizado, notas, creado_por)
        VALUES (p_id_os, v_tecnico, v_tipo_lleg, v_t_lleg, 1, v_notas, p_id_registrador);
        UPDATE orden_servicio SET hora_llegada_real = IFNULL(hora_llegada_real, TIME(CONVERT_TZ(v_t_lleg, '+00:00', '-05:00'))) WHERE id_os = p_id_os;
    END IF;

    -- INICIO_TRABAJO: solo si la OS aún no tiene uno desde la última salida
    SELECT IF(COUNT(*) > 0, 1, 0) INTO v_hay_inicio
    FROM   evento_campo e
    JOIN   tabla_maestra m ON m.IdMaestro = 29 AND m.IdEmpresa = 1 AND m.Num1 = e.id_tipo_evento AND m.String2 = 'INICIO_TRABAJO'
    WHERE  e.id_os = p_id_os AND e.eliminado_en IS NULL AND e.timestamp_utc >= IFNULL(v_salida, '1000-01-01');
    IF v_hay_inicio = 0 THEN
        SELECT m.Num1 INTO v_tipo_ini FROM tabla_maestra m
        WHERE  m.IdMaestro = 29 AND m.IdEmpresa = 1 AND m.String2 = 'INICIO_TRABAJO' AND m.eliminado_en IS NULL LIMIT 1;
        IF v_tipo_ini IS NOT NULL THEN
            INSERT INTO evento_campo (id_os, id_usuario, id_tipo_evento, timestamp_utc, sincronizado, notas, creado_por)
            VALUES (p_id_os, v_tecnico, v_tipo_ini, p_inicio_utc, 1, v_notas, p_id_registrador);
        END IF;
    END IF;

    -- La OS pasa a "en ejecución" (SP_EvaluarCampoMovil solo deja operar en en_ruta, en_ejecucion o pausada)
    SET v_estado_nue = v_estado_os;
    IF v_estado_os IN ('programada', 'reprogramada', 'en_ruta', 'pausada') THEN
        SET v_estado_nue = 'en_ejecucion';
        UPDATE orden_servicio SET estado = 'en_ejecucion', modificado_por = p_id_registrador, modificado_en = NOW() WHERE id_os = p_id_os;
    END IF;

    -- El equipo: en proceso a nombre del técnico, con el tiempo trabajado cerrado (reanudado_utc = NULL: el generar del informe no suma nada)
    IF v_iniciado IS NULL THEN
        SET v_tiempo_seg = v_dur;
    ELSE
        SET v_tiempo_seg = v_acum + IF(v_reanudado IS NULL, 0, GREATEST(0, TIMESTAMPDIFF(SECOND, v_reanudado, v_fin)));
    END IF;
    UPDATE os_equipo
    SET    estado_ejecucion = 'en_proceso', iniciado_utc = IFNULL(iniciado_utc, p_inicio_utc), acumulado_seg = v_tiempo_seg, reanudado_utc = NULL,
           pausado = 0, motivo_pausa = NULL, pausa_requiere_aprobacion = 0, id_usuario_ejecucion = v_tecnico, modificado_por = p_id_registrador
    WHERE  id = p_id_os_equipo;

    -- La sesión (el bloqueo) con las horas y el motivo
    INSERT INTO registro_informe_intranet (id_os, id_os_equipo, id_tecnico, id_registrador, inicio_utc, fin_utc, tiempo_aplicado_seg, motivo_codigo, comentario,
                                           estado, tomado_en, ultima_actividad)
    VALUES (p_id_os, p_id_os_equipo, v_tecnico, p_id_registrador, p_inicio_utc, v_fin, v_tiempo_seg, v_motivo_cod, v_com, 'activo', v_ahora, v_ahora);
    SET v_id_reg = LAST_INSERT_ID();

    -- Auditoría: quién registró, en nombre de quién y con qué horas, en el equipo y en el historial del expediente
    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('os_equipo', p_id_os_equipo, 'iniciar_registro_intranet', v_ant_txt, 'en ejecución',
            LEFT(CONCAT(IFNULL(v_asistente, ''), ' inició desde la intranet el registro del informe de ', IFNULL(v_nom_eq, 'un equipo'), ' (', v_numero_os, ') en nombre de ',
                        IFNULL(v_nom_tec, ''), '. Trabajo del ', v_ini_txt, ' al ', v_fin_txt, ' (hora de Lima). Motivo: ', v_motivo_nom, '.'), 900),
            p_id_registrador, NOW(),
            JSON_OBJECT('idRegistro', v_id_reg, 'via', 'intranet', 'idTecnico', v_tecnico, 'idOs', p_id_os, 'inicioLima', v_ini_txt, 'finLima', v_fin_txt,
                        'motivo', v_motivo_cod, 'tiempoAplicadoSeg', v_tiempo_seg, 'estadoOsAnterior', v_estado_os));
    IF v_exp IS NOT NULL THEN
        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
        VALUES ('expediente', v_exp, 'iniciar_registro_intranet', NULL, NULL,
                LEFT(CONCAT(IFNULL(v_asistente, ''), ' inició el registro del informe de ', IFNULL(v_nom_eq, 'un equipo'), ' del servicio ', v_numero_os, ' en nombre de ',
                            IFNULL(v_nom_tec, ''), '. Motivo: ', v_motivo_nom, '.'), 900),
                p_id_registrador, NOW(), JSON_OBJECT('idRegistro', v_id_reg, 'idOs', p_id_os, 'idOsEquipo', p_id_os_equipo));
    END IF;

    COMMIT;

    SELECT 2 AS IdTipoMensaje, 'Registro iniciado.' AS Mensaje;
    SELECT v_id_reg AS id_registro, 0 AS idempotente, v_estado_nue AS estado_os, 'en_ejecucion' AS estado_equipo, v_tecnico AS id_tecnico,
           FLOOR(v_tiempo_seg / 60) AS tiempo_aplicado_min;
END$$

DELIMITER ;
