-- HU-37 (Sprint 5) Registro de la respuesta del cliente a una programación. La coordinación con el cliente ocurre FUERA del sistema
-- (teléfono, correo, WhatsApp, visita): aquí solo se guarda su resultado. No envía nada al cliente.
-- Acceso: prog_gestionar (módulo operaciones).
--   p_canal: correo | whatsapp | llamada | presencial · p_resultado: acepto | pidio_reprogramar | cancelo
--   p_comentario: opcional, hasta 300 caracteres.
-- Reglas (cada falla devuelve tipo 1 y no guarda nada):
--   · la programación existe, no está cancelada y su orden sigue programada o reprogramada
--   · 'acepto' solo si la programación está pendiente de confirmación y su fecha es de hoy en adelante
--   · la misma respuesta (canal + resultado) del mismo usuario no se repite en 1 minuto (doble clic)
--   · concurrencia: se bloquea primero la fila de la orden y luego la de la programación (mismo orden que la anulación de OS);
--     dos "acepto" simultáneos: el segundo ve la programación ya confirmada y se rechaza
-- Efectos:
--   · siempre: fila en programacion_confirmacion y evento 'respuesta_cliente' en auditoria_evento (historial del detalle)
--   · acepto: la programación pasa a 'confirmada' (PROGRAMADO), la OS queda con confirmacion_cliente = 1 y fecha de confirmación,
--     se avisa a los técnicos asignados y se habilita Gestionar Viáticos (HU-45) para el Jefe de Operaciones
--   · pidio_reprogramar / cancelo: NO cambian el estado; indican el flujo de la HU-38 (reprogramación directa si el usuario es
--     jefe, solicitud si es asistente; cancelación con motivo tipificado obligatorio) en siguiente_accion
-- Resultados: 1 mensaje, 2 respuesta registrada y siguiente acción, 3 advertencias (texto).
DROP PROCEDURE IF EXISTS SP_RegistrarRespuestaClienteProgramacion;

DELIMITER $$

CREATE PROCEDURE SP_RegistrarRespuestaClienteProgramacion(
    IN p_id_usuario      BIGINT,
    IN p_id_programacion BIGINT,
    IN p_canal           VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_resultado       VARCHAR(25)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_comentario      VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_id_os       BIGINT       DEFAULT NULL;
    DECLARE v_estado      VARCHAR(25)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado_os   VARCHAR(25)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_numero      VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tipo        VARCHAR(5)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_codigo      VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cliente     VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_fecha       DATE;
    DECLARE v_ini         TIME;
    DECLARE v_fin         TIME;
    DECLARE v_comentario  VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id          BIGINT       DEFAULT NULL;
    DECLARE v_estado_nuevo VARCHAR(25) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_aprueba     TINYINT      DEFAULT 0;
    DECLARE v_siguiente   VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_canal_txt   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_result_txt  VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_n_bloq      INT          DEFAULT 0;
    DECLARE v_bloq_txt    VARCHAR(600) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            @err_msg  = MESSAGE_TEXT,
            @err_code = MYSQL_ERRNO;   -- primero: la limpieza de abajo genera notas que reemplazan el diagnóstico
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_ssoma_in;
        CALL SP_LimpiarSsomaProgramacion();
        SELECT 3 AS IdTipoMensaje,
               CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    -- ── Permiso y validaciones de forma ──────────────────────────────────
    IF FN_PermisoAccion(p_id_usuario, 'prog_gestionar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para registrar la respuesta del cliente.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF p_canal IS NULL OR p_canal NOT IN ('correo', 'whatsapp', 'llamada', 'presencial') THEN
        SELECT 1 AS IdTipoMensaje, 'Selecciona el canal utilizado: correo, WhatsApp, llamada o presencial.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF p_resultado IS NULL OR p_resultado NOT IN ('acepto', 'pidio_reprogramar', 'cancelo') THEN
        SELECT 1 AS IdTipoMensaje, 'Selecciona el resultado: aceptó, pidió reprogramar o canceló.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_comentario = NULLIF(TRIM(IFNULL(p_comentario, '')), '');
    IF v_comentario IS NOT NULL AND CHAR_LENGTH(v_comentario) > 300 THEN
        SELECT 1 AS IdTipoMensaje, 'El comentario no puede superar 300 caracteres.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT id_os INTO v_id_os FROM programacion WHERE id_programacion = p_id_programacion AND eliminado_en IS NULL;
    IF v_id_os IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'La programación no existe.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_canal_txt  = CASE p_canal WHEN 'correo' THEN 'Correo' WHEN 'whatsapp' THEN 'WhatsApp'
                                    WHEN 'llamada' THEN 'Llamada' ELSE 'Presencial' END;
    SET v_result_txt = CASE p_resultado WHEN 'acepto' THEN 'Aceptó la programación'
                                        WHEN 'pidio_reprogramar' THEN 'Pidió reprogramar' ELSE 'Canceló' END;

    -- ── Validación SSOMA de hoy (solo informa: se evalúa antes de abrir la transacción) ──
    IF p_resultado = 'acepto' THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_ssoma_in;
        CREATE TEMPORARY TABLE tmp_ssoma_in (id_usuario BIGINT NOT NULL, PRIMARY KEY (id_usuario));
        INSERT INTO tmp_ssoma_in (id_usuario)
        SELECT id_usuario FROM programacion_tecnico WHERE id_programacion = p_id_programacion AND eliminado_en IS NULL;
        CALL SP_EvaluarSsomaProgramacion(v_id_os, (SELECT fecha_ejecucion FROM programacion WHERE id_programacion = p_id_programacion));

        SELECT COUNT(*),
               GROUP_CONCAT(CONCAT(TRIM(CONCAT(u.nombre, ' ', u.apellido)), ': ', IFNULL(NULLIF(r.motivo_bloqueo, ''), 'documento SSOMA faltante'))
                            ORDER BY u.nombre SEPARATOR '; ')
          INTO v_n_bloq, v_bloq_txt
        FROM tmp_ssoma_res r
        JOIN usuario u ON u.id_usuario = r.id_usuario
        WHERE r.estado IN ('bloqueado', 'pendiente');

        DROP TEMPORARY TABLE IF EXISTS tmp_ssoma_in;
        CALL SP_LimpiarSsomaProgramacion();
    END IF;

    -- ── Transacción: primero la orden y luego la programación (mismo orden que la anulación de la OS) ──
    START TRANSACTION;

    SELECT estado, numero, tipo INTO v_estado_os, v_numero, v_tipo
    FROM orden_servicio WHERE id_os = v_id_os AND eliminado_en IS NULL FOR UPDATE;

    SELECT estado, codigo, fecha_ejecucion, hora_inicio, hora_fin_estimada INTO v_estado, v_codigo, v_fecha, v_ini, v_fin
    FROM programacion WHERE id_programacion = p_id_programacion AND eliminado_en IS NULL FOR UPDATE;

    IF v_estado IS NULL OR v_estado_os IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'La programación no existe.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF v_estado = 'cancelada' THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, CONCAT('La programación ', v_codigo, ' está cancelada: ya no admite respuestas del cliente.') AS Mensaje;
        LEAVE proc;
    END IF;

    IF v_estado_os NOT IN ('programada', 'reprogramada') THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje,
               CONCAT('La orden ', v_numero, ' está ', REPLACE(v_estado_os, '_', ' '), ': ya no se registra la respuesta del cliente.') AS Mensaje;
        LEAVE proc;
    END IF;

    IF p_resultado = 'acepto' THEN
        IF v_estado = 'confirmada' THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, CONCAT('La programación ', v_codigo, ' ya está confirmada por el cliente.') AS Mensaje;
            LEAVE proc;
        END IF;
        IF v_fecha < CURDATE() THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje,
                   CONCAT('La fecha de la programación (', DATE_FORMAT(v_fecha, '%d/%m/%Y'), ') ya pasó: reprograma antes de confirmar.') AS Mensaje;
            LEAVE proc;
        END IF;
    END IF;

    IF EXISTS (SELECT 1 FROM programacion_confirmacion
               WHERE id_programacion = p_id_programacion AND id_registrado_por = p_id_usuario
                 AND canal = p_canal AND resultado = p_resultado AND eliminado_en IS NULL
                 AND fecha_registro > NOW() - INTERVAL 1 MINUTE) THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Ya registraste esa misma respuesta hace instantes.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- ── Registro ──────────────────────────────────────────────────────────
    INSERT INTO programacion_confirmacion (id_programacion, canal, resultado, comentario, id_registrado_por, fecha_registro, creado_por)
    VALUES (p_id_programacion, p_canal, p_resultado, v_comentario, p_id_usuario, NOW(), p_id_usuario);
    SET v_id = LAST_INSERT_ID();

    SET v_estado_nuevo = IF(p_resultado = 'acepto', 'confirmada', v_estado);

    IF p_resultado = 'acepto' THEN
        UPDATE programacion SET estado = 'confirmada', modificado_por = p_id_usuario WHERE id_programacion = p_id_programacion;
        UPDATE orden_servicio
        SET confirmacion_cliente = 1, fecha_confirmacion_cliente = NOW(), modificado_por = p_id_usuario
        WHERE id_os = v_id_os;
    END IF;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion,
                                  id_usuario, registrado_en, metadata)
    VALUES ('programacion', p_id_programacion, 'respuesta_cliente', v_estado, v_estado_nuevo,
            CONCAT('Respuesta del cliente (', v_canal_txt, '): ', v_result_txt, '.',
                   IF(v_comentario IS NULL, '', CONCAT(' ', v_comentario))),
            p_id_usuario, NOW(),
            JSON_OBJECT('programacion', v_codigo, 'idConfirmacion', v_id, 'canal', p_canal, 'resultado', p_resultado, 'idOs', v_id_os));

    -- ── Aviso a los técnicos cuando el cliente acepta ─────────────────────
    IF p_resultado = 'acepto' THEN
        SELECT razon_social INTO v_cliente FROM cliente
        WHERE id_cliente = (SELECT id_cliente FROM orden_servicio WHERE id_os = v_id_os);

        INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
        SELECT pt.id_usuario, 5, CONCAT('Servicio confirmado: ', v_numero),
               CONCAT('El cliente', IF(v_cliente IS NULL, '', CONCAT(' ', v_cliente)), ' confirmó la ', v_tipo, ' ', v_numero,
                      ' del ', DATE_FORMAT(v_fecha, '%d/%m/%Y'), ' de ', TIME_FORMAT(v_ini, '%H:%i'), ' a ', TIME_FORMAT(v_fin, '%H:%i'), '.'),
               'orden_servicio', v_id_os, NOW(), p_id_usuario
        FROM programacion_tecnico pt
        WHERE pt.id_programacion = p_id_programacion AND pt.eliminado_en IS NULL AND pt.id_usuario <> p_id_usuario;
    END IF;

    COMMIT;

    -- ── Siguiente acción ──────────────────────────────────────────────────
    SET v_aprueba = IF(FN_PermisoAccion(p_id_usuario, 'prog_aprobar_reprogramacion') = 1, 1, 0);
    SET v_siguiente = CASE p_resultado
        WHEN 'acepto'            THEN 'gestionar_viaticos'
        WHEN 'pidio_reprogramar' THEN IF(v_aprueba = 1, 'reprogramar', 'solicitar_reprogramacion')
        ELSE 'cancelar_programacion'
    END;

    SELECT 2 AS IdTipoMensaje,
           CASE p_resultado
               WHEN 'acepto'            THEN CONCAT('Programación ', v_codigo, ' confirmada: pasó a PROGRAMADO.')
               WHEN 'pidio_reprogramar' THEN CONCAT('Respuesta registrada: el cliente pidió reprogramar la ', v_codigo, '.')
               ELSE                          CONCAT('Respuesta registrada: el cliente canceló la ', v_codigo, '.')
           END AS Mensaje;

    -- 2. Respuesta registrada
    SELECT v_id                                 AS id_confirmacion,
           p_id_programacion                    AS id_programacion,
           v_codigo                             AS codigo,
           v_estado_nuevo                       AS estado,
           CASE v_estado_nuevo WHEN 'confirmada' THEN 'Programado' ELSE 'Pendiente confirmación cliente' END AS estado_label,
           p_canal                              AS canal,
           p_resultado                          AS resultado,
           v_comentario                         AS comentario,
           v_id_os                              AS id_os,
           v_numero                             AS numero_os,
           v_siguiente                          AS siguiente_accion,
           IF(p_resultado = 'acepto' AND v_aprueba = 1, 1, 0) AS puede_gestionar_viaticos,
           IF(p_resultado = 'pidio_reprogramar' AND v_aprueba = 0, 1, 0) AS requiere_solicitud,
           IF(p_resultado = 'cancelo', 1, 0)    AS requiere_motivo_cancelacion;

    -- 3. Advertencias: al aceptar, si algún técnico ya quedó sin habilitación SSOMA (no bloquea el registro)
    SELECT CONCAT('Atención: ', v_bloq_txt, '. La ejecución quedará bloqueada hasta reasignar o reprogramar.') AS advertencia
    FROM (SELECT 1) x WHERE v_n_bloq > 0 AND p_resultado = 'acepto';
END$$

DELIMITER ;
