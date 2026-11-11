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
