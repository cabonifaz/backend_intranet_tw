-- HU-53 (Sprint 5) Ayuda interna de SP_RegistrarAsistenteServicioRuta: valida y escribe el registro del Asistente. No llamar directamente:
-- el SP público la ejecuta dentro de un candado por usuario (así el antiduplicado y el límite de frecuencia no tienen carreras).
-- Resultados: 1 mensaje (1 regla de negocio · 2 éxito · 3 error) · 2 (solo éxito) IdRegistro, Modo, Notificados, EstadoNuevo.
DROP PROCEDURE IF EXISTS SP_RegistrarAsistenteServicioRutaInterno;

DELIMITER $$

CREATE PROCEDURE SP_RegistrarAsistenteServicioRutaInterno(
    IN p_id_usuario  BIGINT,
    IN p_id_os       BIGINT,
    IN p_modo        VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_descripcion VARCHAR(1000) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_fuente      VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_vinculo     VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_tipo     INT,
    IN p_duracion    INT,
    IN p_impacto     VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_evidencia   VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_nuevo_estado VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_motivo   INT,
    IN p_comentario  VARCHAR(1000) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_msg        VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_desc       VARCHAR(1000) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_com        VARCHAR(1000) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_fuente     VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_vinculo    VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_impacto    VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_evid       VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado_os  VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_numero     VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tec        BIGINT;
    DECLARE v_exp        BIGINT;
    DECLARE v_asistente  VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tecnico    VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tipo_nom   VARCHAR(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_motivo_nom VARCHAR(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_ini_utc    DATETIME;
    DECLARE v_ahora_utc  DATETIME;
    DECLARE v_ahora      DATETIME;
    DECLARE v_nivel_act  INT DEFAULT 0;
    DECLARE v_nivel_nue  INT DEFAULT 0;
    DECLARE v_estado_nue VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cod_evt    VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_evt_tipo INT;
    DECLARE v_id_evento  BIGINT DEFAULT NULL;
    DECLARE v_id_reg     BIGINT;
    DECLARE v_notif      INT DEFAULT 0;
    DECLARE v_cuenta     INT DEFAULT 0;
    DECLARE v_en_tx      TINYINT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        IF v_en_tx = 1 THEN ROLLBACK; END IF;
        CALL SP_LimpiarSeguimientoOperativo();
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    -- ── Validaciones de entrada (antes de tocar datos) ───────────────────────────────────
    IF FN_PermisoAccion(p_id_usuario, 'seg_registrar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para registrar en el seguimiento operativo.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF IFNULL(p_modo, '') NOT IN ('observacion', 'demora', 'cambio_estado') THEN
        SELECT 1 AS IdTipoMensaje, 'El modo de registro no es válido.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_desc = TRIM(IFNULL(p_descripcion, ''));
    SET v_com  = TRIM(IFNULL(p_comentario, ''));
    SET v_fuente = NULLIF(TRIM(IFNULL(p_fuente, '')), '');
    SET v_vinculo = NULLIF(TRIM(IFNULL(p_vinculo, '')), '');
    SET v_evid = NULLIF(TRIM(IFNULL(p_evidencia, '')), '');
    SET v_impacto = NULL;

    IF p_modo = 'observacion' THEN
        IF CHAR_LENGTH(v_desc) = 0 THEN
            SELECT 1 AS IdTipoMensaje, 'La descripción de la nota es obligatoria.' AS Mensaje; LEAVE proc;
        ELSEIF CHAR_LENGTH(v_desc) > 500 THEN
            SELECT 1 AS IdTipoMensaje, 'La descripción no puede superar los 500 caracteres.' AS Mensaje; LEAVE proc;
        ELSEIF v_fuente IS NOT NULL AND v_fuente NOT IN ('llamada_telefonica', 'whatsapp', 'contacto_planta', 'observacion_directa') THEN
            SELECT 1 AS IdTipoMensaje, 'La fuente de la información no es válida.' AS Mensaje; LEAVE proc;
        ELSEIF v_vinculo IS NOT NULL AND v_vinculo NOT REGEXP '^[edia][0-9]{1,18}$' THEN
            SELECT 1 AS IdTipoMensaje, 'El evento a vincular no es válido.' AS Mensaje; LEAVE proc;
        END IF;
    ELSEIF p_modo = 'demora' THEN
        SET v_impacto = IFNULL(NULLIF(TRIM(IFNULL(p_impacto, '')), ''), 'retrasa');
        IF IFNULL(p_id_tipo, 0) <= 0 OR NOT EXISTS (SELECT 1 FROM tabla_maestra m WHERE m.Descripcion = 'TIPO_DEMORA_INCIDENTE' AND m.IdEmpresa = 1
                                                      AND m.Num1 = p_id_tipo AND m.eliminado_en IS NULL) THEN
            SELECT 1 AS IdTipoMensaje, 'El tipo de demora o incidente no es válido.' AS Mensaje; LEAVE proc;
        ELSEIF CHAR_LENGTH(v_desc) = 0 THEN
            SELECT 1 AS IdTipoMensaje, 'La descripción es obligatoria.' AS Mensaje; LEAVE proc;
        ELSEIF CHAR_LENGTH(v_desc) > 500 THEN
            SELECT 1 AS IdTipoMensaje, 'La descripción no puede superar los 500 caracteres.' AS Mensaje; LEAVE proc;
        ELSEIF p_duracion IS NOT NULL AND (p_duracion < 1 OR p_duracion > 1440) THEN
            SELECT 1 AS IdTipoMensaje, 'La duración estimada debe estar entre 1 y 1440 minutos.' AS Mensaje; LEAVE proc;
        ELSEIF v_impacto NOT IN ('retrasa', 'detiene') THEN
            SELECT 1 AS IdTipoMensaje, 'El impacto en la ruta no es válido.' AS Mensaje; LEAVE proc;
        ELSEIF v_evid IS NOT NULL AND (CHAR_LENGTH(v_evid) > 500 OR v_evid NOT REGEXP '^(https://[^[:space:][:cntrl:]<>"\\\\]+|/[^/[:space:][:cntrl:]<>"\\\\][^[:space:][:cntrl:]<>"\\\\]*)$' OR v_evid LIKE '%..%') THEN
            SELECT 1 AS IdTipoMensaje, 'La evidencia fotográfica debe ser un enlace https o una ruta del sistema.' AS Mensaje; LEAVE proc;
        END IF;
    ELSE
        IF IFNULL(p_nuevo_estado, '') NOT IN ('salida', 'en_ruta', 'llegada', 'ingreso', 'inicio', 'finalizado') THEN
            SELECT 1 AS IdTipoMensaje, 'El nuevo estado no es válido.' AS Mensaje; LEAVE proc;
        ELSEIF IFNULL(p_id_motivo, 0) <= 0 OR NOT EXISTS (SELECT 1 FROM tabla_maestra m WHERE m.Descripcion = 'MOTIVO_CAMBIO_MANUAL' AND m.IdEmpresa = 1
                                                           AND m.Num1 = p_id_motivo AND m.eliminado_en IS NULL) THEN
            SELECT 1 AS IdTipoMensaje, 'El motivo del cambio manual no es válido.' AS Mensaje; LEAVE proc;
        ELSEIF CHAR_LENGTH(v_com) < 10 THEN
            SELECT 1 AS IdTipoMensaje, 'El comentario de justificación es obligatorio (mínimo 10 caracteres).' AS Mensaje; LEAVE proc;
        ELSEIF CHAR_LENGTH(v_com) > 1000 THEN
            SELECT 1 AS IdTipoMensaje, 'El comentario no puede superar los 1000 caracteres.' AS Mensaje; LEAVE proc;
        END IF;
    END IF;

    -- ── Servicio de hoy y estado actual ──────────────────────────────────────────────────
    CALL SP_PrepararDetalleServicioRuta(p_id_usuario, p_id_os, v_msg);
    IF v_msg IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje;
        LEAVE proc;
    END IF;
    SELECT ini_utc, ahora_utc, ahora INTO v_ini_utc, v_ahora_utc, v_ahora FROM tmp_sg_cfg LIMIT 1;
    SELECT id_tecnico, numero, os_estado, tecnico INTO v_tec, v_numero, v_estado_os, v_tecnico FROM tmp_sg_os WHERE id_os = p_id_os;
    CALL SP_LimpiarSeguimientoOperativo();

    IF v_tec IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'El servicio no tiene un técnico asignado.' AS Mensaje; LEAVE proc;
    END IF;
    SELECT TRIM(CONCAT(nombre, ' ', apellido)) INTO v_asistente FROM usuario WHERE id_usuario = p_id_usuario;
    SELECT id_expediente INTO v_exp FROM orden_servicio WHERE id_os = p_id_os;

    -- HU-54: servicio finalizado = modo auditoría post-servicio, el tab Registrar queda deshabilitado (ningún modo)
    IF v_estado_os = 'finalizada' THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio finalizado — Para registrar observaciones post-cierre, pedir reapertura al Jefe de Operaciones.' AS Mensaje; LEAVE proc;
    END IF;

    -- Vínculo: debe ser un evento del timeline de ESTE servicio y de hoy (e<id> hito · a<id> registro del Asistente · d/i<id> demora/incidencia)
    IF p_modo = 'observacion' AND v_vinculo IS NOT NULL THEN
        IF v_vinculo NOT REGEXP '^[edia][0-9]{1,18}$'
           OR NOT (
                (v_vinculo LIKE 'e%' AND EXISTS (SELECT 1 FROM evento_campo e WHERE e.id_os = p_id_os AND e.eliminado_en IS NULL AND e.timestamp_utc >= v_ini_utc
                                                  AND CONCAT('e', e.id_evento) = v_vinculo))
             OR (v_vinculo LIKE 'a%' AND EXISTS (SELECT 1 FROM registro_asistente r WHERE r.id_os = p_id_os AND r.fecha_utc >= v_ini_utc
                                                  AND CONCAT('a', r.id_registro) = v_vinculo))
             OR (v_vinculo LIKE 'd%' AND EXISTS (SELECT 1 FROM demora_registro d WHERE d.id_os = p_id_os AND d.eliminado_en IS NULL
                                                  AND CONCAT('d', d.id_demora) = v_vinculo))
             OR (v_vinculo LIKE 'i%' AND EXISTS (SELECT 1 FROM incidencia_operativa i WHERE i.id_os = p_id_os AND i.eliminado_en IS NULL
                                                  AND CONCAT('i', i.id_incidencia) = v_vinculo))) THEN
            SELECT 1 AS IdTipoMensaje, 'El evento a vincular no pertenece a este servicio.' AS Mensaje; LEAVE proc;
        END IF;
    END IF;

    -- Cambio de estado: solo avanzar. Nivel: 0 programado · 1 salida · 2 en ruta · 3 llegada · 4 ingreso a planta · 5 inicio de servicio · 6 finalizado
    IF p_modo = 'cambio_estado' THEN
        SET v_nivel_act = CASE v_estado_os
            WHEN 'en_ejecucion' THEN 5 WHEN 'pausada' THEN 5 WHEN 'finalizada' THEN 6
            WHEN 'en_ruta' THEN
                CASE WHEN EXISTS (SELECT 1 FROM evento_campo e JOIN tabla_maestra m ON m.Descripcion = 'TIPO_EVENTO_CAMPO' AND m.IdEmpresa = 1 AND m.Num1 = e.id_tipo_evento
                                  WHERE e.id_os = p_id_os AND e.eliminado_en IS NULL AND e.timestamp_utc >= v_ini_utc AND m.String2 = 'INGRESO_PLANTA') THEN 4
                     WHEN (SELECT hora_llegada_real FROM orden_servicio WHERE id_os = p_id_os) IS NOT NULL THEN 3
                     WHEN EXISTS (SELECT 1 FROM evento_campo e JOIN tabla_maestra m ON m.Descripcion = 'TIPO_EVENTO_CAMPO' AND m.IdEmpresa = 1 AND m.Num1 = e.id_tipo_evento
                                  WHERE e.id_os = p_id_os AND e.eliminado_en IS NULL AND e.timestamp_utc >= v_ini_utc AND m.String2 = 'EN_RUTA') THEN 2
                     ELSE 1 END
            ELSE 0 END;
        SET v_nivel_nue = CASE p_nuevo_estado WHEN 'salida' THEN 1 WHEN 'en_ruta' THEN 2 WHEN 'llegada' THEN 3 WHEN 'ingreso' THEN 4 WHEN 'inicio' THEN 5 ELSE 6 END;
        IF v_nivel_nue <= v_nivel_act THEN
            SELECT 1 AS IdTipoMensaje,
                   CONCAT('Solo puedes avanzar el estado, no retroceder. Actualmente el servicio está en "',
                          CASE v_estado_os WHEN 'en_ejecucion' THEN 'En Ejecución' WHEN 'en_ruta' THEN 'En Ruta' WHEN 'pausada' THEN 'Pausada'
                                           WHEN 'finalizada' THEN 'Finalizada' WHEN 'reprogramada' THEN 'Reprogramada' ELSE 'Programada' END, '".') AS Mensaje;
            LEAVE proc;
        END IF;
        SET v_estado_nue = CASE WHEN v_nivel_nue <= 4 THEN 'en_ruta' WHEN v_nivel_nue = 5 THEN 'en_ejecucion' ELSE 'finalizada' END;
        SET v_cod_evt = CASE p_nuevo_estado WHEN 'salida' THEN 'SALIDA_BASE' WHEN 'en_ruta' THEN 'EN_RUTA' WHEN 'llegada' THEN 'LLEGADA'
                                            WHEN 'ingreso' THEN 'INGRESO_PLANTA' WHEN 'inicio' THEN 'INICIO_TRABAJO' ELSE 'CIERRE' END;
        SELECT m.Num1 INTO v_id_evt_tipo FROM tabla_maestra m WHERE m.Descripcion = 'TIPO_EVENTO_CAMPO' AND m.IdEmpresa = 1 AND m.String2 = v_cod_evt LIMIT 1;
        IF v_id_evt_tipo IS NULL THEN
            SELECT 1 AS IdTipoMensaje, 'El hito de campo para ese estado no está configurado.' AS Mensaje; LEAVE proc;
        END IF;
        SELECT m.String1 INTO v_motivo_nom FROM tabla_maestra m WHERE m.Descripcion = 'MOTIVO_CAMBIO_MANUAL' AND m.IdEmpresa = 1 AND m.Num1 = p_id_motivo LIMIT 1;
    END IF;
    IF p_modo = 'demora' THEN
        SELECT m.String1 INTO v_tipo_nom FROM tabla_maestra m WHERE m.Descripcion = 'TIPO_DEMORA_INCIDENTE' AND m.IdEmpresa = 1 AND m.Num1 = p_id_tipo LIMIT 1;
    END IF;

    -- Antiduplicado y límite de frecuencia
    IF EXISTS (SELECT 1 FROM registro_asistente r WHERE r.id_usuario = p_id_usuario AND r.id_os = p_id_os AND r.modo = p_modo
               AND r.descripcion = IF(p_modo = 'cambio_estado', v_com, v_desc) AND r.fecha_utc >= DATE_SUB(v_ahora_utc, INTERVAL 15 SECOND)) THEN
        SELECT 1 AS IdTipoMensaje, 'Ese registro ya se envió hace unos segundos.' AS Mensaje; LEAVE proc;
    END IF;
    SELECT COUNT(*) INTO v_cuenta FROM registro_asistente r WHERE r.id_usuario = p_id_usuario AND r.fecha_utc >= DATE_SUB(v_ahora_utc, INTERVAL 10 MINUTE);
    IF v_cuenta >= 30 THEN
        SELECT 1 AS IdTipoMensaje, 'Demasiados registros en poco tiempo. Espera unos minutos e inténtalo de nuevo.' AS Mensaje; LEAVE proc;
    END IF;

    -- ── Escritura (una transacción) ──────────────────────────────────────────────────────
    SET v_en_tx = 1;
    START TRANSACTION;

    IF p_modo = 'cambio_estado' THEN
        INSERT INTO evento_campo (id_os, id_usuario, id_tipo_evento, timestamp_utc, sincronizado, notas, creado_por)
        VALUES (p_id_os, v_tec, v_id_evt_tipo, v_ahora_utc, 1,
                LEFT(CONCAT('Registrado manualmente por ', v_asistente, '. Motivo: ', v_motivo_nom, '. ', v_com), 1000), p_id_usuario);
        SET v_id_evento = LAST_INSERT_ID();
        UPDATE orden_servicio
        SET estado = v_estado_nue,
            hora_llegada_real = IF(v_nivel_nue >= 3 AND hora_llegada_real IS NULL, TIME(v_ahora), hora_llegada_real),
            hora_fin_real = IF(v_nivel_nue = 6, TIME(v_ahora), hora_fin_real),
            modificado_por = p_id_usuario, modificado_en = NOW()
        WHERE id_os = p_id_os;
    END IF;

    INSERT INTO registro_asistente (id_os, modo, id_usuario, id_tecnico, descripcion, fuente, vinculo_clave, id_tipo, duracion_min, impacto, evidencia_url,
                                    estado_anterior, estado_nuevo, id_motivo, id_evento_campo, fecha_utc)
    VALUES (p_id_os, p_modo, p_id_usuario, v_tec, IF(p_modo = 'cambio_estado', v_com, v_desc), v_fuente, v_vinculo,
            IF(p_modo = 'demora', p_id_tipo, NULL), IF(p_modo = 'demora', p_duracion, NULL), v_impacto, IF(p_modo = 'demora', v_evid, NULL),
            IF(p_modo = 'cambio_estado', v_estado_os, NULL), IF(p_modo = 'cambio_estado', p_nuevo_estado, NULL),
            IF(p_modo = 'cambio_estado', p_id_motivo, NULL), v_id_evento, v_ahora_utc);
    SET v_id_reg = LAST_INSERT_ID();

    -- Auditoría: quién (nombre completo), cuándo y en qué modo; en la OS y en el historial del expediente
    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('orden_servicio', p_id_os, CONCAT('asistente_', p_modo), IF(p_modo = 'cambio_estado', v_estado_os, NULL), IF(p_modo = 'cambio_estado', v_estado_nue, NULL),
            LEFT(CONCAT(v_asistente, ' registró ', CASE p_modo WHEN 'observacion' THEN 'una observación' WHEN 'demora' THEN CONCAT('una demora/incidente (', v_tipo_nom, ')')
                        ELSE CONCAT('un cambio manual de estado a "', p_nuevo_estado, '" (', v_motivo_nom, ')') END,
                        ' en ', v_numero, ' el ', DATE_FORMAT(v_ahora, '%d/%m/%Y %H:%i:%s'), ' (hora de Lima).'), 900),
            p_id_usuario, NOW(),
            JSON_OBJECT('idRegistro', v_id_reg, 'modo', p_modo, 'asistente', v_asistente, 'idTecnico', v_tec, 'fechaLima', DATE_FORMAT(v_ahora, '%Y-%m-%d %H:%i:%s'),
                        'impacto', v_impacto, 'idMotivo', p_id_motivo, 'nuevoEstado', p_nuevo_estado));
    IF v_exp IS NOT NULL THEN
        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
        VALUES ('expediente', v_exp, CONCAT('asistente_', p_modo), NULL, NULL,
                LEFT(CONCAT(v_asistente, ' registró ', CASE p_modo WHEN 'observacion' THEN 'una observación' WHEN 'demora' THEN 'una demora/incidente'
                            ELSE 'un cambio manual de estado' END, ' del servicio ', v_numero, ' el ', DATE_FORMAT(v_ahora, '%d/%m/%Y %H:%i:%s'), '.'), 900),
                p_id_usuario, NOW(), JSON_OBJECT('idRegistro', v_id_reg, 'modo', p_modo, 'idOs', p_id_os));
    END IF;

    -- Notificación al Jefe de Operaciones: demora que detiene o cualquier cambio manual crítico (nunca al que registra)
    IF p_modo = 'cambio_estado' OR (p_modo = 'demora' AND v_impacto = 'detiene') THEN
        INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
        SELECT u.id_usuario, 5,
               IF(p_modo = 'cambio_estado', CONCAT('Cambio manual de estado: ', v_numero), CONCAT('Servicio detenido: ', v_numero)),
               LEFT(IF(p_modo = 'cambio_estado',
                       CONCAT(v_asistente, ' cambió manualmente el estado de ', v_numero, ' (técnico ', IFNULL(v_tecnico, ''), ') a "', p_nuevo_estado, '". Motivo: ', v_motivo_nom, '. ', v_com),
                       CONCAT(v_asistente, ' registró una demora que DETIENE el servicio ', v_numero, ' (técnico ', IFNULL(v_tecnico, ''), '): ', v_tipo_nom, '. ', v_desc,
                              ' Reprograma el servicio.')), 1000),
               'orden_servicio', p_id_os, NOW(), p_id_usuario
        FROM usuario u
        WHERE u.area = 'operaciones' AND u.id_usuario <> p_id_usuario AND FN_PermisoAccion(u.id_usuario, 'seg_alerta_registro') = 1;
        SET v_notif = ROW_COUNT();
    END IF;

    COMMIT;
    SET v_en_tx = 0;

    SELECT 2 AS IdTipoMensaje, 'Registro guardado.' AS Mensaje;
    SELECT v_id_reg AS IdRegistro, p_modo AS Modo, v_notif AS Notificados, IF(p_modo = 'cambio_estado', p_nuevo_estado, NULL) AS EstadoNuevo;
END$$

DELIMITER ;
