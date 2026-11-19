-- ============================================================
-- SP_ObtenerFichaEquipoTecnicoMovil  (App Mobile HU-36 — «Ficha del técnico» de Mi equipo · solo lectura)
-- El jefe abre un técnico de su equipo y ve: su estado de hoy (el mismo de la lista), su cargo, área y teléfono (para llamarlo), su SSOMA, las marcaciones del día (línea de tiempo del Reloj marcador
-- con las demoras registradas y el siguiente paso pendiente) y la CARGA DE LA SEMANA (horas programadas de lunes a viernes).
-- Alcance: el técnico debe estar en el equipo del jefe (SP_ArmarEquipoJefaturaMovil: regla Área + Rol); si no → «El técnico no pertenece a tu equipo.».
-- SSOMA: SP_EvaluarSsomaProgramacion (la regla de la Programación) contra la orden que el técnico tiene hoy; sin orden, contra los requisitos generales. Estado: conforme · por_vencer · incompleto ·
--   pendiente · bloqueado; el detalle dice qué documento falta o está bloqueado.
-- Carga de la semana: fuente = las órdenes (OS/OM) programadas del técnico —como principal o en el personal— de la semana de HOY (lunes a viernes; el sábado solo si tiene servicios), en estado
--   programada · reprogramada · en_ruta · en_ejecucion · pausada · bloqueada · finalizada, sumando sus horas programadas (hora_fin_estimada - hora_inicio de la orden: la MISMA fuente que
--   SP_BuscarTecnicosProgramacion usa para la carga del día). Capacidad = 5 días × HORAS_JORNADA (PARAMETRO_PROGRAMACION, 8 h por defecto). Utilización = planificadas / capacidad;
--   nivel: menos de 50 % «baja», de 50 a 84 % «normal», 85 % o más «alta». Porcentaje de cada día = horas del día / HORAS_JORNADA (puede pasar de 100).
-- Resultados: 1 mensaje · 2 técnico (1 fila: lo de la lista + telefono, area, ssoma y ssoma_detalle) · 3 marcaciones (línea de tiempo) · 4 carga por día · 5 resumen de la carga (1 fila).
--   Marcación: tipo · titulo · hora (HH:mm de Lima; NULL si está pendiente) · detalle · estado (hecho | pendiente) · tono (verde | naranja | rojo | gris).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerFichaEquipoTecnicoMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerFichaEquipoTecnicoMovil(
    IN p_id_usuario BIGINT,
    IN p_id_tecnico BIGINT
)
proc: BEGIN
    DECLARE v_sin_menu  TINYINT DEFAULT 0;
    DECLARE v_existe    INT DEFAULT 0;
    DECLARE v_hoy       DATE;
    DECLARE v_lunes     DATE;
    DECLARE v_hasta     DATE;
    DECLARE v_id_os     BIGINT DEFAULT NULL;
    DECLARE v_siguiente VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_ini_prog  DECIMAL(18,6);
    DECLARE v_ini_txt   VARCHAR(5) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_param     DECIMAL(18,6);
    DECLARE v_jornada   DECIMAL(8,2) DEFAULT 8;
    DECLARE v_horas     DECIMAL(8,2) DEFAULT 0;
    DECLARE v_capacidad DECIMAL(8,2) DEFAULT 40;
    DECLARE v_pct       INT DEFAULT 0;
    DECLARE v_nivel     VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT 'baja';

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_eq;
        DROP TEMPORARY TABLE IF EXISTS tmp_eq_marc;
        DROP TEMPORARY TABLE IF EXISTS tmp_eq_dias;
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

    SET v_hoy = DATE(CONVERT_TZ(UTC_TIMESTAMP(), '+00:00', '-05:00'));
    SELECT MAX(e.id_os), MAX(e.siguiente) INTO v_id_os, v_siguiente FROM tmp_eq e;

    -- SSOMA contra la orden que tiene hoy (SP_ArmarEquipoJefaturaMovil la evaluó contra los requisitos generales)
    IF v_id_os IS NOT NULL THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_ssoma_in;
        CREATE TEMPORARY TABLE tmp_ssoma_in (id_usuario BIGINT NOT NULL, PRIMARY KEY (id_usuario));
        INSERT INTO tmp_ssoma_in (id_usuario) VALUES (p_id_tecnico);
        CALL SP_EvaluarSsomaProgramacion(v_id_os, v_hoy);
        UPDATE tmp_eq t
        JOIN   tmp_ssoma_res s ON s.id_usuario = t.id_usuario
        SET    t.ssoma = s.estado,
               t.ssoma_detalle = LEFT(CASE WHEN s.estado = 'bloqueado' THEN IFNULL(NULLIF(s.motivo_bloqueo, ''), 'SSOMA bloqueado')
                                           WHEN s.estado IN ('pendiente', 'incompleto') THEN CONCAT('Falta documento SSOMA', IF(IFNULL(s.faltantes, '') = '', '', CONCAT(': ', s.faltantes)))
                                           WHEN s.estado = 'por_vencer' THEN 'SSOMA por vencer'
                                           ELSE NULL END, 250);
        DROP TEMPORARY TABLE IF EXISTS tmp_ssoma_in;
        CALL SP_LimpiarSsomaProgramacion();
    END IF;

    -- ── Marcaciones del día (línea de tiempo) ──────────────────────────────────────────────────────────────────────
    CALL SP_LeerParametroProgramacion('JORNADA_INICIO_MIN', 465, v_ini_prog);
    SET v_ini_txt = TIME_FORMAT(SEC_TO_TIME(CAST(v_ini_prog AS SIGNED) * 60), '%H:%i');

    DROP TEMPORARY TABLE IF EXISTS tmp_eq_marc;
    CREATE TEMPORARY TABLE tmp_eq_marc (
        id      INT          NOT NULL AUTO_INCREMENT,
        instante DATETIME,
        tipo    VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        titulo  VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        hora    CHAR(5)      CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        detalle VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        estado  VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        tono    VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        PRIMARY KEY (id)
    );

    -- Inicio de labores, refrigerio y fin de labores (la salida de planta se arma aparte: puede haber varias)
    INSERT INTO tmp_eq_marc (instante, tipo, titulo, hora, detalle, estado, tono)
    SELECT CONVERT_TZ(j.marcado_utc, '+00:00', '-05:00'), j.tipo,
           CASE j.tipo WHEN 'inicio_labores' THEN 'Inicio de labores' WHEN 'inicio_refrigerio' THEN 'Inicio de refrigerio'
                       WHEN 'fin_refrigerio' THEN 'Fin de refrigerio' WHEN 'fin_labores' THEN 'Fin de labores' ELSE j.tipo END,
           DATE_FORMAT(CONVERT_TZ(j.marcado_utc, '+00:00', '-05:00'), '%H:%i'),
           LEFT(CASE WHEN j.tipo = 'inicio_labores'
                     THEN CONCAT(IF(j.puntualidad = 'tardanza', CONCAT('Tardanza ', IFNULL(j.minutos_diferencia, 0), ' min (programado ', v_ini_txt, ')'), 'A tiempo'),
                                 IF(NULLIF(j.lugar, '') IS NULL, '', CONCAT(' · ', j.lugar)))
                     ELSE NULLIF(CONCAT_WS(' · ', NULLIF(j.lugar, ''), IF(j.sin_conexion = 1, 'marcada sin conexión', NULL)), '') END, 250),
           'hecho',
           IF(j.tipo = 'inicio_labores' AND j.puntualidad = 'tardanza', 'naranja', 'verde')
    FROM   jornada_marcacion j
    WHERE  j.id_usuario = p_id_tecnico AND j.fecha = v_hoy AND j.tipo <> 'salida_planta';

    -- Salidas de planta: una por servicio concluido (jornada_salida, HU-20); si es un día anterior a esa tabla, la marcación única del día
    INSERT INTO tmp_eq_marc (instante, tipo, titulo, hora, detalle, estado, tono)
    SELECT CONVERT_TZ(s.marcado_utc, '+00:00', '-05:00'), 'salida_planta', 'Salida de planta',
           DATE_FORMAT(CONVERT_TZ(s.marcado_utc, '+00:00', '-05:00'), '%H:%i'),
           LEFT(NULLIF(CONCAT_WS(' · ', os.numero, NULLIF(s.lugar, '')), ''), 250), 'hecho', 'verde'
    FROM   jornada_salida s
    LEFT JOIN orden_servicio os ON os.id_os = s.id_os
    WHERE  s.id_usuario = p_id_tecnico AND s.fecha = v_hoy;
    INSERT INTO tmp_eq_marc (instante, tipo, titulo, hora, detalle, estado, tono)
    SELECT CONVERT_TZ(j.marcado_utc, '+00:00', '-05:00'), 'salida_planta', 'Salida de planta',
           DATE_FORMAT(CONVERT_TZ(j.marcado_utc, '+00:00', '-05:00'), '%H:%i'), LEFT(NULLIF(j.lugar, ''), 250), 'hecho', 'verde'
    FROM   jornada_marcacion j
    WHERE  j.id_usuario = p_id_tecnico AND j.fecha = v_hoy AND j.tipo = 'salida_planta'
      AND  NOT EXISTS (SELECT 1 FROM jornada_salida s2 WHERE s2.id_usuario = p_id_tecnico AND s2.fecha = v_hoy);

    -- Demoras e incidencias que registró hoy (las mismas del seguimiento operativo)
    INSERT INTO tmp_eq_marc (instante, tipo, titulo, hora, detalle, estado, tono)
    SELECT i.fecha, 'demora', 'Demora registrada', DATE_FORMAT(i.fecha, '%H:%i'),
           LEFT(CONCAT(CASE i.fase WHEN 'llegada' THEN 'Llegada a planta' WHEN 'ingreso' THEN 'Ingreso a planta' ELSE IFNULL(i.tipo, 'Incidencia') END,
                       IF(i.duracion_min IS NULL, '', CONCAT(' +', i.duracion_min, ' min')),
                       IF(NULLIF(i.descripcion, '') IS NULL, '', CONCAT(' · ', i.descripcion))), 250),
           'hecho', IF(i.impacto = 'detiene', 'rojo', 'naranja')
    FROM   tmp_sg_inc i
    WHERE  i.id_usuario = p_id_tecnico;

    -- Lo que sigue en la jornada (pendiente)
    IF v_siguiente IS NOT NULL THEN
        INSERT INTO tmp_eq_marc (instante, tipo, titulo, hora, detalle, estado, tono)
        VALUES ('9999-12-31 00:00:00', v_siguiente,
                CASE v_siguiente WHEN 'inicio_labores' THEN 'Inicio de labores' WHEN 'inicio_refrigerio' THEN 'Inicio de refrigerio' WHEN 'fin_refrigerio' THEN 'Fin de refrigerio'
                                 WHEN 'salida_planta' THEN 'Salida de planta' WHEN 'fin_labores' THEN 'Fin de labores' ELSE v_siguiente END,
                NULL, 'Pendiente', 'pendiente', 'gris');
    END IF;

    -- ── Carga de la semana (lunes a sábado de la semana de hoy) ───────────────────────────────────────────────────
    CALL SP_LeerParametroProgramacion('HORAS_JORNADA', 8, v_param);
    SET v_jornada   = IF(v_param BETWEEN 1 AND 24, v_param, 8);
    SET v_capacidad = v_jornada * 5;
    SET v_lunes     = DATE_SUB(v_hoy, INTERVAL WEEKDAY(v_hoy) DAY);

    DROP TEMPORARY TABLE IF EXISTS tmp_eq_dias;
    CREATE TEMPORARY TABLE tmp_eq_dias (
        n        INT          NOT NULL,
        fecha    DATE         NOT NULL,
        etiqueta VARCHAR(3)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        horas    DECIMAL(8,2) NOT NULL DEFAULT 0,
        servicios INT         NOT NULL DEFAULT 0,
        PRIMARY KEY (n)
    );
    INSERT INTO tmp_eq_dias (n, fecha, etiqueta) VALUES
        (0, v_lunes, 'Lun'), (1, DATE_ADD(v_lunes, INTERVAL 1 DAY), 'Mar'), (2, DATE_ADD(v_lunes, INTERVAL 2 DAY), 'Mié'),
        (3, DATE_ADD(v_lunes, INTERVAL 3 DAY), 'Jue'), (4, DATE_ADD(v_lunes, INTERVAL 4 DAY), 'Vie'), (5, DATE_ADD(v_lunes, INTERVAL 5 DAY), 'Sáb');

    UPDATE tmp_eq_dias d
    SET d.horas = IFNULL((SELECT ROUND(SUM(CASE WHEN os.hora_inicio IS NOT NULL AND os.hora_fin_estimada IS NOT NULL AND os.hora_fin_estimada > os.hora_inicio
                                                THEN TIME_TO_SEC(TIMEDIFF(os.hora_fin_estimada, os.hora_inicio)) / 3600 END), 2)
                          FROM   orden_servicio os
                          WHERE  os.eliminado_en IS NULL AND os.fecha_ejecucion = d.fecha
                            AND  os.estado IN ('programada', 'reprogramada', 'en_ruta', 'en_ejecucion', 'pausada', 'bloqueada', 'finalizada')
                            AND  (os.id_tecnico_principal = p_id_tecnico
                                  OR EXISTS (SELECT 1 FROM os_personal op WHERE op.id_os = os.id_os AND op.id_usuario = p_id_tecnico AND op.eliminado_en IS NULL))), 0),
        d.servicios = (SELECT COUNT(*)
                       FROM   orden_servicio os
                       WHERE  os.eliminado_en IS NULL AND os.fecha_ejecucion = d.fecha
                         AND  os.estado IN ('programada', 'reprogramada', 'en_ruta', 'en_ejecucion', 'pausada', 'bloqueada', 'finalizada')
                         AND  (os.id_tecnico_principal = p_id_tecnico
                               OR EXISTS (SELECT 1 FROM os_personal op WHERE op.id_os = os.id_os AND op.id_usuario = p_id_tecnico AND op.eliminado_en IS NULL)));

    -- El sábado solo si tiene servicios
    DELETE FROM tmp_eq_dias WHERE n = 5 AND servicios = 0 AND horas = 0;
    SELECT MAX(d.fecha), IFNULL(SUM(d.horas), 0) INTO v_hasta, v_horas FROM tmp_eq_dias d;
    SET v_pct   = IF(v_capacidad > 0, ROUND(v_horas * 100 / v_capacidad), 0);
    SET v_nivel = CASE WHEN v_pct >= 85 THEN 'alta' WHEN v_pct >= 50 THEN 'normal' ELSE 'baja' END;

    -- ── Resultados ─────────────────────────────────────────────────────────────────────────────────────────────────
    SELECT 2 AS IdTipoMensaje, 'OK' AS Mensaje;

    -- 2 Técnico
    SELECT e.id_usuario, e.nombre, e.iniciales, e.cargo, e.estado, e.detalle, e.hora_inicio, e.min_tardanza AS minutos_tardanza,
           e.id_os, e.numero_os, e.tipo_os, e.estado_servicio, e.lugar, e.motivo_sin AS motivo_sin_servicio,
           e.latitud, e.longitud, e.min_ubic AS minutos_ubicacion,
           e.telefono, e.area, e.ssoma AS ssoma_estado, e.ssoma_detalle
    FROM   tmp_eq e;

    -- 3 Marcaciones
    SELECT m.tipo, m.titulo, m.hora, m.detalle, m.estado, m.tono
    FROM   tmp_eq_marc m
    ORDER BY m.instante, m.id;

    -- 4 Carga por día
    SELECT DATE_FORMAT(d.fecha, '%Y-%m-%d') AS fecha, d.etiqueta AS etiqueta, d.horas AS horas, ROUND(d.horas * 100 / v_jornada) AS porcentaje
    FROM   tmp_eq_dias d
    ORDER BY d.n;

    -- 5 Resumen de la carga
    SELECT DATE_FORMAT(v_lunes, '%Y-%m-%d') AS desde, DATE_FORMAT(v_hasta, '%Y-%m-%d') AS hasta, v_pct AS utilizacion_pct, v_nivel AS nivel,
           v_horas AS horas_planificadas, v_capacidad AS horas_capacidad;

    DROP TEMPORARY TABLE IF EXISTS tmp_eq_marc;
    DROP TEMPORARY TABLE IF EXISTS tmp_eq_dias;
    DROP TEMPORARY TABLE IF EXISTS tmp_eq;
    CALL SP_LimpiarSeguimientoOperativo();
END$$

DELIMITER ;
