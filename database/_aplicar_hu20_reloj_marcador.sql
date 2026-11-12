-- HU-20 Reloj marcador: aplicar en DBeaver con Alt+X (responder No al aviso Large script). Reiniciar la API después. Idempotente.
-- ============================================================
-- Migración 109 — Reloj Marcador de jornada de la app móvil (HU-20)
--   1. jornada_marcacion: las 5 marcaciones del día del técnico, en orden estricto (inicio de labores → inicio de refrigerio → fin de refrigerio →
--      salida de planta → fin de labores). Una por tipo y día (índice único): reenviar una marcación guardada sin conexión no duplica nada.
--      La hora es la del teléfono validada por el servidor (no se puede editar); guarda GPS, lugar, puntualidad (solo el ingreso) y si se marcó sin conexión.
--   2. Parámetros (PARAMETRO_PROGRAMACION): horario programado de la jornada, tolerancia del ingreso, tope de refrigerio y minutos sin movimiento para alertar.
--      El horario es general (07:45 a 17:00); si más adelante hace falta por técnico, se agrega una tabla de horarios y el SP la lee.
--   Las posiciones GPS de la jornada se guardan en ubicacion_tecnico (migración 90): el Seguimiento Operativo de la intranet ya las lee.
--   No borra ni cambia datos existentes. IDEMPOTENTE.
-- ============================================================

CREATE TABLE IF NOT EXISTS jornada_marcacion (
    id_marcacion       BIGINT        NOT NULL AUTO_INCREMENT,
    id_usuario         BIGINT        NOT NULL,
    fecha              DATE          NOT NULL,
    tipo               VARCHAR(20)   NOT NULL,
    marcado_utc        DATETIME      NOT NULL,
    latitud            DECIMAL(10,7) NULL,
    longitud           DECIMAL(10,7) NULL,
    precision_m        INT           NULL,
    lugar              VARCHAR(200)  NULL,
    puntualidad        VARCHAR(10)   NULL,
    minutos_diferencia INT           NULL,
    sin_conexion       TINYINT       NOT NULL DEFAULT 0,
    creado_en          DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id_marcacion),
    UNIQUE KEY ux_jornada_usuario_dia_tipo (id_usuario, fecha, tipo),
    KEY ix_jornada_fecha (fecha)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

SET @id_param := (SELECT MAX(IdMaestro) FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROGRAMACION');
SET @id_param := IFNULL(@id_param, (SELECT MAX(IdMaestro) + 1 FROM tabla_maestra));

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, Num2, String1, String2)
SELECT 1, @id_param, 'PARAMETRO_PROGRAMACION', x.n, x.valor, x.nombre, x.codigo
FROM (SELECT 120 AS n, 465 AS valor, 'Inicio programado de la jornada (minutos desde las 00:00; 465 = 07:45)'                      AS nombre, 'JORNADA_INICIO_MIN'       AS codigo UNION ALL
      SELECT 121,      1020,          'Fin programado de la jornada (minutos desde las 00:00; 1020 = 17:00)',                                'JORNADA_FIN_MIN'                  UNION ALL
      SELECT 122,      5,             'Minutos de tolerancia sobre el inicio programado para marcar el ingreso "a tiempo"',                  'JORNADA_TOLERANCIA_MIN'           UNION ALL
      SELECT 123,      60,            'Minutos de refrigerio permitidos',                                                                    'JORNADA_REFRIGERIO_MIN'           UNION ALL
      SELECT 124,      10,            'Minutos sin movimiento del técnico (con la jornada en curso) para alertar a Jefatura',                'SEG_SIN_MOVIMIENTO_MIN') x
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra t WHERE t.Descripcion = 'PARAMETRO_PROGRAMACION' AND t.IdEmpresa = 1 AND t.String2 = x.codigo);

-- ── Verificación (debe ser 6) ─────────────────────────────────────────────────
SELECT 'Migración 109 (debe ser 6)' AS verificacion,
       (SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'jornada_marcacion')
     + (SELECT COUNT(DISTINCT String2) FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROGRAMACION' AND IdEmpresa = 1
          AND String2 IN ('JORNADA_INICIO_MIN', 'JORNADA_FIN_MIN', 'JORNADA_TOLERANCIA_MIN', 'JORNADA_REFRIGERIO_MIN', 'SEG_SIN_MOVIMIENTO_MIN')) AS valor;

-- ============================================================
-- SP_EstadoJornadaMovil  (App Mobile HU-20 — apoyo, NO es un endpoint)
-- UNA sola regla del orden de la jornada: las marcaciones del día forman siempre un prefijo de
--   inicio_labores → inicio_refrigerio → fin_refrigerio → salida_planta → fin_labores
-- así que con la cantidad de marcaciones se sabe el estado y el único paso siguiente habilitado.
--   n = 0 sin_iniciar · 1 en_labores · 2 en_refrigerio · 3 en_labores (después del refrigerio) · 4 salio_planta · 5 finalizada
-- Solo lectura. (El Seguimiento Operativo usa esta misma tabla de estados en SP_ArmarSeguimientoOperativo.)
-- ============================================================
DROP PROCEDURE IF EXISTS SP_EstadoJornadaMovil;

DELIMITER $$

CREATE PROCEDURE SP_EstadoJornadaMovil(
    IN  p_id_usuario BIGINT,
    IN  p_fecha      DATE,
    OUT p_n          INT,
    OUT p_estado     VARCHAR(20),
    OUT p_siguiente  VARCHAR(20),
    OUT p_ultima_utc DATETIME
)
BEGIN
    SELECT COUNT(*), MAX(j.marcado_utc) INTO p_n, p_ultima_utc
    FROM   jornada_marcacion j
    WHERE  j.id_usuario = p_id_usuario AND j.fecha = p_fecha;

    SET p_estado = CASE p_n WHEN 0 THEN 'sin_iniciar' WHEN 1 THEN 'en_labores' WHEN 2 THEN 'en_refrigerio'
                            WHEN 3 THEN 'en_labores' WHEN 4 THEN 'salio_planta' ELSE 'finalizada' END;
    SET p_siguiente = CASE p_n WHEN 0 THEN 'inicio_labores' WHEN 1 THEN 'inicio_refrigerio' WHEN 2 THEN 'fin_refrigerio'
                               WHEN 3 THEN 'salida_planta' WHEN 4 THEN 'fin_labores' ELSE NULL END;
END$$

DELIMITER ;

-- ============================================================
-- SP_ObtenerJornadaMovil  (App Mobile HU-20 — pantalla «Reloj marcador» · lectura)
-- La jornada de HOY (hora de Lima) del técnico del token: estado, el único paso habilitado, el horario programado, las marcaciones hechas
-- (hora, lugar GPS, a tiempo / tardanza) y, con la jornada finalizada, el resumen (trabajado, refrigerio, ingreso).
-- Resultados: 1 mensaje (1 regla de negocio · 2 éxito · 3 error) · 2 cabecera · 3 marcaciones · 4 resumen (una fila; vacío si la jornada no terminó).
-- Las horas se devuelven en ISO 8601 UTC («…Z») para que la app las descuente con su reloj; las de pantalla ya vienen en hora de Lima («HH:mm»).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerJornadaMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerJornadaMovil(
    IN p_id_usuario BIGINT
)
proc: BEGIN
    DECLARE v_ahora_utc DATETIME;
    DECLARE v_fecha     DATE;
    DECLARE v_n         INT;
    DECLARE v_estado    VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_sig       VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_ultima    DATETIME;
    DECLARE v_ini_min   DECIMAL(18,6);
    DECLARE v_fin_min   DECIMAL(18,6);
    DECLARE v_tol       DECIMAL(18,6);
    DECLARE v_refri     DECIMAL(18,6);
    DECLARE v_t_ini     DATETIME;
    DECLARE v_t_fin     DATETIME;
    DECLARE v_r_ini     DATETIME;
    DECLARE v_r_fin     DATETIME;
    DECLARE v_punt      VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tard      INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0
       OR NOT EXISTS (SELECT 1 FROM usuario u WHERE u.id_usuario = p_id_usuario AND u.eliminado_en IS NULL AND u.estado = 'activo') THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no válido.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_ahora_utc = UTC_TIMESTAMP();
    SET v_fecha     = DATE(CONVERT_TZ(v_ahora_utc, '+00:00', '-05:00'));
    CALL SP_EstadoJornadaMovil(p_id_usuario, v_fecha, v_n, v_estado, v_sig, v_ultima);
    CALL SP_LeerParametroProgramacion('JORNADA_INICIO_MIN',      465,  v_ini_min);
    CALL SP_LeerParametroProgramacion('JORNADA_FIN_MIN',         1020, v_fin_min);
    CALL SP_LeerParametroProgramacion('JORNADA_TOLERANCIA_MIN',  5,    v_tol);
    CALL SP_LeerParametroProgramacion('JORNADA_REFRIGERIO_MIN',  60,   v_refri);

    SELECT 2 AS IdTipoMensaje, 'OK' AS Mensaje;

    -- 2 Cabecera
    SELECT DATE_FORMAT(v_fecha, '%Y-%m-%d')                              AS fecha,
           DATE_FORMAT(v_ahora_utc, '%Y-%m-%dT%H:%i:%sZ')                AS ahora_utc,
           v_estado                                                      AS estado,
           v_sig                                                         AS siguiente,
           TIME_FORMAT(SEC_TO_TIME(v_ini_min * 60), '%H:%i')             AS inicio_programado,
           TIME_FORMAT(SEC_TO_TIME(v_fin_min * 60), '%H:%i')             AS fin_programado,
           CAST(v_tol AS SIGNED)                                         AS tolerancia_min,
           CAST(v_refri AS SIGNED)                                       AS refrigerio_max_min;

    -- 3 Marcaciones del día
    SELECT j.tipo AS tipo, DATE_FORMAT(CONVERT_TZ(j.marcado_utc, '+00:00', '-05:00'), '%H:%i') AS hora,
           DATE_FORMAT(j.marcado_utc, '%Y-%m-%dT%H:%i:%sZ') AS marcado_utc, j.lugar AS lugar, j.latitud AS latitud, j.longitud AS longitud,
           j.precision_m AS precision_m, j.puntualidad AS puntualidad, j.minutos_diferencia AS minutos_diferencia, j.sin_conexion AS sin_conexion
    FROM   jornada_marcacion j
    WHERE  j.id_usuario = p_id_usuario AND j.fecha = v_fecha
    ORDER BY j.marcado_utc, j.id_marcacion;

    -- 4 Resumen de la jornada finalizada
    IF v_estado = 'finalizada' THEN
        SELECT MAX(IF(j.tipo = 'inicio_labores', j.marcado_utc, NULL)), MAX(IF(j.tipo = 'fin_labores', j.marcado_utc, NULL)),
               MAX(IF(j.tipo = 'inicio_refrigerio', j.marcado_utc, NULL)), MAX(IF(j.tipo = 'fin_refrigerio', j.marcado_utc, NULL)),
               MAX(IF(j.tipo = 'inicio_labores', j.puntualidad, NULL)), MAX(IF(j.tipo = 'inicio_labores', j.minutos_diferencia, NULL))
          INTO v_t_ini, v_t_fin, v_r_ini, v_r_fin, v_punt, v_tard
        FROM jornada_marcacion j WHERE j.id_usuario = p_id_usuario AND j.fecha = v_fecha;
        SELECT GREATEST(0, TIMESTAMPDIFF(MINUTE, v_t_ini, v_t_fin) - IFNULL(TIMESTAMPDIFF(MINUTE, v_r_ini, v_r_fin), 0)) AS trabajado_min,
               IFNULL(TIMESTAMPDIFF(MINUTE, v_r_ini, v_r_fin), 0)                                                       AS refrigerio_min,
               v_punt AS ingreso, v_tard AS minutos_tardanza;
    ELSE
        SELECT NULL AS trabajado_min, NULL AS refrigerio_min, NULL AS ingreso, NULL AS minutos_tardanza FROM DUAL WHERE 1 = 0;
    END IF;
END$$

DELIMITER ;

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

-- ============================================================
-- SP_RegistrarUbicacionJornadaMovil  (App Mobile HU-20 — posición GPS del técnico MIENTRAS LA JORNADA ESTÁ EN CURSO)
-- Igual que SP_RegistrarUbicacionMovil (HU-51) pero sin exigir un servicio en curso: basta que la jornada de hoy esté iniciada y no finalizada
-- (inicio de labores marcado, incluso en refrigerio o ya fuera de planta). Alimenta el mapa, la alerta «Sin movimiento» y «Pérdida de contacto».
-- Antirrebote: si ya hay una posición del técnico de hace menos de 10 s no se guarda otra (responde OK). Si tiene un servicio en curso, la posición
-- se guarda con ese servicio. Limpieza: máx. 500 posiciones de más de 3 días. Resultados: 1 mensaje · 2 Guardada.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_RegistrarUbicacionJornadaMovil;

DELIMITER $$

CREATE PROCEDURE SP_RegistrarUbicacionJornadaMovil(
    IN p_id_usuario BIGINT,
    IN p_latitud    DECIMAL(10,7),
    IN p_longitud   DECIMAL(10,7),
    IN p_precision  DECIMAL(8,1),
    IN p_velocidad  DECIMAL(6,1),
    IN p_altitud    DECIMAL(8,1)
)
proc: BEGIN
    DECLARE v_n         INT;
    DECLARE v_estado    VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_sig       VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_ult       DATETIME;
    DECLARE v_ultima    DATETIME;
    DECLARE v_os        BIGINT DEFAULT NULL;
    DECLARE v_guardada  TINYINT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no válido.' AS Mensaje; LEAVE proc;
    END IF;
    IF p_latitud IS NULL OR p_longitud IS NULL OR p_latitud NOT BETWEEN -90 AND 90 OR p_longitud NOT BETWEEN -180 AND 180
       OR (p_latitud = 0 AND p_longitud = 0) THEN
        SELECT 1 AS IdTipoMensaje, 'La ubicación no es válida.' AS Mensaje; LEAVE proc;
    END IF;
    IF p_precision IS NOT NULL AND (p_precision < 0 OR p_precision > 5000) THEN
        SELECT 1 AS IdTipoMensaje, 'La precisión de la ubicación no es válida.' AS Mensaje; LEAVE proc;
    END IF;

    CALL SP_EstadoJornadaMovil(p_id_usuario, DATE(CONVERT_TZ(UTC_TIMESTAMP(), '+00:00', '-05:00')), v_n, v_estado, v_sig, v_ult);
    IF v_n < 1 OR v_n > 4 THEN
        SELECT 1 AS IdTipoMensaje, 'La ubicación solo se registra con la jornada en curso.' AS Mensaje; LEAVE proc;
    END IF;

    SELECT MAX(timestamp_utc) INTO v_ultima FROM ubicacion_tecnico WHERE id_usuario = p_id_usuario;
    IF v_ultima IS NULL OR v_ultima < DATE_SUB(UTC_TIMESTAMP(), INTERVAL 10 SECOND) THEN
        SELECT os.id_os INTO v_os
        FROM orden_servicio os
        WHERE os.eliminado_en IS NULL AND os.estado IN ('en_ruta', 'en_ejecucion', 'pausada')
          AND (os.id_tecnico_principal = p_id_usuario
               OR EXISTS (SELECT 1 FROM os_personal op WHERE op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL))
        ORDER BY os.id_os DESC LIMIT 1;

        INSERT INTO ubicacion_tecnico (id_usuario, id_os, latitud, longitud, precision_m, velocidad_kmh, altitud_m, timestamp_utc)
        VALUES (p_id_usuario, v_os, p_latitud, p_longitud, IF(p_precision IS NULL, NULL, ROUND(p_precision)),
                IF(p_velocidad BETWEEN 0 AND 400, p_velocidad, NULL), IF(p_altitud BETWEEN -500 AND 9000, p_altitud, NULL), UTC_TIMESTAMP());
        SET v_guardada = 1;
        DELETE FROM ubicacion_tecnico WHERE id_usuario = p_id_usuario AND timestamp_utc < DATE_SUB(UTC_TIMESTAMP(), INTERVAL 3 DAY) LIMIT 500;
    END IF;

    SELECT 2 AS IdTipoMensaje, IF(v_guardada = 1, 'Ubicación registrada.', 'Ubicación reciente ya registrada.') AS Mensaje;
    SELECT v_guardada AS Guardada;
END$$

DELIMITER ;

-- HU-51 (Sprint 5) Arma el estado operativo del DÍA para la bandeja de seguimiento. Ayuda interna: NO devuelve resultados. Solo LEE datos.
-- Los SPs SP_Obtener*Seguimiento la llaman y al terminar ejecutan SP_LimpiarSeguimientoOperativo. "Hoy" y las horas son de Lima (UTC-05:00).
-- Universo: programaciones CONFIRMADAS (Programado) con fecha de ejecución de hoy, cuya OS/OM no esté anulada. La bandeja no escribe nada:
-- lee evento_campo (salida, llegada, inicio, cierre), orden_servicio, os_equipo, demora_registro, incidencia_operativa y ubicacion_tecnico.
-- Estado del servicio (estado_seg), por prioridad:
--   finalizado      OS finalizada
--   con_incidente   incidencia abierta de nivel Crítico o con impacto "detiene"
--   con_demora      demora registrada hoy, incidencia abierta no crítica, o servicio en pausa
--   en_ejecucion    OS en ejecución
--   en_planta       OS en ruta con llegada registrada (aún sin iniciar el trabajo)
--   en_ruta         OS en ruta, sin llegada
--   sin_salir       programada o reprogramada: el técnico aún no marcó "Salida"
-- Estado del técnico = el del servicio más urgente de su día (el finalizado solo si todos lo están).
-- Alertas automáticas (se calculan al consultar; umbrales en PARAMETRO_PROGRAMACION, migración 90):
--   perdida_contacto (crítica) · gps_parado (advertencia) · sin_movimiento (advertencia, HU-20) · sin_ingreso_post_llegada (advertencia) · sin_iniciar_servicio (advertencia)
--   · proximidad (info) · incidente (crítica)
-- Tablas temporales (MySQL no permite abrir dos veces la misma temporal en una consulta):
--   tmp_sg_cfg (1 fila: hoy, ahora y umbrales) · tmp_sg_os (un servicio por fila) · tmp_sg_ev (eventos de campo del día por OS)
--   tmp_sg_ut (técnico x servicio) · tmp_sg_tec (un técnico por fila) · tmp_sg_pos (última posición GPS por técnico)
--   tmp_sg_alerta · tmp_sg_hito · tmp_sg_inc (demoras e incidencias unificadas; `fase` = momento de la demora de la app: llegada = en ruta, ingreso = ingreso a planta)
-- Demoras de la app (demora_registro, HU-05): las de llegada corren la hora esperada de llegada (hito) y las de ingreso, la hora esperada de inicio.
-- Jornada (HU-20): cada técnico trae su estado del Reloj marcador (jornada: en_labores | en_refrigerio | salio_planta | finalizada; NULL si no inició) y una frase de lo que
-- está haciendo (actividad). «Sin movimiento»: jornada en curso (no en refrigerio ni finalizada), con señal, GPS en el mismo punto SEG_SIN_MOVIMIENTO_MIN o más.
-- Requiere las migraciones 85 a 90 y 109.
DROP PROCEDURE IF EXISTS SP_ArmarSeguimientoOperativo;

DELIMITER $$

CREATE PROCEDURE SP_ArmarSeguimientoOperativo()
BEGIN
    DECLARE v_ahora_utc DATETIME;
    DECLARE v_ahora     DATETIME;
    DECLARE v_hoy       DATE;
    DECLARE v_ini_utc   DATETIME;
    DECLARE v_refresco  DECIMAL(18,6);
    DECLARE v_perdida   DECIMAL(18,6);
    DECLARE v_parado    DECIMAL(18,6);
    DECLARE v_sin_ing   DECIMAL(18,6);
    DECLARE v_sin_ini   DECIMAL(18,6);
    DECLARE v_prox      DECIMAL(18,6);
    DECLARE v_anticip   DECIMAL(18,6);
    DECLARE v_nueva     DECIMAL(18,6);
    DECLARE v_ventana   DECIMAL(18,6);
    DECLARE v_retorno   DECIMAL(18,6);
    DECLARE v_sin_mov   DECIMAL(18,6);

    CALL SP_LimpiarSeguimientoOperativo();

    SET v_ahora_utc = UTC_TIMESTAMP();
    SET v_ahora     = CONVERT_TZ(v_ahora_utc, '+00:00', '-05:00');
    SET v_hoy       = DATE(v_ahora);
    SET v_ini_utc   = CONVERT_TZ(TIMESTAMP(v_hoy), '-05:00', '+00:00');

    CALL SP_LeerParametroProgramacion('SEG_REFRESCO_SEGUNDOS',      30,  v_refresco);
    CALL SP_LeerParametroProgramacion('SEG_PERDIDA_CONTACTO_MIN',   10,  v_perdida);
    CALL SP_LeerParametroProgramacion('SEG_GPS_PARADO_MIN',         10,  v_parado);
    CALL SP_LeerParametroProgramacion('SEG_SIN_INGRESO_MIN',        15,  v_sin_ing);
    CALL SP_LeerParametroProgramacion('SEG_SIN_INICIAR_MIN',        15,  v_sin_ini);
    CALL SP_LeerParametroProgramacion('SEG_PROXIMIDAD_METROS',      300, v_prox);
    CALL SP_LeerParametroProgramacion('SEG_ANTICIPACION_SALIDA_MIN', 60, v_anticip);
    CALL SP_LeerParametroProgramacion('SEG_ALERTA_NUEVA_MIN',       15,  v_nueva);
    CALL SP_LeerParametroProgramacion('SEG_HITOS_VENTANA_MIN',      60,  v_ventana);
    CALL SP_LeerParametroProgramacion('SEG_RETORNO_MIN',            30,  v_retorno);
    CALL SP_LeerParametroProgramacion('SEG_SIN_MOVIMIENTO_MIN',     10,  v_sin_mov);

    CREATE TEMPORARY TABLE tmp_sg_cfg (
        hoy DATE, ahora DATETIME, ahora_utc DATETIME, ini_utc DATETIME,
        refresco INT, perdida INT, parado INT, sin_ingreso INT, sin_iniciar INT, prox INT, anticip INT, nueva INT, ventana INT, retorno INT
    );
    INSERT INTO tmp_sg_cfg VALUES (v_hoy, v_ahora, v_ahora_utc, v_ini_utc, v_refresco, v_perdida, v_parado, v_sin_ing, v_sin_ini, v_prox,
                                   v_anticip, v_nueva, v_ventana, v_retorno);

    -- ── Servicios del día ─────────────────────────────────────────────────────────────────
    CREATE TEMPORARY TABLE tmp_sg_os (
        id_os BIGINT NOT NULL, id_programacion BIGINT, numero VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        tipo VARCHAR(5) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, id_cliente BIGINT,
        razon_social VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, ruc VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        id_sede BIGINT, sede_nombre VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        sede_direccion VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, lat_sede DECIMAL(10,7), lon_sede DECIMAL(10,7),
        id_tecnico BIGINT, tecnico VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, nombre_pila VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        zona VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        hora_inicio TIME, hora_fin_est TIME, os_estado VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        propuesta VARCHAR(60) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        n_equipos INT DEFAULT 0, n_ejecutados INT DEFAULT 0,
        salida_utc DATETIME, llegada_dt DATETIME, inicio_dt DATETIME, fin_dt DATETIME,
        crit TINYINT DEFAULT 0, n_demoras INT DEFAULT 0, min_dem_lleg INT DEFAULT 0, ing_eta DATETIME,
        estado_seg VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, fase VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, prio INT DEFAULT 9, dist_m INT,
        PRIMARY KEY (id_os)
    );

    INSERT INTO tmp_sg_os (id_os, id_programacion, numero, tipo, id_cliente, razon_social, ruc, id_sede, sede_nombre, sede_direccion, lat_sede, lon_sede,
                           id_tecnico, tecnico, nombre_pila, zona, hora_inicio, hora_fin_est, os_estado, propuesta, n_equipos, n_ejecutados,
                           llegada_dt, fin_dt)
    SELECT os.id_os, p.id_programacion, os.numero, os.tipo, os.id_cliente, c.razon_social, c.ruc, os.id_sede, sc.nombre, sc.direccion_exacta, COALESCE(s.latitud, os.latitud_llegada), COALESCE(s.longitud, os.longitud_llegada),
           p.id_tecnico_principal, TRIM(CONCAT(u.nombre, ' ', u.apellido)), u.nombre, COALESCE(zn.String1, u.sede_operativa),
           p.hora_inicio, p.hora_fin_estimada, os.estado,
           IF(pr.id_propuesta IS NULL, NULL, pr.numero),
           (SELECT COUNT(*) FROM os_equipo e WHERE e.id_os = os.id_os AND e.eliminado_en IS NULL),
           (SELECT COUNT(*) FROM os_equipo e WHERE e.id_os = os.id_os AND e.eliminado_en IS NULL AND e.estado_ejecucion = 'ejecutado'),
           IF(os.hora_llegada_real IS NULL, NULL, TIMESTAMP(v_hoy, os.hora_llegada_real)),
           IF(os.hora_fin_real IS NULL, NULL, TIMESTAMP(v_hoy, os.hora_fin_real))
    FROM programacion p
    JOIN orden_servicio os ON os.id_os = p.id_os AND os.eliminado_en IS NULL
    JOIN cliente c ON c.id_cliente = os.id_cliente
    LEFT JOIN sede_cliente sc ON sc.id_sede = os.id_sede
    LEFT JOIN sede s ON s.id_sede = os.id_sede AND s.id_cliente = os.id_cliente AND s.eliminado_en IS NULL
    LEFT JOIN usuario u ON u.id_usuario = p.id_tecnico_principal
    LEFT JOIN tabla_maestra zn ON zn.IdMaestro = 69 AND zn.IdEmpresa = 1 AND zn.String2 = u.sede_operativa
    LEFT JOIN propuesta_comercial pr ON pr.id_propuesta = os.id_propuesta
    WHERE p.eliminado_en IS NULL AND p.estado = 'confirmada' AND p.fecha_ejecucion = v_hoy
      AND os.estado NOT IN ('anulada', 'borrador', 'emitida');

    -- Eventos de campo de hoy (una fila por OS)
    CREATE TEMPORARY TABLE tmp_sg_ev (id_os BIGINT NOT NULL, salida_utc DATETIME, llegada_utc DATETIME, inicio_utc DATETIME, cierre_utc DATETIME, PRIMARY KEY (id_os));
    INSERT INTO tmp_sg_ev
    SELECT e.id_os,
           MIN(IF(t.String2 = 'SALIDA_BASE',    e.timestamp_utc, NULL)), MIN(IF(t.String2 = 'LLEGADA', e.timestamp_utc, NULL)),
           MIN(IF(t.String2 = 'INICIO_TRABAJO', e.timestamp_utc, NULL)), MAX(IF(t.String2 = 'CIERRE',  e.timestamp_utc, NULL))
    FROM evento_campo e
    JOIN tabla_maestra t ON t.Descripcion = 'TIPO_EVENTO_CAMPO' AND t.IdEmpresa = 1 AND t.Num1 = e.id_tipo_evento
    JOIN tmp_sg_os o ON o.id_os = e.id_os
    WHERE e.eliminado_en IS NULL AND e.timestamp_utc >= v_ini_utc
    GROUP BY e.id_os;

    UPDATE tmp_sg_os o
    JOIN tmp_sg_ev v ON v.id_os = o.id_os
    SET o.salida_utc = v.salida_utc,
        o.llegada_dt = COALESCE(o.llegada_dt, CONVERT_TZ(v.llegada_utc, '+00:00', '-05:00')),
        o.inicio_dt  = CONVERT_TZ(v.inicio_utc, '+00:00', '-05:00'),
        o.fin_dt     = COALESCE(o.fin_dt, CONVERT_TZ(v.cierre_utc, '+00:00', '-05:00'));

    -- Incidencias y demoras de hoy
    UPDATE tmp_sg_os o
    SET o.crit = IF(EXISTS (SELECT 1 FROM incidencia_operativa i
                            LEFT JOIN tabla_maestra nv ON nv.Descripcion = 'NIVEL_ALERTA' AND nv.IdEmpresa = 1 AND nv.Num1 = i.id_nivel_alerta
                            WHERE i.id_os = o.id_os AND i.eliminado_en IS NULL AND i.estado <> 'resuelta' AND i.fecha_registro >= v_hoy
                              AND (i.impacto = 'detiene' OR nv.String3 = 'CRITICO'))
                    OR EXISTS (SELECT 1 FROM registro_asistente ra
                               WHERE ra.id_os = o.id_os AND ra.modo = 'demora' AND ra.impacto = 'detiene' AND ra.fecha_utc >= v_ini_utc), 1, 0),
        o.n_demoras = (SELECT COUNT(*) FROM demora_registro d WHERE d.id_os = o.id_os AND d.eliminado_en IS NULL AND d.fecha_registro >= v_hoy)
                    + (SELECT COUNT(*) FROM incidencia_operativa i WHERE i.id_os = o.id_os AND i.eliminado_en IS NULL AND i.estado <> 'resuelta'
                         AND i.fecha_registro >= v_hoy)
                    + (SELECT COUNT(*) FROM registro_asistente ra WHERE ra.id_os = o.id_os AND ra.modo = 'demora' AND ra.fecha_utc >= v_ini_utc);

    -- Demoras de la app de hoy: minutos acumulados en ruta y hora de inicio recalculada tras una demora de ingreso a planta
    UPDATE tmp_sg_os o
    SET o.min_dem_lleg = IFNULL((SELECT SUM(d.duracion_minutos) FROM demora_registro d
                                 WHERE d.id_os = o.id_os AND d.tipo = 'llegada' AND d.eliminado_en IS NULL AND d.fecha_registro >= v_hoy), 0),
        o.ing_eta      = (SELECT MAX(d.eta_recalculada) FROM demora_registro d
                          WHERE d.id_os = o.id_os AND d.tipo = 'ingreso' AND d.eliminado_en IS NULL AND d.fecha_registro >= v_hoy);

    UPDATE tmp_sg_os o
    SET o.estado_seg = CASE
            WHEN o.os_estado = 'finalizada'                             THEN 'finalizado'
            WHEN o.crit = 1                                             THEN 'con_incidente'
            WHEN o.n_demoras > 0 OR o.os_estado = 'pausada'             THEN 'con_demora'
            WHEN o.os_estado = 'en_ejecucion'                           THEN 'en_ejecucion'
            WHEN o.os_estado = 'en_ruta' AND o.llegada_dt IS NOT NULL   THEN 'en_planta'
            WHEN o.os_estado = 'en_ruta'                                THEN 'en_ruta'
            ELSE 'sin_salir' END;
    -- Fase del servicio según la OS (sin tener en cuenta demoras ni incidentes): se usa para alertas e hitos
    UPDATE tmp_sg_os o
    SET o.fase = CASE WHEN o.os_estado = 'finalizada' THEN 'finalizado' WHEN o.os_estado IN ('en_ejecucion', 'pausada') THEN 'en_ejecucion'
                      WHEN o.os_estado = 'en_ruta' AND o.llegada_dt IS NOT NULL THEN 'en_planta' WHEN o.os_estado = 'en_ruta' THEN 'en_ruta'
                      ELSE 'sin_salir' END;
    UPDATE tmp_sg_os o
    SET o.prio = CASE o.estado_seg WHEN 'con_incidente' THEN 1 WHEN 'con_demora' THEN 2 WHEN 'en_ejecucion' THEN 3 WHEN 'en_planta' THEN 4
                                   WHEN 'en_ruta' THEN 5 WHEN 'sin_salir' THEN 6 ELSE 7 END;

    -- ── Técnicos del día (principal y apoyo) ──────────────────────────────────────────────
    CREATE TEMPORARY TABLE tmp_sg_ut (id_usuario BIGINT NOT NULL, id_os BIGINT NOT NULL, rol VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, PRIMARY KEY (id_usuario, id_os));
    INSERT IGNORE INTO tmp_sg_ut
    SELECT pt.id_usuario, o.id_os, pt.rol
    FROM programacion_tecnico pt JOIN tmp_sg_os o ON o.id_programacion = pt.id_programacion
    WHERE pt.eliminado_en IS NULL;
    INSERT IGNORE INTO tmp_sg_ut SELECT o.id_tecnico, o.id_os, 'principal' FROM tmp_sg_os o WHERE o.id_tecnico IS NOT NULL;

    -- Copia (id_os, nombre) para la búsqueda por técnico: MySQL no abre dos veces la misma temporal en una consulta
    CREATE TEMPORARY TABLE tmp_sg_utn (id_os BIGINT NOT NULL, id_usuario BIGINT NOT NULL, nombre VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, KEY ix_utn (id_os));
    INSERT INTO tmp_sg_utn SELECT ut.id_os, ut.id_usuario, TRIM(CONCAT(u.nombre, ' ', u.apellido)) FROM tmp_sg_ut ut JOIN usuario u ON u.id_usuario = ut.id_usuario;

    CREATE TEMPORARY TABLE tmp_sg_tec (
        id_usuario BIGINT NOT NULL, nombre VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, nombre_pila VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        iniciales VARCHAR(4) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, cargo VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        zona VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, ssoma VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        prio INT, estado_seg VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, id_os_actual BIGINT,
        n_servicios INT, n_completados INT, n_en_curso INT,
        salida_utc DATETIME, salida_prog TIME, dist_m INT,
        jornada VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, jornada_desde DATETIME, actividad VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        PRIMARY KEY (id_usuario)
    );
    INSERT INTO tmp_sg_tec (id_usuario, nombre, nombre_pila, iniciales, cargo, zona, prio, n_servicios, n_completados, n_en_curso, salida_utc, salida_prog)
    SELECT ut.id_usuario, TRIM(CONCAT(u.nombre, ' ', u.apellido)), u.nombre, UPPER(CONCAT(LEFT(u.nombre, 1), LEFT(u.apellido, 1))),
           COALESCE(cg.String1, u.cargo), COALESCE(zn.String1, u.sede_operativa),
           MIN(o.prio), COUNT(*), SUM(o.estado_seg = 'finalizado'),
           SUM(o.estado_seg IN ('en_ruta', 'en_planta', 'en_ejecucion', 'con_demora', 'con_incidente')),
           MIN(o.salida_utc), SEC_TO_TIME(GREATEST(0, TIME_TO_SEC(MIN(o.hora_inicio)) - v_anticip * 60))
    FROM tmp_sg_ut ut
    JOIN tmp_sg_os o ON o.id_os = ut.id_os
    JOIN usuario u ON u.id_usuario = ut.id_usuario
    LEFT JOIN tabla_maestra cg ON cg.IdMaestro = 80 AND cg.IdEmpresa = 1 AND cg.String2 = u.cargo
    LEFT JOIN tabla_maestra zn ON zn.IdMaestro = 69 AND zn.IdEmpresa = 1 AND zn.String2 = u.sede_operativa
    GROUP BY ut.id_usuario, u.nombre, u.apellido, cg.String1, u.cargo, zn.String1, u.sede_operativa;

    UPDATE tmp_sg_tec t
    SET t.estado_seg = CASE t.prio WHEN 1 THEN 'con_incidente' WHEN 2 THEN 'con_demora' WHEN 3 THEN 'en_ejecucion' WHEN 4 THEN 'en_planta'
                                   WHEN 5 THEN 'en_ruta' WHEN 6 THEN 'sin_salir' ELSE 'finalizado' END,
        t.id_os_actual = (SELECT o.id_os FROM tmp_sg_ut ut JOIN tmp_sg_os o ON o.id_os = ut.id_os
                          WHERE ut.id_usuario = t.id_usuario AND o.prio = t.prio ORDER BY o.hora_inicio, o.id_os LIMIT 1);
    UPDATE tmp_sg_tec t
    SET t.ssoma = (SELECT pt.estado_ssoma FROM programacion_tecnico pt JOIN tmp_sg_os o2 ON o2.id_programacion = pt.id_programacion
                   WHERE pt.id_usuario = t.id_usuario AND pt.eliminado_en IS NULL
                   ORDER BY FIELD(pt.estado_ssoma, 'bloqueado', 'incompleto', 'por_vencer', 'conforme') LIMIT 1);

    -- ── Última posición GPS de hoy (ubicacion_tecnico; si no hay, la última de evento_campo con coordenadas) ─────────────
    CREATE TEMPORARY TABLE tmp_sg_pos (
        id_usuario BIGINT NOT NULL, lat DECIMAL(10,7), lon DECIMAL(10,7), direccion VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        ts_utc DATETIME, parado_desde DATETIME, PRIMARY KEY (id_usuario)
    );
    INSERT IGNORE INTO tmp_sg_pos (id_usuario, lat, lon, direccion, ts_utc)
    SELECT x.id_usuario, x.latitud, x.longitud, x.direccion, x.timestamp_utc
    FROM ubicacion_tecnico x
    WHERE x.id_usuario IN (SELECT t.id_usuario FROM tmp_sg_tec t)
      AND x.id_ubicacion = (SELECT MAX(y.id_ubicacion) FROM ubicacion_tecnico y
                            WHERE y.id_usuario = x.id_usuario
                              AND y.timestamp_utc = (SELECT MAX(z.timestamp_utc) FROM ubicacion_tecnico z
                                                     WHERE z.id_usuario = x.id_usuario AND z.timestamp_utc >= v_ini_utc AND z.timestamp_utc <= v_ahora_utc));
    INSERT IGNORE INTO tmp_sg_pos (id_usuario, lat, lon, direccion, ts_utc)
    SELECT e.id_usuario, e.latitud, e.longitud, NULL, e.timestamp_utc
    FROM evento_campo e
    WHERE e.eliminado_en IS NULL AND e.latitud IS NOT NULL AND e.longitud IS NOT NULL AND e.timestamp_utc >= v_ini_utc AND e.timestamp_utc <= v_ahora_utc
      AND e.id_usuario IN (SELECT t.id_usuario FROM tmp_sg_tec t)
      AND e.id_evento = (SELECT MAX(w.id_evento) FROM evento_campo w WHERE w.id_usuario = e.id_usuario AND w.latitud IS NOT NULL AND w.timestamp_utc >= v_ini_utc
                         AND w.timestamp_utc <= v_ahora_utc AND w.eliminado_en IS NULL);

    -- Desde cuándo está el GPS en el mismo punto (~33 m): primera posición posterior a la última que quedó lejos
    UPDATE tmp_sg_pos p
    SET p.parado_desde = (SELECT MIN(a.timestamp_utc) FROM ubicacion_tecnico a
                          WHERE a.id_usuario = p.id_usuario AND a.timestamp_utc >= v_ini_utc AND a.timestamp_utc <= p.ts_utc
                            AND a.timestamp_utc > COALESCE((SELECT MAX(b.timestamp_utc) FROM ubicacion_tecnico b
                                                            WHERE b.id_usuario = p.id_usuario AND b.timestamp_utc >= v_ini_utc AND b.timestamp_utc <= p.ts_utc
                                                              AND (ABS(b.latitud - p.lat) > 0.0003 OR ABS(b.longitud - p.lon) > 0.0003)), '1000-01-01'));

    -- Jornada del técnico (HU-20): estado del Reloj marcador de hoy (la misma tabla de estados de SP_EstadoJornadaMovil) y lo que está haciendo
    UPDATE tmp_sg_tec t
    SET t.jornada = (SELECT CASE COUNT(*) WHEN 0 THEN NULL WHEN 1 THEN 'en_labores' WHEN 2 THEN 'en_refrigerio' WHEN 3 THEN 'en_labores'
                                          WHEN 4 THEN 'salio_planta' ELSE 'finalizada' END
                     FROM jornada_marcacion j WHERE j.id_usuario = t.id_usuario AND j.fecha = v_hoy),
        t.jornada_desde = (SELECT MAX(j.marcado_utc) FROM jornada_marcacion j WHERE j.id_usuario = t.id_usuario AND j.fecha = v_hoy);
    UPDATE tmp_sg_tec t
    LEFT JOIN tmp_sg_os o ON o.id_os = t.id_os_actual
    SET t.actividad = LEFT(CASE t.jornada
            WHEN 'en_refrigerio' THEN CONCAT('En refrigerio · hace ', TIMESTAMPDIFF(MINUTE, t.jornada_desde, v_ahora_utc), ' min')
            WHEN 'salio_planta'  THEN CONCAT('Salió de planta · hace ', TIMESTAMPDIFF(MINUTE, t.jornada_desde, v_ahora_utc), ' min')
            WHEN 'finalizada'    THEN CONCAT('Jornada finalizada · ', TIME_FORMAT(CONVERT_TZ(t.jornada_desde, '+00:00', '-05:00'), '%H:%i'))
            ELSE CASE o.fase WHEN 'en_ruta'      THEN CONCAT('En labores · en ruta a ', o.razon_social)
                             WHEN 'en_planta'    THEN CONCAT('En labores · en planta de ', o.razon_social)
                             WHEN 'en_ejecucion' THEN CONCAT('En labores · ejecutando servicio en ', o.razon_social)
                             WHEN 'finalizado'   THEN 'En labores · servicio finalizado'
                             ELSE 'En labores' END END, 150)
    WHERE t.jornada IS NOT NULL;

    -- Distancia (m) al cliente: técnico principal de cada servicio y técnico (servicio actual)
    UPDATE tmp_sg_os o
    JOIN tmp_sg_pos p ON p.id_usuario = o.id_tecnico
    SET o.dist_m = IF(o.lat_sede IS NULL OR o.lon_sede IS NULL, NULL,
        ROUND(6371000 * 2 * ASIN(SQRT(POW(SIN(RADIANS(o.lat_sede - p.lat) / 2), 2)
                       + COS(RADIANS(p.lat)) * COS(RADIANS(o.lat_sede)) * POW(SIN(RADIANS(o.lon_sede - p.lon) / 2), 2)))));
    UPDATE tmp_sg_tec t
    JOIN tmp_sg_os o ON o.id_os = t.id_os_actual
    JOIN tmp_sg_pos p ON p.id_usuario = t.id_usuario
    SET t.dist_m = IF(o.lat_sede IS NULL OR o.lon_sede IS NULL, NULL,
        ROUND(6371000 * 2 * ASIN(SQRT(POW(SIN(RADIANS(o.lat_sede - p.lat) / 2), 2)
                       + COS(RADIANS(p.lat)) * COS(RADIANS(o.lat_sede)) * POW(SIN(RADIANS(o.lon_sede - p.lon) / 2), 2)))));

    -- ── Alertas automáticas ───────────────────────────────────────────────────────────────
    CREATE TEMPORARY TABLE tmp_sg_alerta (
        clave VARCHAR(60) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, tipo VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        severidad VARCHAR(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, titulo VARCHAR(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        detalle VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, minutos INT, id_usuario BIGINT,
        tecnico VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, id_os BIGINT, numero VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        PRIMARY KEY (clave)
    );

    -- Pérdida de contacto: servicio en curso y sin señal (o sin ninguna posición desde la salida) por más del umbral
    INSERT INTO tmp_sg_alerta
    SELECT CONCAT('perdida_contacto:', t.id_usuario, ':', o.id_os), 'perdida_contacto', 'critica', 'Pérdida de contacto',
           CONCAT(t.nombre, ' · ', o.numero), TIMESTAMPDIFF(MINUTE, COALESCE(p.ts_utc, t.salida_utc), v_ahora_utc), t.id_usuario, t.nombre, o.id_os, o.numero
    FROM tmp_sg_tec t
    JOIN tmp_sg_os o ON o.id_os = t.id_os_actual
    LEFT JOIN tmp_sg_pos p ON p.id_usuario = t.id_usuario
    WHERE t.estado_seg IN ('en_ruta', 'en_planta', 'en_ejecucion', 'con_demora', 'con_incidente')
      AND COALESCE(p.ts_utc, t.salida_utc) IS NOT NULL
      AND TIMESTAMPDIFF(MINUTE, COALESCE(p.ts_utc, t.salida_utc), v_ahora_utc) > v_perdida;

    -- GPS parado: en ruta, con señal reciente, en el mismo punto por el umbral o más
    INSERT INTO tmp_sg_alerta
    SELECT CONCAT('gps_parado:', t.id_usuario, ':', o.id_os), 'gps_parado', 'advertencia', 'GPS parado',
           CONCAT(t.nombre, ' · ', o.numero), TIMESTAMPDIFF(MINUTE, p.parado_desde, v_ahora_utc), t.id_usuario, t.nombre, o.id_os, o.numero
    FROM tmp_sg_tec t
    JOIN tmp_sg_os o ON o.id_os = t.id_os_actual
    JOIN tmp_sg_pos p ON p.id_usuario = t.id_usuario
    WHERE o.fase = 'en_ruta' AND p.parado_desde IS NOT NULL
      AND TIMESTAMPDIFF(MINUTE, p.ts_utc, v_ahora_utc) <= v_perdida
      AND TIMESTAMPDIFF(MINUTE, p.parado_desde, p.ts_utc) >= v_parado;

    -- Sin movimiento (HU-20): jornada en curso (no en refrigerio ni finalizada), con señal reciente y el GPS en el mismo punto por el umbral o más.
    -- En ruta lo cubre «GPS parado»; con el servicio ya finalizado no se alerta. Se asocia al servicio del día del técnico (la notificación lo exige).
    INSERT INTO tmp_sg_alerta
    SELECT CONCAT('sin_movimiento:', t.id_usuario, ':', o.id_os), 'sin_movimiento', 'advertencia', 'Sin movimiento',
           CONCAT(t.nombre, ' · ', o.numero), TIMESTAMPDIFF(MINUTE, p.parado_desde, v_ahora_utc), t.id_usuario, t.nombre, o.id_os, o.numero
    FROM tmp_sg_tec t
    JOIN tmp_sg_os o ON o.id_os = t.id_os_actual
    JOIN tmp_sg_pos p ON p.id_usuario = t.id_usuario
    WHERE t.jornada IN ('en_labores', 'salio_planta') AND o.fase NOT IN ('en_ruta', 'finalizado') AND p.parado_desde IS NOT NULL
      AND TIMESTAMPDIFF(MINUTE, p.ts_utc, v_ahora_utc) <= v_perdida
      AND TIMESTAMPDIFF(MINUTE, p.parado_desde, p.ts_utc) >= v_sin_mov;

    -- Sin ingreso post-llegada: llegó a planta y no inicia el trabajo
    INSERT INTO tmp_sg_alerta
    SELECT CONCAT('sin_ingreso:', t.id_usuario, ':', o.id_os), 'sin_ingreso_post_llegada', 'advertencia', 'Sin ingreso post-llegada',
           CONCAT(t.nombre, ' · ', o.numero), TIMESTAMPDIFF(MINUTE, o.llegada_dt, v_ahora), t.id_usuario, t.nombre, o.id_os, o.numero
    FROM tmp_sg_tec t
    JOIN tmp_sg_os o ON o.id_os = t.id_os_actual
    WHERE o.fase = 'en_planta' AND o.llegada_dt IS NOT NULL AND TIMESTAMPDIFF(MINUTE, o.llegada_dt, v_ahora) >= v_sin_ing;

    -- Sin iniciar servicio: pasó la hora de salida programada (más la tolerancia) y no marcó "Salida"
    INSERT INTO tmp_sg_alerta
    SELECT CONCAT('sin_iniciar:', t.id_usuario, ':', o.id_os), 'sin_iniciar_servicio', 'advertencia', 'Sin iniciar servicio',
           CONCAT(t.nombre, ' · ', o.numero),
           TIMESTAMPDIFF(MINUTE, TIMESTAMP(v_hoy, SEC_TO_TIME(GREATEST(0, TIME_TO_SEC(o.hora_inicio) - v_anticip * 60))), v_ahora),
           t.id_usuario, t.nombre, o.id_os, o.numero
    FROM tmp_sg_tec t
    JOIN tmp_sg_os o ON o.id_os = t.id_os_actual
    WHERE o.fase = 'sin_salir' AND o.hora_inicio IS NOT NULL
      AND TIMESTAMPDIFF(MINUTE, TIMESTAMP(v_hoy, SEC_TO_TIME(GREATEST(0, TIME_TO_SEC(o.hora_inicio) - v_anticip * 60))), v_ahora) >= v_sin_ini;

    -- Proximidad: en ruta, con señal reciente y a menos de N metros del cliente
    INSERT INTO tmp_sg_alerta
    SELECT CONCAT('proximidad:', t.id_usuario, ':', o.id_os), 'proximidad', 'info', CONCAT('Proximidad (a ', CAST(v_prox AS UNSIGNED), 'm)'),
           CONCAT(t.nombre, ' · ', o.numero), TIMESTAMPDIFF(MINUTE, p.ts_utc, v_ahora_utc), t.id_usuario, t.nombre, o.id_os, o.numero
    FROM tmp_sg_tec t
    JOIN tmp_sg_os o ON o.id_os = t.id_os_actual
    JOIN tmp_sg_pos p ON p.id_usuario = t.id_usuario
    WHERE o.fase = 'en_ruta' AND t.dist_m IS NOT NULL AND t.dist_m <= v_prox AND TIMESTAMPDIFF(MINUTE, p.ts_utc, v_ahora_utc) <= v_perdida;

    -- Incidente crítico abierto (o que detiene el servicio)
    INSERT INTO tmp_sg_alerta
    SELECT CONCAT('incidente:', i.id_incidencia), 'incidente', 'critica', 'Incidente crítico',
           CONCAT(TRIM(CONCAT(u.nombre, ' ', u.apellido)), ' · ', o.numero),
           GREATEST(0, TIMESTAMPDIFF(MINUTE, i.fecha_registro, v_ahora)), i.id_usuario, TRIM(CONCAT(u.nombre, ' ', u.apellido)), o.id_os, o.numero
    FROM incidencia_operativa i
    JOIN tmp_sg_os o ON o.id_os = i.id_os
    JOIN usuario u ON u.id_usuario = i.id_usuario
    LEFT JOIN tabla_maestra nv ON nv.Descripcion = 'NIVEL_ALERTA' AND nv.IdEmpresa = 1 AND nv.Num1 = i.id_nivel_alerta
    WHERE i.eliminado_en IS NULL AND i.estado <> 'resuelta' AND i.fecha_registro >= v_hoy AND o.estado_seg <> 'finalizado'
      AND (i.impacto = 'detiene' OR nv.String3 = 'CRITICO');

    -- ── Próximos hitos esperados ──────────────────────────────────────────────────────────
    CREATE TEMPORARY TABLE tmp_sg_hito (
        id_os BIGINT, numero VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, tipo VARCHAR(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        esperado DATETIME, texto VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, detalle VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        id_tecnico BIGINT, PRIMARY KEY (id_os)
    );
    INSERT INTO tmp_sg_hito
    SELECT o.id_os, o.numero,
           CASE o.fase WHEN 'sin_salir' THEN 'salida' WHEN 'en_ruta' THEN 'llegada' WHEN 'en_planta' THEN 'inicio'
                             WHEN 'finalizado' THEN 'retorno' ELSE 'termino' END,
           CASE o.fase
               WHEN 'sin_salir'  THEN TIMESTAMP(v_hoy, SEC_TO_TIME(GREATEST(0, TIME_TO_SEC(o.hora_inicio) - v_anticip * 60)))
               WHEN 'en_ruta'    THEN DATE_ADD(TIMESTAMP(v_hoy, o.hora_inicio), INTERVAL o.min_dem_lleg MINUTE)
               WHEN 'en_planta'  THEN GREATEST(TIMESTAMP(v_hoy, o.hora_inicio), o.llegada_dt, COALESCE(o.ing_eta, o.llegada_dt))
               WHEN 'finalizado' THEN DATE_ADD(COALESCE(o.fin_dt, TIMESTAMP(v_hoy, o.hora_fin_est)), INTERVAL v_retorno MINUTE)
               ELSE TIMESTAMP(v_hoy, COALESCE(o.hora_fin_est, o.hora_inicio)) END,
           CASE o.fase
               WHEN 'sin_salir'  THEN CONCAT(o.nombre_pila, ' debería salir de base hacia ', o.razon_social)
               WHEN 'en_ruta'    THEN CONCAT(o.nombre_pila, ' debería llegar a ', o.razon_social)
               WHEN 'en_planta'  THEN CONCAT(o.nombre_pila, ' debería iniciar el servicio en ', o.razon_social)
               WHEN 'finalizado' THEN CONCAT(o.nombre_pila, ' debería iniciar el retorno a Total Weight')
               ELSE CONCAT(o.nombre_pila, ' debería terminar el servicio en ', o.razon_social) END,
           CONCAT(CASE o.fase
                      WHEN 'sin_salir'  THEN 'Sin salir aún'
                      WHEN 'en_ruta'    THEN CONCAT('En ruta', IF(o.dist_m IS NULL, '', CONCAT(' · a ', FORMAT(o.dist_m / 1000, 1), ' km')),
                                                   IF(o.min_dem_lleg > 0, CONCAT(' · con demora (+', o.min_dem_lleg, ' min)'), ''))
                      WHEN 'en_planta'  THEN CONCAT('En planta', IF(o.llegada_dt IS NULL, '', CONCAT(' · llegó hace ', TIMESTAMPDIFF(MINUTE, o.llegada_dt, v_ahora), ' min')),
                                                   IF(o.ing_eta IS NULL, '', ' · con demora en el ingreso'))
                      WHEN 'finalizado' THEN CONCAT('Finalizó servicio', IF(o.fin_dt IS NULL, '', CONCAT(' hace ', TIMESTAMPDIFF(MINUTE, o.fin_dt, v_ahora), ' min')))
                                            ELSE 'En ejecución' END, ' · ', o.numero),
           o.id_tecnico
    FROM tmp_sg_os o
    WHERE o.hora_inicio IS NOT NULL;

    -- ── Demoras e incidencias del día (unificadas) ────────────────────────────────────────
    CREATE TEMPORARY TABLE tmp_sg_inc (
        clave VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, fecha DATETIME, id_usuario BIGINT,
        tecnico VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, iniciales VARCHAR(4) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        id_os BIGINT, numero VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, cliente VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        tipo_codigo VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, tipo VARCHAR(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        descripcion VARCHAR(400) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, duracion_min INT, impacto VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        origen VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, fase VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, PRIMARY KEY (clave)
    );
    INSERT INTO tmp_sg_inc
    SELECT CONCAT('d', d.id_demora), d.fecha_registro, d.id_usuario, TRIM(CONCAT(u.nombre, ' ', u.apellido)), UPPER(CONCAT(LEFT(u.nombre, 1), LEFT(u.apellido, 1))),
           d.id_os, os.numero, c.razon_social, COALESCE(m.String2, 'OTRO'), COALESCE(m.String1, 'Demora'), LEFT(IFNULL(d.descripcion, ''), 400),
           d.duracion_minutos, d.impacto, IF(d.creado_por IS NULL OR d.creado_por = d.id_usuario, 'tecnico', 'asistente'), d.tipo
    FROM demora_registro d
    JOIN orden_servicio os ON os.id_os = d.id_os
    JOIN cliente c ON c.id_cliente = os.id_cliente
    JOIN usuario u ON u.id_usuario = d.id_usuario
    LEFT JOIN tabla_maestra m ON m.Descripcion = 'MOTIVO_DEMORA_RUTA' AND m.IdEmpresa = 1 AND m.Num1 = d.id_motivo
    WHERE d.eliminado_en IS NULL AND d.fecha_registro >= v_hoy AND d.fecha_registro < DATE_ADD(v_hoy, INTERVAL 1 DAY);
    INSERT INTO tmp_sg_inc
    SELECT CONCAT('i', i.id_incidencia), i.fecha_registro, i.id_usuario, TRIM(CONCAT(u.nombre, ' ', u.apellido)), UPPER(CONCAT(LEFT(u.nombre, 1), LEFT(u.apellido, 1))),
           i.id_os, os.numero, c.razon_social, COALESCE(m.String2, 'OTRO'), COALESCE(m.String1, 'Incidencia'), LEFT(IFNULL(i.descripcion, ''), 400),
           i.duracion_estimada_min, IF(nv.String3 = 'CRITICO', 'detiene', i.impacto), IF(i.creado_por IS NULL OR i.creado_por = i.id_usuario, 'tecnico', 'asistente'), NULL
    FROM incidencia_operativa i
    JOIN orden_servicio os ON os.id_os = i.id_os
    JOIN cliente c ON c.id_cliente = os.id_cliente
    JOIN usuario u ON u.id_usuario = i.id_usuario
    LEFT JOIN tabla_maestra m ON m.Descripcion = 'TIPO_INCIDENCIA_OPERATIVA' AND m.IdEmpresa = 1 AND m.Num1 = i.id_tipo
    LEFT JOIN tabla_maestra nv ON nv.Descripcion = 'NIVEL_ALERTA' AND nv.IdEmpresa = 1 AND nv.Num1 = i.id_nivel_alerta
    WHERE i.eliminado_en IS NULL AND i.fecha_registro >= v_hoy AND i.fecha_registro < DATE_ADD(v_hoy, INTERVAL 1 DAY);
    -- HU-53: demoras/incidentes registrados por el Asistente desde la intranet (clave 'a<id>')
    INSERT INTO tmp_sg_inc
    SELECT CONCAT('a', ra.id_registro), CONVERT_TZ(ra.fecha_utc, '+00:00', '-05:00'), COALESCE(ra.id_tecnico, ra.id_usuario),
           TRIM(CONCAT(ut.nombre, ' ', ut.apellido)), UPPER(CONCAT(LEFT(ut.nombre, 1), LEFT(ut.apellido, 1))),
           ra.id_os, os.numero, c.razon_social, COALESCE(m.String2, 'OTROS'), COALESCE(m.String1, 'Demora'), LEFT(IFNULL(ra.descripcion, ''), 400),
           ra.duracion_min, ra.impacto, 'asistente', NULL
    FROM registro_asistente ra
    JOIN orden_servicio os ON os.id_os = ra.id_os
    JOIN cliente c ON c.id_cliente = os.id_cliente
    JOIN usuario ut ON ut.id_usuario = COALESCE(ra.id_tecnico, ra.id_usuario)
    LEFT JOIN tabla_maestra m ON m.Descripcion = 'TIPO_DEMORA_INCIDENTE' AND m.IdEmpresa = 1 AND m.Num1 = ra.id_tipo
    WHERE ra.modo = 'demora' AND ra.fecha_utc >= v_ini_utc AND ra.fecha_utc < DATE_ADD(v_ini_utc, INTERVAL 1 DAY);
END$$

DELIMITER ;

-- HU-51 (Sprint 5) Bandeja de Seguimiento Operativo: KPIs superiores, pestaña 1 Vista Principal (mapa operativo, alertas críticas, próximos hitos) y contadores de las pestañas.
-- Acceso: seg_bandeja (observacional: solo lectura; la bandeja no cambia datos). Los KPIs y contadores del día NO dependen de los filtros;
-- el mapa y las alertas sí respetan los filtros globales. "Hoy" es la fecha de Lima.
-- Resultados: 1 mensaje, 2 KPIs y contadores, 3 pines del mapa, 4 alertas críticas (más recientes), 5 totales de alertas, 6 próximos hitos, 7 resumen de hitos.
DROP PROCEDURE IF EXISTS SP_ObtenerResumenSeguimiento;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerResumenSeguimiento(
    IN p_id_usuario BIGINT,
    IN p_id_tecnico BIGINT,
    IN p_id_cliente BIGINT,
    IN p_estado     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_zona       VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_busqueda   VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_prog, v_ruta, v_planta, v_ejec, v_dem, v_fin, v_sinsalir, v_filtrados, v_tecs, v_incs INT DEFAULT 0;
    DECLARE v_estados VARCHAR(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT ',sin_salir,en_ruta,en_planta,en_ejecucion,con_demora,con_incidente,finalizado,';
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            @err_msg  = MESSAGE_TEXT,
            @err_code = MYSQL_ERRNO;
        CALL SP_LimpiarSeguimientoOperativo();
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF FN_PermisoAccion(p_id_usuario, 'seg_bandeja') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver la bandeja de seguimiento operativo.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF (p_id_tecnico IS NOT NULL AND p_id_tecnico <= 0) OR (p_id_cliente IS NOT NULL AND p_id_cliente <= 0) THEN
        SELECT 1 AS IdTipoMensaje, 'El técnico o el cliente del filtro no es válido.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF NULLIF(p_estado, '') IS NOT NULL AND LOCATE(CONCAT(',', p_estado, ','), v_estados) = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El estado del servicio no es válido.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF CHAR_LENGTH(IFNULL(p_zona, '')) > 100 OR CHAR_LENGTH(IFNULL(p_busqueda, '')) > 100 THEN
        SELECT 1 AS IdTipoMensaje, 'La zona o la búsqueda superan los 100 caracteres.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_ArmarSeguimientoOperativo();
    CALL SP_FiltrarSeguimientoOperativo(p_id_tecnico, p_id_cliente, NULLIF(p_estado, ''), NULLIF(p_zona, ''), NULLIF(TRIM(p_busqueda), ''));

    SELECT 2 AS IdTipoMensaje, 'OK' AS Mensaje;

    -- 2 KPIs del día (sin filtros) y contadores de pestañas (con filtros)
    SELECT COUNT(*), IFNULL(SUM(estado_seg = 'en_planta'), 0), IFNULL(SUM(estado_seg = 'en_ejecucion'), 0),
           IFNULL(SUM(estado_seg IN ('con_demora', 'con_incidente')), 0), IFNULL(SUM(estado_seg = 'finalizado'), 0), IFNULL(SUM(estado_seg = 'sin_salir'), 0)
      INTO v_prog, v_planta, v_ejec, v_dem, v_fin, v_sinsalir FROM tmp_sg_os;
    SELECT IFNULL(SUM(estado_seg = 'en_ruta'), 0), COUNT(*) INTO v_ruta, v_tecs FROM tmp_sg_tec;
    SELECT COUNT(*) INTO v_filtrados FROM tmp_sg_f;
    SELECT COUNT(*) INTO v_incs FROM tmp_sg_inc;
    SELECT v_prog AS Programados, v_ruta AS TecnicosEnRuta, v_planta AS EnPlanta, v_ejec AS EnEjecucion, v_dem AS ConDemoraIncidente, v_fin AS Finalizados,
           v_sinsalir AS SinSalir, v_filtrados AS ServiciosFiltrados, v_tecs AS TecnicosActivos, v_incs AS IncidenciasDelDia,
           DATE_FORMAT(c.ahora, '%H:%i') AS Actualizado, c.refresco AS RefrescoSegundos
    FROM tmp_sg_cfg c;

    -- 3 Pines del mapa: un pin por técnico con servicios en el filtro; el color lo da el estado. Jornada y Actividad (HU-20): lo que hace el técnico (refrigerio, salida de planta…)
    CREATE TEMPORARY TABLE tmp_sg_tf (id_usuario BIGINT NOT NULL, PRIMARY KEY (id_usuario));
    INSERT INTO tmp_sg_tf SELECT DISTINCT ut.id_usuario FROM tmp_sg_ut ut JOIN tmp_sg_f f ON f.id_os = ut.id_os;
    SELECT t.id_usuario AS IdUsuario, t.nombre AS Tecnico, t.iniciales AS Iniciales, t.estado_seg AS Estado, p.lat AS Latitud, p.lon AS Longitud,
           COALESCE(p.direccion, '') AS Direccion, IF(p.ts_utc IS NULL, NULL, TIMESTAMPDIFF(MINUTE, p.ts_utc, c.ahora_utc)) AS MinutosUbicacion,
           t.id_os_actual AS IdOs, o.numero AS NumeroOs, o.razon_social AS Cliente, t.jornada AS Jornada, t.actividad AS Actividad
    FROM tmp_sg_tec t
    JOIN tmp_sg_tf tf ON tf.id_usuario = t.id_usuario
    LEFT JOIN tmp_sg_pos p ON p.id_usuario = t.id_usuario
    LEFT JOIN tmp_sg_os o ON o.id_os = t.id_os_actual
    JOIN tmp_sg_cfg c
    ORDER BY t.nombre;

    -- 4 Alertas críticas: las más recientes del día (menos minutos = más reciente), críticas primero
    SELECT a.clave AS Clave, a.tipo AS Tipo, a.severidad AS Severidad, a.titulo AS Titulo, a.detalle AS Detalle, a.minutos AS Minutos,
           IF(a.minutos <= c.nueva, 1, 0) AS Nueva, a.id_usuario AS IdUsuario, a.tecnico AS Tecnico, a.id_os AS IdOs, a.numero AS NumeroOs
    FROM tmp_sg_alerta a JOIN tmp_sg_f f ON f.id_os = a.id_os JOIN tmp_sg_cfg c
    ORDER BY FIELD(a.severidad, 'critica', 'advertencia', 'info'), a.minutos, a.clave
    LIMIT 10;
    -- 5 Totales
    SELECT COUNT(*) AS Total, IFNULL(SUM(a.minutos <= c.nueva), 0) AS Nuevas, IFNULL(SUM(a.severidad = 'critica'), 0) AS Criticas
    FROM tmp_sg_alerta a JOIN tmp_sg_f f ON f.id_os = a.id_os JOIN tmp_sg_cfg c;

    -- 6 Próximos hitos (ventana configurable; los vencidos sin ocurrir se muestran primero como atrasados)
    SELECT h.id_os AS IdOs, h.numero AS NumeroOs, h.tipo AS Tipo, DATE_FORMAT(h.esperado, '%H:%i') AS Hora, h.texto AS Texto, h.detalle AS Detalle,
           IF(h.esperado < c.ahora, 1, 0) AS Atrasado, h.id_tecnico AS IdTecnico
    FROM tmp_sg_hito h JOIN tmp_sg_f f ON f.id_os = h.id_os JOIN tmp_sg_cfg c
    WHERE NOT (h.tipo = 'retorno' AND h.esperado <= c.ahora) AND h.esperado <= DATE_ADD(c.ahora, INTERVAL c.ventana MINUTE)
    ORDER BY h.esperado, h.id_os
    LIMIT 6;
    -- 7 Resumen: "Todos los hitos del día ya ocurrieron" cuando no queda ninguno pendiente
    SELECT IF(COUNT(*) = 0, 1, 0) AS TodosOcurrieron, COUNT(*) AS Pendientes
    FROM tmp_sg_hito h JOIN tmp_sg_cfg c WHERE NOT (h.tipo = 'retorno' AND h.esperado <= c.ahora);

    CALL SP_LimpiarSeguimientoOperativo();
END$$

DELIMITER ;

-- HU-51 (Sprint 5) Pestaña 3 "Técnicos Activos": una tarjeta por técnico con servicios hoy (estado, SSOMA, salida real vs programada, última ubicación y servicios del día).
-- El filtro "Estado" es el del TÉCNICO (el de su servicio más urgente). "Agrupar por zona" lo resuelve la pantalla con el campo Zona.
-- Resultados: 1 mensaje, 2 resumen, 3 tarjetas, 4 servicios de cada técnico.
DROP PROCEDURE IF EXISTS SP_ObtenerTecnicosSeguimiento;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerTecnicosSeguimiento(
    IN p_id_usuario BIGINT,
    IN p_id_tecnico BIGINT,
    IN p_id_cliente BIGINT,
    IN p_estado     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_zona       VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_busqueda   VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_estados VARCHAR(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT ',sin_salir,en_ruta,en_planta,en_ejecucion,con_demora,con_incidente,finalizado,';
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            @err_msg  = MESSAGE_TEXT,
            @err_code = MYSQL_ERRNO;
        CALL SP_LimpiarSeguimientoOperativo();
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF FN_PermisoAccion(p_id_usuario, 'seg_bandeja') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver la bandeja de seguimiento operativo.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF (p_id_tecnico IS NOT NULL AND p_id_tecnico <= 0) OR (p_id_cliente IS NOT NULL AND p_id_cliente <= 0) THEN
        SELECT 1 AS IdTipoMensaje, 'El técnico o el cliente del filtro no es válido.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF NULLIF(p_estado, '') IS NOT NULL AND LOCATE(CONCAT(',', p_estado, ','), v_estados) = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El estado del servicio no es válido.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF CHAR_LENGTH(IFNULL(p_zona, '')) > 100 OR CHAR_LENGTH(IFNULL(p_busqueda, '')) > 100 THEN
        SELECT 1 AS IdTipoMensaje, 'La zona o la búsqueda superan los 100 caracteres.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_ArmarSeguimientoOperativo();
    CALL SP_FiltrarSeguimientoOperativo(p_id_tecnico, p_id_cliente, NULL, NULLIF(p_zona, ''), NULLIF(TRIM(p_busqueda), ''));

    CREATE TEMPORARY TABLE tmp_sg_tf (id_usuario BIGINT NOT NULL, PRIMARY KEY (id_usuario));
    INSERT INTO tmp_sg_tf
    SELECT DISTINCT ut.id_usuario FROM tmp_sg_ut ut JOIN tmp_sg_f f ON f.id_os = ut.id_os
    WHERE p_id_tecnico IS NULL OR ut.id_usuario = p_id_tecnico;
    IF NULLIF(p_estado, '') IS NOT NULL THEN
        DELETE tf FROM tmp_sg_tf tf JOIN tmp_sg_tec t ON t.id_usuario = tf.id_usuario WHERE t.estado_seg <> p_estado;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'OK' AS Mensaje;
    SELECT (SELECT COUNT(*) FROM tmp_sg_tf) AS Total,
           (SELECT COUNT(*) FROM tmp_sg_tec WHERE estado_seg = 'sin_salir') AS AdicionalesSinIniciar,
           DATE_FORMAT(c.ahora, '%H:%i') AS Actualizado
    FROM tmp_sg_cfg c;

    SELECT t.id_usuario AS IdUsuario, t.nombre AS Tecnico, t.iniciales AS Iniciales, t.cargo AS Cargo, t.zona AS Zona, t.estado_seg AS Estado,
           t.ssoma AS Ssoma, t.n_servicios AS Servicios, t.n_completados AS Completados, t.n_en_curso AS EnCurso,
           DATE_FORMAT(CONVERT_TZ(t.salida_utc, '+00:00', '-05:00'), '%H:%i') AS SalidaReal, DATE_FORMAT(t.salida_prog, '%H:%i') AS SalidaProgramada,
           IF(t.salida_utc IS NULL, NULL,
              TIMESTAMPDIFF(MINUTE, TIMESTAMP(c.hoy, t.salida_prog), CONVERT_TZ(t.salida_utc, '+00:00', '-05:00'))) AS DiferenciaSalidaMin,
           COALESCE(NULLIF(p.direccion, ''), IF(p.lat IS NULL, NULL, CONCAT(FORMAT(p.lat, 5), ', ', FORMAT(p.lon, 5)))) AS UltimaUbicacion,
           IF(p.ts_utc IS NULL, NULL, TIMESTAMPDIFF(MINUTE, p.ts_utc, c.ahora_utc)) AS MinutosUbicacion,
           t.jornada AS Jornada, t.actividad AS Actividad
    FROM tmp_sg_tec t
    JOIN tmp_sg_tf tf ON tf.id_usuario = t.id_usuario
    LEFT JOIN tmp_sg_pos p ON p.id_usuario = t.id_usuario
    JOIN tmp_sg_cfg c
    ORDER BY t.zona, t.nombre;

    SELECT ut.id_usuario AS IdUsuario, o.id_os AS IdOs, o.numero AS Numero, o.razon_social AS Cliente, o.estado_seg AS Estado,
           DATE_FORMAT(o.hora_inicio, '%H:%i') AS HoraInicio, DATE_FORMAT(o.hora_fin_est, '%H:%i') AS HoraFin, ut.rol AS Rol,
           o.n_equipos AS Equipos, o.n_ejecutados AS Ejecutados
    FROM tmp_sg_ut ut
    JOIN tmp_sg_tf tf ON tf.id_usuario = ut.id_usuario
    JOIN tmp_sg_os o ON o.id_os = ut.id_os
    ORDER BY ut.id_usuario, o.hora_inicio, o.id_os;

    CALL SP_LimpiarSeguimientoOperativo();
END$$

DELIMITER ;

-- ============================================================
-- SP_GenerarAlertasOperativas  (HU-90 Centro de Notificaciones — alertas del Módulo 11 Control de Campo)
-- Lo ejecuta el worker de la API (AlertasOperativasWorker) cada minuto. Proceso del sistema: no valida permisos de quien llama.
-- Las alertas automáticas del Módulo 11 solo se calculaban al abrir la bandeja de seguimiento; este SP las guarda como notificación
-- para que lleguen a la campana. Usa EXACTAMENTE el mismo cálculo y los mismos umbrales (SP_ArmarSeguimientoOperativo, migración 90):
--   perdida_contacto (crítica) · gps_parado (advertencia) · sin_movimiento (advertencia, HU-20) · sin_ingreso_post_llegada (advertencia) · sin_iniciar_servicio (advertencia)
--   · proximidad (info) · incidente crítico (crítica)
-- Destinatarios: usuarios activos con el permiso seg_bandeja (los que ven la bandeja de seguimiento).
-- Sin duplicados: clave_alerta = clave de la alerta + fecha de Lima → una sola notificación por alerta, técnico, servicio y día.
-- Varias instancias de la API: GET_LOCK evita que dos corran a la vez (la otra sale sin hacer nada).
-- Se guarda con modulo_origen = control_campo, tipo_origen = alerta_operativa y la prioridad según la severidad.
-- Resultados: 1 mensaje · 2 generadas (notificaciones insertadas) y alertas (alertas activas en este momento).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_GenerarAlertasOperativas;

DELIMITER $$

CREATE PROCEDURE SP_GenerarAlertasOperativas()
proc: BEGIN
    DECLARE v_lock       INT DEFAULT 0;
    DECLARE v_hoy        DATE;
    DECLARE v_prox       INT DEFAULT 300;
    DECLARE v_generadas  INT DEFAULT 0;
    DECLARE v_alertas    INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_alerta_dest;
        CALL SP_LimpiarSeguimientoOperativo();
        DO RELEASE_LOCK('tw_alertas_operativas');
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SET v_lock = GET_LOCK('tw_alertas_operativas', 0);
    IF IFNULL(v_lock, 0) <> 1 THEN
        SELECT 2 AS IdTipoMensaje, 'Otra instancia está generando las alertas operativas.' AS Mensaje;
        SELECT 0 AS generadas, 0 AS alertas;
        LEAVE proc;
    END IF;

    CALL SP_ArmarSeguimientoOperativo();

    SELECT hoy, prox INTO v_hoy, v_prox FROM tmp_sg_cfg LIMIT 1;
    SELECT COUNT(*) INTO v_alertas FROM tmp_sg_alerta;

    IF v_alertas > 0 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_alerta_dest;
        CREATE TEMPORARY TABLE tmp_alerta_dest (id_usuario BIGINT NOT NULL, PRIMARY KEY (id_usuario));

        INSERT INTO tmp_alerta_dest (id_usuario)
        SELECT u.id_usuario
        FROM   usuario u
        WHERE  u.eliminado_en IS NULL AND u.estado = 'activo'
          AND  FN_PermisoAccion(u.id_usuario, 'seg_bandeja') = 1;

        INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por,
                                  modulo_origen, tipo_origen, prioridad_origen, clave_alerta)
        SELECT d.id_usuario, 5,
               LEFT(CONCAT('Técnico ', IFNULL(a.tecnico, ''), ' — ', a.titulo), 150),
               LEFT(CONCAT(
                   CASE a.tipo
                       WHEN 'gps_parado'               THEN CONCAT('Sin movimiento registrado en los últimos ', IFNULL(a.minutos, 0), ' min')
                       WHEN 'sin_movimiento'           THEN CONCAT('Sin movimiento desde hace ', IFNULL(a.minutos, 0), ' min con la jornada en curso. Comunícate con el técnico para saber qué sucede')
                       WHEN 'perdida_contacto'         THEN CONCAT('Sin señal GPS desde hace ', IFNULL(a.minutos, 0), ' min')
                       WHEN 'sin_ingreso_post_llegada' THEN CONCAT('Llegó a planta hace ', IFNULL(a.minutos, 0), ' min y aún no inicia el trabajo')
                       WHEN 'sin_iniciar_servicio'     THEN CONCAT('Pasaron ', IFNULL(a.minutos, 0), ' min de la hora de salida programada y no marcó "Salida"')
                       WHEN 'proximidad'               THEN CONCAT('Está a menos de ', v_prox, ' m del cliente')
                       WHEN 'incidente'                THEN CONCAT('Incidente crítico abierto hace ', IFNULL(a.minutos, 0), ' min')
                       ELSE a.titulo END,
                   ' — ', COALESCE(NULLIF(o.sede_nombre, ''), NULLIF(o.razon_social, ''), 'cliente'),
                   IF(NULLIF(o.sede_nombre, '') IS NOT NULL AND NULLIF(o.razon_social, '') IS NOT NULL, CONCAT(' (', o.razon_social, ')'), ''),
                   ' · ', IFNULL(a.numero, ''), '.'), 1000),
               'orden_servicio', a.id_os, NOW(), NULL,
               'control_campo', 'alerta_operativa',
               CASE a.severidad WHEN 'critica' THEN 'critica' WHEN 'advertencia' THEN 'alta' ELSE 'normal' END,
               CONCAT(a.clave, ':', DATE_FORMAT(v_hoy, '%Y%m%d'))
        FROM   tmp_sg_alerta a
        JOIN   tmp_sg_os o ON o.id_os = a.id_os
        CROSS JOIN tmp_alerta_dest d
        WHERE  NOT EXISTS (SELECT 1 FROM notificacion n
                           WHERE  n.clave_alerta = CONCAT(a.clave, ':', DATE_FORMAT(v_hoy, '%Y%m%d'))
                             AND  n.id_usuario_destino = d.id_usuario);
        SET v_generadas = ROW_COUNT();

        DROP TEMPORARY TABLE IF EXISTS tmp_alerta_dest;
    END IF;

    CALL SP_LimpiarSeguimientoOperativo();
    DO RELEASE_LOCK('tw_alertas_operativas');

    SELECT 2 AS IdTipoMensaje, 'Alertas operativas procesadas.' AS Mensaje;
    SELECT v_generadas AS generadas, v_alertas AS alertas;
END$$

DELIMITER ;

SELECT 'HU-20 (debe ser 8)' AS verificacion, COUNT(*) AS valor FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = DATABASE() AND ROUTINE_NAME IN ('SP_EstadoJornadaMovil','SP_ObtenerJornadaMovil','SP_RegistrarMarcacionJornadaMovil','SP_RegistrarUbicacionJornadaMovil','SP_ArmarSeguimientoOperativo','SP_ObtenerResumenSeguimiento','SP_ObtenerTecnicosSeguimiento','SP_GenerarAlertasOperativas');
