-- HU-20 y HU-04: salida de planta que concluye el servicio, alertas críticas (sin movimiento y autorización de salida pendiente) y colores del seguimiento. Ejecutar con Alt+X (No al aviso) y reiniciar la API.
-- 119: jornada_salida — cada «Salida de planta» del Reloj marcador (HU-20). Un técnico puede salir de varias plantas el mismo día (una por servicio concluido);
-- jornada_marcacion conserva solo la primera por su índice único (usuario, día, tipo). Idempotente.
CREATE TABLE IF NOT EXISTS jornada_salida (
    id_salida    BIGINT        NOT NULL AUTO_INCREMENT,
    id_usuario   BIGINT        NOT NULL,
    fecha        DATE          NOT NULL,
    id_os        BIGINT        NULL,
    marcado_utc  DATETIME      NOT NULL,
    latitud      DECIMAL(10,7) NULL,
    longitud     DECIMAL(10,7) NULL,
    precision_m  INT           NULL,
    lugar        VARCHAR(200)  NULL,
    sin_conexion TINYINT       NOT NULL DEFAULT 0,
    creado_en    DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id_salida),
    KEY ix_jornada_salida_dia (id_usuario, fecha),
    KEY ix_jornada_salida_os (id_os)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ============================================================
-- SP_EstadoJornadaMovil  (App Mobile HU-20 — apoyo, NO es un endpoint)
-- UNA sola regla del orden de la jornada: las marcaciones del día forman siempre un prefijo de
--   inicio_labores → inicio_refrigerio → fin_refrigerio → salida_planta → fin_labores
-- así que con la cantidad de marcaciones se sabe el estado y el único paso siguiente habilitado.
--   n = 0 sin_iniciar · 1 en_labores · 2 en_refrigerio · 3 en_labores (después del refrigerio) · 4 salio_planta · 5 finalizada
-- Salida adicional (HU-20): con n = 4 (ya salió de una planta) pero con OTRO servicio del día en ejecución, el paso siguiente vuelve a ser «salida_planta»:
-- cada salida concluye el servicio en ejecución (ver SP_RegistrarMarcacionJornadaMovil); sin servicio en ejecución el siguiente es «fin_labores».
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
    IF p_n = 4 AND EXISTS (SELECT 1 FROM orden_servicio os
                           WHERE os.eliminado_en IS NULL AND os.estado = 'en_ejecucion'
                             AND (os.id_tecnico_principal = p_id_usuario
                                  OR EXISTS (SELECT 1 FROM os_personal op WHERE op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL))
                             AND EXISTS (SELECT 1 FROM programacion pg WHERE pg.id_os = os.id_os AND pg.estado = 'confirmada' AND pg.eliminado_en IS NULL AND pg.fecha_ejecucion = p_fecha)) THEN
        SET p_siguiente = 'salida_planta';
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
--   · Salida de planta (HU-20): confirma que el técnico concluyó el servicio programado en ejecución. Si a sus equipos (los visibles en la app) les falta ejecutar alguno,
--     NO deja salir (regla de negocio); si están todos, la OS pasa a «finalizada» (evento de campo CIERRE, hora fin real, auditoría) y sale del Seguimiento Operativo (queda en
--     Revisión de Informes). Con otro servicio del día en ejecución la salida se puede marcar de nuevo (jornada_salida guarda cada salida; jornada_marcacion solo la primera).
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
    DECLARE v_id_os     BIGINT DEFAULT NULL;
    DECLARE v_num_os    VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_id_prog   BIGINT DEFAULT NULL;
    DECLARE v_n_prog    INT DEFAULT 0;
    DECLARE v_pend      INT DEFAULT 0;
    DECLARE v_tipo_cie  INT DEFAULT NULL;
    DECLARE v_cerro     TINYINT DEFAULT 0;

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
    CALL SP_EstadoJornadaMovil(p_id_usuario, v_fecha, v_n, v_estado, v_sig, v_ultima);
    SELECT j.id_marcacion INTO v_existente FROM jornada_marcacion j WHERE j.id_usuario = p_id_usuario AND j.fecha = v_fecha AND j.tipo = p_tipo LIMIT 1;
    -- Salida adicional (otro servicio del día): su repetición se reconoce por la hora marcada
    IF p_tipo = 'salida_planta' AND v_n >= 4 THEN
        SET v_existente = NULL;
        SELECT s.id_salida INTO v_existente FROM jornada_salida s WHERE s.id_usuario = p_id_usuario AND s.fecha = v_fecha AND s.marcado_utc = v_marcado LIMIT 1;
        IF v_existente IS NULL THEN
            SELECT j.id_marcacion INTO v_existente FROM jornada_marcacion j WHERE j.id_usuario = p_id_usuario AND j.fecha = v_fecha AND j.tipo = 'salida_planta' AND j.marcado_utc = v_marcado LIMIT 1;
        END IF;
    END IF;
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

    -- Salida de planta: el servicio programado en ejecución debe tener todos sus equipos ejecutados
    IF p_tipo = 'salida_planta' THEN
        SELECT os.id_os, os.numero INTO v_id_os, v_num_os
        FROM   orden_servicio os
        WHERE  os.eliminado_en IS NULL AND os.estado = 'en_ejecucion'
          AND  (os.id_tecnico_principal = p_id_usuario
                OR EXISTS (SELECT 1 FROM os_personal op WHERE op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL))
          AND  EXISTS (SELECT 1 FROM programacion pg WHERE pg.id_os = os.id_os AND pg.estado = 'confirmada' AND pg.eliminado_en IS NULL AND pg.fecha_ejecucion = v_fecha)
        ORDER BY os.id_os LIMIT 1;
        IF v_id_os IS NOT NULL THEN
            SELECT MAX(pg.id_programacion) INTO v_id_prog FROM programacion pg
            WHERE  pg.id_os = v_id_os AND pg.estado = 'confirmada' AND pg.eliminado_en IS NULL AND pg.fecha_ejecucion = v_fecha;
            SELECT COUNT(*) INTO v_n_prog FROM programacion_equipo pe WHERE pe.id_programacion = v_id_prog AND pe.eliminado_en IS NULL;
            -- mismos equipos que ve el técnico en la app (SP_ArmarObjetivosMovil)
            SELECT COUNT(*) INTO v_pend
            FROM   os_equipo oe
            WHERE  oe.id_os = v_id_os AND oe.eliminado_en IS NULL AND IFNULL(oe.estado_ejecucion, '') <> 'ejecutado'
              AND  (v_n_prog = 0 OR oe.ingresado_en_campo = 1
                    OR EXISTS (SELECT 1 FROM programacion_equipo pe WHERE pe.id_programacion = v_id_prog AND pe.id_equipo = oe.id_equipo AND pe.eliminado_en IS NULL));
            IF v_pend > 0 THEN
                ROLLBACK;
                SELECT 1 AS IdTipoMensaje,
                       CONCAT('Aún falta ejecutar ', v_pend, IF(v_pend = 1, ' equipo', ' equipos'), ' del servicio ', v_num_os, '. Termina el trabajo antes de marcar la salida de planta.') AS Mensaje;
                LEAVE proc;
            END IF;
        END IF;
    END IF;

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
                 6371000 * 2 * ASIN(SQRT(POW(SIN(RADIANS(sc.latitud - p_latitud) / 2), 2)
                              + COS(RADIANS(p_latitud)) * COS(RADIANS(sc.latitud)) * POW(SIN(RADIANS(sc.longitud - p_longitud) / 2), 2))) AS d
          FROM sede_cliente sc
          JOIN cliente c ON c.id_cliente = sc.id_cliente
          WHERE sc.SoftDelete = 0 AND sc.latitud IS NOT NULL AND sc.longitud IS NOT NULL) x
    WHERE x.d <= 300
    ORDER BY x.d
    LIMIT 1;

    IF p_tipo = 'salida_planta' AND v_n >= 4 THEN
        SET v_id = NULL;   -- salida adicional: la marcación del día ya existe (índice único); queda registrada en jornada_salida
    ELSE
        INSERT INTO jornada_marcacion (id_usuario, fecha, tipo, marcado_utc, latitud, longitud, precision_m, lugar, puntualidad, minutos_diferencia, sin_conexion)
        VALUES (p_id_usuario, v_fecha, p_tipo, v_marcado, p_latitud, p_longitud, IF(p_precision IS NULL, NULL, ROUND(p_precision)), v_lugar, v_punt, v_dif,
                IF(IFNULL(p_sin_conexion, 0) = 1, 1, 0));
        SET v_id = LAST_INSERT_ID();
    END IF;

    IF p_tipo = 'salida_planta' THEN
        INSERT INTO jornada_salida (id_usuario, fecha, id_os, marcado_utc, latitud, longitud, precision_m, lugar, sin_conexion)
        VALUES (p_id_usuario, v_fecha, v_id_os, v_marcado, p_latitud, p_longitud, IF(p_precision IS NULL, NULL, ROUND(p_precision)), v_lugar,
                IF(IFNULL(p_sin_conexion, 0) = 1, 1, 0));
        IF v_id IS NULL THEN SET v_id = LAST_INSERT_ID(); END IF;

        IF v_id_os IS NOT NULL THEN
            SELECT t.Num1 INTO v_tipo_cie FROM tabla_maestra t WHERE t.Descripcion = 'TIPO_EVENTO_CAMPO' AND t.IdEmpresa = 1 AND t.String2 = 'CIERRE' LIMIT 1;
            IF v_tipo_cie IS NOT NULL THEN
                INSERT INTO evento_campo (id_os, id_usuario, id_tipo_evento, timestamp_utc, latitud, longitud, sincronizado, notas, creado_por)
                VALUES (v_id_os, p_id_usuario, v_tipo_cie, v_marcado, p_latitud, p_longitud, 1,
                        'Salida de planta marcada en el Reloj marcador: el técnico concluyó el servicio.', p_id_usuario);
            END IF;
            UPDATE orden_servicio
            SET    estado = 'finalizada', hora_fin_real = TIME(CONVERT_TZ(v_marcado, '+00:00', '-05:00')), modificado_por = p_id_usuario, modificado_en = NOW()
            WHERE  id_os = v_id_os;
            INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
            VALUES ('orden_servicio', v_id_os, 'cerrar_por_salida_planta', 'en_ejecucion', 'finalizada',
                    LEFT(CONCAT('El técnico marcó la salida de planta a las ', TIME_FORMAT(CONVERT_TZ(v_marcado, '+00:00', '-05:00'), '%H:%i'), ' y concluyó el servicio ', v_num_os, '.'), 900),
                    p_id_usuario, NOW(), JSON_OBJECT('id_os', v_id_os, 'fecha', DATE_FORMAT(v_fecha, '%Y-%m-%d')));
            SET v_cerro = 1;
        END IF;
    END IF;

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
    SELECT 2 AS IdTipoMensaje, CONCAT(v_nombre, ' registrado.', IF(v_cerro = 1, CONCAT(' El servicio ', v_num_os, ' quedó finalizado.'), '')) AS Mensaje;
    SELECT p_tipo AS tipo, 0 AS repetida, v_estado2 AS estado, v_sig2 AS siguiente,
           TIME_FORMAT(CONVERT_TZ(v_marcado, '+00:00', '-05:00'), '%H:%i:%s') AS hora, v_lugar AS lugar, v_punt AS puntualidad, v_dif AS minutos_diferencia;
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
--   perdida_contacto (crítica) · gps_parado (advertencia) · sin_movimiento (crítica, HU-20) · autorizacion_salida (crítica: el técnico pidió autorización para iniciar el traslado y el encargado aún no responde) · sin_ingreso_post_llegada (advertencia) · sin_iniciar_servicio (advertencia)
--   · proximidad (info) · incidente (crítica)
-- Tablas temporales (MySQL no permite abrir dos veces la misma temporal en una consulta):
--   tmp_sg_cfg (1 fila: hoy, ahora y umbrales) · tmp_sg_os (un servicio por fila) · tmp_sg_ev (eventos de campo del día por OS)
--   tmp_sg_ut (técnico x servicio) · tmp_sg_tec (un técnico por fila) · tmp_sg_pos (última posición GPS por técnico)
--   tmp_sg_alerta · tmp_sg_hito · tmp_sg_inc (demoras e incidencias unificadas; `fase` = momento de la demora de la app: llegada = en ruta, ingreso = ingreso a planta)
-- Demoras de la app (demora_registro, HU-05): las de llegada corren la hora esperada de llegada (hito) y las de ingreso, la hora esperada de inicio.
-- Jornada (HU-20): cada técnico trae su estado del Reloj marcador (jornada: en_labores | en_refrigerio | salio_planta | finalizada; NULL si no inició) y una frase de lo que
-- está haciendo (actividad). «Sin movimiento»: jornada en curso (no en refrigerio ni finalizada), con señal, GPS en el mismo punto SEG_SIN_MOVIMIENTO_MIN o más.
-- Destino y ETA (HU-20): la planta es la sede_cliente de la OS y, si no tiene datos, la del requerimiento (RQ); las coordenadas salen de sede_cliente.latitud/longitud (migración 110),
-- de la tabla sede o, sin ninguna, de la llegada registrada. eta_min / eta_est = estimación EN RUTA: distancia en línea recta × 1,3 (calles) a SEG_VELOCIDAD_PROMEDIO_KMH (30 por defecto); es referencial.
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
    DECLARE v_vel_prom  DECIMAL(18,6);

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
    CALL SP_LeerParametroProgramacion('SEG_VELOCIDAD_PROMEDIO_KMH', 30,  v_vel_prom);

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
        planta_ubicada TINYINT DEFAULT 0,   -- 1 = lat/lon_sede son de la sede (mapa); 0 = no tiene, o es la llegada registrada del técnico (reemplazo)
        id_tecnico BIGINT, tecnico VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, nombre_pila VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        zona VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        hora_inicio TIME, hora_fin_est TIME, os_estado VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        propuesta VARCHAR(60) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        n_equipos INT DEFAULT 0, n_ejecutados INT DEFAULT 0,
        salida_utc DATETIME, llegada_dt DATETIME, inicio_dt DATETIME, fin_dt DATETIME,
        crit TINYINT DEFAULT 0, n_demoras INT DEFAULT 0, min_dem_lleg INT DEFAULT 0, ing_eta DATETIME,
        estado_seg VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, fase VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, prio INT DEFAULT 9, dist_m INT, eta_min INT, eta_est DATETIME,
        PRIMARY KEY (id_os)
    );

    INSERT INTO tmp_sg_os (id_os, id_programacion, numero, tipo, id_cliente, razon_social, ruc, id_sede, sede_nombre, sede_direccion, lat_sede, lon_sede, planta_ubicada,
                           id_tecnico, tecnico, nombre_pila, zona, hora_inicio, hora_fin_est, os_estado, propuesta, n_equipos, n_ejecutados,
                           llegada_dt, fin_dt)
    SELECT os.id_os, p.id_programacion, os.numero, os.tipo, os.id_cliente, c.razon_social, c.ruc, os.id_sede, COALESCE(NULLIF(sc.nombre, ''), sc2.nombre), COALESCE(NULLIF(sc.direccion_exacta, ''), sc2.direccion_exacta), COALESCE(sc.latitud, s.latitud, sc2.latitud, os.latitud_llegada), COALESCE(sc.longitud, s.longitud, sc2.longitud, os.longitud_llegada),
           IF(COALESCE(sc.latitud, s.latitud, sc2.latitud) IS NOT NULL AND COALESCE(sc.longitud, s.longitud, sc2.longitud) IS NOT NULL, 1, 0),
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
    LEFT JOIN requerimiento rq ON rq.id_requerimiento = COALESCE(os.id_requerimiento, pr.id_requerimiento)
    LEFT JOIN sede_cliente sc2 ON sc2.id_sede = rq.id_sede AND sc2.SoftDelete = 0
    WHERE p.eliminado_en IS NULL AND p.estado = 'confirmada' AND p.fecha_ejecucion = v_hoy
      AND os.estado NOT IN ('anulada', 'borrador', 'emitida', 'finalizada');   -- finalizada: ya está en Revisión de Informes (el técnico sigue en el mapa por su jornada)

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
        jornada VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, jornada_n INT DEFAULT 0, jornada_desde DATETIME, actividad VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        actividad_tono VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, actividad_color CHAR(7) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
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

    -- HU-20: técnicos con la jornada iniciada hoy que no tienen servicio programado: también salen en el mapa y en la lista (sin servicios; estado «sin salir»,
    -- lo que hacen lo dice «actividad»). Los que ya están por tener servicio no se repiten (clave primaria).
    INSERT IGNORE INTO tmp_sg_tec (id_usuario, nombre, nombre_pila, iniciales, cargo, zona, prio, estado_seg, n_servicios, n_completados, n_en_curso)
    SELECT u.id_usuario, TRIM(CONCAT(u.nombre, ' ', u.apellido)), u.nombre, UPPER(CONCAT(LEFT(u.nombre, 1), LEFT(u.apellido, 1))),
           COALESCE(cg.String1, u.cargo), COALESCE(zn.String1, u.sede_operativa), 6, 'sin_salir', 0, 0, 0
    FROM usuario u
    LEFT JOIN tabla_maestra cg ON cg.IdMaestro = 80 AND cg.IdEmpresa = 1 AND cg.String2 = u.cargo
    LEFT JOIN tabla_maestra zn ON zn.IdMaestro = 69 AND zn.IdEmpresa = 1 AND zn.String2 = u.sede_operativa
    WHERE u.eliminado_en IS NULL
      AND EXISTS (SELECT 1 FROM jornada_marcacion j WHERE j.id_usuario = u.id_usuario AND j.fecha = v_hoy);

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

    -- Jornada del técnico (HU-20): estado del Reloj marcador de hoy (la misma tabla de estados de SP_EstadoJornadaMovil) y lo que está haciendo.
    -- jornada_n = marcaciones de hoy (1 inicio · 2 refrigerio · 3 volvió del refrigerio · 4 salida de planta · 5 fin).
    UPDATE tmp_sg_tec t
    SET t.jornada_n = (SELECT COUNT(*) FROM jornada_marcacion j WHERE j.id_usuario = t.id_usuario AND j.fecha = v_hoy),
        t.jornada_desde = (SELECT MAX(j.marcado_utc) FROM jornada_marcacion j WHERE j.id_usuario = t.id_usuario AND j.fecha = v_hoy);
    UPDATE tmp_sg_tec t
    SET t.jornada = CASE t.jornada_n WHEN 0 THEN NULL WHEN 1 THEN 'en_labores' WHEN 2 THEN 'en_refrigerio' WHEN 3 THEN 'en_labores'
                                     WHEN 4 THEN 'salio_planta' ELSE 'finalizada' END;
    -- Actividad (texto) y actividad_tono / actividad_color (para diferenciar por colores a simple vista):
    --   trabajo (verde) ejecutando un equipo · planta (turquesa) en planta sin iniciar · ruta (azul) · refrigerio (ámbar) comiendo/descansando (fuera de sus responsabilidades) ·
    --   refrigerio_fin (lima) acaba de volver de comer (menos de 15 min) · salida_planta (morado) · finalizada (gris) · sin_iniciar (gris claro) · demora (naranja) · incidente (rojo)
    UPDATE tmp_sg_tec t
    LEFT JOIN tmp_sg_os o ON o.id_os = t.id_os_actual
    SET t.actividad = LEFT(CASE
            WHEN t.jornada = 'en_refrigerio' THEN CONCAT('En refrigerio (almuerzo/descanso) desde las ', TIME_FORMAT(CONVERT_TZ(t.jornada_desde, '+00:00', '-05:00'), '%H:%i'),
                 ' · hace ', TIMESTAMPDIFF(MINUTE, t.jornada_desde, v_ahora_utc), ' min · fuera de sus labores')
            WHEN t.jornada = 'salio_planta' THEN CONCAT('Salió de planta hace ', TIMESTAMPDIFF(MINUTE, t.jornada_desde, v_ahora_utc), ' min (',
                 TIME_FORMAT(CONVERT_TZ(t.jornada_desde, '+00:00', '-05:00'), '%H:%i'), ')', IF(o.id_os IS NULL, '', CONCAT(' · servicio ', o.numero)))
            WHEN t.jornada = 'finalizada' THEN CONCAT('Jornada finalizada a las ', TIME_FORMAT(CONVERT_TZ(t.jornada_desde, '+00:00', '-05:00'), '%H:%i'))
            WHEN t.jornada = 'en_labores' THEN CONCAT(
                 IF(t.jornada_n = 3, CONCAT('Volvió del refrigerio hace ', TIMESTAMPDIFF(MINUTE, t.jornada_desde, v_ahora_utc), ' min · '), 'En labores · '),
                 CASE o.fase WHEN 'en_ruta'      THEN CONCAT('en ruta a ', o.razon_social, IF(o.eta_min IS NULL, '', CONCAT(' · llega en ~', o.eta_min, ' min')), ' · ', o.numero)
                             WHEN 'en_planta'    THEN CONCAT('en planta de ', o.razon_social, IF(o.llegada_dt IS NULL, '', CONCAT(' desde hace ', TIMESTAMPDIFF(MINUTE, o.llegada_dt, v_ahora), ' min')), ' · ', o.numero)
                             WHEN 'en_ejecucion' THEN CONCAT('ejecutando ', o.numero, ' en ', o.razon_social, ' · ', o.n_ejecutados, ' de ', o.n_equipos, ' equipos',
                                                             IFNULL((SELECT CONCAT(' · trabajando en ', COALESCE(NULLIF(ec.codigo_cliente, ''), ec.codigo_tw))
                                                                     FROM os_equipo oe JOIN equipo_cliente ec ON ec.id_equipo = oe.id_equipo
                                                                     WHERE oe.id_os = o.id_os AND oe.eliminado_en IS NULL AND oe.estado_ejecucion = 'en_proceso' AND oe.pausado = 0
                                                                     ORDER BY oe.id LIMIT 1), ''))
                             WHEN 'finalizado'   THEN CONCAT('servicio ', o.numero, ' finalizado · ', o.n_ejecutados, ' de ', o.n_equipos, ' equipos')
                             WHEN 'sin_salir'    THEN CONCAT('aún en base · servicio ', o.numero, ' programado ', IFNULL(TIME_FORMAT(o.hora_inicio, '%H:%i'), ''))
                             ELSE 'sin servicio asignado hoy' END,
                 IF(t.estado_seg = 'con_incidente', ' · CON INCIDENTE', IF(t.estado_seg = 'con_demora', ' · con demora', '')))
            ELSE CASE o.fase WHEN 'en_ruta' THEN CONCAT('En ruta a ', o.razon_social, ' (sin marcar el Reloj) · ', o.numero) ELSE 'Jornada sin iniciar (no marcó el Reloj)' END
        END, 250),
        t.actividad_tono = CASE
            WHEN t.jornada = 'en_refrigerio' THEN 'refrigerio'
            WHEN t.jornada = 'salio_planta' AND o.fase = 'en_ejecucion' THEN 'trabajo'
            WHEN t.jornada = 'salio_planta'  THEN 'activo'
            WHEN t.jornada = 'finalizada'    THEN 'finalizada'
            WHEN t.estado_seg = 'con_incidente' THEN 'incidente'
            WHEN t.estado_seg = 'con_demora'    THEN 'demora'
            WHEN t.jornada = 'en_labores' AND t.jornada_n = 3 AND TIMESTAMPDIFF(MINUTE, t.jornada_desde, v_ahora_utc) < 15 THEN 'refrigerio_fin'
            WHEN o.fase = 'en_ejecucion' THEN 'trabajo'
            WHEN o.fase = 'en_planta'    THEN 'planta'
            WHEN o.fase = 'en_ruta'      THEN 'ruta'
            WHEN t.jornada = 'en_labores' THEN 'activo'
            ELSE 'sin_iniciar' END;
    UPDATE tmp_sg_tec t
    SET t.actividad_color = CASE t.actividad_tono
            WHEN 'trabajo' THEN '#EAB308' WHEN 'activo' THEN '#16A34A' WHEN 'planta' THEN '#14B8A6' WHEN 'ruta' THEN '#2563EB' WHEN 'refrigerio' THEN '#F97316' WHEN 'refrigerio_fin' THEN '#84CC16'
            WHEN 'salida_planta' THEN '#7C3AED' WHEN 'finalizada' THEN '#64748B' WHEN 'demora' THEN '#EA580C' WHEN 'incidente' THEN '#DC2626' ELSE '#94A3B8' END;

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

    -- ETA estimada en ruta (HU-20): línea recta × 1,3 a la velocidad promedio (mínimo 5 km/h); al menos 1 minuto
    UPDATE tmp_sg_os o
    SET o.eta_min = GREATEST(1, CEIL(o.dist_m * 1.3 / 1000 / GREATEST(v_vel_prom, 5) * 60))
    WHERE o.fase = 'en_ruta' AND o.dist_m IS NOT NULL;
    UPDATE tmp_sg_os o SET o.eta_est = DATE_ADD(v_ahora, INTERVAL o.eta_min MINUTE) WHERE o.eta_min IS NOT NULL;

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
    -- El tiempo sin movimiento se cuenta desde el último «Inicio de labores» o «Fin de refrigerio» (no desde antes de marcar). Severidad crítica (aparece en «Alertas críticas»). En ruta lo cubre «GPS parado»; con el servicio ya finalizado o con el trabajo en ejecución no se alerta. Se asocia al servicio del día del técnico (la notificación lo exige).
    INSERT INTO tmp_sg_alerta
    SELECT CONCAT('sin_movimiento:', t.id_usuario, ':', o.id_os), 'sin_movimiento', 'critica', 'Técnico sin movimiento',
           CONCAT(t.nombre, ' · ', o.numero), TIMESTAMPDIFF(MINUTE, GREATEST(p.parado_desde, jd.desde_utc), v_ahora_utc), t.id_usuario, t.nombre, o.id_os, o.numero
    FROM tmp_sg_tec t
    JOIN tmp_sg_os o ON o.id_os = t.id_os_actual
    JOIN tmp_sg_pos p ON p.id_usuario = t.id_usuario
    JOIN (SELECT j.id_usuario, MAX(j.marcado_utc) AS desde_utc
          FROM   jornada_marcacion j
          WHERE  j.fecha = v_hoy AND j.tipo IN ('inicio_labores', 'fin_refrigerio')
          GROUP BY j.id_usuario) jd ON jd.id_usuario = t.id_usuario
    WHERE t.jornada IN ('en_labores', 'salio_planta') AND o.fase NOT IN ('en_ruta', 'en_ejecucion', 'finalizado') AND p.parado_desde IS NOT NULL
      AND TIMESTAMPDIFF(MINUTE, p.ts_utc, v_ahora_utc) <= v_perdida
      AND TIMESTAMPDIFF(MINUTE, GREATEST(p.parado_desde, jd.desde_utc), p.ts_utc) >= v_sin_mov;

    -- Autorización de salida pendiente: el técnico pidió el visto bueno para iniciar el traslado y el encargado aún no responde (crítica: sale en «Alertas críticas»)
    INSERT INTO tmp_sg_alerta
    SELECT CONCAT('autorizacion_salida:', a.id_tecnico, ':', o.id_os), 'autorizacion_salida', 'critica', 'Autorización de salida pendiente',
           CONCAT(t.nombre, ' · ', o.numero), GREATEST(0, TIMESTAMPDIFF(MINUTE, a.solicitado_en, NOW())), t.id_usuario, t.nombre, o.id_os, o.numero
    FROM tmp_sg_os o
    JOIN tmp_sg_tec t ON t.id_usuario = o.id_tecnico
    JOIN autorizacion_salida_os a ON a.id_os = o.id_os AND a.estado = 'pendiente'
    WHERE o.fase = 'sin_salir';

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

-- ============================================================
-- SP_GenerarAlertasOperativas  (HU-90 Centro de Notificaciones — alertas del Módulo 11 Control de Campo)
-- Lo ejecuta el worker de la API (AlertasOperativasWorker) cada minuto. Proceso del sistema: no valida permisos de quien llama.
-- Las alertas automáticas del Módulo 11 solo se calculaban al abrir la bandeja de seguimiento; este SP las guarda como notificación
-- para que lleguen a la campana. Usa EXACTAMENTE el mismo cálculo y los mismos umbrales (SP_ArmarSeguimientoOperativo, migración 90):
--   perdida_contacto (crítica) · gps_parado (advertencia) · sin_movimiento (CRÍTICA, HU-20: avisa a los 10 min y se repite cada 5 min hasta que el técnico se mueve o inicia el trabajo) · sin_ingreso_post_llegada (advertencia) · sin_iniciar_servicio (advertencia)
--   · proximidad (info) · incidente crítico (crítica)
-- Destinatarios: usuarios activos con el permiso seg_bandeja (los que ven la bandeja de seguimiento).
-- Sin duplicados: clave_alerta = clave de la alerta + fecha de Lima → una sola notificación por alerta, técnico, servicio y día.
-- Excepción «sin_movimiento»: la clave lleva además el tramo de 5 minutos (minutos / 5) → una notificación nueva cada 5 min mientras siga parado.
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
               IF(a.tipo = 'sin_movimiento', LEFT(CONCAT('Técnico sin movimiento — ', IFNULL(a.tecnico, '')), 150), LEFT(CONCAT('Técnico ', IFNULL(a.tecnico, ''), ' — ', a.titulo), 150)),
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
               CONCAT(a.clave, IF(a.tipo = 'sin_movimiento', CONCAT(':r', FLOOR(IFNULL(a.minutos, 0) / 5)), ''), ':', DATE_FORMAT(v_hoy, '%Y%m%d'))
        FROM   tmp_sg_alerta a
        JOIN   tmp_sg_os o ON o.id_os = a.id_os
        CROSS JOIN tmp_alerta_dest d
        WHERE  a.tipo <> 'autorizacion_salida'   -- su notificación (crítica) ya la crea SP_SolicitarAutorizacionSalidaMovil al pedir la autorización
          AND  NOT EXISTS (SELECT 1 FROM notificacion n
                           WHERE  n.clave_alerta = CONCAT(a.clave, IF(a.tipo = 'sin_movimiento', CONCAT(':r', FLOOR(IFNULL(a.minutos, 0) / 5)), ''), ':', DATE_FORMAT(v_hoy, '%Y%m%d'))
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

-- ============================================================
-- SP_SolicitarAutorizacionSalidaMovil  (App Mobile HU-04)
-- El técnico pide el visto bueno para salir con pendientes al ENCARGADO DEL ÁREA del servicio.
--   - El área sale de la RQ de la OS: orden_servicio → expediente_digital → requerimiento.id_area
--     (catálogo AREA_REQUERIMIENTO 64) → area_servicio_rq → servicio_tecnico | metrologia.
--   - Encargado = usuario activo cuyo cargo es el "jefe_*" de esa área en CARGO_USUARIO (80):
--     Jefe de Servicio Técnico o Jefe de Metrología.
--   - Si la RQ no tiene área (o no está mapeada) se notifica a ambos encargados.
--   - Respaldo si el área no tiene encargado activo: supervisores/administradores del área;
--     si tampoco, Jefe/Coordinador de Operaciones; si tampoco, administradores.
--   - Una sola solicitud pendiente por OS (evita duplicados y spam de notificaciones).
--   - Solo desde el día programado de la OS (SP_ObtenerSalidaHabilitadaMovil).
--   - La notificación al encargado es CRÍTICA (prioridad_origen = critica, control_campo / autorizacion_salida): sale como alerta crítica; el Seguimiento Operativo
--     también la muestra en «Alertas críticas» mientras la solicitud siga pendiente (SP_ArmarSeguimientoOperativo).
--   - Deja también una notificación al propio técnico ("Solicitud de autorización enviada") para que la vea en la app.
--   - Deja registro en autorizacion_salida_os (con area_destino) y auditoria_evento.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_SolicitarAutorizacionSalidaMovil;

DELIMITER $$

CREATE PROCEDURE SP_SolicitarAutorizacionSalidaMovil(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT,
    IN p_motivo     VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_pendientes VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_estado      VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_numero      VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cliente     VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tecnico     VARCHAR(210) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_aut_estado  VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_aut      BIGINT;
    DECLARE v_destinos    INT DEFAULT 0;
    DECLARE v_area        VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_area_nombre VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_notificados VARCHAR(600) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_salida_ok   TINYINT DEFAULT 1;
    DECLARE v_salida_msg  VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

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

    IF v_estado NOT IN ('programada', 'reprogramada') THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'El servicio ya no está programado: no hace falta autorización de salida.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- La salida (y su autorización) solo se gestiona desde el día programado
    CALL SP_ObtenerSalidaHabilitadaMovil(p_id_os, v_salida_ok, v_salida_msg);
    IF v_salida_ok = 0 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, v_salida_msg AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT a.estado INTO v_aut_estado
    FROM   autorizacion_salida_os a
    WHERE  a.id_os = p_id_os AND a.eliminado_en IS NULL
    ORDER BY a.id_autorizacion DESC LIMIT 1;

    IF v_aut_estado = 'pendiente' THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Ya enviaste una solicitud: espera la respuesta del encargado del área.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF v_aut_estado = 'aprobada' THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Ya tienes el visto bueno: puedes iniciar el traslado.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT TRIM(CONCAT(IFNULL(nombre, ''), ' ', IFNULL(apellido, ''))) INTO v_tecnico
    FROM usuario WHERE id_usuario = p_id_usuario;

    SET v_area_nombre = (SELECT t.String1 FROM tabla_maestra t
                         WHERE t.IdMaestro = 79 AND t.IdEmpresa = 1 AND t.String2 = v_area LIMIT 1);

    INSERT INTO autorizacion_salida_os (id_os, id_tecnico, motivo, pendientes, estado, area_destino, solicitado_en, creado_por)
    VALUES (p_id_os, p_id_usuario, NULLIF(TRIM(p_motivo), ''), NULLIF(TRIM(p_pendientes), ''), 'pendiente', v_area, NOW(), p_id_usuario);
    SET v_id_aut = LAST_INSERT_ID();

    -- Destinatarios (en una tabla temporal para notificar y responder con los nombres)
    DROP TEMPORARY TABLE IF EXISTS tmp_aut_destino;
    CREATE TEMPORARY TABLE tmp_aut_destino (
        id_usuario BIGINT PRIMARY KEY,
        nombre     VARCHAR(210) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        cargo      VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
    );

    -- 1) Encargado(s) del área: cargo jefe_* del área (si la RQ no tiene área: de ambas áreas)
    INSERT IGNORE INTO tmp_aut_destino
    SELECT u.id_usuario, TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))), c.String1
    FROM   usuario u
    JOIN   tabla_maestra c ON c.IdMaestro = 80 AND c.IdEmpresa = 1 AND c.String2 = u.cargo
    WHERE  u.eliminado_en IS NULL AND u.estado = 'activo'
      AND  c.String2 LIKE 'jefe\_%'
      AND  ((v_area IS NOT NULL AND c.String3 = v_area)
            OR (v_area IS NULL AND c.String3 IN ('servicio_tecnico', 'metrologia')));

    -- 2) Respaldo: supervisores / administradores del área
    IF (SELECT COUNT(*) FROM tmp_aut_destino) = 0 THEN
        INSERT IGNORE INTO tmp_aut_destino
        SELECT u.id_usuario, TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))), NULL
        FROM   usuario u
        WHERE  u.eliminado_en IS NULL AND u.estado = 'activo'
          AND  u.rol_sistema IN ('supervisor', 'administrador')
          AND  ((v_area IS NOT NULL AND u.area = v_area)
                OR (v_area IS NULL AND u.area IN ('servicio_tecnico', 'metrologia')));
    END IF;

    -- 3) Respaldo: Jefe / Coordinador de Operaciones
    IF (SELECT COUNT(*) FROM tmp_aut_destino) = 0 THEN
        INSERT IGNORE INTO tmp_aut_destino
        SELECT u.id_usuario, TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))), c.String1
        FROM   usuario u
        LEFT JOIN tabla_maestra c ON c.IdMaestro = 80 AND c.IdEmpresa = 1 AND c.String2 = u.cargo
        WHERE  u.eliminado_en IS NULL AND u.estado = 'activo'
          AND  u.cargo IN ('jefe_operaciones', 'coordinador_operaciones');
    END IF;

    -- 4) Respaldo final: administradores
    IF (SELECT COUNT(*) FROM tmp_aut_destino) = 0 THEN
        INSERT IGNORE INTO tmp_aut_destino
        SELECT u.id_usuario, TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))), NULL
        FROM   usuario u
        WHERE  u.eliminado_en IS NULL AND u.estado = 'activo' AND u.rol_sistema IN ('administrador', 'admin');
    END IF;

    INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por,
                              modulo_origen, tipo_origen, prioridad_origen)
    SELECT d.id_usuario, 5,
           CONCAT('Autorización de salida', IF(v_area_nombre IS NULL, '', CONCAT(' · ', v_area_nombre)), ': ', v_numero),
           CONCAT(v_tecnico, ' solicita tu visto bueno para salir a ', IFNULL(v_cliente, 'el cliente'), ' (', v_numero, ').',
                  IF(v_area_nombre IS NULL, ' La RQ no indica el área del servicio.', CONCAT(' Área del servicio según la RQ: ', v_area_nombre, '.')),
                  IF(NULLIF(TRIM(p_pendientes), '') IS NULL, '', CONCAT(' Pendientes: ', TRIM(p_pendientes), '.')),
                  IF(NULLIF(TRIM(p_motivo), '') IS NULL, '', CONCAT(' Motivo: ', TRIM(p_motivo)))),
           'orden_servicio', p_id_os, NOW(), p_id_usuario,
           'control_campo', 'autorizacion_salida', 'critica'
    FROM   tmp_aut_destino d;
    SET v_destinos = ROW_COUNT();

    SELECT GROUP_CONCAT(CONCAT(d.nombre, IFNULL(CONCAT(' (', d.cargo, ')'), '')) ORDER BY d.nombre SEPARATOR ', ')
    INTO   v_notificados
    FROM   tmp_aut_destino d;
    DROP TEMPORARY TABLE IF EXISTS tmp_aut_destino;

    -- Confirmación para el propio técnico (HU-04: "Solicitud de autorización enviada · avisado al Jefe …")
    INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
    VALUES (p_id_usuario, 5, 'Solicitud de autorización enviada',
            LEFT(CONCAT(v_numero, ' · ', IF(v_notificados IS NULL, 'sin un encargado activo para avisar', CONCAT('avisado a ', v_notificados))), 3000),
            'orden_servicio', p_id_os, NOW(), p_id_usuario);

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('orden_servicio', p_id_os, 'solicitar_autorizacion_salida', IFNULL(v_aut_estado, 'sin_solicitud'), 'pendiente',
            CONCAT('El técnico solicita visto bueno para salir.',
                   IF(NULLIF(TRIM(p_pendientes), '') IS NULL, '', CONCAT(' Pendientes: ', TRIM(p_pendientes), '.'))),
            p_id_usuario, NOW(), JSON_OBJECT('id_autorizacion', v_id_aut, 'area_destino', v_area, 'notificados', v_destinos));

    COMMIT;

    SELECT 2 AS IdTipoMensaje,
           IF(v_destinos > 0,
              CONCAT('Solicitud enviada a ', v_notificados, '.'),
              'Solicitud registrada, pero no hay un encargado activo para notificar: avisa a tu jefe.') AS Mensaje;
END$$

DELIMITER ;
