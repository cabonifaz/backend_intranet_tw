-- «¿El servicio tendrá informe físico?» (respuesta del cliente a la programación, HU-37 → app móvil). Ejecutar con Alt+X (No al aviso) y reiniciar la API.
-- Requiere antes: Registro fotográfico de la app (HU-11) y el script _aplicar_fotos_adicionales_movil.sql (este script vuelve a crear SP_RegistrarEvidenciaMovil y SP_ObtenerEvidenciasMovil
-- con ese cambio incluido, así que también sirve si todavía no lo aplicaste). No crea datos.
-- Qué hace: agrega la columna informe_fisico a programacion_confirmacion y a orden_servicio (migración 125; todo lo anterior queda NULL = sí) y actualiza 5 procedimientos:
--   SP_RegistrarRespuestaClienteProgramacion (recibe y guarda p_informe_fisico solo con «Aceptó»; sin dato = sí), SP_ObtenerDetalleProgramacion (las respuestas traen informe_fisico),
--   SP_ResumenEvidenciasMovil (con informe_fisico = 0 la evidencia «informe» sale del catálogo: 8 en vez de 9), SP_RegistrarEvidenciaMovil (rechaza la foto del informe si el servicio no lo lleva)
--   y SP_ObtenerEvidenciasMovil (la cabecera trae informe_fisico).
-- Importante: SP_RegistrarRespuestaClienteProgramacion cambia de firma (nuevo parámetro): despliega la API de este cambio junto con el script.

-- ============================================================
-- Migración 125 — «¿El servicio tendrá informe físico?» (respuesta del cliente a la programación, HU-37)
--   1. programacion_confirmacion.informe_fisico: lo que se respondió al registrar «Aceptó» (1 = sí, 0 = no; NULL = no se preguntó: otras respuestas o registros anteriores).
--   2. orden_servicio.informe_fisico: lo vigente para la orden (la última aceptación). NULL o 1 = lleva informe físico (la foto del informe a mano es obligatoria en la
--      app móvil, como hasta ahora); 0 = NO lleva: la app no pide esa foto (el registro fotográfico pasa de 9 a 8 evidencias).
--   No cambia datos existentes (todo lo anterior queda NULL = sí). IDEMPOTENTE.
-- ============================================================

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'programacion_confirmacion' AND COLUMN_NAME = 'informe_fisico'),
    'ALTER TABLE programacion_confirmacion ADD COLUMN informe_fisico TINYINT(1) NULL AFTER comentario', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'orden_servicio' AND COLUMN_NAME = 'informe_fisico'),
    'ALTER TABLE orden_servicio ADD COLUMN informe_fisico TINYINT(1) NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;


-- HU-37 (Sprint 5) Registro de la respuesta del cliente a una programación. La coordinación con el cliente ocurre FUERA del sistema
-- (teléfono, correo, WhatsApp, visita): aquí solo se guarda su resultado. No envía nada al cliente.
-- Acceso: prog_gestionar (módulo operaciones).
--   p_canal: correo | whatsapp | llamada | presencial · p_resultado: acepto | pidio_reprogramar | cancelo
--   p_comentario: opcional, hasta 300 caracteres.
--   p_informe_fisico: «¿El servicio tendrá informe físico?» (1 sí, 0 no). Solo se guarda con 'acepto' (con otro resultado se ignora). NULL se toma como SÍ (compatibilidad
--     con la intranet anterior a este campo). Con 0 la app móvil no pide la foto del informe a mano (SP_ResumenEvidenciasMovil).
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
    IN p_comentario      VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_informe_fisico  TINYINT
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
    DECLARE v_informe_fisico TINYINT   DEFAULT NULL;

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

    IF p_informe_fisico IS NOT NULL AND p_informe_fisico NOT IN (0, 1) THEN
        SELECT 1 AS IdTipoMensaje, 'Indica si el servicio tendrá informe físico: sí o no.' AS Mensaje;
        LEAVE proc;
    END IF;
    -- Solo la aceptación decide el informe físico; sin respuesta (intranet anterior) se toma como SÍ
    SET v_informe_fisico = IF(p_resultado = 'acepto', IFNULL(p_informe_fisico, 1), NULL);

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
    INSERT INTO programacion_confirmacion (id_programacion, canal, resultado, comentario, informe_fisico, id_registrado_por, fecha_registro, creado_por)
    VALUES (p_id_programacion, p_canal, p_resultado, v_comentario, v_informe_fisico, p_id_usuario, NOW(), p_id_usuario);
    SET v_id = LAST_INSERT_ID();

    SET v_estado_nuevo = IF(p_resultado = 'acepto', 'confirmada', v_estado);

    IF p_resultado = 'acepto' THEN
        UPDATE programacion SET estado = 'confirmada', modificado_por = p_id_usuario WHERE id_programacion = p_id_programacion;
        UPDATE orden_servicio
        SET confirmacion_cliente = 1, fecha_confirmacion_cliente = NOW(), informe_fisico = v_informe_fisico, modificado_por = p_id_usuario
        WHERE id_os = v_id_os;
    END IF;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion,
                                  id_usuario, registrado_en, metadata)
    VALUES ('programacion', p_id_programacion, 'respuesta_cliente', v_estado, v_estado_nuevo,
            CONCAT('Respuesta del cliente (', v_canal_txt, '): ', v_result_txt, '.',
                   IF(v_informe_fisico IS NULL, '', CONCAT(' Informe físico: ', IF(v_informe_fisico = 1, 'sí', 'no'), '.')),
                   IF(v_comentario IS NULL, '', CONCAT(' ', v_comentario))),
            p_id_usuario, NOW(),
            JSON_OBJECT('programacion', v_codigo, 'idConfirmacion', v_id, 'canal', p_canal, 'resultado', p_resultado, 'idOs', v_id_os,
                        'informeFisico', IF(v_informe_fisico IS NULL, NULL, v_informe_fisico = 1)));

    -- ── Aviso a los técnicos cuando el cliente acepta ─────────────────────
    IF p_resultado = 'acepto' THEN
        SELECT razon_social INTO v_cliente FROM cliente
        WHERE id_cliente = (SELECT id_cliente FROM orden_servicio WHERE id_os = v_id_os);

        INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
        SELECT pt.id_usuario, 5, CONCAT('Servicio confirmado: ', v_numero),
               CONCAT('El cliente', IF(v_cliente IS NULL, '', CONCAT(' ', v_cliente)), ' confirmó la ', v_tipo, ' ', v_numero,
                      ' del ', DATE_FORMAT(v_fecha, '%d/%m/%Y'), ' de ', TIME_FORMAT(v_ini, '%H:%i'), ' a ', TIME_FORMAT(v_fin, '%H:%i'), '.',
                      IF(v_informe_fisico = 0, ' Este servicio NO lleva informe físico: no se pide la foto del informe.', '')),
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
           v_informe_fisico                     AS informe_fisico,
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

-- HU-37 (Sprint 5) Detalle de la Programación (se abre desde cualquier tab de la bandeja). Solo lectura.
-- Acceso: prog_bandeja (módulo operaciones). Las acciones (registrar respuesta, reprogramar, cancelar, viáticos) vienen como
-- banderas calculadas con el usuario del token.
-- HU-38: cancelar lo permite cualquier rol con prog_gestionar (no pide aprobación); trae la solicitud de reprogramación pendiente
--   (id_solicitud_pendiente) y puede_resolver_solicitud (jefe); el historial incluye reprogramaciones, aprobaciones y la cancelación.
-- Resultados: 1 mensaje, 2 programación (datos, enlaces cruzados, próximo paso y acciones), 3 técnicos, 4 equipos reservados,
--   5 conceptos del servicio, 6 checklist de validación (4 ítems, siempre visibles), 7 alertas SSOMA sobrevenidas,
--   8 historial (timeline), 9 respuestas del cliente registradas.
-- Checklist: técnico asignado · equipos reservados · SSOMA habilitado · cronograma válido (mismo criterio que HU-36 al programar,
--   evaluado hoy: cambió algo después de programar si un documento venció, otro servicio se cruzó o la fecha ya pasó).
-- Alerta SSOMA sobrevenida: solo mientras la programación está vigente (no cancelada, orden programada o reprogramada) y su fecha
--   es de hoy en adelante. Usa SP_EvaluarSsomaProgramacion (la misma regla del buscador y de Programar) con la fecha del servicio:
--   un documento vencido, observado o que vence antes del servicio es crítico (bloquea la ejecución hasta reasignar o reprogramar);
--   uno que vence pronto es advertencia.
-- Historial: eventos de la programación y de su orden (programar, respuestas del cliente, anulación) más las solicitudes de
--   reprogramación y su resolución (os_reprogramacion), con los motivos.
-- Sin funciones almacenadas (exigen SUPER). Las tablas temporales se borran al terminar.
DROP PROCEDURE IF EXISTS SP_ObtenerDetalleProgramacion;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerDetalleProgramacion(
    IN p_id_usuario      BIGINT,
    IN p_id_programacion BIGINT
)
proc: BEGIN
    DECLARE v_id_os        BIGINT       DEFAULT NULL;
    DECLARE v_estado       VARCHAR(25)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado_os    VARCHAR(25)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_fecha        DATE;
    DECLARE v_ini          TIME;
    DECLARE v_fin          TIME;
    DECLARE v_creado       DATETIME;
    DECLARE v_activa       TINYINT      DEFAULT 0;
    DECLARE v_aplica       TINYINT      DEFAULT 0;
    DECLARE v_gestiona     TINYINT      DEFAULT 0;
    DECLARE v_aprueba      TINYINT      DEFAULT 0;
    DECLARE v_pendiente    BIGINT       DEFAULT NULL;
    DECLARE v_n_tec        INT          DEFAULT 0;
    DECLARE v_principal    VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_n_eq_prog    INT          DEFAULT 0;
    DECLARE v_n_eq_os      INT          DEFAULT 0;
    DECLARE v_n_bloq       INT          DEFAULT 0;
    DECLARE v_motivo       VARCHAR(600) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_n_cruces     INT          DEFAULT 0;
    DECLARE v_cruces       VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_crono_ok     TINYINT      DEFAULT 1;
    DECLARE v_crono_txt    VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_ultimo       VARCHAR(25)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_proximo      VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            @err_msg  = MESSAGE_TEXT,
            @err_code = MYSQL_ERRNO;   -- primero: la limpieza de abajo genera notas que reemplazan el diagnóstico
        DROP TEMPORARY TABLE IF EXISTS tmp_det_tec;
        DROP TEMPORARY TABLE IF EXISTS tmp_det_cruce;
        DROP TEMPORARY TABLE IF EXISTS tmp_det_check;
        DROP TEMPORARY TABLE IF EXISTS tmp_det_alerta;
        DROP TEMPORARY TABLE IF EXISTS tmp_ssoma_in;
        CALL SP_LimpiarSsomaProgramacion();
        SELECT 3 AS IdTipoMensaje,
               CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF FN_PermisoAccion(p_id_usuario, 'prog_bandeja') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver la programación operativa.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT id_os, estado, fecha_ejecucion, hora_inicio, hora_fin_estimada, creado_en
      INTO v_id_os, v_estado, v_fecha, v_ini, v_fin, v_creado
    FROM programacion
    WHERE id_programacion = p_id_programacion AND eliminado_en IS NULL;

    IF v_id_os IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'La programación no existe.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT estado INTO v_estado_os FROM orden_servicio WHERE id_os = v_id_os;

    SET v_activa   = IF(v_estado <> 'cancelada' AND v_estado_os IN ('programada', 'reprogramada'), 1, 0);
    SET v_aplica   = IF(v_activa = 1 AND v_fecha >= CURDATE(), 1, 0);
    SET v_gestiona = IF(FN_PermisoAccion(p_id_usuario, 'prog_gestionar') = 1, 1, 0);
    SET v_aprueba  = IF(FN_PermisoAccion(p_id_usuario, 'prog_aprobar_reprogramacion') = 1, 1, 0);
    -- HU-38: solicitud de reprogramación pendiente de esta programación (también las anteriores a la HU-38, que solo traen la OS)
    SELECT MAX(rp.id_reprogramacion) INTO v_pendiente
    FROM os_reprogramacion rp
    WHERE rp.estado = 'pendiente' AND rp.eliminado_en IS NULL
      AND (rp.id_programacion = p_id_programacion OR (rp.id_programacion IS NULL AND rp.id_os = v_id_os));

    -- ── Técnicos de la programación y su situación SSOMA de hoy ───────────────
    DROP TEMPORARY TABLE IF EXISTS tmp_det_tec;
    DROP TEMPORARY TABLE IF EXISTS tmp_det_cruce;
    DROP TEMPORARY TABLE IF EXISTS tmp_det_check;
    DROP TEMPORARY TABLE IF EXISTS tmp_det_alerta;
    DROP TEMPORARY TABLE IF EXISTS tmp_ssoma_in;
    CREATE TEMPORARY TABLE tmp_det_tec (id_usuario BIGINT NOT NULL, rol VARCHAR(10) NOT NULL, PRIMARY KEY (id_usuario));
    INSERT IGNORE INTO tmp_det_tec (id_usuario, rol)
    SELECT id_usuario, rol FROM programacion_tecnico
    WHERE id_programacion = p_id_programacion AND eliminado_en IS NULL;

    CREATE TEMPORARY TABLE tmp_ssoma_in (id_usuario BIGINT NOT NULL, PRIMARY KEY (id_usuario));
    INSERT INTO tmp_ssoma_in (id_usuario) SELECT id_usuario FROM tmp_det_tec;
    CALL SP_EvaluarSsomaProgramacion(v_id_os, v_fecha);

    SELECT COUNT(*) INTO v_n_tec FROM tmp_det_tec;
    SELECT TRIM(CONCAT(u.nombre, ' ', u.apellido)) INTO v_principal
    FROM programacion_tecnico pt JOIN usuario u ON u.id_usuario = pt.id_usuario
    WHERE pt.id_programacion = p_id_programacion AND pt.rol = 'principal' AND pt.eliminado_en IS NULL LIMIT 1;

    SELECT COUNT(*) INTO v_n_eq_prog FROM programacion_equipo WHERE id_programacion = p_id_programacion AND eliminado_en IS NULL;
    SELECT COUNT(*) INTO v_n_eq_os   FROM os_equipo           WHERE id_os = v_id_os AND eliminado_en IS NULL;

    IF v_aplica = 1 THEN
        SELECT COUNT(*),
               GROUP_CONCAT(CONCAT(TRIM(CONCAT(u.nombre, ' ', u.apellido)), ': ', IFNULL(NULLIF(r.motivo_bloqueo, ''), 'documento SSOMA faltante'))
                            ORDER BY u.nombre SEPARATOR '; ')
          INTO v_n_bloq, v_motivo
        FROM tmp_ssoma_res r
        JOIN usuario u ON u.id_usuario = r.id_usuario
        WHERE r.estado IN ('bloqueado', 'pendiente');
    END IF;

    -- ── Cruces de horario con otros servicios de los mismos técnicos (dos lecturas separadas: una temporal por consulta) ──
    CREATE TEMPORARY TABLE tmp_det_cruce (numero VARCHAR(20) NOT NULL, id_usuario BIGINT NOT NULL);
    IF v_estado <> 'cancelada' THEN
        INSERT INTO tmp_det_cruce (numero, id_usuario)
        SELECT o.numero, t.id_usuario
        FROM orden_servicio o
        JOIN tmp_det_tec t ON t.id_usuario = o.id_tecnico_principal
        WHERE o.id_os <> v_id_os AND o.eliminado_en IS NULL
          AND o.estado IN ('programada', 'reprogramada', 'en_ruta', 'en_ejecucion', 'pausada', 'bloqueada')
          AND o.fecha_ejecucion = v_fecha AND o.hora_inicio < v_fin AND v_ini < o.hora_fin_estimada;
        INSERT INTO tmp_det_cruce (numero, id_usuario)
        SELECT o.numero, t.id_usuario
        FROM orden_servicio o
        JOIN os_personal pe ON pe.id_os = o.id_os AND pe.eliminado_en IS NULL
        JOIN tmp_det_tec t ON t.id_usuario = pe.id_usuario
        WHERE o.id_os <> v_id_os AND o.eliminado_en IS NULL
          AND o.estado IN ('programada', 'reprogramada', 'en_ruta', 'en_ejecucion', 'pausada', 'bloqueada')
          AND o.fecha_ejecucion = v_fecha AND o.hora_inicio < v_fin AND v_ini < o.hora_fin_estimada;
    END IF;
    SELECT COUNT(DISTINCT numero), GROUP_CONCAT(DISTINCT numero ORDER BY numero SEPARATOR ', ') INTO v_n_cruces, v_cruces FROM tmp_det_cruce;

    -- ── Cronograma válido ────────────────────────────────────────────────────
    IF v_fin <= v_ini THEN
        SET v_crono_ok = 0, v_crono_txt = 'La hora fin no es posterior a la hora de inicio.';
    ELSEIF v_n_cruces > 0 THEN
        SET v_crono_ok = 0, v_crono_txt = CONCAT('Se cruza con ', v_cruces, '.');
    ELSEIF v_activa = 1 AND v_fecha < CURDATE() THEN
        SET v_crono_ok = 0, v_crono_txt = CONCAT('La fecha ', DATE_FORMAT(v_fecha, '%d/%m/%Y'), ' ya pasó y el servicio no se ejecutó.');
    ELSE
        SET v_crono_txt = CONCAT(DATE_FORMAT(v_fecha, '%d/%m'), ' · ', TIME_FORMAT(v_ini, '%H:%i'), '-', TIME_FORMAT(v_fin, '%H:%i'));
    END IF;

    -- ── Checklist (siempre 4 ítems) ──────────────────────────────────────────
    CREATE TEMPORARY TABLE tmp_det_check (
        orden INT NOT NULL, item VARCHAR(30) NOT NULL, titulo VARCHAR(60) NOT NULL,
        cumple TINYINT NOT NULL, requiere_accion TINYINT NOT NULL, detalle VARCHAR(700) NULL
    );
    INSERT INTO tmp_det_check (orden, item, titulo, cumple, requiere_accion, detalle) VALUES
        (1, 'tecnico_asignado', 'Técnico asignado', IF(v_principal IS NULL, 0, 1), IF(v_principal IS NULL, 1, 0),
            IF(v_principal IS NULL, 'No hay técnico principal asignado.',
               CONCAT(v_principal, IF(v_n_tec > 1, CONCAT(' y ', v_n_tec - 1, ' de apoyo'), '')))),
        (2, 'equipos_reservados', 'Equipos reservados',
            IF(v_n_eq_prog > 0 OR v_n_eq_os = 0, 1, 0), IF(v_n_eq_prog > 0 OR v_n_eq_os = 0, 0, 1),
            IF(v_n_eq_prog > 0, CONCAT(v_n_eq_prog, IF(v_n_eq_prog = 1, ' equipo', ' equipos'), ' del listado de la OS'),
               IF(v_n_eq_os = 0, 'La OS no tiene equipos.', 'No hay equipos confirmados para esta programación.'))),
        (3, 'ssoma_habilitado', 'SSOMA habilitado',
            IF(v_aplica = 1 AND v_n_bloq > 0, 0, 1), IF(v_aplica = 1 AND v_n_bloq > 0, 1, 0),
            IF(v_aplica = 1 AND v_n_bloq > 0, CONCAT(v_motivo, ' — Requiere acción'),
               IF(v_aplica = 1, 'Habilitación vigente de todo el equipo', 'Sin validación (la programación ya no está vigente)'))),
        (4, 'cronograma_valido', 'Cronograma válido', v_crono_ok, IF(v_crono_ok = 1, 0, 1), v_crono_txt);

    -- ── Próximo paso ─────────────────────────────────────────────────────────
    SELECT resultado INTO v_ultimo FROM programacion_confirmacion
    WHERE id_programacion = p_id_programacion AND eliminado_en IS NULL ORDER BY id DESC LIMIT 1;

    SET v_proximo = CASE
        WHEN v_estado = 'cancelada'                          THEN 'Sin próximo paso: la programación está cancelada'
        WHEN v_aplica = 1 AND v_n_bloq > 0                   THEN 'Resolver el bloqueo SSOMA: reasignar técnico o reprogramar'
        WHEN v_ultimo = 'pidio_reprogramar' AND v_activa = 1 THEN 'Reprogramar: el cliente lo pidió (HU-38)'
        WHEN v_ultimo = 'cancelo'           AND v_activa = 1 THEN 'Cancelar la programación: el cliente la canceló (HU-38)'
        WHEN v_estado = 'pendiente_confirmacion'             THEN 'Registrar la respuesta del cliente'
        ELSE 'Ejecución en campo (Módulo 11)'
    END;

    -- 1. Header
    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Programación
    SELECT pr.id_programacion, pr.codigo, pr.estado,
           CASE pr.estado WHEN 'pendiente_confirmacion' THEN 'Pendiente confirmación cliente'
                          WHEN 'confirmada'             THEN 'Programado'
                          WHEN 'cancelada'              THEN 'Cancelada' END                            AS estado_label,
           os.id_os, os.numero AS numero_os, os.tipo, os.estado AS estado_os,
           os.id_expediente, e.numero AS numero_expediente,
           os.id_cliente, c.razon_social, c.ruc,
           os.id_sede, sc.nombre AS sede, sc.direccion_exacta AS ubicacion,
           COALESCE(os.id_propuesta, e.id_propuesta)                                                      AS id_propuesta,
           p.numero AS numero_propuesta, p.version AS version_propuesta,
           os.id_tipo_servicio, ts.String1 AS tipo_servicio,
           pr.fecha_ejecucion,
           TIME_FORMAT(pr.hora_inicio, '%H:%i')                                                           AS hora_inicio,
           TIME_FORMAT(pr.hora_fin_estimada, '%H:%i')                                                     AS hora_fin,
           ROUND(TIME_TO_SEC(TIMEDIFF(pr.hora_fin_estimada, pr.hora_inicio)) / 3600, 2)                   AS duracion_horas,
           pr.observaciones,
           v_principal                                                                                    AS tecnico_principal,
           v_n_tec                                                                                        AS n_tecnicos,
           v_n_eq_prog                                                                                    AS n_equipos,
           (SELECT COUNT(*) FROM os_concepto oc WHERE oc.id_os = os.id_os AND oc.eliminado_en IS NULL)    AS n_conceptos,
           v_proximo                                                                                      AS proximo_paso,
           pr.creado_en, TRIM(CONCAT(uc.nombre, ' ', uc.apellido))                                        AS creado_por_nombre,
           IF(v_aplica = 1 AND v_n_bloq > 0, 1, 0)                                                        AS bloqueo_ssoma_activo,
           -- Acciones (según los permisos del usuario del token y el estado)
           IF(v_gestiona = 1 AND v_activa = 1, 1, 0)                                                      AS puede_registrar_respuesta,
           IF(v_gestiona = 1 AND v_activa = 1, 1, 0)                                                      AS puede_reasignar,
           IF(v_activa = 1 AND (v_aprueba = 1 OR (v_gestiona = 1 AND v_pendiente IS NULL)), 1, 0)          AS puede_reprogramar,
           IF(v_aprueba = 1, 1, 0)                                                                        AS reprogramacion_directa,
           IF(v_gestiona = 1 AND v_aprueba = 0, 1, 0)                                                     AS reprogramacion_requiere_solicitud,
           IF(v_gestiona = 1 AND v_activa = 1, 1, 0)                                                      AS puede_cancelar,
           IF(v_estado = 'confirmada' AND v_activa = 1 AND v_aprueba = 1, 1, 0)                           AS puede_gestionar_viaticos,
           IF(os.id_expediente IS NOT NULL, 1, 0)                                                         AS puede_ver_expediente,
           v_pendiente                                                                                    AS id_solicitud_pendiente,
           IF(v_aprueba = 1 AND v_pendiente IS NOT NULL AND v_activa = 1, 1, 0)                           AS puede_resolver_solicitud
    FROM programacion pr
    JOIN orden_servicio os          ON os.id_os = pr.id_os
    LEFT JOIN cliente c             ON c.id_cliente = os.id_cliente
    LEFT JOIN sede_cliente sc       ON sc.id_sede = os.id_sede
    LEFT JOIN expediente_digital e  ON e.id_expediente = os.id_expediente
    LEFT JOIN propuesta_comercial p ON p.id_propuesta = COALESCE(os.id_propuesta, e.id_propuesta)
    LEFT JOIN tabla_maestra ts      ON ts.IdMaestro = 3 AND ts.IdEmpresa = 1 AND ts.Num1 = os.id_tipo_servicio
    LEFT JOIN usuario uc            ON uc.id_usuario = pr.creado_por
    WHERE pr.id_programacion = p_id_programacion;

    -- 3. Técnicos (principal primero) con la situación SSOMA al programar y la de hoy
    SELECT u.id_usuario, TRIM(CONCAT(u.nombre, ' ', u.apellido)) AS nombre,
           COALESCE(cg.String1, u.cargo, IF(u.area = 'metrologia', 'Metrología', 'Servicio Técnico')) AS cargo,
           pt.rol, pt.estado_ssoma AS ssoma_al_programar,
           r.estado AS ssoma_actual, IF(v_aplica = 1, NULLIF(r.motivo_bloqueo, ''), NULL) AS ssoma_motivo
    FROM programacion_tecnico pt
    JOIN usuario u            ON u.id_usuario = pt.id_usuario
    LEFT JOIN tabla_maestra cg ON cg.IdMaestro = 80 AND cg.IdEmpresa = 1 AND cg.String2 = u.cargo
    LEFT JOIN tmp_ssoma_res r  ON r.id_usuario = pt.id_usuario
    WHERE pt.id_programacion = p_id_programacion AND pt.eliminado_en IS NULL
    ORDER BY pt.rol = 'apoyo', u.nombre, u.apellido;

    -- 4. Equipos reservados
    SELECT ec.id_equipo, ec.codigo_tw, ec.marca, ec.modelo, ec.num_serie
    FROM programacion_equipo pe
    JOIN equipo_cliente ec ON ec.id_equipo = pe.id_equipo
    WHERE pe.id_programacion = p_id_programacion AND pe.eliminado_en IS NULL
    ORDER BY ec.codigo_tw, ec.id_equipo;

    -- 5. Conceptos del servicio
    SELECT oc.id AS id_os_concepto, oc.codigo, oc.descripcion, oc.alcance, IFNULL(oc.orden, oc.id) AS orden
    FROM os_concepto oc
    WHERE oc.id_os = v_id_os AND oc.eliminado_en IS NULL
    ORDER BY IFNULL(oc.orden, oc.id);

    -- 6. Checklist de validación
    SELECT item, titulo, cumple, requiere_accion, detalle FROM tmp_det_check ORDER BY orden;

    -- 7. Alertas SSOMA sobrevenidas (críticas = bloquean la ejecución; advertencias = vencen pronto).
    --    Se arman con varias sentencias: MySQL no reabre una temporal en la misma consulta (un UNION lee tmp_ssoma_det dos veces).
    CREATE TEMPORARY TABLE tmp_det_alerta (
        severidad VARCHAR(12) NOT NULL, id_usuario BIGINT NOT NULL, tecnico VARCHAR(200) NULL, requisito VARCHAR(255) NULL,
        situacion VARCHAR(20) NULL, estado_doc VARCHAR(20) NULL, fecha_vencimiento DATE NULL, dias_vencido INT NULL,
        ya_vencio TINYINT NOT NULL DEFAULT 0, mensaje VARCHAR(900) NULL
    );
    INSERT INTO tmp_det_alerta (severidad, id_usuario, tecnico, requisito, situacion, estado_doc, fecha_vencimiento, dias_vencido, ya_vencio, mensaje)
    SELECT 'critica', d.id_usuario, TRIM(CONCAT(u.nombre, ' ', u.apellido)) AS tecnico,
           d.requisito, d.situacion, d.estado_doc, d.fecha_vencimiento,
           IF(d.fecha_vencimiento IS NOT NULL AND d.fecha_vencimiento < CURDATE(), DATEDIFF(CURDATE(), d.fecha_vencimiento), NULL) AS dias_vencido,
           IF(d.estado_doc = 'vencido' OR (d.fecha_vencimiento IS NOT NULL AND d.fecha_vencimiento < CURDATE()), 1, 0) AS ya_vencio,
           CASE WHEN d.estado_doc = 'observado'
                    THEN CONCAT('El documento ', d.requisito, ' de ', TRIM(CONCAT(u.nombre, ' ', u.apellido)), ' está observado.')
                WHEN d.estado_doc = 'vencido' OR d.fecha_vencimiento < CURDATE()
                    THEN CONCAT('El ', d.requisito, ' de ', TRIM(CONCAT(u.nombre, ' ', u.apellido)), ' venció el ',
                                IFNULL(DATE_FORMAT(d.fecha_vencimiento, '%d/%m/%Y'), '(fecha no registrada)'),
                                IF(d.fecha_vencimiento IS NULL, '', CONCAT(' (hoy +', DATEDIFF(CURDATE(), d.fecha_vencimiento), ' días)')),
                                '. La ejecución queda bloqueada hasta reasignar o reprogramar.')
                ELSE CONCAT('El ', d.requisito, ' de ', TRIM(CONCAT(u.nombre, ' ', u.apellido)), ' vence el ',
                            DATE_FORMAT(d.fecha_vencimiento, '%d/%m/%Y'), ', antes de la fecha del servicio. Reasigna o reprograma.')
           END AS mensaje
    FROM tmp_ssoma_det d
    JOIN usuario u ON u.id_usuario = d.id_usuario
    WHERE v_aplica = 1 AND d.situacion = 'bloqueado' AND d.bloquea = 1;
    INSERT INTO tmp_det_alerta (severidad, id_usuario, tecnico, requisito, situacion, estado_doc, fecha_vencimiento, dias_vencido, ya_vencio, mensaje)
    SELECT 'advertencia', d.id_usuario, TRIM(CONCAT(u.nombre, ' ', u.apellido)), d.requisito, d.situacion, d.estado_doc,
           d.fecha_vencimiento, NULL, 0,
           CONCAT('El ', d.requisito, ' de ', TRIM(CONCAT(u.nombre, ' ', u.apellido)), ' vence el ',
                  DATE_FORMAT(d.fecha_vencimiento, '%d/%m/%Y'), '; coordina su renovación con SSOMA.')
    FROM tmp_ssoma_det d
    JOIN usuario u ON u.id_usuario = d.id_usuario
    WHERE v_aplica = 1 AND d.situacion = 'por_vencer' AND d.requerido = 1;
    INSERT INTO tmp_det_alerta (severidad, id_usuario, tecnico, requisito, situacion, estado_doc, fecha_vencimiento, dias_vencido, ya_vencio, mensaje)
    SELECT 'critica', r.id_usuario, TRIM(CONCAT(u.nombre, ' ', u.apellido)),
           IF(r.bloqueado_en_otra_os = 1, 'Bloqueo SSOMA en otra orden', 'Documento SSOMA faltante'),
           IF(r.bloqueado_en_otra_os = 1, 'bloqueado', 'sin_documento'), NULL, NULL, NULL, 0,
           IF(r.bloqueado_en_otra_os = 1,
              CONCAT(TRIM(CONCAT(u.nombre, ' ', u.apellido)), ' figura bloqueado por SSOMA en otra orden activa.'),
              CONCAT('A ', TRIM(CONCAT(u.nombre, ' ', u.apellido)), ' le falta el documento que pide el cliente: ', IFNULL(r.faltantes, 'SSOMA'), '.'))
    FROM tmp_ssoma_res r
    JOIN usuario u ON u.id_usuario = r.id_usuario
    WHERE v_aplica = 1 AND (r.bloqueado_en_otra_os = 1 OR r.estado = 'pendiente');
    SELECT severidad, id_usuario, tecnico, requisito, situacion, estado_doc, fecha_vencimiento, dias_vencido, ya_vencio, mensaje
    FROM tmp_det_alerta ORDER BY severidad, tecnico, requisito;

    -- 8. Historial (timeline)
    SELECT x.fecha, x.tipo, x.titulo, x.descripcion, x.usuario, x.estado_anterior, x.estado_nuevo, x.motivo
    FROM (
        SELECT ae.registrado_en AS fecha, 1 AS ord,
               CASE ae.accion WHEN 'programar_os'   THEN 'programacion'
                              WHEN 'respuesta_cliente' THEN 'respuesta_cliente'
                              WHEN 'anular_os'      THEN 'cancelacion'
                              WHEN 'cancelar_programacion' THEN 'cancelacion'
                              WHEN 'solicitar_reprogramacion' THEN 'reprogramacion'
                              WHEN 'reprogramacion_directa' THEN 'reprogramacion'
                              WHEN 'aprobar_reprogramacion' THEN 'aprobacion'
                              WHEN 'rechazar_reprogramacion' THEN 'aprobacion'
                              WHEN 'retirar_solicitud_reprogramacion' THEN 'aprobacion'
                              ELSE 'estado' END                                       AS tipo,
               CASE ae.accion WHEN 'programar_os'   THEN 'Programación creada'
                              WHEN 'respuesta_cliente' THEN 'Respuesta del cliente'
                              WHEN 'anular_os'      THEN 'Orden anulada: programación cancelada'
                              WHEN 'cancelar_programacion' THEN 'Programación cancelada'
                              WHEN 'solicitar_reprogramacion' THEN 'Reprogramación solicitada'
                              WHEN 'reprogramacion_directa' THEN 'Reprogramación (edición directa del Jefe)'
                              WHEN 'aprobar_reprogramacion' THEN 'Reprogramación aprobada'
                              WHEN 'rechazar_reprogramacion' THEN 'Reprogramación rechazada'
                              WHEN 'retirar_solicitud_reprogramacion' THEN 'Solicitud de reprogramación retirada'
                              ELSE ae.accion END                                      AS titulo,
               ae.descripcion, TRIM(CONCAT(ua.nombre, ' ', ua.apellido))              AS usuario,
               ae.estado_anterior, ae.estado_nuevo, JSON_UNQUOTE(JSON_EXTRACT(ae.metadata, '$.motivo')) AS motivo
        FROM auditoria_evento ae
        LEFT JOIN usuario ua ON ua.id_usuario = ae.id_usuario
        WHERE (ae.entidad_tipo = 'programacion' AND ae.id_entidad = p_id_programacion)
           OR (ae.entidad_tipo = 'orden_servicio' AND ae.id_entidad = v_id_os
               AND ((ae.accion = 'programar_os'
                     AND CAST(JSON_UNQUOTE(JSON_EXTRACT(ae.metadata, '$.idProgramacion')) AS UNSIGNED) = p_id_programacion)
                    OR (ae.accion = 'anular_os' AND ae.registrado_en >= v_creado)))
        UNION ALL
        SELECT rp.fecha_solicitud, 2, 'reprogramacion', 'Reprogramación solicitada',
               CONCAT('Propone el ', DATE_FORMAT(rp.fecha_propuesta, '%d/%m/%Y'),
                      IF(rp.hora_propuesta IS NULL, '', CONCAT(' a las ', TIME_FORMAT(rp.hora_propuesta, '%H:%i'))), '. ', rp.comentario),
               TRIM(CONCAT(us.nombre, ' ', us.apellido)), NULL, NULL, mo.String1
        FROM os_reprogramacion rp
        LEFT JOIN usuario us        ON us.id_usuario = rp.id_solicitante
        LEFT JOIN tabla_maestra mo  ON mo.IdMaestro = 13 AND mo.IdEmpresa = 1 AND mo.Num1 = rp.id_motivo
        WHERE rp.id_os = v_id_os AND rp.id_programacion IS NULL AND rp.eliminado_en IS NULL AND rp.fecha_solicitud >= v_creado
        UNION ALL
        SELECT rp.fecha_resolucion, 3, 'aprobacion',
               CASE rp.estado WHEN 'aprobada' THEN 'Reprogramación aprobada' WHEN 'rechazada' THEN 'Reprogramación rechazada'
                              ELSE 'Solicitud de reprogramación cancelada' END,
               rp.comentario_resolucion, TRIM(CONCAT(ur.nombre, ' ', ur.apellido)), 'pendiente', rp.estado, mo.String1
        FROM os_reprogramacion rp
        LEFT JOIN usuario ur        ON ur.id_usuario = rp.resuelto_por
        LEFT JOIN tabla_maestra mo  ON mo.IdMaestro = 13 AND mo.IdEmpresa = 1 AND mo.Num1 = rp.id_motivo
        WHERE rp.id_os = v_id_os AND rp.id_programacion IS NULL AND rp.eliminado_en IS NULL AND rp.fecha_solicitud >= v_creado
          AND rp.estado <> 'pendiente' AND rp.fecha_resolucion IS NOT NULL
    ) x
    ORDER BY x.fecha, x.ord;

    -- 9. Respuestas del cliente registradas (la más reciente primero)
    SELECT pc.id, pc.canal,
           CASE pc.canal WHEN 'correo' THEN 'Correo' WHEN 'whatsapp' THEN 'WhatsApp'
                         WHEN 'llamada' THEN 'Llamada' ELSE 'Presencial' END            AS canal_label,
           pc.resultado,
           CASE pc.resultado WHEN 'acepto' THEN 'Aceptó la programación'
                             WHEN 'pidio_reprogramar' THEN 'Pidió reprogramar' ELSE 'Canceló' END AS resultado_label,
           pc.comentario, pc.fecha_registro, TRIM(CONCAT(ur.nombre, ' ', ur.apellido)) AS registrado_por,
           pc.informe_fisico
    FROM programacion_confirmacion pc
    LEFT JOIN usuario ur ON ur.id_usuario = pc.id_registrado_por
    WHERE pc.id_programacion = p_id_programacion AND pc.eliminado_en IS NULL
    ORDER BY pc.id DESC;

    DROP TEMPORARY TABLE IF EXISTS tmp_det_tec;
    DROP TEMPORARY TABLE IF EXISTS tmp_det_cruce;
    DROP TEMPORARY TABLE IF EXISTS tmp_det_check;
    DROP TEMPORARY TABLE IF EXISTS tmp_det_alerta;
    DROP TEMPORARY TABLE IF EXISTS tmp_ssoma_in;
    CALL SP_LimpiarSsomaProgramacion();
END$$

DELIMITER ;

-- ============================================================
-- SP_ResumenEvidenciasMovil  (App Mobile HU-11 / HU-08 — apoyo, no es un endpoint)
-- Avance del registro fotográfico de un equipo, UNA sola vez. Lo usan el panel de evidencias y la etapa "Registro fotográfico" del trabajo en el equipo.
--   Evidencia COMPLETA = su última captura (vigente, página 1) está aprobada por la IA, fue forzada por el técnico (HU-12) o no se pudo validar con la IA
--   ("omitida": no cuenta como rechazo). Una toma rechazada y no forzada NO completa la evidencia.
-- Informe físico: sin él (orden_servicio.informe_fisico = 0, lo decide la respuesta del cliente a la programación) la evidencia «informe» NO forma parte del catálogo (8 en vez de 9).
-- Deja la tabla temporal tmp_cat_evid armada, con completa / forzada / rechazada por evidencia (quien llama la borra; HU-16 lista las que faltan). Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ResumenEvidenciasMovil;

DELIMITER $$

CREATE PROCEDURE SP_ResumenEvidenciasMovil(
    IN  p_id_os          BIGINT,
    IN  p_id_equipo      BIGINT,
    OUT p_total          INT,
    OUT p_completas      INT,
    OUT p_forzadas       INT,
    OUT p_rechazadas     INT,
    OUT p_oblig_faltan   INT
)
BEGIN
    CALL SP_CatalogoEvidenciasMovil();

    -- Si el cliente respondió que el servicio NO tendrá informe físico (orden_servicio.informe_fisico = 0), la foto del informe a mano no se pide: se quita del
    -- catálogo y el registro fotográfico pasa de 9 a 8 evidencias (NULL o 1 = lleva informe físico, como siempre). Es el único lugar donde vive esta regla.
    DELETE FROM tmp_cat_evid
    WHERE  codigo = 'informe'
      AND  EXISTS (SELECT 1 FROM orden_servicio os WHERE os.id_os = p_id_os AND os.informe_fisico = 0);

    -- Última toma vigente (página 1) de cada evidencia: completa = aprobada por la IA, forzada o sin validar ('omitida'); una rechazada y no forzada NO completa
    UPDATE tmp_cat_evid c
    JOIN  (SELECT f2.codigo, MAX(f2.id_evidencia) AS id_ultima
           FROM   evidencia_fotografica f2
           WHERE  f2.id_os = p_id_os AND f2.id_equipo = p_id_equipo AND f2.pagina = 1 AND f2.vigente = 1 AND f2.eliminado_en IS NULL
           GROUP BY f2.codigo) u ON u.codigo = c.codigo
    JOIN   evidencia_fotografica f ON f.id_evidencia = u.id_ultima
    SET    c.completa  = IF(f.override_aprobado = 1 OR f.validacion_ia IN ('aprobada', 'omitida'), 1, 0),
           c.forzada   = IF(f.override_aprobado = 1, 1, 0),
           c.rechazada = IF(f.override_aprobado = 0 AND f.validacion_ia = 'rechazada', 1, 0);

    SELECT COUNT(*), IFNULL(SUM(completa), 0), IFNULL(SUM(forzada), 0), IFNULL(SUM(rechazada), 0), IFNULL(SUM(obligatoria = 1 AND completa = 0), 0)
    INTO   p_total, p_completas, p_forzadas, p_rechazadas, p_oblig_faltan
    FROM   tmp_cat_evid;
END$$

DELIMITER ;

-- ============================================================
-- SP_RegistrarEvidenciaMovil  (App Mobile HU-11 / HU-13 — guarda una captura del panel de evidencias · escritura)
-- Guarda UN intento de captura (foto, microvideo de encendido o lectura del QR) con el resultado de la validación IA que ya hizo el back.
--   - Acceso: SP_ContextoEquipoMovil (OS del técnico, Hard Stop) y el equipo EN EJECUCIÓN.
--   - p_codigo: una de las 9 evidencias (SP_CatalogoEvidenciasMovil). p_pagina: solo el informe a mano admite varias hojas (1 a 10).
--   - Encendido (HU-13): el microvideo dura de 3 a 5 s (se tolera 0,5 s). p_ruta_cuadro = cuadro de la imagen que analizó la IA.
--   - QR: p_qr_texto es lo que leyó la cámara; debe corresponder a ESTE equipo (N/S, código del cliente o COD TW, igual que la búsqueda por QR de la HU-07) o ser una
--     etiqueta QR de TW (enlace q.me-qr.com/… o tw.com.pe/e/…, SP_NormalizarQrMovil) vinculada a este equipo en equipo_qr: la primera lectura de una etiqueta que no
--     pertenece a nadie la vincula a este equipo; una etiqueta de OTRO equipo se rechaza.
--   - p_ia_estado = aprobada | rechazada | omitida (la IA no estuvo disponible: no bloquea) con p_ia_motivo y p_ia_json (lo que leyó).
--     Placa: si la IA leyó la serie y no coincide con la del equipo, la toma se RECHAZA aquí (la regla vive solo en este SP).
--   - Cada captura es un intento nuevo (intento = 1, 2, 3…); la última queda vigente y reemplaza a la anterior. Una toma rechazada se puede
--     aceptar a la fuerza con SP_ForzarEvidenciaMovil (HU-12).
--   - p_codigo = 'adicional' (fotos adicionales, opcionales): foto extra del servicio, hasta 20 por equipo; el SP le asigna el número; NO pasa por la IA
--     (queda 'omitida'), no forma parte de las 9 ni cuenta para "Guardar y volver".
--   - Deja el registro en auditoria_evento.
-- Resultados: 1 mensaje; 2 (id_evidencia, estado, motivo_rechazo, intento, coincide, numero_rq).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_RegistrarEvidenciaMovil;

DELIMITER $$

CREATE PROCEDURE SP_RegistrarEvidenciaMovil(
    IN p_id_usuario    BIGINT,
    IN p_id_os         BIGINT,
    IN p_id_os_equipo  BIGINT,
    IN p_codigo        VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_pagina        INT,
    IN p_ruta_archivo  VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_ruta_cuadro   VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_duracion      DECIMAL(5,1),
    IN p_latitud       DECIMAL(10,7),
    IN p_longitud      DECIMAL(10,7),
    IN p_precision     DECIMAL(8,1),
    IN p_capturado_utc DATETIME,
    IN p_qr_texto      VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_ia_estado     VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_ia_motivo     VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_ia_json       LONGTEXT     CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_msg      VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_eq    BIGINT;
    DECLARE v_est_eq   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_hab      TINYINT;
    DECLARE v_numero   INT;
    DECLARE v_nombre   VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_num_os   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_servicio VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_tipo  INT DEFAULT NULL;
    DECLARE v_medio    VARCHAR(6) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_pagina   INT;
    DECLARE v_serie    VARCHAR(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cod_tw   VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cod_cli  VARCHAR(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_qr       VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado   VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_motivo   VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_json     LONGTEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_serie_ia VARCHAR(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_coincide TINYINT DEFAULT NULL;
    DECLARE v_rq       VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_intento  INT DEFAULT 1;
    DECLARE v_id_evid  BIGINT;
    DECLARE v_ahora    DATETIME;
    DECLARE v_capt     DATETIME;
    DECLARE v_clave    VARCHAR(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_vinc_eq  BIGINT DEFAULT NULL;
    DECLARE v_vinc_cod VARCHAR(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_filas    INT DEFAULT 0;
    DECLARE v_vinculado TINYINT DEFAULT 0;
    DECLARE v_motivo_qr VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
        DROP TEMPORARY TABLE IF EXISTS tmp_cat_evid;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 OR IFNULL(p_id_os_equipo, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio o equipo no encontrado.' AS Mensaje; LEAVE proc;
    END IF;
    SET v_estado = LOWER(TRIM(IFNULL(p_ia_estado, 'omitida')));
    IF v_estado NOT IN ('aprobada', 'rechazada', 'omitida') THEN
        SELECT 1 AS IdTipoMensaje, 'El resultado de la validación no es válido.' AS Mensaje; LEAVE proc;
    END IF;
    IF p_latitud IS NOT NULL AND (p_latitud NOT BETWEEN -90 AND 90 OR p_longitud IS NULL OR p_longitud NOT BETWEEN -180 AND 180) THEN
        SELECT 1 AS IdTipoMensaje, 'La ubicación GPS no es válida.' AS Mensaje; LEAVE proc;
    END IF;
    SET v_json = IF(p_ia_json IS NOT NULL AND JSON_VALID(p_ia_json) AND CHAR_LENGTH(p_ia_json) <= 8000, p_ia_json, NULL);
    SET v_motivo = LEFT(NULLIF(TRIM(IFNULL(p_ia_motivo, '')), ''), 300);

    SET p_codigo = LOWER(TRIM(IFNULL(p_codigo, '')));
    IF p_codigo = 'adicional' THEN
        -- Fotos adicionales: extras opcionales del servicio. No forman parte de las 9 del panel, no pasan por la IA y no cuentan para "Guardar y volver"
        SET v_id_tipo = 2, v_medio = 'foto', v_estado = 'omitida', v_json = NULL, v_motivo = NULL;
    ELSE
        CALL SP_CatalogoEvidenciasMovil();
        SELECT c.id_tipo, c.medio INTO v_id_tipo, v_medio FROM tmp_cat_evid c WHERE c.codigo = p_codigo;
        DROP TEMPORARY TABLE IF EXISTS tmp_cat_evid;
    END IF;
    IF v_id_tipo IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'La evidencia no existe en el panel.' AS Mensaje; LEAVE proc;
    END IF;
    SET v_pagina = IF(p_codigo = 'informe', IFNULL(p_pagina, 1), 1);
    IF v_pagina < 1 OR v_pagina > 10 THEN
        SELECT 1 AS IdTipoMensaje, 'El informe admite hasta 10 hojas.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_medio = 'video' AND (p_duracion IS NULL OR p_duracion < 2.5 OR p_duracion > 5.5) THEN
        SELECT 1 AS IdTipoMensaje, 'El microvideo debe durar de 3 a 5 segundos.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_medio = 'qr' THEN
        SET v_qr = UPPER(TRIM(IFNULL(p_qr_texto, '')));
        IF v_qr = '' OR CHAR_LENGTH(v_qr) > 300 THEN
            SELECT 1 AS IdTipoMensaje, 'El código leído no es válido.' AS Mensaje; LEAVE proc;
        END IF;
    ELSEIF NULLIF(TRIM(IFNULL(p_ruta_archivo, '')), '') IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Falta el archivo de la captura.' AS Mensaje; LEAVE proc;
    END IF;

    SET v_ahora = UTC_TIMESTAMP();
    SET v_capt  = v_ahora;
    IF p_capturado_utc IS NOT NULL AND p_capturado_utc >= v_ahora - INTERVAL 24 HOUR AND p_capturado_utc <= v_ahora + INTERVAL 5 MINUTE THEN
        SET v_capt = LEAST(p_capturado_utc, v_ahora);
    END IF;

    START TRANSACTION;

    CALL SP_ContextoEquipoMovil(p_id_usuario, p_id_os, p_id_os_equipo, v_msg, v_id_eq, v_est_eq, v_hab, v_numero, v_nombre, v_num_os, v_servicio);
    IF v_msg IS NULL AND (v_hab = 0 OR v_est_eq <> 'en_ejecucion') THEN
        SET v_msg = IF(v_est_eq = 'pausado', 'El equipo está pausado: reanúdalo para registrar evidencias.',
                       IF(v_est_eq = 'completado', 'Este equipo ya está completado.', 'El servicio ya no está en curso: no se pueden registrar evidencias.'));
    END IF;
    IF v_msg IS NOT NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje; LEAVE proc;
    END IF;

    -- Sin informe físico (la respuesta del cliente a la programación) no se toma la foto del informe a mano
    IF p_codigo = 'informe' AND EXISTS (SELECT 1 FROM orden_servicio os WHERE os.id_os = p_id_os AND os.informe_fisico = 0) THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Este servicio no tiene informe físico: no se toma la foto del informe.' AS Mensaje; LEAVE proc;
    END IF;

    -- Foto adicional: el SP asigna el número (1, 2, 3…) y no admite más de 20 por equipo
    IF p_codigo = 'adicional' THEN
        SELECT IFNULL(MAX(f.pagina), 0) + 1 INTO v_pagina
        FROM   evidencia_fotografica f
        WHERE  f.id_os = p_id_os AND f.id_equipo = v_id_eq AND f.codigo = 'adicional' AND f.eliminado_en IS NULL;
        IF v_pagina > 20 THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, 'Un equipo admite hasta 20 fotos adicionales. Quita alguna para agregar otra.' AS Mensaje; LEAVE proc;
        END IF;
    END IF;

    SELECT NULLIF(TRIM(ec.num_serie), ''), ec.codigo_tw, NULLIF(ec.codigo_cliente, '') INTO v_serie, v_cod_tw, v_cod_cli
    FROM   equipo_cliente ec WHERE ec.id_equipo = v_id_eq;
    SELECT rq.numero INTO v_rq
    FROM   orden_servicio os
    JOIN   expediente_digital ed ON ed.id_expediente = os.id_expediente
    JOIN   requerimiento      rq ON rq.id_requerimiento = ed.id_requerimiento
    WHERE  os.id_os = p_id_os LIMIT 1;

    -- Reglas propias de cada evidencia
    IF v_medio = 'qr' THEN
        SET v_coincide = IF(UPPER(IFNULL(v_serie, '')) = v_qr OR UPPER(IFNULL(v_cod_cli, '')) = v_qr OR UPPER(IFNULL(v_cod_tw, '')) = v_qr
                            OR (CHAR_LENGTH(IFNULL(v_cod_tw, '')) >= 5 AND LOCATE(UPPER(v_cod_tw), v_qr) > 0)
                            OR (CHAR_LENGTH(IFNULL(v_cod_cli, '')) >= 5 AND LOCATE(UPPER(v_cod_cli), v_qr) > 0), 1, 0);
        -- Etiqueta QR de TW (enlace corto q.me-qr.com/… o tw.com.pe/e/…): no trae el código del equipo, así que se reconoce por su clave (SP_NormalizarQrMovil).
        -- Si ya está vinculada a ESTE equipo, coincide; si no pertenece a nadie, queda vinculada a este equipo (primera lectura); si es de otro, se rechaza.
        IF v_coincide = 0 THEN
            CALL SP_NormalizarQrMovil(p_qr_texto, v_clave);
            IF v_clave IS NOT NULL THEN
                SELECT q.id_equipo INTO v_vinc_eq FROM equipo_qr q WHERE q.clave = v_clave AND q.eliminado_en IS NULL LIMIT 1;
                IF v_vinc_eq IS NULL THEN
                    INSERT IGNORE INTO equipo_qr (id_equipo, clave, texto, creado_por) VALUES (v_id_eq, v_clave, LEFT(TRIM(p_qr_texto), 300), p_id_usuario);
                    SET v_filas = ROW_COUNT();
                    SELECT q.id_equipo INTO v_vinc_eq FROM equipo_qr q WHERE q.clave = v_clave AND q.eliminado_en IS NULL LIMIT 1;
                    SET v_vinculado = IF(v_filas = 1, 1, 0);
                END IF;
                IF v_vinc_eq = v_id_eq THEN
                    SET v_coincide = 1;
                ELSE
                    SELECT COALESCE(NULLIF(ec.codigo_cliente, ''), NULLIF(ec.codigo_tw, ''), ec.num_serie) INTO v_vinc_cod FROM equipo_cliente ec WHERE ec.id_equipo = v_vinc_eq;
                    SET v_motivo_qr = LEFT(CONCAT('Este QR ya pertenece a otro equipo (', IFNULL(v_vinc_cod, 'sin código'), '). Escanea la etiqueta del equipo que estás trabajando.'), 300);
                END IF;
            END IF;
        END IF;
        SET v_estado = IF(v_coincide = 1, 'aprobada', 'rechazada');
        SET v_motivo = IF(v_coincide = 1, NULL, COALESCE(v_motivo_qr, 'El QR leído no corresponde a este equipo. Escanea la etiqueta del equipo que estás trabajando.'));
        SET v_json = JSON_OBJECT('qr', LEFT(TRIM(p_qr_texto), 300), 'vinculado', v_vinculado = 1);
        SET p_ruta_archivo = 'qr://leido';
    ELSEIF p_codigo = 'placa' AND v_estado = 'aprobada' AND v_json IS NOT NULL THEN
        SET v_serie_ia = NULLIF(UPPER(REGEXP_REPLACE(IFNULL(JSON_UNQUOTE(JSON_EXTRACT(v_json, '$.serie')), ''), '[^A-Za-z0-9]', '')), '');
        IF v_serie_ia IS NOT NULL AND v_serie IS NOT NULL THEN
            SET v_coincide = IF(v_serie_ia = UPPER(REGEXP_REPLACE(v_serie, '[^A-Za-z0-9]', '')), 1, 0);
            IF v_coincide = 0 THEN
                SET v_estado = 'rechazada';
                SET v_motivo = LEFT(CONCAT('La serie de la placa (', JSON_UNQUOTE(JSON_EXTRACT(v_json, '$.serie')), ') no coincide con la del equipo (', v_serie, ').'), 300);
            END IF;
        END IF;
    END IF;
    IF v_estado = 'rechazada' AND v_motivo IS NULL THEN SET v_motivo = 'La IA no pudo validar la toma. Repite la foto con mejor luz y enfoque.'; END IF;
    IF v_estado <> 'rechazada' THEN SET v_motivo = NULL; END IF;

    -- Intento nuevo: el último queda vigente y reemplaza al anterior de esa evidencia (y página)
    SELECT IFNULL(MAX(f.intento), 0) + 1 INTO v_intento
    FROM   evidencia_fotografica f
    WHERE  f.id_os = p_id_os AND f.id_equipo = v_id_eq AND f.codigo = p_codigo AND f.pagina = v_pagina AND f.eliminado_en IS NULL;
    UPDATE evidencia_fotografica SET vigente = 0
    WHERE  id_os = p_id_os AND id_equipo = v_id_eq AND codigo = p_codigo AND pagina = v_pagina AND vigente = 1 AND eliminado_en IS NULL;

    INSERT INTO evidencia_fotografica (id_os, id_equipo, id_usuario, id_tipo_evidencia, url_archivo, latitud, longitud, timestamp_captura, validacion_ia,
                                       override_aprobado, codigo, pagina, es_video, duracion_seg, precision_m, intento, vigente, motivo_rechazo_ia, resultado_ia,
                                       ruta_cuadro, creado_por)
    VALUES (p_id_os, v_id_eq, p_id_usuario, v_id_tipo, IFNULL(NULLIF(TRIM(p_ruta_archivo), ''), 'qr://leido'), p_latitud, p_longitud, v_capt, v_estado,
            0, p_codigo, v_pagina, IF(v_medio = 'video', 1, 0), IF(v_medio = 'video', p_duracion, NULL), p_precision, v_intento, 1, v_motivo, v_json,
            NULLIF(TRIM(IFNULL(p_ruta_cuadro, '')), ''), p_id_usuario);
    SET v_id_evid = LAST_INSERT_ID();

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('os_equipo', p_id_os_equipo, 'registrar_evidencia', NULL, v_estado,
            LEFT(CONCAT('Evidencia ', p_codigo, IF(v_pagina > 1, CONCAT(' (hoja ', v_pagina, ')'), ''), ' de ', v_num_os, ' · intento ', v_intento, ': ', v_estado,
                        IF(v_motivo IS NULL, '', CONCAT('. ', v_motivo))), 900),
            p_id_usuario, NOW(),
            JSON_OBJECT('id_evidencia', v_id_evid, 'codigo', p_codigo, 'intento', v_intento, 'resultado', v_estado));

    COMMIT;

    SELECT 2 AS IdTipoMensaje,
           CASE WHEN v_medio = 'qr' AND v_estado = 'aprobada' THEN IF(v_vinculado = 1, 'QR leído y vinculado a este equipo.', 'QR del equipo leído.')
                WHEN v_medio = 'qr' THEN 'El QR no corresponde a este equipo.'
                WHEN p_codigo = 'adicional' THEN 'Foto adicional guardada.'
                ELSE CASE v_estado WHEN 'aprobada' THEN 'Evidencia guardada y validada por la IA.'
                         WHEN 'omitida'  THEN 'Evidencia guardada (la IA no estuvo disponible para validarla).'
                         ELSE 'La IA rechazó la toma.' END END AS Mensaje;
    SELECT v_id_evid AS id_evidencia, v_estado AS estado, v_motivo AS motivo_rechazo, v_intento AS intento, v_coincide AS coincide, v_rq AS numero_rq;
END$$

DELIMITER ;

-- ============================================================
-- SP_ObtenerEvidenciasMovil  (App Mobile HU-11 / HU-12 / HU-13 — panel de evidencias del equipo · lectura)
-- El panel del "Registro fotográfico": las 9 evidencias (SP_CatalogoEvidenciasMovil) con su estado, el avance "N de 9 completas" y lo que necesita el
-- botón "Guardar y volver" (puede_guardar = todas completas: 9, u 8 si el servicio no tiene informe físico, ver SP_ResumenEvidenciasMovil; la cabecera trae informe_fisico). Acceso: SP_ContextoEquipoMovil (OS del técnico, Hard Stop, equipo iniciado).
--   estado de cada evidencia: pendiente | aprobada | rechazada | forzada | omitida  (omitida = la IA no estuvo disponible; cuenta como completa)
--   Para una evidencia FORZADA (HU-12) trae lo de "Ver detalles": motivo del técnico, rechazo de la IA, quién la aceptó, cuándo y los intentos previos.
--   Informe a mano: paginas = hojas válidas; la tarjeta muestra la primera.
-- Resultados: 1 mensaje · 2 cabecera (1 fila) · 3 evidencias (9 filas) · 4 fotos adicionales (0 a 20 filas; no cuentan en el avance ni en "Guardar y volver").
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerEvidenciasMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerEvidenciasMovil(
    IN p_id_usuario   BIGINT,
    IN p_id_os        BIGINT,
    IN p_id_os_equipo BIGINT
)
proc: BEGIN
    DECLARE v_msg      VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_eq    BIGINT;
    DECLARE v_est_eq   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_hab      TINYINT;
    DECLARE v_numero   INT;
    DECLARE v_nombre   VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_num_os   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_servicio VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_rq       VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_total    INT;
    DECLARE v_compl    INT;
    DECLARE v_forz     INT;
    DECLARE v_rech     INT;
    DECLARE v_oblig    INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
        DROP TEMPORARY TABLE IF EXISTS tmp_cat_evid;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    CALL SP_ContextoEquipoMovil(p_id_usuario, p_id_os, p_id_os_equipo, v_msg, v_id_eq, v_est_eq, v_hab, v_numero, v_nombre, v_num_os, v_servicio);
    IF v_msg IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT rq.numero INTO v_rq
    FROM   orden_servicio os
    JOIN   expediente_digital ed ON ed.id_expediente = os.id_expediente
    JOIN   requerimiento      rq ON rq.id_requerimiento = ed.id_requerimiento
    WHERE  os.id_os = p_id_os LIMIT 1;

    CALL SP_ResumenEvidenciasMovil(p_id_os, v_id_eq, v_total, v_compl, v_forz, v_rech, v_oblig);

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Cabecera
    SELECT p_id_os AS id_os, p_id_os_equipo AS id_os_equipo, v_num_os AS numero_os, v_nombre AS nombre, v_numero AS numero, v_servicio AS servicio_sigla,
           NULLIF(TRIM(ec.num_serie), '') AS num_serie, NULLIF(ec.codigo_cliente, '') AS codigo_cliente, ec.codigo_tw, ec.marca, ec.modelo,
           v_est_eq AS estado, IF(v_est_eq = 'en_ejecucion' AND v_hab = 1, 1, 0) AS puede_registrar, v_rq AS numero_rq,
           v_total AS total, v_compl AS completas, v_forz AS forzadas, v_rech AS rechazadas, v_oblig AS obligatorias_faltan,
           IF(v_compl = v_total, 1, 0) AS puede_guardar,
           IF(EXISTS (SELECT 1 FROM orden_servicio os WHERE os.id_os = p_id_os AND os.informe_fisico = 0), 0, 1) AS informe_fisico
    FROM   equipo_cliente ec WHERE ec.id_equipo = v_id_eq;

    -- 3. Las 9 evidencias (la última captura de cada una)
    SELECT c.orden, c.codigo, c.nombre, c.descripcion, c.obligatoria, c.medio,
           CASE WHEN f.id_evidencia IS NULL THEN 'pendiente'
                WHEN f.override_aprobado = 1 THEN 'forzada'
                ELSE f.validacion_ia END AS estado,
           f.id_evidencia, f.intento, f.es_video, f.duracion_seg,
           (SELECT COUNT(*) FROM evidencia_fotografica p
            WHERE p.id_os = p_id_os AND p.id_equipo = v_id_eq AND p.codigo = c.codigo AND p.vigente = 1 AND p.eliminado_en IS NULL
              AND (p.override_aprobado = 1 OR p.validacion_ia <> 'rechazada')) AS paginas,
           f.motivo_rechazo_ia, f.motivo_forzado,
           TRIM(CONCAT(IFNULL(uf.nombre, ''), ' ', IFNULL(uf.apellido, ''))) AS forzada_por,
           IF(f.forzada_en IS NULL, NULL, CONVERT_TZ(f.forzada_en, '+00:00', '-05:00')) AS forzada_en,
           IF(f.id_evidencia IS NULL, 0, f.intento - 1) AS intentos_previos,
           CONVERT_TZ(f.timestamp_captura, '+00:00', '-05:00') AS capturada_en,
           CAST(f.resultado_ia AS CHAR) AS resultado_ia,
           IF(f.ruta_cuadro IS NULL, 0, 1) AS tiene_cuadro
    FROM   tmp_cat_evid c
    LEFT JOIN evidencia_fotografica f
           ON f.id_evidencia = (SELECT MAX(f2.id_evidencia) FROM evidencia_fotografica f2
                                WHERE f2.id_os = p_id_os AND f2.id_equipo = v_id_eq AND f2.codigo = c.codigo
                                  AND f2.pagina = 1 AND f2.vigente = 1 AND f2.eliminado_en IS NULL)
    LEFT JOIN usuario uf ON uf.id_usuario = f.id_usuario_override
    ORDER BY c.orden;

    -- 4. Fotos adicionales (opcionales, no cuentan en las 9): de la más antigua a la más reciente
    SELECT f.id_evidencia, f.pagina AS numero, CONVERT_TZ(f.timestamp_captura, '+00:00', '-05:00') AS capturada_en
    FROM   evidencia_fotografica f
    WHERE  f.id_os = p_id_os AND f.id_equipo = v_id_eq AND f.codigo = 'adicional' AND f.eliminado_en IS NULL
    ORDER BY f.pagina, f.id_evidencia;

    DROP TEMPORARY TABLE IF EXISTS tmp_cat_evid;
END$$

DELIMITER ;

-- ============================================================
-- VERIFICACIÓN (solo lectura: no crea datos)
-- ============================================================
SELECT 'Columnas informe_fisico (deben ser 2)' AS verificacion,
       (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND COLUMN_NAME = 'informe_fisico'
          AND TABLE_NAME IN ('programacion_confirmacion', 'orden_servicio')) AS valor
UNION ALL
SELECT 'Respuesta del cliente guarda el informe físico (debe ser 1)',
       (SELECT COUNT(*) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = DATABASE() AND ROUTINE_NAME = 'SP_RegistrarRespuestaClienteProgramacion' AND ROUTINE_DEFINITION LIKE '%p_informe_fisico%')
UNION ALL
SELECT 'Detalle de la programación trae el informe físico (debe ser 1)',
       (SELECT COUNT(*) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = DATABASE() AND ROUTINE_NAME = 'SP_ObtenerDetalleProgramacion' AND ROUTINE_DEFINITION LIKE '%pc.informe_fisico%')
UNION ALL
SELECT 'El resumen de evidencias respeta el informe físico (debe ser 1)',
       (SELECT COUNT(*) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = DATABASE() AND ROUTINE_NAME = 'SP_ResumenEvidenciasMovil' AND ROUTINE_DEFINITION LIKE '%informe_fisico = 0%')
UNION ALL
SELECT 'Registrar evidencia rechaza la foto del informe sin informe físico (debe ser 1)',
       (SELECT COUNT(*) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = DATABASE() AND ROUTINE_NAME = 'SP_RegistrarEvidenciaMovil' AND ROUTINE_DEFINITION LIKE '%informe_fisico = 0%' AND ROUTINE_DEFINITION LIKE '%adicional%')
UNION ALL
SELECT 'El panel de evidencias trae informe_fisico (debe ser 1)',
       (SELECT COUNT(*) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = DATABASE() AND ROUTINE_NAME = 'SP_ObtenerEvidenciasMovil' AND ROUTINE_DEFINITION LIKE '%informe_fisico%' AND ROUTINE_DEFINITION LIKE '%adicional%');
