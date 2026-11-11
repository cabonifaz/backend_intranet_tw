-- HU-20 (destino y ETA en el mapa y en Ubicación y ruta): Alt+X, responder No al aviso Large script. Reiniciar la API. Idempotente.
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, Num2, String1, String2)
SELECT 1, (SELECT MAX(IdMaestro) FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROGRAMACION'), 'PARAMETRO_PROGRAMACION', 125, 30, 'Velocidad promedio (km/h) para estimar la hora de llegada del técnico en ruta', 'SEG_VELOCIDAD_PROMEDIO_KMH'
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra t WHERE t.Descripcion = 'PARAMETRO_PROGRAMACION' AND t.IdEmpresa = 1 AND t.String2 = 'SEG_VELOCIDAD_PROMEDIO_KMH');

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
-- Destino y ETA (HU-20): la planta se toma de la sede de la OS y, si no tiene coordenadas, de la sede del requerimiento (RQ); sin coordenadas en ninguna, de la llegada
-- registrada. eta_min / eta_est = estimación EN RUTA: distancia en línea recta × 1,3 (calles) a SEG_VELOCIDAD_PROMEDIO_KMH (30 por defecto); es referencial.
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

    INSERT INTO tmp_sg_os (id_os, id_programacion, numero, tipo, id_cliente, razon_social, ruc, id_sede, sede_nombre, sede_direccion, lat_sede, lon_sede,
                           id_tecnico, tecnico, nombre_pila, zona, hora_inicio, hora_fin_est, os_estado, propuesta, n_equipos, n_ejecutados,
                           llegada_dt, fin_dt)
    SELECT os.id_os, p.id_programacion, os.numero, os.tipo, os.id_cliente, c.razon_social, c.ruc, os.id_sede, COALESCE(NULLIF(sc.nombre, ''), s2.nombre), COALESCE(NULLIF(sc.direccion_exacta, ''), s2.direccion), COALESCE(s.latitud, s2.latitud, os.latitud_llegada), COALESCE(s.longitud, s2.longitud, os.longitud_llegada),
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
    LEFT JOIN sede s2 ON s2.id_sede = rq.id_sede AND s2.eliminado_en IS NULL
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

-- HU-52 (Sprint 5) Pestaña "Mapa GPS": posición actual del técnico, ruta recorrida hoy, pin del cliente con radio de proximidad y panel GPS. SOLO LECTURA.
-- Conexión: sin_senal (sin posición o más del umbral SEG_PERDIDA_CONTACTO_MIN) | gps_parado (mismo punto por SEG_GPS_PARADO_MIN o más) | gps_activo.
-- Velocidad, altitud, satélites y latencia salen de ubicacion_tecnico (migración 91; los envía la app; NULL si no los envía).
-- Resultados: 1 mensaje · 2 panel (1 fila) · 3 ruta (puntos del día, máx. 300) · 4 cronograma GPS (salida, pre-llegada, llegada)
--   · 5 demoras de la app con su GPS (Fase: llegada = en ruta, ingreso = ingreso a planta).
DROP PROCEDURE IF EXISTS SP_ObtenerMapaServicioRuta;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerMapaServicioRuta(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT
)
proc: BEGIN
    DECLARE v_msg      VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_ahora_utc DATETIME;
    DECLARE v_ini_utc  DATETIME;
    DECLARE v_perdida  INT;
    DECLARE v_parado   INT;
    DECLARE v_prox     INT;
    DECLARE v_tec      BIGINT;
    DECLARE v_lat_s    DECIMAL(10,7);
    DECLARE v_lon_s    DECIMAL(10,7);
    DECLARE v_id_ub    BIGINT;
    DECLARE v_pre_utc  DATETIME;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        CALL SP_LimpiarSeguimientoOperativo();
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    CALL SP_PrepararDetalleServicioRuta(p_id_usuario, p_id_os, v_msg);
    IF v_msg IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT ahora_utc, ini_utc, perdida, parado, prox INTO v_ahora_utc, v_ini_utc, v_perdida, v_parado, v_prox FROM tmp_sg_cfg LIMIT 1;
    SELECT id_tecnico, lat_sede, lon_sede INTO v_tec, v_lat_s, v_lon_s FROM tmp_sg_os WHERE id_os = p_id_os;
    SELECT MAX(id_ubicacion) INTO v_id_ub FROM ubicacion_tecnico WHERE id_usuario = v_tec AND timestamp_utc >= v_ini_utc AND timestamp_utc <= v_ahora_utc;

    -- Primera posición dentro del radio de proximidad (pre-llegada)
    SELECT MIN(x.timestamp_utc) INTO v_pre_utc FROM ubicacion_tecnico x
    WHERE v_lat_s IS NOT NULL AND v_lon_s IS NOT NULL AND x.id_usuario = v_tec AND x.timestamp_utc >= v_ini_utc AND x.timestamp_utc <= v_ahora_utc
      AND 6371000 * 2 * ASIN(SQRT(POW(SIN(RADIANS(v_lat_s - x.latitud) / 2), 2) + COS(RADIANS(x.latitud)) * COS(RADIANS(v_lat_s)) * POW(SIN(RADIANS(v_lon_s - x.longitud) / 2), 2))) <= v_prox;

    SELECT 2 AS IdTipoMensaje, 'OK' AS Mensaje;

    SELECT o.id_os AS IdOs, o.estado_seg AS Estado, o.tecnico AS Tecnico, o.razon_social AS Cliente, o.sede_nombre AS Sede, o.sede_direccion AS DireccionSede,
           o.lat_sede AS LatSede, o.lon_sede AS LonSede, v_prox AS RadioProximidadM,
           IF(o.fase IN ('en_planta', 'en_ejecucion', 'finalizado') OR (o.dist_m IS NOT NULL AND o.dist_m <= v_prox), 1, 0) AS MostrarRadio,
           p.lat AS Latitud, p.lon AS Longitud, p.direccion AS UltimaUbicacion, o.dist_m AS DistanciaM,
           DATE_FORMAT(CONVERT_TZ(p.ts_utc, '+00:00', '-05:00'), '%H:%i:%s') AS UltimaActualizacion,
           IF(p.ts_utc IS NULL, NULL, GREATEST(0, TIMESTAMPDIFF(SECOND, p.ts_utc, v_ahora_utc))) AS SegundosDesdeUltima,
           CASE WHEN p.ts_utc IS NULL OR TIMESTAMPDIFF(MINUTE, p.ts_utc, v_ahora_utc) > v_perdida THEN 'sin_senal'
                WHEN p.parado_desde IS NOT NULL AND TIMESTAMPDIFF(MINUTE, p.parado_desde, p.ts_utc) >= v_parado THEN 'gps_parado'
                ELSE 'gps_activo' END AS Conexion,
           IF(p.parado_desde IS NULL, 0, GREATEST(0, TIMESTAMPDIFF(MINUTE, p.parado_desde, v_ahora_utc))) AS MinutosEnPunto,
           u.precision_m AS PrecisionM, u.velocidad_kmh AS VelocidadKmh, u.altitud_m AS AltitudM, u.satelites AS Satelites, u.latencia_ms AS LatenciaMs,
           o.eta_min AS EtaMinutos, DATE_FORMAT(o.eta_est, '%H:%i') AS EtaHora
    FROM tmp_sg_os o
    LEFT JOIN tmp_sg_pos p ON p.id_usuario = o.id_tecnico
    LEFT JOIN ubicacion_tecnico u ON u.id_ubicacion = v_id_ub
    WHERE o.id_os = p_id_os;

    SELECT x.latitud AS Latitud, x.longitud AS Longitud, DATE_FORMAT(CONVERT_TZ(x.timestamp_utc, '+00:00', '-05:00'), '%H:%i:%s') AS Hora
    FROM ubicacion_tecnico x
    WHERE x.id_usuario = v_tec AND x.timestamp_utc >= v_ini_utc AND x.timestamp_utc <= v_ahora_utc
    ORDER BY x.timestamp_utc DESC, x.id_ubicacion DESC LIMIT 300;

    SELECT c.hito AS Hito, DATE_FORMAT(CONVERT_TZ(c.t, '+00:00', '-05:00'), '%H:%i') AS Hora, c.n AS Orden FROM (
        SELECT 'salida' AS hito, MIN(e.timestamp_utc) AS t, 1 AS n FROM evento_campo e JOIN tabla_maestra m ON m.Descripcion = 'TIPO_EVENTO_CAMPO' AND m.IdEmpresa = 1 AND m.Num1 = e.id_tipo_evento
          WHERE e.id_os = p_id_os AND e.eliminado_en IS NULL AND e.timestamp_utc >= v_ini_utc AND m.String2 = 'SALIDA_BASE'
        UNION ALL SELECT 'pre_llegada', v_pre_utc, 2
        UNION ALL SELECT 'llegada', MIN(e.timestamp_utc), 3 FROM evento_campo e JOIN tabla_maestra m ON m.Descripcion = 'TIPO_EVENTO_CAMPO' AND m.IdEmpresa = 1 AND m.Num1 = e.id_tipo_evento
          WHERE e.id_os = p_id_os AND e.eliminado_en IS NULL AND e.timestamp_utc >= v_ini_utc AND m.String2 = 'LLEGADA'
    ) c ORDER BY c.n;

    SELECT d.latitud AS Latitud, d.longitud AS Longitud, DATE_FORMAT(d.fecha_registro, '%H:%i') AS Hora, d.tipo AS Fase,
           COALESCE(m.String1, 'Demora') AS Motivo, d.duracion_minutos AS DuracionMin
    FROM demora_registro d
    LEFT JOIN tabla_maestra m ON m.Descripcion = 'MOTIVO_DEMORA_RUTA' AND m.IdEmpresa = 1 AND m.Num1 = d.id_motivo
    WHERE d.id_os = p_id_os AND d.eliminado_en IS NULL AND d.latitud IS NOT NULL AND d.longitud IS NOT NULL
      AND d.fecha_registro >= CONVERT_TZ(v_ini_utc, '+00:00', '-05:00')
    ORDER BY d.fecha_registro, d.id_demora;

    CALL SP_LimpiarSeguimientoOperativo();
END$$

DELIMITER ;

-- ============================================================
-- SP_ObtenerRutaServicioJefaturaMovil  (App Mobile HU-30 — "Ubicación y ruta" de un servicio · solo lectura)
-- Posición y recorrido GPS del técnico en un servicio de HOY dentro del alcance del jefe (SP_ResolverJefaturaMovil + SP_ArmarAlcanceJefaturaMovil), con la
-- demora registrada por el técnico y los eventos en ruta. Datos del motor de Seguimiento Operativo (HU-51): ubicacion_tecnico, evento_campo, demora_registro.
-- Resultados: 1 mensaje · 2 resumen (1 fila) · 3 recorrido GPS (máx. 120 puntos, en orden) · 4 eventos en ruta (cronológicos).
--   Resumen: lat/lon = última posición; minutos_ubicacion = antigüedad de esa posición; destino_* = planta del cliente (sede); origen_* = coordenada del evento de
--     salida (si la app la envió). distancia_m = distancia EN LÍNEA RECTA de la última posición a la planta (no es la distancia por calle).
--     velocidad_kmh = entre las dos últimas posiciones de hoy (solo si distan entre 20 s y 10 min; NULL si no hay datos suficientes).
--     eta_estimada / eta_minutos = estimación en ruta desde la posición actual (línea recta × 1,3 a la velocidad promedio configurada; referencial). destino_direccion = dirección de la planta.
--     eta (HH:MM) = solo en ruta: la hora de llegada recalculada por la última demora de la app (demora_registro.eta_recalculada) o, si no hay, la hora esperada de
--     la bandeja de seguimiento (hora programada + demoras en ruta). eta_programada = hora programada del servicio.
--     demora_* = la última demora/incidencia de hoy (texto armado para la tarjeta amarilla). contacto_* = contacto en planta del cliente (para avisarle).
--   Eventos: tono (verde · naranja · amarillo): hito del técnico (OK) · demora (+N MIN) · alerta automática de la bandeja (ALERTA).
-- Requiere las migraciones 90 a 92 y 97.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerRutaServicioJefaturaMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerRutaServicioJefaturaMovil(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT
)
proc: BEGIN
    DECLARE v_area        VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_sede        VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_aut_area    VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_aut_general TINYINT DEFAULT 0;
    DECLARE v_existe      INT DEFAULT 0;
    DECLARE v_ini_utc     DATETIME;
    DECLARE v_ahora_utc   DATETIME;
    DECLARE v_tec         BIGINT;
    DECLARE v_la1 DECIMAL(10,7) DEFAULT NULL;
    DECLARE v_lo1 DECIMAL(10,7) DEFAULT NULL;
    DECLARE v_t1  DATETIME      DEFAULT NULL;
    DECLARE v_la2 DECIMAL(10,7) DEFAULT NULL;
    DECLARE v_lo2 DECIMAL(10,7) DEFAULT NULL;
    DECLARE v_t2  DATETIME      DEFAULT NULL;
    DECLARE v_dt_seg  INT DEFAULT NULL;
    DECLARE v_dist_m  DOUBLE DEFAULT NULL;
    DECLARE v_kmh     DECIMAL(6,1) DEFAULT NULL;
    DECLARE v_dem_txt VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_dem_org VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_jf_alc;
        DROP TEMPORARY TABLE IF EXISTS tmp_jf_ev;
        CALL SP_LimpiarSeguimientoOperativo();
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_os, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El servicio indicado no es válido.' AS Mensaje;
        LEAVE proc;
    END IF;
    CALL SP_ResolverJefaturaMovil(p_id_usuario, v_area, v_sede, v_aut_area, v_aut_general);
    IF v_area IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Tu cargo no tiene el menú de Jefatura.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_ArmarSeguimientoOperativo();
    CALL SP_ArmarAlcanceJefaturaMovil(v_area, p_id_os);
    SELECT COUNT(*) INTO v_existe FROM tmp_sg_os o JOIN tmp_jf_alc a ON a.id_os = o.id_os WHERE o.id_os = p_id_os;
    IF v_existe = 0 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_jf_alc;
        CALL SP_LimpiarSeguimientoOperativo();
        SELECT 1 AS IdTipoMensaje, 'El servicio no existe, no es de hoy o no pertenece a tu área.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT ini_utc, ahora_utc INTO v_ini_utc, v_ahora_utc FROM tmp_sg_cfg LIMIT 1;
    SELECT id_tecnico INTO v_tec FROM tmp_sg_os WHERE id_os = p_id_os;

    -- Velocidad: entre las dos últimas posiciones del técnico en este servicio (hoy)
    SELECT x.latitud, x.longitud, x.timestamp_utc INTO v_la1, v_lo1, v_t1
    FROM   ubicacion_tecnico x
    WHERE  x.id_usuario = v_tec AND x.timestamp_utc >= v_ini_utc AND x.timestamp_utc <= v_ahora_utc AND (x.id_os IS NULL OR x.id_os = p_id_os)
    ORDER BY x.timestamp_utc DESC, x.id_ubicacion DESC LIMIT 1;
    SELECT x.latitud, x.longitud, x.timestamp_utc INTO v_la2, v_lo2, v_t2
    FROM   ubicacion_tecnico x
    WHERE  x.id_usuario = v_tec AND x.timestamp_utc >= v_ini_utc AND x.timestamp_utc <= v_ahora_utc AND (x.id_os IS NULL OR x.id_os = p_id_os)
    ORDER BY x.timestamp_utc DESC, x.id_ubicacion DESC LIMIT 1 OFFSET 1;
    IF v_t1 IS NOT NULL AND v_t2 IS NOT NULL THEN
        SET v_dt_seg = TIMESTAMPDIFF(SECOND, v_t2, v_t1);
        IF v_dt_seg BETWEEN 20 AND 600 THEN
            SET v_dist_m = 6371000 * 2 * ASIN(SQRT(POW(SIN(RADIANS(v_la1 - v_la2) / 2), 2)
                                                 + COS(RADIANS(v_la2)) * COS(RADIANS(v_la1)) * POW(SIN(RADIANS(v_lo1 - v_lo2) / 2), 2)));
            SET v_kmh = ROUND(v_dist_m / v_dt_seg * 3.6, 1);
        END IF;
    END IF;

    -- Eventos en ruta: hitos del técnico, demoras/incidencias y alertas automáticas de este servicio
    DROP TEMPORARY TABLE IF EXISTS tmp_jf_ev;
    CREATE TEMPORARY TABLE tmp_jf_ev (
        id      INT NOT NULL AUTO_INCREMENT,
        hora    DATETIME,
        titulo  VARCHAR(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        detalle VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        badge   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        tono    VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        PRIMARY KEY (id)
    );
    INSERT INTO tmp_jf_ev (hora, titulo, detalle, badge, tono)
    SELECT CONVERT_TZ(e.timestamp_utc, '+00:00', '-05:00'), m.String1,
           IF(e.latitud IS NULL, NULL, CONCAT('GPS ', ROUND(e.latitud, 2), ', ', ROUND(e.longitud, 2))), 'OK', 'verde'
    FROM   evento_campo e
    JOIN   tabla_maestra m ON m.Descripcion = 'TIPO_EVENTO_CAMPO' AND m.IdEmpresa = 1 AND m.Num1 = e.id_tipo_evento
    WHERE  e.id_os = p_id_os AND e.eliminado_en IS NULL AND e.timestamp_utc >= v_ini_utc AND m.String2 IN ('SALIDA_BASE', 'EN_RUTA', 'LLEGADA', 'INGRESO_PLANTA');
    INSERT INTO tmp_jf_ev (hora, titulo, detalle, badge, tono)
    SELECT i.fecha, LEFT(CONCAT(CASE i.fase WHEN 'llegada' THEN 'Demora registrada' WHEN 'ingreso' THEN 'Demora en ingreso a planta' ELSE i.tipo END), 120),
           LEFT(IFNULL(NULLIF(i.descripcion, ''), i.tipo), 300),
           IF(i.duracion_min IS NULL, 'DEMORA', CONCAT('+', i.duracion_min, ' MIN')), IF(i.impacto = 'detiene', 'rojo', 'naranja')
    FROM   tmp_sg_inc i WHERE i.id_os = p_id_os;
    INSERT INTO tmp_jf_ev (hora, titulo, detalle, badge, tono)
    SELECT DATE_SUB(c.ahora, INTERVAL IFNULL(a.minutos, 0) MINUTE), a.titulo, a.detalle, 'ALERTA', 'amarillo'
    FROM   tmp_sg_alerta a JOIN tmp_sg_cfg c
    WHERE  a.id_os = p_id_os AND a.tipo <> 'proximidad';

    -- Última demora/incidencia de hoy (se precalcula: una tabla temporal no puede abrirse dos veces en la misma consulta)
    SELECT LEFT(CONCAT(CASE i.fase WHEN 'llegada' THEN 'Llegada a planta' WHEN 'ingreso' THEN 'Ingreso a planta' ELSE i.tipo END,
                       IF(i.duracion_min IS NULL, '', CONCAT(' · +', i.duracion_min, ' min')),
                       IF(IFNULL(i.descripcion, '') = '', '', CONCAT(' · "', i.descripcion, '"')),
                       ' · Impacto: ', IF(i.impacto = 'detiene', 'detiene el servicio', 'retrasa el servicio')), 300),
           IF(i.origen = 'asistente', 'asistente', 'tecnico')
    INTO   v_dem_txt, v_dem_org
    FROM   tmp_sg_inc i WHERE i.id_os = p_id_os ORDER BY i.fecha DESC LIMIT 1;

    SELECT 2 AS IdTipoMensaje, 'OK' AS Mensaje;

    -- 2 Resumen
    SELECT o.id_os AS id_os, o.numero AS numero, o.razon_social AS cliente, o.estado_seg AS estado,
           o.id_tecnico AS id_tecnico, o.tecnico AS tecnico, NULLIF(TRIM(ut.telefono), '') AS telefono_tecnico,
           p.lat AS latitud, p.lon AS longitud,
           IF(p.ts_utc IS NULL, NULL, GREATEST(0, TIMESTAMPDIFF(MINUTE, p.ts_utc, c.ahora_utc))) AS minutos_ubicacion,
           v_kmh AS velocidad_kmh, o.dist_m AS distancia_m,
           o.lat_sede AS destino_latitud, o.lon_sede AS destino_longitud,
           COALESCE(NULLIF(o.sede_nombre, ''), NULLIF(o.sede_direccion, '')) AS destino_nombre,
           (SELECT e.latitud FROM evento_campo e JOIN tabla_maestra m ON m.Descripcion = 'TIPO_EVENTO_CAMPO' AND m.IdEmpresa = 1 AND m.Num1 = e.id_tipo_evento AND m.String2 = 'SALIDA_BASE'
             WHERE e.id_os = o.id_os AND e.eliminado_en IS NULL AND e.latitud IS NOT NULL AND e.timestamp_utc >= c.ini_utc ORDER BY e.id_evento LIMIT 1) AS origen_latitud,
           (SELECT e.longitud FROM evento_campo e JOIN tabla_maestra m ON m.Descripcion = 'TIPO_EVENTO_CAMPO' AND m.IdEmpresa = 1 AND m.Num1 = e.id_tipo_evento AND m.String2 = 'SALIDA_BASE'
             WHERE e.id_os = o.id_os AND e.eliminado_en IS NULL AND e.latitud IS NOT NULL AND e.timestamp_utc >= c.ini_utc ORDER BY e.id_evento LIMIT 1) AS origen_longitud,
           IF(o.fase = 'en_ruta', DATE_FORMAT(COALESCE((SELECT MAX(d.eta_recalculada) FROM demora_registro d
                                                          WHERE d.id_os = o.id_os AND d.tipo = 'llegada' AND d.eliminado_en IS NULL AND d.fecha_registro >= c.hoy), h.esperado), '%H:%i'), NULL) AS eta,
           TIME_FORMAT(o.hora_inicio, '%H:%i') AS eta_programada,
           o.eta_min AS eta_minutos, DATE_FORMAT(o.eta_est, '%H:%i') AS eta_estimada, NULLIF(o.sede_direccion, '') AS destino_direccion,
           v_dem_txt AS demora_texto, v_dem_org AS demora_origen,
           cc.nombres AS contacto_nombre, NULLIF(TRIM(cc.telefono_movil), '') AS contacto_telefono,
           DATE_FORMAT(c.ahora, '%H:%i') AS actualizado
    FROM   tmp_sg_os o
    JOIN   tmp_sg_cfg c
    JOIN   orden_servicio osr ON osr.id_os = o.id_os
    LEFT JOIN tmp_sg_pos  p ON p.id_usuario = o.id_tecnico
    LEFT JOIN tmp_sg_hito h ON h.id_os = o.id_os
    LEFT JOIN usuario ut ON ut.id_usuario = o.id_tecnico
    LEFT JOIN contacto_cliente cc ON cc.id_contacto = osr.id_contacto AND cc.SoftDelete = 0
    WHERE  o.id_os = p_id_os;

    -- 3 Recorrido GPS (hasta 120 puntos repartidos en todo el trayecto)
    SELECT t.latitud AS latitud, t.longitud AS longitud, DATE_FORMAT(CONVERT_TZ(t.timestamp_utc, '+00:00', '-05:00'), '%H:%i') AS hora
    FROM (SELECT x.latitud, x.longitud, x.timestamp_utc,
                 ROW_NUMBER() OVER (ORDER BY x.timestamp_utc, x.id_ubicacion) AS rn,
                 COUNT(*) OVER () AS n
          FROM   ubicacion_tecnico x
          WHERE  x.id_usuario = v_tec AND x.timestamp_utc >= v_ini_utc AND x.timestamp_utc <= v_ahora_utc AND (x.id_os IS NULL OR x.id_os = p_id_os)) t
    WHERE  t.n <= 120 OR MOD(t.rn, CEIL(t.n / 120)) = 0 OR t.rn = t.n
    ORDER BY t.rn;

    -- 4 Eventos en ruta
    SELECT DATE_FORMAT(ev.hora, '%H:%i') AS hora, ev.titulo AS titulo, ev.detalle AS detalle, ev.badge AS badge, ev.tono AS tono
    FROM   tmp_jf_ev ev ORDER BY ev.hora, ev.id;

    DROP TEMPORARY TABLE IF EXISTS tmp_jf_ev;
    DROP TEMPORARY TABLE IF EXISTS tmp_jf_alc;
    CALL SP_LimpiarSeguimientoOperativo();
END$$

DELIMITER ;

SELECT os.numero AS os, s.nombre AS sede_de_la_os, s.latitud AS lat_os, s.longitud AS lon_os, s2.nombre AS sede_del_rq, s2.latitud AS lat_rq, s2.longitud AS lon_rq, os.latitud_llegada AS lat_llegada FROM orden_servicio os LEFT JOIN sede s ON s.id_sede = os.id_sede LEFT JOIN requerimiento rq ON rq.id_requerimiento = os.id_requerimiento LEFT JOIN sede s2 ON s2.id_sede = rq.id_sede WHERE os.numero = 'OS-000007';
