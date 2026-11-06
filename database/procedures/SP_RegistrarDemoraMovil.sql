-- ============================================================
-- SP_RegistrarDemoraMovil  (App Mobile HU-05 — Registro de demoras en ruta · escritura)
-- El técnico reporta una demora durante el traslado ("llegar a planta") o al ingresar a la planta ("ingreso a planta").
--   - El técnico sale del token; la OS debe ser suya (principal o personal) y estar en el estado que permite ese tipo:
--       llegada : OS EN RUTA y sin llegada registrada. Recalcula la ETA de llegada.
--       ingreso : OS en ruta o en ejecución, con la llegada registrada y sin inicio del trabajo. Recalcula el inicio del trabajo.
--   - Solo se captura el GPS y la hora: la hora la pone el servidor (Lima, UTC-5), nunca el teléfono. Foto opcional (la ruta ya
--     guardada en el almacenamiento de archivos; la valida y guarda el back antes de llamar a este SP).
--   - El tipo de demora (motivo) debe existir en MOTIVO_DEMORA_RUTA y corresponder al ámbito (traslado | ingreso | ambos).
--   - Duración de 1 a 480 minutos. Las horas se recalculan con las reglas de SP_ObtenerEtaDemorasMovil.
--   - Antirrebote: la misma demora (mismo tipo, motivo y duración) del mismo técnico en los últimos 20 s no se duplica: se responde
--     con la ya registrada y sin avisar de nuevo.
--   - Avisa a Operaciones (supervisor o administrador del área Operaciones, o Jefe/Coordinador de Operaciones; si no hay, a los
--     administradores) y deja el registro en auditoria_evento. El impacto queda en 'retrasa' (lo lee el Seguimiento Operativo).
-- Resultados: 1 mensaje; 2 la demora (id_demora, tipo, eta_original, eta_anterior, eta_recalculada, notificados).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_RegistrarDemoraMovil;

DELIMITER $$

CREATE PROCEDURE SP_RegistrarDemoraMovil(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT,
    IN p_tipo       VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_motivo  INT,
    IN p_duracion   INT,
    IN p_descripcion VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_latitud    DECIMAL(10,7),
    IN p_longitud   DECIMAL(10,7),
    IN p_precision  DECIMAL(8,1),
    IN p_foto       VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_tipo       VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_numero     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_motivo     VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_ambito     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tecnico    VARCHAR(210) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_texto      VARCHAR(400) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_eta_orig   DATETIME;
    DECLARE v_min_lleg   INT DEFAULT 0;
    DECLARE v_llegada    DATETIME;
    DECLARE v_inicio_vig DATETIME;
    DECLARE v_ahora      DATETIME;
    DECLARE v_eta_ant    DATETIME DEFAULT NULL;
    DECLARE v_eta_nueva  DATETIME DEFAULT NULL;
    DECLARE v_inicio_trab TINYINT DEFAULT 0;
    DECLARE v_id_dem     BIGINT DEFAULT NULL;
    DECLARE v_notif      INT DEFAULT 0;
    DECLARE v_repetida   TINYINT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    -- ── Datos que llegan ─────────────────────────────────────────────────────────────────────────
    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio no encontrado o no asignado a tu usuario.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_tipo = LOWER(TRIM(IFNULL(p_tipo, '')));
    IF v_tipo NOT IN ('llegada', 'ingreso') THEN
        SELECT 1 AS IdTipoMensaje, 'Elige dónde se presenta la demora: llegar a planta o ingreso a planta.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF IFNULL(p_id_motivo, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Selecciona el tipo de demora.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF p_duracion IS NULL OR p_duracion < 1 OR p_duracion > 480 THEN
        SELECT 1 AS IdTipoMensaje, 'La duración estimada debe estar entre 1 y 480 minutos.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF CHAR_LENGTH(IFNULL(p_descripcion, '')) > 500 THEN
        SELECT 1 AS IdTipoMensaje, 'La descripción puede tener hasta 500 caracteres.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF p_latitud IS NULL OR p_longitud IS NULL OR p_latitud NOT BETWEEN -90 AND 90 OR p_longitud NOT BETWEEN -180 AND 180
       OR (p_latitud = 0 AND p_longitud = 0) THEN
        SELECT 1 AS IdTipoMensaje, 'La ubicación GPS no es válida: activa el GPS e inténtalo de nuevo.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF p_precision IS NOT NULL AND (p_precision < 0 OR p_precision > 5000) THEN
        SELECT 1 AS IdTipoMensaje, 'La precisión del GPS no es válida.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_ahora = UTC_TIMESTAMP() - INTERVAL 5 HOUR;

    START TRANSACTION;

    -- La OS debe ser del técnico del token
    SELECT os.estado, os.numero INTO v_estado, v_numero
    FROM   orden_servicio os
    WHERE  os.id_os = p_id_os AND os.eliminado_en IS NULL
      AND  (os.id_tecnico_principal = p_id_usuario
            OR EXISTS (SELECT 1 FROM os_personal op
                       WHERE op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL))
    FOR UPDATE;

    IF v_estado IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Servicio no encontrado o no asignado a tu usuario.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- El motivo debe existir y corresponder al tipo de demora
    SELECT t.String1, IFNULL(NULLIF(t.String3, ''), 'ambos') INTO v_motivo, v_ambito
    FROM   tabla_maestra t
    WHERE  t.IdMaestro = 15 AND t.IdEmpresa = 1 AND t.Num1 = p_id_motivo AND t.eliminado_en IS NULL;

    IF v_motivo IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'El tipo de demora seleccionado no es válido.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_ambito <> 'ambos' AND v_ambito <> IF(v_tipo = 'llegada', 'traslado', 'ingreso') THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje,
               IF(v_tipo = 'llegada', 'Ese tipo de demora es de ingreso a planta: no aplica al traslado.',
                                      'Ese tipo de demora es del traslado: no aplica al ingreso a planta.') AS Mensaje;
        LEAVE proc;
    END IF;

    -- Estado de la OS y de la llegada
    CALL SP_ObtenerEtaDemorasMovil(p_id_os, v_eta_orig, v_min_lleg, v_llegada, v_inicio_vig);

    SELECT IF(COUNT(*) > 0, 1, 0) INTO v_inicio_trab
    FROM   evento_campo e
    JOIN   tabla_maestra m ON m.IdMaestro = 29 AND m.IdEmpresa = 1 AND m.Num1 = e.id_tipo_evento AND m.String2 = 'INICIO_TRABAJO'
    WHERE  e.id_os = p_id_os AND e.eliminado_en IS NULL;

    IF v_tipo = 'llegada' THEN
        IF v_estado IN ('programada', 'reprogramada') THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, 'Las demoras se registran durante el traslado: primero inicia el traslado.' AS Mensaje;
            LEAVE proc;
        END IF;
        IF v_estado <> 'en_ruta' THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, 'Las demoras de llegada solo se registran con el servicio en ruta.' AS Mensaje;
            LEAVE proc;
        END IF;
        IF v_llegada IS NOT NULL THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, 'Ya registraste tu llegada: reporta la demora como ingreso a planta.' AS Mensaje;
            LEAVE proc;
        END IF;
    ELSE
        IF v_estado NOT IN ('en_ruta', 'en_ejecucion') THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, 'Las demoras de ingreso solo se registran al llegar a la planta, antes de iniciar el trabajo.' AS Mensaje;
            LEAVE proc;
        END IF;
        IF v_llegada IS NULL THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, 'Registra primero tu llegada a la planta para reportar una demora de ingreso.' AS Mensaje;
            LEAVE proc;
        END IF;
        IF v_inicio_trab = 1 THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, 'El trabajo ya inició: no se registran demoras de ingreso.' AS Mensaje;
            LEAVE proc;
        END IF;
    END IF;

    -- Antirrebote: la misma demora hace menos de 20 s ya está registrada
    SELECT d.id_demora, d.eta_anterior, d.eta_recalculada INTO v_id_dem, v_eta_ant, v_eta_nueva
    FROM   demora_registro d
    WHERE  d.id_os = p_id_os AND d.id_usuario = p_id_usuario AND d.tipo = v_tipo AND d.id_motivo = p_id_motivo
      AND  d.duracion_minutos = p_duracion AND d.eliminado_en IS NULL AND d.fecha_registro >= v_ahora - INTERVAL 20 SECOND
    ORDER BY d.id_demora DESC LIMIT 1;

    IF v_id_dem IS NOT NULL THEN
        SET v_repetida = 1;
    ELSE
        -- Horas: llegada → ETA de llegada; ingreso → inicio del trabajo previsto (nunca antes de "ahora")
        IF v_tipo = 'llegada' THEN
            SET v_eta_ant   = IF(v_eta_orig IS NULL, NULL, v_eta_orig + INTERVAL v_min_lleg MINUTE);
            SET v_eta_nueva = IF(v_eta_ant IS NULL, NULL, v_eta_ant + INTERVAL p_duracion MINUTE);
        ELSE
            SET v_eta_ant   = GREATEST(IFNULL(v_inicio_vig, v_ahora), v_ahora);
            SET v_eta_nueva = v_eta_ant + INTERVAL p_duracion MINUTE;
        END IF;

        INSERT INTO demora_registro
            (id_os, id_usuario, id_motivo, tipo, descripcion, duracion_minutos, impacto, fotografia_url,
             latitud, longitud, precision_metros, eta_anterior, eta_recalculada, fecha_registro, creado_por)
        VALUES
            (p_id_os, p_id_usuario, p_id_motivo, v_tipo, NULLIF(TRIM(IFNULL(p_descripcion, '')), ''), p_duracion, 'retrasa',
             NULLIF(TRIM(IFNULL(p_foto, '')), ''), p_latitud, p_longitud, p_precision, v_eta_ant, v_eta_nueva, v_ahora, p_id_usuario);
        SET v_id_dem = LAST_INSERT_ID();

        -- Aviso a Operaciones
        SELECT TRIM(CONCAT(IFNULL(nombre, ''), ' ', IFNULL(apellido, ''))) INTO v_tecnico FROM usuario WHERE id_usuario = p_id_usuario;
        SET v_texto = LEFT(CONCAT(v_numero, ' · ', IF(v_tipo = 'llegada', 'Llegar a planta', 'Ingreso a planta'), ' +', p_duracion, ' min · ',
                                  v_motivo, ' · ', IFNULL(v_tecnico, '')), 400);

        INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
        SELECT u.id_usuario, 5, 'Demora en ruta', v_texto, 'orden_servicio', p_id_os, NOW(), p_id_usuario
        FROM   usuario u
        WHERE  u.eliminado_en IS NULL AND u.estado = 'activo' AND u.id_usuario <> p_id_usuario
          AND  ((u.area = 'operaciones' AND u.rol_sistema IN ('supervisor', 'administrador'))
                OR u.cargo IN ('jefe_operaciones', 'coordinador_operaciones'));
        SET v_notif = ROW_COUNT();

        -- Respaldo: si no hay nadie en Operaciones, los administradores
        IF v_notif = 0 THEN
            INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
            SELECT u.id_usuario, 5, 'Demora en ruta', v_texto, 'orden_servicio', p_id_os, NOW(), p_id_usuario
            FROM   usuario u
            WHERE  u.eliminado_en IS NULL AND u.estado = 'activo' AND u.id_usuario <> p_id_usuario
              AND  u.rol_sistema IN ('administrador', 'admin');
            SET v_notif = ROW_COUNT();
        END IF;

        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
        VALUES ('orden_servicio', p_id_os, 'registrar_demora', v_estado, v_estado,
                LEFT(CONCAT('Demora ', IF(v_tipo = 'llegada', 'al llegar a planta', 'en el ingreso a planta'), ': ', v_motivo, ', ', p_duracion, ' min.'), 900),
                p_id_usuario, NOW(),
                JSON_OBJECT('id_demora', v_id_dem, 'tipo', v_tipo, 'minutos', p_duracion, 'notificados', v_notif));
    END IF;

    COMMIT;

    SELECT 2 AS IdTipoMensaje,
           CONCAT('Demora registrada. ',
                  IF(v_tipo = 'llegada', 'ETA recalculada: ', 'Inicio de trabajo recalculado: '),
                  IFNULL(TIME_FORMAT(v_eta_nueva, '%H:%i'), '—'), '. ',
                  IF(v_repetida = 1, 'Ya estaba registrada.',
                     IF(v_notif > 0, 'Se avisó a Operaciones.', 'No hay un responsable de Operaciones activo para avisar: informa a tu jefe.'))) AS Mensaje;

    SELECT v_id_dem AS id_demora, v_tipo AS tipo, v_eta_orig AS eta_original, v_eta_ant AS eta_anterior, v_eta_nueva AS eta_recalculada, v_notif AS notificados;
END$$

DELIMITER ;
