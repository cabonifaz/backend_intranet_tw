-- ============================================================
-- SP_ObtenerAgendaAreaMovil  (App Mobile HU-37 — «Agenda del Área»: semana, día y carga de los técnicos + conflictos · solo lectura)
-- El jefe consulta la programación de su equipo: la matriz técnico × día de la semana con cada servicio (OS u OM), la carga (horas y utilización) y el banner de conflictos de programación.
-- NO duplica reglas: lee las bases de la intranet —SP_ArmarBaseProgramacion (HU-35: servicios, sub-estado, asignaciones y cruces de horario), SP_ArmarConflictosProgramacion (HU-39: baja,
-- SSOMA vencido, solapamiento y extensión de duración) y, para la demora de HOY, SP_ArmarSeguimientoOperativo (HU-51)— y el equipo del alcance Área + Rol (SP_ArmarEquipoAgendaMovil).
-- Permiso: prog_bandeja (el mismo de la intranet). La agenda completa sigue en la intranet (Módulo 8): aquí se consulta y se hacen ajustes rápidos (SP_ResolverConflictoAgendaMovil).
-- p_desde: cualquier fecha de la semana que se quiere ver (NULL = la semana actual de Lima); se normaliza al LUNES. Rango: hasta 26 semanas antes o después de la semana actual.
-- Semana: de lunes a VIERNES; si algún técnico del alcance tiene servicios el sábado o el domingo, la semana llega hasta el DOMINGO (hasta = domingo).
-- Estado del servicio (contrato de la app), en este orden: conflicto (el servicio está en un conflicto de HU-39) · finalizado · demora (hoy con demora/incidencia en el seguimiento operativo, o la OS
--   pausada) · en_curso (en ruta, en ejecución o bloqueada) · confirmado (programado y confirmado por el cliente) · pendiente (falta la confirmación del cliente, o lo frena SSOMA / una solicitud de
--   reprogramación). El código corto del servicio son los dígitos del número, de 4 cifras («OS-000014» → 0014).
-- Carga por día: libre = 0 · baja < 6 h · óptima 6 a 8 · alta > 8 a 10 · sobrecarga > 10 h o servicios solapados (la regla de SP_ObtenerProgramacionesTecnicoDia y de la matriz de la intranet).
--   Utilización de la semana = horas / (HORAS_JORNADA × DIAS_LABORABLES_SEMANA; 8 × 6 = 48 h por defecto): sobrecarga > 100 % · alta ≥ 90 % · óptima ≥ 60 % · baja > 0 % · libre
--   (la regla de SP_ObtenerResumenProgramacion). Cuenta al técnico principal y al personal de apoyo.
-- Técnicos: los del alcance del jefe por nombre; los dados de baja solo si tienen servicios en la semana.
-- Resultados: 1 mensaje · 2 cabecera y KPIs (desde, hasta, conflictos —TODOS los del alcance, el número del menú—, servicios, sobrecargados, actualizado, refresco_segundos) · 3 técnicos ·
--   4 días (técnico × día: horas, nivel, conflicto) · 5 servicios (técnico × día) · 6 conflictos (modo: directa | solicitud | solo_lectura según el permiso).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerAgendaAreaMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerAgendaAreaMovil(
    IN p_id_usuario BIGINT,
    IN p_desde      DATE
)
proc: BEGIN
    DECLARE v_sin_menu   TINYINT DEFAULT 0;
    DECLARE v_hoy        DATE;
    DECLARE v_lunes_hoy  DATE;
    DECLARE v_lunes      DATE;
    DECLARE v_domingo    DATE;
    DECLARE v_hasta      DATE;
    DECLARE v_gestiona   TINYINT DEFAULT 0;
    DECLARE v_aprueba    TINYINT DEFAULT 0;
    DECLARE v_param      DECIMAL(18,6);
    DECLARE v_jornada    DECIMAL(8,2) DEFAULT 8;
    DECLARE v_capacidad  DECIMAL(8,2) DEFAULT 48;
    DECLARE v_conflictos INT DEFAULT 0;
    DECLARE v_servicios  INT DEFAULT 0;
    DECLARE v_sobrecarga INT DEFAULT 0;
    DECLARE v_refresco   INT DEFAULT 30;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SET @tw_eq_inactivos = 0;
        DROP TEMPORARY TABLE IF EXISTS tmp_eq;
        DROP TEMPORARY TABLE IF EXISTS tmp_ag_dem;
        DROP TEMPORARY TABLE IF EXISTS tmp_ag_dias;
        DROP TEMPORARY TABLE IF EXISTS tmp_ag_srv;
        DROP TEMPORARY TABLE IF EXISTS tmp_ag_dia;
        DROP TEMPORARY TABLE IF EXISTS tmp_ag_tec;
        CALL SP_LimpiarBaseProgramacion();
        CALL SP_LimpiarConflictosProgramacion();
        CALL SP_LimpiarSeguimientoOperativo();
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0
       OR NOT EXISTS (SELECT 1 FROM usuario u WHERE u.id_usuario = p_id_usuario AND u.eliminado_en IS NULL AND u.estado = 'activo') THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no válido.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF FN_PermisoAccion(p_id_usuario, 'prog_bandeja') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver la agenda de programación.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Semana pedida (siempre el lunes) y su rango
    SET v_hoy       = DATE(CONVERT_TZ(UTC_TIMESTAMP(), '+00:00', '-05:00'));
    SET v_lunes_hoy = DATE_SUB(v_hoy, INTERVAL WEEKDAY(v_hoy) DAY);
    SET v_lunes     = DATE_SUB(IFNULL(p_desde, v_hoy), INTERVAL WEEKDAY(IFNULL(p_desde, v_hoy)) DAY);
    IF ABS(DATEDIFF(v_lunes, v_lunes_hoy)) > 182 THEN
        SELECT 1 AS IdTipoMensaje, 'La semana pedida está fuera del rango (hasta 26 semanas antes o después de la actual).' AS Mensaje;
        LEAVE proc;
    END IF;
    SET v_domingo = DATE_ADD(v_lunes, INTERVAL 6 DAY);

    -- Alcance: el equipo del jefe (regla Área + Rol)
    CALL SP_ArmarEquipoAgendaMovil(p_id_usuario, NULL, v_sin_menu);
    IF v_sin_menu = 1 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_eq;
        SELECT 1 AS IdTipoMensaje, 'Tu cargo no tiene el menú de Jefatura.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_gestiona = FN_PermisoAccion(p_id_usuario, 'prog_gestionar');
    SET v_aprueba  = FN_PermisoAccion(p_id_usuario, 'prog_aprobar_reprogramacion');
    CALL SP_LeerParametroProgramacion('HORAS_JORNADA', 8, v_param);
    SET v_jornada  = IF(v_param BETWEEN 1 AND 24, v_param, 8);
    CALL SP_LeerParametroProgramacion('DIAS_LABORABLES_SEMANA', 6, v_param);
    SET v_capacidad = v_jornada * IF(v_param BETWEEN 1 AND 7, ROUND(v_param), 6);

    -- Bases de la intranet: programación de la semana (con los finalizados de la ventana) y conflictos sobrevenidos
    CALL SP_ArmarBaseProgramacion(v_lunes, v_domingo);
    CALL SP_ArmarConflictosProgramacion();

    -- Demora de HOY según el seguimiento operativo (solo si hoy está en la semana pedida)
    DROP TEMPORARY TABLE IF EXISTS tmp_ag_dem;
    CREATE TEMPORARY TABLE tmp_ag_dem (id_os BIGINT NOT NULL, PRIMARY KEY (id_os));
    IF v_hoy BETWEEN v_lunes AND v_domingo THEN
        CALL SP_ArmarSeguimientoOperativo();
        INSERT IGNORE INTO tmp_ag_dem (id_os) SELECT o.id_os FROM tmp_sg_os o WHERE o.estado_seg IN ('con_demora', 'con_incidente');
        CALL SP_LimpiarSeguimientoOperativo();
    END IF;

    -- Hasta: viernes; domingo si el equipo tiene servicios el sábado o el domingo
    IF EXISTS (SELECT 1 FROM tmp_prog_asig s JOIN tmp_eq e ON e.id_usuario = s.id_usuario
               WHERE s.fecha_ejecucion >= DATE_ADD(v_lunes, INTERVAL 5 DAY) AND s.fecha_ejecucion <= v_domingo) THEN
        SET v_hasta = v_domingo;
    ELSE
        SET v_hasta = DATE_ADD(v_lunes, INTERVAL 4 DAY);
    END IF;

    DROP TEMPORARY TABLE IF EXISTS tmp_ag_dias;
    CREATE TEMPORARY TABLE tmp_ag_dias (n INT NOT NULL, fecha DATE NOT NULL, PRIMARY KEY (n));
    INSERT INTO tmp_ag_dias (n, fecha) VALUES
        (0, v_lunes), (1, DATE_ADD(v_lunes, INTERVAL 1 DAY)), (2, DATE_ADD(v_lunes, INTERVAL 2 DAY)), (3, DATE_ADD(v_lunes, INTERVAL 3 DAY)),
        (4, DATE_ADD(v_lunes, INTERVAL 4 DAY)), (5, DATE_ADD(v_lunes, INTERVAL 5 DAY)), (6, DATE_ADD(v_lunes, INTERVAL 6 DAY));
    DELETE FROM tmp_ag_dias WHERE fecha > v_hasta;

    -- Servicios de la semana de los técnicos del alcance (principal y apoyo), con su estado
    DROP TEMPORARY TABLE IF EXISTS tmp_ag_srv;
    CREATE TEMPORARY TABLE tmp_ag_srv (
        id_usuario      BIGINT       NOT NULL,
        fecha           DATE         NOT NULL,
        id_os           BIGINT       NOT NULL,
        id_programacion BIGINT       NULL,
        numero_os       VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        tipo            VARCHAR(2)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        codigo          VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        cliente         VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        hora_inicio     TIME         NULL,
        hora_fin        TIME         NULL,
        horas           DECIMAL(8,2) NOT NULL DEFAULT 0,
        tipo_servicio   VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        estado          VARCHAR(12)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        conflicto       TINYINT      NOT NULL DEFAULT 0,
        PRIMARY KEY (id_usuario, id_os)
    );
    INSERT IGNORE INTO tmp_ag_srv (id_usuario, fecha, id_os, id_programacion, numero_os, tipo, codigo, cliente, hora_inicio, hora_fin, horas, tipo_servicio, estado, conflicto)
    SELECT s.id_usuario, s.fecha_ejecucion, b.id_os, b.id_programacion, b.numero,
           IF(UPPER(IFNULL(b.tipo, '')) = 'OM' OR UPPER(LEFT(IFNULL(b.numero, ''), 2)) = 'OM', 'OM', 'OS'),
           LPAD(CAST(CAST(IFNULL(NULLIF(REGEXP_SUBSTR(IFNULL(b.numero, ''), '[0-9]+'), ''), '0') AS UNSIGNED) AS CHAR), 4, '0'),
           b.razon_social, s.hora_inicio, s.hora_fin, IFNULL(s.horas, 0), b.tipo_servicio,
           CASE WHEN cf.id_os IS NOT NULL                                  THEN 'conflicto'
                WHEN b.estado = 'finalizada'                               THEN 'finalizado'
                WHEN b.estado = 'pausada' OR d.id_os IS NOT NULL           THEN 'demora'
                WHEN b.estado IN ('en_ruta', 'en_ejecucion', 'bloqueada')  THEN 'en_curso'
                WHEN b.sub_estado = 'programado'                           THEN 'confirmado'
                ELSE 'pendiente' END,
           IF(cf.id_os IS NOT NULL, 1, 0)
    FROM   tmp_prog_asig s
    JOIN   tmp_prog_base b ON b.id_os = s.id_os
    JOIN   tmp_eq e        ON e.id_usuario = s.id_usuario
    -- cada tabla temporal se abre UNA sola vez en la consulta (MySQL no permite reabrirlas): el conflicto y la demora entran por unión
    LEFT JOIN (SELECT DISTINCT cs.id_os, cs.id_usuario FROM tmp_cf_serv cs) cf ON cf.id_os = b.id_os AND cf.id_usuario = s.id_usuario
    LEFT JOIN tmp_ag_dem d ON d.id_os = b.id_os
    WHERE  s.fecha_ejecucion BETWEEN v_lunes AND v_hasta;

    -- Carga por técnico y día (todos los días de la semana mostrada)
    DROP TEMPORARY TABLE IF EXISTS tmp_ag_dia;
    CREATE TEMPORARY TABLE tmp_ag_dia (
        id_usuario BIGINT      NOT NULL,
        fecha      DATE        NOT NULL,
        horas      DECIMAL(8,2) NOT NULL DEFAULT 0,
        nivel      VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        conflicto  TINYINT     NOT NULL DEFAULT 0,
        PRIMARY KEY (id_usuario, fecha)
    );
    INSERT INTO tmp_ag_dia (id_usuario, fecha, horas, nivel, conflicto)
    SELECT x.id_usuario, x.fecha, x.horas,
           CASE WHEN x.conflicto = 1 OR x.horas > 10 THEN 'sobrecarga'
                WHEN x.horas > 8                     THEN 'alta'
                WHEN x.horas >= 6                    THEN 'optima'
                WHEN x.horas > 0                     THEN 'baja'
                ELSE 'libre' END,
           x.conflicto
    FROM (
        SELECT e.id_usuario, d.fecha, IFNULL(g.horas, 0) AS horas,
               IF(IFNULL(g.conf, 0) = 1
                  OR EXISTS (SELECT 1 FROM tmp_prog_conf_ud c WHERE c.id_usuario = e.id_usuario AND c.fecha_ejecucion = d.fecha), 1, 0) AS conflicto
        FROM   tmp_eq e
        CROSS JOIN tmp_ag_dias d
        LEFT JOIN (SELECT sv.id_usuario, sv.fecha, ROUND(SUM(sv.horas), 2) AS horas, MAX(sv.conflicto) AS conf
                   FROM tmp_ag_srv sv GROUP BY sv.id_usuario, sv.fecha) g ON g.id_usuario = e.id_usuario AND g.fecha = d.fecha
    ) x;

    -- Técnicos (los dados de baja solo si tienen servicios en la semana) con su carga y utilización
    DROP TEMPORARY TABLE IF EXISTS tmp_ag_tec;
    CREATE TEMPORARY TABLE tmp_ag_tec (
        id_usuario    BIGINT       NOT NULL,
        nombre        VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        nombre_corto  VARCHAR(60)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        iniciales     VARCHAR(4)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        horas_semana  DECIMAL(8,2) NOT NULL DEFAULT 0,
        utilizacion   INT          NOT NULL DEFAULT 0,
        nivel         VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        sobre_dia     TINYINT      NOT NULL DEFAULT 0,
        PRIMARY KEY (id_usuario)
    );
    INSERT INTO tmp_ag_tec (id_usuario, nombre, nombre_corto, iniciales, horas_semana, utilizacion, nivel, sobre_dia)
    SELECT y.id_usuario, y.nombre, y.nombre_corto, y.iniciales, y.horas, y.util,
           CASE WHEN y.util > 100 THEN 'sobrecarga' WHEN y.util >= 90 THEN 'alta' WHEN y.util >= 60 THEN 'optima' WHEN y.util > 0 THEN 'baja' ELSE 'libre' END,
           y.sobre_dia
    FROM (
        SELECT e.id_usuario, e.nombre, e.iniciales, IFNULL(w.horas, 0) AS horas, IFNULL(w.sobre_dia, 0) AS sobre_dia,
               CONCAT(SUBSTRING_INDEX(TRIM(IFNULL(u.nombre, '')), ' ', 1), IF(IFNULL(TRIM(u.apellido), '') = '', '', CONCAT(' ', LEFT(TRIM(u.apellido), 1), '.'))) AS nombre_corto,
               IF(v_capacidad > 0, ROUND(IFNULL(w.horas, 0) / v_capacidad * 100), 0) AS util
        FROM   tmp_eq e
        JOIN   usuario u ON u.id_usuario = e.id_usuario
        LEFT JOIN (SELECT dd.id_usuario, ROUND(SUM(dd.horas), 2) AS horas, MAX(dd.nivel = 'sobrecarga') AS sobre_dia
                   FROM tmp_ag_dia dd GROUP BY dd.id_usuario) w ON w.id_usuario = e.id_usuario
        WHERE  (u.eliminado_en IS NULL AND u.estado = 'activo') OR IFNULL(w.horas, 0) > 0
    ) y;

    SELECT COUNT(*) INTO v_conflictos FROM tmp_cf c WHERE c.id_usuario IN (SELECT e.id_usuario FROM tmp_eq e);
    SELECT COUNT(DISTINCT sv.id_os) INTO v_servicios FROM tmp_ag_srv sv;
    SELECT COUNT(*) INTO v_sobrecarga FROM tmp_ag_tec t WHERE t.nivel = 'sobrecarga' OR t.sobre_dia = 1;

    -- ── Resultados ─────────────────────────────────────────────────────────────────────────────────────────────────
    SELECT 2 AS IdTipoMensaje, 'OK' AS Mensaje;

    -- 2 Cabecera y KPIs
    SELECT DATE_FORMAT(v_lunes, '%Y-%m-%d') AS desde, DATE_FORMAT(v_hasta, '%Y-%m-%d') AS hasta, v_conflictos AS conflictos, v_servicios AS servicios,
           v_sobrecarga AS sobrecargados, DATE_FORMAT(CONVERT_TZ(UTC_TIMESTAMP(), '+00:00', '-05:00'), '%H:%i') AS actualizado, v_refresco AS refresco_segundos;

    -- 3 Técnicos
    SELECT t.id_usuario, t.nombre, t.nombre_corto, t.iniciales, t.horas_semana, t.utilizacion AS utilizacion_pct, t.nivel
    FROM   tmp_ag_tec t
    ORDER BY t.nombre, t.id_usuario;

    -- 4 Días (técnico × día)
    SELECT d.id_usuario, DATE_FORMAT(d.fecha, '%Y-%m-%d') AS fecha, d.horas, d.nivel, d.conflicto
    FROM   tmp_ag_dia d
    WHERE  d.id_usuario IN (SELECT t.id_usuario FROM tmp_ag_tec t)
    ORDER BY d.id_usuario, d.fecha;

    -- 5 Servicios (técnico × día)
    SELECT sv.id_usuario, DATE_FORMAT(sv.fecha, '%Y-%m-%d') AS fecha, sv.id_os, sv.id_programacion, sv.numero_os, sv.tipo, sv.codigo, sv.cliente,
           TIME_FORMAT(sv.hora_inicio, '%H:%i') AS hora_inicio, TIME_FORMAT(sv.hora_fin, '%H:%i') AS hora_fin, sv.tipo_servicio, sv.estado, sv.conflicto
    FROM   tmp_ag_srv sv
    ORDER BY sv.id_usuario, sv.fecha, sv.hora_inicio, sv.id_os;

    -- 6 Conflictos de los técnicos del alcance (todos los pendientes; el mismo número que el menú)
    SELECT c.clave, c.tipo, c.titulo, c.detalle, DATE_FORMAT(c.fecha, '%Y-%m-%d') AS fecha, c.id_usuario AS id_tecnico, c.tecnico,
           c.id_os_a, oa.numero AS numero_os_a, c.id_os_b, ob.numero AS numero_os_b,
           v_gestiona AS puede_resolver,
           IF(v_aprueba = 1, 'directa', IF(v_gestiona = 1, 'solicitud', 'solo_lectura')) AS modo
    FROM   tmp_cf c
    LEFT JOIN orden_servicio oa ON oa.id_os = c.id_os_a
    LEFT JOIN orden_servicio ob ON ob.id_os = c.id_os_b
    WHERE  c.id_usuario IN (SELECT e.id_usuario FROM tmp_eq e)
    ORDER BY FIELD(c.tipo, 'baja', 'ssoma_vencido', 'solapamiento', 'extension_duracion'), c.fecha, c.clave
    LIMIT 100;

    DROP TEMPORARY TABLE IF EXISTS tmp_ag_tec;
    DROP TEMPORARY TABLE IF EXISTS tmp_ag_dia;
    DROP TEMPORARY TABLE IF EXISTS tmp_ag_srv;
    DROP TEMPORARY TABLE IF EXISTS tmp_ag_dias;
    DROP TEMPORARY TABLE IF EXISTS tmp_ag_dem;
    DROP TEMPORARY TABLE IF EXISTS tmp_eq;
    CALL SP_LimpiarBaseProgramacion();
    CALL SP_LimpiarConflictosProgramacion();
END$$

DELIMITER ;
