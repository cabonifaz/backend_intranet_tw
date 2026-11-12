-- HU-06 Llegada forzada: tabla + 3 SP nuevos + 5 SP ajustados. Ejecutar completo (Alt+X en DBeaver) y reiniciar la API.

-- ===== migrations/111_llegada_forzada.sql =====
-- ============================================================
-- Migración 111 — Llegada forzada (HU-06): el técnico fuera del radio permitido pide a Jefatura que le autorice registrar su llegada
--   Tras 5 capturas de ubicación fuera del rango, la app ofrece «Confirmar llegada forzada»: crea una solicitud que le llega al encargado del área
--   (misma regla que la autorización de salida) y aparece en Aprobaciones. Solo cuando el encargado la aprueba el técnico puede registrar la llegada
--   (una sola vez: la aprobación se marca como usada al registrar). IDEMPOTENTE.
-- ============================================================
CREATE TABLE IF NOT EXISTS llegada_forzada_os (
    id_solicitud     BIGINT        NOT NULL AUTO_INCREMENT,
    id_os            BIGINT        NOT NULL,
    id_tecnico       BIGINT        NOT NULL,
    estado           ENUM('pendiente','aprobada','rechazada') NOT NULL DEFAULT 'pendiente',
    motivo           VARCHAR(500)  NULL,
    intentos         SMALLINT      NOT NULL DEFAULT 0,          -- capturas fuera de rango que hizo el técnico antes de pedirla
    latitud          DECIMAL(10,7) NULL,                        -- dónde estaba al pedirla
    longitud         DECIMAL(10,7) NULL,
    precision_metros DECIMAL(8,1)  NULL,
    distancia_metros INT           NULL,                        -- a cuántos metros de la planta
    area_destino     VARCHAR(30)   NULL,                        -- AREA_USUARIO del encargado al que se avisó (según la RQ)
    solicitado_en    DATETIME      NULL,
    id_jefe          BIGINT        NULL,
    resuelto_en      DATETIME      NULL,
    comentario       VARCHAR(500)  NULL,
    usada_en         DATETIME      NULL,                        -- cuando el técnico registró la llegada con esta aprobación
    -- AUDITORÍA
    creado_en        DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por       BIGINT        NULL,
    modificado_en    DATETIME      NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por   BIGINT        NULL,
    eliminado_en     DATETIME      NULL,
    eliminado_por    BIGINT        NULL,
    PRIMARY KEY (id_solicitud),
    KEY ix_llegada_forzada_os (id_os, estado),
    KEY ix_llegada_forzada_estado (estado, solicitado_en)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

SELECT 'Migración 111 (debe ser 1)' AS verificacion, COUNT(*) AS valor FROM information_schema.TABLES
WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'llegada_forzada_os';

-- ===== procedures/SP_SolicitarLlegadaForzadaMovil.sql =====
-- ============================================================
-- SP_SolicitarLlegadaForzadaMovil  (App Mobile HU-06 — llegada forzada · escritura)
-- El técnico, que sigue fuera del radio permitido tras volver a capturar su ubicación (mínimo 5 veces), pide a Jefatura que le autorice registrar la llegada.
--   - El técnico sale del token; la OS debe ser suya y estar EN RUTA, sin llegada registrada en este viaje.
--   - La ubicación se evalúa AQUÍ (SP_EvaluarLlegadaMovil): solo se puede pedir si de verdad está fuera del rango (con señal GPS aceptable).
--     Dentro del rango o sin coordenada de la planta no hace falta autorización.
--   - Mínimo de intentos (p_intentos, lo cuenta la app) = 5: LLEGADA_FORZADA_INTENTOS (PARAMETRO_PROGRAMACION, por defecto 5).
--   - Una sola solicitud pendiente por OS; si ya hay una aprobada sin usar se avisa que ya puede registrar.
--   - Destinatarios: el encargado del área de la RQ (cargo jefe_*); respaldos: supervisores del área, Jefe/Coordinador de Operaciones, administradores
--     (misma regla que la autorización de salida, SP_SolicitarAutorizacionSalidaMovil). Les llega una notificación «Llegada forzada · OS».
--   - Deja una notificación de confirmación al técnico y el registro en auditoria_evento.
-- Resultado: 1 fila (IdTipoMensaje, Mensaje).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_SolicitarLlegadaForzadaMovil;

DELIMITER $$

CREATE PROCEDURE SP_SolicitarLlegadaForzadaMovil(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT,
    IN p_latitud    DECIMAL(10,7),
    IN p_longitud   DECIMAL(10,7),
    IN p_precision  DECIMAL(8,1),
    IN p_intentos   INT,
    IN p_motivo     VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_estado      VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_numero      VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cliente     VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tecnico     VARCHAR(210) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_area        VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_area_nombre VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_notificados VARCHAR(600) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_ult_estado  VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_ult_usada   DATETIME;
    DECLARE v_salida_utc  DATETIME;
    DECLARE v_ya_llego    TINYINT DEFAULT 0;
    DECLARE v_min_int     DECIMAL(18,6);
    DECLARE v_id_sol      BIGINT;
    DECLARE v_destinos    INT DEFAULT 0;
    DECLARE v_resultado   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_registrable TINYINT;
    DECLARE v_distancia   INT;
    DECLARE v_radio       INT;
    DECLARE v_pmax        INT;
    DECLARE v_lat_ref     DECIMAL(10,7);
    DECLARE v_lon_ref     DECIMAL(10,7);
    DECLARE v_mensaje     VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio no encontrado o no asignado a tu usuario.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF p_latitud IS NULL OR p_longitud IS NULL OR p_latitud NOT BETWEEN -90 AND 90 OR p_longitud NOT BETWEEN -180 AND 180
       OR (p_latitud = 0 AND p_longitud = 0) THEN
        SELECT 1 AS IdTipoMensaje, 'La ubicación GPS no es válida: activa el GPS e inténtalo de nuevo.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF p_precision IS NULL OR p_precision < 0 OR p_precision > 5000 THEN
        SELECT 1 AS IdTipoMensaje, 'La precisión del GPS no es válida.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_LeerParametroProgramacion('LLEGADA_FORZADA_INTENTOS', 5, v_min_int);
    IF IFNULL(p_intentos, 0) < v_min_int THEN
        SELECT 1 AS IdTipoMensaje, CONCAT('Vuelve a capturar tu ubicación al menos ', ROUND(v_min_int), ' veces antes de pedir la llegada forzada.') AS Mensaje;
        LEAVE proc;
    END IF;

    START TRANSACTION;

    SELECT os.estado, os.numero, COALESCE(NULLIF(cl.nombre_comercial, ''), cl.razon_social), asr.area_usuario
    INTO   v_estado, v_numero, v_cliente, v_area
    FROM   orden_servicio os
    LEFT JOIN cliente            cl  ON cl.id_cliente        = os.id_cliente
    LEFT JOIN expediente_digital ed  ON ed.id_expediente     = os.id_expediente
    LEFT JOIN requerimiento      rq  ON rq.id_requerimiento  = ed.id_requerimiento
    LEFT JOIN area_servicio_rq   asr ON asr.id_area_rq       = rq.id_area
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
    IF v_estado <> 'en_ruta' THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'La llegada solo se registra con el servicio en ruta.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- ¿Ya llegó en este viaje? (evento LLEGADA posterior a la última salida)
    SELECT MAX(e.timestamp_utc) INTO v_salida_utc
    FROM   evento_campo e
    JOIN   tabla_maestra m ON m.IdMaestro = 29 AND m.IdEmpresa = 1 AND m.Num1 = e.id_tipo_evento AND m.String2 = 'SALIDA_BASE'
    WHERE  e.id_os = p_id_os AND e.eliminado_en IS NULL;
    SELECT IF(COUNT(*) > 0, 1, 0) INTO v_ya_llego
    FROM   evento_campo e
    JOIN   tabla_maestra m ON m.IdMaestro = 29 AND m.IdEmpresa = 1 AND m.Num1 = e.id_tipo_evento AND m.String2 = 'LLEGADA'
    WHERE  e.id_os = p_id_os AND e.eliminado_en IS NULL AND e.timestamp_utc >= IFNULL(v_salida_utc, '1000-01-01');
    IF v_ya_llego = 1 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Ya registraste tu llegada.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT s.estado, s.usada_en INTO v_ult_estado, v_ult_usada
    FROM   llegada_forzada_os s
    WHERE  s.id_os = p_id_os AND s.eliminado_en IS NULL
    ORDER BY s.id_solicitud DESC LIMIT 1;

    IF v_ult_estado = 'pendiente' THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Ya enviaste la solicitud: espera la respuesta de Jefatura.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_ult_estado = 'aprobada' AND v_ult_usada IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Jefatura ya autorizó tu llegada: confírmala.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Solo se pide estando de verdad fuera del rango
    CALL SP_EvaluarLlegadaMovil(p_id_os, p_latitud, p_longitud, p_precision, v_resultado, v_registrable, v_distancia, v_radio, v_pmax,
                                v_lat_ref, v_lon_ref, v_mensaje);
    IF v_resultado <> 'fuera_rango' THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje,
               CASE v_resultado
                   WHEN 'precision_baja' THEN v_mensaje
                   ELSE 'No hace falta autorización: tu ubicación ya permite registrar la llegada.' END AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT TRIM(CONCAT(IFNULL(nombre, ''), ' ', IFNULL(apellido, ''))) INTO v_tecnico FROM usuario WHERE id_usuario = p_id_usuario;
    SET v_area_nombre = (SELECT t.String1 FROM tabla_maestra t WHERE t.IdMaestro = 79 AND t.IdEmpresa = 1 AND t.String2 = v_area LIMIT 1);

    INSERT INTO llegada_forzada_os (id_os, id_tecnico, estado, motivo, intentos, latitud, longitud, precision_metros, distancia_metros,
                                    area_destino, solicitado_en, creado_por)
    VALUES (p_id_os, p_id_usuario, 'pendiente', NULLIF(TRIM(p_motivo), ''), p_intentos, p_latitud, p_longitud, p_precision, v_distancia,
            v_area, NOW(), p_id_usuario);
    SET v_id_sol = LAST_INSERT_ID();

    -- Destinatarios (misma regla que la autorización de salida)
    DROP TEMPORARY TABLE IF EXISTS tmp_llf_destino;
    CREATE TEMPORARY TABLE tmp_llf_destino (
        id_usuario BIGINT PRIMARY KEY,
        nombre     VARCHAR(210) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        cargo      VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
    );

    INSERT IGNORE INTO tmp_llf_destino
    SELECT u.id_usuario, TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))), c.String1
    FROM   usuario u
    JOIN   tabla_maestra c ON c.IdMaestro = 80 AND c.IdEmpresa = 1 AND c.String2 = u.cargo
    WHERE  u.eliminado_en IS NULL AND u.estado = 'activo'
      AND  c.String2 LIKE 'jefe\_%'
      AND  ((v_area IS NOT NULL AND c.String3 = v_area)
            OR (v_area IS NULL AND c.String3 IN ('servicio_tecnico', 'metrologia')));

    IF (SELECT COUNT(*) FROM tmp_llf_destino) = 0 THEN
        INSERT IGNORE INTO tmp_llf_destino
        SELECT u.id_usuario, TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))), NULL
        FROM   usuario u
        WHERE  u.eliminado_en IS NULL AND u.estado = 'activo' AND u.rol_sistema IN ('supervisor', 'administrador')
          AND  ((v_area IS NOT NULL AND u.area = v_area) OR (v_area IS NULL AND u.area IN ('servicio_tecnico', 'metrologia')));
    END IF;
    IF (SELECT COUNT(*) FROM tmp_llf_destino) = 0 THEN
        INSERT IGNORE INTO tmp_llf_destino
        SELECT u.id_usuario, TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))), NULL
        FROM   usuario u
        WHERE  u.eliminado_en IS NULL AND u.estado = 'activo' AND u.cargo IN ('jefe_operaciones', 'coordinador_operaciones');
    END IF;
    IF (SELECT COUNT(*) FROM tmp_llf_destino) = 0 THEN
        INSERT IGNORE INTO tmp_llf_destino
        SELECT u.id_usuario, TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))), NULL
        FROM   usuario u
        WHERE  u.eliminado_en IS NULL AND u.estado = 'activo' AND u.rol_sistema IN ('administrador', 'admin');
    END IF;

    INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
    SELECT d.id_usuario, 5,
           CONCAT('Llegada forzada', IF(v_area_nombre IS NULL, '', CONCAT(' · ', v_area_nombre)), ': ', v_numero),
           LEFT(CONCAT(v_tecnico, ' está a ', FORMAT(v_distancia, 0), ' m de la planta de ', IFNULL(v_cliente, 'el cliente'), ' (', v_numero, ') y pide autorización para registrar su llegada.',
                       ' Capturó su ubicación ', p_intentos, ' veces (permitido hasta ', v_radio, ' m).',
                       IF(NULLIF(TRIM(p_motivo), '') IS NULL, '', CONCAT(' Motivo: ', TRIM(p_motivo)))), 3000),
           'orden_servicio', p_id_os, NOW(), p_id_usuario
    FROM   tmp_llf_destino d;
    SET v_destinos = ROW_COUNT();

    SELECT GROUP_CONCAT(CONCAT(d.nombre, IFNULL(CONCAT(' (', d.cargo, ')'), '')) ORDER BY d.nombre SEPARATOR ', ') INTO v_notificados FROM tmp_llf_destino d;
    DROP TEMPORARY TABLE IF EXISTS tmp_llf_destino;

    INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
    VALUES (p_id_usuario, 5, 'Solicitud de llegada forzada enviada',
            LEFT(CONCAT(v_numero, ' · ', IF(v_notificados IS NULL, 'sin un encargado activo para avisar', CONCAT('avisado a ', v_notificados))), 3000),
            'orden_servicio', p_id_os, NOW(), p_id_usuario);

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('orden_servicio', p_id_os, 'solicitar_llegada_forzada', IFNULL(v_ult_estado, 'sin_solicitud'), 'pendiente',
            LEFT(CONCAT('El técnico pide autorización para registrar la llegada a ', v_distancia, ' m de la planta tras ', p_intentos, ' capturas.',
                        IF(NULLIF(TRIM(p_motivo), '') IS NULL, '', CONCAT(' Motivo: ', TRIM(p_motivo)))), 900),
            p_id_usuario, NOW(),
            JSON_OBJECT('id_solicitud', v_id_sol, 'distancia_m', v_distancia, 'intentos', p_intentos, 'area_destino', v_area, 'notificados', v_destinos));

    COMMIT;

    SELECT 2 AS IdTipoMensaje,
           IF(v_destinos > 0, CONCAT('Solicitud enviada a ', v_notificados, '. Espera su aprobación para registrar tu llegada.'),
              'Solicitud registrada, pero no hay un encargado activo para notificar: avisa a tu jefe.') AS Mensaje;
END$$

DELIMITER ;

-- ===== procedures/SP_ObtenerLlegadasForzadas.sql =====
-- ============================================================
-- SP_ObtenerLlegadasForzadas  (App Mobile HU-06 / HU-31 — bandeja de Aprobaciones del encargado · lectura)
-- Solicitudes de llegada forzada que puede ver el usuario (misma regla de áreas que las autorizaciones de salida):
--   encargado de área (Jefe de Servicio Técnico / Jefe de Metrología o supervisor de Metrología): las de SU área y las sin área en la RQ;
--   Jefe/Coordinador de Operaciones, supervisor de Operaciones y administradores: todas.
--   p_id_os = 0/NULL → las PENDIENTES (la bandeja). p_id_os > 0 → la más reciente de esa OS, en cualquier estado (el detalle).
-- Resultado: 1 mensaje · 2 filas (id_solicitud, id_os, numero_os, cliente, sede, fecha_ejecucion, hora_inicio, tecnico, estado, motivo, intentos,
--   latitud, longitud, precision_metros, distancia_m, lat_planta, lon_planta, radio_m, area_destino, area, solicitado_en, jefe, resuelto_en, comentario, usada_en).
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerLlegadasForzadas;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerLlegadasForzadas(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT
)
proc: BEGIN
    DECLARE v_area_jefe VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_general   TINYINT DEFAULT 0;
    DECLARE v_existe    TINYINT DEFAULT 0;
    DECLARE v_radio     DECIMAL(18,6);

    SELECT 1,
           COALESCE(IF(c.String2 LIKE 'jefe\_%' AND c.String3 IN ('servicio_tecnico', 'metrologia'), c.String3, NULL),
                    IF(u.rol_sistema = 'supervisor' AND u.area = 'metrologia', 'metrologia', NULL)),
           (u.cargo IN ('jefe_operaciones', 'coordinador_operaciones') OR u.rol_sistema IN ('administrador', 'admin')
            OR (u.rol_sistema = 'supervisor' AND u.area = 'operaciones'))
    INTO   v_existe, v_area_jefe, v_general
    FROM   usuario u
    LEFT JOIN tabla_maestra c ON c.IdMaestro = 80 AND c.IdEmpresa = 1 AND c.String2 = u.cargo
    WHERE  u.id_usuario = p_id_usuario AND u.eliminado_en IS NULL AND u.estado = 'activo'
    LIMIT 1;

    IF v_existe = 0 OR (v_area_jefe IS NULL AND v_general = 0) THEN
        SELECT 1 AS IdTipoMensaje, 'Solo los encargados de Servicio Técnico y Metrología pueden ver las llegadas forzadas.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_LeerParametroProgramacion('LLEGADA_RADIO_METROS', 200, v_radio);

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT s.id_solicitud,
           s.id_os,
           os.numero                                                        AS numero_os,
           COALESCE(NULLIF(cl.nombre_comercial, ''), cl.razon_social)       AS cliente,
           COALESCE(NULLIF(sc.nombre, ''), sc2.nombre)                      AS sede,
           os.fecha_ejecucion,
           TIME_FORMAT(os.hora_inicio, '%H:%i')                             AS hora_inicio,
           NULLIF(TRIM(CONCAT(IFNULL(tc.nombre, ''), ' ', IFNULL(tc.apellido, ''))), '') AS tecnico,
           s.estado,
           s.motivo,
           s.intentos,
           s.latitud,
           s.longitud,
           s.precision_metros,
           s.distancia_metros                                               AS distancia_m,
           COALESCE(sc.latitud, sc2.latitud, os.latitud_llegada)            AS lat_planta,
           COALESCE(sc.longitud, sc2.longitud, os.longitud_llegada)         AS lon_planta,
           ROUND(v_radio)                                                   AS radio_m,
           s.area_destino,
           ar.String1                                                       AS area,
           s.solicitado_en,
           NULLIF(TRIM(CONCAT(IFNULL(jf.nombre, ''), ' ', IFNULL(jf.apellido, ''))), '') AS jefe,
           s.resuelto_en,
           s.comentario,
           s.usada_en
    FROM   llegada_forzada_os s
    JOIN   orden_servicio os ON os.id_os = s.id_os AND os.eliminado_en IS NULL
    LEFT JOIN cliente        cl  ON cl.id_cliente = os.id_cliente
    LEFT JOIN sede_cliente   sc  ON sc.id_sede = os.id_sede AND sc.SoftDelete = 0
    LEFT JOIN requerimiento  rq  ON rq.id_requerimiento = os.id_requerimiento
    LEFT JOIN sede_cliente   sc2 ON sc2.id_sede = rq.id_sede AND sc2.SoftDelete = 0
    LEFT JOIN usuario        tc  ON tc.id_usuario = s.id_tecnico
    LEFT JOIN usuario        jf  ON jf.id_usuario = s.id_jefe
    LEFT JOIN tabla_maestra  ar  ON ar.IdMaestro = 79 AND ar.IdEmpresa = 1 AND ar.String2 = s.area_destino
    WHERE  s.eliminado_en IS NULL
      AND  (v_general = 1 OR s.area_destino IS NULL OR s.area_destino = v_area_jefe)
      AND  ((IFNULL(p_id_os, 0) = 0 AND s.estado = 'pendiente')
            OR (IFNULL(p_id_os, 0) > 0 AND s.id_os = p_id_os
                AND s.id_solicitud = (SELECT MAX(x.id_solicitud) FROM llegada_forzada_os x WHERE x.id_os = p_id_os AND x.eliminado_en IS NULL)))
    ORDER BY s.solicitado_en DESC, s.id_solicitud DESC
    LIMIT 200;
END$$

DELIMITER ;

-- ===== procedures/SP_ResolverLlegadaForzada.sql =====
-- ============================================================
-- SP_ResolverLlegadaForzada  (App Mobile HU-06 / HU-31 — el encargado aprueba o rechaza la llegada forzada · escritura)
--   - Pueden resolver las mismas personas que ven la solicitud (SP_ObtenerLlegadasForzadas): el encargado del ÁREA de la solicitud, la supervisión
--     general (Jefe/Coordinador de Operaciones, supervisor de Operaciones) y los administradores. El de la otra área NO.
--   - Solo una solicitud PENDIENTE de la OS; el comentario es obligatorio (condición al aprobar, motivo al rechazar; 3 a 500 caracteres).
--   - Aprobar deja a la OS lista para que el técnico registre su llegada UNA vez (SP_EvaluarLlegadaMovil → 'autorizada'); rechazar le pide volver a
--     acercarse (puede intentarlo otra vez tras 5 capturas más).
--   - Notifica al técnico principal y al personal de la OS («Llegada forzada aprobada/rechazada») y deja el registro en auditoria_evento.
-- Resultado: 1 fila (IdTipoMensaje, Mensaje).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ResolverLlegadaForzada;

DELIMITER $$

CREATE PROCEDURE SP_ResolverLlegadaForzada(
    IN p_id_jefe    BIGINT,
    IN p_id_os      BIGINT,
    IN p_aprobar    TINYINT,
    IN p_comentario VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_numero     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado_os  VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cliente    VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_jefe       VARCHAR(210) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cargo_jefe VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_area_jefe  VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_general    TINYINT DEFAULT 0;
    DECLARE v_principal  BIGINT;
    DECLARE v_id_sol     BIGINT;
    DECLARE v_sol_estado VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_sol_area   VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_nuevo      VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SELECT TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))),
           IFNULL(c.String1, NULLIF(u.cargo, '')),
           COALESCE(IF(c.String2 LIKE 'jefe\_%' AND c.String3 IN ('servicio_tecnico', 'metrologia'), c.String3, NULL),
                    IF(u.rol_sistema = 'supervisor' AND u.area = 'metrologia', 'metrologia', NULL)),
           (u.cargo IN ('jefe_operaciones', 'coordinador_operaciones') OR u.rol_sistema IN ('administrador', 'admin')
            OR (u.rol_sistema = 'supervisor' AND u.area = 'operaciones'))
    INTO   v_jefe, v_cargo_jefe, v_area_jefe, v_general
    FROM   usuario u
    LEFT JOIN tabla_maestra c ON c.IdMaestro = 80 AND c.IdEmpresa = 1 AND c.String2 = u.cargo
    WHERE  u.id_usuario = p_id_jefe AND u.eliminado_en IS NULL AND u.estado = 'activo'
    LIMIT 1;

    IF v_jefe IS NULL OR (v_area_jefe IS NULL AND v_general = 0) THEN
        SELECT 1 AS IdTipoMensaje, 'Solo el encargado del área (Servicio Técnico o Metrología) puede resolver la llegada forzada.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF NULLIF(TRIM(p_comentario), '') IS NULL OR CHAR_LENGTH(TRIM(p_comentario)) < 3 THEN
        SELECT 1 AS IdTipoMensaje, IF(p_aprobar = 1, 'Indica la condición con la que autorizas la llegada.', 'Indica el motivo por el que no autorizas la llegada.') AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_nuevo = IF(p_aprobar = 1, 'aprobada', 'rechazada');

    START TRANSACTION;

    SELECT os.numero, os.estado, os.id_tecnico_principal, COALESCE(NULLIF(cl.nombre_comercial, ''), cl.razon_social)
    INTO   v_numero, v_estado_os, v_principal, v_cliente
    FROM   orden_servicio os
    LEFT JOIN cliente cl ON cl.id_cliente = os.id_cliente
    WHERE  os.id_os = p_id_os AND os.eliminado_en IS NULL
    FOR UPDATE;

    IF v_numero IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Orden de servicio no encontrada.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT s.id_solicitud, s.estado, s.area_destino INTO v_id_sol, v_sol_estado, v_sol_area
    FROM   llegada_forzada_os s
    WHERE  s.id_os = p_id_os AND s.eliminado_en IS NULL
    ORDER BY s.id_solicitud DESC LIMIT 1;

    IF v_id_sol IS NULL OR v_sol_estado <> 'pendiente' THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'No hay una solicitud de llegada forzada pendiente para este servicio (quizá ya la resolvió otra persona).' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_general = 0 AND v_sol_area IS NOT NULL AND v_sol_area <> v_area_jefe THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Este servicio no es de tu área: lo autoriza el encargado del área indicada en la RQ.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF p_aprobar = 1 AND v_estado_os <> 'en_ruta' THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'El servicio ya no está en ruta: no hace falta autorizar la llegada.' AS Mensaje;
        LEAVE proc;
    END IF;

    UPDATE llegada_forzada_os
    SET    estado = v_nuevo, id_jefe = p_id_jefe, resuelto_en = NOW(), comentario = TRIM(p_comentario), modificado_por = p_id_jefe
    WHERE  id_solicitud = v_id_sol;

    INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
    SELECT d.id_usuario, 5,
           IF(p_aprobar = 1, 'Llegada forzada aprobada', 'Llegada forzada rechazada'),
           LEFT(CONCAT(v_numero, IF(v_cliente IS NULL, '', CONCAT(' · ', v_cliente)), ' · ', v_jefe,
                       IF(v_cargo_jefe IS NULL, '', CONCAT(' (', v_cargo_jefe, ')')),
                       IF(p_aprobar = 1, ' autorizó tu llegada: ya puedes registrarla.', ' no autorizó tu llegada: acércate a la planta.'),
                       IF(p_aprobar = 1, ' Condición: ', ' Motivo: '), TRIM(p_comentario)), 3000),
           'orden_servicio', p_id_os, NOW(), p_id_jefe
    FROM (
        SELECT v_principal AS id_usuario FROM DUAL WHERE v_principal IS NOT NULL
        UNION
        SELECT op.id_usuario FROM os_personal op WHERE op.id_os = p_id_os AND op.eliminado_en IS NULL
    ) d;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('orden_servicio', p_id_os, 'resolver_llegada_forzada', 'pendiente', v_nuevo,
            LEFT(CONCAT(v_jefe, IF(p_aprobar = 1, ' autorizó la llegada forzada.', ' no autorizó la llegada forzada.'), ' ', TRIM(p_comentario)), 900),
            p_id_jefe, NOW(), JSON_OBJECT('id_solicitud', v_id_sol, 'area', v_sol_area));

    COMMIT;

    SELECT 2 AS IdTipoMensaje, IF(p_aprobar = 1, 'Llegada autorizada: el técnico ya puede registrarla.', 'Llegada no autorizada.') AS Mensaje;
END$$

DELIMITER ;

-- ===== procedures/SP_EvaluarLlegadaMovil.sql =====
-- ============================================================
-- SP_EvaluarLlegadaMovil  (App Mobile HU-06 — apoyo, no es un endpoint)
-- Regla de la llegada validada por GPS, UNA sola vez (la usan la validación y el registro). Solo lectura.
--   Referencia = coordenada de la planta: sede_cliente.latitud/longitud (migración 110) de la OS o, si no tiene, la del requerimiento (RQ); luego la tabla sede; si ninguna la tiene, la llegada ya registrada de la OS
--   (orden_servicio.latitud_llegada/longitud_llegada), igual que la bandeja de Seguimiento Operativo.
--   Parámetros (PARAMETRO_PROGRAMACION, migración 97): LLEGADA_RADIO_METROS (200) y LLEGADA_PRECISION_MAX_METROS (100).
--   Resultado:
--     precision_baja  ± de la precisión supera el máximo: no se puede registrar (hay que volver a capturar en un lugar abierto)
--     sin_referencia  la planta no tiene coordenada: se puede registrar, queda sin validar distancia
--     valida          dentro del radio permitido
--     fuera_rango     fuera del radio: no se puede registrar
--     autorizada      fuera del radio, pero Jefatura aprobó la llegada forzada (llegada_forzada_os, aprobada y sin usar): se puede registrar UNA vez
--   p_registrable: 1 = se puede confirmar la llegada. p_mensaje: texto para el técnico. Distancia por Haversine (m).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_EvaluarLlegadaMovil;

DELIMITER $$

CREATE PROCEDURE SP_EvaluarLlegadaMovil(
    IN  p_id_os          BIGINT,
    IN  p_latitud        DECIMAL(10,7),
    IN  p_longitud       DECIMAL(10,7),
    IN  p_precision      DECIMAL(8,1),
    OUT p_resultado      VARCHAR(20),
    OUT p_registrable    TINYINT,
    OUT p_distancia      INT,
    OUT p_radio          INT,
    OUT p_precision_max  INT,
    OUT p_lat_ref        DECIMAL(10,7),
    OUT p_lon_ref        DECIMAL(10,7),
    OUT p_mensaje        VARCHAR(250)
)
BEGIN
    DECLARE v_radio DECIMAL(18,6);
    DECLARE v_pmax  DECIMAL(18,6);

    CALL SP_LeerParametroProgramacion('LLEGADA_RADIO_METROS', 200, v_radio);
    CALL SP_LeerParametroProgramacion('LLEGADA_PRECISION_MAX_METROS', 100, v_pmax);
    SET p_radio         = ROUND(v_radio);
    SET p_precision_max = ROUND(v_pmax);
    SET p_distancia     = NULL;
    SET p_lat_ref       = NULL;
    SET p_lon_ref       = NULL;

    SELECT COALESCE(sc.latitud, s.latitud, sc2.latitud, os.latitud_llegada), COALESCE(sc.longitud, s.longitud, sc2.longitud, os.longitud_llegada) INTO p_lat_ref, p_lon_ref
    FROM   orden_servicio os
    LEFT JOIN sede_cliente sc  ON sc.id_sede = os.id_sede AND sc.SoftDelete = 0
    LEFT JOIN sede s           ON s.id_sede = os.id_sede AND s.id_cliente = os.id_cliente AND s.eliminado_en IS NULL
    LEFT JOIN requerimiento rq ON rq.id_requerimiento = os.id_requerimiento
    LEFT JOIN sede_cliente sc2 ON sc2.id_sede = rq.id_sede AND sc2.SoftDelete = 0
    WHERE  os.id_os = p_id_os;

    IF p_precision IS NOT NULL AND p_precision > p_precision_max THEN
        SET p_resultado   = 'precision_baja';
        SET p_registrable = 0;
        SET p_mensaje     = CONCAT('La señal GPS es débil (± ', ROUND(p_precision), ' m; máximo ', p_precision_max,
                                   ' m). Sal a un lugar abierto y vuelve a capturar tu ubicación.');
    ELSEIF p_lat_ref IS NULL OR p_lon_ref IS NULL THEN
        SET p_resultado   = 'sin_referencia';
        SET p_registrable = 1;
        SET p_mensaje     = 'La planta no tiene coordenadas registradas: tu llegada se registrará sin validar la distancia y quedará marcada para Operaciones.';
    ELSE
        SET p_distancia = ROUND(6371000 * 2 * ASIN(SQRT(POW(SIN(RADIANS(p_lat_ref - p_latitud) / 2), 2)
                          + COS(RADIANS(p_latitud)) * COS(RADIANS(p_lat_ref)) * POW(SIN(RADIANS(p_lon_ref - p_longitud) / 2), 2))));
        IF p_distancia <= p_radio THEN
            SET p_resultado   = 'valida';
            SET p_registrable = 1;
            SET p_mensaje     = CONCAT('Te encuentras dentro del rango permitido (a ', FORMAT(p_distancia, 0), ' m de la planta).');
        ELSE
            SET p_resultado   = 'fuera_rango';
            SET p_registrable = 0;
            SET p_mensaje     = CONCAT('Estás a ', FORMAT(p_distancia, 0), ' m de la planta (máximo ', p_radio, ' m). Acércate para registrar tu llegada.');
            -- Llegada forzada aprobada por Jefatura (HU-06): se puede registrar aunque esté fuera del radio, una sola vez
            IF EXISTS (SELECT 1 FROM llegada_forzada_os f WHERE f.id_os = p_id_os AND f.estado = 'aprobada' AND f.usada_en IS NULL AND f.eliminado_en IS NULL) THEN
                SET p_resultado   = 'autorizada';
                SET p_registrable = 1;
                SET p_mensaje     = CONCAT('Jefatura autorizó tu llegada (estás a ', FORMAT(p_distancia, 0), ' m de la planta). Ya puedes confirmarla.');
            END IF;
        END IF;
    END IF;
END$$

DELIMITER ;

-- ===== procedures/SP_RegistrarLlegadaMovil.sql =====
-- ============================================================
-- SP_RegistrarLlegadaMovil  (App Mobile HU-06 — Registro de llegada y Hard Stop · escritura)
-- El técnico confirma su llegada a la planta del cliente. Se registra el GPS, su precisión y la hora (nada más).
--   - El técnico sale del token; la OS debe ser suya (principal o personal) y estar EN RUTA (traslado iniciado).
--   - La ubicación se evalúa AQUÍ (SP_EvaluarLlegadaMovil), no se confía en lo que la app mostró: fuera del radio permitido o con la
--     precisión del GPS demasiado baja NO se registra (el técnico puede volver a capturar). Sin coordenada de la planta se registra
--     sin validar la distancia y queda anotado en el evento.
--   - Escribe lo mismo que el cambio manual "llegada" del Asistente, para que la bandeja de Seguimiento Operativo lo lea igual:
--     evento_campo LLEGADA (GPS, precisión, distancia), orden_servicio.hora_llegada_real y latitud/longitud_llegada. La OS sigue "en ruta"
--     (la bandeja la muestra "en planta"); pasa a "en ejecución" al iniciar el trabajo.
--   - Fuera del radio SOLO se registra si Jefatura aprobó la llegada forzada (SP_SolicitarLlegadaForzadaMovil / SP_ResolverLlegadaForzada): la nota del evento lo dice y la aprobación se usa una vez.
--   - Una sola llegada por viaje (evento posterior a la última SALIDA_BASE): repetir el envío responde éxito con la ya registrada
--     (la app reintenta si la respuesta no le llegó).
--   - Sin conexión: la app guarda la llegada en el teléfono y la envía al recuperar la señal con la hora en que se confirmó
--     (p_capturado_utc, UTC del teléfono; solo se respeta si no es futura —tolerancia 5 min— ni tiene más de 24 h). La distancia se evalúa
--     con el GPS capturado, así que el resultado es el mismo que habría tenido en el momento.
--   - Deja el registro en auditoria_evento.
-- Resultados: 1 mensaje; 2 la llegada (id_evento, llegada_en, distancia_m, precision_m, resultado, ya_registrada, diferida).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_RegistrarLlegadaMovil;

DELIMITER $$

CREATE PROCEDURE SP_RegistrarLlegadaMovil(
    IN p_id_usuario    BIGINT,
    IN p_id_os         BIGINT,
    IN p_latitud       DECIMAL(10,7),
    IN p_longitud      DECIMAL(10,7),
    IN p_precision     DECIMAL(8,1),
    IN p_capturado_utc DATETIME
)
proc: BEGIN
    DECLARE v_estado     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_numero     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tipo_evt   INT;
    DECLARE v_salida_utc DATETIME;
    DECLARE v_id_evt     BIGINT DEFAULT NULL;
    DECLARE v_ll_utc     DATETIME;
    DECLARE v_ll_dist    INT;
    DECLARE v_ll_prec    DECIMAL(8,1);
    DECLARE v_ahora_utc  DATETIME;
    DECLARE v_capt_utc   DATETIME;
    DECLARE v_reg_utc    DATETIME;
    DECLARE v_reg_lima   DATETIME;
    DECLARE v_diferida   TINYINT DEFAULT 0;
    DECLARE v_ya         TINYINT DEFAULT 0;
    DECLARE v_resultado  VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_registrable TINYINT;
    DECLARE v_distancia  INT;
    DECLARE v_radio      INT;
    DECLARE v_pmax       INT;
    DECLARE v_lat_ref    DECIMAL(10,7);
    DECLARE v_lon_ref    DECIMAL(10,7);
    DECLARE v_mensaje    VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_notas      VARCHAR(1000) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

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
    IF p_latitud IS NULL OR p_longitud IS NULL OR p_latitud NOT BETWEEN -90 AND 90 OR p_longitud NOT BETWEEN -180 AND 180
       OR (p_latitud = 0 AND p_longitud = 0) THEN
        SELECT 1 AS IdTipoMensaje, 'La ubicación GPS no es válida: activa el GPS e inténtalo de nuevo.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF p_precision IS NULL OR p_precision < 0 OR p_precision > 5000 THEN
        SELECT 1 AS IdTipoMensaje, 'La precisión del GPS no es válida.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Hora de registro: la del servidor, salvo una llegada guardada sin conexión (la hora del teléfono, sin futuro ni más de 24 h)
    SET v_ahora_utc = UTC_TIMESTAMP();
    SET v_capt_utc  = v_ahora_utc;
    IF p_capturado_utc IS NOT NULL AND p_capturado_utc >= v_ahora_utc - INTERVAL 24 HOUR AND p_capturado_utc <= v_ahora_utc + INTERVAL 5 MINUTE THEN
        SET v_capt_utc = LEAST(p_capturado_utc, v_ahora_utc);
    END IF;
    SET v_diferida = IF(v_capt_utc < v_ahora_utc - INTERVAL 2 MINUTE, 1, 0);
    SET v_reg_utc  = IF(v_diferida = 1, v_capt_utc, v_ahora_utc);
    SET v_reg_lima = v_reg_utc - INTERVAL 5 HOUR;

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

    SELECT m.Num1 INTO v_tipo_evt
    FROM   tabla_maestra m
    WHERE  m.IdMaestro = 29 AND m.IdEmpresa = 1 AND m.String2 = 'LLEGADA' AND m.eliminado_en IS NULL
    LIMIT 1;
    IF v_tipo_evt IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'El hito de campo "Llegada a planta" no está configurado.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- ¿Ya hay llegada en este viaje? (posterior a la última salida)
    SELECT MAX(e.timestamp_utc) INTO v_salida_utc
    FROM   evento_campo e
    JOIN   tabla_maestra m ON m.IdMaestro = 29 AND m.IdEmpresa = 1 AND m.Num1 = e.id_tipo_evento AND m.String2 = 'SALIDA_BASE'
    WHERE  e.id_os = p_id_os AND e.eliminado_en IS NULL;

    SELECT e.id_evento, e.timestamp_utc, e.distancia_metros, e.precision_metros INTO v_id_evt, v_ll_utc, v_ll_dist, v_ll_prec
    FROM   evento_campo e
    WHERE  e.id_os = p_id_os AND e.id_tipo_evento = v_tipo_evt AND e.eliminado_en IS NULL
      AND  e.timestamp_utc >= IFNULL(v_salida_utc, '1000-01-01')
    ORDER BY e.timestamp_utc DESC, e.id_evento DESC LIMIT 1;

    IF v_id_evt IS NOT NULL THEN
        SET v_ya = 1;
        SET v_resultado = IF(v_ll_dist IS NULL, 'sin_referencia', 'valida');
        SET v_distancia = v_ll_dist;
    ELSE
        IF v_estado IN ('programada', 'reprogramada') THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, 'Primero inicia el traslado desde la validación antes de salir.' AS Mensaje;
            LEAVE proc;
        END IF;
        IF v_estado <> 'en_ruta' THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje,
                   IF(v_estado IN ('en_ejecucion', 'pausada'), 'El servicio ya está en ejecución.', 'La llegada solo se registra con el servicio en ruta.') AS Mensaje;
            LEAVE proc;
        END IF;

        -- Hard Stop: la ubicación se evalúa aquí
        CALL SP_EvaluarLlegadaMovil(p_id_os, p_latitud, p_longitud, p_precision, v_resultado, v_registrable, v_distancia, v_radio, v_pmax,
                                    v_lat_ref, v_lon_ref, v_mensaje);
        IF v_registrable = 0 THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, v_mensaje AS Mensaje;
            LEAVE proc;
        END IF;

        SET v_notas = LEFT(CONCAT(
            CASE v_resultado
                WHEN 'valida'     THEN CONCAT('Llegada validada por GPS a ', v_distancia, ' m de la planta (± ', ROUND(p_precision), ' m).')
                WHEN 'autorizada' THEN CONCAT('Llegada FORZADA: a ', v_distancia, ' m de la planta (fuera del radio de ', v_radio, ' m), autorizada por Jefatura.')
                ELSE 'Llegada sin referencia GPS de la planta: no se validó la distancia.' END,
            IF(v_diferida = 1, ' Registrada sin conexión y enviada después.', '')), 1000);

        INSERT INTO evento_campo (id_os, id_usuario, id_tipo_evento, latitud, longitud, precision_metros, distancia_metros, timestamp_utc, sincronizado, notas, creado_por)
        VALUES (p_id_os, p_id_usuario, v_tipo_evt, p_latitud, p_longitud, p_precision, v_distancia, v_reg_utc, 1, v_notas, p_id_usuario);
        SET v_id_evt = LAST_INSERT_ID();
        SET v_ll_utc = v_reg_utc;
        SET v_ll_prec = p_precision;

        UPDATE orden_servicio
        SET    hora_llegada_real = TIME(v_reg_lima), latitud_llegada = p_latitud, longitud_llegada = p_longitud,
               modificado_por = p_id_usuario, modificado_en = NOW()
        WHERE  id_os = p_id_os;

        -- La aprobación de la llegada forzada se usa una sola vez
        IF v_resultado = 'autorizada' THEN
            UPDATE llegada_forzada_os SET usada_en = NOW(), modificado_por = p_id_usuario
            WHERE  id_os = p_id_os AND estado = 'aprobada' AND usada_en IS NULL AND eliminado_en IS NULL;
        END IF;

        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
        VALUES ('orden_servicio', p_id_os, 'registrar_llegada', v_estado, v_estado,
                LEFT(CONCAT('Llegada a planta registrada en ', v_numero, ': ', v_notas), 900),
                p_id_usuario, NOW(),
                JSON_OBJECT('id_evento', v_id_evt, 'resultado', v_resultado, 'distancia_m', v_distancia, 'precision_m', p_precision, 'diferida', v_diferida = 1));
    END IF;

    COMMIT;

    SELECT 2 AS IdTipoMensaje, IF(v_ya = 1, 'Ya registraste tu llegada.', 'Llegada registrada. Ya puedes ver tus objetivos.') AS Mensaje;
    SELECT v_id_evt AS id_evento, CONVERT_TZ(v_ll_utc, '+00:00', '-05:00') AS llegada_en, v_distancia AS distancia_m, v_ll_prec AS precision_m,
           v_resultado AS resultado, v_ya AS ya_registrada, v_diferida AS diferida;
END$$

DELIMITER ;

-- ===== procedures/SP_ObtenerLlegadaMovil.sql =====
-- ============================================================
-- SP_ObtenerLlegadaMovil  (App Mobile HU-06 — Registro de llegada · lectura)
-- Contexto de la pantalla "Registrar llegada" de una OS del técnico que inició sesión (el id sale del token):
--   cliente, ubicación esperada (sede + coordenada de referencia + radio permitido), hora programada, salida y la llegada ya registrada.
--   Se puede registrar con la OS EN RUTA (traslado iniciado) y sin llegada en este viaje. La llegada de "este viaje" es el último evento
--   LLEGADA posterior a la última SALIDA_BASE (una OS reprogramada que sale otra vez no hereda la llegada anterior).
--   Horas en Lima (UTC-5). Las reglas de la distancia están en SP_EvaluarLlegadaMovil.
-- Resultados: 1 mensaje · 2 una fila (id_os, numero_os, estado_os, cliente, sede, direccion, hora_programada, lat_ref, lon_ref, radio_m,
--   precision_max_m, salida_en, llegada_en, llegada_lat, llegada_lon, llegada_precision, llegada_distancia, llegada_resultado,
--   puede_registrar, motivo_no_registra).
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerLlegadaMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerLlegadaMovil(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT
)
proc: BEGIN
    DECLARE v_estado     VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_salida_utc DATETIME;
    DECLARE v_radio      DECIMAL(18,6);
    DECLARE v_pmax       DECIMAL(18,6);
    DECLARE v_lat_ref    DECIMAL(10,7);
    DECLARE v_lon_ref    DECIMAL(10,7);
    DECLARE v_o_lat      DECIMAL(10,7) DEFAULT NULL;
    DECLARE v_o_lon      DECIMAL(10,7) DEFAULT NULL;
    DECLARE v_ll_utc     DATETIME;
    DECLARE v_ll_lat     DECIMAL(10,7);
    DECLARE v_ll_lon     DECIMAL(10,7);
    DECLARE v_ll_prec    DECIMAL(8,1);
    DECLARE v_ll_dist    INT;
    DECLARE v_puede      TINYINT DEFAULT 0;
    DECLARE v_f_estado   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_f_coment   VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_f_jefe     VARCHAR(210) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_f_resuelta DATETIME DEFAULT NULL;
    DECLARE v_f_usada    DATETIME DEFAULT NULL;

    SELECT os.estado INTO v_estado
    FROM   orden_servicio os
    WHERE  os.id_os = p_id_os AND os.eliminado_en IS NULL
      AND  (os.id_tecnico_principal = p_id_usuario
            OR EXISTS (SELECT 1 FROM os_personal op
                       WHERE op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL));

    IF v_estado IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio no encontrado o no asignado a tu usuario.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_LeerParametroProgramacion('LLEGADA_RADIO_METROS', 200, v_radio);
    CALL SP_LeerParametroProgramacion('LLEGADA_PRECISION_MAX_METROS', 100, v_pmax);

    SELECT MAX(e.timestamp_utc) INTO v_salida_utc
    FROM   evento_campo e
    JOIN   tabla_maestra m ON m.IdMaestro = 29 AND m.IdEmpresa = 1 AND m.Num1 = e.id_tipo_evento AND m.String2 = 'SALIDA_BASE'
    WHERE  e.id_os = p_id_os AND e.eliminado_en IS NULL;

    SELECT COALESCE(sc.latitud, s.latitud, sc2.latitud, os.latitud_llegada), COALESCE(sc.longitud, s.longitud, sc2.longitud, os.longitud_llegada) INTO v_lat_ref, v_lon_ref
    FROM   orden_servicio os
    LEFT JOIN sede_cliente sc  ON sc.id_sede = os.id_sede AND sc.SoftDelete = 0
    LEFT JOIN sede s           ON s.id_sede = os.id_sede AND s.id_cliente = os.id_cliente AND s.eliminado_en IS NULL
    LEFT JOIN requerimiento rq ON rq.id_requerimiento = os.id_requerimiento
    LEFT JOIN sede_cliente sc2 ON sc2.id_sede = rq.id_sede AND sc2.SoftDelete = 0
    WHERE  os.id_os = p_id_os;

    -- Punto de salida (HU-20): la coordenada del evento «Salida» de este viaje
    SELECT e.latitud, e.longitud INTO v_o_lat, v_o_lon
    FROM   evento_campo e
    JOIN   tabla_maestra m ON m.IdMaestro = 29 AND m.IdEmpresa = 1 AND m.Num1 = e.id_tipo_evento AND m.String2 = 'SALIDA_BASE'
    WHERE  e.id_os = p_id_os AND e.eliminado_en IS NULL AND e.latitud IS NOT NULL AND e.longitud IS NOT NULL
    ORDER BY e.timestamp_utc DESC, e.id_evento DESC LIMIT 1;

    SELECT e.timestamp_utc, e.latitud, e.longitud, e.precision_metros, e.distancia_metros INTO v_ll_utc, v_ll_lat, v_ll_lon, v_ll_prec, v_ll_dist
    FROM   evento_campo e
    JOIN   tabla_maestra m ON m.IdMaestro = 29 AND m.IdEmpresa = 1 AND m.Num1 = e.id_tipo_evento AND m.String2 = 'LLEGADA'
    WHERE  e.id_os = p_id_os AND e.eliminado_en IS NULL AND e.timestamp_utc >= IFNULL(v_salida_utc, '1000-01-01')
    ORDER BY e.timestamp_utc DESC, e.id_evento DESC LIMIT 1;

    SET v_puede = IF(v_estado = 'en_ruta' AND v_ll_utc IS NULL, 1, 0);

    -- Llegada forzada (HU-06): la última solicitud de esta OS y lo que respondió Jefatura
    SELECT s.estado, s.comentario, NULLIF(TRIM(CONCAT(IFNULL(j.nombre, ''), ' ', IFNULL(j.apellido, ''))), ''), s.resuelto_en, s.usada_en
    INTO   v_f_estado, v_f_coment, v_f_jefe, v_f_resuelta, v_f_usada
    FROM   llegada_forzada_os s
    LEFT JOIN usuario j ON j.id_usuario = s.id_jefe
    WHERE  s.id_os = p_id_os AND s.eliminado_en IS NULL
    ORDER BY s.id_solicitud DESC LIMIT 1;
    IF v_f_usada IS NOT NULL THEN SET v_f_estado = NULL; END IF;   -- ya se usó: la llegada quedó registrada

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT os.id_os,
           os.numero                                                         AS numero_os,
           os.estado                                                         AS estado_os,
           COALESCE(NULLIF(c.nombre_comercial, ''), c.razon_social)          AS cliente,
           sc.nombre                                                         AS sede,
           sc.direccion_exacta                                               AS direccion,
           TIME_FORMAT(os.hora_inicio, '%H:%i')                              AS hora_programada,
           v_lat_ref                                                         AS lat_ref,
           v_lon_ref                                                         AS lon_ref,
           v_o_lat                                                           AS origen_lat,
           v_o_lon                                                           AS origen_lon,
           ROUND(v_radio)                                                    AS radio_m,
           ROUND(v_pmax)                                                     AS precision_max_m,
           IF(v_salida_utc IS NULL, NULL, CONVERT_TZ(v_salida_utc, '+00:00', '-05:00')) AS salida_en,
           IF(v_ll_utc IS NULL, NULL, CONVERT_TZ(v_ll_utc, '+00:00', '-05:00'))         AS llegada_en,
           v_ll_lat                                                          AS llegada_lat,
           v_ll_lon                                                          AS llegada_lon,
           v_ll_prec                                                         AS llegada_precision,
           v_ll_dist                                                         AS llegada_distancia,
           IF(v_ll_utc IS NULL, NULL, IF(v_ll_dist IS NULL, 'sin_referencia', 'valida')) AS llegada_resultado,
           v_puede                                                           AS puede_registrar,
           v_f_estado                                                        AS forzada_estado,
           v_f_coment                                                        AS forzada_comentario,
           v_f_jefe                                                          AS forzada_jefe,
           v_f_resuelta                                                      AS forzada_resuelta_en,
           CASE WHEN v_puede = 1 THEN NULL
                WHEN v_ll_utc IS NOT NULL THEN 'Ya registraste tu llegada.'
                WHEN v_estado IN ('programada', 'reprogramada') THEN 'Primero inicia el traslado desde la validación antes de salir.'
                ELSE 'La llegada se registra durante el traslado (servicio en ruta).' END AS motivo_no_registra
    FROM   orden_servicio os
    LEFT JOIN cliente      c  ON c.id_cliente = os.id_cliente
    LEFT JOIN sede_cliente sc ON sc.id_sede   = os.id_sede
    WHERE  os.id_os = p_id_os;
END$$

DELIMITER ;

-- ===== procedures/SP_ObtenerMenuJefaturaMovil.sql =====
-- ============================================================
-- SP_ObtenerMenuJefaturaMovil  (App Mobile HU-28 — Menú de Jefatura)
-- Resumen del día para quien tiene el menú de Jefatura en la app. Es UN SOLO menú para todos los jefes de área:
--   · cargo "Jefe de …" (CARGO_USUARIO jefe_*: Servicio Técnico, Metrología, Operaciones…), o
--   · rol SUPERVISOR / ADMINISTRADOR con un área definida (cualquier área, incluida Servicio Técnico).
-- Los técnicos, metrólogos y usuarios comunes reciben un mensaje y la app les muestra el menú de campo.
-- El área del jefe sale de su ficha (usuario.area) o, si no la tiene, del catálogo del cargo (CARGO_USUARIO.String3): SP_ResolverJefaturaMovil.
-- El alcance de los servicios (área de la RQ) lo arma SP_ArmarAlcanceJefaturaMovil; el Panel de Campo y el Seguimiento del servicio (HU-29 / HU-30)
-- usan los mismos dos procedimientos de apoyo.
--   - Servicio Técnico y Metrología: se filtra por el área de la RQ de cada servicio (orden_servicio → expediente_digital →
--     requerimiento.id_area → area_servicio_rq.area_usuario = área del jefe).
--   - Otras áreas (Operaciones, TI, Gerencia, Comercial…): no tienen área en la RQ, así que ven el resumen de TODOS los servicios.
-- Resultados:
--   1. Mensaje
--   2. Una fila: area_codigo (el área del usuario), area_nombre, sede, y los contadores de HOY (fecha de Lima, UTC-5):
--        programados      : servicios programados para hoy (en cualquier estado activo)
--        en_ruta          : de esos, en ruta
--        en_ejecucion     : de esos, en ejecución o pausados (ya están en planta)
--        con_demora       : de esos, con una demora registrada hoy
--        aprobaciones_pendientes : solicitudes de salida que ESTE usuario puede resolver. Misma regla que
--                           SP_ObtenerAutorizacionesSalida / SP_ResolverAutorizacionSalida: encargado del área (Jefe de Servicio
--                           Técnico o Jefe de Metrología, o supervisor de Metrología) → las de su área y las que la RQ no ubica en
--                           un área; supervisión general (Jefe/Coordinador de Operaciones, supervisor de Operaciones, administrador)
--                           → todas; el resto → 0.
--      Contadores de las tarjetas (HU-28, actualización). NULL = sin dato para este usuario (no tiene el permiso, el área no aplica o
--      la fuente no está disponible): la app no pinta contador. Cada uno se calcula en su propio bloque: si una fuente falla (p. ej. falta
--      una migración) solo ese contador queda NULL y el menú sigue funcionando.
--        alertas_criticas     : notificaciones CRÍTICAS sin leer ni archivar de este usuario (notificacion.prioridad = 'critica', la
--                               clasificación del Centro de Notificaciones HU-90, migración 102_centro_notificaciones: error crítico de ensayo,
--                               servicio detenido, alertas críticas de Control de Campo). Es lo mismo que filtra "Críticas" en Notificaciones.
--        informes_por_revisar : informes de servicio técnico enviados por los técnicos y pendientes de revisión (grupos pendiente_revision y
--                               pendiente_precotizacion de SP_ArmarBaseInformes, el MISMO cálculo de la bandeja de Revisión Técnica). Solo con rt_bandeja.
--        certificados_pendientes : órdenes de metrología en estado pendiente_certificado. Solo área Metrología.
--        tickets_correlativo  : tickets de metrología solicitados (ticket_metrologia.estado = 'solicitado'), pendientes de asignar correlativo.
--                               Solo área Metrología.
--        mi_equipo_total / mi_equipo_en_labores : técnicos activos del área (misma regla de técnico que la bandeja de Programación: sin
--                               jefaturas ni asistentes) y, de ellos, los que HOY tienen una orden en ruta, en ejecución o pausada (como técnico
--                               principal o personal de apoyo). Solo Servicio Técnico y Metrología.
--        agenda_conflictos    : conflictos sobrevenidos de la Programación (HU-39, SP_ArmarConflictosProgramacion: el MISMO cálculo de la lista de
--                               conflictos). Solo con prog_bandeja; en Servicio Técnico y Metrología, los de técnicos de su área.
--        viaticos_por_revisar : gastos rendidos por los técnicos pendientes de revisión (gasto_viatico tipo gasto_solicitado, estado pendiente).
--                               Solo con prog_aprobar_reprogramacion (el Jefe de Operaciones, quien revisa los gastos: SP_RevisarGastoProgramacion).
--      Sin fuente todavía (no hay contador): Recepción en Taller (no existe el módulo ni tabla) y Panel de Campo usa en_ruta.
-- Solo lectura. No usa funciones almacenadas propias (solo el FN_PermisoAccion que ya existe).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerMenuJefaturaMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerMenuJefaturaMovil(
    IN p_id_usuario BIGINT
)
proc: BEGIN
    DECLARE v_area VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_sede VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_hoy  DATE;
    DECLARE v_aut_area    VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_aut_general TINYINT DEFAULT 0;
    DECLARE v_alertas      INT DEFAULT NULL;
    DECLARE v_informes     INT DEFAULT NULL;
    DECLARE v_certificados INT DEFAULT NULL;
    DECLARE v_tickets      INT DEFAULT NULL;
    DECLARE v_eq_total     INT DEFAULT NULL;
    DECLARE v_eq_labores   INT DEFAULT NULL;
    DECLARE v_conflictos   INT DEFAULT NULL;
    DECLARE v_gastos       INT DEFAULT NULL;
    DECLARE v_prog         INT DEFAULT 0;
    DECLARE v_ruta         INT DEFAULT 0;
    DECLARE v_ejec         INT DEFAULT 0;
    DECLARE v_dem          INT DEFAULT 0;

    -- Quién es el jefe y de qué área: la regla vive en SP_ResolverJefaturaMovil (la comparten el Panel de Campo y el Seguimiento del servicio)
    CALL SP_ResolverJefaturaMovil(p_id_usuario, v_area, v_sede, v_aut_area, v_aut_general);

    IF v_area IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Tu cargo no tiene el menú de Jefatura.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_hoy = DATE(UTC_TIMESTAMP() - INTERVAL 5 HOUR);

    -- ── Contadores de las tarjetas: cada uno en su bloque; si la fuente falla queda NULL ─────────────────────────────────
    -- Alertas de Campo: críticas sin leer (la misma clasificación que el filtro "Críticas" de Notificaciones)
    BEGIN
        DECLARE EXIT HANDLER FOR SQLEXCEPTION SET v_alertas = NULL;
        SELECT COUNT(*) INTO v_alertas
        FROM   notificacion n
        WHERE  n.id_usuario_destino = p_id_usuario AND n.eliminado_en IS NULL
          AND  n.archivado = 0 AND n.leido = 0 AND n.prioridad = 'critica';
    END;

    -- Informes pendientes de revisión: el cálculo compartido de la bandeja de Revisión Técnica
    BEGIN
        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;
            SET v_informes = NULL;
        END;
        IF FN_PermisoAccion(p_id_usuario, 'rt_bandeja') = 1 THEN
            CALL SP_ArmarBaseInformes(p_id_usuario, NULL);
            SELECT COUNT(*) INTO v_informes FROM tmp_rt_base WHERE grupo_estado IN ('pendiente_revision', 'pendiente_precotizacion');
            DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;
        END IF;
    END;

    -- Metrología: certificados pendientes y tickets de correlativo solicitados
    IF v_area = 'metrologia' THEN
        BEGIN
            DECLARE EXIT HANDLER FOR SQLEXCEPTION SET v_certificados = NULL;
            SELECT COUNT(*) INTO v_certificados FROM orden_metrologia om WHERE om.eliminado_en IS NULL AND om.estado = 'pendiente_certificado';
        END;
        BEGIN
            DECLARE EXIT HANDLER FOR SQLEXCEPTION SET v_tickets = NULL;
            SELECT COUNT(*) INTO v_tickets FROM ticket_metrologia t WHERE t.eliminado_en IS NULL AND t.estado = 'solicitado';
        END;
    END IF;

    -- Mi Equipo: técnicos del área y los que hoy están en labores (solo Servicio Técnico y Metrología)
    IF v_area IN ('servicio_tecnico', 'metrologia') THEN
        BEGIN
            DECLARE EXIT HANDLER FOR SQLEXCEPTION
            BEGIN
                SET v_eq_total = NULL;
                SET v_eq_labores = NULL;
            END;
            SELECT COUNT(*),
                   IFNULL(SUM(EXISTS (SELECT 1
                                      FROM   orden_servicio os
                                      WHERE  os.eliminado_en IS NULL AND os.fecha_ejecucion = v_hoy
                                        AND  os.estado IN ('en_ruta', 'en_ejecucion', 'pausada')
                                        AND  (os.id_tecnico_principal = u.id_usuario
                                              OR EXISTS (SELECT 1 FROM os_personal op
                                                         WHERE op.id_os = os.id_os AND op.id_usuario = u.id_usuario AND op.eliminado_en IS NULL)))), 0)
            INTO   v_eq_total, v_eq_labores
            FROM   usuario u
            WHERE  u.eliminado_en IS NULL AND u.estado = 'activo' AND u.area = v_area
              AND  (u.cargo IS NULL OR (u.cargo NOT LIKE 'jefe\_%' AND u.cargo NOT LIKE 'asistente\_%'));
        END;
    END IF;

    -- Agenda del Área: conflictos sobrevenidos de la Programación (HU-39)
    BEGIN
        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            CALL SP_LimpiarConflictosProgramacion();
            SET v_conflictos = NULL;
        END;
        IF FN_PermisoAccion(p_id_usuario, 'prog_bandeja') = 1 THEN
            CALL SP_ArmarConflictosProgramacion();
            SELECT COUNT(*) INTO v_conflictos
            FROM   tmp_cf c
            WHERE  v_area NOT IN ('servicio_tecnico', 'metrologia')
                   OR EXISTS (SELECT 1 FROM usuario t WHERE t.id_usuario = c.id_usuario AND t.area = v_area);
            CALL SP_LimpiarConflictosProgramacion();
        END IF;
    END;

    -- Viáticos y Gastos: gastos rendidos por revisar (solo quien los revisa)
    BEGIN
        DECLARE EXIT HANDLER FOR SQLEXCEPTION SET v_gastos = NULL;
        IF FN_PermisoAccion(p_id_usuario, 'prog_aprobar_reprogramacion') = 1 THEN
            SELECT COUNT(*) INTO v_gastos
            FROM   gasto_viatico g
            WHERE  g.eliminado_en IS NULL AND g.tipo = 'gasto_solicitado' AND g.estado = 'pendiente';
        END IF;
    END;

    -- Resumen del día: los servicios del alcance del jefe (SP_ArmarAlcanceJefaturaMovil: área de la RQ para ST/Metrología; las demás áreas ven todo)
    CALL SP_ArmarAlcanceJefaturaMovil(v_area, NULL);
    SELECT COUNT(*),
           IFNULL(SUM(os.estado = 'en_ruta'), 0),
           IFNULL(SUM(os.estado IN ('en_ejecucion', 'pausada')), 0)
    INTO   v_prog, v_ruta, v_ejec
    FROM   orden_servicio os
    JOIN   tmp_jf_alc a ON a.id_os = os.id_os
    WHERE  os.estado IN ('programada', 'reprogramada', 'en_ruta', 'en_ejecucion', 'pausada', 'bloqueada');
    SELECT COUNT(DISTINCT d.id_os) INTO v_dem
    FROM   demora_registro d
    JOIN   tmp_jf_alc a ON a.id_os = d.id_os
    JOIN   orden_servicio os ON os.id_os = d.id_os
    WHERE  d.eliminado_en IS NULL AND DATE(d.fecha_registro) = v_hoy
      AND  os.estado IN ('programada', 'reprogramada', 'en_ruta', 'en_ejecucion', 'pausada', 'bloqueada');
    DROP TEMPORARY TABLE IF EXISTS tmp_jf_alc;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT v_area                                                           AS area_codigo,
           (SELECT t.String1 FROM tabla_maestra t
            WHERE  t.IdMaestro = 79 AND t.IdEmpresa = 1 AND t.String2 = v_area LIMIT 1) AS area_nombre,
           v_sede                                                           AS sede,
           v_prog                                                           AS programados,
           v_ruta                                                           AS en_ruta,
           v_ejec                                                           AS en_ejecucion,
           v_dem                                                            AS con_demora,
           (SELECT COUNT(*)
            FROM   autorizacion_salida_os a
            WHERE  a.eliminado_en IS NULL AND a.estado = 'pendiente'
              AND  (v_aut_general = 1
                    OR (v_aut_area IS NOT NULL AND (a.area_destino IS NULL OR a.area_destino = v_aut_area))))
           + (SELECT COUNT(*)
              FROM   llegada_forzada_os lf
              WHERE  lf.eliminado_en IS NULL AND lf.estado = 'pendiente'
                AND  (v_aut_general = 1
                      OR (v_aut_area IS NOT NULL AND (lf.area_destino IS NULL OR lf.area_destino = v_aut_area)))) AS aprobaciones_pendientes,
           v_alertas                                                        AS alertas_criticas,
           v_informes                                                       AS informes_por_revisar,
           v_certificados                                                   AS certificados_pendientes,
           v_tickets                                                        AS tickets_correlativo,
           v_eq_total                                                       AS mi_equipo_total,
           v_eq_labores                                                     AS mi_equipo_en_labores,
           v_conflictos                                                     AS agenda_conflictos,
           v_gastos                                                         AS viaticos_por_revisar;
END$$

DELIMITER ;

-- ===== procedures/SP_ObtenerNotificacionesMovil.sql =====
-- ============================================================
-- SP_ObtenerNotificacionesMovil  (App Mobile HU-02 / HU-04 — pestaña Notificaciones)
-- Avisos del usuario que inició sesión (el id sale del token): las 60 más recientes, no eliminadas.
-- Son las mismas de la campana de la intranet (tabla notificacion), con el tipo ya clasificado para el ícono y la acción de la app.
--   tipo (según el título que dejan los demás SP):
--     autorizacion_aprobada   "Autorización de salida aprobada" (y el texto anterior "Visto bueno de salida: …")
--     autorizacion_rechazada  "Autorización de salida rechazada" (y "Salida no autorizada: …")
--     autorizacion_solicitud  "Autorización de salida · …" (le llega al jefe cuando un técnico pide su visto bueno)
--     solicitud_enviada       "Solicitud de autorización enviada" (confirmación para el técnico)
--     gasto_aprobado | gasto_observado | gasto_rechazado   gastos revisados por el Jefe de Operaciones
--     servicio                "Nueva programación: …" (se asignó un servicio)
--     demora                  "Demora en ruta" (le llega a Operaciones)
--     ensayo_critico          "Ensayo con error crítico" (HU-10: le llega al encargado del área; el técnico pidió apoyo o aceptó guardar con una lectura fuera del EMP)
--     evidencia_forzada       "Evidencia forzada" (HU-12: una foto rechazada por la IA que el técnico aceptó con un motivo)
--     correlativo_solicitado  "Solicitud de correlativo enviada" (HU-14: confirmación al técnico) · correlativo_solicitud "Solicitud de correlativo" (HU-34: le llega al Jefe de
--                             Metrología) · correlativo_asignado "Correlativo asignado" (HU-14: Metrología asignó el correlativo; abre "Mis tickets"). entidad_tipo = ticket_metrologia.
--     equipo_nuevo            "Equipo nuevo por aprobar" (HU-07: equipo NEW registrado en campo)
--     servicio_detenido       "Servicio detenido: …" (Control de Campo)
--     alerta_campo            otra alerta operativa del Control de Campo (tipo_notificacion = alerta_operativa)
--     general                 cualquier otro
--   critica / prioridad: la prioridad que ya clasifica el Centro de Notificaciones (HU-90, migración 102_centro_notificaciones: columna
--     notificacion.prioridad = critica | alta | normal). Es lo que filtra "Críticas" en la pestaña Notificaciones del jefe. No se repite la regla aquí.
--   Las archivadas en la intranet no se muestran.
--   pendientes_aprobados: solo en autorizacion_aprobada, los pendientes con los que el jefe autorizó la salida.
--   entidad_tipo / id_entidad: a qué abre la app ('orden_servicio' = el detalle del servicio).
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerNotificacionesMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerNotificacionesMovil(
    IN p_id_usuario BIGINT
)
proc: BEGIN
    IF NOT EXISTS (SELECT 1 FROM usuario WHERE id_usuario = p_id_usuario AND eliminado_en IS NULL) THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no encontrado.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT x.id_notificacion, x.tipo, x.titulo, x.cuerpo, x.entidad_tipo, x.id_entidad, x.leida, x.fecha_creacion,
           x.prioridad, IF(x.prioridad = 'critica', 1, 0) AS critica,
           CASE WHEN x.tipo = 'autorizacion_aprobada' AND x.entidad_tipo = 'orden_servicio'
                THEN (SELECT a.pendientes FROM autorizacion_salida_os a
                      WHERE  a.id_os = x.id_entidad AND a.eliminado_en IS NULL
                      ORDER BY a.id_autorizacion DESC LIMIT 1)
           END AS pendientes_aprobados
    FROM (
        SELECT n.id_notificacion,
               CASE WHEN n.titulo LIKE 'Autorización de salida aprobada%' OR n.titulo LIKE 'Visto bueno de salida%'     THEN 'autorizacion_aprobada'
                    WHEN n.titulo LIKE 'Autorización de salida rechazada%' OR n.titulo LIKE 'Salida no autorizada%'     THEN 'autorizacion_rechazada'
                    WHEN n.titulo LIKE 'Solicitud de autorización enviada%'                                             THEN 'solicitud_enviada'
                    WHEN n.titulo LIKE 'Solicitud de llegada forzada enviada%'                                          THEN 'solicitud_enviada'
                    WHEN n.titulo LIKE 'Llegada forzada aprobada%'                                                      THEN 'llegada_forzada_aprobada'
                    WHEN n.titulo LIKE 'Llegada forzada rechazada%'                                                     THEN 'llegada_forzada_rechazada'
                    WHEN n.titulo LIKE 'Llegada forzada%'                                                               THEN 'llegada_forzada_solicitud'
                    WHEN n.titulo LIKE 'Solicitud de correlativo enviada%'                                              THEN 'correlativo_solicitado'
                    WHEN n.titulo LIKE 'Solicitud de correlativo%'                                                      THEN 'correlativo_solicitud'
                    WHEN n.titulo LIKE 'Correlativo asignado%'                                                          THEN 'correlativo_asignado'
                    WHEN n.titulo LIKE 'Autorización de salida%'                                                        THEN 'autorizacion_solicitud'
                    WHEN n.titulo LIKE 'Gasto aprobado%'                                                                THEN 'gasto_aprobado'
                    WHEN n.titulo LIKE 'Gasto observado%'                                                               THEN 'gasto_observado'
                    WHEN n.titulo LIKE 'Gasto rechazado%'                                                               THEN 'gasto_rechazado'
                    WHEN n.titulo LIKE 'Nueva programación%' OR n.titulo LIKE 'Nuevo servicio%'                         THEN 'servicio'
                    WHEN n.titulo LIKE 'Demora en ruta%'                                                                THEN 'demora'
                    WHEN n.titulo LIKE 'Ensayo con error cr%'                                                           THEN 'ensayo_critico'
                    WHEN n.titulo LIKE 'Evidencia forzada%'                                                             THEN 'evidencia_forzada'
                    WHEN n.titulo LIKE 'Equipo nuevo por aprobar%'                                                      THEN 'equipo_nuevo'
                    WHEN n.titulo LIKE 'Servicio detenido:%'                                                            THEN 'servicio_detenido'
                    WHEN n.tipo_notificacion = 'alerta_operativa'                                                       THEN 'alerta_campo'
                    ELSE 'general' END AS tipo,
               n.titulo,
               n.cuerpo,
               n.entidad_tipo,
               n.id_entidad,
               n.leido                AS leida,
               n.fecha_creacion,
               n.prioridad
        FROM   notificacion n
        WHERE  n.id_usuario_destino = p_id_usuario AND n.eliminado_en IS NULL AND n.archivado = 0
        ORDER BY n.fecha_creacion DESC, n.id_notificacion DESC
        LIMIT 60
    ) x
    ORDER BY x.fecha_creacion DESC, x.id_notificacion DESC;
END$$

DELIMITER ;

