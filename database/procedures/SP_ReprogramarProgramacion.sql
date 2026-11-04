-- HU-38 (Sprint 5) Reprogramar la Programación activa de una OS/OM.
-- Acceso: prog_gestionar. El circuito lo decide el SERVIDOR según el permiso del usuario del token (no lo elige el cliente):
--   · con prog_aprobar_reprogramacion (Jefe de Operaciones): EDICIÓN DIRECTA. Se aplican los cambios al instante, sin aprobación, y
--     queda en el historial firmada como "edición directa del Jefe". Si había una solicitud pendiente de esa programación, queda cancelada.
--   · sin ese permiso (Asistente): SOLICITUD DE REPROGRAMACIÓN pendiente (motivo y comentario obligatorios). La Programación NO se
--     congela: sigue tal cual hasta que el Jefe apruebe o rechace (SP_ResolverSolicitudReprogramacion). Solo una solicitud pendiente
--     por programación. Aquí solo se valida la forma; los cruces de horario y la SSOMA se validan al aprobar.
--   p_fecha, p_hora_inicio, p_hora_fin, p_id_tecnico, p_ids_apoyo (JSON [ids]), p_ids_equipos (JSON [ids]): NULL = se mantiene.
--   p_id_motivo: obligatorio, del catálogo MOTIVO_REPROGRAMACION (13). p_comentario: hasta 400; obligatorio en la solicitud.
-- Efecto del cambio sobre el estado: si cambia fecha u hora la programación VUELVE a 'pendiente_confirmacion' y hay que registrar de
-- nuevo la respuesta del cliente (HU-37); si cambia solo el técnico o los equipos el estado se mantiene.
-- Reglas de la edición directa: las mismas de SP_CrearProgramacion (fecha desde hoy, horas, técnicos programables, equipos de la OS,
--   sin cruces de horario, SSOMA conforme). Concurrencia: se bloquea primero a los técnicos (en orden de id), luego la OS y luego la
--   programación (mismo orden que SP_CrearProgramacion y SP_AnularOrdenServicio).
-- Resultados: 1 mensaje, 2 resultado (modo directa | solicitud).
DROP PROCEDURE IF EXISTS SP_ReprogramarProgramacion;

DELIMITER $$

CREATE PROCEDURE SP_ReprogramarProgramacion(
    IN p_id_usuario       BIGINT,
    IN p_id_programacion  BIGINT,
    IN p_fecha            DATE,
    IN p_hora_inicio      TIME,
    IN p_hora_fin         TIME,
    IN p_id_tecnico       BIGINT,
    IN p_ids_apoyo        JSON,
    IN p_ids_equipos      JSON,
    IN p_id_motivo        INT,
    IN p_comentario       VARCHAR(400) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_directa     TINYINT      DEFAULT 0;
    DECLARE v_comentario  VARCHAR(400) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_motivo      VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_os       BIGINT       DEFAULT NULL;
    DECLARE v_numero      VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tipo        VARCHAR(5)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_codigo      VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado_prg  VARCHAR(25)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado_os   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_fecha_act   DATE;
    DECLARE v_ini_act     TIME;
    DECLARE v_fin_act     TIME;
    DECLARE v_tec_act     BIGINT;
    DECLARE v_n_eq_act    INT          DEFAULT 0;
    DECLARE v_nom_tec_act VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_ids_bloqueo JSON;
    DECLARE v_ids_ahora   JSON;
    DECLARE v_i           INT          DEFAULT 0;
    DECLARE v_bloqueado   BIGINT       DEFAULT NULL;
    DECLARE v_error       VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_c_horario   TINYINT      DEFAULT 0;
    DECLARE v_c_tecnicos  TINYINT      DEFAULT 0;
    DECLARE v_c_equipos   TINYINT      DEFAULT 0;
    DECLARE v_pendiente   BIGINT       DEFAULT NULL;
    DECLARE v_id_solicitud BIGINT      DEFAULT NULL;
    DECLARE v_estado_nuevo VARCHAR(25) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_fecha_n     DATE;
    DECLARE v_ini_n       TIME;
    DECLARE v_fin_n       TIME;
    DECLARE v_tec_n       BIGINT;
    DECLARE v_nom_tec_n   VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_n_eq_n      INT          DEFAULT 0;
    DECLARE v_desc        VARCHAR(900) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cliente     VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_cliente  BIGINT       DEFAULT NULL;
    DECLARE v_apoyo_json  JSON;
    DECLARE v_equipos_json JSON;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            @err_msg  = MESSAGE_TEXT,
            @err_code = MYSQL_ERRNO;   -- primero: la limpieza de abajo genera notas que reemplazan el diagnóstico
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_prg_tec;
        DROP TEMPORARY TABLE IF EXISTS tmp_prg_eq;
        DROP TEMPORARY TABLE IF EXISTS tmp_ssoma_in;
        DROP TEMPORARY TABLE IF EXISTS tmp_apl_afectados;
        CALL SP_LimpiarSsomaProgramacion();
        IF @err_code IN (1213, 1205) THEN   -- interbloqueo / espera de bloqueo por otra operación simultánea: se reintenta
            SELECT 1 AS IdTipoMensaje, 'Otra persona está modificando esta programación en este momento. Inténtalo de nuevo.' AS Mensaje;
        ELSE
            SELECT 3 AS IdTipoMensaje,
                   CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
        END IF;
    END;

    -- ── Permiso y forma ──────────────────────────────────────────────────
    IF FN_PermisoAccion(p_id_usuario, 'prog_gestionar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para reprogramar servicios.' AS Mensaje;
        LEAVE proc;
    END IF;
    SET v_directa = IF(FN_PermisoAccion(p_id_usuario, 'prog_aprobar_reprogramacion') = 1, 1, 0);

    IF IFNULL(p_id_programacion, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Indica la programación a reprogramar.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_motivo = NULL;
    IF IFNULL(p_id_motivo, 0) > 0 THEN
        SELECT String1 INTO v_motivo FROM tabla_maestra
        WHERE IdMaestro = 13 AND IdEmpresa = 1 AND Num1 = p_id_motivo AND eliminado_en IS NULL;
    END IF;
    IF v_motivo IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Selecciona el motivo de la reprogramación.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_comentario = NULLIF(TRIM(IFNULL(p_comentario, '')), '');
    IF v_directa = 0 AND v_comentario IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Describe el contexto: el comentario es obligatorio en la solicitud al Jefe.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF (p_ids_apoyo IS NOT NULL AND JSON_TYPE(p_ids_apoyo) <> 'ARRAY')
       OR (p_ids_equipos IS NOT NULL AND JSON_TYPE(p_ids_equipos) <> 'ARRAY') THEN
        SELECT 1 AS IdTipoMensaje, 'Los técnicos de apoyo y los equipos deben enviarse como listas de identificadores.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- ── La programación existe (se vuelve a leer con bloqueo en la transacción) ──
    SELECT id_os INTO v_id_os FROM programacion WHERE id_programacion = p_id_programacion AND eliminado_en IS NULL;
    IF v_id_os IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'La programación no existe.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Listas normalizadas (sin repetidos ni ids inválidos) para guardarlas en la solicitud
    IF p_ids_apoyo IS NOT NULL THEN
        SET v_apoyo_json = (SELECT JSON_ARRAYAGG(x.id) FROM
                              (SELECT DISTINCT jt.id FROM JSON_TABLE(p_ids_apoyo, '$[*]' COLUMNS (id BIGINT PATH '$')) jt
                               WHERE jt.id IS NOT NULL AND jt.id > 0) x);
        SET v_apoyo_json = IFNULL(v_apoyo_json, JSON_ARRAY());
    END IF;
    IF p_ids_equipos IS NOT NULL THEN
        SET v_equipos_json = (SELECT JSON_ARRAYAGG(x.id) FROM
                              (SELECT DISTINCT jt.id FROM JSON_TABLE(p_ids_equipos, '$[*]' COLUMNS (id BIGINT PATH '$')) jt
                               WHERE jt.id IS NOT NULL AND jt.id > 0) x);
        SET v_equipos_json = IFNULL(v_equipos_json, JSON_ARRAY());
    END IF;

    -- ── Ids de los técnicos que quedarían (solo la edición directa los bloquea, por orden de id) ──
    IF v_directa = 1 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_prg_tec;
        CREATE TEMPORARY TABLE tmp_prg_tec (id_usuario BIGINT NOT NULL, PRIMARY KEY (id_usuario));
        INSERT IGNORE INTO tmp_prg_tec (id_usuario)
        SELECT IFNULL(p_id_tecnico, pr.id_tecnico_principal) FROM programacion pr WHERE pr.id_programacion = p_id_programacion;
        IF p_ids_apoyo IS NULL THEN
            INSERT IGNORE INTO tmp_prg_tec (id_usuario)
            SELECT id_usuario FROM programacion_tecnico
            WHERE id_programacion = p_id_programacion AND rol = 'apoyo' AND eliminado_en IS NULL;
        ELSE
            INSERT IGNORE INTO tmp_prg_tec (id_usuario)
            SELECT jt.id FROM JSON_TABLE(p_ids_apoyo, '$[*]' COLUMNS (id BIGINT PATH '$')) jt
            WHERE jt.id IS NOT NULL AND jt.id > 0;
        END IF;
        SET v_ids_bloqueo = CAST(CONCAT('[', IFNULL((SELECT GROUP_CONCAT(id_usuario ORDER BY id_usuario) FROM tmp_prg_tec), ''), ']') AS JSON);
        DROP TEMPORARY TABLE IF EXISTS tmp_prg_tec;

        IF JSON_LENGTH(v_ids_bloqueo) > 10 THEN
            SELECT 1 AS IdTipoMensaje, 'Una programación admite hasta 10 técnicos.' AS Mensaje;
            LEAVE proc;
        END IF;
    END IF;

    START TRANSACTION;

    -- ── Concurrencia: técnicos (en orden) → OS → programación ──────────
    IF v_directa = 1 THEN
        SET v_i = 0;
        WHILE v_i < JSON_LENGTH(v_ids_bloqueo) DO
            SELECT id_usuario INTO v_bloqueado
            FROM usuario
            WHERE id_usuario = CAST(JSON_EXTRACT(v_ids_bloqueo, CONCAT('$[', v_i, ']')) AS UNSIGNED)
            FOR UPDATE;
            SET v_i = v_i + 1;
        END WHILE;
    END IF;

    SELECT numero, tipo, estado, id_cliente
      INTO v_numero, v_tipo, v_estado_os, v_id_cliente
    FROM orden_servicio WHERE id_os = v_id_os AND eliminado_en IS NULL FOR UPDATE;

    SELECT codigo, estado, fecha_ejecucion, hora_inicio, hora_fin_estimada, id_tecnico_principal
      INTO v_codigo, v_estado_prg, v_fecha_act, v_ini_act, v_fin_act, v_tec_act
    FROM programacion WHERE id_programacion = p_id_programacion AND eliminado_en IS NULL FOR UPDATE;

    IF v_codigo IS NULL OR v_estado_prg = 'cancelada' THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, IF(v_codigo IS NULL, 'La programación no existe.', 'La programación está cancelada: ya no admite cambios.') AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT id_reprogramacion INTO v_pendiente
    FROM os_reprogramacion
    WHERE id_programacion = p_id_programacion AND estado = 'pendiente' AND eliminado_en IS NULL
    ORDER BY id_reprogramacion DESC LIMIT 1;

    -- ══════════════ ASISTENTE: solicitud de reprogramación ══════════════
    IF v_directa = 0 THEN
        IF v_pendiente IS NOT NULL THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje,
                   'Ya hay una solicitud de reprogramación pendiente para esta programación. Espera la decisión del Jefe o retírala.' AS Mensaje;
            LEAVE proc;
        END IF;

        CALL SP_AplicarCambiosProgramacion(p_id_usuario, p_id_programacion, p_fecha, p_hora_inicio, p_hora_fin,
                                           p_id_tecnico, p_ids_apoyo, p_ids_equipos, 0,
                                           v_error, v_c_horario, v_c_tecnicos, v_c_equipos);
        IF v_error IS NOT NULL THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, v_error AS Mensaje;
            LEAVE proc;
        END IF;

        INSERT INTO os_reprogramacion (id_os, id_programacion, id_solicitante, fecha_actual, hora_actual,
                                       fecha_propuesta, hora_propuesta, hora_fin_propuesta, id_tecnico_propuesto,
                                       ids_apoyo_propuestos, ids_equipos_propuestos, id_motivo, comentario, estado, creado_por)
        VALUES (v_id_os, p_id_programacion, p_id_usuario, v_fecha_act, v_ini_act,
                IFNULL(p_fecha, v_fecha_act), IFNULL(p_hora_inicio, v_ini_act), IFNULL(p_hora_fin, v_fin_act), p_id_tecnico,
                v_apoyo_json, v_equipos_json, p_id_motivo, v_comentario, 'pendiente', p_id_usuario);
        SET v_id_solicitud = LAST_INSERT_ID();

        SELECT razon_social INTO v_cliente FROM cliente WHERE id_cliente = v_id_cliente;

        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion,
                                      id_usuario, registrado_en, metadata)
        VALUES ('programacion', p_id_programacion, 'solicitar_reprogramacion', v_estado_prg, v_estado_prg,
                LEFT(CONCAT('Solicitud de reprogramación enviada al Jefe. Motivo: ', v_motivo, '. ', IFNULL(v_comentario, '')), 900),
                p_id_usuario, NOW(),
                JSON_OBJECT('idSolicitud', v_id_solicitud, 'idMotivo', p_id_motivo, 'motivo', v_motivo));

        INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
        SELECT u.id_usuario, 5, CONCAT('Solicitud de reprogramación: ', v_numero),
               LEFT(CONCAT('Hay una solicitud para reprogramar la ', v_tipo, ' ', v_numero, IF(v_cliente IS NULL, '', CONCAT(' de ', v_cliente)),
                           ' (', v_codigo, '). Motivo: ', v_motivo, '. Revísala y decide.'), 1000),
               'orden_servicio', v_id_os, NOW(), p_id_usuario
        FROM usuario u
        WHERE u.eliminado_en IS NULL AND u.estado = 'activo' AND u.id_usuario <> p_id_usuario AND u.area = 'operaciones'
          AND FN_PermisoAccion(u.id_usuario, 'prog_aprobar_reprogramacion') = 1;

        COMMIT;

        SELECT 2 AS IdTipoMensaje,
               'Solicitud de reprogramación enviada al Jefe. La programación sigue vigente hasta que él decida.' AS Mensaje;
        SELECT 'solicitud'                                  AS modo,
               v_id_solicitud                               AS id_solicitud,
               p_id_programacion                            AS id_programacion,
               v_codigo                                     AS codigo,
               v_estado_prg                                 AS estado,
               IF(v_estado_prg = 'confirmada', 'Programado', 'Pendiente confirmación cliente') AS estado_label,
               0                                            AS requiere_reconfirmar_cliente,
               v_c_horario                                  AS cambia_fecha_hora,
               v_c_tecnicos                                 AS cambia_tecnicos,
               v_c_equipos                                  AS cambia_equipos,
               v_fecha_act                                  AS fecha_ejecucion,
               TIME_FORMAT(v_ini_act, '%H:%i')              AS hora_inicio,
               TIME_FORMAT(v_fin_act, '%H:%i')              AS hora_fin;
        LEAVE proc;
    END IF;

    -- ══════════════ JEFE: edición directa ══════════════
    SELECT TRIM(CONCAT(nombre, ' ', apellido)) INTO v_nom_tec_act FROM usuario WHERE id_usuario = v_tec_act;
    SELECT COUNT(*) INTO v_n_eq_act FROM programacion_equipo WHERE id_programacion = p_id_programacion AND eliminado_en IS NULL;

    -- Los técnicos bloqueados deben ser exactamente los que quedan: si otra persona cambió la programación en el medio, se reintenta
    DROP TEMPORARY TABLE IF EXISTS tmp_prg_tec;
    CREATE TEMPORARY TABLE tmp_prg_tec (id_usuario BIGINT NOT NULL, PRIMARY KEY (id_usuario));
    INSERT IGNORE INTO tmp_prg_tec (id_usuario) VALUES (IFNULL(p_id_tecnico, v_tec_act));
    IF p_ids_apoyo IS NULL THEN
        INSERT IGNORE INTO tmp_prg_tec (id_usuario)
        SELECT id_usuario FROM programacion_tecnico WHERE id_programacion = p_id_programacion AND rol = 'apoyo' AND eliminado_en IS NULL;
    ELSE
        INSERT IGNORE INTO tmp_prg_tec (id_usuario)
        SELECT jt.id FROM JSON_TABLE(p_ids_apoyo, '$[*]' COLUMNS (id BIGINT PATH '$')) jt WHERE jt.id IS NOT NULL AND jt.id > 0;
    END IF;
    SET v_ids_ahora = CAST(CONCAT('[', IFNULL((SELECT GROUP_CONCAT(id_usuario ORDER BY id_usuario) FROM tmp_prg_tec), ''), ']') AS JSON);
    DROP TEMPORARY TABLE IF EXISTS tmp_prg_tec;
    IF v_ids_ahora <> v_ids_bloqueo THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'La programación cambió mientras se procesaba tu cambio. Vuelve a abrirla e inténtalo de nuevo.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_AplicarCambiosProgramacion(p_id_usuario, p_id_programacion, p_fecha, p_hora_inicio, p_hora_fin,
                                       p_id_tecnico, p_ids_apoyo, p_ids_equipos, 1,
                                       v_error, v_c_horario, v_c_tecnicos, v_c_equipos);
    IF v_error IS NOT NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, v_error AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT estado, fecha_ejecucion, hora_inicio, hora_fin_estimada, id_tecnico_principal
      INTO v_estado_nuevo, v_fecha_n, v_ini_n, v_fin_n, v_tec_n
    FROM programacion WHERE id_programacion = p_id_programacion;
    SELECT TRIM(CONCAT(nombre, ' ', apellido)) INTO v_nom_tec_n FROM usuario WHERE id_usuario = v_tec_n;
    SELECT COUNT(*) INTO v_n_eq_n FROM programacion_equipo WHERE id_programacion = p_id_programacion AND eliminado_en IS NULL;

    -- Descripción del cambio: solo lo que cambió
    SET v_desc = 'Edición directa del Jefe:';
    IF v_fecha_n <> v_fecha_act THEN
        SET v_desc = CONCAT(v_desc, ' fecha ', DATE_FORMAT(v_fecha_act, '%d/%m/%Y'), ' → ', DATE_FORMAT(v_fecha_n, '%d/%m/%Y'), ';');
    END IF;
    IF v_ini_n <> v_ini_act OR v_fin_n <> v_fin_act THEN
        SET v_desc = CONCAT(v_desc, ' horario ', TIME_FORMAT(v_ini_act, '%H:%i'), '-', TIME_FORMAT(v_fin_act, '%H:%i'), ' → ',
                            TIME_FORMAT(v_ini_n, '%H:%i'), '-', TIME_FORMAT(v_fin_n, '%H:%i'), ';');
    END IF;
    IF v_tec_n <> v_tec_act THEN
        SET v_desc = CONCAT(v_desc, ' técnico principal ', IFNULL(v_nom_tec_act, v_tec_act), ' → ', IFNULL(v_nom_tec_n, v_tec_n), ';');
    ELSEIF v_c_tecnicos = 1 THEN
        SET v_desc = CONCAT(v_desc, ' técnicos de apoyo;');
    END IF;
    IF v_c_equipos = 1 THEN
        SET v_desc = CONCAT(v_desc, ' equipos ', v_n_eq_act, ' → ', v_n_eq_n, ';');
    END IF;
    SET v_desc = CONCAT(v_desc, ' Motivo: ', v_motivo, '.', IFNULL(CONCAT(' Comentario: ', v_comentario, IF(RIGHT(v_comentario, 1) IN ('.', '!', '?'), '', '.')), ''),
                        IF(v_c_horario = 1, ' Pendiente de confirmación del cliente.', ''));

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion,
                                  id_usuario, registrado_en, metadata)
    VALUES ('programacion', p_id_programacion, 'reprogramacion_directa', v_estado_prg, v_estado_nuevo, LEFT(v_desc, 900),
            p_id_usuario, NOW(),
            JSON_OBJECT('idMotivo', p_id_motivo, 'motivo', v_motivo, 'cambiaFechaHora', v_c_horario,
                        'cambiaTecnicos', v_c_tecnicos, 'cambiaEquipos', v_c_equipos));

    -- Una solicitud pendiente queda sin efecto: el Jefe ya decidió por su cuenta
    UPDATE os_reprogramacion
    SET estado = 'cancelada', resuelto_por = p_id_usuario, fecha_resolucion = NOW(),
        comentario_resolucion = 'Reemplazada por la edición directa del Jefe.', modificado_por = p_id_usuario
    WHERE id_programacion = p_id_programacion AND estado = 'pendiente' AND eliminado_en IS NULL;

    SELECT razon_social INTO v_cliente FROM cliente WHERE id_cliente = v_id_cliente;

    INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
    SELECT a.id_usuario, 5,
           CONCAT(IF(a.situacion = 'quitado', 'Asignación retirada: ', 'Servicio reprogramado: '), v_numero),
           LEFT(CASE a.situacion
                    WHEN 'nuevo'   THEN CONCAT('Te asignaron la ', v_tipo, ' ', v_numero, IF(v_cliente IS NULL, '', CONCAT(' de ', v_cliente)),
                                               ' el ', DATE_FORMAT(v_fecha_n, '%d/%m/%Y'), ' de ', TIME_FORMAT(v_ini_n, '%H:%i'), ' a ',
                                               TIME_FORMAT(v_fin_n, '%H:%i'), '.')
                    WHEN 'quitado' THEN CONCAT('Ya no estás asignado a la ', v_tipo, ' ', v_numero, IF(v_cliente IS NULL, '', CONCAT(' de ', v_cliente)), '.')
                    ELSE CONCAT('Se reprogramó la ', v_tipo, ' ', v_numero, IF(v_cliente IS NULL, '', CONCAT(' de ', v_cliente)),
                                ': ', DATE_FORMAT(v_fecha_n, '%d/%m/%Y'), ' de ', TIME_FORMAT(v_ini_n, '%H:%i'), ' a ',
                                TIME_FORMAT(v_fin_n, '%H:%i'), '. Motivo: ', v_motivo, '.')
                END, 1000),
           'orden_servicio', v_id_os, NOW(), p_id_usuario
    FROM tmp_apl_afectados a
    WHERE a.id_usuario <> p_id_usuario;

    DROP TEMPORARY TABLE IF EXISTS tmp_apl_afectados;

    COMMIT;

    SELECT 2 AS IdTipoMensaje,
           IF(v_c_horario = 1, 'Programación reprogramada. Registra de nuevo la respuesta del cliente.', 'Programación actualizada.') AS Mensaje;
    SELECT 'directa'                                    AS modo,
           NULL                                         AS id_solicitud,
           p_id_programacion                            AS id_programacion,
           v_codigo                                     AS codigo,
           v_estado_nuevo                               AS estado,
           IF(v_estado_nuevo = 'confirmada', 'Programado', 'Pendiente confirmación cliente') AS estado_label,
           v_c_horario                                  AS requiere_reconfirmar_cliente,
           v_c_horario                                  AS cambia_fecha_hora,
           v_c_tecnicos                                 AS cambia_tecnicos,
           v_c_equipos                                  AS cambia_equipos,
           v_fecha_n                                    AS fecha_ejecucion,
           TIME_FORMAT(v_ini_n, '%H:%i')                AS hora_inicio,
           TIME_FORMAT(v_fin_n, '%H:%i')                AS hora_fin;
END$$

DELIMITER ;
