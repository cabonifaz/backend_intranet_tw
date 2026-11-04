-- HU-36 (Sprint 5) Buscador de técnicos de la ficha "Programar Servicio" y del modal "Asignar Recurso". Solo lectura.
-- Acceso: prog_gestionar (módulo operaciones).
-- Parámetros (todos opcionales salvo el usuario y la orden):
--   p_fecha, p_hora_inicio, p_hora_fin: cronograma elegido; con él se calcula la disponibilidad. Sin horario la
--     disponibilidad es 'sin_horario' y solo se informa la carga del día.
--   p_solo_disponibles = 1: solo técnicos sin otro servicio que se cruce con el horario.
--   p_solo_ssoma_conforme = 1: solo técnicos con todos los requisitos del cliente al día (conforme o por vencer, como en el
--     mockup: "Pedro Salazar · SSOMA por vencer" sigue en la lista con el filtro activo).
--   p_busqueda: nombre o cargo · p_sede_operativa: código de SEDE_OPERATIVA_TW (lima_central, arequipa).
--   p_tipo_recurso: pestaña del modal: tecnico · metrologo · externo (vacío = todos). Proveedor externo todavía no tiene
--     registro propio en el sistema: devuelve la lista vacía y su contador en 0.
-- Técnico = usuario activo de servicio técnico o metrología, sin jefaturas ni asistentes (la misma regla de la bandeja HU-35
--   y de SP_CrearProgramacion). tipo_recurso: metrologo (área metrología o cargo de metrólogo) o tecnico.
-- SSOMA: lo evalúa SP_EvaluarSsomaProgramacion contra los requisitos del cliente / zona de la orden (ver su cabecera):
--   conforme · por_vencer · incompleto (falta un documento, no bloquea) · pendiente (falta un documento exigido) · bloqueado.
-- Disponibilidad: otro servicio activo del técnico (como principal o en el personal) el mismo día con horario cruzado.
-- Panel lateral: carga del día (servicios y horas, cupo libre según SERVICIOS_MAX_DIA y horas libres según HORAS_JORNADA),
--   experiencia con el cliente (alta >= 5 servicios finalizados, media 1 a 4, sin_experiencia 0), scorecard del último mes
--   (porcentaje, nivel y servicios evaluados) y sede operativa.
-- No usa funciones almacenadas: crearlas exige el privilegio SUPER cuando el registro binario está activo.
-- Resultados: 1 mensaje, 2 técnicos, 3 detalle SSOMA por técnico (requisitos del cliente y demás documentos),
--   4 contadores por pestaña (tecnico, metrologo, externo) con los filtros de búsqueda y sede.
DROP PROCEDURE IF EXISTS SP_BuscarTecnicosProgramacion;

DELIMITER $$

CREATE PROCEDURE SP_BuscarTecnicosProgramacion(
    IN p_id_usuario          BIGINT,
    IN p_id_os               BIGINT,
    IN p_fecha               DATE,
    IN p_hora_inicio         TIME,
    IN p_hora_fin            TIME,
    IN p_solo_disponibles    TINYINT,
    IN p_solo_ssoma_conforme TINYINT,
    IN p_busqueda            VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_sede_operativa      VARCHAR(60)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_tipo_recurso        VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_fecha      DATE;
    DECLARE v_id_cliente BIGINT DEFAULT NULL;
    DECLARE v_busqueda   VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_sede       VARCHAR(60)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tipo       VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_horario    TINYINT DEFAULT 0;
    DECLARE v_param      DECIMAL(18,6);
    DECLARE v_max_dia    INT DEFAULT 4;
    DECLARE v_jornada    DECIMAL(5,1) DEFAULT 8;

    IF FN_PermisoAccion(p_id_usuario, 'prog_gestionar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para programar servicios.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM orden_servicio WHERE id_os = p_id_os AND eliminado_en IS NULL) THEN
        SELECT 1 AS IdTipoMensaje, 'La orden de servicio no existe.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF p_hora_inicio IS NOT NULL AND p_hora_fin IS NOT NULL AND p_hora_fin <= p_hora_inicio THEN
        SELECT 1 AS IdTipoMensaje, 'La hora fin debe ser posterior a la hora de inicio.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_tipo = LOWER(TRIM(IFNULL(p_tipo_recurso, '')));
    IF v_tipo NOT IN ('', 'todos', 'tecnico', 'metrologo', 'externo') THEN
        SELECT 1 AS IdTipoMensaje, 'El tipo de recurso no es válido.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_tipo = 'todos' THEN SET v_tipo = ''; END IF;

    SELECT id_cliente INTO v_id_cliente FROM orden_servicio WHERE id_os = p_id_os AND eliminado_en IS NULL;

    CALL SP_LeerParametroProgramacion('SERVICIOS_MAX_DIA', 4, v_param);
    SET v_max_dia  = IF(v_param BETWEEN 1 AND 20, ROUND(v_param), 4);
    CALL SP_LeerParametroProgramacion('HORAS_JORNADA', 8, v_param);
    SET v_jornada  = IF(v_param BETWEEN 1 AND 24, v_param, 8);

    SET v_fecha    = IFNULL(p_fecha, CURDATE());
    SET v_busqueda = TRIM(IFNULL(p_busqueda, ''));
    SET v_sede     = TRIM(IFNULL(p_sede_operativa, ''));
    SET v_horario  = IF(p_fecha IS NOT NULL AND p_hora_inicio IS NOT NULL AND p_hora_fin IS NOT NULL, 1, 0);

    DROP TEMPORARY TABLE IF EXISTS tmp_prg_cand;
    DROP TEMPORARY TABLE IF EXISTS tmp_prg_dia;
    DROP TEMPORARY TABLE IF EXISTS tmp_prg_carga;
    DROP TEMPORARY TABLE IF EXISTS tmp_prg_conf;
    DROP TEMPORARY TABLE IF EXISTS tmp_ssoma_in;

    -- Técnicos candidatos (búsqueda y sede; la pestaña se aplica al final para poder contar cada una)
    CREATE TEMPORARY TABLE tmp_prg_cand AS
    SELECT u.id_usuario,
           TRIM(CONCAT(u.nombre, ' ', u.apellido))  AS nombre,
           COALESCE(c.String1, u.cargo, IF(u.area = 'metrologia', 'Metrología', 'Servicio Técnico')) AS cargo,
           u.area,
           IF(u.area = 'metrologia' OR IFNULL(u.cargo, '') LIKE 'metrologo%', 'metrologo', 'tecnico') AS tipo_recurso,
           u.sede_operativa,
           so.String1                               AS sede_operativa_nombre
    FROM usuario u
    LEFT JOIN tabla_maestra c  ON c.IdMaestro = 80 AND c.IdEmpresa = 1 AND c.String2 = u.cargo
    LEFT JOIN tabla_maestra so ON so.IdMaestro = 69 AND so.IdEmpresa = 1 AND so.String2 = u.sede_operativa
    WHERE u.eliminado_en IS NULL
      AND u.estado = 'activo'
      AND u.area IN ('servicio_tecnico', 'metrologia')
      AND (u.cargo IS NULL OR (u.cargo NOT LIKE 'jefe\_%' AND u.cargo NOT LIKE 'asistente\_%'))
      AND (v_busqueda = '' OR CONCAT(u.nombre, ' ', u.apellido) LIKE CONCAT('%', v_busqueda, '%')
                           OR u.cargo   LIKE CONCAT('%', v_busqueda, '%')
                           OR c.String1 LIKE CONCAT('%', v_busqueda, '%'))
      AND (v_sede = '' OR u.sede_operativa = v_sede);

    -- SSOMA de cada candidato contra los requisitos del cliente / zona (misma regla que al crear)
    CREATE TEMPORARY TABLE tmp_ssoma_in (id_usuario BIGINT NOT NULL, PRIMARY KEY (id_usuario));
    INSERT INTO tmp_ssoma_in (id_usuario) SELECT id_usuario FROM tmp_prg_cand;
    CALL SP_EvaluarSsomaProgramacion(p_id_os, v_fecha);

    -- Servicios activos de esa fecha de los técnicos (como principal o en el personal), sin contar esta orden
    CREATE TEMPORARY TABLE tmp_prg_dia AS
    SELECT x.id_usuario, x.id_os, x.numero, x.hora_inicio, x.hora_fin
    FROM (
        SELECT os.id_tecnico_principal AS id_usuario, os.id_os, os.numero, os.hora_inicio, os.hora_fin_estimada AS hora_fin
        FROM orden_servicio os
        WHERE os.eliminado_en IS NULL AND os.fecha_ejecucion = v_fecha AND os.id_os <> p_id_os
          AND os.estado IN ('programada', 'reprogramada', 'en_ruta', 'en_ejecucion', 'pausada', 'bloqueada')
          AND os.id_tecnico_principal IS NOT NULL
        UNION
        SELECT pe.id_usuario, os.id_os, os.numero, os.hora_inicio, os.hora_fin_estimada
        FROM os_personal pe
        JOIN orden_servicio os ON os.id_os = pe.id_os
        WHERE pe.eliminado_en IS NULL AND os.eliminado_en IS NULL AND os.fecha_ejecucion = v_fecha AND os.id_os <> p_id_os
          AND os.estado IN ('programada', 'reprogramada', 'en_ruta', 'en_ejecucion', 'pausada', 'bloqueada')
    ) x;

    CREATE TEMPORARY TABLE tmp_prg_carga AS
    SELECT d.id_usuario,
           COUNT(DISTINCT d.id_os) AS servicios,
           IFNULL(ROUND(SUM(CASE WHEN d.hora_inicio IS NOT NULL AND d.hora_fin IS NOT NULL AND d.hora_fin > d.hora_inicio
                                 THEN TIME_TO_SEC(TIMEDIFF(d.hora_fin, d.hora_inicio)) / 3600 END), 2), 0) AS horas
    FROM tmp_prg_dia d
    GROUP BY d.id_usuario;

    CREATE TEMPORARY TABLE tmp_prg_conf AS
    SELECT d.id_usuario, MIN(d.numero) AS numero, MIN(d.hora_inicio) AS hora_inicio, MAX(d.hora_fin) AS hora_fin
    FROM tmp_prg_dia d
    WHERE v_horario = 1
      AND d.hora_inicio IS NOT NULL AND d.hora_fin IS NOT NULL
      AND d.hora_inicio < p_hora_fin AND d.hora_fin > p_hora_inicio
    GROUP BY d.id_usuario;

    -- 1. Header
    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Técnicos (la pestaña y los filtros "solo disponibles" / "con SSOMA conforme" se aplican aquí)
    SELECT c.id_usuario, c.nombre, c.cargo, c.area, c.tipo_recurso, c.sede_operativa, c.sede_operativa_nombre,
           CASE WHEN v_horario = 0 THEN 'sin_horario'
                WHEN f.id_usuario IS NOT NULL THEN 'ocupado'
                ELSE 'disponible'
           END                                                    AS disponibilidad,
           f.numero                                               AS conflicto_os,
           TIME_FORMAT(f.hora_inicio, '%H:%i')                    AS conflicto_desde,
           TIME_FORMAT(f.hora_fin, '%H:%i')                       AS conflicto_hasta,
           IFNULL(k.servicios, 0)                                 AS servicios_dia,
           IFNULL(k.horas, 0)                                     AS horas_dia,
           v_max_dia                                              AS servicios_max_dia,
           GREATEST(v_max_dia - IFNULL(k.servicios, 0), 0)        AS cupo_libre,
           GREATEST(ROUND(v_jornada - IFNULL(k.horas, 0), 2), 0)  AS horas_libres,
           IFNULL(s.estado, 'conforme')                           AS ssoma_estado,
           NULLIF(s.motivo_bloqueo, '')                           AS ssoma_motivo,
           s.faltantes                                            AS ssoma_faltantes,
           IFNULL(s.n_requeridos, 0)                              AS ssoma_requeridos,
           IFNULL(s.n_cumplidos, 0)                               AS ssoma_cumplidos,
           c.servicios_cliente,
           CASE WHEN c.servicios_cliente >= 5 THEN 'alta'
                WHEN c.servicios_cliente >= 1 THEN 'media'
                ELSE 'sin_experiencia'
           END                                                    AS experiencia_cliente,
           sc.score_general                                       AS scorecard_pct,
           sc.nivel                                               AS scorecard_nivel,
           sc.servicios_completados                               AS scorecard_servicios
    FROM (SELECT t.*,
                 (SELECT COUNT(*) FROM orden_servicio o2
                  WHERE o2.id_cliente = v_id_cliente AND o2.id_tecnico_principal = t.id_usuario
                    AND o2.estado = 'finalizada' AND o2.eliminado_en IS NULL) AS servicios_cliente
          FROM tmp_prg_cand t
          WHERE v_tipo = '' OR t.tipo_recurso = v_tipo) c
    LEFT JOIN tmp_prg_carga k ON k.id_usuario = c.id_usuario
    LEFT JOIN tmp_prg_conf  f ON f.id_usuario = c.id_usuario
    LEFT JOIN tmp_ssoma_res s ON s.id_usuario = c.id_usuario
    LEFT JOIN (SELECT x.id_usuario, x.score_general, x.nivel, x.servicios_completados
               FROM tecnico_scorecard x
               WHERE x.eliminado_en IS NULL
                 AND x.id_scorecard = (SELECT y.id_scorecard FROM tecnico_scorecard y
                                       WHERE y.id_usuario = x.id_usuario AND y.eliminado_en IS NULL
                                       ORDER BY y.periodo_mes DESC, y.id_scorecard DESC LIMIT 1)) sc
           ON sc.id_usuario = c.id_usuario
    WHERE (IFNULL(p_solo_disponibles, 0) = 0 OR v_horario = 0 OR f.id_usuario IS NULL)
      AND (IFNULL(p_solo_ssoma_conforme, 0) = 0 OR IFNULL(s.estado, 'conforme') IN ('conforme', 'por_vencer'))
    ORDER BY (f.id_usuario IS NOT NULL), (IFNULL(s.estado, 'conforme') IN ('bloqueado', 'pendiente')), c.nombre;

    -- 3. Detalle SSOMA por técnico: requisitos del cliente / zona y demás documentos (último de cada tipo)
    SELECT d.id_usuario, d.requisito, d.requerido, d.bloquea, d.estado_doc AS estado, d.fecha_vencimiento, d.situacion
    FROM tmp_ssoma_det d
    JOIN tmp_prg_cand c ON c.id_usuario = d.id_usuario
    WHERE v_tipo = '' OR c.tipo_recurso = v_tipo
    ORDER BY d.id_usuario, d.requerido DESC, d.requisito;

    -- 4. Contadores por pestaña del modal (con la búsqueda y la sede; sin los filtros de disponibilidad ni SSOMA)
    SELECT IFNULL(SUM(c.tipo_recurso = 'tecnico'), 0)   AS tecnicos,
           IFNULL(SUM(c.tipo_recurso = 'metrologo'), 0) AS metrologos,
           0                                            AS externos
    FROM tmp_prg_cand c;

    CALL SP_LimpiarSsomaProgramacion();
    DROP TEMPORARY TABLE IF EXISTS tmp_ssoma_in;
    DROP TEMPORARY TABLE IF EXISTS tmp_prg_conf;
    DROP TEMPORARY TABLE IF EXISTS tmp_prg_carga;
    DROP TEMPORARY TABLE IF EXISTS tmp_prg_dia;
    DROP TEMPORARY TABLE IF EXISTS tmp_prg_cand;
END$$

DELIMITER ;
