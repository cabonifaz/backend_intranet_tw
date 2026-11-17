-- Ensayo y calibración con error crítico: sale en Alertas críticas y en Demoras / Incidencias con su detalle. Ejecutar con Alt+X (No al aviso), redesplegar la API y recargar la intranet.
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
--   perdida_contacto (crítica) · gps_parado (advertencia) · sin_movimiento (crítica, HU-20) · ensayo_critico (crítica: ensayo guardado con error crítico, sin revisión del jefe) · autorizacion_salida (crítica: el técnico pidió autorización para iniciar el traslado y el encargado aún no responde) · sin_ingreso_post_llegada (advertencia) · sin_iniciar_servicio (advertencia)
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
           (SELECT COUNT(*) FROM os_equipo e WHERE e.id_os = os.id_os AND e.eliminado_en IS NULL AND EXISTS (SELECT 1 FROM vw_objetivo_visible vv WHERE vv.id_os_equipo = e.id)),
           (SELECT COUNT(*) FROM os_equipo e WHERE e.id_os = os.id_os AND e.eliminado_en IS NULL AND EXISTS (SELECT 1 FROM vw_objetivo_visible vv WHERE vv.id_os_equipo = e.id) AND e.estado_ejecucion = 'ejecutado'),
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

    -- Ensayo y calibración guardado con error crítico y sin revisión del jefe (crítica: sale en «Alertas críticas»). La notificación al encargado ya la crea SP_GuardarEnsayosMovil.
    INSERT INTO tmp_sg_alerta
    SELECT CONCAT('ensayo_critico:', it.id_informe), 'ensayo_critico', 'critica', 'Ensayo con error crítico',
           LEFT(CONCAT(IFNULL(TRIM(CONCAT(u.nombre, ' ', u.apellido)), 'Técnico'), ' · ', o.numero, IFNULL(CONCAT(' · ', ec.codigo_tw), '')), 200),
           GREATEST(0, TIMESTAMPDIFF(MINUTE, COALESCE(it.error_critico_notificado_en, it.ensayos_finalizado_en, it.modificado_en, it.creado_en), NOW())), it.id_tecnico, TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))), o.id_os, o.numero
    FROM informe_tecnico it
    JOIN tmp_sg_os o ON o.id_os = it.id_os
    LEFT JOIN usuario u ON u.id_usuario = it.id_tecnico
    LEFT JOIN equipo_cliente ec ON ec.id_equipo = it.id_equipo
    WHERE it.eliminado_en IS NULL AND it.error_critico_motivo IS NOT NULL AND it.error_critico_revision IS NULL;

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
    -- Ensayo y calibración guardado con error crítico (clave 'c<id_informe>'): incidencia del técnico que detiene el servicio; el detalle (motivo y lecturas fuera del EMP) se ve al abrirla
    INSERT IGNORE INTO tmp_sg_inc
    SELECT CONCAT('c', it.id_informe), COALESCE(it.error_critico_notificado_en, it.ensayos_finalizado_en, it.modificado_en, it.creado_en), it.id_tecnico,
           TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))), UPPER(CONCAT(LEFT(IFNULL(u.nombre, '?'), 1), LEFT(IFNULL(u.apellido, ''), 1))),
           it.id_os, os.numero, c.razon_social, 'ENSAYO_ERROR', 'Ensayo con error crítico',
           LEFT(CONCAT(IFNULL(CONCAT(ec.codigo_tw, ' · '), ''), 'Motivo del técnico: ', it.error_critico_motivo, ' · ',
                       (SELECT COUNT(*) FROM informe_ensayo ie WHERE ie.id_informe = it.id_informe AND ie.critico = 1 AND ie.eliminado_en IS NULL), ' lectura(s) fuera del EMP'), 400),
           NULL, 'detiene', 'tecnico', NULL
    FROM informe_tecnico it
    JOIN orden_servicio os ON os.id_os = it.id_os
    JOIN cliente c ON c.id_cliente = os.id_cliente
    LEFT JOIN usuario u ON u.id_usuario = it.id_tecnico
    LEFT JOIN equipo_cliente ec ON ec.id_equipo = it.id_equipo
    WHERE it.eliminado_en IS NULL AND it.error_critico_motivo IS NOT NULL
      AND COALESCE(it.error_critico_notificado_en, it.ensayos_finalizado_en, it.modificado_en, it.creado_en) >= v_hoy AND COALESCE(it.error_critico_notificado_en, it.ensayos_finalizado_en, it.modificado_en, it.creado_en) < DATE_ADD(v_hoy, INTERVAL 1 DAY);
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
        WHERE  a.tipo NOT IN ('autorizacion_salida', 'ensayo_critico')   -- sus notificaciones (críticas) ya las crean SP_SolicitarAutorizacionSalidaMovil y SP_GuardarEnsayosMovil
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

-- HU-52 (Sprint 5) Pestaña "Demoras / Incidencias" (solo de esta OS, de hoy): mini-KPIs, tabla y detalle de un registro. SOLO LECTURA.
-- p_clave (opcional): 'd<id>' demora, 'i<id>' incidencia, 'a<id>' demora registrada por el Asistente (HU-53) o 'c<id>' ensayo y calibración guardado con error crítico (motivo y lecturas fuera del EMP); con clave devuelve solo ese registro con la descripción completa y la foto.
-- Impacto: retrasa | detiene (incidencia crítica = detiene). Origen: tecnico | asistente. La tabla alimenta también la exportación CSV.
-- Momento (demoras de la app): "En ruta (llegar a planta)" o "Ingreso a planta"; Latitud/Longitud = GPS desde donde el técnico la registró.
-- Resultados: 1 mensaje · 2 KPIs (1 fila) · 3 filas.
DROP PROCEDURE IF EXISTS SP_ObtenerIncidenciasServicioRuta;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerIncidenciasServicioRuta(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT,
    IN p_clave      VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_msg VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        CALL SP_LimpiarSeguimientoOperativo();
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF NULLIF(p_clave, '') IS NOT NULL AND p_clave NOT REGEXP '^[diac][0-9]{1,18}$' THEN
        SELECT 1 AS IdTipoMensaje, 'El registro indicado no es válido.' AS Mensaje;
        LEAVE proc;
    END IF;
    CALL SP_PrepararDetalleServicioRuta(p_id_usuario, p_id_os, v_msg);
    IF v_msg IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje;
        LEAVE proc;
    END IF;
    IF NULLIF(p_clave, '') IS NOT NULL AND NOT EXISTS (SELECT 1 FROM tmp_sg_inc i WHERE i.id_os = p_id_os AND i.clave = p_clave) THEN
        CALL SP_LimpiarSeguimientoOperativo();
        SELECT 1 AS IdTipoMensaje, 'El registro no existe en este servicio.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'OK' AS Mensaje;
    SELECT COUNT(*) AS Total, IFNULL(SUM(impacto = 'retrasa'), 0) AS Retrasan, IFNULL(SUM(impacto = 'detiene'), 0) AS Detienen,
           IFNULL(SUM(origen = 'tecnico'), 0) AS PorTecnico, IFNULL(SUM(origen = 'asistente'), 0) AS PorAsistente
    FROM tmp_sg_inc WHERE id_os = p_id_os;

    SELECT i.clave AS Clave, DATE_FORMAT(i.fecha, '%H:%i') AS Hora, i.tipo_codigo AS TipoCodigo, i.tipo AS Tipo,
           IF(NULLIF(p_clave, '') IS NULL, i.descripcion, COALESCE(d.descripcion, n.descripcion, ra.descripcion, (SELECT CONCAT(IFNULL(CONCAT('Equipo ', ec.codigo_tw, CHAR(10)), ''), 'Motivo del técnico: ', it.error_critico_motivo,
                        IFNULL((SELECT CONCAT(CHAR(10), CHAR(10), 'Lecturas fuera del EMP:', CHAR(10),
                                       GROUP_CONCAT(CONCAT('• ', IF(ie.tipo = 'pesaje', 'Pesaje', 'Excentricidad'), ' · ', ie.punto,
                                                           IF(ie.tipo = 'excentricidad' AND ie.grupo IS NOT NULL, CONCAT(' (carga ', ie.grupo, ')'), ''),
                                                           ': carga ', IFNULL(TRIM(TRAILING '.' FROM TRIM(TRAILING '0' FROM CAST(ie.carga AS CHAR))), '-'), ' kg · lectura ', IFNULL(TRIM(TRAILING '.' FROM TRIM(TRAILING '0' FROM CAST(ie.lectura AS CHAR))), '-'), ' kg · error ', IFNULL(TRIM(TRAILING '.' FROM TRIM(TRAILING '0' FROM CAST(ie.error AS CHAR))), '-'),
                                                           ' kg · EMP ±', IFNULL(TRIM(TRAILING '.' FROM TRIM(TRAILING '0' FROM CAST(ie.tolerancia AS CHAR))), '-'), ' kg') ORDER BY ie.tipo, ie.orden SEPARATOR '\n'))
                                FROM informe_ensayo ie WHERE ie.id_informe = it.id_informe AND ie.critico = 1 AND ie.eliminado_en IS NULL), ''))
                 FROM informe_tecnico it LEFT JOIN equipo_cliente ec ON ec.id_equipo = it.id_equipo
                 WHERE i.clave = CONCAT('c', it.id_informe)), i.descripcion)) AS Descripcion,
           i.duracion_min AS DuracionMin, i.impacto AS Impacto, i.origen AS Origen, COALESCE((SELECT TRIM(CONCAT(ua.nombre, ' ', ua.apellido)) FROM usuario ua WHERE ua.id_usuario = ra.id_usuario), i.tecnico) AS Registrador,
           IF(NULLIF(p_clave, '') IS NULL, NULL, COALESCE(d.fotografia_url, ra.evidencia_url)) AS Evidencia, IF(COALESCE(d.fotografia_url, ra.evidencia_url) IS NULL, 0, 1) AS TieneEvidencia,
           CASE i.fase WHEN 'llegada' THEN 'En ruta (llegar a planta)' WHEN 'ingreso' THEN 'Ingreso a planta' END AS Momento,
           d.latitud AS Latitud, d.longitud AS Longitud
    FROM tmp_sg_inc i
    LEFT JOIN demora_registro d ON i.clave = CONCAT('d', d.id_demora)
    LEFT JOIN incidencia_operativa n ON i.clave = CONCAT('i', n.id_incidencia)
    LEFT JOIN registro_asistente ra ON i.clave = CONCAT('a', ra.id_registro)
    WHERE i.id_os = p_id_os AND (NULLIF(p_clave, '') IS NULL OR i.clave = p_clave)
    ORDER BY i.fecha DESC, i.clave;

    CALL SP_LimpiarSeguimientoOperativo();
END$$

DELIMITER ;
