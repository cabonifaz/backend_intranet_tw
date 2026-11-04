-- HU-38 (Sprint 5) Datos de la ficha "Reprogramar Servicio": origen heredado (no editable), cronograma y técnico actuales, equipos
-- reservados (con los de la OS que se pueden reservar), motivos tipificados, viáticos ya depositados y el circuito que le toca a quien
-- abre la ficha: modo 'directa' (Jefe: guarda y se aplica) o 'solicitud' (Asistente: se envía al Jefe). La ficha está BLOQUEADA
-- (puede_reprogramar = 0) si la programación está cancelada, el servicio ya empezó o, para el Asistente, ya hay una solicitud pendiente.
-- Solo lectura. Acceso: prog_gestionar.
-- Resultados: 1 mensaje, 2 programación, 3 técnicos actuales, 4 equipos de la OS (reservado 0/1), 5 motivos.
DROP PROCEDURE IF EXISTS SP_PrepararReprogramacion;

DELIMITER $$

CREATE PROCEDURE SP_PrepararReprogramacion(
    IN p_id_usuario      BIGINT,
    IN p_id_programacion BIGINT
)
proc: BEGIN
    DECLARE v_id_os    BIGINT DEFAULT NULL;
    DECLARE v_directa  TINYINT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF FN_PermisoAccion(p_id_usuario, 'prog_gestionar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para reprogramar servicios.' AS Mensaje;
        LEAVE proc;
    END IF;
    SET v_directa = IF(FN_PermisoAccion(p_id_usuario, 'prog_aprobar_reprogramacion') = 1, 1, 0);

    SELECT id_os INTO v_id_os FROM programacion WHERE id_programacion = p_id_programacion AND eliminado_en IS NULL;
    IF v_id_os IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'La programación no existe.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT pr.id_programacion, pr.codigo, pr.estado,
           CASE pr.estado WHEN 'pendiente_confirmacion' THEN 'Pendiente confirmación cliente'
                          WHEN 'confirmada' THEN 'Programado' ELSE 'Cancelada' END                      AS estado_label,
           os.id_os, os.numero AS numero_os, os.tipo, os.estado AS estado_os,
           os.id_expediente, e.numero AS numero_expediente,
           c.razon_social, c.ruc,
           sc.nombre AS sede, sc.direccion_exacta AS ubicacion,
           COALESCE(os.id_propuesta, e.id_propuesta)                                                      AS id_propuesta,
           p.numero AS numero_propuesta, p.version AS version_propuesta,
           ts.String1 AS tipo_servicio,
           pr.fecha_ejecucion,
           TIME_FORMAT(pr.hora_inicio, '%H:%i')                                                           AS hora_inicio,
           TIME_FORMAT(pr.hora_fin_estimada, '%H:%i')                                                     AS hora_fin,
           ROUND(TIME_TO_SEC(TIMEDIFF(pr.hora_fin_estimada, pr.hora_inicio)) / 3600, 2)                   AS duracion_horas,
           pr.id_tecnico_principal,
           TRIM(CONCAT(ut.nombre, ' ', ut.apellido))                                                      AS tecnico_principal,
           (SELECT COUNT(*) FROM os_equipo oe WHERE oe.id_os = os.id_os AND oe.eliminado_en IS NULL)      AS n_equipos_os,
           (SELECT COUNT(*) FROM os_concepto oc WHERE oc.id_os = os.id_os AND oc.eliminado_en IS NULL)    AS n_conceptos,
           IFNULL((SELECT SUM(g.monto) FROM gasto_viatico g
                   WHERE g.id_os = os.id_os AND g.eliminado_en IS NULL AND g.tipo = 'viatico_asignado' AND g.estado = 'aprobado'), 0) AS viaticos_depositados,
           IF(v_directa = 1, 'directa', 'solicitud')                                                      AS modo,
           (SELECT MAX(rp.id_reprogramacion) FROM os_reprogramacion rp
            WHERE rp.id_programacion = pr.id_programacion AND rp.estado = 'pendiente' AND rp.eliminado_en IS NULL) AS id_solicitud_pendiente,
           IF(pr.estado <> 'cancelada' AND os.estado IN ('programada', 'reprogramada')
              AND (v_directa = 1 OR NOT EXISTS (SELECT 1 FROM os_reprogramacion rp
                                                WHERE rp.id_programacion = pr.id_programacion AND rp.estado = 'pendiente' AND rp.eliminado_en IS NULL)), 1, 0) AS puede_reprogramar,
           CASE WHEN pr.estado = 'cancelada' THEN 'La programación está cancelada: ya no admite cambios.'
                WHEN os.estado NOT IN ('programada', 'reprogramada') THEN 'El servicio ya empezó: no se puede reprogramar.'
                WHEN v_directa = 0 AND EXISTS (SELECT 1 FROM os_reprogramacion rp
                                               WHERE rp.id_programacion = pr.id_programacion AND rp.estado = 'pendiente' AND rp.eliminado_en IS NULL)
                     THEN 'Ya hay una solicitud de reprogramación pendiente del Jefe.'
                ELSE NULL END                                                                             AS motivo_no_reprogramable,
           400                                                                                            AS comentario_maximo
    FROM programacion pr
    JOIN orden_servicio os          ON os.id_os = pr.id_os
    LEFT JOIN cliente c             ON c.id_cliente = os.id_cliente
    LEFT JOIN sede_cliente sc       ON sc.id_sede = os.id_sede
    LEFT JOIN expediente_digital e  ON e.id_expediente = os.id_expediente
    LEFT JOIN propuesta_comercial p ON p.id_propuesta = COALESCE(os.id_propuesta, e.id_propuesta)
    LEFT JOIN tabla_maestra ts      ON ts.IdMaestro = 3 AND ts.IdEmpresa = 1 AND ts.Num1 = os.id_tipo_servicio
    LEFT JOIN usuario ut            ON ut.id_usuario = pr.id_tecnico_principal
    WHERE pr.id_programacion = p_id_programacion;

    SELECT u.id_usuario, TRIM(CONCAT(u.nombre, ' ', u.apellido)) AS nombre,
           COALESCE(cg.String1, u.cargo, IF(u.area = 'metrologia', 'Metrología', 'Servicio Técnico')) AS cargo, pt.rol
    FROM programacion_tecnico pt
    JOIN usuario u             ON u.id_usuario = pt.id_usuario
    LEFT JOIN tabla_maestra cg ON cg.IdMaestro = 80 AND cg.IdEmpresa = 1 AND cg.String2 = u.cargo
    WHERE pt.id_programacion = p_id_programacion AND pt.eliminado_en IS NULL
    ORDER BY pt.rol = 'apoyo', u.nombre, u.apellido;

    SELECT ec.id_equipo, ec.codigo_tw, ec.marca, ec.modelo, ec.num_serie,
           IF(EXISTS (SELECT 1 FROM programacion_equipo pe
                      WHERE pe.id_programacion = p_id_programacion AND pe.id_equipo = oe.id_equipo AND pe.eliminado_en IS NULL), 1, 0) AS reservado
    FROM os_equipo oe
    JOIN equipo_cliente ec ON ec.id_equipo = oe.id_equipo
    WHERE oe.id_os = v_id_os AND oe.eliminado_en IS NULL
    ORDER BY ec.codigo_tw, ec.id_equipo;

    SELECT t.Num1 AS id_motivo, t.String1 AS nombre, t.String2 AS codigo
    FROM tabla_maestra t
    WHERE t.IdMaestro = 13 AND t.IdEmpresa = 1 AND t.eliminado_en IS NULL
    ORDER BY t.Num1;
END$$

DELIMITER ;
