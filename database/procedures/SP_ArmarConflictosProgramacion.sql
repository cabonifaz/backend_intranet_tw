-- HU-39 (Sprint 5) Detección de conflictos SOBREVENIDOS a la Programación. Ayuda interna: NO devuelve resultados. Solo lee datos.
-- La llaman SP_ObtenerConflictosProgramacion, SP_ObtenerConflictoProgramacion y SP_ResolverConflictoProgramacion, que al terminar
-- ejecutan SP_LimpiarConflictosProgramacion. (La validación al PROGRAMAR es de la HU-36: aquí solo lo que aparece DESPUÉS.)
-- Se analizan las órdenes programadas (programada o reprogramada) con fecha de hoy en adelante, con su técnico principal y su
-- personal de apoyo. Tipos de conflicto:
--   baja              técnico de baja o ausente: su usuario ya no está activo (inactivo, suspendido o eliminado) y tiene programaciones
--                     pendientes. (El sistema no tiene aún un módulo de ausencias/vacaciones: cuando exista se suma aquí como fuente.)
--   ssoma_vencido     habilitación SSOMA vencida (o que vence antes de la fecha del servicio) DESPUÉS de haber programado: último
--                     documento del técnico en esa orden, aprobado, cargado o vencido, con vencimiento anterior a la fecha del servicio.
--   solapamiento      dos programaciones del mismo técnico el mismo día con horarios que se cruzan (p. ej. tras una reprogramación aprobada)
--   extension_duracion igual que el solapamiento, pero una de las dos programaciones fue ALARGADA por una reprogramación y pisa a la otra
-- Tablas temporales (MySQL no permite abrir dos veces la misma temporal en una consulta, de ahí las copias):
--   tmp_cf_asig / tmp_cf_asig2 : una fila por orden programada y persona asignada (con su programación vigente, si la tiene)
--   tmp_cf_par                 : pares de órdenes del mismo técnico con horarios cruzados
--   tmp_cf_serv                : servicios afectados por conflicto (clave, tipo, técnico, orden, programación)
--   tmp_cf                     : una fila por conflicto, con el motivo sugerido para el flujo de la HU-38
-- Requiere las migraciones 85 a 88.
DROP PROCEDURE IF EXISTS SP_ArmarConflictosProgramacion;

DELIMITER $$

CREATE PROCEDURE SP_ArmarConflictosProgramacion()
BEGIN
    DECLARE v_m_tecnico INT DEFAULT 0;
    DECLARE v_m_ssoma   INT DEFAULT 0;
    DECLARE v_m_imprev  INT DEFAULT 0;

    CALL SP_LimpiarConflictosProgramacion();

    -- Motivos sugeridos (catálogo MOTIVO_REPROGRAMACION, por código)
    SELECT IFNULL(MAX(Num1), 0) INTO v_m_tecnico FROM tabla_maestra WHERE IdMaestro = 13 AND IdEmpresa = 1 AND String2 = 'FALTA_TECNICO';
    SELECT IFNULL(MAX(Num1), 0) INTO v_m_ssoma   FROM tabla_maestra WHERE IdMaestro = 13 AND IdEmpresa = 1 AND String2 = 'SSOMA_SOBREVENIDO';
    SELECT IFNULL(MAX(Num1), 0) INTO v_m_imprev  FROM tabla_maestra WHERE IdMaestro = 13 AND IdEmpresa = 1 AND String2 = 'IMPREVISTO_OPERATIVO';

    CREATE TEMPORARY TABLE tmp_cf_asig (
        id_os           BIGINT       NOT NULL,
        id_usuario      BIGINT       NOT NULL,
        rol             VARCHAR(10)  NOT NULL,
        numero          VARCHAR(20)  NULL,
        tipo_os         VARCHAR(5)   NULL,
        razon_social    VARCHAR(250) NULL,
        tipo_servicio   VARCHAR(200) NULL,
        fecha           DATE         NULL,
        hora_inicio     TIME         NULL,
        hora_fin        TIME         NULL,
        horas           DECIMAL(8,2) NULL,
        estado_os       VARCHAR(20)  NULL,
        id_programacion BIGINT       NULL,
        estado_prog     VARCHAR(25)  NULL,
        PRIMARY KEY (id_os, id_usuario),
        KEY (id_usuario, fecha)
    );

    INSERT IGNORE INTO tmp_cf_asig (id_os, id_usuario, rol, numero, tipo_os, razon_social, tipo_servicio, fecha, hora_inicio, hora_fin,
                                    horas, estado_os, id_programacion, estado_prog)
    SELECT os.id_os, os.id_tecnico_principal, 'principal', os.numero, os.tipo, c.razon_social, ts.String1,
           os.fecha_ejecucion, os.hora_inicio, os.hora_fin_estimada,
           IF(os.hora_inicio IS NOT NULL AND os.hora_fin_estimada > os.hora_inicio,
              ROUND(TIME_TO_SEC(TIMEDIFF(os.hora_fin_estimada, os.hora_inicio)) / 3600, 2), NULL),
           os.estado, pr.id_programacion, pr.estado
    FROM orden_servicio os
    LEFT JOIN cliente c        ON c.id_cliente = os.id_cliente
    LEFT JOIN tabla_maestra ts ON ts.IdMaestro = 3 AND ts.IdEmpresa = 1 AND ts.Num1 = os.id_tipo_servicio
    LEFT JOIN programacion pr  ON pr.id_programacion = (SELECT MAX(p2.id_programacion) FROM programacion p2
                                                         WHERE p2.id_os = os.id_os AND p2.estado <> 'cancelada' AND p2.eliminado_en IS NULL)
    WHERE os.eliminado_en IS NULL
      AND os.estado IN ('programada', 'reprogramada')
      AND os.fecha_ejecucion >= CURDATE()
      AND os.id_tecnico_principal IS NOT NULL;

    INSERT IGNORE INTO tmp_cf_asig (id_os, id_usuario, rol, numero, tipo_os, razon_social, tipo_servicio, fecha, hora_inicio, hora_fin,
                                    horas, estado_os, id_programacion, estado_prog)
    SELECT os.id_os, pe.id_usuario, 'apoyo', os.numero, os.tipo, c.razon_social, ts.String1,
           os.fecha_ejecucion, os.hora_inicio, os.hora_fin_estimada,
           IF(os.hora_inicio IS NOT NULL AND os.hora_fin_estimada > os.hora_inicio,
              ROUND(TIME_TO_SEC(TIMEDIFF(os.hora_fin_estimada, os.hora_inicio)) / 3600, 2), NULL),
           os.estado, pr.id_programacion, pr.estado
    FROM orden_servicio os
    JOIN os_personal pe        ON pe.id_os = os.id_os AND pe.eliminado_en IS NULL
    LEFT JOIN cliente c        ON c.id_cliente = os.id_cliente
    LEFT JOIN tabla_maestra ts ON ts.IdMaestro = 3 AND ts.IdEmpresa = 1 AND ts.Num1 = os.id_tipo_servicio
    LEFT JOIN programacion pr  ON pr.id_programacion = (SELECT MAX(p2.id_programacion) FROM programacion p2
                                                         WHERE p2.id_os = os.id_os AND p2.estado <> 'cancelada' AND p2.eliminado_en IS NULL)
    WHERE os.eliminado_en IS NULL
      AND os.estado IN ('programada', 'reprogramada')
      AND os.fecha_ejecucion >= CURDATE();

    CREATE TEMPORARY TABLE tmp_cf_asig2 AS SELECT * FROM tmp_cf_asig;

    CREATE TEMPORARY TABLE tmp_cf_serv (
        clave           VARCHAR(80)  NOT NULL,
        tipo            VARCHAR(20)  NOT NULL,
        id_usuario      BIGINT       NOT NULL,
        id_os           BIGINT       NOT NULL,
        id_programacion BIGINT       NULL,
        fecha           DATE         NULL,
        detalle         VARCHAR(255) NULL,
        fecha_ref       DATE         NULL,
        PRIMARY KEY (clave, id_os)
    );

    -- ── (a) Técnico de baja o ausente ─────────────────────────────────────
    INSERT IGNORE INTO tmp_cf_serv (clave, tipo, id_usuario, id_os, id_programacion, fecha, detalle, fecha_ref)
    SELECT CONCAT('baja:', a.id_usuario), 'baja', a.id_usuario, a.id_os, a.id_programacion, a.fecha,
           CASE u.estado WHEN 'suspendido' THEN 'suspendido' WHEN 'inactivo' THEN 'de baja' ELSE 'no disponible' END, NULL
    FROM tmp_cf_asig a
    JOIN usuario u ON u.id_usuario = a.id_usuario
    WHERE u.estado <> 'activo' OR u.eliminado_en IS NOT NULL;

    -- ── (b) Habilitación SSOMA vencida después de programar ───────────────
    INSERT IGNORE INTO tmp_cf_serv (clave, tipo, id_usuario, id_os, id_programacion, fecha, detalle, fecha_ref)
    SELECT CONCAT('ssoma_vencido:', a.id_usuario), 'ssoma_vencido', a.id_usuario, a.id_os, a.id_programacion, a.fecha,
           IFNULL(MAX(rq.String1), 'documento SSOMA'), MIN(d.fecha_vencimiento)
    FROM tmp_cf_asig a
    JOIN ssoma_documento d     ON d.id_os = a.id_os AND d.id_usuario = a.id_usuario AND d.eliminado_en IS NULL
                              AND d.estado IN ('aprobado', 'cargado', 'vencido')
                              AND d.fecha_vencimiento IS NOT NULL
                              AND (d.estado = 'vencido' OR d.fecha_vencimiento < a.fecha)
    LEFT JOIN tabla_maestra rq ON rq.IdMaestro = 36 AND rq.IdEmpresa = 1 AND rq.Num1 = d.id_requisito
    WHERE NOT EXISTS (SELECT 1 FROM ssoma_documento sn
                      WHERE sn.id_os = d.id_os AND sn.id_usuario = d.id_usuario AND sn.id_requisito = d.id_requisito
                        AND sn.eliminado_en IS NULL
                        AND (sn.version > d.version OR (sn.version = d.version AND sn.id_ssoma_doc > d.id_ssoma_doc)))
    GROUP BY a.id_usuario, a.id_os, a.id_programacion, a.fecha;

    -- ── (c) y (d) Solapamientos del mismo técnico (con extensión de duración) ──
    CREATE TEMPORARY TABLE tmp_cf_par AS
    SELECT a.id_usuario, a.fecha, a.id_os AS id_os_a, b.id_os AS id_os_b,
           GREATEST(a.hora_inicio, b.hora_inicio) AS solape_ini,
           LEAST(a.hora_fin, b.hora_fin)          AS solape_fin,
           IF(EXISTS (SELECT 1 FROM auditoria_evento ae
                      WHERE ae.entidad_tipo = 'programacion'
                        AND ae.id_entidad IN (a.id_programacion, b.id_programacion)
                        AND ae.accion IN ('reprogramacion_directa', 'aprobar_reprogramacion')
                        AND JSON_UNQUOTE(JSON_EXTRACT(ae.metadata, '$.horaFinNueva'))
                            > JSON_UNQUOTE(JSON_EXTRACT(ae.metadata, '$.horaFinAnterior'))), 1, 0) AS extension
    FROM tmp_cf_asig a
    JOIN tmp_cf_asig2 b ON b.id_usuario = a.id_usuario AND b.fecha = a.fecha AND a.id_os < b.id_os
                       AND a.hora_inicio < b.hora_fin AND b.hora_inicio < a.hora_fin
    WHERE a.hora_inicio IS NOT NULL AND a.hora_fin > a.hora_inicio
      AND b.hora_inicio IS NOT NULL AND b.hora_fin > b.hora_inicio;

    INSERT IGNORE INTO tmp_cf_serv (clave, tipo, id_usuario, id_os, id_programacion, fecha, detalle, fecha_ref)
    SELECT CONCAT(IF(p.extension = 1, 'extension_duracion', 'solapamiento'), ':', p.id_usuario, ':', p.id_os_a, ':', p.id_os_b),
           IF(p.extension = 1, 'extension_duracion', 'solapamiento'), p.id_usuario, a.id_os, a.id_programacion, p.fecha, NULL, NULL
    FROM tmp_cf_par p
    JOIN tmp_cf_asig a ON a.id_os = p.id_os_a AND a.id_usuario = p.id_usuario;

    INSERT IGNORE INTO tmp_cf_serv (clave, tipo, id_usuario, id_os, id_programacion, fecha, detalle, fecha_ref)
    SELECT CONCAT(IF(p.extension = 1, 'extension_duracion', 'solapamiento'), ':', p.id_usuario, ':', p.id_os_a, ':', p.id_os_b),
           IF(p.extension = 1, 'extension_duracion', 'solapamiento'), p.id_usuario, a.id_os, a.id_programacion, p.fecha, NULL, NULL
    FROM tmp_cf_par p
    JOIN tmp_cf_asig a ON a.id_os = p.id_os_b AND a.id_usuario = p.id_usuario;

    -- ── Una fila por conflicto ────────────────────────────────────────────
    CREATE TEMPORARY TABLE tmp_cf (
        clave           VARCHAR(80)  NOT NULL,
        tipo            VARCHAR(20)  NOT NULL,
        severidad       VARCHAR(12)  NOT NULL,
        id_usuario      BIGINT       NOT NULL,
        tecnico         VARCHAR(250) NULL,
        fecha           DATE         NULL,
        titulo          VARCHAR(255) NULL,
        detalle         VARCHAR(500) NULL,
        id_motivo       INT          NULL,
        motivo_sugerido VARCHAR(400) NULL,
        n_servicios     INT          NOT NULL DEFAULT 1,
        id_os_a         BIGINT       NULL,
        id_os_b         BIGINT       NULL,
        solape_ini      TIME         NULL,
        solape_fin      TIME         NULL,
        PRIMARY KEY (clave)
    );

    INSERT INTO tmp_cf (clave, tipo, severidad, id_usuario, tecnico, fecha, titulo, detalle, id_motivo, motivo_sugerido, n_servicios, id_os_a)
    SELECT s.clave, 'baja', 'critica', s.id_usuario, TRIM(CONCAT(u.nombre, ' ', u.apellido)), MIN(s.fecha),
           'Técnico de baja o ausente',
           CONCAT(TRIM(CONCAT(u.nombre, ' ', u.apellido)), ' está ', MAX(s.detalle), ' y tiene ', COUNT(*),
                  IF(COUNT(*) = 1, ' programación pendiente', ' programaciones pendientes'), '.'),
           NULLIF(v_m_tecnico, 0),
           CONCAT('Técnico no disponible: ', TRIM(CONCAT(u.nombre, ' ', u.apellido)), ' está ', MAX(s.detalle), '.'),
           COUNT(*), MIN(s.id_os)
    FROM tmp_cf_serv s
    JOIN usuario u ON u.id_usuario = s.id_usuario
    WHERE s.tipo = 'baja'
    GROUP BY s.clave, s.id_usuario, u.nombre, u.apellido;

    INSERT INTO tmp_cf (clave, tipo, severidad, id_usuario, tecnico, fecha, titulo, detalle, id_motivo, motivo_sugerido, n_servicios, id_os_a)
    SELECT s.clave, 'ssoma_vencido', 'critica', s.id_usuario, TRIM(CONCAT(u.nombre, ' ', u.apellido)), MIN(s.fecha),
           'Habilitación SSOMA vencida',
           CONCAT('El ', MAX(s.detalle), ' de ', TRIM(CONCAT(u.nombre, ' ', u.apellido)), IF(MIN(s.fecha_ref) < CURDATE(), ' venció el ', ' vence el '),
                  DATE_FORMAT(MIN(s.fecha_ref), '%d/%m/%Y'), ', antes de ejecutar ', COUNT(*),
                  IF(COUNT(*) = 1, ' servicio programado.', ' servicios programados.')),
           NULLIF(v_m_ssoma, 0),
           CONCAT('SSOMA vencido del técnico ', TRIM(CONCAT(u.nombre, ' ', u.apellido)), '.'),
           COUNT(*), MIN(s.id_os)
    FROM tmp_cf_serv s
    JOIN usuario u ON u.id_usuario = s.id_usuario
    WHERE s.tipo = 'ssoma_vencido'
    GROUP BY s.clave, s.id_usuario, u.nombre, u.apellido;

    INSERT INTO tmp_cf (clave, tipo, severidad, id_usuario, tecnico, fecha, titulo, detalle, id_motivo, motivo_sugerido,
                        n_servicios, id_os_a, id_os_b, solape_ini, solape_fin)
    SELECT CONCAT(IF(p.extension = 1, 'extension_duracion', 'solapamiento'), ':', p.id_usuario, ':', p.id_os_a, ':', p.id_os_b),
           IF(p.extension = 1, 'extension_duracion', 'solapamiento'), 'critica', p.id_usuario,
           TRIM(CONCAT(u.nombre, ' ', u.apellido)), p.fecha,
           IF(p.extension = 1, 'Extensión de duración que pisa otra programación', 'Solapamiento horario'),
           CONCAT(IF(p.extension = 1, 'Extensión de duración: ', 'Solapamiento: '), TRIM(CONCAT(u.nombre, ' ', u.apellido)), ' el ',
                  DATE_FORMAT(p.fecha, '%d/%m'), ' de ', TIME_FORMAT(p.solape_ini, '%H:%i'), ' a ', TIME_FORMAT(p.solape_fin, '%H:%i'),
                  ' (', oa.numero, ' y ', ob.numero, ').'),
           NULLIF(v_m_imprev, 0),
           CONCAT(IF(p.extension = 1, 'Extensión de duración que pisa otra programación de ', 'Solapamiento horario de '),
                  TRIM(CONCAT(u.nombre, ' ', u.apellido)), ' el ', DATE_FORMAT(p.fecha, '%d/%m/%Y'), ' (', oa.numero, ' y ', ob.numero, ').'),
           2, p.id_os_a, p.id_os_b, p.solape_ini, p.solape_fin
    FROM tmp_cf_par p
    JOIN usuario u         ON u.id_usuario = p.id_usuario
    JOIN orden_servicio oa ON oa.id_os = p.id_os_a
    JOIN orden_servicio ob ON ob.id_os = p.id_os_b;
END$$

DELIMITER ;
