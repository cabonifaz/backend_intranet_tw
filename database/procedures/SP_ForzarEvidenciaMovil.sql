-- ============================================================
-- SP_ForzarEvidenciaMovil  (App Mobile HU-12 — Override de evidencia fotográfica · escritura)
-- El técnico acepta a la fuerza una toma que la IA rechazó, en una situación excepcional donde no puede conseguir una mejor.
--   - Solo con un MOTIVO ESCRITO (3 a 300 caracteres). Solo se fuerza la última captura de la evidencia (vigente) y solo si está rechazada.
--   - Acceso: OS del técnico, Hard Stop y equipo EN EJECUCIÓN (SP_ContextoEquipoMovil).
--   - Marca la evidencia FORZADA (override_aprobado = 1) con el motivo, quién y cuándo (la validación de la IA y su motivo de rechazo se conservan).
--     Cuenta como completa en el panel.
--   - Consecuencias que la app muestra ANTES de confirmar y que se cumplen aquí: queda registrada como excepción en el expediente (auditoria_evento),
--     suma al contador de evidencias forzadas del scorecard del técnico del mes (tecnico_scorecard.foto_override_count) y queda visible para Jefatura
--     (notificación al encargado del área según la RQ; si no hay, a los administradores).
--   - Repetir la petición sobre una evidencia ya forzada responde éxito sin duplicar nada.
-- Resultados: 1 mensaje; 2 (id_evidencia, forzada_en en Lima, intentos_previos, notificados).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ForzarEvidenciaMovil;

DELIMITER $$

CREATE PROCEDURE SP_ForzarEvidenciaMovil(
    IN p_id_usuario    BIGINT,
    IN p_id_os         BIGINT,
    IN p_id_os_equipo  BIGINT,
    IN p_id_evidencia  BIGINT,
    IN p_motivo        VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
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
    DECLARE v_motivo   VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_codigo   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_valida   VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_ya       TINYINT DEFAULT 0;
    DECLARE v_vigente  TINYINT DEFAULT 0;
    DECLARE v_intento  INT DEFAULT 1;
    DECLARE v_motivo_ia VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_forzada  DATETIME DEFAULT NULL;
    DECLARE v_mes      DATE;
    DECLARE v_area     VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_enc   BIGINT;
    DECLARE v_nom_enc  VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_car_enc  VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tel_enc  VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_nombre_tec VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_texto    VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_notif    INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 OR IFNULL(p_id_os_equipo, 0) <= 0 OR IFNULL(p_id_evidencia, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Evidencia no encontrada.' AS Mensaje; LEAVE proc;
    END IF;
    SET v_motivo = NULLIF(TRIM(IFNULL(p_motivo, '')), '');
    IF v_motivo IS NULL OR CHAR_LENGTH(v_motivo) < 3 THEN
        SELECT 1 AS IdTipoMensaje, 'Escribe el motivo por el que aceptas la foto (mínimo 3 caracteres).' AS Mensaje; LEAVE proc;
    END IF;
    IF CHAR_LENGTH(v_motivo) > 300 THEN
        SELECT 1 AS IdTipoMensaje, 'El motivo puede tener hasta 300 caracteres.' AS Mensaje; LEAVE proc;
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

    SELECT f.codigo, f.validacion_ia, f.override_aprobado, f.vigente, f.intento, f.motivo_rechazo_ia, f.forzada_en
    INTO   v_codigo, v_valida, v_ya, v_vigente, v_intento, v_motivo_ia, v_forzada
    FROM   evidencia_fotografica f
    WHERE  f.id_evidencia = p_id_evidencia AND f.id_os = p_id_os AND f.id_equipo = v_id_eq AND f.eliminado_en IS NULL
    FOR UPDATE;

    IF v_codigo IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Evidencia no encontrada.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_ya = 1 THEN
        COMMIT;
        SELECT 2 AS IdTipoMensaje, 'Esta evidencia ya estaba aceptada como forzada.' AS Mensaje;
        SELECT p_id_evidencia AS id_evidencia, CONVERT_TZ(v_forzada, '+00:00', '-05:00') AS forzada_en, v_intento - 1 AS intentos_previos, 0 AS notificados;
        LEAVE proc;
    END IF;
    IF v_valida <> 'rechazada' THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Solo se puede forzar una foto que la IA rechazó.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_vigente = 0 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Esa toma ya fue reemplazada por una más reciente.' AS Mensaje; LEAVE proc;
    END IF;

    SET v_forzada = UTC_TIMESTAMP();
    UPDATE evidencia_fotografica
    SET    override_aprobado = 1, id_usuario_override = p_id_usuario, motivo_forzado = v_motivo, forzada_en = v_forzada, modificado_por = p_id_usuario
    WHERE  id_evidencia = p_id_evidencia;

    -- Scorecard del técnico (mes en curso, hora de Lima)
    SET v_mes = DATE_FORMAT(UTC_TIMESTAMP() - INTERVAL 5 HOUR, '%Y-%m-01');
    UPDATE tecnico_scorecard SET foto_override_count = foto_override_count + 1, modificado_por = p_id_usuario
    WHERE  id_usuario = p_id_usuario AND periodo_mes = v_mes AND eliminado_en IS NULL;
    IF ROW_COUNT() = 0 THEN
        INSERT INTO tecnico_scorecard (id_usuario, periodo_mes, foto_override_count, creado_por) VALUES (p_id_usuario, v_mes, 1, p_id_usuario);
    END IF;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('os_equipo', p_id_os_equipo, 'forzar_evidencia', 'rechazada', 'forzada',
            LEFT(CONCAT('Evidencia ', v_codigo, ' de ', v_num_os, ' aceptada a la fuerza tras ', v_intento, IF(v_intento = 1, ' intento', ' intentos'),
                        '. Rechazo de la IA: ', IFNULL(v_motivo_ia, '—'), '. Motivo del técnico: ', v_motivo), 900),
            p_id_usuario, NOW(),
            JSON_OBJECT('id_evidencia', p_id_evidencia, 'codigo', v_codigo, 'intentos', v_intento, 'motivo', v_motivo, 'motivo_ia', v_motivo_ia));

    -- Visible para Jefatura: aviso al encargado del área (si no hay, a los administradores)
    CALL SP_ContactoEncargadoEnsayoMovil(p_id_os, v_area, v_id_enc, v_nom_enc, v_car_enc, v_tel_enc);
    SELECT TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))) INTO v_nombre_tec FROM usuario u WHERE u.id_usuario = p_id_usuario LIMIT 1;
    SET v_texto = LEFT(CONCAT(v_nombre_tec, ' aceptó a la fuerza la evidencia «', v_codigo, '» de ', v_nombre, ' (', v_num_os, '), rechazada por la IA. Motivo: ', v_motivo), 500);
    IF v_id_enc IS NOT NULL AND v_id_enc <> p_id_usuario THEN
        INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
        VALUES (v_id_enc, 5, 'Evidencia forzada', v_texto, 'orden_servicio', p_id_os, NOW(), p_id_usuario);
        SET v_notif = 1;
    ELSE
        INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
        SELECT u.id_usuario, 5, 'Evidencia forzada', v_texto, 'orden_servicio', p_id_os, NOW(), p_id_usuario
        FROM   usuario u
        WHERE  u.eliminado_en IS NULL AND u.estado = 'activo' AND u.id_usuario <> p_id_usuario AND u.rol_sistema IN ('administrador', 'admin');
        SET v_notif = ROW_COUNT();
    END IF;

    COMMIT;

    SELECT 2 AS IdTipoMensaje, 'Foto aceptada como evidencia forzada: quedó registrada y visible para Jefatura.' AS Mensaje;
    SELECT p_id_evidencia AS id_evidencia, CONVERT_TZ(v_forzada, '+00:00', '-05:00') AS forzada_en, v_intento - 1 AS intentos_previos, v_notif AS notificados;
END$$

DELIMITER ;
