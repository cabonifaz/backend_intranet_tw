-- ============================================================
-- SP_ConsolidarHorasTecnicoMovil  (App Mobile HU-36 — «Ver las horas contabilizadas»: consolida el historial de horas de UN técnico en UN mes · apoyo, NO es un endpoint · escritura idempotente)
-- Calcula las horas laboradas por día «desde que inicia el servicio hasta que finaliza el servicio» y las GUARDA (migración 123): tecnico_horas_dia, tecnico_horas_servicio y el resumen del mes
-- en tecnico_horas_mes. Se invoca de forma perezosa al leer las horas (SP_ObtenerHorasTecnicoMovil), así funciona sin worker.
--
-- FUENTE DE LAS HORAS (elegida por ser la más fiel al pedido «desde que inicia servicio hasta que finaliza su servicio»): los eventos de campo de cada OS/OM (evento_campo, los mismos que lee el
--   Seguimiento Operativo de la intranet):
--     INICIO · el evento INICIO_TRABAJO (lo registra SP_CambiarEstadoEquipoMovil con el primer «Iniciar» de un equipo de la OS, HU-07; también el cambio manual «inicio» del asistente).
--     FIN    · el PRIMER evento CIERRE posterior (lo registra la «Salida de planta» del Reloj marcador, SP_RegistrarMarcacionJornadaMovil, o el cambio manual «finalizado» del asistente). Si no hay
--              CIERRE pero la OS tiene orden_servicio.hora_fin_real del mismo día, se usa esa hora.
--   Se descartó orden_servicio.hora_llegada_real (es la llegada a planta, no el inicio del trabajo), la jornada (jornada_marcacion: es presencia en labores, incluye traslados y refrigerio) y
--   os_equipo (tramos por equipo: se solapan entre sí; la OS ya los resume en INICIO_TRABAJO → CIERRE).
-- Quién acumula: el técnico principal (orden_servicio.id_tecnico_principal) y el personal de apoyo (os_personal) de la OS.
-- Por día (hora de Lima, UTC-5): el tiempo es la UNIÓN de los servicios del día (si dos servicios se solapan, no se cuenta doble). Un servicio que cruza la medianoche se reparte entre los días (máx. 7).
-- CASOS BORDE: servicio iniciado y aún sin fin → si es de HOY se cuenta hasta ahora (en vivo); de un día anterior NO se inventa la duración: cuenta 0 minutos y el día queda marcado sin_cierre
--   (se recalcula mientras el mes esté abierto, por si el cierre llega después). Duraciones imposibles (fin antes del inicio o de más de 7 días) se tratan como sin_cierre.
-- QUÉ SE RECALCULA: los días sin fila, hoy, ayer y los marcados sin_cierre. Un día ya consolidado queda como foto. Un MES PASADO queda cerrado=1 y NO se vuelve a calcular (su historial no cambia aunque
--   la fuente cambie después). El mes actual se mantiene abierto.
-- p_mes: cualquier fecha del mes (se usa su primer día). Meses futuros: no hace nada. Sin resultados (el que llama lee las tablas).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ConsolidarHorasTecnicoMovil;

DELIMITER $$

CREATE PROCEDURE SP_ConsolidarHorasTecnicoMovil(
    IN p_id_tecnico BIGINT,
    IN p_mes        DATE
)
proc: BEGIN
    DECLARE v_ahora      DATETIME;
    DECLARE v_hoy        DATE;
    DECLARE v_ini        DATE;
    DECLARE v_fin        DATE;
    DECLARE v_mes_actual DATE;
    DECLARE v_ini_utc    DATETIME;
    DECLARE v_fin_utc    DATETIME;
    DECLARE v_cerrado    INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        DROP TEMPORARY TABLE IF EXISTS tmp_hd_ini;
        DROP TEMPORARY TABLE IF EXISTS tmp_hd_fin;
        DROP TEMPORARY TABLE IF EXISTS tmp_hd_tr;
        DROP TEMPORARY TABLE IF EXISTS tmp_hd_n;
        DROP TEMPORARY TABLE IF EXISTS tmp_hd_seg;
        DROP TEMPORARY TABLE IF EXISTS tmp_hd_g;
        DROP TEMPORARY TABLE IF EXISTS tmp_hd_dia;
        DROP TEMPORARY TABLE IF EXISTS tmp_hd_w;
        RESIGNAL;   -- el SP que llama devuelve el error (IdTipoMensaje 3)
    END;

    IF IFNULL(p_id_tecnico, 0) <= 0 OR p_mes IS NULL THEN
        LEAVE proc;
    END IF;

    SET v_ahora      = CONVERT_TZ(UTC_TIMESTAMP(), '+00:00', '-05:00');
    SET v_hoy        = DATE(v_ahora);
    SET v_ini        = DATE_SUB(p_mes, INTERVAL DAYOFMONTH(p_mes) - 1 DAY);
    SET v_mes_actual = DATE_SUB(v_hoy, INTERVAL DAYOFMONTH(v_hoy) - 1 DAY);
    IF v_ini > v_hoy THEN
        LEAVE proc;
    END IF;

    -- Un mes pasado ya consolidado es una foto: no se toca
    SELECT COUNT(*) INTO v_cerrado
    FROM   tecnico_horas_mes m
    WHERE  m.id_usuario = p_id_tecnico AND m.mes = v_ini AND m.cerrado = 1 AND m.eliminado_en IS NULL;
    IF v_cerrado > 0 THEN
        LEAVE proc;
    END IF;

    SET v_fin     = LEAST(LAST_DAY(v_ini), v_hoy);
    -- Ventana de eventos en UTC: desde 3 días antes (servicios que empezaron antes y cruzan al mes) hasta el día siguiente al último
    SET v_ini_utc = CONVERT_TZ(TIMESTAMP(DATE_SUB(v_ini, INTERVAL 3 DAY)), '-05:00', '+00:00');
    SET v_fin_utc = CONVERT_TZ(TIMESTAMP(DATE_ADD(v_fin, INTERVAL 1 DAY)), '-05:00', '+00:00');

    DROP TEMPORARY TABLE IF EXISTS tmp_hd_ini;
    DROP TEMPORARY TABLE IF EXISTS tmp_hd_fin;
    DROP TEMPORARY TABLE IF EXISTS tmp_hd_tr;
    DROP TEMPORARY TABLE IF EXISTS tmp_hd_n;
    DROP TEMPORARY TABLE IF EXISTS tmp_hd_seg;
    DROP TEMPORARY TABLE IF EXISTS tmp_hd_g;
    DROP TEMPORARY TABLE IF EXISTS tmp_hd_dia;
    DROP TEMPORARY TABLE IF EXISTS tmp_hd_w;

    -- 1) Inicio del servicio de cada OS/OM del técnico (INICIO_TRABAJO) dentro de la ventana
    CREATE TEMPORARY TABLE tmp_hd_ini AS
    SELECT os.id_os,
           os.numero,
           CONVERT_TZ(MIN(e.timestamp_utc), '+00:00', '-05:00') AS ini_dt,
           MAX(os.hora_fin_real)                               AS hora_fin_real
    FROM   evento_campo e
    JOIN   tabla_maestra t ON t.Descripcion = 'TIPO_EVENTO_CAMPO' AND t.IdEmpresa = 1 AND t.Num1 = e.id_tipo_evento AND t.String2 = 'INICIO_TRABAJO'
    JOIN   orden_servicio os ON os.id_os = e.id_os AND os.eliminado_en IS NULL
    WHERE  e.eliminado_en IS NULL AND e.timestamp_utc >= v_ini_utc AND e.timestamp_utc < v_fin_utc
      AND  (os.id_tecnico_principal = p_id_tecnico
            OR EXISTS (SELECT 1 FROM os_personal op WHERE op.id_os = os.id_os AND op.id_usuario = p_id_tecnico AND op.eliminado_en IS NULL))
    GROUP BY os.id_os, os.numero;

    -- 2) Fin: el primer CIERRE posterior al inicio
    CREATE TEMPORARY TABLE tmp_hd_fin AS
    SELECT i.id_os,
           CONVERT_TZ(MIN(e.timestamp_utc), '+00:00', '-05:00') AS fin_dt
    FROM   tmp_hd_ini i
    JOIN   evento_campo e ON e.id_os = i.id_os AND e.eliminado_en IS NULL
    JOIN   tabla_maestra t ON t.Descripcion = 'TIPO_EVENTO_CAMPO' AND t.IdEmpresa = 1 AND t.Num1 = e.id_tipo_evento AND t.String2 = 'CIERRE'
    WHERE  CONVERT_TZ(e.timestamp_utc, '+00:00', '-05:00') > i.ini_dt
    GROUP BY i.id_os;

    -- 3) Tramo de cada servicio: inicio, fin (evento CIERRE o hora_fin_real del mismo día; hoy sin cierre = hasta ahora) y si quedó sin cierre
    CREATE TEMPORARY TABLE tmp_hd_tr (
        id_os      BIGINT      NOT NULL,
        numero     VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        ini        DATETIME    NOT NULL,
        fin        DATETIME    NULL,
        sin_cierre TINYINT     NOT NULL DEFAULT 0,
        PRIMARY KEY (id_os)
    );
    INSERT INTO tmp_hd_tr (id_os, numero, ini, fin)
    SELECT i.id_os, i.numero, i.ini_dt,
           COALESCE(f.fin_dt,
                    IF(i.hora_fin_real IS NOT NULL AND TIMESTAMP(DATE(i.ini_dt), i.hora_fin_real) > i.ini_dt, TIMESTAMP(DATE(i.ini_dt), i.hora_fin_real), NULL))
    FROM   tmp_hd_ini i
    LEFT JOIN tmp_hd_fin f ON f.id_os = i.id_os;

    -- hoy y aún sin cierre: se cuenta hasta ahora; de un día anterior sin cierre: no se inventa (queda sin_cierre)
    UPDATE tmp_hd_tr SET fin = v_ahora WHERE fin IS NULL AND DATE(ini) = v_hoy;
    UPDATE tmp_hd_tr SET sin_cierre = 1, fin = NULL WHERE fin IS NULL OR fin <= ini OR TIMESTAMPDIFF(DAY, ini, fin) >= 7;

    -- 4) Un registro por servicio y día (recortado a cada día de Lima)
    CREATE TEMPORARY TABLE tmp_hd_n (n INT NOT NULL, PRIMARY KEY (n));
    INSERT INTO tmp_hd_n (n) VALUES (0), (1), (2), (3), (4), (5), (6);

    CREATE TEMPORARY TABLE tmp_hd_seg AS
    SELECT x.id_os, x.numero, x.dia, x.ini, x.fin, x.sin_cierre
    FROM (
        SELECT t.id_os, t.numero, t.sin_cierre,
               DATE_ADD(DATE(t.ini), INTERVAL n.n DAY) AS dia,
               GREATEST(t.ini, TIMESTAMP(DATE_ADD(DATE(t.ini), INTERVAL n.n DAY))) AS ini,
               IF(t.sin_cierre = 1, GREATEST(t.ini, TIMESTAMP(DATE_ADD(DATE(t.ini), INTERVAL n.n DAY))),
                  LEAST(t.fin, TIMESTAMP(DATE_ADD(DATE(t.ini), INTERVAL n.n + 1 DAY)))) AS fin
        FROM   tmp_hd_tr t
        JOIN   tmp_hd_n n ON (t.sin_cierre = 1 AND n.n = 0)
                          OR (t.sin_cierre = 0 AND TIMESTAMP(DATE_ADD(DATE(t.ini), INTERVAL n.n DAY)) < t.fin)
    ) x
    WHERE x.dia BETWEEN v_ini AND v_fin;

    -- 5) Unión de los servicios de cada día (sin doble conteo si se solapan): islas por día con una ventana
    CREATE TEMPORARY TABLE tmp_hd_g AS
    SELECT b.dia, MIN(b.ini) AS g_ini, MAX(b.fin) AS g_fin
    FROM (
        SELECT a.dia, a.ini, a.fin,
               SUM(a.nuevo) OVER (PARTITION BY a.dia ORDER BY a.ini, a.fin ROWS UNBOUNDED PRECEDING) AS grp
        FROM (
            SELECT s.dia, s.ini, s.fin,
                   IF(s.ini > IFNULL(MAX(s.fin) OVER (PARTITION BY s.dia ORDER BY s.ini, s.fin ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING),
                                     CAST('1000-01-01 00:00:00' AS DATETIME)), 1, 0) AS nuevo
            FROM   tmp_hd_seg s
            WHERE  s.fin > s.ini
        ) a
    ) b
    GROUP BY b.dia, b.grp;

    -- 6) Resumen por día
    CREATE TEMPORARY TABLE tmp_hd_dia AS
    SELECT a.dia,
           IFNULL(u.minutos, 0)  AS minutos,
           a.n_serv              AS n_serv,
           u.ini_min             AS ini_min,
           u.fin_min             AS fin_min,
           a.sin_cierre          AS sin_cierre
    FROM (SELECT s.dia, COUNT(DISTINCT s.id_os) AS n_serv, MAX(s.sin_cierre) AS sin_cierre FROM tmp_hd_seg s GROUP BY s.dia) a
    LEFT JOIN (SELECT g.dia,
                      CAST(ROUND(SUM(TIMESTAMPDIFF(SECOND, g.g_ini, g.g_fin)) / 60) AS SIGNED) AS minutos,
                      HOUR(MIN(g.g_ini)) * 60 + MINUTE(MIN(g.g_ini))                          AS ini_min,
                      IF(MAX(g.g_fin) >= DATE_ADD(g.dia, INTERVAL 1 DAY), 1440, HOUR(MAX(g.g_fin)) * 60 + MINUTE(MAX(g.g_fin))) AS fin_min
               FROM   tmp_hd_g g
               GROUP BY g.dia) u ON u.dia = a.dia;

    -- 7) Días a escribir: sin fila, hoy, ayer o marcados sin_cierre (los demás días del mes ya son foto)
    CREATE TEMPORARY TABLE tmp_hd_w AS
    SELECT d.dia, d.minutos, d.n_serv, d.ini_min, d.fin_min, d.sin_cierre
    FROM   tmp_hd_dia d
    LEFT JOIN tecnico_horas_dia x ON x.id_usuario = p_id_tecnico AND x.fecha = d.dia AND x.eliminado_en IS NULL
    WHERE  x.id_hora_dia IS NULL OR d.dia >= DATE_SUB(v_hoy, INTERVAL 1 DAY) OR x.sin_cierre = 1;

    INSERT INTO tecnico_horas_dia (id_usuario, fecha, minutos, n_servicios, inicio_min, fin_min, sin_cierre, calculado_en)
    SELECT p_id_tecnico, w.dia, w.minutos, w.n_serv, w.ini_min, w.fin_min, w.sin_cierre, UTC_TIMESTAMP()
    FROM   tmp_hd_w w
    ON DUPLICATE KEY UPDATE minutos = VALUES(minutos), n_servicios = VALUES(n_servicios), inicio_min = VALUES(inicio_min), fin_min = VALUES(fin_min),
                            sin_cierre = VALUES(sin_cierre), calculado_en = VALUES(calculado_en), eliminado_en = NULL, eliminado_por = NULL;

    -- Detalle por servicio de esos días: se reemplaza (los anteriores quedan dados de baja)
    UPDATE tecnico_horas_servicio s
    JOIN   tmp_hd_w w ON w.dia = s.fecha
    SET    s.eliminado_en = UTC_TIMESTAMP()
    WHERE  s.id_usuario = p_id_tecnico AND s.eliminado_en IS NULL;

    INSERT INTO tecnico_horas_servicio (id_usuario, fecha, id_os, numero, inicio_dt, fin_dt, minutos, sin_cierre)
    SELECT p_id_tecnico, g.dia, g.id_os, g.numero, g.ini,
           IF(g.sin_cierre = 1, NULL, g.fin),
           IF(g.sin_cierre = 1, 0, CAST(ROUND(TIMESTAMPDIFF(SECOND, g.ini, g.fin) / 60) AS SIGNED)),
           g.sin_cierre
    FROM   tmp_hd_seg g
    JOIN   tmp_hd_w w ON w.dia = g.dia
    ON DUPLICATE KEY UPDATE numero = VALUES(numero), inicio_dt = VALUES(inicio_dt), fin_dt = VALUES(fin_dt), minutos = VALUES(minutos), sin_cierre = VALUES(sin_cierre),
                            eliminado_en = NULL, eliminado_por = NULL;

    -- 8) Resumen del mes (se cierra cuando el mes ya pasó: queda como foto)
    INSERT INTO tecnico_horas_mes (id_usuario, mes, minutos, dias_trabajados, n_servicios, cerrado, calculado_en)
    SELECT p_id_tecnico, v_ini, IFNULL(SUM(d.minutos), 0), IFNULL(SUM(d.minutos > 0), 0), IFNULL(SUM(d.n_servicios), 0), IF(v_ini < v_mes_actual, 1, 0), UTC_TIMESTAMP()
    FROM   tecnico_horas_dia d
    WHERE  d.id_usuario = p_id_tecnico AND d.fecha BETWEEN v_ini AND LAST_DAY(v_ini) AND d.eliminado_en IS NULL
    HAVING COUNT(*) > 0
    ON DUPLICATE KEY UPDATE minutos = VALUES(minutos), dias_trabajados = VALUES(dias_trabajados), n_servicios = VALUES(n_servicios), cerrado = VALUES(cerrado),
                            calculado_en = VALUES(calculado_en), eliminado_en = NULL, eliminado_por = NULL;

    DROP TEMPORARY TABLE IF EXISTS tmp_hd_ini;
    DROP TEMPORARY TABLE IF EXISTS tmp_hd_fin;
    DROP TEMPORARY TABLE IF EXISTS tmp_hd_tr;
    DROP TEMPORARY TABLE IF EXISTS tmp_hd_n;
    DROP TEMPORARY TABLE IF EXISTS tmp_hd_seg;
    DROP TEMPORARY TABLE IF EXISTS tmp_hd_g;
    DROP TEMPORARY TABLE IF EXISTS tmp_hd_dia;
    DROP TEMPORARY TABLE IF EXISTS tmp_hd_w;
END$$

DELIMITER ;
