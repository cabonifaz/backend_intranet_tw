-- HU-30 Tab ✓ Visto Bueno de la ficha del expediente (carga perezosa, solo lectura). Acción expediente_bandeja.
-- Pills por propuesta ("Ver visto bueno de"); p_numero = número de la propuesta (por defecto la propuesta activa).
-- Resultados: 1 mensaje
--   2 propuestas del RQ (pills: número, última versión, seleccionada)
--   3 estado actual del VB de la propuesta: versión en revisión, estado global, aprobador asignado (cargo, área, correo,
--     teléfono), versión aprobada y su monto, fecha de aprobación final, horas hábiles vs. SLA
--   4 historial de decisiones por versión (aprobador, decisión, comentario, fechas y tiempo de revisión en horas hábiles)
--   5 historial de reasignación del aprobador
--   6 métricas: versiones totales, devueltas, tiempo total de aprobación (días), promedio por versión y SLA cumplido
DROP PROCEDURE IF EXISTS SP_ObtenerVistoBuenoExpediente;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerVistoBuenoExpediente(
    IN p_id_usuario    BIGINT,
    IN p_id_expediente BIGINT,
    IN p_numero        VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_id_rq   BIGINT;
    DECLARE v_numero  VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_ultima  BIGINT;
    DECLARE v_vb      BIGINT;

    IF FN_PermisoAccion(p_id_usuario, 'expediente_bandeja') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver los expedientes digitales.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM expediente_digital WHERE id_expediente = p_id_expediente AND eliminado_en IS NULL) THEN
        SELECT 1 AS IdTipoMensaje, 'El expediente no existe.' AS Mensaje;
        LEAVE proc;
    END IF;
    SELECT id_requerimiento INTO v_id_rq FROM expediente_digital WHERE id_expediente = p_id_expediente;

    IF NULLIF(TRIM(IFNULL(p_numero, '')), '') IS NOT NULL THEN
        SELECT MAX(p.numero) INTO v_numero FROM propuesta_comercial p
        WHERE p.id_requerimiento = v_id_rq AND p.eliminado_en IS NULL AND p.numero = TRIM(p_numero);
        IF v_numero IS NULL THEN
            SELECT 1 AS IdTipoMensaje, 'La propuesta no pertenece a este expediente.' AS Mensaje;
            LEAVE proc;
        END IF;
    ELSE
        -- Propuesta activa del expediente (la más avanzada entre las últimas versiones)
        SELECT p.numero INTO v_numero FROM propuesta_comercial p
        WHERE p.id_requerimiento = v_id_rq AND p.eliminado_en IS NULL AND p.estado <> 'anulado'
          AND p.version = (SELECT MAX(p2.version) FROM propuesta_comercial p2 WHERE p2.numero = p.numero AND p2.eliminado_en IS NULL)
        ORDER BY CASE p.estado WHEN 'aceptado' THEN 1 WHEN 'enviado' THEN 2 WHEN 'aprobado' THEN 2
                               WHEN 'pendiente_vb' THEN 3 WHEN 'pendiente_revocacion' THEN 3 WHEN 'rechazado' THEN 6 ELSE 4 END,
                 p.id_propuesta DESC
        LIMIT 1;
    END IF;

    SELECT MAX(p.id_propuesta) INTO v_ultima FROM propuesta_comercial p
    WHERE p.numero = v_numero AND p.eliminado_en IS NULL
      AND p.version = (SELECT MAX(p2.version) FROM propuesta_comercial p2 WHERE p2.numero = v_numero AND p2.eliminado_en IS NULL);

    -- VB vigente: el último de la propuesta (pendiente o resuelto)
    SELECT v.id_vb INTO v_vb FROM visto_bueno v
    JOIN propuesta_comercial p ON p.id_propuesta = v.id_propuesta
    WHERE p.numero = v_numero AND v.tipo = 'aprobacion' AND v.eliminado_en IS NULL AND v.estado <> 'reasignado'
    ORDER BY v.fecha_solicitud DESC, v.id_vb DESC LIMIT 1;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Propuestas (pills)
    SELECT p.numero, MAX(p.version) AS version, (p.numero = v_numero) AS seleccionada
    FROM propuesta_comercial p
    WHERE p.id_requerimiento = v_id_rq AND p.eliminado_en IS NULL
    GROUP BY p.numero ORDER BY MIN(p.id_propuesta);

    -- 3. Estado actual del VB
    SELECT v_numero AS numero, pu.id_propuesta AS id_propuesta_revision, pu.version AS version_revision,
           pu.estado AS estado_propuesta,
           CASE WHEN v.id_vb IS NULL THEN 'sin_solicitud' ELSE v.estado END AS estado_vb,
           v.id_vb, v.id_aprobador, CONCAT(ua.nombre, ' ', ua.apellido) AS aprobador, ua.cargo AS cargo_aprobador,
           aa.String1 AS area_aprobador, ua.correo AS correo_aprobador, ua.telefono AS telefono_aprobador,
           va.id_propuesta AS id_propuesta_aprobada, pa.version AS version_aprobada, pa.total AS monto_aprobado,
           m.String2 AS simbolo_moneda, va.fecha_respuesta AS fecha_aprobacion,
           IFNULL(v.sla_horas, va.sla_horas) AS sla_horas,
           IF(v.id_vb IS NULL, NULL, FN_HorasHabiles(v.fecha_solicitud, IFNULL(v.fecha_respuesta, NOW()))) AS horas_habiles,
           IF(v.id_vb IS NULL OR IFNULL(v.sla_horas, 0) = 0, NULL,
              FN_HorasHabiles(v.fecha_solicitud, IFNULL(v.fecha_respuesta, NOW())) <= v.sla_horas) AS dentro_sla,
           v.fecha_solicitud, v.comentario_respuesta AS comentario
    FROM (SELECT 1) d
    LEFT JOIN propuesta_comercial pu ON pu.id_propuesta = v_ultima
    LEFT JOIN visto_bueno v ON v.id_vb = v_vb
    LEFT JOIN usuario ua ON ua.id_usuario = v.id_aprobador
    LEFT JOIN tabla_maestra aa ON aa.IdMaestro = 79 AND aa.IdEmpresa = 1 AND aa.String2 = ua.area
    LEFT JOIN visto_bueno va ON va.id_vb = (SELECT v2.id_vb FROM visto_bueno v2
                                            JOIN propuesta_comercial p2 ON p2.id_propuesta = v2.id_propuesta
                                            WHERE p2.numero = v_numero AND v2.tipo = 'aprobacion' AND v2.estado = 'aprobado'
                                              AND v2.eliminado_en IS NULL
                                            ORDER BY v2.fecha_respuesta DESC LIMIT 1)
    LEFT JOIN propuesta_comercial pa ON pa.id_propuesta = va.id_propuesta
    LEFT JOIN tabla_maestra m ON m.IdMaestro = 1 AND m.IdEmpresa = 1 AND m.Num1 = pa.id_moneda;

    -- 4. Historial de decisiones por versión (más reciente primero)
    SELECT v.id_vb, p.id_propuesta, p.version, v.estado, v.id_aprobador, CONCAT(ua.nombre, ' ', ua.apellido) AS aprobador,
           ua.cargo AS cargo_aprobador, IFNULL(v.resuelto_por, v.id_aprobador) AS id_revisor,
           CONCAT(ur.nombre, ' ', ur.apellido) AS revisor, ur.cargo AS cargo_revisor,
           v.fecha_solicitud, v.fecha_respuesta, v.comentario_respuesta AS comentario, mr.String1 AS motivo_rechazo,
           IF(v.fecha_respuesta IS NULL, NULL, FN_HorasHabiles(v.fecha_solicitud, v.fecha_respuesta)) AS horas_revision,
           v.sla_horas
    FROM visto_bueno v
    JOIN propuesta_comercial p ON p.id_propuesta = v.id_propuesta
    LEFT JOIN usuario ua ON ua.id_usuario = v.id_aprobador
    LEFT JOIN usuario ur ON ur.id_usuario = IFNULL(v.resuelto_por, v.id_aprobador)
    LEFT JOIN tabla_maestra mr ON mr.IdMaestro = 10 AND mr.IdEmpresa = 1 AND mr.Num1 = v.id_motivo_rechazo
    WHERE p.numero = v_numero AND v.tipo = 'aprobacion' AND v.eliminado_en IS NULL AND v.estado <> 'reasignado'
    ORDER BY v.fecha_solicitud DESC, v.id_vb DESC;

    -- 5. Historial de reasignación del aprobador
    SELECT v.id_vb, p.version, v.fecha_respuesta AS fecha, v.id_aprobador AS id_anterior,
           CONCAT(ua.nombre, ' ', ua.apellido) AS aprobador_anterior,
           n.id_aprobador AS id_nuevo, CONCAT(un.nombre, ' ', un.apellido) AS aprobador_nuevo,
           mo.String1 AS motivo, NULLIF(TRIM(IFNULL(v.comentario_respuesta, '')), '') AS comentario,
           IFNULL(v.resuelto_por, n.creado_por) AS id_ejecutado_por,
           CONCAT(ue.nombre, ' ', ue.apellido) AS ejecutado_por
    FROM visto_bueno v
    JOIN propuesta_comercial p ON p.id_propuesta = v.id_propuesta
    LEFT JOIN visto_bueno n ON n.id_vb_origen = v.id_vb AND n.eliminado_en IS NULL
    LEFT JOIN usuario ua ON ua.id_usuario = v.id_aprobador
    LEFT JOIN usuario un ON un.id_usuario = n.id_aprobador
    LEFT JOIN usuario ue ON ue.id_usuario = IFNULL(v.resuelto_por, n.creado_por)
    LEFT JOIN tabla_maestra mo ON mo.IdMaestro = 92 AND mo.IdEmpresa = 1 AND mo.Num1 = IFNULL(n.id_motivo_reasignacion, v.id_motivo_reasignacion)
    WHERE p.numero = v_numero AND v.tipo = 'aprobacion' AND v.eliminado_en IS NULL AND v.estado = 'reasignado'
    ORDER BY v.fecha_respuesta DESC;

    -- 6. Métricas de aprobación
    SELECT COUNT(DISTINCT p.id_propuesta)                                                   AS versiones_totales,
           SUM(v.estado IN ('devuelto', 'rechazado'))                                       AS versiones_devueltas,
           ROUND(TIMESTAMPDIFF(MINUTE, MIN(v.fecha_solicitud),
                 IFNULL(MAX(IF(v.estado = 'aprobado', v.fecha_respuesta, NULL)), NOW())) / 1440, 1) AS dias_totales,
           ROUND(AVG(IF(v.fecha_respuesta IS NULL, NULL, TIMESTAMPDIFF(MINUTE, v.fecha_solicitud, v.fecha_respuesta))) / 1440, 1)
                                                                                            AS dias_promedio_revision,
           SUM(v.fecha_respuesta IS NOT NULL AND IFNULL(v.sla_horas, 0) > 0
               AND FN_HorasHabiles(v.fecha_solicitud, v.fecha_respuesta) <= v.sla_horas)    AS decisiones_en_sla,
           SUM(v.fecha_respuesta IS NOT NULL)                                               AS decisiones
    FROM visto_bueno v
    JOIN propuesta_comercial p ON p.id_propuesta = v.id_propuesta
    WHERE p.numero = v_numero AND v.tipo = 'aprobacion' AND v.eliminado_en IS NULL AND v.estado <> 'reasignado';
END$$

DELIMITER ;
