-- HU-36 Mi equipo: asistencia y ubicación (Jefe de Área, app móvil) + horas contabilizadas con historial. Ejecutar con Alt+X (No al aviso) y reiniciar la API.
-- Requiere antes: _aplicar_aprobaciones_area_rol_movil.sql (SP_ResolverAprobadorMovil), los SP del Reloj marcador (HU-20: SP_EstadoJornadaMovil, migraciones 109 y 119) y el Seguimiento Operativo (SP_ArmarSeguimientoOperativo).
-- Crea las tablas del historial de horas (migración 123) y 5 procedimientos nuevos; actualiza SP_ObtenerMenuJefaturaMovil (mi_equipo_total / mi_equipo_en_labores salen de la misma fuente que Mi equipo).
-- No crea datos: el historial se llena solo, al consultar las horas de un técnico.

-- ============================================================
-- Migración 123 — Horas contabilizadas del técnico (HU-36 «Mi equipo», botón «Ver las horas contabilizadas», Jefe de Área, app móvil)
--   Las horas laboradas se cuentan «desde que inicia el servicio hasta que finaliza el servicio» (evento de campo INICIO_TRABAJO → primer CIERRE de cada OS/OM, ver SP_ConsolidarHorasTecnicoMovil)
--   y se GUARDAN como historial: lo que hizo cada técnico por día y por mes queda fijo aunque la fuente cambie después.
--     tecnico_horas_dia ........ una fila por técnico y día con actividad: minutos trabajados (unión de los servicios, sin doble conteo si se solapan), servicios, primera hora de inicio y última de
--                                fin (en minutos desde las 00:00, hora de Lima) y sin_cierre (hubo un servicio iniciado que nunca se cerró: no se inventa su duración, cuenta 0).
--     tecnico_horas_servicio ... el detalle de cada día: cada OS/OM con su inicio, fin y minutos (recortados a ese día si el servicio cruzó la medianoche).
--     tecnico_horas_mes ........ el resumen de cada mes (minutos, días trabajados, servicios). cerrado = 1 cuando el mes ya pasó: queda como FOTO y no se vuelve a recalcular.
--   Soft delete + auditoría. Sin FK. UNIQUE por (técnico, día), (técnico, día, OS) y (técnico, mes): así la consolidación es un UPSERT idempotente (como jornada_marcacion, migración 109).
--   No borra ni cambia datos existentes. IDEMPOTENTE.
-- ============================================================
CREATE TABLE IF NOT EXISTS tecnico_horas_dia (
    id_hora_dia    BIGINT      NOT NULL AUTO_INCREMENT,
    id_usuario     BIGINT      NOT NULL,
    fecha          DATE        NOT NULL,
    minutos        INT         NOT NULL DEFAULT 0,
    n_servicios    INT         NOT NULL DEFAULT 0,
    inicio_min     INT         NULL,
    fin_min        INT         NULL,
    sin_cierre     TINYINT     NOT NULL DEFAULT 0,
    calculado_en   DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    -- AUDITORÍA
    creado_en      DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por     BIGINT      NULL,
    modificado_en  DATETIME    NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por BIGINT      NULL,
    eliminado_en   DATETIME    NULL,
    eliminado_por  BIGINT      NULL,
    PRIMARY KEY (id_hora_dia),
    UNIQUE KEY ux_horas_dia_usuario_fecha (id_usuario, fecha)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS tecnico_horas_servicio (
    id_hora_servicio BIGINT      NOT NULL AUTO_INCREMENT,
    id_usuario       BIGINT      NOT NULL,
    fecha            DATE        NOT NULL,
    id_os            BIGINT      NOT NULL,
    numero           VARCHAR(20) NULL,
    inicio_dt        DATETIME    NOT NULL,
    fin_dt           DATETIME    NULL,
    minutos          INT         NOT NULL DEFAULT 0,
    sin_cierre       TINYINT     NOT NULL DEFAULT 0,
    -- AUDITORÍA
    creado_en        DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por       BIGINT      NULL,
    modificado_en    DATETIME    NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por   BIGINT      NULL,
    eliminado_en     DATETIME    NULL,
    eliminado_por    BIGINT      NULL,
    PRIMARY KEY (id_hora_servicio),
    UNIQUE KEY ux_horas_servicio_usuario_fecha_os (id_usuario, fecha, id_os)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS tecnico_horas_mes (
    id_hora_mes     BIGINT      NOT NULL AUTO_INCREMENT,
    id_usuario      BIGINT      NOT NULL,
    mes             DATE        NOT NULL,   -- primer día del mes
    minutos         INT         NOT NULL DEFAULT 0,
    dias_trabajados INT         NOT NULL DEFAULT 0,
    n_servicios     INT         NOT NULL DEFAULT 0,
    cerrado         TINYINT     NOT NULL DEFAULT 0,
    calculado_en    DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    -- AUDITORÍA
    creado_en       DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por      BIGINT      NULL,
    modificado_en   DATETIME    NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por  BIGINT      NULL,
    eliminado_en    DATETIME    NULL,
    eliminado_por   BIGINT      NULL,
    PRIMARY KEY (id_hora_mes),
    UNIQUE KEY ux_horas_mes_usuario_mes (id_usuario, mes)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

SELECT 'Migración 123 (debe ser 3)' AS verificacion,
       (SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE()
           AND TABLE_NAME IN ('tecnico_horas_dia', 'tecnico_horas_servicio', 'tecnico_horas_mes')) AS valor;

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
    WHERE  u.eliminado_en IS NULL AND u.estado = 'activo'
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

-- ============================================================
-- SP_ObtenerEquipoJefaturaMovil  (App Mobile HU-36 — «Mi equipo»: asistencia y ubicación de los técnicos de HOY · solo lectura)
-- El jefe ve a cada técnico de su equipo con su estado según el Reloj marcador (HU-20: en labores · refrigerio · tardanza · sin marcar · finalizada), el servicio que tiene hoy (OS u OM, su estado y la
-- planta) y su última ubicación. El equipo, el alcance Área + Rol y el estado de cada técnico los arma SP_ArmarEquipoJefaturaMovil (la MISMA fuente de los contadores del menú de Jefatura).
-- No exige un permiso propio: basta tener el menú de Jefatura (SP_ResolverAprobadorMovil); el Supervisor de Servicio Técnico / Metrología ve solo a su área.
-- Resultados: 1 mensaje · 2 KPIs (1 fila) · 3 técnicos (uno por fila; sin marcar y tardanza primero, luego refrigerio, en labores y finalizada; luego por nombre).
--   KPIs: en_labores · refrigerio · tardanza · sin_marcar · finalizaron (jornada finalizada) · total · en_jornada (= en_labores + tardanza + refrigerio: los que están en su jornada ahora; es el
--   «N de M en labores» del menú) · actualizado (HH:mm de Lima) · refresco_segundos.
--   Técnico: estado · detalle (texto armado: «En labores · 07:58 (tardanza 13 min)», «En refrigerio desde 10:30 · vuelve 11:15», «Sin marcar inicio de labores») · hora_inicio · minutos_tardanza ·
--   id_os / numero_os / tipo_os (OS u OM) / estado_servicio (el del seguimiento operativo) / lugar (planta) del servicio actual · motivo_sin_servicio (SSOMA bloqueado o con documentos
--   faltantes cuando no tiene servicio) · latitud / longitud / minutos_ubicacion (última posición GPS de hoy).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerEquipoJefaturaMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerEquipoJefaturaMovil(
    IN p_id_usuario BIGINT
)
proc: BEGIN
    DECLARE v_sin_menu TINYINT DEFAULT 0;
    DECLARE v_refresco INT DEFAULT 30;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_eq;
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

    CALL SP_ArmarEquipoJefaturaMovil(p_id_usuario, NULL, 1, v_sin_menu);
    IF v_sin_menu = 1 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_eq;
        CALL SP_LimpiarSeguimientoOperativo();
        SELECT 1 AS IdTipoMensaje, 'Tu cargo no tiene el menú de Jefatura.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_refresco = IFNULL((SELECT MAX(c.refresco) FROM tmp_sg_cfg c), 30);

    SELECT 2 AS IdTipoMensaje, 'OK' AS Mensaje;

    -- 2 KPIs
    SELECT IFNULL(SUM(e.estado = 'en_labores'), 0)                              AS en_labores,
           IFNULL(SUM(e.estado = 'refrigerio'), 0)                              AS refrigerio,
           IFNULL(SUM(e.estado = 'tardanza'), 0)                                AS tardanza,
           IFNULL(SUM(e.estado = 'sin_marcar'), 0)                              AS sin_marcar,
           IFNULL(SUM(e.estado = 'finalizada'), 0)                              AS finalizaron,
           COUNT(*)                                                             AS total,
           IFNULL(SUM(e.estado IN ('en_labores', 'tardanza', 'refrigerio')), 0) AS en_jornada,
           DATE_FORMAT(CONVERT_TZ(UTC_TIMESTAMP(), '+00:00', '-05:00'), '%H:%i') AS actualizado,
           v_refresco                                                           AS refresco_segundos
    FROM   tmp_eq e;

    -- 3 Técnicos
    SELECT e.id_usuario, e.nombre, e.iniciales, e.cargo, e.estado, e.detalle, e.hora_inicio, e.min_tardanza AS minutos_tardanza,
           e.id_os, e.numero_os, e.tipo_os, e.estado_servicio, e.lugar, e.motivo_sin AS motivo_sin_servicio,
           e.latitud, e.longitud, e.min_ubic AS minutos_ubicacion
    FROM   tmp_eq e
    ORDER BY e.orden, e.nombre, e.id_usuario;

    DROP TEMPORARY TABLE IF EXISTS tmp_eq;
    CALL SP_LimpiarSeguimientoOperativo();
END$$

DELIMITER ;

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
--                               conflictos). Solo con prog_bandeja; en Servicio Técnico y Metrología, los de técnicos de su área.
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

    -- Agenda del Área: conflictos sobrevenidos de la Programación (HU-39)
    BEGIN
        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            CALL SP_LimpiarConflictosProgramacion();
            SET v_conflictos = NULL;
        END;
        IF FN_PermisoAccion(p_id_usuario, 'prog_bandeja') = 1 THEN
            CALL SP_ArmarConflictosProgramacion();
            SELECT COUNT(*) INTO v_conflictos
            FROM   tmp_cf c
            WHERE  v_area NOT IN ('servicio_tecnico', 'metrologia')
                   OR EXISTS (SELECT 1 FROM usuario t WHERE t.id_usuario = c.id_usuario AND t.area = v_area);
            CALL SP_LimpiarConflictosProgramacion();
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
-- VERIFICACIÓN (solo lectura: no crea datos)
-- ============================================================
SELECT 'Tablas del historial de horas, migración 123 (deben ser 3)' AS verificacion,
       (SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME IN ('tecnico_horas_dia', 'tecnico_horas_servicio', 'tecnico_horas_mes')) AS valor
UNION ALL
SELECT 'Procedimientos HU-36 (deben ser 6)',
       (SELECT COUNT(*) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = DATABASE() AND ROUTINE_TYPE = 'PROCEDURE'
          AND ROUTINE_NAME IN ('SP_ArmarEquipoJefaturaMovil', 'SP_ConsolidarHorasTecnicoMovil', 'SP_ObtenerEquipoJefaturaMovil', 'SP_ObtenerFichaEquipoTecnicoMovil',
                               'SP_ObtenerHorasTecnicoMovil', 'SP_ObtenerMenuJefaturaMovil'))
UNION ALL
SELECT 'Menú de Jefatura con la fuente de Mi equipo (debe ser 1)',
       (SELECT COUNT(*) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = DATABASE() AND ROUTINE_NAME = 'SP_ObtenerMenuJefaturaMovil' AND ROUTINE_DEFINITION LIKE '%SP_ArmarEquipoJefaturaMovil%')
UNION ALL
SELECT 'Requisitos previos: SP_ResolverAprobadorMovil, SP_EstadoJornadaMovil y SP_ArmarSeguimientoOperativo (deben ser 3)',
       (SELECT COUNT(*) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = DATABASE() AND ROUTINE_NAME IN ('SP_ResolverAprobadorMovil', 'SP_EstadoJornadaMovil', 'SP_ArmarSeguimientoOperativo'));
