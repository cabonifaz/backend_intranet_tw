-- HU-36 (Sprint 5) Programación de una OS/OM y asignación de recursos. Crea la Programación activa (PRG-AAAA-NNNN) en estado
-- pendiente_confirmacion y la refleja en la OS: técnico, fecha, horas, estado 'programada', confirmación del cliente en 0 y
-- personal (os_personal). Así la bandeja HU-35, el expediente y la agenda de la app móvil la leen de la OS.
-- Acceso: prog_gestionar (módulo operaciones).
--   p_id_tecnico_principal: obligatorio. p_ids_apoyo: JSON [ids] de técnicos de apoyo (opcional, hasta 9).
--   p_ids_equipos: JSON [ids de equipo] confirmados para esta programación; deben ser equipos de la OS. Si la OS tiene
--     equipos, hay que confirmar al menos uno.
-- Reglas (cada falla devuelve tipo 1 y no guarda nada):
--   · la OS existe y está EMITIDA, y no tiene otra programación activa (se serializa bloqueando la fila de la OS)
--   · fecha de hoy en adelante, hora fin posterior a la hora de inicio
--   · cada técnico es programable (activo, servicio técnico o metrología, sin jefaturas ni asistentes)
--   · concurrencia: la transacción bloquea primero a los técnicos (en orden) y luego la orden; dos programaciones que
--     comparten técnico se serializan y la segunda ve el horario que tomó la primera
--   · ningún técnico tiene otro servicio activo que se cruce con el horario (como principal o en el personal)
--   · SSOMA (SP_EvaluarSsomaProgramacion, la misma regla del buscador): se comparan los requisitos del cliente / zona de la
--     orden con el último documento de cada técnico. Bloquea un requisito vencido, observado o que vence antes del servicio,
--     o un técnico bloqueado por SSOMA en otra orden activa; si SSOMA_EXIGIR_DOCUMENTO = 1 también bloquea la falta del
--     documento. Lo demás (por vencer, sin documento cuando no se exige, sin equivalencia) se devuelve como advertencia.
--     La evaluación se hace antes de abrir la transacción (solo lee y usa tablas temporales).
--   Sin funciones almacenadas: crearlas exige el privilegio SUPER cuando el registro binario está activo.
--   · la OC no es una validación: se puede programar con o sin OC
-- Resultados: 1 mensaje, 2 programación creada, 3 advertencias (texto).
DROP PROCEDURE IF EXISTS SP_CrearProgramacion;

DELIMITER $$

CREATE PROCEDURE SP_CrearProgramacion(
    IN p_id_usuario           BIGINT,
    IN p_id_os                BIGINT,
    IN p_fecha                DATE,
    IN p_hora_inicio          TIME,
    IN p_hora_fin             TIME,
    IN p_id_tecnico_principal BIGINT,
    IN p_ids_apoyo            JSON,
    IN p_ids_equipos          JSON,
    IN p_observaciones        VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_numero     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tipo       VARCHAR(5)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_cliente BIGINT       DEFAULT NULL;
    DECLARE v_id_sede    BIGINT       DEFAULT NULL;
    DECLARE v_cliente    VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_codigo     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id         BIGINT       DEFAULT NULL;
    DECLARE v_n          INT          DEFAULT 0;
    DECLARE v_n_eq_os    INT          DEFAULT 0;
    DECLARE v_texto      VARCHAR(400) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_obs        VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_ids_bloqueo JSON;
    DECLARE v_i          INT          DEFAULT 0;
    DECLARE v_bloqueado  BIGINT       DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            @err_msg  = MESSAGE_TEXT,
            @err_code = MYSQL_ERRNO;   -- primero: la limpieza de abajo genera notas que reemplazan el diagnóstico
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_prg_tec;
        DROP TEMPORARY TABLE IF EXISTS tmp_prg_eq;
        DROP TEMPORARY TABLE IF EXISTS tmp_ssoma_in;
        CALL SP_LimpiarSsomaProgramacion();
        SELECT 3 AS IdTipoMensaje,
               CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    -- ── Permiso y validaciones de forma ──────────────────────────────────
    IF FN_PermisoAccion(p_id_usuario, 'prog_gestionar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para programar servicios.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF p_fecha IS NULL OR p_hora_inicio IS NULL OR p_hora_fin IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Indica la fecha de ejecución, la hora de inicio y la hora fin estimada.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF p_fecha < CURDATE() THEN
        SELECT 1 AS IdTipoMensaje, 'La fecha de ejecución no puede ser anterior a hoy.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF p_hora_fin <= p_hora_inicio THEN
        SELECT 1 AS IdTipoMensaje, 'La hora fin estimada debe ser posterior a la hora de inicio.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF IFNULL(p_id_tecnico_principal, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Selecciona al menos un técnico: el técnico principal es obligatorio.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF (p_ids_apoyo IS NOT NULL AND JSON_TYPE(p_ids_apoyo) <> 'ARRAY')
       OR (p_ids_equipos IS NOT NULL AND JSON_TYPE(p_ids_equipos) <> 'ARRAY') THEN
        SELECT 1 AS IdTipoMensaje, 'Los técnicos de apoyo y los equipos deben enviarse como listas de identificadores.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_obs = NULLIF(TRIM(IFNULL(p_observaciones, '')), '');

    -- ── Técnicos y equipos recibidos (sin repetidos) ─────────────────────
    DROP TEMPORARY TABLE IF EXISTS tmp_prg_tec;
    DROP TEMPORARY TABLE IF EXISTS tmp_prg_eq;
    DROP TEMPORARY TABLE IF EXISTS tmp_ssoma_in;
    CALL SP_LimpiarSsomaProgramacion();
    CREATE TEMPORARY TABLE tmp_prg_tec (
        id_usuario   BIGINT      NOT NULL,
        rol          VARCHAR(10) NOT NULL,
        estado_ssoma  VARCHAR(12)  NULL,
        motivo        VARCHAR(600) NULL,
        faltantes     VARCHAR(600) NULL,
        sin_verificar INT          NOT NULL DEFAULT 0,
        PRIMARY KEY (id_usuario)
    );
    CREATE TEMPORARY TABLE tmp_prg_eq (
        id_equipo BIGINT NOT NULL,
        PRIMARY KEY (id_equipo)
    );

    INSERT INTO tmp_prg_tec (id_usuario, rol) VALUES (p_id_tecnico_principal, 'principal');
    IF p_ids_apoyo IS NOT NULL THEN
        INSERT IGNORE INTO tmp_prg_tec (id_usuario, rol)
        SELECT jt.id, 'apoyo'
        FROM JSON_TABLE(p_ids_apoyo, '$[*]' COLUMNS (id BIGINT PATH '$')) jt
        WHERE jt.id IS NOT NULL AND jt.id > 0;
    END IF;
    IF p_ids_equipos IS NOT NULL THEN
        INSERT IGNORE INTO tmp_prg_eq (id_equipo)
        SELECT jt.id
        FROM JSON_TABLE(p_ids_equipos, '$[*]' COLUMNS (id BIGINT PATH '$')) jt
        WHERE jt.id IS NOT NULL AND jt.id > 0;
    END IF;

    SELECT COUNT(*) INTO v_n FROM tmp_prg_tec;
    IF v_n > 10 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_prg_tec;
        DROP TEMPORARY TABLE IF EXISTS tmp_prg_eq;
        DROP TEMPORARY TABLE IF EXISTS tmp_ssoma_in;
        CALL SP_LimpiarSsomaProgramacion();
        SELECT 1 AS IdTipoMensaje, 'Una programación admite hasta 10 técnicos.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- ── La orden existe (se vuelve a leer con bloqueo dentro de la transacción) ──
    IF NOT EXISTS (SELECT 1 FROM orden_servicio WHERE id_os = p_id_os AND eliminado_en IS NULL) THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_prg_tec;
        DROP TEMPORARY TABLE IF EXISTS tmp_prg_eq;
        DROP TEMPORARY TABLE IF EXISTS tmp_ssoma_in;
        CALL SP_LimpiarSsomaProgramacion();
        SELECT 1 AS IdTipoMensaje, 'La orden de servicio no existe.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- ── Técnicos programables ────────────────────────────────────────────
    SELECT COUNT(*) INTO v_n
    FROM tmp_prg_tec t
    WHERE NOT EXISTS (SELECT 1 FROM usuario u
                      WHERE u.id_usuario = t.id_usuario AND u.eliminado_en IS NULL AND u.estado = 'activo'
                        AND u.area IN ('servicio_tecnico', 'metrologia')
                        AND (u.cargo IS NULL OR (u.cargo NOT LIKE 'jefe\_%' AND u.cargo NOT LIKE 'asistente\_%')));
    IF v_n > 0 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_prg_tec;
        DROP TEMPORARY TABLE IF EXISTS tmp_prg_eq;
        DROP TEMPORARY TABLE IF EXISTS tmp_ssoma_in;
        CALL SP_LimpiarSsomaProgramacion();
        SELECT 1 AS IdTipoMensaje, 'Uno o más técnicos no están activos o no pertenecen a Servicio Técnico o Metrología.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- ── SSOMA de los técnicos contra los requisitos del cliente / zona (solo lectura, antes de la transacción) ──
    CREATE TEMPORARY TABLE tmp_ssoma_in (id_usuario BIGINT NOT NULL, PRIMARY KEY (id_usuario));
    INSERT INTO tmp_ssoma_in (id_usuario) SELECT id_usuario FROM tmp_prg_tec;
    CALL SP_EvaluarSsomaProgramacion(p_id_os, p_fecha);

    UPDATE tmp_prg_tec t
    JOIN tmp_ssoma_res r ON r.id_usuario = t.id_usuario
    SET t.estado_ssoma  = r.estado,
        t.motivo        = LEFT(NULLIF(r.motivo_bloqueo, ''), 600),
        t.faltantes     = LEFT(r.faltantes, 600),
        t.sin_verificar = r.n_sin_verificar;

    -- Ids de los técnicos en orden, para bloquearlos al inicio de la transacción sin leer ninguna tabla antes
    SET v_ids_bloqueo = CAST(CONCAT('[', (SELECT GROUP_CONCAT(id_usuario ORDER BY id_usuario) FROM tmp_prg_tec), ']') AS JSON);

    START TRANSACTION;

    -- ── Concurrencia: lo PRIMERO de la transacción es bloquear a los técnicos, uno por uno y en orden de id ──
    -- Así dos programaciones que comparten un técnico se ejecutan una detrás de otra y la lectura de disponibilidad de la
    -- segunda ya ve lo que guardó la primera: en REPEATABLE READ la foto de datos se toma en la primera lectura normal de la
    -- transacción, y aquí esa lectura ocurre recién después de obtener estos bloqueos (la lista de ids se armó antes de la
    -- transacción para no leer ninguna tabla antes de bloquear). El orden fijo evita bloqueos cruzados.
    -- (Antes el bloqueo iba después de otras lecturas y dos órdenes distintas podían quedar con el mismo técnico y horario.)
    SET v_i = 0;
    WHILE v_i < JSON_LENGTH(v_ids_bloqueo) DO
        SELECT id_usuario INTO v_bloqueado
        FROM usuario
        WHERE id_usuario = CAST(JSON_EXTRACT(v_ids_bloqueo, CONCAT('$[', v_i, ']')) AS UNSIGNED)
        FOR UPDATE;
        SET v_i = v_i + 1;
    END WHILE;

    -- ── La OS: se bloquea la fila para que dos asistentes no la programen a la vez ──
    SELECT numero, estado, tipo, id_cliente, id_sede
    INTO   v_numero, v_estado, v_tipo, v_id_cliente, v_id_sede
    FROM   orden_servicio
    WHERE  id_os = p_id_os AND eliminado_en IS NULL
    FOR UPDATE;

    IF v_estado IS NULL THEN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_prg_tec;
        DROP TEMPORARY TABLE IF EXISTS tmp_prg_eq;
        DROP TEMPORARY TABLE IF EXISTS tmp_ssoma_in;
        CALL SP_LimpiarSsomaProgramacion();
        SELECT 1 AS IdTipoMensaje, 'La orden de servicio no existe.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF v_estado <> 'emitida' THEN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_prg_tec;
        DROP TEMPORARY TABLE IF EXISTS tmp_prg_eq;
        DROP TEMPORARY TABLE IF EXISTS tmp_ssoma_in;
        CALL SP_LimpiarSsomaProgramacion();
        SELECT 1 AS IdTipoMensaje, CONCAT('La orden ', v_numero, ' está ', v_estado, ': solo se programa una orden emitida.') AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_codigo = NULL;
    SELECT codigo INTO v_codigo
    FROM programacion
    WHERE id_os = p_id_os AND estado <> 'cancelada' AND eliminado_en IS NULL
    LIMIT 1;
    IF v_codigo IS NOT NULL THEN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_prg_tec;
        DROP TEMPORARY TABLE IF EXISTS tmp_prg_eq;
        DROP TEMPORARY TABLE IF EXISTS tmp_ssoma_in;
        CALL SP_LimpiarSsomaProgramacion();
        SELECT 1 AS IdTipoMensaje, CONCAT('La orden ', v_numero, ' ya tiene la programación activa ', v_codigo, '.') AS Mensaje;
        LEAVE proc;
    END IF;

    -- ── Equipos: deben ser de la OS ──────────────────────────────────────
    SELECT COUNT(*) INTO v_n_eq_os FROM os_equipo WHERE id_os = p_id_os AND eliminado_en IS NULL;

    SELECT COUNT(*) INTO v_n
    FROM tmp_prg_eq q
    WHERE NOT EXISTS (SELECT 1 FROM os_equipo oe
                      WHERE oe.id_os = p_id_os AND oe.id_equipo = q.id_equipo AND oe.eliminado_en IS NULL);
    IF v_n > 0 THEN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_prg_tec;
        DROP TEMPORARY TABLE IF EXISTS tmp_prg_eq;
        DROP TEMPORARY TABLE IF EXISTS tmp_ssoma_in;
        CALL SP_LimpiarSsomaProgramacion();
        SELECT 1 AS IdTipoMensaje, 'Uno o más equipos no pertenecen a la orden.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT COUNT(*) INTO v_n FROM tmp_prg_eq;
    IF v_n_eq_os > 0 AND v_n = 0 THEN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_prg_tec;
        DROP TEMPORARY TABLE IF EXISTS tmp_prg_eq;
        DROP TEMPORARY TABLE IF EXISTS tmp_ssoma_in;
        CALL SP_LimpiarSsomaProgramacion();
        SELECT 1 AS IdTipoMensaje, 'Confirma al menos un equipo a intervenir.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- ── Disponibilidad: ningún técnico con otro servicio que se cruce ────
    SET v_texto = NULL;
    SELECT CONCAT(TRIM(CONCAT(u.nombre, ' ', u.apellido)), ' ya tiene el servicio ', os2.numero, ' de ',
                  TIME_FORMAT(os2.hora_inicio, '%H:%i'), ' a ', TIME_FORMAT(os2.hora_fin_estimada, '%H:%i'), ' ese día.')
    INTO   v_texto
    FROM   tmp_prg_tec t
    JOIN   usuario u        ON u.id_usuario = t.id_usuario
    JOIN   orden_servicio os2 ON os2.eliminado_en IS NULL
                             AND os2.id_os <> p_id_os
                             AND os2.fecha_ejecucion = p_fecha
                             AND os2.estado IN ('programada', 'reprogramada', 'en_ruta', 'en_ejecucion', 'pausada', 'bloqueada')
                             AND os2.hora_inicio IS NOT NULL AND os2.hora_fin_estimada IS NOT NULL
                             AND os2.hora_inicio < p_hora_fin AND os2.hora_fin_estimada > p_hora_inicio
                             AND (os2.id_tecnico_principal = t.id_usuario
                                  OR EXISTS (SELECT 1 FROM os_personal pp
                                             WHERE pp.id_os = os2.id_os AND pp.id_usuario = t.id_usuario AND pp.eliminado_en IS NULL))
    ORDER BY os2.hora_inicio
    LIMIT 1;
    IF v_texto IS NOT NULL THEN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_prg_tec;
        DROP TEMPORARY TABLE IF EXISTS tmp_prg_eq;
        DROP TEMPORARY TABLE IF EXISTS tmp_ssoma_in;
        CALL SP_LimpiarSsomaProgramacion();
        SELECT 1 AS IdTipoMensaje, CONCAT('Solapamiento de horario: ', v_texto,
                                          ' Elige otro técnico o ajusta el horario.') AS Mensaje;
        LEAVE proc;
    END IF;

    -- ── SSOMA: resultado de SP_EvaluarSsomaProgramacion ─────────────────
    SET v_texto = NULL;
    SELECT CONCAT(TRIM(CONCAT(u.nombre, ' ', u.apellido)),
                  IF(t.estado_ssoma = 'bloqueado',
                     CONCAT(' no tiene la habilitación SSOMA conforme', IFNULL(CONCAT(': ', t.motivo), ''), '.'),
                     CONCAT(' no tiene el documento SSOMA que exige el cliente: ', IFNULL(t.faltantes, 'requisitos del cliente'), '.')))
    INTO   v_texto
    FROM   tmp_prg_tec t
    JOIN   usuario u ON u.id_usuario = t.id_usuario
    WHERE  t.estado_ssoma IN ('bloqueado', 'pendiente')
    ORDER BY (t.rol = 'principal') DESC, u.nombre
    LIMIT 1;
    IF v_texto IS NOT NULL THEN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_prg_tec;
        DROP TEMPORARY TABLE IF EXISTS tmp_prg_eq;
        DROP TEMPORARY TABLE IF EXISTS tmp_ssoma_in;
        CALL SP_LimpiarSsomaProgramacion();
        SELECT 1 AS IdTipoMensaje,
               CONCAT('Validación SSOMA: ', v_texto, ' Elige otro técnico o deriva el caso al área SSOMA.') AS Mensaje;
        LEAVE proc;
    END IF;

    -- ── Crear la programación ────────────────────────────────────────────
    SELECT CONCAT('PRG-', YEAR(CURDATE()), '-', LPAD(IFNULL(MAX(CAST(SUBSTRING(codigo, 10) AS UNSIGNED)), 0) + 1, 4, '0'))
    INTO   v_codigo
    FROM   programacion
    WHERE  codigo LIKE CONCAT('PRG-', YEAR(CURDATE()), '-%')
    FOR UPDATE;

    INSERT INTO programacion (codigo, id_os, estado, fecha_ejecucion, hora_inicio, hora_fin_estimada,
                              id_tecnico_principal, observaciones, creado_por)
    VALUES (v_codigo, p_id_os, 'pendiente_confirmacion', p_fecha, p_hora_inicio, p_hora_fin,
            p_id_tecnico_principal, v_obs, p_id_usuario);
    SET v_id = LAST_INSERT_ID();

    INSERT INTO programacion_tecnico (id_programacion, id_usuario, rol, estado_ssoma, creado_por)
    SELECT v_id, t.id_usuario, t.rol, IF(t.estado_ssoma IN ('por_vencer', 'incompleto'), t.estado_ssoma, 'conforme'), p_id_usuario
    FROM tmp_prg_tec t;

    INSERT INTO programacion_equipo (id_programacion, id_equipo, creado_por)
    SELECT v_id, q.id_equipo, p_id_usuario FROM tmp_prg_eq q;

    -- ── Reflejo en la OS (la leen la bandeja HU-35, el expediente y la app móvil) ──
    UPDATE orden_servicio
    SET    estado                     = 'programada',
           id_tecnico_principal       = p_id_tecnico_principal,
           fecha_ejecucion            = p_fecha,
           hora_inicio                = p_hora_inicio,
           hora_fin_estimada          = p_hora_fin,
           confirmacion_cliente       = 0,
           id_canal_confirmacion      = NULL,
           id_contacto_confirma       = NULL,
           fecha_confirmacion_cliente = NULL,
           modificado_por             = p_id_usuario
    WHERE  id_os = p_id_os;

    -- Personal de la OS: se reemplaza por el de esta programación. Sin evidencia negativa de SSOMA queda habilitado.
    UPDATE os_personal
    SET    eliminado_en = NOW(), eliminado_por = p_id_usuario
    WHERE  id_os = p_id_os AND eliminado_en IS NULL;

    INSERT INTO os_personal (id_os, id_usuario, rol_en_servicio, estado_ssoma, creado_por)
    SELECT p_id_os, t.id_usuario, IF(t.rol = 'principal', 'Técnico principal', 'Técnico de apoyo'), 'habilitado', p_id_usuario
    FROM tmp_prg_tec t;

    -- ── Auditoría y aviso a los técnicos ─────────────────────────────────
    SELECT razon_social INTO v_cliente FROM cliente WHERE id_cliente = v_id_cliente;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion,
                                  id_usuario, registrado_en, metadata)
    VALUES ('orden_servicio', p_id_os, 'programar_os', 'emitida', 'programada',
            CONCAT(v_tipo, ' ', v_numero, ' programada (', v_codigo, ') el ', DATE_FORMAT(p_fecha, '%d/%m/%Y'), ' de ',
                   TIME_FORMAT(p_hora_inicio, '%H:%i'), ' a ', TIME_FORMAT(p_hora_fin, '%H:%i'), '. Pendiente de confirmación del cliente.'),
            p_id_usuario, NOW(),
            JSON_OBJECT('programacion', v_codigo, 'idProgramacion', v_id, 'idTecnicoPrincipal', p_id_tecnico_principal,
                        'tecnicos', (SELECT COUNT(*) FROM tmp_prg_tec), 'equipos', (SELECT COUNT(*) FROM tmp_prg_eq)));

    INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
    SELECT t.id_usuario, 5, CONCAT('Nueva programación: ', v_numero),
           CONCAT('Te asignaron la ', v_tipo, ' ', v_numero, IF(v_cliente IS NULL, '', CONCAT(' de ', v_cliente)),
                  ' el ', DATE_FORMAT(p_fecha, '%d/%m/%Y'), ' de ', TIME_FORMAT(p_hora_inicio, '%H:%i'), ' a ',
                  TIME_FORMAT(p_hora_fin, '%H:%i'), '. Queda pendiente de confirmación del cliente.'),
           'orden_servicio', p_id_os, NOW(), p_id_usuario
    FROM tmp_prg_tec t
    WHERE t.id_usuario <> p_id_usuario;

    COMMIT;

    -- 1. Header
    SELECT 2 AS IdTipoMensaje,
           CONCAT('Programación ', v_codigo, ' creada. Queda pendiente de confirmación del cliente.') AS Mensaje;

    -- 2. Programación creada
    SELECT v_id                                  AS id_programacion,
           v_codigo                              AS codigo,
           p_id_os                               AS id_os,
           v_numero                              AS numero_os,
           'pendiente_confirmacion'              AS estado,
           p_fecha                               AS fecha_ejecucion,
           TIME_FORMAT(p_hora_inicio, '%H:%i')   AS hora_inicio,
           TIME_FORMAT(p_hora_fin, '%H:%i')      AS hora_fin;

    -- 3. Advertencias (no bloquean). Se arman con varias sentencias: MySQL no reabre una temporal en la misma consulta.
    DROP TEMPORARY TABLE IF EXISTS tmp_prg_adv;
    CREATE TEMPORARY TABLE tmp_prg_adv (orden INT NOT NULL, advertencia VARCHAR(800) NOT NULL);

    INSERT INTO tmp_prg_adv (orden, advertencia)
    SELECT 1, CONCAT(TRIM(CONCAT(u.nombre, ' ', u.apellido)),
                     ': la habilitación SSOMA vence en los próximos días; coordina su renovación con SSOMA.')
    FROM tmp_prg_tec t
    JOIN usuario u ON u.id_usuario = t.id_usuario
    WHERE t.estado_ssoma = 'por_vencer';

    INSERT INTO tmp_prg_adv (orden, advertencia)
    SELECT 2, CONCAT(TRIM(CONCAT(u.nombre, ' ', u.apellido)), ': no tiene cargado el documento de ', t.faltantes,
                     ' (lo pide el cliente). Coordínalo con SSOMA antes del servicio.')
    FROM tmp_prg_tec t
    JOIN usuario u ON u.id_usuario = t.id_usuario
    WHERE t.faltantes IS NOT NULL AND t.faltantes <> '';

    INSERT INTO tmp_prg_adv (orden, advertencia)
    SELECT 3, CONCAT(MAX(t.sin_verificar),
                     ' requisito(s) SSOMA del cliente no tienen un documento equivalente configurado: revísalos con SSOMA.')
    FROM tmp_prg_tec t
    HAVING MAX(t.sin_verificar) > 0;

    SELECT advertencia FROM tmp_prg_adv ORDER BY orden, advertencia;
    DROP TEMPORARY TABLE IF EXISTS tmp_prg_adv;

    DROP TEMPORARY TABLE IF EXISTS tmp_prg_tec;
    DROP TEMPORARY TABLE IF EXISTS tmp_prg_eq;
    DROP TEMPORARY TABLE IF EXISTS tmp_ssoma_in;
    CALL SP_LimpiarSsomaProgramacion();
END$$

DELIMITER ;
