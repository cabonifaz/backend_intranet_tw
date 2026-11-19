-- ============================================================
-- SP_ObtenerHorasTecnicoMovil  (App Mobile HU-36 — «Ver las horas contabilizadas» de un técnico: calendario del mes, total mensual e historial · lectura con consolidación perezosa)
-- Antes de leer consolida el historial del técnico (SP_ConsolidarHorasTecnicoMovil, idempotente): el mes pedido, el mes actual y los meses anteriores con servicios que aún no tienen resumen
-- (últimos 24 meses). Un mes pasado queda guardado y cerrado: su historial no cambia aunque la fuente cambie después. Las horas son las del tiempo en servicio (inicio → fin del servicio, hora de Lima).
-- Alcance: el técnico debe estar en el equipo del jefe (SP_ArmarEquipoJefaturaMovil: regla Área + Rol); si no → «El técnico no pertenece a tu equipo.».
-- p_mes: 'AAAA-MM' (NULL o vacío = el mes actual de Lima). No puede ser futuro ni de hace más de 24 meses.
-- Resultados: 1 mensaje · 2 técnico (1 fila; igual que la lista) · 3 resumen del mes (1 fila: mes, total_minutos, dias_trabajados, servicios, cerrado) · 4 días con datos (fecha, minutos, servicios,
--   inicio y fin HH:mm del día, sin_cierre) · 5 detalle por servicio de esos días (fecha, id_os, numero, inicio, fin, minutos, sin_cierre) · 6 historial (mes AAAA-MM, minutos, dias_trabajados,
--   servicios, cerrado; los meses con datos, el más reciente primero, máx. 24).
--   Las semanas (acumulado semanal) las arma la API a partir de los días: la semana es lunes a domingo y cuenta solo los días del mes.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerHorasTecnicoMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerHorasTecnicoMovil(
    IN p_id_usuario BIGINT,
    IN p_id_tecnico BIGINT,
    IN p_mes        VARCHAR(7) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_sin_menu   TINYINT DEFAULT 0;
    DECLARE v_existe     INT DEFAULT 0;
    DECLARE v_hoy        DATE;
    DECLARE v_mes_actual DATE;
    DECLARE v_mes        DATE;
    DECLARE v_mes_min    DATE;
    DECLARE v_pend       DATE DEFAULT NULL;
    DECLARE v_prev       DATE DEFAULT '1900-01-01';
    DECLARE v_texto      VARCHAR(7) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_eq;
        DROP TEMPORARY TABLE IF EXISTS tmp_hm_pend;
        DROP TEMPORARY TABLE IF EXISTS tmp_ssoma_in;
        CALL SP_LimpiarSsomaProgramacion();
        CALL SP_LimpiarSeguimientoOperativo();
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0
       OR NOT EXISTS (SELECT 1 FROM usuario u WHERE u.id_usuario = p_id_usuario AND u.eliminado_en IS NULL AND u.estado = 'activo') THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no válido.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF IFNULL(p_id_tecnico, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El técnico indicado no es válido.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_hoy        = DATE(CONVERT_TZ(UTC_TIMESTAMP(), '+00:00', '-05:00'));
    SET v_mes_actual = DATE_SUB(v_hoy, INTERVAL DAYOFMONTH(v_hoy) - 1 DAY);
    SET v_mes_min    = DATE_SUB(v_mes_actual, INTERVAL 23 MONTH);
    SET v_texto      = TRIM(IFNULL(p_mes, ''));

    IF v_texto = '' THEN
        SET v_mes = v_mes_actual;
    ELSEIF v_texto REGEXP '^[0-9]{4}-(0[1-9]|1[0-2])$' THEN
        SET v_mes = STR_TO_DATE(CONCAT(v_texto, '-01'), '%Y-%m-%d');
    ELSE
        SELECT 1 AS IdTipoMensaje, 'El mes no es válido: usa el formato AAAA-MM.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_mes IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'El mes no es válido: usa el formato AAAA-MM.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_mes > v_mes_actual THEN
        SELECT 1 AS IdTipoMensaje, 'No hay horas de un mes futuro.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_mes < v_mes_min THEN
        SELECT 1 AS IdTipoMensaje, 'Solo se guarda el historial de los últimos 24 meses.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Alcance: el técnico debe ser del equipo del jefe
    CALL SP_ArmarEquipoJefaturaMovil(p_id_usuario, p_id_tecnico, 1, v_sin_menu);
    IF v_sin_menu = 1 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_eq;
        CALL SP_LimpiarSeguimientoOperativo();
        SELECT 1 AS IdTipoMensaje, 'Tu cargo no tiene el menú de Jefatura.' AS Mensaje;
        LEAVE proc;
    END IF;
    SELECT COUNT(*) INTO v_existe FROM tmp_eq;
    IF v_existe = 0 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_eq;
        CALL SP_LimpiarSeguimientoOperativo();
        SELECT 1 AS IdTipoMensaje, 'El técnico no pertenece a tu equipo.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Consolidación perezosa: el mes pedido, el mes actual y los meses con servicios que aún no tienen resumen
    CALL SP_ConsolidarHorasTecnicoMovil(p_id_tecnico, v_mes);
    IF v_mes <> v_mes_actual THEN
        CALL SP_ConsolidarHorasTecnicoMovil(p_id_tecnico, v_mes_actual);
    END IF;

    DROP TEMPORARY TABLE IF EXISTS tmp_hm_pend;
    CREATE TEMPORARY TABLE tmp_hm_pend (mes DATE NOT NULL, PRIMARY KEY (mes));
    INSERT IGNORE INTO tmp_hm_pend (mes)
    SELECT DISTINCT DATE_SUB(DATE(CONVERT_TZ(e.timestamp_utc, '+00:00', '-05:00')), INTERVAL DAYOFMONTH(DATE(CONVERT_TZ(e.timestamp_utc, '+00:00', '-05:00'))) - 1 DAY)
    FROM   evento_campo e
    JOIN   tabla_maestra t ON t.Descripcion = 'TIPO_EVENTO_CAMPO' AND t.IdEmpresa = 1 AND t.Num1 = e.id_tipo_evento AND t.String2 = 'INICIO_TRABAJO'
    JOIN   orden_servicio os ON os.id_os = e.id_os AND os.eliminado_en IS NULL
    WHERE  e.eliminado_en IS NULL
      AND  e.timestamp_utc >= CONVERT_TZ(TIMESTAMP(v_mes_min), '-05:00', '+00:00')
      AND  (os.id_tecnico_principal = p_id_tecnico
            OR EXISTS (SELECT 1 FROM os_personal op WHERE op.id_os = os.id_os AND op.id_usuario = p_id_tecnico AND op.eliminado_en IS NULL));
    DELETE FROM tmp_hm_pend
    WHERE  mes IN (SELECT m.mes FROM tecnico_horas_mes m WHERE m.id_usuario = p_id_tecnico AND m.eliminado_en IS NULL);

    pendientes: LOOP
        SELECT MIN(p.mes) INTO v_pend FROM tmp_hm_pend p WHERE p.mes > v_prev;
        IF v_pend IS NULL THEN LEAVE pendientes; END IF;
        SET v_prev = v_pend;
        IF v_pend <> v_mes AND v_pend <> v_mes_actual THEN
            CALL SP_ConsolidarHorasTecnicoMovil(p_id_tecnico, v_pend);
        END IF;
    END LOOP pendientes;
    DROP TEMPORARY TABLE IF EXISTS tmp_hm_pend;

    -- ── Resultados ─────────────────────────────────────────────────────────────────────────────────────────────────
    SELECT 2 AS IdTipoMensaje, 'OK' AS Mensaje;

    -- 2 Técnico
    SELECT e.id_usuario, e.nombre, e.iniciales, e.cargo, e.estado, e.detalle, e.hora_inicio, e.min_tardanza AS minutos_tardanza,
           e.id_os, e.numero_os, e.tipo_os, e.estado_servicio, e.lugar, e.motivo_sin AS motivo_sin_servicio,
           e.latitud, e.longitud, e.min_ubic AS minutos_ubicacion
    FROM   tmp_eq e;

    -- 3 Resumen del mes
    SELECT DATE_FORMAT(v_mes, '%Y-%m')                     AS mes,
           IFNULL(m.minutos, 0)                            AS total_minutos,
           IFNULL(m.dias_trabajados, 0)                    AS dias_trabajados,
           IFNULL(m.n_servicios, 0)                        AS servicios,
           IFNULL(m.cerrado, IF(v_mes < v_mes_actual, 1, 0)) AS cerrado
    FROM   (SELECT 1 AS uno) x
    LEFT JOIN tecnico_horas_mes m ON m.id_usuario = p_id_tecnico AND m.mes = v_mes AND m.eliminado_en IS NULL;

    -- 4 Días del mes con datos
    SELECT DATE_FORMAT(d.fecha, '%Y-%m-%d')                                           AS fecha,
           d.minutos                                                                  AS minutos,
           d.n_servicios                                                              AS servicios,
           IF(d.inicio_min IS NULL, NULL, TIME_FORMAT(SEC_TO_TIME(d.inicio_min * 60), '%H:%i')) AS inicio,
           IF(d.fin_min IS NULL, NULL, TIME_FORMAT(SEC_TO_TIME(d.fin_min * 60), '%H:%i'))       AS fin,
           d.sin_cierre                                                               AS sin_cierre
    FROM   tecnico_horas_dia d
    WHERE  d.id_usuario = p_id_tecnico AND d.fecha BETWEEN v_mes AND LAST_DAY(v_mes) AND d.eliminado_en IS NULL
    ORDER BY d.fecha;

    -- 5 Detalle por servicio
    SELECT DATE_FORMAT(s.fecha, '%Y-%m-%d')           AS fecha,
           s.id_os                                    AS id_os,
           s.numero                                   AS numero,
           DATE_FORMAT(s.inicio_dt, '%H:%i')          AS inicio,
           IF(s.fin_dt IS NULL, NULL, IF(s.fin_dt >= DATE_ADD(s.fecha, INTERVAL 1 DAY), '24:00', DATE_FORMAT(s.fin_dt, '%H:%i'))) AS fin,
           s.minutos                                  AS minutos,
           s.sin_cierre                               AS sin_cierre
    FROM   tecnico_horas_servicio s
    WHERE  s.id_usuario = p_id_tecnico AND s.fecha BETWEEN v_mes AND LAST_DAY(v_mes) AND s.eliminado_en IS NULL
    ORDER BY s.fecha, s.inicio_dt, s.id_os;

    -- 6 Historial de meses (con datos, el más reciente primero)
    SELECT DATE_FORMAT(m.mes, '%Y-%m') AS mes, m.minutos AS minutos, m.dias_trabajados AS dias_trabajados, m.n_servicios AS servicios, m.cerrado AS cerrado
    FROM   tecnico_horas_mes m
    WHERE  m.id_usuario = p_id_tecnico AND m.eliminado_en IS NULL AND m.mes >= v_mes_min AND (m.minutos > 0 OR m.n_servicios > 0)
    ORDER BY m.mes DESC
    LIMIT 24;

    DROP TEMPORARY TABLE IF EXISTS tmp_eq;
    CALL SP_LimpiarSeguimientoOperativo();
END$$

DELIMITER ;
