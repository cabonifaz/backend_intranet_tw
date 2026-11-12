-- HU-52 (Sprint 5) Pestaña Aprobaciones del Detalle del Servicio en Ruta: una sola lista con todo lo que el encargado aprueba en esa OS. SOLO LECTURA.
--   salida    autorizacion_salida_os (App Mobile HU-04)
--   llegada   llegada_forzada_os (migración 111, HU-06)
--   evidencia evidencia_fotografica forzada por el técnico (override_aprobado, motivo_forzado, HU-12); revisión en revision_jefe (migración 113)
--   ensayo    informe_tecnico guardado con error crítico (error_critico_motivo, migraciones 100 y 107); revisión en error_critico_revision (113)
-- Acceso: seg_bandeja y el servicio en la jornada de hoy (SP_PrepararDetalleServicioRuta), igual que las demás pestañas.
-- puede_resolver: misma regla de área que SP_ObtenerAutorizacionesSalida / SP_ResolverLlegadaForzada: el encargado del área de la solicitud (o de la RQ
--   si la solicitud no la tiene), Jefe o Coordinador de Operaciones, supervisor de Operaciones o administrador. Salida y llegada: solo la última
--   solicitud pendiente de la OS (los SP de resolver actúan sobre esa); la salida, además, mientras la OS siga programada.
-- Resultados: 1 mensaje · 2 aprobaciones · 3 totales (total, pendientes, aprobadas, rechazadas).
DROP PROCEDURE IF EXISTS SP_ObtenerAprobacionesServicioRuta;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerAprobacionesServicioRuta(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT
)
proc: BEGIN
    DECLARE v_msg         VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_area_jefe   VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_general     TINYINT DEFAULT 0;
    DECLARE v_area_os     VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado_os   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_ult_salida  BIGINT;
    DECLARE v_ult_llegada BIGINT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_apr;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    CALL SP_PrepararDetalleServicioRuta(p_id_usuario, p_id_os, v_msg);
    IF v_msg IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje;
        LEAVE proc;
    END IF;
    CALL SP_LimpiarSeguimientoOperativo();

    -- Quién consulta: encargado de un área (v_area_jefe) o supervisión general (v_general)
    SELECT COALESCE(IF(c.String2 LIKE 'jefe\_%' AND c.String3 IN ('servicio_tecnico', 'metrologia'), c.String3, NULL),
                    IF(u.rol_sistema = 'supervisor' AND u.area = 'metrologia', 'metrologia', NULL)),
           (u.cargo IN ('jefe_operaciones', 'coordinador_operaciones') OR u.rol_sistema IN ('administrador', 'admin')
            OR (u.rol_sistema = 'supervisor' AND u.area = 'operaciones'))
    INTO   v_area_jefe, v_general
    FROM   usuario u
    LEFT JOIN tabla_maestra c ON c.IdMaestro = 80 AND c.IdEmpresa = 1 AND c.String2 = u.cargo
    WHERE  u.id_usuario = p_id_usuario AND u.eliminado_en IS NULL AND u.estado = 'activo'
    LIMIT 1;
    SET v_general = IFNULL(v_general, 0);

    -- Área de la OS (la de la RQ) y estado
    SELECT os.estado, asr.area_usuario INTO v_estado_os, v_area_os
    FROM   orden_servicio os
    LEFT JOIN expediente_digital ed  ON ed.id_expediente    = os.id_expediente
    LEFT JOIN requerimiento      rq  ON rq.id_requerimiento = ed.id_requerimiento
    LEFT JOIN area_servicio_rq   asr ON asr.id_area_rq      = rq.id_area
    WHERE  os.id_os = p_id_os;

    SELECT MAX(id_autorizacion) INTO v_ult_salida  FROM autorizacion_salida_os WHERE id_os = p_id_os AND eliminado_en IS NULL;
    SELECT MAX(id_solicitud)    INTO v_ult_llegada FROM llegada_forzada_os     WHERE id_os = p_id_os AND eliminado_en IS NULL;

    DROP TEMPORARY TABLE IF EXISTS tmp_apr;
    CREATE TEMPORARY TABLE tmp_apr (
        tipo           VARCHAR(12)  NOT NULL,
        id             BIGINT       NOT NULL,
        titulo         VARCHAR(200) NULL,
        solicitante    VARCHAR(210) NULL,
        solicitado_en  DATETIME     NULL,
        motivo         VARCHAR(500) NULL,
        detalle        VARCHAR(500) NULL,
        estado         VARCHAR(12)  NOT NULL,
        resuelto_por   VARCHAR(210) NULL,
        cargo          VARCHAR(150) NULL,
        resuelto_en    DATETIME     NULL,
        comentario     VARCHAR(500) NULL,
        urgente        TINYINT      NOT NULL DEFAULT 0,
        puede_resolver TINYINT      NOT NULL DEFAULT 0
    ) DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;

    -- Salida
    INSERT INTO tmp_apr
    SELECT 'salida', a.id_autorizacion, 'Autorización de salida',
           NULLIF(TRIM(CONCAT(IFNULL(t.nombre, ''), ' ', IFNULL(t.apellido, ''))), ''),
           a.solicitado_en, a.motivo, a.pendientes, a.estado,
           NULLIF(TRIM(CONCAT(IFNULL(j.nombre, ''), ' ', IFNULL(j.apellido, ''))), ''), IFNULL(cj.String1, NULLIF(j.cargo, '')),
           a.resuelto_en, a.comentario,
           IF(a.estado = 'pendiente', 1, 0),
           IF(a.estado = 'pendiente' AND a.id_autorizacion = v_ult_salida AND v_estado_os IN ('programada', 'reprogramada')
              AND (v_general = 1 OR (v_area_jefe IS NOT NULL
                                     AND (COALESCE(a.area_destino, v_area_os) IS NULL OR COALESCE(a.area_destino, v_area_os) = v_area_jefe))), 1, 0)
    FROM   autorizacion_salida_os a
    LEFT JOIN usuario t        ON t.id_usuario = a.id_tecnico
    LEFT JOIN usuario j        ON j.id_usuario = a.id_jefe
    LEFT JOIN tabla_maestra cj ON cj.IdMaestro = 80 AND cj.IdEmpresa = 1 AND cj.String2 = j.cargo
    WHERE  a.id_os = p_id_os AND a.eliminado_en IS NULL;

    -- Llegada forzada
    INSERT INTO tmp_apr
    SELECT 'llegada', s.id_solicitud, 'Llegada forzada',
           NULLIF(TRIM(CONCAT(IFNULL(t.nombre, ''), ' ', IFNULL(t.apellido, ''))), ''),
           s.solicitado_en, s.motivo,
           NULLIF(CONCAT_WS(' · ', IF(s.distancia_metros IS NULL, NULL, CONCAT('A ', s.distancia_metros, ' m de la planta')),
                                   IF(IFNULL(s.intentos, 0) = 0, NULL, CONCAT(s.intentos, ' capturas fuera de rango'))), ''),
           s.estado,
           NULLIF(TRIM(CONCAT(IFNULL(j.nombre, ''), ' ', IFNULL(j.apellido, ''))), ''), IFNULL(cj.String1, NULLIF(j.cargo, '')),
           s.resuelto_en, s.comentario,
           IF(s.estado = 'pendiente', 1, 0),
           IF(s.estado = 'pendiente' AND s.id_solicitud = v_ult_llegada
              AND (v_general = 1 OR (v_area_jefe IS NOT NULL AND (s.area_destino IS NULL OR s.area_destino = v_area_jefe))), 1, 0)
    FROM   llegada_forzada_os s
    LEFT JOIN usuario t        ON t.id_usuario = s.id_tecnico
    LEFT JOIN usuario j        ON j.id_usuario = s.id_jefe
    LEFT JOIN tabla_maestra cj ON cj.IdMaestro = 80 AND cj.IdEmpresa = 1 AND cj.String2 = j.cargo
    WHERE  s.id_os = p_id_os AND s.eliminado_en IS NULL;

    -- Evidencias forzadas (la toma vigente; o una anterior que ya fue revisada)
    INSERT INTO tmp_apr
    SELECT 'evidencia', f.id_evidencia,
           LEFT(CONCAT('Evidencia forzada: ', IFNULL(f.codigo, 'foto'), IF(IFNULL(f.pagina, 1) > 1, CONCAT(' (hoja ', f.pagina, ')'), ''),
                       IF(ec.codigo_tw IS NULL, '', CONCAT(' · ', ec.codigo_tw))), 200),
           NULLIF(TRIM(CONCAT(IFNULL(t.nombre, ''), ' ', IFNULL(t.apellido, ''))), ''),
           COALESCE(f.forzada_en, f.timestamp_captura), f.motivo_forzado,
           LEFT(CONCAT('La IA la rechazó', IF(f.motivo_rechazo_ia IS NULL, '.', CONCAT(': ', f.motivo_rechazo_ia))), 500),
           IFNULL(f.revision_jefe, 'pendiente'),
           NULLIF(TRIM(CONCAT(IFNULL(j.nombre, ''), ' ', IFNULL(j.apellido, ''))), ''), IFNULL(cj.String1, NULLIF(j.cargo, '')),
           f.revisado_jefe_en, f.comentario_jefe,
           0,
           IF(f.revision_jefe IS NULL
              AND (v_general = 1 OR (v_area_jefe IS NOT NULL AND (v_area_os IS NULL OR v_area_os = v_area_jefe))), 1, 0)
    FROM   evidencia_fotografica f
    LEFT JOIN equipo_cliente ec ON ec.id_equipo = f.id_equipo
    LEFT JOIN usuario t         ON t.id_usuario = COALESCE(f.id_usuario_override, f.id_usuario)
    LEFT JOIN usuario j         ON j.id_usuario = f.revisado_jefe_por
    LEFT JOIN tabla_maestra cj  ON cj.IdMaestro = 80 AND cj.IdEmpresa = 1 AND cj.String2 = j.cargo
    WHERE  f.id_os = p_id_os AND f.eliminado_en IS NULL AND f.override_aprobado = 1
      AND  (f.vigente = 1 OR f.revision_jefe IS NOT NULL);

    -- Ensayos guardados con error crítico
    INSERT INTO tmp_apr
    SELECT 'ensayo', it.id_informe,
           LEFT(CONCAT('Ensayo con error crítico', IF(ec.codigo_tw IS NULL, '', CONCAT(' · ', ec.codigo_tw))), 200),
           NULLIF(TRIM(CONCAT(IFNULL(t.nombre, ''), ' ', IFNULL(t.apellido, ''))), ''),
           COALESCE(it.error_critico_notificado_en, it.ensayos_finalizado_en, it.modificado_en, it.creado_en),
           it.error_critico_motivo,
           CONCAT((SELECT COUNT(*) FROM informe_ensayo ie WHERE ie.id_informe = it.id_informe AND ie.critico = 1 AND ie.eliminado_en IS NULL),
                  ' lectura(s) fuera del EMP'),
           IFNULL(it.error_critico_revision, 'pendiente'),
           NULLIF(TRIM(CONCAT(IFNULL(j.nombre, ''), ' ', IFNULL(j.apellido, ''))), ''), IFNULL(cj.String1, NULLIF(j.cargo, '')),
           it.error_critico_revisado_en, it.error_critico_comentario,
           IF(it.error_critico_revision IS NULL, 1, 0),
           IF(it.error_critico_revision IS NULL
              AND (v_general = 1 OR (v_area_jefe IS NOT NULL AND (v_area_os IS NULL OR v_area_os = v_area_jefe))), 1, 0)
    FROM   informe_tecnico it
    LEFT JOIN equipo_cliente ec ON ec.id_equipo = it.id_equipo
    LEFT JOIN usuario t         ON t.id_usuario = it.id_tecnico
    LEFT JOIN usuario j         ON j.id_usuario = it.error_critico_revisado_por
    LEFT JOIN tabla_maestra cj  ON cj.IdMaestro = 80 AND cj.IdEmpresa = 1 AND cj.String2 = j.cargo
    WHERE  it.id_os = p_id_os AND it.eliminado_en IS NULL AND it.error_critico_motivo IS NOT NULL;

    SELECT 2 AS IdTipoMensaje, 'OK' AS Mensaje;

    SELECT tipo, id, titulo, solicitante, solicitado_en, motivo, detalle, estado, resuelto_por, cargo, resuelto_en, comentario,
           urgente, puede_resolver
    FROM   tmp_apr
    ORDER BY (estado = 'pendiente') DESC, urgente DESC, solicitado_en DESC, id DESC;

    SELECT COUNT(*) AS total,
           IFNULL(SUM(estado = 'pendiente'), 0) AS pendientes,
           IFNULL(SUM(estado = 'aprobada'), 0)  AS aprobadas,
           IFNULL(SUM(estado = 'rechazada'), 0) AS rechazadas
    FROM   tmp_apr;

    DROP TEMPORARY TABLE IF EXISTS tmp_apr;
END$$

DELIMITER ;
