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
