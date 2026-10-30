-- HU-30 Tab 🚀 Ejecución de la ficha del expediente (carga perezosa, solo lectura). Acción expediente_bandeja.
-- Eventos de campo (GPS), evidencias fotográficas, incidencias y demoras registradas desde la app de campo.
-- Resultados: 1 mensaje · 2 resumen por OS (estado, llegada y fin reales, ubicación de llegada) · 3 timeline de
--   eventos de campo (con latitud y longitud) · 4 evidencias (clave evi-<id> para ver/descargar) · 5 incidencias
--   · 6 demoras
DROP PROCEDURE IF EXISTS SP_ObtenerEjecucionExpediente;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerEjecucionExpediente(
    IN p_id_usuario    BIGINT,
    IN p_id_expediente BIGINT
)
proc: BEGIN
    IF FN_PermisoAccion(p_id_usuario, 'expediente_bandeja') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver los expedientes digitales.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM expediente_digital WHERE id_expediente = p_id_expediente AND eliminado_en IS NULL) THEN
        SELECT 1 AS IdTipoMensaje, 'El expediente no existe.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Resumen por OS
    SELECT os.id_os, os.numero, os.estado, os.fecha_ejecucion, os.hora_inicio, os.hora_llegada_real, os.hora_fin_real,
           os.latitud_llegada, os.longitud_llegada, CONCAT(u.nombre, ' ', u.apellido) AS tecnico_principal
    FROM orden_servicio os LEFT JOIN usuario u ON u.id_usuario = os.id_tecnico_principal
    WHERE os.id_expediente = p_id_expediente AND os.eliminado_en IS NULL AND os.estado <> 'anulada'
    ORDER BY os.id_os;

    -- 3. Eventos de campo
    SELECT ec.id_evento, os.numero AS os, ec.timestamp_utc AS fecha, ec.id_tipo_evento, t29.String1 AS tipo_evento,
           ec.latitud, ec.longitud, ec.notas, ec.sincronizado, CONCAT(u.nombre, ' ', u.apellido) AS usuario
    FROM evento_campo ec
    JOIN orden_servicio os ON os.id_os = ec.id_os AND os.id_expediente = p_id_expediente AND os.eliminado_en IS NULL
    LEFT JOIN tabla_maestra t29 ON t29.IdMaestro = 29 AND t29.IdEmpresa = 1 AND t29.Num1 = ec.id_tipo_evento
    LEFT JOIN usuario u ON u.id_usuario = ec.id_usuario
    WHERE ec.eliminado_en IS NULL
    ORDER BY ec.timestamp_utc DESC;

    -- 4. Evidencias fotográficas
    SELECT CONCAT('evi-', ev.id_evidencia) AS clave, os.numero AS os, t30.String1 AS tipo_evidencia,
           SUBSTRING_INDEX(ev.url_archivo, '/', -1) AS nombre_archivo, ev.timestamp_captura AS fecha,
           ev.latitud, ev.longitud, ev.validacion_ia, ev.override_aprobado, CONCAT(u.nombre, ' ', u.apellido) AS usuario
    FROM evidencia_fotografica ev
    JOIN orden_servicio os ON os.id_os = ev.id_os AND os.id_expediente = p_id_expediente AND os.eliminado_en IS NULL
    LEFT JOIN tabla_maestra t30 ON t30.IdMaestro = 30 AND t30.IdEmpresa = 1 AND t30.Num1 = ev.id_tipo_evidencia
    LEFT JOIN usuario u ON u.id_usuario = ev.id_usuario
    WHERE ev.eliminado_en IS NULL
    ORDER BY ev.timestamp_captura DESC;

    -- 5. Incidencias
    SELECT i.id_incidencia, os.numero AS os, t33.String1 AS tipo, i.descripcion, t34.String1 AS nivel_alerta, i.estado,
           i.fecha_registro, CONCAT(u.nombre, ' ', u.apellido) AS usuario
    FROM incidencia_operativa i
    JOIN orden_servicio os ON os.id_os = i.id_os AND os.id_expediente = p_id_expediente AND os.eliminado_en IS NULL
    LEFT JOIN tabla_maestra t33 ON t33.IdMaestro = 33 AND t33.IdEmpresa = 1 AND t33.Num1 = i.id_tipo
    LEFT JOIN tabla_maestra t34 ON t34.IdMaestro = 34 AND t34.IdEmpresa = 1 AND t34.Num1 = i.id_nivel_alerta
    LEFT JOIN usuario u ON u.id_usuario = i.id_usuario
    WHERE i.eliminado_en IS NULL
    ORDER BY i.fecha_registro DESC;

    -- 6. Demoras
    SELECT d.id_demora, os.numero AS os, mo.String1 AS motivo, d.descripcion, d.duracion_minutos, d.fecha_registro,
           CONCAT(u.nombre, ' ', u.apellido) AS usuario
    FROM demora_registro d
    JOIN orden_servicio os ON os.id_os = d.id_os AND os.id_expediente = p_id_expediente AND os.eliminado_en IS NULL
    LEFT JOIN tabla_maestra mo ON mo.IdMaestro = 15 AND mo.IdEmpresa = 1 AND mo.Num1 = d.id_motivo
    LEFT JOIN usuario u ON u.id_usuario = d.id_usuario
    WHERE d.eliminado_en IS NULL
    ORDER BY d.fecha_registro DESC;
END$$

DELIMITER ;
