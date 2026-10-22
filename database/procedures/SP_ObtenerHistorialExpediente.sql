-- HU-32 Modal "Historial de Auditoría del Expediente" (vista forense, solo lectura e inmutable). Acción expediente_bandeja.
-- Cuatro tabs, todos con los mismos filtros (opcionales):
--   p_busqueda          texto en título, descripción/comentario, motivo, usuario o entidad
--   p_id_usuario_evento usuario que hizo el evento (ejecutó la reasignación, registró el bloqueo, responsable en la alerta)
--   p_etapa             código de ETAPA_EXPEDIENTE        p_tipo_evento  tipo de evento (solo Timeline)
--   p_desde / p_hasta   rango de fechas (inclusive)
--   Timeline        eventos de todos los módulos origen, sin duplicados (SP_CargarEventosExpediente)
--   Reasignaciones  cambios de responsable (entidad, cascada o cartera completa; y los del expediente antes del refinamiento)
--   Bloqueos        bloqueos y excepciones abiertos y resueltos, con duración (SP_CargarBloqueosExpediente)
--   Alertas SLA     alertas de cada etapa: advertencia (50 % del SLA), riesgo (ventana de alerta de CONFIG_SLA) y vencido
-- p_exportar = timeline | reasignaciones | bloqueos | alertas_sla registra en la auditoría la exportación (XLSX o PDF) de
--   ese tab con los filtros aplicados.
-- Resultados: 1 mensaje · 2 resumen (expediente, cliente, responsable actual) · 3 tabs con cantidad · 4 timeline
--   · 5 reasignaciones · 6 bloqueos · 7 alertas SLA · 8 tipos de evento · 9 usuarios · 10 etapas
DROP PROCEDURE IF EXISTS SP_ObtenerHistorialExpediente;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerHistorialExpediente(
    IN p_id_usuario        BIGINT,
    IN p_id_expediente     BIGINT,
    IN p_busqueda          VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_usuario_evento BIGINT,
    IN p_etapa             VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_tipo_evento       VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_desde             DATE,
    IN p_hasta             DATE,
    IN p_exportar          VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_existe   INT DEFAULT 0;
    DECLARE v_busqueda VARCHAR(102) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_etapa    VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tipo     VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_usr      BIGINT;
    DECLARE v_n_tl     INT DEFAULT 0;
    DECLARE v_n_re     INT DEFAULT 0;
    DECLARE v_n_bl     INT DEFAULT 0;
    DECLARE v_n_sla    INT DEFAULT 0;

    SET SESSION group_concat_max_len = 1000000;

    IF FN_PermisoAccion(p_id_usuario, 'expediente_bandeja') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver los expedientes digitales.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF p_desde IS NOT NULL AND p_hasta IS NOT NULL AND p_desde > p_hasta THEN
        SELECT 1 AS IdTipoMensaje, 'La fecha desde no puede ser posterior a la fecha hasta.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF NULLIF(TRIM(IFNULL(p_exportar, '')), '') IS NOT NULL
       AND p_exportar NOT IN ('timeline', 'reasignaciones', 'bloqueos', 'alertas_sla') THEN
        SELECT 1 AS IdTipoMensaje, 'Tab de exportación no válido. Use timeline, reasignaciones, bloqueos o alertas_sla.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_CalcularExpedientes(p_id_usuario, p_id_expediente);
    SELECT COUNT(*) INTO v_existe FROM tmp_exp;
    IF v_existe = 0 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_exp;
        DROP TEMPORARY TABLE IF EXISTS tmp_exp_blq;
        SELECT 1 AS IdTipoMensaje, 'El expediente no existe.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_busqueda = IF(NULLIF(TRIM(IFNULL(p_busqueda, '')), '') IS NULL, NULL, CONCAT('%', TRIM(p_busqueda), '%'));
    SET v_etapa    = NULLIF(TRIM(IFNULL(p_etapa, '')), '');
    SET v_tipo     = NULLIF(TRIM(IFNULL(p_tipo_evento, '')), '');
    SET v_usr      = NULLIF(IFNULL(p_id_usuario_evento, 0), 0);

    CALL SP_CargarEtapasExpediente();
    CALL SP_CargarEventosExpediente(p_id_usuario, p_id_expediente);

    -- ── Timeline ────────────────────────────────────────────────────────────
    DROP TEMPORARY TABLE IF EXISTS tmp_his_tl;
    CREATE TEMPORARY TABLE tmp_his_tl AS
    SELECT ev.fecha, ev.tipo_evento, ev.accion, ev.titulo, ev.descripcion, ev.etapa, et.String1 AS etapa_nombre,
           ev.id_usuario, IFNULL(CONCAT(u.nombre, ' ', u.apellido), 'Sistema') AS usuario, ev.entidad, ev.referencia,
           ev.urgente, ev.origen
    FROM tmp_exp_evt ev
    LEFT JOIN usuario u        ON u.id_usuario = ev.id_usuario
    LEFT JOIN tabla_maestra et ON et.IdMaestro = 97 AND et.IdEmpresa = 1 AND et.String2 = ev.etapa
    WHERE (v_tipo IS NULL OR ev.tipo_evento = v_tipo)
      AND (v_usr IS NULL OR ev.id_usuario = v_usr)
      AND (v_etapa IS NULL OR ev.etapa = v_etapa)
      AND (p_desde IS NULL OR ev.fecha >= p_desde)
      AND (p_hasta IS NULL OR ev.fecha < p_hasta + INTERVAL 1 DAY)
      AND (v_busqueda IS NULL OR ev.titulo LIKE v_busqueda OR ev.descripcion LIKE v_busqueda OR ev.referencia LIKE v_busqueda
           OR CONCAT(u.nombre, ' ', u.apellido) LIKE v_busqueda);
    DROP TEMPORARY TABLE IF EXISTS tmp_exp_evt;

    -- ── Reasignaciones ──────────────────────────────────────────────────────
    DROP TEMPORARY TABLE IF EXISTS tmp_his_re;
    CREATE TEMPORARY TABLE tmp_his_re AS
    SELECT r.id_reasignacion, r.registrado_en AS fecha, r.modo,
           CASE r.modo
               WHEN 'entidad' THEN CONCAT(CASE r.entidad_tipo WHEN 'propuesta' THEN 'Propuesta ' WHEN 'orden_compra' THEN 'OC ' ELSE '' END,
                                          r.codigo_entidad)
               WHEN 'cascada' THEN CONCAT('Cascada desde ', CASE r.entidad_tipo WHEN 'propuesta' THEN 'Propuesta ' WHEN 'orden_compra' THEN 'OC ' ELSE '' END,
                                          r.codigo_entidad, ' (', r.total_entidades, ' entidades)')
               ELSE CONCAT('Cartera completa (', r.total_entidades, ' entidades en ', r.total_expedientes, ' expedientes)')
           END AS alcance,
           (SELECT GROUP_CONCAT(d.codigo_entidad ORDER BY d.id_detalle SEPARATOR ', ') FROM expediente_reasignacion_detalle d
            WHERE d.id_reasignacion = r.id_reasignacion AND d.id_expediente = p_id_expediente AND d.SoftDelete = 0) AS entidades,
           r.id_responsable_anterior AS id_de, CONCAT(ua.nombre, ' ', ua.apellido) AS de,
           r.id_responsable_nuevo AS id_a, CONCAT(un.nombre, ' ', un.apellido) AS a,
           mo.String1 AS motivo, r.comentario, r.gestion_sla,
           IF(r.gestion_sla = 'reiniciar', 'Reiniciado', 'Mantenido') AS decision_sla,
           r.registrado_por AS id_ejecutado_por, CONCAT(ue.nombre, ' ', ue.apellido) AS ejecutado_por,
           (SELECT MAX(d.etapa) FROM expediente_reasignacion_detalle d
            WHERE d.id_reasignacion = r.id_reasignacion AND d.id_expediente = p_id_expediente) AS etapa
    FROM expediente_reasignacion r
    LEFT JOIN usuario ua ON ua.id_usuario = r.id_responsable_anterior
    LEFT JOIN usuario un ON un.id_usuario = r.id_responsable_nuevo
    LEFT JOIN usuario ue ON ue.id_usuario = r.registrado_por
    LEFT JOIN tabla_maestra mo ON mo.IdMaestro = 100 AND mo.IdEmpresa = 1 AND mo.Num1 = r.id_motivo
    WHERE r.SoftDelete = 0
      AND EXISTS (SELECT 1 FROM expediente_reasignacion_detalle d
                  WHERE d.id_reasignacion = r.id_reasignacion AND d.id_expediente = p_id_expediente AND d.SoftDelete = 0)
    UNION ALL
    -- Reasignaciones del responsable del expediente hechas antes del refinamiento
    SELECT NULL, a.registrado_en, 'expediente', 'Expediente (responsable de la etapa)', NULL,
           CAST(JSON_UNQUOTE(JSON_EXTRACT(a.metadata, '$.id_anterior')) AS UNSIGNED), a.estado_anterior,
           CAST(JSON_UNQUOTE(JSON_EXTRACT(a.metadata, '$.id_nuevo')) AS UNSIGNED), a.estado_nuevo,
           mo.String1, a.descripcion, JSON_UNQUOTE(JSON_EXTRACT(a.metadata, '$.gestion_sla')),
           IF(JSON_UNQUOTE(JSON_EXTRACT(a.metadata, '$.gestion_sla')) = 'reiniciar', 'Reiniciado', 'Mantenido'),
           a.id_usuario, CONCAT(ue.nombre, ' ', ue.apellido), JSON_UNQUOTE(JSON_EXTRACT(a.metadata, '$.etapa'))
    FROM auditoria_evento a
    LEFT JOIN usuario ue ON ue.id_usuario = a.id_usuario
    LEFT JOIN tabla_maestra mo ON mo.IdMaestro = 100 AND mo.IdEmpresa = 1
                              AND mo.Num1 = CAST(JSON_UNQUOTE(JSON_EXTRACT(a.metadata, '$.id_motivo')) AS UNSIGNED)
    WHERE a.entidad_tipo = 'expediente' AND a.id_entidad = p_id_expediente AND a.accion = 'reasignar_responsable'
      AND JSON_EXTRACT(a.metadata, '$.id_reasignacion') IS NULL;

    DELETE FROM tmp_his_re
    WHERE NOT ((v_usr IS NULL OR id_ejecutado_por = v_usr OR id_de = v_usr OR id_a = v_usr)
               AND (v_etapa IS NULL OR etapa = v_etapa)
               AND (p_desde IS NULL OR fecha >= p_desde)
               AND (p_hasta IS NULL OR fecha < p_hasta + INTERVAL 1 DAY)
               AND (v_busqueda IS NULL OR alcance LIKE v_busqueda OR IFNULL(entidades, '') LIKE v_busqueda
                    OR IFNULL(comentario, '') LIKE v_busqueda OR IFNULL(motivo, '') LIKE v_busqueda
                    OR IFNULL(de, '') LIKE v_busqueda OR IFNULL(a, '') LIKE v_busqueda OR IFNULL(ejecutado_por, '') LIKE v_busqueda));

    -- ── Bloqueos ────────────────────────────────────────────────────────────
    DROP TEMPORARY TABLE IF EXISTS tmp_his_bl;
    CREATE TEMPORARY TABLE tmp_his_bl AS
    SELECT b.clave, b.fecha, b.clase, b.tipo, b.tipo_nombre, b.etapa, et.String1 AS etapa_nombre, b.entidad_tipo, b.entidad,
           b.motivo, b.impacto, b.fecha_resolucion, b.resolucion, b.activo,
           ROUND(TIMESTAMPDIFF(MINUTE, b.fecha, IFNULL(b.fecha_resolucion, NOW())) / 60, 1) AS duracion_horas,
           b.id_usuario, IFNULL(CONCAT(u.nombre, ' ', u.apellido), 'Sistema') AS usuario, b.origen
    FROM tmp_exp_blq b
    LEFT JOIN usuario u        ON u.id_usuario = b.id_usuario
    LEFT JOIN tabla_maestra et ON et.IdMaestro = 97 AND et.IdEmpresa = 1 AND et.String2 = b.etapa
    WHERE (v_usr IS NULL OR b.id_usuario = v_usr)
      AND (v_etapa IS NULL OR b.etapa = v_etapa)
      AND (p_desde IS NULL OR b.fecha >= p_desde)
      AND (p_hasta IS NULL OR b.fecha < p_hasta + INTERVAL 1 DAY)
      AND (v_busqueda IS NULL OR b.tipo_nombre LIKE v_busqueda OR b.motivo LIKE v_busqueda OR b.entidad LIKE v_busqueda
           OR IFNULL(b.resolucion, '') LIKE v_busqueda OR CONCAT(u.nombre, ' ', u.apellido) LIKE v_busqueda);
    DROP TEMPORARY TABLE IF EXISTS tmp_exp_blq;

    -- ── Alertas SLA (una fila por cada nivel alcanzado en cada etapa) ───────
    DROP TEMPORARY TABLE IF EXISTS tmp_his_sla;
    CREATE TEMPORARY TABLE tmp_his_sla (
        fecha           DATETIME,
        etapa           VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        etapa_nombre    VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        nivel           VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        orden_nivel     INT,
        sla_horas       INT,
        horas_reales    DECIMAL(10,1),
        desvio_horas    DECIMAL(10,1),
        id_responsable  BIGINT,
        responsable     VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        fin_etapa       DATETIME
    );

    INSERT INTO tmp_his_sla
    SELECT e.inicio_sla + INTERVAL ROUND(e.sla_horas * 30) MINUTE, e.etapa, e.nombre, 'advertencia', 1, e.sla_horas, e.horas_reales,
           e.horas_reales - e.sla_horas, e.id_responsable, e.responsable, e.fin
    FROM tmp_exp_etp e
    WHERE e.sla_horas > 0 AND e.inicio_sla IS NOT NULL AND e.horas_reales >= e.sla_horas * 0.5;

    INSERT INTO tmp_his_sla
    SELECT e.inicio_sla + INTERVAL (e.sla_horas - IFNULL(e.sla_alerta_horas, 0)) HOUR, e.etapa, e.nombre, 'riesgo', 2, e.sla_horas,
           e.horas_reales, e.horas_reales - e.sla_horas, e.id_responsable, e.responsable, e.fin
    FROM tmp_exp_etp e
    WHERE e.sla_horas > 0 AND e.inicio_sla IS NOT NULL AND IFNULL(e.sla_alerta_horas, 0) > 0
      AND e.sla_horas - e.sla_alerta_horas > e.sla_horas * 0.5
      AND e.horas_reales >= e.sla_horas - e.sla_alerta_horas;

    INSERT INTO tmp_his_sla
    SELECT e.inicio_sla + INTERVAL e.sla_horas HOUR, e.etapa, e.nombre, 'vencido', 3, e.sla_horas, e.horas_reales,
           e.horas_reales - e.sla_horas, e.id_responsable, e.responsable, e.fin
    FROM tmp_exp_etp e
    WHERE e.sla_horas > 0 AND e.inicio_sla IS NOT NULL AND e.horas_reales > e.sla_horas;

    DROP TEMPORARY TABLE IF EXISTS tmp_exp_etp;

    DROP TEMPORARY TABLE IF EXISTS tmp_his_sla2;
    CREATE TEMPORARY TABLE tmp_his_sla2 AS
    SELECT s.*,
           -- Responsable al momento de la alerta: si después se reasignó en esa etapa, el anterior a esa reasignación
           COALESCE((SELECT d.id_responsable_anterior FROM expediente_reasignacion_detalle d
                     WHERE d.id_expediente = p_id_expediente AND d.etapa = s.etapa AND d.FchCre >= s.fecha AND d.SoftDelete = 0
                     ORDER BY d.FchCre LIMIT 1), s.id_responsable) AS id_responsable_alerta,
           (SELECT CONCAT('Reasignación (SLA ', IF(r.gestion_sla = 'reiniciar', 'reiniciado', 'mantenido'), ') el ',
                          DATE_FORMAT(d.FchCre, '%d/%m/%Y %H:%i'))
            FROM expediente_reasignacion_detalle d
            JOIN expediente_reasignacion r ON r.id_reasignacion = d.id_reasignacion
            WHERE d.id_expediente = p_id_expediente AND d.etapa = s.etapa AND d.FchCre >= s.fecha AND d.SoftDelete = 0
            ORDER BY d.FchCre LIMIT 1) AS reasignacion
    FROM tmp_his_sla s;
    DROP TEMPORARY TABLE IF EXISTS tmp_his_sla;

    DROP TEMPORARY TABLE IF EXISTS tmp_his_sla3;
    CREATE TEMPORARY TABLE tmp_his_sla3 AS
    SELECT s.fecha, s.etapa, s.etapa_nombre, s.nivel, s.orden_nivel, s.sla_horas, s.horas_reales, s.desvio_horas,
           s.id_responsable_alerta AS id_responsable, CONCAT(u.nombre, ' ', u.apellido) AS responsable,
           COALESCE(s.reasignacion,
                    IF(s.fin_etapa IS NOT NULL, CONCAT('Etapa completada el ', DATE_FORMAT(s.fin_etapa, '%d/%m/%Y %H:%i')), NULL),
                    'Sin acción registrada') AS accion_tomada
    FROM tmp_his_sla2 s
    LEFT JOIN usuario u ON u.id_usuario = s.id_responsable_alerta
    WHERE (v_usr IS NULL OR s.id_responsable_alerta = v_usr)
      AND (v_etapa IS NULL OR s.etapa = v_etapa)
      AND (p_desde IS NULL OR s.fecha >= p_desde)
      AND (p_hasta IS NULL OR s.fecha < p_hasta + INTERVAL 1 DAY)
      AND (v_busqueda IS NULL OR s.etapa_nombre LIKE v_busqueda OR s.nivel LIKE v_busqueda
           OR CONCAT(u.nombre, ' ', u.apellido) LIKE v_busqueda);
    DROP TEMPORARY TABLE IF EXISTS tmp_his_sla2;

    SELECT COUNT(*) INTO v_n_tl  FROM tmp_his_tl;
    SELECT COUNT(*) INTO v_n_re  FROM tmp_his_re;
    SELECT COUNT(*) INTO v_n_bl  FROM tmp_his_bl;
    SELECT COUNT(*) INTO v_n_sla FROM tmp_his_sla3;

    IF NULLIF(TRIM(IFNULL(p_exportar, '')), '') IS NOT NULL THEN
        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, descripcion, id_usuario, registrado_en, metadata)
        VALUES ('expediente', p_id_expediente, 'exportar_historial',
                CONCAT('Auditoría del expediente exportada (', REPLACE(p_exportar, '_', ' '), ').'), p_id_usuario, NOW(),
                JSON_OBJECT('tab', p_exportar, 'busqueda', p_busqueda, 'id_usuario', p_id_usuario_evento, 'etapa_filtro', p_etapa,
                            'tipo_evento', p_tipo_evento, 'desde', p_desde, 'hasta', p_hasta));
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Resumen
    SELECT x.id_expediente, x.numero, c.razon_social, c.ruc, x.id_responsable, CONCAT(u.nombre, ' ', u.apellido) AS responsable,
           x.etapa, x.etapa_nombre
    FROM tmp_exp x
    LEFT JOIN cliente c ON c.id_cliente = x.id_cliente
    LEFT JOIN usuario u ON u.id_usuario = x.id_responsable;

    -- 3. Tabs con cantidad
    SELECT 'timeline' AS codigo, 'Timeline' AS nombre, v_n_tl AS cantidad UNION ALL
    SELECT 'reasignaciones', 'Reasignaciones', v_n_re UNION ALL
    SELECT 'bloqueos',       'Bloqueos',       v_n_bl UNION ALL
    SELECT 'alertas_sla',    'Alertas SLA',    v_n_sla;

    -- 4. Timeline (más recientes primero)
    SELECT * FROM tmp_his_tl ORDER BY fecha DESC;

    -- 5. Reasignaciones
    SELECT * FROM tmp_his_re ORDER BY fecha DESC;

    -- 6. Bloqueos
    SELECT * FROM tmp_his_bl ORDER BY fecha DESC;

    -- 7. Alertas SLA
    SELECT * FROM tmp_his_sla3 ORDER BY fecha DESC, orden_nivel DESC;

    -- 8. Tipos de evento
    SELECT v.codigo, v.nombre FROM (
        SELECT 1 AS o, 'creacion' AS codigo, 'Creación' AS nombre UNION ALL
        SELECT 2,  'requerimiento',  'Requerimiento'      UNION ALL
        SELECT 3,  'propuesta',      'Propuesta'          UNION ALL
        SELECT 4,  'visto_bueno',    'Visto bueno'        UNION ALL
        SELECT 5,  'seguimiento',    'Seguimiento'        UNION ALL
        SELECT 6,  'orden_compra',   'Orden de compra'    UNION ALL
        SELECT 7,  'orden_servicio', 'Orden de servicio'  UNION ALL
        SELECT 8,  'programacion',   'Programación'       UNION ALL
        SELECT 9,  'ejecucion',      'Ejecución'          UNION ALL
        SELECT 10, 'cierre',         'Cierre'             UNION ALL
        SELECT 11, 'bloqueo',        'Bloqueos y excepciones' UNION ALL
        SELECT 12, 'reasignacion',   'Reasignación'       UNION ALL
        SELECT 13, 'documento',      'Documentos'         UNION ALL
        SELECT 14, 'anulacion',      'Anulación'          UNION ALL
        SELECT 15, 'otro',           'Otros'
    ) v ORDER BY v.o;

    -- 9. Usuarios que aparecen en el historial
    SELECT DISTINCT u.id_usuario, CONCAT(u.nombre, ' ', u.apellido) AS nombre
    FROM (SELECT id_usuario FROM tmp_his_tl UNION SELECT id_ejecutado_por FROM tmp_his_re
          UNION SELECT id_usuario FROM tmp_his_bl UNION SELECT id_responsable FROM tmp_his_sla3) x
    JOIN usuario u ON u.id_usuario = x.id_usuario
    ORDER BY nombre;

    -- 10. Etapas (ETAPA_EXPEDIENTE, tal cual)
    SELECT String2 AS codigo, String1 AS nombre
    FROM tabla_maestra WHERE IdMaestro = 97 AND IdEmpresa = 1 AND eliminado_en IS NULL ORDER BY Num1;

    DROP TEMPORARY TABLE IF EXISTS tmp_his_tl;
    DROP TEMPORARY TABLE IF EXISTS tmp_his_re;
    DROP TEMPORARY TABLE IF EXISTS tmp_his_bl;
    DROP TEMPORARY TABLE IF EXISTS tmp_his_sla3;
    DROP TEMPORARY TABLE IF EXISTS tmp_exp;
END$$

DELIMITER ;
