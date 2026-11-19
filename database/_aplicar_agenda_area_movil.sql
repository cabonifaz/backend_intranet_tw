-- HU-37 Agenda y carga del área (Jefe de Área, app móvil). Ejecutar con Alt+X (No al aviso) y reiniciar la API.
-- Requiere antes: _aplicar_equipo_jefatura_movil.sql (HU-36: SP_ArmarEquipoJefaturaMovil) y la Programación de la intranet (HU-35 a HU-39: SP_ArmarBaseProgramacion, SP_ArmarConflictosProgramacion,
-- SP_ObtenerConflictoProgramacion, SP_ResolverConflictoProgramacion, SP_ReprogramarProgramacion). No crea tablas ni datos.
-- Crea 4 procedimientos nuevos que ENVUELVEN la programación de la intranet (SP_ArmarEquipoAgendaMovil, SP_ObtenerAgendaAreaMovil, SP_ObtenerConflictoAgendaMovil, SP_ResolverConflictoAgendaMovil) y actualiza 4:
--   SP_ArmarEquipoJefaturaMovil (la agenda también ve a los técnicos dados de baja), SP_ResolverConflictoProgramacion (la app puede elegir el motivo; sin ella la intranet no cambia),
--   SP_ObtenerMenuJefaturaMovil (agenda_conflictos con el mismo alcance que el banner) y SP_ObtenerNotificacionesMovil ("Servicio reprogramado" abre el servicio).

-- ============================================================
-- SP_ArmarEquipoJefaturaMovil  (App Mobile HU-36 «Mi equipo» — apoyo, NO es un endpoint)
-- Arma, UNA sola vez, el equipo de técnicos que ve el jefe y el estado de cada uno HOY, en la tabla temporal `tmp_eq`. Lo usan la lista «Mi equipo», la ficha del técnico, las horas contabilizadas
-- y los contadores del menú de Jefatura (mi_equipo_total / mi_equipo_en_labores): así el menú y las pantallas muestran siempre los mismos números.
-- Quien la llame debe terminar con DROP TEMPORARY TABLE IF EXISTS tmp_eq y, si usó p_completo = 1, con CALL SP_LimpiarSeguimientoOperativo() (las tablas tmp_sg_* quedan armadas por si el que llama
-- necesita más datos del día, p. ej. las demoras de la ficha).
--
-- QUIÉN VE A QUIÉN (regla Área + Rol de la app, SP_ResolverAprobadorMovil): Gerencia, Operaciones, Administración, TI, SSOMA, Calidad y Comercial (cualquier rol) y los Administradores ven a TODOS los
--   técnicos; el Supervisor de Servicio Técnico / Metrología, solo a los de su área; Usuario / Visor de ST o Metrología y quien no tiene área: nada → p_sin_menu = 1 (el SP que llama responde
--   «Tu cargo no tiene el menú de Jefatura.»).
-- QUIÉN ES TÉCNICO: la misma regla de la bandeja de Programación (SP_BuscarTecnicosProgramacion): usuario activo de Servicio Técnico o Metrología, sin cargos «Jefe de …» ni «Asistente …»; además, como en el
--   Panel de Campo, de campo = sin rol Supervisor / Administrador (esos son jefatura, no técnicos).
--
-- ESTADO HOY (excluyente; la regla del orden de la jornada vive en SP_EstadoJornadaMovil y no se repite aquí):
--   finalizada (marcó «Fin de labores») > refrigerio (está en refrigerio ahora) > sin_marcar (no marcó «Inicio de labores») > tardanza (inició fuera de la tolerancia: jornada_marcacion.puntualidad)
--   > en_labores (inició a tiempo y sigue en jornada, incluso si ya salió de una planta). Es el estado del Reloj marcador (HU-20), NO el del servicio.
-- @tw_eq_inactivos = 1 (lo fija SP_ArmarEquipoAgendaMovil, HU-37, y lo deja en 0): incluye también a los técnicos dados de baja / suspendidos (la agenda de conflictos debe verlos: «técnico de baja
--   o ausente»). Sin la variable (menú, Mi equipo, ficha, horas) solo los activos.
-- p_id_tecnico: no NULL = solo ese técnico (si pertenece al equipo del jefe; si no, tmp_eq queda vacía).
-- p_completo = 0: solo jornada (liviano; lo usa el menú). p_completo = 1: además el servicio actual (el del seguimiento operativo: SP_ArmarSeguimientoOperativo), la última posición GPS y, si no hay
--   servicio, el motivo (SSOMA bloqueado o con documentos faltantes: SP_EvaluarSsomaProgramacion contra los requisitos generales).
-- Columnas de tmp_eq: id_usuario, nombre, iniciales, cargo, area, telefono, n_jornada, estado_jornada, siguiente, estado, orden, detalle, hora_inicio, min_tardanza, id_os, numero_os, tipo_os,
--   estado_servicio, lugar, motivo_sin, ssoma, ssoma_detalle, latitud, longitud, min_ubic (+ marcas internas: inicio_utc, puntualidad, refri_utc, fin_utc).
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ArmarEquipoJefaturaMovil;

DELIMITER $$

CREATE PROCEDURE SP_ArmarEquipoJefaturaMovil(
    IN  p_id_usuario BIGINT,
    IN  p_id_tecnico BIGINT,
    IN  p_completo   TINYINT,
    OUT p_sin_menu   TINYINT
)
proc: BEGIN
    DECLARE v_area_jefe VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_general   TINYINT DEFAULT 0;
    DECLARE v_ahora_utc DATETIME;
    DECLARE v_hoy       DATE;
    DECLARE v_id        BIGINT DEFAULT NULL;
    DECLARE v_prev      BIGINT DEFAULT 0;
    DECLARE v_n         INT DEFAULT 0;
    DECLARE v_estado    VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_sig       VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_ultima    DATETIME;
    DECLARE v_refri     DECIMAL(18,6);

    SET p_sin_menu  = 0;
    SET v_ahora_utc = UTC_TIMESTAMP();
    SET v_hoy       = DATE(CONVERT_TZ(v_ahora_utc, '+00:00', '-05:00'));

    DROP TEMPORARY TABLE IF EXISTS tmp_eq;
    CREATE TEMPORARY TABLE tmp_eq (
        id_usuario      BIGINT        NOT NULL,
        nombre          VARCHAR(220)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        iniciales       VARCHAR(4)    CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        cargo           VARCHAR(150)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        area            VARCHAR(30)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        telefono        VARCHAR(30)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        n_jornada       INT           NOT NULL DEFAULT 0,
        estado_jornada  VARCHAR(20)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        siguiente       VARCHAR(20)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        ultima_utc      DATETIME,
        inicio_utc      DATETIME,
        puntualidad     VARCHAR(10)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        min_tardanza    INT,
        refri_utc       DATETIME,
        fin_utc         DATETIME,
        estado          VARCHAR(20)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        orden           INT           NOT NULL DEFAULT 9,
        detalle         VARCHAR(250)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        hora_inicio     CHAR(5)       CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        id_os           BIGINT,
        numero_os       VARCHAR(20)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        tipo_os         VARCHAR(2)    CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        estado_servicio VARCHAR(20)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        lugar           VARCHAR(200)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        motivo_sin      VARCHAR(250)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        ssoma           VARCHAR(20)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        ssoma_detalle   VARCHAR(250)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        latitud         DECIMAL(10,7),
        longitud        DECIMAL(10,7),
        min_ubic        INT,
        PRIMARY KEY (id_usuario)
    );

    -- Quién es y qué ve: la misma regla Área + Rol de la app
    CALL SP_ResolverAprobadorMovil(p_id_usuario, v_area_jefe, v_general);
    IF v_area_jefe IS NULL AND IFNULL(v_general, 0) = 0 THEN
        SET p_sin_menu = 1;
        LEAVE proc;
    END IF;

    INSERT INTO tmp_eq (id_usuario, nombre, iniciales, cargo, area, telefono)
    SELECT u.id_usuario,
           TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))),
           UPPER(CONCAT(LEFT(IFNULL(u.nombre, '?'), 1), LEFT(IFNULL(u.apellido, ''), 1))),
           COALESCE(c.String1, u.cargo, IF(u.area = 'metrologia', 'Metrología', 'Servicio Técnico')),
           u.area,
           NULLIF(TRIM(u.telefono), '')
    FROM   usuario u
    LEFT JOIN tabla_maestra c ON c.IdMaestro = 80 AND c.IdEmpresa = 1 AND c.String2 = u.cargo
    WHERE  (IFNULL(@tw_eq_inactivos, 0) = 1 OR (u.eliminado_en IS NULL AND u.estado = 'activo'))
      AND  u.area IN ('servicio_tecnico', 'metrologia')
      AND  (u.cargo IS NULL OR (u.cargo NOT LIKE 'jefe\_%' AND u.cargo NOT LIKE 'asistente\_%'))
      AND  IFNULL(u.rol_sistema, 'usuario') NOT IN ('supervisor', 'administrador', 'admin')
      AND  (v_general = 1 OR u.area = v_area_jefe)
      AND  (p_id_tecnico IS NULL OR u.id_usuario = p_id_tecnico);

    -- Estado del Reloj marcador de cada técnico (SP_EstadoJornadaMovil: la regla del orden de la jornada, una sola vez)
    jornada: LOOP
        SELECT MIN(e.id_usuario) INTO v_id FROM tmp_eq e WHERE e.id_usuario > v_prev;
        IF v_id IS NULL THEN LEAVE jornada; END IF;
        SET v_prev = v_id;
        CALL SP_EstadoJornadaMovil(v_id, v_hoy, v_n, v_estado, v_sig, v_ultima);
        UPDATE tmp_eq SET n_jornada = v_n, estado_jornada = v_estado, siguiente = v_sig, ultima_utc = v_ultima WHERE id_usuario = v_id;
    END LOOP jornada;

    -- Marcaciones de hoy que explican el estado (inicio con su puntualidad, refrigerio y fin)
    UPDATE tmp_eq t
    SET t.inicio_utc   = (SELECT j.marcado_utc FROM jornada_marcacion j WHERE j.id_usuario = t.id_usuario AND j.fecha = v_hoy AND j.tipo = 'inicio_labores' LIMIT 1),
        t.puntualidad  = (SELECT j.puntualidad FROM jornada_marcacion j WHERE j.id_usuario = t.id_usuario AND j.fecha = v_hoy AND j.tipo = 'inicio_labores' LIMIT 1),
        t.min_tardanza = (SELECT j.minutos_diferencia FROM jornada_marcacion j WHERE j.id_usuario = t.id_usuario AND j.fecha = v_hoy AND j.tipo = 'inicio_labores' LIMIT 1),
        t.refri_utc    = (SELECT j.marcado_utc FROM jornada_marcacion j WHERE j.id_usuario = t.id_usuario AND j.fecha = v_hoy AND j.tipo = 'inicio_refrigerio' LIMIT 1),
        t.fin_utc      = (SELECT j.marcado_utc FROM jornada_marcacion j WHERE j.id_usuario = t.id_usuario AND j.fecha = v_hoy AND j.tipo = 'fin_labores' LIMIT 1);

    CALL SP_LeerParametroProgramacion('JORNADA_REFRIGERIO_MIN', 60, v_refri);

    UPDATE tmp_eq
    SET estado = CASE WHEN estado_jornada = 'finalizada'    THEN 'finalizada'
                      WHEN estado_jornada = 'en_refrigerio' THEN 'refrigerio'
                      WHEN n_jornada = 0                    THEN 'sin_marcar'
                      WHEN puntualidad = 'tardanza'         THEN 'tardanza'
                      ELSE 'en_labores' END,
        hora_inicio = DATE_FORMAT(CONVERT_TZ(inicio_utc, '+00:00', '-05:00'), '%H:%i');

    UPDATE tmp_eq
    SET orden = CASE estado WHEN 'sin_marcar' THEN 0 WHEN 'tardanza' THEN 1 WHEN 'refrigerio' THEN 2 WHEN 'en_labores' THEN 3 ELSE 4 END,
        detalle = CASE estado
                    WHEN 'sin_marcar' THEN 'Sin marcar inicio de labores'
                    WHEN 'finalizada' THEN CONCAT('Jornada finalizada · ', DATE_FORMAT(CONVERT_TZ(fin_utc, '+00:00', '-05:00'), '%H:%i'))
                    WHEN 'refrigerio' THEN CONCAT('En refrigerio desde ', DATE_FORMAT(CONVERT_TZ(refri_utc, '+00:00', '-05:00'), '%H:%i'),
                                                  ' · vuelve ', DATE_FORMAT(CONVERT_TZ(DATE_ADD(refri_utc, INTERVAL CAST(v_refri AS SIGNED) MINUTE), '+00:00', '-05:00'), '%H:%i'))
                    WHEN 'tardanza'   THEN CONCAT('En labores · ', hora_inicio, ' (tardanza ', IFNULL(min_tardanza, 0), ' min)')
                    ELSE CONCAT('En labores · ', IFNULL(hora_inicio, '—')) END;

    -- Servicio actual, ubicación y motivo si no tiene servicio
    IF p_completo = 1 THEN
        CALL SP_ArmarSeguimientoOperativo();

        UPDATE tmp_eq t
        JOIN   tmp_sg_tec s ON s.id_usuario = t.id_usuario
        SET    t.id_os = s.id_os_actual,
               t.estado_servicio = IF(s.id_os_actual IS NULL, NULL, s.estado_seg);

        UPDATE tmp_eq t
        JOIN   tmp_sg_os o ON o.id_os = t.id_os
        SET    t.numero_os = o.numero,
               t.tipo_os   = IF(UPPER(IFNULL(o.tipo, '')) = 'OM' OR UPPER(LEFT(IFNULL(o.numero, ''), 2)) = 'OM', 'OM', 'OS'),
               t.lugar     = LEFT(COALESCE(NULLIF(o.sede_nombre, ''), NULLIF(o.razon_social, '')), 200);

        UPDATE tmp_eq t
        JOIN   tmp_sg_pos p ON p.id_usuario = t.id_usuario
        SET    t.latitud  = p.lat,
               t.longitud = p.lon,
               t.min_ubic = IF(p.ts_utc IS NULL, NULL, GREATEST(0, TIMESTAMPDIFF(MINUTE, p.ts_utc, v_ahora_utc)));

        -- SSOMA contra los requisitos generales (la ficha vuelve a evaluarlo contra la orden del técnico)
        DROP TEMPORARY TABLE IF EXISTS tmp_ssoma_in;
        CREATE TEMPORARY TABLE tmp_ssoma_in (id_usuario BIGINT NOT NULL, PRIMARY KEY (id_usuario));
        INSERT INTO tmp_ssoma_in (id_usuario) SELECT e.id_usuario FROM tmp_eq e;
        CALL SP_EvaluarSsomaProgramacion(NULL, v_hoy);

        UPDATE tmp_eq t
        JOIN   tmp_ssoma_res s ON s.id_usuario = t.id_usuario
        SET    t.ssoma = s.estado,
               t.ssoma_detalle = LEFT(CASE WHEN s.estado = 'bloqueado' THEN IFNULL(NULLIF(s.motivo_bloqueo, ''), 'SSOMA bloqueado')
                                           WHEN s.estado IN ('pendiente', 'incompleto') THEN CONCAT('Falta documento SSOMA', IF(IFNULL(s.faltantes, '') = '', '', CONCAT(': ', s.faltantes)))
                                           WHEN s.estado = 'por_vencer' THEN 'SSOMA por vencer'
                                           ELSE NULL END, 250);

        UPDATE tmp_eq
        SET    motivo_sin = IF(id_os IS NULL AND ssoma IN ('bloqueado', 'pendiente', 'incompleto'), ssoma_detalle, NULL);

        DROP TEMPORARY TABLE IF EXISTS tmp_ssoma_in;
        CALL SP_LimpiarSsomaProgramacion();
    END IF;
END$$

DELIMITER ;

-- ============================================================
-- SP_ArmarEquipoAgendaMovil  (App Mobile HU-37 «Agenda y carga del área» — apoyo, NO es un endpoint)
-- El equipo de técnicos que ve el jefe en la agenda, la carga, los conflictos y sus acciones: el MISMO de «Mi equipo» (SP_ArmarEquipoJefaturaMovil, regla Área + Rol de SP_ResolverAprobadorMovil), pero
-- incluyendo también a los técnicos dados de baja o suspendidos, porque el conflicto «técnico de baja o ausente» (HU-39) es justamente de ellos y el jefe debe poder verlo y resolverlo.
-- Deja la tabla temporal `tmp_eq` (solo jornada; ver SP_ArmarEquipoJefaturaMovil). Quien la llame debe terminar con DROP TEMPORARY TABLE IF EXISTS tmp_eq.
-- p_id_tecnico: no NULL = solo ese técnico (tmp_eq queda vacía si no es del alcance). p_sin_menu = 1: el usuario no tiene menú de Jefatura («Tu cargo no tiene el menú de Jefatura.»).
-- Solo lectura. La variable @tw_eq_inactivos solo vive durante esta llamada (se limpia también si falla).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ArmarEquipoAgendaMovil;

DELIMITER $$

CREATE PROCEDURE SP_ArmarEquipoAgendaMovil(
    IN  p_id_usuario BIGINT,
    IN  p_id_tecnico BIGINT,
    OUT p_sin_menu   TINYINT
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        SET @tw_eq_inactivos = 0;
        RESIGNAL;
    END;

    SET p_sin_menu = 0;
    SET @tw_eq_inactivos = 1;
    CALL SP_ArmarEquipoJefaturaMovil(p_id_usuario, p_id_tecnico, 0, p_sin_menu);
    SET @tw_eq_inactivos = 0;
END$$

DELIMITER ;

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

-- ============================================================
-- SP_ObtenerConflictoAgendaMovil  (App Mobile HU-37 — modal «Conflicto de programación»: los servicios, el motivo sugerido y el técnico sugerido · solo lectura)
-- ENVUELVE SP_ObtenerConflictoProgramacion (HU-39 de la intranet: vuelve a detectar el conflicto, trae los servicios, las opciones y los recursos sugeridos con SSOMA conforme y carga) sin repetir
-- ninguna de sus reglas; solo añade el alcance del jefe y el catálogo de motivos:
--   · el técnico del conflicto debe ser del equipo del jefe (SP_ArmarEquipoAgendaMovil: regla Área + Rol, incluidos los dados de baja); si no → «El técnico del conflicto no pertenece a tu equipo.».
--   · permiso prog_bandeja (lo valida el SP envuelto).
-- Resultados (los 5 primeros son los del SP envuelto, tal cual; la API arma el modal con ellos):
--   1 mensaje · 2 conflicto · 3 servicios (orden, etiqueta, id_os, id_programacion, numero_os, tipo, razon_social, tipo_servicio, estado_programacion, fecha, hora_inicio, hora_fin, horas, resoluble) ·
--   4 opciones · 5 recursos sugeridos por servicio (puntaje: a menos carga de la semana, más puntos)
--   6 (añadido) los técnicos del alcance del jefe (id_tecnico): la API solo sugiere a quien el jefe puede asignar ·
--   7 (añadido) motivos de reprogramación (catálogo MOTIVO_REPROGRAMACION: id_motivo, nombre).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerConflictoAgendaMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerConflictoAgendaMovil(
    IN p_id_usuario BIGINT,
    IN p_tipo       VARCHAR(25) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_tecnico BIGINT,
    IN p_id_os_a    BIGINT,
    IN p_id_os_b    BIGINT
)
proc: BEGIN
    DECLARE v_sin_menu TINYINT DEFAULT 0;
    DECLARE v_en       INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SET @tw_eq_inactivos = 0;
        DROP TEMPORARY TABLE IF EXISTS tmp_eq;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0
       OR NOT EXISTS (SELECT 1 FROM usuario u WHERE u.id_usuario = p_id_usuario AND u.eliminado_en IS NULL AND u.estado = 'activo') THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no válido.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF IFNULL(p_id_tecnico, 0) <= 0 OR IFNULL(p_id_os_a, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Indica el técnico y la orden del conflicto.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Alcance Área + Rol
    CALL SP_ArmarEquipoAgendaMovil(p_id_usuario, NULL, v_sin_menu);
    IF v_sin_menu = 1 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_eq;
        SELECT 1 AS IdTipoMensaje, 'Tu cargo no tiene el menú de Jefatura.' AS Mensaje;
        LEAVE proc;
    END IF;
    SELECT COUNT(*) INTO v_en FROM tmp_eq e WHERE e.id_usuario = p_id_tecnico;
    IF v_en = 0 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_eq;
        SELECT 1 AS IdTipoMensaje, 'El técnico del conflicto no pertenece a tu equipo.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- El detalle del conflicto es el de la intranet (sus resultados 1 a 5 salen tal cual)
    CALL SP_ObtenerConflictoProgramacion(p_id_usuario, p_tipo, p_id_tecnico, p_id_os_a, p_id_os_b);

    -- 6 Técnicos del alcance (para sugerir solo a quien el jefe puede asignar)
    SELECT e.id_usuario AS id_tecnico FROM tmp_eq e;

    -- 7 Motivos de reprogramación
    SELECT t.Num1 AS id_motivo, t.String1 AS nombre
    FROM   tabla_maestra t
    WHERE  t.IdMaestro = 13 AND t.IdEmpresa = 1 AND t.eliminado_en IS NULL AND t.Num1 IS NOT NULL
    ORDER BY t.Num1;

    DROP TEMPORARY TABLE IF EXISTS tmp_eq;
END$$

DELIMITER ;

-- ============================================================
-- SP_ResolverConflictoAgendaMovil  (App Mobile HU-37 — «Resolver» un conflicto de programación desde la agenda del área · escritura)
-- ENVUELVE SP_ResolverConflictoProgramacion (HU-39 de la intranet), que a su vez delega en SP_ReprogramarProgramacion (HU-38): vuelve a detectar el conflicto, valida las opciones y decide por el
-- permiso del usuario del token si es EDICIÓN DIRECTA (prog_aprobar_reprogramacion) o una SOLICITUD de reprogramación pendiente (solo prog_gestionar). Aquí NO se repite ninguna de esas reglas
-- (ni el cruce de horarios, ni la SSOMA, ni el aviso a los técnicos «Servicio reprogramado: …» / «Asignación retirada: …»); solo se añade:
--   · el ALCANCE Área + Rol del jefe (SP_ArmarEquipoAgendaMovil): el técnico del conflicto y, al reasignar, el técnico nuevo deben ser de su equipo; si no, mensaje de negocio.
--   · el MOTIVO elegido en la app (p_id_motivo, del catálogo MOTIVO_REPROGRAMACION): si no viene, se usa el del conflicto (el que ya sugiere la HU-39); el SP de la intranet lo respeta mediante las
--     variables @tw_cf_motivo / @tw_cf_motivo_usuario, que aquí se fijan justo antes y se limpian al terminar (también si falla).
-- Opciones (p_opcion): reasignar (Cambiar técnico: requiere p_id_nuevo_tecnico) · reprogramar (Cambiar horario = la misma fecha con otras horas; Reprogramar con motivo = otra fecha y horas: requiere
--   p_fecha, p_hora_inicio y p_hora_fin). p_id_os_objetivo = la orden a mover (NULL = p_id_os_a). p_comentario hasta 400 (se antepone el motivo autocompletado del conflicto).
-- Resultados: los de SP_ResolverConflictoProgramacion: 1 mensaje, 2 resultado (modo: directa | solicitud).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ResolverConflictoAgendaMovil;

DELIMITER $$

CREATE PROCEDURE SP_ResolverConflictoAgendaMovil(
    IN p_id_usuario       BIGINT,
    IN p_tipo             VARCHAR(25) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_tecnico       BIGINT,
    IN p_id_os_a          BIGINT,
    IN p_id_os_b          BIGINT,
    IN p_opcion           VARCHAR(15) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_os_objetivo   BIGINT,
    IN p_id_nuevo_tecnico BIGINT,
    IN p_fecha            DATE,
    IN p_hora_inicio      TIME,
    IN p_hora_fin         TIME,
    IN p_id_motivo        INT,
    IN p_comentario       VARCHAR(400) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_sin_menu TINYINT DEFAULT 0;
    DECLARE v_en       INT DEFAULT 0;
    DECLARE v_opcion   VARCHAR(15) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SET @tw_eq_inactivos = 0;
        SET @tw_cf_motivo = NULL;
        SET @tw_cf_motivo_usuario = NULL;
        DROP TEMPORARY TABLE IF EXISTS tmp_eq;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0
       OR NOT EXISTS (SELECT 1 FROM usuario u WHERE u.id_usuario = p_id_usuario AND u.eliminado_en IS NULL AND u.estado = 'activo') THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no válido.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF IFNULL(p_id_tecnico, 0) <= 0 OR IFNULL(p_id_os_a, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Indica el técnico y la orden del conflicto.' AS Mensaje;
        LEAVE proc;
    END IF;
    SET v_opcion = LOWER(TRIM(IFNULL(p_opcion, '')));

    -- Alcance Área + Rol: el técnico del conflicto y, al reasignar, el técnico nuevo
    CALL SP_ArmarEquipoAgendaMovil(p_id_usuario, NULL, v_sin_menu);
    IF v_sin_menu = 1 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_eq;
        SELECT 1 AS IdTipoMensaje, 'Tu cargo no tiene el menú de Jefatura.' AS Mensaje;
        LEAVE proc;
    END IF;
    SELECT COUNT(*) INTO v_en FROM tmp_eq e WHERE e.id_usuario = p_id_tecnico;
    IF v_en = 0 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_eq;
        SELECT 1 AS IdTipoMensaje, 'El técnico del conflicto no pertenece a tu equipo.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_opcion = 'reasignar' AND IFNULL(p_id_nuevo_tecnico, 0) > 0 THEN
        SELECT COUNT(*) INTO v_en FROM tmp_eq e WHERE e.id_usuario = p_id_nuevo_tecnico;
        IF v_en = 0 OR NOT EXISTS (SELECT 1 FROM usuario u WHERE u.id_usuario = p_id_nuevo_tecnico AND u.eliminado_en IS NULL AND u.estado = 'activo') THEN
            DROP TEMPORARY TABLE IF EXISTS tmp_eq;
            SELECT 1 AS IdTipoMensaje, 'El técnico elegido no pertenece a tu equipo o no está activo.' AS Mensaje;
            LEAVE proc;
        END IF;
    END IF;
    DROP TEMPORARY TABLE IF EXISTS tmp_eq;

    -- Motivo elegido en la app (opcional): del catálogo MOTIVO_REPROGRAMACION
    IF p_id_motivo IS NOT NULL THEN
        IF NOT EXISTS (SELECT 1 FROM tabla_maestra t WHERE t.IdMaestro = 13 AND t.IdEmpresa = 1 AND t.eliminado_en IS NULL AND t.Num1 = p_id_motivo) THEN
            SELECT 1 AS IdTipoMensaje, 'El motivo de reprogramación no es válido.' AS Mensaje;
            LEAVE proc;
        END IF;
        SET @tw_cf_motivo = p_id_motivo;
        SET @tw_cf_motivo_usuario = p_id_usuario;
    ELSE
        SET @tw_cf_motivo = NULL;
        SET @tw_cf_motivo_usuario = NULL;
    END IF;

    -- La resolución es la de la intranet (permisos, cruces de horario, SSOMA, directa o solicitud, avisos y auditoría)
    CALL SP_ResolverConflictoProgramacion(p_id_usuario, p_tipo, p_id_tecnico, p_id_os_a, p_id_os_b, p_opcion, p_id_os_objetivo, p_id_nuevo_tecnico,
                                          p_fecha, p_hora_inicio, p_hora_fin, p_comentario);

    SET @tw_cf_motivo = NULL;
    SET @tw_cf_motivo_usuario = NULL;
END$$

DELIMITER ;

-- HU-39 (Sprint 5) "Aplicar Resolución" del modal Resolver Conflicto de Programación. Acceso: prog_gestionar.
-- No inventa un circuito nuevo: vuelve a detectar el conflicto (si ya cambió, avisa) y delega en SP_ReprogramarProgramacion (HU-38), que
-- decide por el permiso del usuario del token: Jefe (prog_aprobar_reprogramacion) = edición directa; Asistente = Solicitud de
-- Reprogramación pendiente. Así no se otorgan permisos nuevos y la auditoría/historial son los mismos de la HU-38.
--   p_tipo / p_id_tecnico / p_id_os_a / p_id_os_b: identifican el conflicto (igual que SP_ObtenerConflictoProgramacion).
--   p_opcion: reasignar (cambia el técnico del servicio; mantiene el estado confirmado) | reprogramar (nueva fecha y horas; vuelve a
--             Pendiente confirmación cliente). La cancelación se hace con SP_CancelarProgramacion (HU-38), siempre disponible.
--   p_id_os_objetivo: la orden afectada por la resolución (debe formar parte del conflicto). NULL = p_id_os_a.
--   p_id_nuevo_tecnico: solo en reasignar. p_fecha, p_hora_inicio, p_hora_fin: solo en reprogramar.
--   p_comentario: opcional; se antepone el motivo autocompletado del conflicto (p. ej. 'SSOMA vencido del técnico Juan Pérez').
-- Motivo: el del conflicto (id_motivo_sugerido). La app móvil (HU-37, SP_ResolverConflictoAgendaMovil) puede elegir otro del catálogo MOTIVO_REPROGRAMACION: lo deja en @tw_cf_motivo junto con
--   @tw_cf_motivo_usuario (= el usuario del token) y lo limpia al terminar; solo se respeta si el usuario coincide. Sin las variables, el comportamiento de la intranet NO cambia.
-- Resultados: 1 mensaje, 2 resultado (los de SP_ReprogramarProgramacion: modo directa | solicitud).
DROP PROCEDURE IF EXISTS SP_ResolverConflictoProgramacion;

DELIMITER $$

CREATE PROCEDURE SP_ResolverConflictoProgramacion(
    IN p_id_usuario       BIGINT,
    IN p_tipo             VARCHAR(25) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_tecnico       BIGINT,
    IN p_id_os_a          BIGINT,
    IN p_id_os_b          BIGINT,
    IN p_opcion           VARCHAR(15) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_os_objetivo   BIGINT,
    IN p_id_nuevo_tecnico BIGINT,
    IN p_fecha            DATE,
    IN p_hora_inicio      TIME,
    IN p_hora_fin         TIME,
    IN p_comentario       VARCHAR(400) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_tipo      VARCHAR(25) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_opcion    VARCHAR(15) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_clave     VARCHAR(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_objetivo  BIGINT;
    DECLARE v_id_prog   BIGINT DEFAULT NULL;
    DECLARE v_rol       VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_motivo INT DEFAULT NULL;
    DECLARE v_sugerido  VARCHAR(400) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_coment    VARCHAR(400) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_principal BIGINT DEFAULT NULL;
    DECLARE v_apoyo     JSON DEFAULT NULL;
    DECLARE v_tec_param BIGINT DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            @err_msg  = MESSAGE_TEXT,
            @err_code = MYSQL_ERRNO;
        CALL SP_LimpiarConflictosProgramacion();
        IF @err_code IN (1213, 1205) THEN
            SELECT 1 AS IdTipoMensaje, 'Otra persona está modificando esta programación en este momento. Inténtalo de nuevo.' AS Mensaje;
        ELSE
            SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
        END IF;
    END;

    IF FN_PermisoAccion(p_id_usuario, 'prog_gestionar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para resolver conflictos de programación.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_tipo   = LOWER(TRIM(IFNULL(p_tipo, '')));
    SET v_opcion = LOWER(TRIM(IFNULL(p_opcion, '')));
    IF v_tipo NOT IN ('baja', 'ssoma_vencido', 'solapamiento', 'extension_duracion') THEN
        SELECT 1 AS IdTipoMensaje, 'El tipo de conflicto no es válido.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF IFNULL(p_id_tecnico, 0) <= 0 OR IFNULL(p_id_os_a, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Indica el técnico y la orden del conflicto.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_tipo IN ('solapamiento', 'extension_duracion') THEN
        IF IFNULL(p_id_os_b, 0) <= 0 OR p_id_os_b = p_id_os_a THEN
            SELECT 1 AS IdTipoMensaje, 'Indica las dos órdenes que se cruzan.' AS Mensaje;
            LEAVE proc;
        END IF;
        SET v_clave = CONCAT(v_tipo, ':', p_id_tecnico, ':', LEAST(p_id_os_a, p_id_os_b), ':', GREATEST(p_id_os_a, p_id_os_b));
    ELSE
        SET v_clave = CONCAT(v_tipo, ':', p_id_tecnico);
    END IF;
    IF v_opcion NOT IN ('reasignar', 'reprogramar') THEN
        SELECT 1 AS IdTipoMensaje, 'Selecciona cómo resolver el conflicto: reasignar o reprogramar.' AS Mensaje;
        LEAVE proc;
    END IF;
    SET v_objetivo = IFNULL(p_id_os_objetivo, p_id_os_a);
    IF v_objetivo NOT IN (p_id_os_a, IFNULL(p_id_os_b, 0)) THEN
        SELECT 1 AS IdTipoMensaje, 'La orden a resolver no forma parte de este conflicto.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_opcion = 'reasignar' THEN
        IF IFNULL(p_id_nuevo_tecnico, 0) <= 0 THEN
            SELECT 1 AS IdTipoMensaje, 'Selecciona el técnico que asumirá el servicio.' AS Mensaje;
            LEAVE proc;
        END IF;
        IF p_id_nuevo_tecnico = p_id_tecnico THEN
            SELECT 1 AS IdTipoMensaje, 'El nuevo técnico debe ser distinto del técnico en conflicto.' AS Mensaje;
            LEAVE proc;
        END IF;
    ELSE
        IF p_fecha IS NULL OR p_hora_inicio IS NULL OR p_hora_fin IS NULL THEN
            SELECT 1 AS IdTipoMensaje, 'Indica la nueva fecha y el horario del servicio.' AS Mensaje;
            LEAVE proc;
        END IF;
    END IF;

    -- Se vuelve a detectar: nada de datos viejos
    CALL SP_ArmarConflictosProgramacion();
    IF NOT EXISTS (SELECT 1 FROM tmp_cf WHERE clave = v_clave) THEN
        CALL SP_LimpiarConflictosProgramacion();
        SELECT 1 AS IdTipoMensaje, 'El conflicto ya no existe o cambió: actualiza la lista de alertas.' AS Mensaje;
        LEAVE proc;
    END IF;
    SELECT c.id_motivo, c.motivo_sugerido INTO v_id_motivo, v_sugerido FROM tmp_cf c WHERE c.clave = v_clave;
    IF IFNULL(@tw_cf_motivo_usuario, 0) = p_id_usuario AND IFNULL(@tw_cf_motivo, 0) > 0 THEN
        SET v_id_motivo = @tw_cf_motivo;
    END IF;
    SELECT a.id_programacion, a.rol INTO v_id_prog, v_rol
    FROM tmp_cf_asig a WHERE a.id_os = v_objetivo AND a.id_usuario = p_id_tecnico;
    IF v_rol IS NULL THEN
        CALL SP_LimpiarConflictosProgramacion();
        SELECT 1 AS IdTipoMensaje, 'El conflicto ya no existe o cambió: actualiza la lista de alertas.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_id_prog IS NULL THEN
        CALL SP_LimpiarConflictosProgramacion();
        SELECT 1 AS IdTipoMensaje, 'Este servicio no tiene una programación vigente: edítalo desde su ficha.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_id_motivo IS NULL THEN
        CALL SP_LimpiarConflictosProgramacion();
        SELECT 1 AS IdTipoMensaje, 'No hay un motivo de reprogramación configurado para este conflicto.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_coment = LEFT(CONCAT(IFNULL(v_sugerido, ''),
                               IF(NULLIF(TRIM(IFNULL(p_comentario, '')), '') IS NULL, '', CONCAT(' — ', TRIM(p_comentario)))), 400);

    IF v_opcion = 'reasignar' THEN
        SELECT os.id_tecnico_principal INTO v_principal FROM orden_servicio os WHERE os.id_os = v_objetivo;
        IF v_rol = 'principal' THEN
            SET v_tec_param = p_id_nuevo_tecnico;
        ELSE
            -- El técnico en conflicto es de apoyo: se sustituye dentro de la lista de apoyo
            SELECT JSON_ARRAYAGG(x.id_usuario) INTO v_apoyo FROM (
                SELECT DISTINCT IF(pe.id_usuario = p_id_tecnico, p_id_nuevo_tecnico, pe.id_usuario) AS id_usuario
                FROM os_personal pe
                WHERE pe.id_os = v_objetivo AND pe.eliminado_en IS NULL AND pe.id_usuario <> IFNULL(v_principal, 0)
            ) x;
        END IF;
    END IF;

    CALL SP_LimpiarConflictosProgramacion();

    IF v_opcion = 'reasignar' THEN
        CALL SP_ReprogramarProgramacion(p_id_usuario, v_id_prog, NULL, NULL, NULL, v_tec_param, v_apoyo, NULL, v_id_motivo, v_coment);
    ELSE
        CALL SP_ReprogramarProgramacion(p_id_usuario, v_id_prog, p_fecha, p_hora_inicio, p_hora_fin, NULL, NULL, NULL, v_id_motivo, v_coment);
    END IF;
END$$

DELIMITER ;

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
--        mi_equipo_total / mi_equipo_en_labores : el equipo de técnicos que ve este jefe y, de ellos, los que HOY están en su jornada según el Reloj marcador (HU-20: en labores, con tardanza o
--                               en refrigerio; no cuentan los que no marcaron o ya finalizaron). Es EL MISMO cálculo de «Mi equipo» (HU-36, SP_ArmarEquipoJefaturaMovil: regla Área + Rol; técnico =
--                               la regla de la bandeja de Programación, de campo), así que el menú y la pantalla muestran los mismos números (KPI en_jornada). Para todas las áreas con menú de Jefatura.
--        agenda_conflictos    : conflictos sobrevenidos de la Programación (HU-39, SP_ArmarConflictosProgramacion: el MISMO cálculo de la lista de
--                               conflictos) de los técnicos del alcance Área + Rol del jefe (SP_ArmarEquipoAgendaMovil, HU-37: el mismo número que el banner de «Agenda del Área»).
--                               Solo con prog_bandeja.
--        viaticos_por_revisar : gastos rendidos por los técnicos pendientes de revisión (gasto_viatico tipo gasto_solicitado, estado pendiente).
--                               Solo con prog_aprobar_reprogramacion (el Jefe de Operaciones, quien revisa los gastos: SP_RevisarGastoProgramacion) y solo los de servicios de su
--                               alcance Área + Rol (HU-35, SP_ArmarAlcanceViaticosMovil: el mismo número que los "por revisar" de Viáticos y gastos del equipo).
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
        DECLARE v_tiene_inf TINYINT DEFAULT 0;
        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            SET @tw_inf_usuario = NULL, @tw_inf_ver_todo = NULL, @tw_inf_area = NULL;
            DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;
            SET v_informes = NULL;
        END;
        IF FN_PermisoAccion(p_id_usuario, 'rt_bandeja') = 1 THEN
            -- Con el alcance de la app (regla ÁREA + ROL) y sin los observados (esos esperan la corrección del técnico): los mismos de la pestaña "Por revisar" (HU-33)
            CALL SP_FijarAlcanceInformesMovil(p_id_usuario, v_tiene_inf);
            IF v_tiene_inf = 1 THEN
                CALL SP_ArmarBaseInformes(p_id_usuario, NULL);
                SELECT COUNT(*) INTO v_informes FROM tmp_rt_base
                WHERE grupo_estado IN ('pendiente_revision', 'pendiente_precotizacion') AND estado <> 'observado';
                DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;
            END IF;
            SET @tw_inf_usuario = NULL, @tw_inf_ver_todo = NULL, @tw_inf_area = NULL;
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

    -- Mi Equipo (HU-36): los técnicos que ve el jefe y los que hoy están en su jornada. UNA sola fuente con la pantalla «Mi equipo»: SP_ArmarEquipoJefaturaMovil (modo liviano: solo el Reloj marcador)
    BEGIN
        DECLARE v_sin_eq TINYINT DEFAULT 0;
        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            SET v_eq_total = NULL;
            SET v_eq_labores = NULL;
            DROP TEMPORARY TABLE IF EXISTS tmp_eq;
        END;
        CALL SP_ArmarEquipoJefaturaMovil(p_id_usuario, NULL, 0, v_sin_eq);
        IF v_sin_eq = 0 THEN
            SELECT COUNT(*), IFNULL(SUM(e.estado IN ('en_labores', 'tardanza', 'refrigerio')), 0)
            INTO   v_eq_total, v_eq_labores
            FROM   tmp_eq e;
        END IF;
        DROP TEMPORARY TABLE IF EXISTS tmp_eq;
    END;

    -- Agenda del Área (HU-37): conflictos sobrevenidos de la Programación (HU-39) de los técnicos del alcance Área + Rol del jefe (SP_ArmarEquipoAgendaMovil: el MISMO equipo de la agenda,
    -- incluidos los dados de baja); el número es el del banner de «Agenda del Área»
    BEGIN
        DECLARE v_sin_ag TINYINT DEFAULT 0;
        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            CALL SP_LimpiarConflictosProgramacion();
            DROP TEMPORARY TABLE IF EXISTS tmp_eq;
            SET v_conflictos = NULL;
        END;
        IF FN_PermisoAccion(p_id_usuario, 'prog_bandeja') = 1 THEN
            CALL SP_ArmarEquipoAgendaMovil(p_id_usuario, NULL, v_sin_ag);
            IF v_sin_ag = 0 THEN
                CALL SP_ArmarConflictosProgramacion();
                SELECT COUNT(*) INTO v_conflictos
                FROM   tmp_cf c
                WHERE  c.id_usuario IN (SELECT e.id_usuario FROM tmp_eq e);
                CALL SP_LimpiarConflictosProgramacion();
            END IF;
            DROP TEMPORARY TABLE IF EXISTS tmp_eq;
        END IF;
    END;

    -- Viáticos y Gastos: gastos rendidos por revisar (solo quien los revisa y solo los de su alcance Área + Rol: SP_ArmarAlcanceViaticosMovil, el mismo de "Viáticos y gastos del
    -- equipo" y de la revisión de un gasto; el mismo número que los "por revisar" de esa pantalla)
    BEGIN
        DECLARE v_sin_vi TINYINT DEFAULT 0;
        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            SET v_gastos = NULL;
            DROP TEMPORARY TABLE IF EXISTS tmp_vi_alc;
        END;
        IF FN_PermisoAccion(p_id_usuario, 'prog_aprobar_reprogramacion') = 1 THEN
            CALL SP_ArmarAlcanceViaticosMovil(p_id_usuario, NULL, v_sin_vi);
            IF v_sin_vi = 0 THEN
                SELECT COUNT(*) INTO v_gastos
                FROM   gasto_viatico g
                JOIN   tmp_vi_alc a ON a.id_os = g.id_os
                WHERE  g.eliminado_en IS NULL AND g.tipo = 'gasto_solicitado' AND g.estado = 'pendiente';
            END IF;
            DROP TEMPORARY TABLE IF EXISTS tmp_vi_alc;
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
                      OR (v_aut_area IS NOT NULL AND (lf.area_destino IS NULL OR lf.area_destino = v_aut_area))))
           -- Evidencias forzadas y ensayos con error sin revisar (migración 113), por el área de la RQ
           + (SELECT COUNT(*)
              FROM   evidencia_fotografica f
              JOIN   orden_servicio os ON os.id_os = f.id_os AND os.eliminado_en IS NULL AND os.estado <> 'anulada'
              LEFT JOIN expediente_digital ed ON ed.id_expediente = os.id_expediente
              LEFT JOIN requerimiento rq      ON rq.id_requerimiento = ed.id_requerimiento
              LEFT JOIN area_servicio_rq asr  ON asr.id_area_rq = rq.id_area
              WHERE  f.eliminado_en IS NULL AND f.override_aprobado = 1 AND f.vigente = 1 AND f.revision_jefe IS NULL
                AND  (v_aut_general = 1 OR (v_aut_area IS NOT NULL AND (asr.area_usuario IS NULL OR asr.area_usuario = v_aut_area))))
           + (SELECT COUNT(*)
              FROM   informe_tecnico it
              JOIN   orden_servicio os ON os.id_os = it.id_os AND os.eliminado_en IS NULL AND os.estado <> 'anulada'
              LEFT JOIN expediente_digital ed ON ed.id_expediente = os.id_expediente
              LEFT JOIN requerimiento rq      ON rq.id_requerimiento = ed.id_requerimiento
              LEFT JOIN area_servicio_rq asr  ON asr.id_area_rq = rq.id_area
              WHERE  it.eliminado_en IS NULL AND it.error_critico_motivo IS NOT NULL AND it.error_critico_revision IS NULL
                AND  (v_aut_general = 1 OR (v_aut_area IS NOT NULL AND (asr.area_usuario IS NULL OR asr.area_usuario = v_aut_area))))
           -- Gastos pendientes: solo para quien los revisa (el mismo contador de la tarjeta Viáticos y Gastos)
           + IFNULL(v_gastos, 0)                                            AS aprobaciones_pendientes,
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
--     viatico_asignado        "Viático asignado: S/ …" (HU-35: el jefe le asignó viáticos; abre Viáticos y Gastos)
--     servicio                "Nueva programación: …" (se asignó un servicio) y "Servicio reprogramado: …" (HU-37: el jefe reasignó o reprogramó el servicio)
--     demora                  "Demora en ruta" (le llega a Operaciones)
--     ensayo_critico          "Ensayo con error crítico" (HU-10: le llega al encargado del área; el técnico pidió apoyo o aceptó guardar con una lectura fuera del EMP)
--     evidencia_forzada       "Evidencia forzada" (HU-12: una foto rechazada por la IA que el técnico aceptó con un motivo)
--     correlativo_solicitado  "Solicitud de correlativo enviada" (HU-14: confirmación al técnico) · correlativo_solicitud "Solicitud de correlativo" (HU-34: le llega al Jefe de
--                             Metrología) · correlativo_asignado "Correlativo asignado" (HU-14: Metrología asignó el correlativo; abre "Mis tickets"). entidad_tipo = ticket_metrologia.
--     equipo_nuevo            "Equipo nuevo por aprobar" (HU-07: equipo NEW registrado en campo)
--     servicio_detenido       "Servicio detenido: …" (Control de Campo)
--     informe_observado       "Informe observado: …" (HU-33: el jefe pidió una corrección; le llega al técnico, entidad_tipo = informe_tecnico) · informe_revisado "Informe revisado: …" (HU-59)
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
                    WHEN n.titulo LIKE 'Viático asignado%'                                                              THEN 'viatico_asignado'
                    WHEN n.titulo LIKE 'Nueva programación%' OR n.titulo LIKE 'Nuevo servicio%'
                         OR n.titulo LIKE 'Servicio reprogramado%'                                                       THEN 'servicio'
                    WHEN n.titulo LIKE 'Demora en ruta%'                                                                THEN 'demora'
                    WHEN n.titulo LIKE 'Ensayo con error cr%'                                                           THEN 'ensayo_critico'
                    WHEN n.titulo LIKE 'Evidencia forzada%'                                                             THEN 'evidencia_forzada'
                    WHEN n.titulo LIKE 'Equipo nuevo por aprobar%'                                                      THEN 'equipo_nuevo'
                    WHEN n.titulo LIKE 'Servicio detenido:%'                                                            THEN 'servicio_detenido'
                    WHEN n.titulo LIKE 'Informe observado%'                                                             THEN 'informe_observado'
                    WHEN n.titulo LIKE 'Informe revisado%'                                                              THEN 'informe_revisado'
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

-- ============================================================
-- VERIFICACIÓN (solo lectura: no crea datos)
-- ============================================================
SELECT 'Procedimientos HU-37 nuevos (deben ser 4)' AS verificacion,
       (SELECT COUNT(*) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = DATABASE() AND ROUTINE_TYPE = 'PROCEDURE'
          AND ROUTINE_NAME IN ('SP_ArmarEquipoAgendaMovil', 'SP_ObtenerAgendaAreaMovil', 'SP_ObtenerConflictoAgendaMovil', 'SP_ResolverConflictoAgendaMovil')) AS valor
UNION ALL
SELECT 'Equipo con los técnicos dados de baja para la agenda (debe ser 1)',
       (SELECT COUNT(*) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = DATABASE() AND ROUTINE_NAME = 'SP_ArmarEquipoJefaturaMovil' AND ROUTINE_DEFINITION LIKE '%tw_eq_inactivos%')
UNION ALL
SELECT 'Resolución de conflictos con el motivo elegido en la app (debe ser 1)',
       (SELECT COUNT(*) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = DATABASE() AND ROUTINE_NAME = 'SP_ResolverConflictoProgramacion' AND ROUTINE_DEFINITION LIKE '%tw_cf_motivo%')
UNION ALL
SELECT 'Menú de Jefatura con el alcance de la agenda (debe ser 1)',
       (SELECT COUNT(*) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = DATABASE() AND ROUTINE_NAME = 'SP_ObtenerMenuJefaturaMovil' AND ROUTINE_DEFINITION LIKE '%SP_ArmarEquipoAgendaMovil%')
UNION ALL
SELECT 'Notificaciones: Servicio reprogramado (debe ser 1)',
       (SELECT COUNT(*) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = DATABASE() AND ROUTINE_NAME = 'SP_ObtenerNotificacionesMovil' AND ROUTINE_DEFINITION LIKE '%Servicio reprogramado%')
UNION ALL
SELECT 'Requisitos previos: Programación de la intranet y el equipo de HU-36 (deben ser 6)',
       (SELECT COUNT(*) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = DATABASE()
          AND ROUTINE_NAME IN ('SP_ArmarBaseProgramacion', 'SP_ArmarConflictosProgramacion', 'SP_ObtenerConflictoProgramacion', 'SP_ReprogramarProgramacion', 'SP_ArmarSeguimientoOperativo', 'SP_ResolverAprobadorMovil'));
