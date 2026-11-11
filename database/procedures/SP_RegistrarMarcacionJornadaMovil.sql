-- ============================================================
-- SP_RegistrarMarcacionJornadaMovil  (App Mobile HU-20 — «Reloj marcador»: marcar un paso de la jornada · escritura)
-- Marca inicio de labores, inicio/fin de refrigerio, salida de planta o fin de labores del técnico del token.
--   · Orden estricto (SP_EstadoJornadaMovil): solo se acepta el paso siguiente; una jornada finalizada no se reabre.
--   · Hora: la del teléfono (p_marcado_utc, UTC) cuando se marcó sin conexión; se valida: no puede ser del futuro (se usa la del servidor), ni de hace más
--     de 20 h, ni anterior a la marcación previa. Sin hora = la del servidor. El día es el de Lima.
--   · GPS obligatorio (rango válido, distinto de 0,0, precisión 0 a 5000 m). Lugar = la sede de cliente más cercana a 300 m o menos (si hay).
--   · Ingreso: «a tiempo» si marcó hasta JORNADA_TOLERANCIA_MIN minutos después del inicio programado; si no, «tardanza» con los minutos.
--   · Idempotente: la misma marcación del día ya registrada (reintento de la cola sin conexión) responde éxito con repetida = 1, sin duplicar.
--   · Cada marcación deja también una posición en ubicacion_tecnico: el técnico aparece de inmediato en el mapa del Seguimiento Operativo de la intranet.
-- Auditoría: auditoria_evento (jornada_marcacion). Se bloquea al usuario para serializar sus marcaciones.
-- Resultados: 1 mensaje (1 regla de negocio · 2 éxito · 3 error) · 2 (solo éxito) marcación registrada y el estado siguiente.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_RegistrarMarcacionJornadaMovil;

DELIMITER $$

CREATE PROCEDURE SP_RegistrarMarcacionJornadaMovil(
    IN p_id_usuario   BIGINT,
    IN p_tipo         VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_latitud      DECIMAL(10,7),
    IN p_longitud     DECIMAL(10,7),
    IN p_precision    DECIMAL(8,1),
    IN p_marcado_utc  DATETIME,
    IN p_sin_conexion TINYINT
)
proc: BEGIN
    DECLARE v_ahora_utc DATETIME;
    DECLARE v_marcado   DATETIME;
    DECLARE v_fecha     DATE;
    DECLARE v_n         INT;
    DECLARE v_estado    VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_sig       VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_ultima    DATETIME;
    DECLARE v_estado2   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_sig2      VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_n2        INT;
    DECLARE v_ult2      DATETIME;
    DECLARE v_id_usr    BIGINT;
    DECLARE v_existente BIGINT DEFAULT NULL;
    DECLARE v_ini_min   DECIMAL(18,6);
    DECLARE v_tol       DECIMAL(18,6);
    DECLARE v_loc_min   INT;
    DECLARE v_dif       INT DEFAULT NULL;
    DECLARE v_punt      VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_lugar     VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_id        BIGINT;
    DECLARE v_nombre    VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_nom_sig   VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        ROLLBACK;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0
       OR NOT EXISTS (SELECT 1 FROM usuario u WHERE u.id_usuario = p_id_usuario AND u.eliminado_en IS NULL AND u.estado = 'activo') THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no válido.' AS Mensaje; LEAVE proc;
    END IF;
    IF IFNULL(p_tipo, '') NOT IN ('inicio_labores', 'inicio_refrigerio', 'fin_refrigerio', 'salida_planta', 'fin_labores') THEN
        SELECT 1 AS IdTipoMensaje, 'La marcación no es válida.' AS Mensaje; LEAVE proc;
    END IF;
    IF p_latitud IS NULL OR p_longitud IS NULL OR p_latitud NOT BETWEEN -90 AND 90 OR p_longitud NOT BETWEEN -180 AND 180
       OR (p_latitud = 0 AND p_longitud = 0) THEN
        SELECT 1 AS IdTipoMensaje, 'No se pudo tomar tu ubicación. Activa el GPS e inténtalo de nuevo.' AS Mensaje; LEAVE proc;
    END IF;
    IF p_precision IS NOT NULL AND (p_precision < 0 OR p_precision > 5000) THEN
        SELECT 1 AS IdTipoMensaje, 'La precisión de la ubicación no es válida.' AS Mensaje; LEAVE proc;
    END IF;

    SET v_nombre = CASE p_tipo WHEN 'inicio_labores' THEN 'Inicio de labores' WHEN 'inicio_refrigerio' THEN 'Inicio de refrigerio'
                               WHEN 'fin_refrigerio' THEN 'Fin de refrigerio' WHEN 'salida_planta' THEN 'Salida de planta' ELSE 'Fin de labores' END;

    -- Hora de la marcación (la del teléfono si es creíble)
    SET v_ahora_utc = UTC_TIMESTAMP();
    SET v_marcado   = v_ahora_utc;
    IF p_marcado_utc IS NOT NULL THEN
        IF p_marcado_utc < DATE_SUB(v_ahora_utc, INTERVAL 20 HOUR) THEN
            SELECT 1 AS IdTipoMensaje, 'La marcación es demasiado antigua y no se puede registrar.' AS Mensaje; LEAVE proc;
        END IF;
        IF p_marcado_utc <= DATE_ADD(v_ahora_utc, INTERVAL 2 MINUTE) THEN SET v_marcado = p_marcado_utc; END IF;
    END IF;
    SET v_fecha = DATE(CONVERT_TZ(v_marcado, '+00:00', '-05:00'));

    START TRANSACTION;
    SELECT u.id_usuario INTO v_id_usr FROM usuario u WHERE u.id_usuario = p_id_usuario FOR UPDATE;

    -- Reintento de una marcación ya registrada
    SELECT j.id_marcacion INTO v_existente FROM jornada_marcacion j WHERE j.id_usuario = p_id_usuario AND j.fecha = v_fecha AND j.tipo = p_tipo LIMIT 1;
    CALL SP_EstadoJornadaMovil(p_id_usuario, v_fecha, v_n, v_estado, v_sig, v_ultima);
    IF v_existente IS NOT NULL THEN
        ROLLBACK;
        SELECT 2 AS IdTipoMensaje, CONCAT(v_nombre, ' ya estaba registrada.') AS Mensaje;
        SELECT p_tipo AS tipo, 1 AS repetida, v_estado AS estado, v_sig AS siguiente, NULL AS hora, NULL AS lugar, NULL AS puntualidad, NULL AS minutos_diferencia;
        LEAVE proc;
    END IF;

    -- Orden estricto
    IF v_sig IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Tu jornada de hoy ya finalizó.' AS Mensaje; LEAVE proc;
    END IF;
    IF p_tipo <> v_sig THEN
        SET v_nom_sig = CASE v_sig WHEN 'inicio_labores' THEN 'Inicio de labores' WHEN 'inicio_refrigerio' THEN 'Inicio de refrigerio'
                                   WHEN 'fin_refrigerio' THEN 'Fin de refrigerio' WHEN 'salida_planta' THEN 'Salida de planta' ELSE 'Fin de labores' END;
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, CONCAT('Primero marca «', v_nom_sig, '».') AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_ultima IS NOT NULL AND v_marcado < v_ultima THEN SET v_marcado = v_ultima; END IF;

    -- Ingreso: a tiempo o tardanza
    IF p_tipo = 'inicio_labores' THEN
        CALL SP_LeerParametroProgramacion('JORNADA_INICIO_MIN',     465, v_ini_min);
        CALL SP_LeerParametroProgramacion('JORNADA_TOLERANCIA_MIN', 5,   v_tol);
        SET v_loc_min = HOUR(CONVERT_TZ(v_marcado, '+00:00', '-05:00')) * 60 + MINUTE(CONVERT_TZ(v_marcado, '+00:00', '-05:00'));
        SET v_dif   = v_loc_min - CAST(v_ini_min AS SIGNED);
        SET v_punt  = IF(v_dif <= v_tol, 'a_tiempo', 'tardanza');
        SET v_dif   = GREATEST(v_dif, 0);
    END IF;

    -- Lugar: la sede de cliente más cercana (300 m o menos)
    SELECT x.lugar INTO v_lugar
    FROM (SELECT LEFT(CONCAT(c.razon_social, IF(NULLIF(sc.nombre, '') IS NULL, '', CONCAT(' – ', sc.nombre))), 200) AS lugar,
                 6371000 * 2 * ASIN(SQRT(POW(SIN(RADIANS(s.latitud - p_latitud) / 2), 2)
                              + COS(RADIANS(p_latitud)) * COS(RADIANS(s.latitud)) * POW(SIN(RADIANS(s.longitud - p_longitud) / 2), 2))) AS d
          FROM sede s
          JOIN cliente c ON c.id_cliente = s.id_cliente
          LEFT JOIN sede_cliente sc ON sc.id_sede = s.id_sede
          WHERE s.eliminado_en IS NULL AND s.latitud IS NOT NULL AND s.longitud IS NOT NULL) x
    WHERE x.d <= 300
    ORDER BY x.d
    LIMIT 1;

    INSERT INTO jornada_marcacion (id_usuario, fecha, tipo, marcado_utc, latitud, longitud, precision_m, lugar, puntualidad, minutos_diferencia, sin_conexion)
    VALUES (p_id_usuario, v_fecha, p_tipo, v_marcado, p_latitud, p_longitud, IF(p_precision IS NULL, NULL, ROUND(p_precision)), v_lugar, v_punt, v_dif,
            IF(IFNULL(p_sin_conexion, 0) = 1, 1, 0));
    SET v_id = LAST_INSERT_ID();

    -- La posición queda en el seguimiento: el técnico se ve en el mapa de la intranet apenas marca
    INSERT INTO ubicacion_tecnico (id_usuario, id_os, latitud, longitud, precision_m, direccion, timestamp_utc)
    VALUES (p_id_usuario, NULL, p_latitud, p_longitud, IF(p_precision IS NULL, NULL, ROUND(p_precision)), v_lugar, v_marcado);

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('jornada_marcacion', v_id, CONCAT('marcar_', p_tipo), v_estado, NULL,
            LEFT(CONCAT(v_nombre, ' a las ', TIME_FORMAT(CONVERT_TZ(v_marcado, '+00:00', '-05:00'), '%H:%i'),
                        IF(v_punt = 'tardanza', CONCAT(' (tardanza de ', v_dif, ' min)'), ''), IF(IFNULL(p_sin_conexion, 0) = 1, ' · marcada sin conexión', ''), '.'), 300),
            p_id_usuario, NOW(), JSON_OBJECT('tipo', p_tipo, 'fecha', DATE_FORMAT(v_fecha, '%Y-%m-%d'), 'puntualidad', v_punt));

    COMMIT;

    CALL SP_EstadoJornadaMovil(p_id_usuario, v_fecha, v_n2, v_estado2, v_sig2, v_ult2);
    SELECT 2 AS IdTipoMensaje, CONCAT(v_nombre, ' registrado.') AS Mensaje;
    SELECT p_tipo AS tipo, 0 AS repetida, v_estado2 AS estado, v_sig2 AS siguiente,
           TIME_FORMAT(CONVERT_TZ(v_marcado, '+00:00', '-05:00'), '%H:%i:%s') AS hora, v_lugar AS lugar, v_punt AS puntualidad, v_dif AS minutos_diferencia;
END$$

DELIMITER ;
