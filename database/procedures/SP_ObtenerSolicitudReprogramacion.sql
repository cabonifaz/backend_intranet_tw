-- HU-38 (Sprint 5) Detalle de una solicitud de reprogramación: es el modal "Solicitud de Reprogramación" del Jefe (programación actual
-- contra cambios propuestos, justificación del Asistente e impacto si se aprueba). Se abre con el id_reprogramacion_pendiente que trae
-- la fila de la bandeja o con id_solicitud_pendiente del detalle de la programación.
-- Solo lectura. Acceso: prog_bandeja. puede_resolver = el usuario es jefe (prog_aprobar_reprogramacion) y la solicitud sigue pendiente.
-- Resultados: 1 mensaje, 2 solicitud, 3 equipo de trabajo propuesto (principal y apoyo), 4 equipos propuestos.
DROP PROCEDURE IF EXISTS SP_ObtenerSolicitudReprogramacion;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerSolicitudReprogramacion(
    IN p_id_usuario   BIGINT,
    IN p_id_solicitud BIGINT
)
proc: BEGIN
    DECLARE v_id_os    BIGINT DEFAULT NULL;
    DECLARE v_id_prog  BIGINT DEFAULT NULL;
    DECLARE v_tec_p    BIGINT DEFAULT NULL;
    DECLARE v_apoyo    JSON;
    DECLARE v_equipos  JSON;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_sol_tec;
        DROP TEMPORARY TABLE IF EXISTS tmp_sol_eq;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF FN_PermisoAccion(p_id_usuario, 'prog_bandeja') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver la programación operativa.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT rp.id_os, IFNULL(rp.id_programacion, (SELECT MAX(pr.id_programacion) FROM programacion pr
                                                  WHERE pr.id_os = rp.id_os AND pr.estado <> 'cancelada' AND pr.eliminado_en IS NULL)),
           rp.id_tecnico_propuesto, rp.ids_apoyo_propuestos, rp.ids_equipos_propuestos
      INTO v_id_os, v_id_prog, v_tec_p, v_apoyo, v_equipos
    FROM os_reprogramacion rp WHERE rp.id_reprogramacion = p_id_solicitud AND rp.eliminado_en IS NULL;

    IF v_id_os IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'La solicitud de reprogramación no existe.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_id_prog IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'La solicitud no corresponde a una programación.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Equipo de trabajo y equipos que quedarían (NULL = se mantienen los actuales)
    DROP TEMPORARY TABLE IF EXISTS tmp_sol_tec;
    DROP TEMPORARY TABLE IF EXISTS tmp_sol_eq;
    CREATE TEMPORARY TABLE tmp_sol_tec (id_usuario BIGINT NOT NULL, rol VARCHAR(10) NOT NULL, PRIMARY KEY (id_usuario));
    CREATE TEMPORARY TABLE tmp_sol_eq (id_equipo BIGINT NOT NULL, PRIMARY KEY (id_equipo));

    INSERT INTO tmp_sol_tec (id_usuario, rol)
    SELECT IFNULL(v_tec_p, pr.id_tecnico_principal), 'principal' FROM programacion pr WHERE pr.id_programacion = v_id_prog;
    IF v_apoyo IS NULL THEN
        INSERT IGNORE INTO tmp_sol_tec (id_usuario, rol)
        SELECT id_usuario, 'apoyo' FROM programacion_tecnico WHERE id_programacion = v_id_prog AND rol = 'apoyo' AND eliminado_en IS NULL;
    ELSE
        INSERT IGNORE INTO tmp_sol_tec (id_usuario, rol)
        SELECT jt.id, 'apoyo' FROM JSON_TABLE(v_apoyo, '$[*]' COLUMNS (id BIGINT PATH '$')) jt WHERE jt.id IS NOT NULL AND jt.id > 0;
    END IF;
    IF v_equipos IS NULL THEN
        INSERT IGNORE INTO tmp_sol_eq (id_equipo)
        SELECT id_equipo FROM programacion_equipo WHERE id_programacion = v_id_prog AND eliminado_en IS NULL;
    ELSE
        INSERT IGNORE INTO tmp_sol_eq (id_equipo)
        SELECT jt.id FROM JSON_TABLE(v_equipos, '$[*]' COLUMNS (id BIGINT PATH '$')) jt WHERE jt.id IS NOT NULL AND jt.id > 0;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT rp.id_reprogramacion AS id_solicitud, rp.estado,
           CASE rp.estado WHEN 'pendiente' THEN 'Pendiente de aprobación' WHEN 'aprobada' THEN 'Aprobada'
                          WHEN 'rechazada' THEN 'Rechazada' ELSE 'Retirada' END                          AS estado_label,
           pr.id_programacion, pr.codigo, os.id_os, os.numero AS numero_os, c.razon_social,
           rp.id_solicitante, TRIM(CONCAT(us.nombre, ' ', us.apellido))                                   AS solicitante,
           COALESCE(cg.String1, us.cargo)                                                                 AS cargo_solicitante,
           rp.fecha_solicitud,
           mo.String1 AS motivo, rp.comentario,
           -- Programación actual (la vigente hoy)
           pr.fecha_ejecucion                                                                             AS fecha_actual,
           TIME_FORMAT(pr.hora_inicio, '%H:%i')                                                           AS hora_inicio_actual,
           TIME_FORMAT(pr.hora_fin_estimada, '%H:%i')                                                     AS hora_fin_actual,
           ROUND(TIME_TO_SEC(TIMEDIFF(pr.hora_fin_estimada, pr.hora_inicio)) / 3600, 2)                   AS duracion_actual_horas,
           pr.id_tecnico_principal                                                                        AS id_tecnico_actual,
           TRIM(CONCAT(ua.nombre, ' ', ua.apellido))                                                      AS tecnico_actual,
           pr.estado                                                                                      AS estado_programacion,
           CASE pr.estado WHEN 'pendiente_confirmacion' THEN 'Pendiente confirmación cliente'
                          WHEN 'confirmada' THEN 'Programado' ELSE 'Cancelada' END                        AS estado_programacion_label,
           -- Cambios propuestos
           rp.fecha_propuesta                                                                             AS fecha_propuesta,
           TIME_FORMAT(IFNULL(rp.hora_propuesta, pr.hora_inicio), '%H:%i')                                AS hora_inicio_propuesta,
           TIME_FORMAT(IFNULL(rp.hora_fin_propuesta, pr.hora_fin_estimada), '%H:%i')                      AS hora_fin_propuesta,
           ROUND(TIME_TO_SEC(TIMEDIFF(IFNULL(rp.hora_fin_propuesta, pr.hora_fin_estimada), IFNULL(rp.hora_propuesta, pr.hora_inicio))) / 3600, 2) AS duracion_propuesta_horas,
           DATEDIFF(rp.fecha_propuesta, pr.fecha_ejecucion)                                               AS dias_diferencia,
           TIMESTAMPDIFF(MINUTE, pr.hora_inicio, IFNULL(rp.hora_propuesta, pr.hora_inicio))               AS minutos_inicio,
           TIMESTAMPDIFF(MINUTE, pr.hora_fin_estimada, IFNULL(rp.hora_fin_propuesta, pr.hora_fin_estimada)) AS minutos_fin,
           IFNULL(rp.id_tecnico_propuesto, pr.id_tecnico_principal)                                       AS id_tecnico_propuesto,
           TRIM(CONCAT(up.nombre, ' ', up.apellido))                                                      AS tecnico_propuesto,
           IF(rp.id_tecnico_propuesto IS NOT NULL AND rp.id_tecnico_propuesto <> pr.id_tecnico_principal, 1, 0) AS cambia_tecnico_principal,
           IF(rp.ids_apoyo_propuestos IS NOT NULL, 1, 0)                                                  AS propone_apoyo,
           IF(rp.ids_equipos_propuestos IS NOT NULL, 1, 0)                                                AS propone_equipos,
           IF(rp.fecha_propuesta <> pr.fecha_ejecucion
              OR TIME_TO_SEC(IFNULL(rp.hora_propuesta, pr.hora_inicio)) <> TIME_TO_SEC(pr.hora_inicio)
              OR TIME_TO_SEC(IFNULL(rp.hora_fin_propuesta, pr.hora_fin_estimada)) <> TIME_TO_SEC(pr.hora_fin_estimada), 1, 0) AS cambia_fecha_hora,
           -- Impacto si se aprueba
           IF(rp.fecha_propuesta <> pr.fecha_ejecucion
              OR TIME_TO_SEC(IFNULL(rp.hora_propuesta, pr.hora_inicio)) <> TIME_TO_SEC(pr.hora_inicio)
              OR TIME_TO_SEC(IFNULL(rp.hora_fin_propuesta, pr.hora_fin_estimada)) <> TIME_TO_SEC(pr.hora_fin_estimada),
              'pendiente_confirmacion', pr.estado)                                                        AS nuevo_estado,
           IF(rp.fecha_propuesta <> pr.fecha_ejecucion
              OR TIME_TO_SEC(IFNULL(rp.hora_propuesta, pr.hora_inicio)) <> TIME_TO_SEC(pr.hora_inicio)
              OR TIME_TO_SEC(IFNULL(rp.hora_fin_propuesta, pr.hora_fin_estimada)) <> TIME_TO_SEC(pr.hora_fin_estimada),
              'Pendiente confirmación cliente',
              CASE pr.estado WHEN 'confirmada' THEN 'Programado' ELSE 'Pendiente confirmación cliente' END) AS nuevo_estado_label,
           IFNULL((SELECT SUM(g.monto) FROM gasto_viatico g
                   WHERE g.id_os = os.id_os AND g.eliminado_en IS NULL AND g.tipo = 'viatico_asignado' AND g.estado = 'aprobado'), 0) AS viaticos_depositados,
           -- Resolución
           rp.resuelto_por, TRIM(CONCAT(ur.nombre, ' ', ur.apellido))                                     AS resuelto_por_nombre,
           rp.fecha_resolucion, rp.comentario_resolucion,
           IF(rp.estado = 'pendiente' AND FN_PermisoAccion(p_id_usuario, 'prog_aprobar_reprogramacion') = 1, 1, 0) AS puede_resolver,
           IF(rp.estado = 'pendiente' AND (rp.id_solicitante = p_id_usuario
                                           OR FN_PermisoAccion(p_id_usuario, 'prog_aprobar_reprogramacion') = 1), 1, 0) AS puede_retirar
    FROM os_reprogramacion rp
    JOIN programacion pr           ON pr.id_programacion = v_id_prog
    JOIN orden_servicio os         ON os.id_os = rp.id_os
    LEFT JOIN cliente c            ON c.id_cliente = os.id_cliente
    LEFT JOIN usuario us           ON us.id_usuario = rp.id_solicitante
    LEFT JOIN tabla_maestra cg     ON cg.IdMaestro = 80 AND cg.IdEmpresa = 1 AND cg.String2 = us.cargo
    LEFT JOIN tabla_maestra mo     ON mo.IdMaestro = 13 AND mo.IdEmpresa = 1 AND mo.Num1 = rp.id_motivo
    LEFT JOIN usuario ua           ON ua.id_usuario = pr.id_tecnico_principal
    LEFT JOIN usuario up           ON up.id_usuario = IFNULL(rp.id_tecnico_propuesto, pr.id_tecnico_principal)
    LEFT JOIN usuario ur           ON ur.id_usuario = rp.resuelto_por
    WHERE rp.id_reprogramacion = p_id_solicitud;

    SELECT u.id_usuario, TRIM(CONCAT(u.nombre, ' ', u.apellido)) AS nombre, t.rol
    FROM tmp_sol_tec t JOIN usuario u ON u.id_usuario = t.id_usuario
    ORDER BY t.rol = 'apoyo', u.nombre, u.apellido;

    SELECT ec.id_equipo, ec.codigo_tw, ec.marca, ec.modelo, ec.num_serie
    FROM tmp_sol_eq q JOIN equipo_cliente ec ON ec.id_equipo = q.id_equipo
    ORDER BY ec.codigo_tw, ec.id_equipo;

    DROP TEMPORARY TABLE IF EXISTS tmp_sol_tec;
    DROP TEMPORARY TABLE IF EXISTS tmp_sol_eq;
END$$

DELIMITER ;
