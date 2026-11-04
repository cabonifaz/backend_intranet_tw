-- HU-38 (Sprint 5) El Jefe de Operaciones aprueba o rechaza una solicitud de reprogramación del Asistente.
-- Acceso: prog_aprobar_reprogramacion (jefe).
--   p_decision: 'aprobar' | 'rechazar'. p_comentario: hasta 500; OBLIGATORIO al rechazar (queda en el historial como motivo del rechazo).
-- Aprobar: se aplican los cambios propuestos con las mismas validaciones de SP_CrearProgramacion (cruces de horario y SSOMA con la
--   nueva fecha; si algo ya no se cumple devuelve el motivo y la solicitud sigue pendiente). Si cambia fecha u hora la programación
--   VUELVE a 'pendiente_confirmacion' (hay que re-registrar la respuesta del cliente, HU-37); si cambia solo técnico o equipos el estado
--   se mantiene. Se avisa al Asistente y a los técnicos afectados.
-- Rechazar: la programación sigue tal cual estaba. Se avisa al Asistente.
-- Una solicitud ya resuelta (o cancelada) no se vuelve a resolver. Dos jefes resolviendo a la vez: gana uno, el otro ve la solicitud resuelta.
-- Concurrencia: técnicos (en orden de id) → OS → programación → solicitud. Resultados: 1 mensaje, 2 resultado.
DROP PROCEDURE IF EXISTS SP_ResolverSolicitudReprogramacion;

DELIMITER $$

CREATE PROCEDURE SP_ResolverSolicitudReprogramacion(
    IN p_id_usuario    BIGINT,
    IN p_id_solicitud  BIGINT,
    IN p_decision      VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_comentario    VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_decision    VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_comentario  VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_os       BIGINT       DEFAULT NULL;
    DECLARE v_id_prog     BIGINT       DEFAULT NULL;
    DECLARE v_estado_sol  VARCHAR(12)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_solicitante BIGINT       DEFAULT NULL;
    DECLARE v_id_motivo   INT          DEFAULT NULL;
    DECLARE v_motivo      VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_p_fecha     DATE;
    DECLARE v_p_ini       TIME;
    DECLARE v_p_fin       TIME;
    DECLARE v_p_tec       BIGINT;
    DECLARE v_p_apoyo     JSON;
    DECLARE v_p_equipos   JSON;
    DECLARE v_numero      VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tipo        VARCHAR(5)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_cliente  BIGINT       DEFAULT NULL;
    DECLARE v_cliente     VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_codigo      VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado_prg  VARCHAR(25)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_fecha_act   DATE;
    DECLARE v_ini_act     TIME;
    DECLARE v_fin_act     TIME;
    DECLARE v_tec_act     BIGINT;
    DECLARE v_nom_tec_act VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_n_eq_act    INT          DEFAULT 0;
    DECLARE v_ids_bloqueo JSON;
    DECLARE v_ids_ahora   JSON;
    DECLARE v_i           INT          DEFAULT 0;
    DECLARE v_bloqueado   BIGINT       DEFAULT NULL;
    DECLARE v_error       VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_c_horario   TINYINT      DEFAULT 0;
    DECLARE v_c_tecnicos  TINYINT      DEFAULT 0;
    DECLARE v_c_equipos   TINYINT      DEFAULT 0;
    DECLARE v_estado_nuevo VARCHAR(25) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_fecha_n     DATE;
    DECLARE v_ini_n       TIME;
    DECLARE v_fin_n       TIME;
    DECLARE v_tec_n       BIGINT;
    DECLARE v_nom_tec_n   VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_n_eq_n      INT          DEFAULT 0;
    DECLARE v_desc        VARCHAR(900) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_jefe        VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

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

    IF FN_PermisoAccion(p_id_usuario, 'prog_aprobar_reprogramacion') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Solo el Jefe de Operaciones puede aprobar o rechazar solicitudes de reprogramación.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_decision = LOWER(TRIM(IFNULL(p_decision, '')));
    IF v_decision NOT IN ('aprobar', 'rechazar') THEN
        SELECT 1 AS IdTipoMensaje, 'La decisión debe ser aprobar o rechazar.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_comentario = NULLIF(TRIM(IFNULL(p_comentario, '')), '');
    IF v_decision = 'rechazar' AND v_comentario IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Indica el motivo del rechazo: queda registrado en el historial.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF IFNULL(p_id_solicitud, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'La solicitud de reprogramación no existe.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- ── Lectura previa (sin bloqueo) para saber qué bloquear ─────────────
    SELECT rp.id_os, IFNULL(rp.id_programacion, (SELECT MAX(pr.id_programacion) FROM programacion pr
                                                  WHERE pr.id_os = rp.id_os AND pr.estado <> 'cancelada' AND pr.eliminado_en IS NULL))
      INTO v_id_os, v_id_prog
    FROM os_reprogramacion rp WHERE rp.id_reprogramacion = p_id_solicitud AND rp.eliminado_en IS NULL;

    IF v_id_os IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'La solicitud de reprogramación no existe.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_id_prog IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'La solicitud no corresponde a una programación vigente.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF v_decision = 'aprobar' THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_prg_tec;
        CREATE TEMPORARY TABLE tmp_prg_tec (id_usuario BIGINT NOT NULL, PRIMARY KEY (id_usuario));
        INSERT IGNORE INTO tmp_prg_tec (id_usuario)
        SELECT IFNULL(rp.id_tecnico_propuesto, pr.id_tecnico_principal)
        FROM os_reprogramacion rp JOIN programacion pr ON pr.id_programacion = v_id_prog
        WHERE rp.id_reprogramacion = p_id_solicitud;
        INSERT IGNORE INTO tmp_prg_tec (id_usuario)
        SELECT jt.id
        FROM os_reprogramacion rp
        JOIN JSON_TABLE(rp.ids_apoyo_propuestos, '$[*]' COLUMNS (id BIGINT PATH '$')) jt
        WHERE rp.id_reprogramacion = p_id_solicitud AND rp.ids_apoyo_propuestos IS NOT NULL AND jt.id IS NOT NULL AND jt.id > 0;
        INSERT IGNORE INTO tmp_prg_tec (id_usuario)
        SELECT pt.id_usuario
        FROM os_reprogramacion rp
        JOIN programacion_tecnico pt ON pt.id_programacion = v_id_prog AND pt.rol = 'apoyo' AND pt.eliminado_en IS NULL
        WHERE rp.id_reprogramacion = p_id_solicitud AND rp.ids_apoyo_propuestos IS NULL;
        SET v_ids_bloqueo = CAST(CONCAT('[', IFNULL((SELECT GROUP_CONCAT(id_usuario ORDER BY id_usuario) FROM tmp_prg_tec), ''), ']') AS JSON);
        DROP TEMPORARY TABLE IF EXISTS tmp_prg_tec;
    END IF;

    START TRANSACTION;

    IF v_decision = 'aprobar' THEN
        SET v_i = 0;
        WHILE v_i < JSON_LENGTH(v_ids_bloqueo) DO
            SELECT id_usuario INTO v_bloqueado
            FROM usuario
            WHERE id_usuario = CAST(JSON_EXTRACT(v_ids_bloqueo, CONCAT('$[', v_i, ']')) AS UNSIGNED)
            FOR UPDATE;
            SET v_i = v_i + 1;
        END WHILE;
    END IF;

    SELECT numero, tipo, id_cliente INTO v_numero, v_tipo, v_id_cliente
    FROM orden_servicio WHERE id_os = v_id_os AND eliminado_en IS NULL FOR UPDATE;

    SELECT codigo, estado, fecha_ejecucion, hora_inicio, hora_fin_estimada, id_tecnico_principal
      INTO v_codigo, v_estado_prg, v_fecha_act, v_ini_act, v_fin_act, v_tec_act
    FROM programacion WHERE id_programacion = v_id_prog AND eliminado_en IS NULL FOR UPDATE;

    SELECT rp.estado, rp.id_solicitante, rp.id_motivo, rp.fecha_propuesta, rp.hora_propuesta, rp.hora_fin_propuesta,
           rp.id_tecnico_propuesto, rp.ids_apoyo_propuestos, rp.ids_equipos_propuestos
      INTO v_estado_sol, v_solicitante, v_id_motivo, v_p_fecha, v_p_ini, v_p_fin, v_p_tec, v_p_apoyo, v_p_equipos
    FROM os_reprogramacion rp WHERE rp.id_reprogramacion = p_id_solicitud AND rp.eliminado_en IS NULL FOR UPDATE;

    IF v_estado_sol IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'La solicitud de reprogramación no existe.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_estado_sol <> 'pendiente' THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, CONCAT('La solicitud ya fue resuelta: está ', v_estado_sol, '.') AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_codigo IS NULL OR v_estado_prg = 'cancelada' THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'La programación ya no está vigente: la solicitud no se puede resolver.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT String1 INTO v_motivo FROM tabla_maestra
    WHERE IdMaestro = 13 AND IdEmpresa = 1 AND Num1 = v_id_motivo AND eliminado_en IS NULL;
    SELECT TRIM(CONCAT(nombre, ' ', apellido)) INTO v_jefe FROM usuario WHERE id_usuario = p_id_usuario;
    SELECT razon_social INTO v_cliente FROM cliente WHERE id_cliente = v_id_cliente;

    -- ══════════════ RECHAZAR ══════════════
    IF v_decision = 'rechazar' THEN
        UPDATE os_reprogramacion
        SET estado = 'rechazada', resuelto_por = p_id_usuario, fecha_resolucion = NOW(),
            comentario_resolucion = v_comentario, modificado_por = p_id_usuario
        WHERE id_reprogramacion = p_id_solicitud;

        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion,
                                      id_usuario, registrado_en, metadata)
        VALUES ('programacion', v_id_prog, 'rechazar_reprogramacion', v_estado_prg, v_estado_prg,
                LEFT(CONCAT('Solicitud de reprogramación rechazada por el Jefe. Motivo del rechazo: ', v_comentario), 900),
                p_id_usuario, NOW(), JSON_OBJECT('idSolicitud', p_id_solicitud, 'motivo', v_comentario, 'motivoSolicitud', v_motivo));

        IF v_solicitante IS NOT NULL AND v_solicitante <> p_id_usuario THEN
            INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
            VALUES (v_solicitante, 5, CONCAT('Reprogramación rechazada: ', v_numero),
                    LEFT(CONCAT('El Jefe rechazó tu solicitud de reprogramar la ', v_tipo, ' ', v_numero, ' (', v_codigo,
                                '). Motivo: ', v_comentario), 1000),
                    'orden_servicio', v_id_os, NOW(), p_id_usuario);
        END IF;

        COMMIT;

        SELECT 2 AS IdTipoMensaje, 'Solicitud rechazada. La programación sigue como estaba.' AS Mensaje;
        SELECT p_id_solicitud AS id_solicitud, 'rechazada' AS estado_solicitud, v_id_prog AS id_programacion, v_codigo AS codigo,
               v_estado_prg AS estado, IF(v_estado_prg = 'confirmada', 'Programado', 'Pendiente confirmación cliente') AS estado_label,
               0 AS requiere_reconfirmar_cliente;
        LEAVE proc;
    END IF;

    -- ══════════════ APROBAR ══════════════
    -- Los técnicos bloqueados deben ser los que quedan: si la programación cambió en el medio, se reintenta
    DROP TEMPORARY TABLE IF EXISTS tmp_prg_tec;
    CREATE TEMPORARY TABLE tmp_prg_tec (id_usuario BIGINT NOT NULL, PRIMARY KEY (id_usuario));
    INSERT IGNORE INTO tmp_prg_tec (id_usuario) VALUES (IFNULL(v_p_tec, v_tec_act));
    IF v_p_apoyo IS NULL THEN
        INSERT IGNORE INTO tmp_prg_tec (id_usuario)
        SELECT id_usuario FROM programacion_tecnico WHERE id_programacion = v_id_prog AND rol = 'apoyo' AND eliminado_en IS NULL;
    ELSE
        INSERT IGNORE INTO tmp_prg_tec (id_usuario)
        SELECT jt.id FROM JSON_TABLE(v_p_apoyo, '$[*]' COLUMNS (id BIGINT PATH '$')) jt WHERE jt.id IS NOT NULL AND jt.id > 0;
    END IF;
    SET v_ids_ahora = CAST(CONCAT('[', IFNULL((SELECT GROUP_CONCAT(id_usuario ORDER BY id_usuario) FROM tmp_prg_tec), ''), ']') AS JSON);
    DROP TEMPORARY TABLE IF EXISTS tmp_prg_tec;
    IF v_ids_ahora <> v_ids_bloqueo THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'La programación cambió mientras se procesaba. Vuelve a abrir la solicitud e inténtalo de nuevo.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT TRIM(CONCAT(nombre, ' ', apellido)) INTO v_nom_tec_act FROM usuario WHERE id_usuario = v_tec_act;
    SELECT COUNT(*) INTO v_n_eq_act FROM programacion_equipo WHERE id_programacion = v_id_prog AND eliminado_en IS NULL;

    CALL SP_AplicarCambiosProgramacion(p_id_usuario, v_id_prog, v_p_fecha, v_p_ini, v_p_fin, v_p_tec, v_p_apoyo, v_p_equipos, 1,
                                       v_error, v_c_horario, v_c_tecnicos, v_c_equipos);
    IF v_error IS NOT NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, CONCAT('No se puede aprobar: ', v_error) AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT estado, fecha_ejecucion, hora_inicio, hora_fin_estimada, id_tecnico_principal
      INTO v_estado_nuevo, v_fecha_n, v_ini_n, v_fin_n, v_tec_n
    FROM programacion WHERE id_programacion = v_id_prog;
    SELECT TRIM(CONCAT(nombre, ' ', apellido)) INTO v_nom_tec_n FROM usuario WHERE id_usuario = v_tec_n;
    SELECT COUNT(*) INTO v_n_eq_n FROM programacion_equipo WHERE id_programacion = v_id_prog AND eliminado_en IS NULL;

    SET v_desc = CONCAT('Reprogramación aprobada por ', IFNULL(v_jefe, 'el Jefe'), ':');
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
    SET v_desc = CONCAT(v_desc, IFNULL(CONCAT(' Motivo de la solicitud: ', v_motivo, '.'), ''),
                        IFNULL(CONCAT(' Comentario del Jefe: ', v_comentario, IF(RIGHT(v_comentario, 1) IN ('.', '!', '?'), '', '.')), ''),
                        IF(v_c_horario = 1, ' Pendiente de confirmación del cliente.', ''));

    UPDATE os_reprogramacion
    SET estado = 'aprobada', resuelto_por = p_id_usuario, fecha_resolucion = NOW(),
        comentario_resolucion = v_comentario, modificado_por = p_id_usuario
    WHERE id_reprogramacion = p_id_solicitud;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion,
                                  id_usuario, registrado_en, metadata)
    VALUES ('programacion', v_id_prog, 'aprobar_reprogramacion', v_estado_prg, v_estado_nuevo, LEFT(v_desc, 900),
            p_id_usuario, NOW(),
            JSON_OBJECT('idSolicitud', p_id_solicitud, 'motivo', v_motivo, 'cambiaFechaHora', v_c_horario,
                        'cambiaTecnicos', v_c_tecnicos, 'cambiaEquipos', v_c_equipos,
                        'horaFinAnterior', TIME_FORMAT(v_fin_act, '%H:%i'), 'horaFinNueva', TIME_FORMAT(v_fin_n, '%H:%i')));

    -- Avisos: el Asistente que pidió el cambio y los técnicos afectados
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
                                TIME_FORMAT(v_fin_n, '%H:%i'), IFNULL(CONCAT('. Motivo: ', v_motivo), ''), '.')
                END, 1000),
           'orden_servicio', v_id_os, NOW(), p_id_usuario
    FROM tmp_apl_afectados a
    WHERE a.id_usuario <> p_id_usuario AND a.id_usuario <> IFNULL(v_solicitante, 0);

    IF v_solicitante IS NOT NULL AND v_solicitante <> p_id_usuario THEN
        INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
        VALUES (v_solicitante, 5, CONCAT('Reprogramación aprobada: ', v_numero),
                LEFT(CONCAT('El Jefe aprobó tu solicitud de reprogramar la ', v_tipo, ' ', v_numero, ' (', v_codigo, '): ',
                            DATE_FORMAT(v_fecha_n, '%d/%m/%Y'), ' de ', TIME_FORMAT(v_ini_n, '%H:%i'), ' a ', TIME_FORMAT(v_fin_n, '%H:%i'), '.',
                            IF(v_c_horario = 1, ' Registra de nuevo la respuesta del cliente.', '')), 1000),
                'orden_servicio', v_id_os, NOW(), p_id_usuario);
    END IF;

    DROP TEMPORARY TABLE IF EXISTS tmp_apl_afectados;

    COMMIT;

    SELECT 2 AS IdTipoMensaje,
           IF(v_c_horario = 1, 'Solicitud aprobada y aplicada. Registra de nuevo la respuesta del cliente.', 'Solicitud aprobada y aplicada.') AS Mensaje;
    SELECT p_id_solicitud AS id_solicitud, 'aprobada' AS estado_solicitud, v_id_prog AS id_programacion, v_codigo AS codigo,
           v_estado_nuevo AS estado, IF(v_estado_nuevo = 'confirmada', 'Programado', 'Pendiente confirmación cliente') AS estado_label,
           v_c_horario AS requiere_reconfirmar_cliente;
END$$

DELIMITER ;
