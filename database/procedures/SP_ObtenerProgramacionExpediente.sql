-- HU-30 Tab 📅 Programación de la ficha del expediente (carga perezosa, solo lectura). Acción expediente_bandeja.
-- Calendario de ejecución de las OS, recursos reservados y backlog de programación del expediente.
-- Resultados: 1 mensaje · 2 calendario (una fila por OS: fecha, horas, técnico, estado, confirmación del cliente)
--   · 3 recursos reservados (personal y equipos por OS) · 4 backlog de programación (prioridad, técnico sugerido,
--   fecha límite, estado, notas: reprogramaciones y conflictos resueltos) · 5 checklist de presalida
DROP PROCEDURE IF EXISTS SP_ObtenerProgramacionExpediente;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerProgramacionExpediente(
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

    -- 2. Calendario de ejecución
    SELECT os.id_os, os.numero, os.estado, os.fecha_ejecucion, os.hora_inicio, os.hora_fin_estimada,
           os.id_tecnico_principal, CONCAT(u.nombre, ' ', u.apellido) AS tecnico_principal,
           s.nombre AS sede, os.confirmacion_cliente, os.fecha_confirmacion_cliente
    FROM orden_servicio os
    LEFT JOIN usuario u      ON u.id_usuario = os.id_tecnico_principal
    LEFT JOIN sede_cliente s ON s.id_sede = os.id_sede
    WHERE os.id_expediente = p_id_expediente AND os.eliminado_en IS NULL
    ORDER BY os.fecha_ejecucion, os.hora_inicio;

    -- 3. Recursos reservados
    SELECT os.numero AS os, 'personal' AS tipo_recurso, CONCAT(u.nombre, ' ', u.apellido) AS recurso, p.rol_en_servicio AS detalle,
           p.estado_ssoma AS estado
    FROM os_personal p
    JOIN orden_servicio os ON os.id_os = p.id_os AND os.id_expediente = p_id_expediente AND os.eliminado_en IS NULL
    LEFT JOIN usuario u ON u.id_usuario = p.id_usuario
    WHERE p.eliminado_en IS NULL
    UNION ALL
    SELECT os.numero, 'equipo', COALESCE(ec.codigo_tw, e.codigo_tw, CONCAT('Equipo ', oe.id_equipo)),
           ti.String1, IF(oe.ingresado_en_campo = 1, 'ingresado', 'reservado')
    FROM os_equipo oe
    JOIN orden_servicio os ON os.id_os = oe.id_os AND os.id_expediente = p_id_expediente AND os.eliminado_en IS NULL
    LEFT JOIN equipo_cliente ec ON ec.id_equipo = oe.id_equipo
    LEFT JOIN equipo e          ON e.id_equipo = oe.id_equipo
    LEFT JOIN tabla_maestra ti  ON ti.IdMaestro = 31 AND ti.IdEmpresa = 1 AND ti.Num1 = oe.id_tipo_intervencion
    WHERE oe.eliminado_en IS NULL;

    -- 4. Backlog de programación
    SELECT b.id_backlog, os.numero AS os, om.numero AS om, pr.String1 AS prioridad,
           CONCAT(u.nombre, ' ', u.apellido) AS tecnico_sugerido, b.fecha_limite, b.estado, b.notas_programacion,
           b.creado_en, b.modificado_en
    FROM backlog_programacion b
    LEFT JOIN orden_servicio os   ON os.id_os = b.id_os
    LEFT JOIN orden_metrologia om ON om.id_om = b.id_om
    LEFT JOIN tabla_maestra pr    ON pr.IdMaestro = 7 AND pr.IdEmpresa = 1 AND pr.Num1 = b.id_prioridad
    LEFT JOIN usuario u           ON u.id_usuario = b.id_tecnico_sugerido
    WHERE b.id_expediente = p_id_expediente AND b.eliminado_en IS NULL
    ORDER BY b.fecha_limite, b.id_backlog;

    -- 5. Checklist de presalida
    SELECT os.numero AS os, i.descripcion, i.confirmado, i.confirmado_en, CONCAT(u.nombre, ' ', u.apellido) AS confirmado_por
    FROM item_presalida i
    JOIN orden_servicio os ON os.id_os = i.id_os AND os.id_expediente = p_id_expediente AND os.eliminado_en IS NULL
    LEFT JOIN usuario u ON u.id_usuario = i.confirmado_por
    WHERE i.eliminado_en IS NULL
    ORDER BY os.id_os, i.id_item;
END$$

DELIMITER ;
