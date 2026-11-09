-- HU-38 (Sprint 5) Ayuda interna: valida y aplica los cambios de una reprogramación sobre la Programación activa. La usan
-- SP_ReprogramarProgramacion (edición directa del Jefe) y SP_ResolverSolicitudReprogramacion (aprobación). NO abre ni cierra la
-- transacción: quien la llama ya bloqueó (en este orden) a los técnicos nuevos, la OS y la programación. No devuelve resultados.
--   p_fecha, p_hora_inicio, p_hora_fin, p_id_tecnico, p_ids_apoyo, p_ids_equipos: NULL = se mantiene lo actual.
--   p_aplicar = 0: solo valida la forma (para registrar una solicitud): fecha de hoy en adelante, horas, técnicos programables,
--                  equipos de la OS y que haya al menos un cambio. No mira cruces ni SSOMA ni escribe nada.
--   p_aplicar = 1: además valida cruces de horario y SSOMA (las mismas reglas de SP_CrearProgramacion) y escribe.
--   OUT p_error: NULL si todo bien; si no, el mensaje de negocio (nada se escribió).
--   OUT p_cambio_horario: cambió fecha u hora → la programación vuelve a PENDIENTE DE CONFIRMACIÓN DEL CLIENTE.
--        Si solo cambia técnico o equipos el estado se mantiene (el cliente no se entera del cambio interno).
--   OUT p_cambio_tecnicos / p_cambio_equipos: cambió el equipo de trabajo / los equipos reservados.
--   Con p_aplicar = 1 deja la tabla temporal tmp_apl_afectados (id_usuario, situacion: nuevo | quitado | sigue) para que quien
--   llama avise a los técnicos; quien llama debe eliminarla.
DROP PROCEDURE IF EXISTS SP_AplicarCambiosProgramacion;

DELIMITER $$

CREATE PROCEDURE SP_AplicarCambiosProgramacion(
    IN  p_id_usuario        BIGINT,
    IN  p_id_programacion   BIGINT,
    IN  p_fecha             DATE,
    IN  p_hora_inicio       TIME,
    IN  p_hora_fin          TIME,
    IN  p_id_tecnico        BIGINT,
    IN  p_ids_apoyo         JSON,
    IN  p_ids_equipos       JSON,
    IN  p_aplicar           TINYINT,
    OUT p_error             VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    OUT p_cambio_horario    TINYINT,
    OUT p_cambio_tecnicos   TINYINT,
    OUT p_cambio_equipos    TINYINT
)
proc: BEGIN
    DECLARE v_id_os      BIGINT       DEFAULT NULL;
    DECLARE v_estado_prg VARCHAR(25)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado_os  VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_numero     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_fecha_act  DATE;
    DECLARE v_ini_act    TIME;
    DECLARE v_fin_act    TIME;
    DECLARE v_tec_act    BIGINT;
    DECLARE v_fecha      DATE;
    DECLARE v_ini        TIME;
    DECLARE v_fin        TIME;
    DECLARE v_tec        BIGINT;
    DECLARE v_n          INT          DEFAULT 0;
    DECLARE v_n_eq_os    INT          DEFAULT 0;
    DECLARE v_texto      VARCHAR(400) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    SET p_error = NULL, p_cambio_horario = 0, p_cambio_tecnicos = 0, p_cambio_equipos = 0;

    DROP TEMPORARY TABLE IF EXISTS tmp_prg_tec;
    DROP TEMPORARY TABLE IF EXISTS tmp_prg_eq;
    DROP TEMPORARY TABLE IF EXISTS tmp_ssoma_in;
    DROP TEMPORARY TABLE IF EXISTS tmp_apl_afectados;
    CALL SP_LimpiarSsomaProgramacion();

    body: BEGIN
        -- ── Programación y orden vigentes ────────────────────────────────
        SELECT id_os, estado, fecha_ejecucion, hora_inicio, hora_fin_estimada, id_tecnico_principal
          INTO v_id_os, v_estado_prg, v_fecha_act, v_ini_act, v_fin_act, v_tec_act
        FROM programacion
        WHERE id_programacion = p_id_programacion AND eliminado_en IS NULL;

        IF v_id_os IS NULL THEN
            SET p_error = 'La programación no existe.';
            LEAVE body;
        END IF;
        IF v_estado_prg = 'cancelada' THEN
            SET p_error = 'La programación está cancelada: ya no admite cambios.';
            LEAVE body;
        END IF;

        SELECT numero, estado INTO v_numero, v_estado_os FROM orden_servicio WHERE id_os = v_id_os AND eliminado_en IS NULL;
        IF v_estado_os IS NULL OR v_estado_os NOT IN ('programada', 'reprogramada') THEN
            SET p_error = CONCAT('La orden ', IFNULL(v_numero, ''), ' está ', IFNULL(v_estado_os, 'inexistente'),
                                 ': solo se puede reprogramar un servicio programado que aún no empezó.');
            LEAVE body;
        END IF;

        -- ── Valores resultantes (NULL = se mantiene) ─────────────────────
        SET v_fecha = IFNULL(p_fecha, v_fecha_act);
        SET v_ini   = IFNULL(p_hora_inicio, v_ini_act);
        SET v_fin   = IFNULL(p_hora_fin, v_fin_act);
        SET v_tec   = IFNULL(p_id_tecnico, v_tec_act);

        IF v_fecha < CURDATE() THEN
            SET p_error = 'La fecha de ejecución no puede ser anterior a hoy.';
            LEAVE body;
        END IF;
        IF v_fin <= v_ini THEN
            SET p_error = 'La hora fin estimada debe ser posterior a la hora de inicio.';
            LEAVE body;
        END IF;
        IF IFNULL(v_tec, 0) <= 0 THEN
            SET p_error = 'El técnico principal es obligatorio.';
            LEAVE body;
        END IF;
        IF (p_ids_apoyo IS NOT NULL AND JSON_TYPE(p_ids_apoyo) <> 'ARRAY')
           OR (p_ids_equipos IS NOT NULL AND JSON_TYPE(p_ids_equipos) <> 'ARRAY') THEN
            SET p_error = 'Los técnicos de apoyo y los equipos deben enviarse como listas de identificadores.';
            LEAVE body;
        END IF;

        CREATE TEMPORARY TABLE tmp_prg_tec (
            id_usuario    BIGINT       NOT NULL,
            rol           VARCHAR(10)  NOT NULL,
            estado_ssoma  VARCHAR(12)  NULL,
            motivo        VARCHAR(600) NULL,
            faltantes     VARCHAR(600) NULL,
            sin_verificar INT          NOT NULL DEFAULT 0,
            PRIMARY KEY (id_usuario)
        );
        CREATE TEMPORARY TABLE tmp_prg_eq (id_equipo BIGINT NOT NULL, PRIMARY KEY (id_equipo));

        INSERT INTO tmp_prg_tec (id_usuario, rol) VALUES (v_tec, 'principal');
        IF p_ids_apoyo IS NULL THEN
            INSERT IGNORE INTO tmp_prg_tec (id_usuario, rol)
            SELECT id_usuario, 'apoyo' FROM programacion_tecnico
            WHERE id_programacion = p_id_programacion AND rol = 'apoyo' AND eliminado_en IS NULL;
        ELSE
            INSERT IGNORE INTO tmp_prg_tec (id_usuario, rol)
            SELECT jt.id, 'apoyo'
            FROM JSON_TABLE(p_ids_apoyo, '$[*]' COLUMNS (id BIGINT PATH '$')) jt
            WHERE jt.id IS NOT NULL AND jt.id > 0;
        END IF;

        IF p_ids_equipos IS NULL THEN
            INSERT IGNORE INTO tmp_prg_eq (id_equipo)
            SELECT id_equipo FROM programacion_equipo WHERE id_programacion = p_id_programacion AND eliminado_en IS NULL;
        ELSE
            INSERT IGNORE INTO tmp_prg_eq (id_equipo)
            SELECT jt.id
            FROM JSON_TABLE(p_ids_equipos, '$[*]' COLUMNS (id BIGINT PATH '$')) jt
            WHERE jt.id IS NOT NULL AND jt.id > 0;
        END IF;

        SELECT COUNT(*) INTO v_n FROM tmp_prg_tec;
        IF v_n > 10 THEN
            SET p_error = 'Una programación admite hasta 10 técnicos.';
            LEAVE body;
        END IF;

        -- ── Técnicos programables y equipos de la OS ─────────────────────
        SELECT COUNT(*) INTO v_n
        FROM tmp_prg_tec t
        WHERE NOT EXISTS (SELECT 1 FROM usuario u
                          WHERE u.id_usuario = t.id_usuario AND u.eliminado_en IS NULL AND u.estado = 'activo'
                            AND u.area IN ('servicio_tecnico', 'metrologia')
                            AND (u.cargo IS NULL OR (u.cargo NOT LIKE 'jefe\_%' AND u.cargo NOT LIKE 'asistente\_%')));
        IF v_n > 0 THEN
            SET p_error = 'Uno o más técnicos no están activos o no pertenecen a Servicio Técnico o Metrología.';
            LEAVE body;
        END IF;

        SELECT COUNT(*) INTO v_n_eq_os FROM os_equipo WHERE id_os = v_id_os AND eliminado_en IS NULL;
        SELECT COUNT(*) INTO v_n
        FROM tmp_prg_eq q
        WHERE NOT EXISTS (SELECT 1 FROM os_equipo oe
                          WHERE oe.id_os = v_id_os AND oe.id_equipo = q.id_equipo AND oe.eliminado_en IS NULL);
        IF v_n > 0 THEN
            SET p_error = 'Uno o más equipos no pertenecen a la orden.';
            LEAVE body;
        END IF;
        SELECT COUNT(*) INTO v_n FROM tmp_prg_eq;
        IF v_n_eq_os > 0 AND v_n = 0 THEN
            SET p_error = 'Confirma al menos un equipo a intervenir.';
            LEAVE body;
        END IF;

        -- ── Qué cambia ───────────────────────────────────────────────────
        SET p_cambio_horario = IF(v_fecha <> v_fecha_act OR v_ini <> v_ini_act OR v_fin <> v_fin_act, 1, 0);

        SELECT COUNT(*) INTO v_n
        FROM tmp_prg_tec t
        WHERE NOT EXISTS (SELECT 1 FROM programacion_tecnico pt
                          WHERE pt.id_programacion = p_id_programacion AND pt.id_usuario = t.id_usuario
                            AND pt.rol = t.rol AND pt.eliminado_en IS NULL);
        SELECT v_n + COUNT(*) INTO v_n
        FROM programacion_tecnico pt
        WHERE pt.id_programacion = p_id_programacion AND pt.eliminado_en IS NULL
          AND NOT EXISTS (SELECT 1 FROM tmp_prg_tec t WHERE t.id_usuario = pt.id_usuario AND t.rol = pt.rol);
        SET p_cambio_tecnicos = IF(v_n > 0, 1, 0);

        SELECT COUNT(*) INTO v_n
        FROM tmp_prg_eq q
        WHERE NOT EXISTS (SELECT 1 FROM programacion_equipo pe
                          WHERE pe.id_programacion = p_id_programacion AND pe.id_equipo = q.id_equipo AND pe.eliminado_en IS NULL);
        SELECT v_n + COUNT(*) INTO v_n
        FROM programacion_equipo pe
        WHERE pe.id_programacion = p_id_programacion AND pe.eliminado_en IS NULL
          AND NOT EXISTS (SELECT 1 FROM tmp_prg_eq q WHERE q.id_equipo = pe.id_equipo);
        SET p_cambio_equipos = IF(v_n > 0, 1, 0);

        IF p_cambio_horario = 0 AND p_cambio_tecnicos = 0 AND p_cambio_equipos = 0 THEN
            SET p_error = 'No hay cambios respecto a la programación actual.';
            LEAVE body;
        END IF;

        IF p_aplicar = 0 THEN
            LEAVE body;
        END IF;

        -- ── Cruces de horario (otros servicios activos de los técnicos) ──
        IF p_cambio_horario = 1 OR p_cambio_tecnicos = 1 THEN
            SET v_texto = NULL;
            SELECT CONCAT(TRIM(CONCAT(u.nombre, ' ', u.apellido)), ' ya tiene el servicio ', os2.numero, ' de ',
                          TIME_FORMAT(os2.hora_inicio, '%H:%i'), ' a ', TIME_FORMAT(os2.hora_fin_estimada, '%H:%i'), ' ese día.')
            INTO   v_texto
            FROM   tmp_prg_tec t
            JOIN   usuario u        ON u.id_usuario = t.id_usuario
            JOIN   orden_servicio os2 ON os2.eliminado_en IS NULL
                                     AND os2.id_os <> v_id_os
                                     AND os2.fecha_ejecucion = v_fecha
                                     AND os2.estado IN ('programada', 'reprogramada', 'en_ruta', 'en_ejecucion', 'pausada', 'bloqueada')
                                     AND os2.hora_inicio IS NOT NULL AND os2.hora_fin_estimada IS NOT NULL
                                     AND os2.hora_inicio < v_fin AND os2.hora_fin_estimada > v_ini
                                     AND (os2.id_tecnico_principal = t.id_usuario
                                          OR EXISTS (SELECT 1 FROM os_personal pp
                                                     WHERE pp.id_os = os2.id_os AND pp.id_usuario = t.id_usuario AND pp.eliminado_en IS NULL))
            ORDER BY os2.hora_inicio
            LIMIT 1;
            IF v_texto IS NOT NULL THEN
                SET p_error = CONCAT('Solapamiento de horario: ', v_texto, ' Elige otro técnico o ajusta el horario.');
                LEAVE body;
            END IF;

            -- ── SSOMA contra los requisitos del cliente / zona, con la nueva fecha ──
            CREATE TEMPORARY TABLE tmp_ssoma_in (id_usuario BIGINT NOT NULL, PRIMARY KEY (id_usuario));
            INSERT INTO tmp_ssoma_in (id_usuario) SELECT id_usuario FROM tmp_prg_tec;
            CALL SP_EvaluarSsomaProgramacion(v_id_os, v_fecha);

            UPDATE tmp_prg_tec t
            JOIN tmp_ssoma_res r ON r.id_usuario = t.id_usuario
            SET t.estado_ssoma  = r.estado,
                t.motivo        = LEFT(NULLIF(r.motivo_bloqueo, ''), 600),
                t.faltantes     = LEFT(r.faltantes, 600),
                t.sin_verificar = r.n_sin_verificar;

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
                SET p_error = CONCAT('Validación SSOMA: ', v_texto, ' Elige otro técnico o deriva el caso al área SSOMA.');
                LEAVE body;
            END IF;
        END IF;

        -- ── Quién queda afectado (para avisar) ───────────────────────────
        CREATE TEMPORARY TABLE tmp_apl_afectados (id_usuario BIGINT NOT NULL, situacion VARCHAR(10) NOT NULL, PRIMARY KEY (id_usuario));
        INSERT INTO tmp_apl_afectados (id_usuario, situacion)
        SELECT t.id_usuario,
               IF(EXISTS (SELECT 1 FROM programacion_tecnico pt
                          WHERE pt.id_programacion = p_id_programacion AND pt.id_usuario = t.id_usuario AND pt.eliminado_en IS NULL),
                  'sigue', 'nuevo')
        FROM tmp_prg_tec t;
        INSERT INTO tmp_apl_afectados (id_usuario, situacion)
        SELECT pt.id_usuario, 'quitado'
        FROM programacion_tecnico pt
        WHERE pt.id_programacion = p_id_programacion AND pt.eliminado_en IS NULL
          AND NOT EXISTS (SELECT 1 FROM tmp_prg_tec t WHERE t.id_usuario = pt.id_usuario);

        -- ── Escritura ────────────────────────────────────────────────────
        UPDATE programacion
        SET    fecha_ejecucion      = v_fecha,
               hora_inicio          = v_ini,
               hora_fin_estimada    = v_fin,
               id_tecnico_principal = v_tec,
               estado               = IF(p_cambio_horario = 1, 'pendiente_confirmacion', estado),
               modificado_por       = p_id_usuario
        WHERE  id_programacion = p_id_programacion;

        IF p_cambio_tecnicos = 1 THEN
            UPDATE programacion_tecnico SET eliminado_en = NOW(), eliminado_por = p_id_usuario
            WHERE id_programacion = p_id_programacion AND eliminado_en IS NULL;
            INSERT INTO programacion_tecnico (id_programacion, id_usuario, rol, estado_ssoma, creado_por)
            SELECT p_id_programacion, t.id_usuario, t.rol,
                   IF(t.estado_ssoma IN ('por_vencer', 'incompleto'), t.estado_ssoma, 'conforme'), p_id_usuario
            FROM tmp_prg_tec t;

            UPDATE os_personal SET eliminado_en = NOW(), eliminado_por = p_id_usuario
            WHERE id_os = v_id_os AND eliminado_en IS NULL;
            INSERT INTO os_personal (id_os, id_usuario, rol_en_servicio, estado_ssoma, creado_por)
            SELECT v_id_os, t.id_usuario, IF(t.rol = 'principal', 'Técnico principal', 'Técnico de apoyo'), 'habilitado', p_id_usuario
            FROM tmp_prg_tec t;
        END IF;

        IF p_cambio_equipos = 1 THEN
            UPDATE programacion_equipo SET eliminado_en = NOW(), eliminado_por = p_id_usuario
            WHERE id_programacion = p_id_programacion AND eliminado_en IS NULL;
            INSERT INTO programacion_equipo (id_programacion, id_equipo, creado_por)
            SELECT p_id_programacion, q.id_equipo, p_id_usuario FROM tmp_prg_eq q;
        END IF;

        -- Reflejo en la OS (la leen la bandeja HU-35, el expediente y la app móvil)
        UPDATE orden_servicio
        SET    id_tecnico_principal       = v_tec,
               fecha_ejecucion            = v_fecha,
               hora_inicio                = v_ini,
               hora_fin_estimada          = v_fin,
               confirmacion_cliente       = IF(p_cambio_horario = 1, 0, confirmacion_cliente),
               id_canal_confirmacion      = IF(p_cambio_horario = 1, NULL, id_canal_confirmacion),
               id_contacto_confirma       = IF(p_cambio_horario = 1, NULL, id_contacto_confirma),
               fecha_confirmacion_cliente = IF(p_cambio_horario = 1, NULL, fecha_confirmacion_cliente),
               modificado_por             = p_id_usuario
        WHERE  id_os = v_id_os;
    END body;

    DROP TEMPORARY TABLE IF EXISTS tmp_prg_tec;
    DROP TEMPORARY TABLE IF EXISTS tmp_prg_eq;
    DROP TEMPORARY TABLE IF EXISTS tmp_ssoma_in;
    CALL SP_LimpiarSsomaProgramacion();
    IF p_error IS NOT NULL THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_apl_afectados;
    END IF;
END$$

DELIMITER ;
