-- HU-38 (Sprint 5) Historial de programaciones de una OS/OM: todas (activa y canceladas) con su timeline completo (creación, respuestas del
-- cliente, reprogramaciones y su motivo, aprobaciones o rechazos, cancelación). Se abre desde el detalle de la OS (Módulo 9) y desde el
-- detalle de la programación activa. Reprogramaciones sin límite. Solo lectura. Acceso: prog_bandeja.
-- Resultados: 1 mensaje, 2 programaciones (la más reciente primero), 3 eventos (id_programacion, en orden cronológico).
DROP PROCEDURE IF EXISTS SP_ObtenerHistorialProgramacionesOs;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerHistorialProgramacionesOs(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT
)
proc: BEGIN
    DECLARE v_numero VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF FN_PermisoAccion(p_id_usuario, 'prog_bandeja') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver la programación operativa.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT numero INTO v_numero FROM orden_servicio WHERE id_os = IFNULL(p_id_os, 0) AND eliminado_en IS NULL;
    IF v_numero IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'La orden de servicio no existe.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT pr.id_programacion, pr.codigo, pr.estado,
           CASE pr.estado WHEN 'pendiente_confirmacion' THEN 'Pendiente confirmación cliente'
                          WHEN 'confirmada' THEN 'Programado' ELSE 'Cancelada' END                      AS estado_label,
           IF(pr.estado <> 'cancelada', 1, 0)                                                            AS es_activa,
           pr.fecha_ejecucion,
           TIME_FORMAT(pr.hora_inicio, '%H:%i')                                                          AS hora_inicio,
           TIME_FORMAT(pr.hora_fin_estimada, '%H:%i')                                                    AS hora_fin,
           TRIM(CONCAT(ut.nombre, ' ', ut.apellido))                                                     AS tecnico_principal,
           pr.creado_en, TRIM(CONCAT(uc.nombre, ' ', uc.apellido))                                       AS creado_por_nombre,
           pr.cancelada_en, TRIM(CONCAT(ux.nombre, ' ', ux.apellido))                                    AS cancelada_por_nombre,
           IFNULL(mc.String1, IF(pr.estado = 'cancelada' AND pr.id_motivo_cancelacion IS NULL, 'Orden anulada', NULL)) AS motivo_cancelacion,
           pr.comentario_cancelacion,
           (SELECT COUNT(*) FROM os_reprogramacion rp
            WHERE rp.id_programacion = pr.id_programacion AND rp.eliminado_en IS NULL)                   AS n_solicitudes,
           (SELECT COUNT(*) FROM auditoria_evento ae
            WHERE ae.entidad_tipo = 'programacion' AND ae.id_entidad = pr.id_programacion
              AND ae.accion IN ('reprogramacion_directa', 'aprobar_reprogramacion'))                     AS n_reprogramaciones
    FROM programacion pr
    LEFT JOIN usuario ut       ON ut.id_usuario = pr.id_tecnico_principal
    LEFT JOIN usuario uc       ON uc.id_usuario = pr.creado_por
    LEFT JOIN usuario ux       ON ux.id_usuario = pr.cancelada_por
    LEFT JOIN tabla_maestra mc ON mc.Descripcion = 'MOTIVO_CANCELACION_PROGRAMACION' AND mc.IdEmpresa = 1 AND mc.Num1 = pr.id_motivo_cancelacion
    WHERE pr.id_os = p_id_os AND pr.eliminado_en IS NULL
    ORDER BY pr.id_programacion DESC;

    SELECT x.id_programacion, x.fecha, x.tipo, x.titulo, x.descripcion, x.usuario, x.estado_anterior, x.estado_nuevo, x.motivo
    FROM (
        SELECT pr.id_programacion, ae.registrado_en AS fecha, 1 AS ord,
               CASE ae.accion WHEN 'programar_os' THEN 'programacion'
                              WHEN 'respuesta_cliente' THEN 'respuesta_cliente'
                              WHEN 'anular_os' THEN 'cancelacion'
                              WHEN 'cancelar_programacion' THEN 'cancelacion'
                              WHEN 'solicitar_reprogramacion' THEN 'reprogramacion'
                              WHEN 'reprogramacion_directa' THEN 'reprogramacion'
                              WHEN 'aprobar_reprogramacion' THEN 'aprobacion'
                              WHEN 'rechazar_reprogramacion' THEN 'aprobacion'
                              WHEN 'retirar_solicitud_reprogramacion' THEN 'aprobacion'
                              ELSE 'estado' END                                       AS tipo,
               CASE ae.accion WHEN 'programar_os' THEN 'Programación creada'
                              WHEN 'respuesta_cliente' THEN 'Respuesta del cliente'
                              WHEN 'anular_os' THEN 'Orden anulada: programación cancelada'
                              WHEN 'cancelar_programacion' THEN 'Programación cancelada'
                              WHEN 'solicitar_reprogramacion' THEN 'Reprogramación solicitada'
                              WHEN 'reprogramacion_directa' THEN 'Reprogramación (edición directa del Jefe)'
                              WHEN 'aprobar_reprogramacion' THEN 'Reprogramación aprobada'
                              WHEN 'rechazar_reprogramacion' THEN 'Reprogramación rechazada'
                              WHEN 'retirar_solicitud_reprogramacion' THEN 'Solicitud de reprogramación retirada'
                              ELSE ae.accion END                                      AS titulo,
               ae.descripcion, TRIM(CONCAT(ua.nombre, ' ', ua.apellido))              AS usuario,
               ae.estado_anterior, ae.estado_nuevo,
               JSON_UNQUOTE(JSON_EXTRACT(ae.metadata, '$.motivo'))                    AS motivo
        FROM auditoria_evento ae
        JOIN programacion pr ON pr.id_os = p_id_os AND pr.eliminado_en IS NULL
                            AND ((ae.entidad_tipo = 'programacion' AND ae.id_entidad = pr.id_programacion)
                              OR (ae.entidad_tipo = 'orden_servicio' AND ae.id_entidad = p_id_os AND ae.accion = 'programar_os'
                                  AND CAST(JSON_UNQUOTE(JSON_EXTRACT(ae.metadata, '$.idProgramacion')) AS UNSIGNED) = pr.id_programacion)
                              OR (ae.entidad_tipo = 'orden_servicio' AND ae.id_entidad = p_id_os AND ae.accion = 'anular_os'
                                  AND ae.registrado_en >= pr.creado_en AND pr.estado = 'cancelada' AND pr.id_motivo_cancelacion IS NULL))
        LEFT JOIN usuario ua ON ua.id_usuario = ae.id_usuario
        UNION ALL
        -- Solicitudes anteriores a la HU-38 (sin programación asociada): van a la programación vigente en ese momento
        SELECT (SELECT MAX(p2.id_programacion) FROM programacion p2
                WHERE p2.id_os = p_id_os AND p2.eliminado_en IS NULL AND p2.creado_en <= rp.fecha_solicitud),
               rp.fecha_solicitud, 2, 'reprogramacion', 'Reprogramación solicitada',
               CONCAT('Propone el ', DATE_FORMAT(rp.fecha_propuesta, '%d/%m/%Y'),
                      IF(rp.hora_propuesta IS NULL, '', CONCAT(' a las ', TIME_FORMAT(rp.hora_propuesta, '%H:%i'))), '. ', rp.comentario),
               TRIM(CONCAT(us.nombre, ' ', us.apellido)), NULL, NULL, mo.String1
        FROM os_reprogramacion rp
        LEFT JOIN usuario us       ON us.id_usuario = rp.id_solicitante
        LEFT JOIN tabla_maestra mo ON mo.IdMaestro = 13 AND mo.IdEmpresa = 1 AND mo.Num1 = rp.id_motivo
        WHERE rp.id_os = p_id_os AND rp.id_programacion IS NULL AND rp.eliminado_en IS NULL
    ) x
    WHERE x.id_programacion IS NOT NULL
    ORDER BY x.id_programacion, x.fecha, x.ord;
END$$

DELIMITER ;
