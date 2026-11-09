-- HU-36 (Sprint 5) Ficha "Programar Servicio": datos heredados de la OS/OM (OS, expediente, propuesta origen, cliente, sede,
-- ubicación, tipo de servicio), equipos a intervenir, requisitos SSOMA del cliente/zona y conceptos del servicio. Solo lectura.
-- Acceso: prog_gestionar (módulo operaciones).
-- Resultados: 1 mensaje, 2 orden (datos heredados, y si se puede programar o por qué no), 3 equipos de la OS,
--   4 requisitos SSOMA del cliente / sede / tipo de servicio con el documento del técnico que lo acredita
--     (se verifican contra cada técnico en SP_BuscarTecnicosProgramacion y SP_CrearProgramacion),
--   5 conceptos del servicio (os_concepto).
DROP PROCEDURE IF EXISTS SP_PrepararProgramacion;

DELIMITER $$

CREATE PROCEDURE SP_PrepararProgramacion(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT
)
proc: BEGIN
    DECLARE v_id_cliente BIGINT DEFAULT NULL;
    DECLARE v_id_sede    BIGINT DEFAULT NULL;
    DECLARE v_tipo_serv  INT    DEFAULT NULL;

    IF FN_PermisoAccion(p_id_usuario, 'prog_gestionar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para programar servicios.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM orden_servicio WHERE id_os = p_id_os AND eliminado_en IS NULL) THEN
        SELECT 1 AS IdTipoMensaje, 'La orden de servicio no existe.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT id_cliente, id_sede, id_tipo_servicio INTO v_id_cliente, v_id_sede, v_tipo_serv
    FROM orden_servicio
    WHERE id_os = p_id_os AND eliminado_en IS NULL;

    -- 1. Header
    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Datos heredados de la orden
    SELECT os.id_os, os.numero, os.tipo, os.estado,
           os.id_expediente, e.numero                                   AS numero_expediente,
           os.id_cliente, c.razon_social, c.ruc,
           os.id_sede, sc.nombre                                        AS sede, sc.direccion_exacta AS ubicacion,
           COALESCE(os.id_propuesta, e.id_propuesta)                    AS id_propuesta,
           p.numero                                                     AS numero_propuesta,
           p.version                                                    AS version_propuesta,
           os.id_tipo_servicio, ts.String1                              AS tipo_servicio,
           r.numero                                                     AS numero_requerimiento,
           r.id_area, ar.String1                                        AS area,
           os.fecha_programada_desde, os.fecha_programada_hasta,
           (SELECT COUNT(*) FROM os_equipo oe WHERE oe.id_os = os.id_os AND oe.eliminado_en IS NULL)   AS n_equipos,
           (SELECT COUNT(*) FROM os_concepto oc WHERE oc.id_os = os.id_os AND oc.eliminado_en IS NULL) AS n_conceptos,
           pr.id_programacion                                           AS id_programacion_activa,
           pr.codigo                                                    AS codigo_programacion_activa,
           IF(os.estado = 'emitida' AND pr.id_programacion IS NULL, 1, 0) AS puede_programar,
           CASE WHEN os.estado <> 'emitida'
                    THEN CONCAT('La orden está ', os.estado, ': solo se programa una orden emitida.')
                WHEN pr.id_programacion IS NOT NULL
                    THEN CONCAT('La orden ya tiene la programación activa ', pr.codigo, '.')
           END                                                          AS motivo_no_programable
    FROM orden_servicio os
    LEFT JOIN cliente c             ON c.id_cliente = os.id_cliente
    LEFT JOIN sede_cliente sc       ON sc.id_sede = os.id_sede
    LEFT JOIN expediente_digital e  ON e.id_expediente = os.id_expediente
    LEFT JOIN propuesta_comercial p ON p.id_propuesta = COALESCE(os.id_propuesta, e.id_propuesta)
    LEFT JOIN requerimiento r       ON r.id_requerimiento = COALESCE(os.id_requerimiento, p.id_requerimiento, e.id_requerimiento)
    LEFT JOIN tabla_maestra ar      ON ar.IdMaestro = 64 AND ar.IdEmpresa = 1 AND ar.Num1 = r.id_area
    LEFT JOIN tabla_maestra ts      ON ts.IdMaestro = 3  AND ts.IdEmpresa = 1 AND ts.Num1 = os.id_tipo_servicio
    LEFT JOIN programacion pr       ON pr.id_programacion = (SELECT MAX(x.id_programacion) FROM programacion x
                                                             WHERE x.id_os = os.id_os AND x.estado <> 'cancelada' AND x.eliminado_en IS NULL)
    WHERE os.id_os = p_id_os;

    -- 3. Equipos a intervenir (heredados de la OS)
    SELECT oe.id AS id_os_equipo, ec.id_equipo, ec.codigo_tw, ec.marca, ec.modelo, ec.num_serie,
           ec.ubicacion_especifica, ec.alcance_maximo,
           IFNULL(oe.orden, oe.id) AS orden
    FROM os_equipo oe
    JOIN equipo_cliente ec ON ec.id_equipo = oe.id_equipo
    WHERE oe.id_os = p_id_os AND oe.eliminado_en IS NULL
    ORDER BY IFNULL(oe.orden, oe.id);

    -- 4. Requisitos SSOMA del cliente / sede / tipo de servicio y documento del técnico que los acredita
    SELECT rq.id,
           rq.id_requisito,
           IFNULL(tm.String1, CONCAT('Requisito ', rq.id_requisito)) AS requisito,
           rq.es_obligatorio, rq.bloquea_servicio, scr.nombre AS sede,
           IFNULL(tm.String3, 'ambos')                               AS aplica_a,
           d36.String1                                               AS documento_equivalente
    FROM requisito_ssoma_cliente rq
    LEFT JOIN tabla_maestra tm   ON tm.IdMaestro = 48 AND tm.IdEmpresa = 1 AND tm.Num1 = rq.id_requisito
    LEFT JOIN sede_cliente scr   ON scr.id_sede = rq.id_sede
    LEFT JOIN ssoma_requisito_documento m ON m.id_requisito = rq.id_requisito AND m.eliminado_en IS NULL
    LEFT JOIN tabla_maestra d36  ON d36.IdMaestro = 36 AND d36.IdEmpresa = 1 AND d36.Num1 = m.id_tipo_documento
    WHERE rq.eliminado_en IS NULL
      AND (rq.id_cliente IS NULL OR rq.id_cliente = v_id_cliente)
      AND (rq.id_sede    IS NULL OR rq.id_sede    = v_id_sede)
      AND (rq.id_tipo_servicio IS NULL OR rq.id_tipo_servicio = v_tipo_serv)
    ORDER BY rq.es_obligatorio DESC, requisito;

    -- 5. Conceptos del servicio (heredados de la OS)
    SELECT oc.id AS id_os_concepto, oc.codigo, oc.descripcion, oc.alcance, oc.orden
    FROM os_concepto oc
    WHERE oc.id_os = p_id_os AND oc.eliminado_en IS NULL
    ORDER BY oc.orden, oc.id;
END$$

DELIMITER ;
