-- HU-30 Tab ⚙️ OS de la ficha del expediente (carga perezosa, solo lectura). Acción expediente_bandeja.
-- Datos de la OS vinculada al expediente (el módulo de OS la genera; "Ir al módulo OS" para editar).
-- p_id_os = OS elegida (por defecto la primera no anulada). Si aún no hay OS, devuelve las listas vacías.
-- Resultados: 1 mensaje · 2 OS del expediente (pills) · 3 datos de la OS (cronograma, sede, técnico principal,
--   responsable comercial, estado, confirmación del cliente, costo estimado) · 4 personal técnico asignado
--   · 5 equipos a intervenir · 6 viáticos y gastos · 7 órdenes de metrología del expediente
-- Observaciones 31/10 (los datos de la OS no se mostraban bien): la OS/OM del módulo comercial (Sprint 4) no usa
--   fecha/hora de ejecución ni técnico hasta que Operaciones la programa. Se agregan sus datos: tipo OS/OM, estado
--   legible, emisión, rango tentativo, propuesta/RQ, cliente y contacto, observaciones, certificado (tercerizado),
--   anulación y conteos; sede y tipo de servicio caen a los de la propuesta. Equipos con su avance y
--   resultado 8 = conceptos de la OS.
--   Feedback cliente 04/11: + id_requerimiento; conceptos con cantidad, frecuencia y precio del ítem de la propuesta;
--   resultado 9 = programaciones de la OS (visita = fecha + técnico principal, sin las canceladas) y
--   resultado 10 = equipos de cada programación.
DROP PROCEDURE IF EXISTS SP_ObtenerOrdenServicioExpediente;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerOrdenServicioExpediente(
    IN p_id_usuario    BIGINT,
    IN p_id_expediente BIGINT,
    IN p_id_os         BIGINT
)
proc: BEGIN
    DECLARE v_id_os   BIGINT;
    DECLARE v_id_prop BIGINT;
    DECLARE v_simbolo VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    IF FN_PermisoAccion(p_id_usuario, 'expediente_bandeja') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver los expedientes digitales.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM expediente_digital WHERE id_expediente = p_id_expediente AND eliminado_en IS NULL) THEN
        SELECT 1 AS IdTipoMensaje, 'El expediente no existe.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF IFNULL(p_id_os, 0) > 0 THEN
        SELECT id_os INTO v_id_os FROM orden_servicio
        WHERE id_os = p_id_os AND id_expediente = p_id_expediente AND eliminado_en IS NULL;
        IF v_id_os IS NULL THEN
            SELECT 1 AS IdTipoMensaje, 'La orden de servicio no pertenece a este expediente.' AS Mensaje;
            LEAVE proc;
        END IF;
    ELSE
        SELECT id_os INTO v_id_os FROM orden_servicio
        WHERE id_expediente = p_id_expediente AND eliminado_en IS NULL
        ORDER BY (estado = 'anulada'), id_os LIMIT 1;
    END IF;

    SELECT COALESCE(os.id_propuesta, e.id_propuesta) INTO v_id_prop
    FROM orden_servicio os LEFT JOIN expediente_digital e ON e.id_expediente = os.id_expediente
    WHERE os.id_os = v_id_os;
    SELECT m.String2 INTO v_simbolo
    FROM propuesta_comercial p JOIN tabla_maestra m ON m.IdMaestro = 1 AND m.IdEmpresa = 1 AND m.Num1 = p.id_moneda
    WHERE p.id_propuesta = v_id_prop LIMIT 1;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. OS (pills)
    SELECT os.id_os, os.numero, os.estado, os.fecha_ejecucion, (os.id_os = v_id_os) AS seleccionada,
           os.tipo, os.fecha_programada_desde, os.fecha_programada_hasta
    FROM orden_servicio os WHERE os.id_expediente = p_id_expediente AND os.eliminado_en IS NULL ORDER BY os.id_os;

    -- 3. Datos de la OS
    SELECT os.id_os, os.numero, os.estado, os.fecha_creacion, os.fecha_ejecucion, os.hora_inicio, os.hora_fin_estimada,
           os.hora_llegada_real, os.hora_fin_real, os.costo_total_estimado,
           COALESCE(ts.String1, p.tipo_servicio) AS tipo_servicio, s.nombre AS sede,
           COALESCE(NULLIF(s.direccion_exacta, ''), NULLIF(c.direccion_fiscal, ''), c.domicilio_fiscal) AS sede_direccion,
           os.id_tecnico_principal, CONCAT(ut.nombre, ' ', ut.apellido) AS tecnico_principal,
           os.id_responsable_comercial, CONCAT(uc.nombre, ' ', uc.apellido) AS responsable_comercial,
           os.confirmacion_cliente, os.fecha_confirmacion_cliente, cn.String1 AS canal_confirmacion,
           ct.nombres AS contacto_confirma, os.notas_operativas,
           os.creado_por AS id_generado_por, CONCAT(ug.nombre, ' ', ug.apellido) AS generado_por,
           -- Datos de la OS/OM comercial (Sprint 4)
           os.tipo,
           CASE os.estado WHEN 'borrador' THEN 'Borrador' WHEN 'emitida' THEN 'Emitida' WHEN 'programada' THEN 'Programada'
                          WHEN 'reprogramada' THEN 'Reprogramada' WHEN 'en_ruta' THEN 'En ruta' WHEN 'en_ejecucion' THEN 'En ejecución'
                          WHEN 'pausada' THEN 'Pausada' WHEN 'bloqueada' THEN 'Bloqueada' WHEN 'finalizada' THEN 'Finalizada'
                          WHEN 'anulada' THEN 'Anulada' ELSE os.estado END AS estado_label,
           os.fecha_emision, CONCAT(ue.nombre, ' ', ue.apellido) AS emitido_por,
           os.fecha_programada_desde, os.fecha_programada_hasta,
           p.id_propuesta, p.numero AS numero_propuesta, p.version AS version_propuesta, p.codigo_formateado AS codigo_formateado_propuesta,
           r.id_requerimiento, r.numero AS numero_rq,
           c.razon_social, c.ruc,
           co.nombres AS contacto, co.cargo AS cargo_contacto, co.telefono_movil AS telefono_contacto, co.correo AS correo_contacto,
           os.observaciones,
           IFNULL(os.es_tercerizado, 0) AS es_tercerizado, os.cert_razon_social, os.cert_ruc, os.cert_direccion, os.cert_contacto,
           ma.String1 AS motivo_anulacion, os.comentario_anulacion, os.anulado_en, CONCAT(uan.nombre, ' ', uan.apellido) AS anulado_por,
           (SELECT COUNT(*) FROM os_equipo x WHERE x.id_os = os.id_os AND x.eliminado_en IS NULL)   AS n_equipos,
           (SELECT COUNT(*) FROM os_concepto x WHERE x.id_os = os.id_os AND x.eliminado_en IS NULL) AS n_conceptos
    FROM orden_servicio os
    LEFT JOIN expediente_digital e  ON e.id_expediente = os.id_expediente
    LEFT JOIN propuesta_comercial p ON p.id_propuesta = COALESCE(os.id_propuesta, e.id_propuesta)
    LEFT JOIN requerimiento r       ON r.id_requerimiento = COALESCE(os.id_requerimiento, p.id_requerimiento, e.id_requerimiento)
    LEFT JOIN cliente c             ON c.id_cliente = COALESCE(os.id_cliente, p.id_cliente)
    LEFT JOIN contacto_cliente co   ON co.id_contacto = COALESCE(os.id_contacto, p.id_contacto)
    LEFT JOIN usuario ue            ON ue.id_usuario = os.emitido_por
    LEFT JOIN usuario uan           ON uan.id_usuario = os.anulado_por
    LEFT JOIN tabla_maestra ma      ON ma.Descripcion = 'MOTIVO_ANULACION_OS' AND ma.Num1 = os.id_motivo_anulacion
    LEFT JOIN tabla_maestra ts ON ts.IdMaestro = 3 AND ts.IdEmpresa = 1 AND ts.Num1 = os.id_tipo_servicio
    LEFT JOIN sede_cliente s   ON s.id_sede = COALESCE(os.id_sede, p.id_sede)
    LEFT JOIN usuario ut       ON ut.id_usuario = os.id_tecnico_principal
    LEFT JOIN usuario uc       ON uc.id_usuario = os.id_responsable_comercial
    LEFT JOIN usuario ug       ON ug.id_usuario = os.creado_por
    LEFT JOIN tabla_maestra cn ON cn.IdMaestro = 26 AND cn.IdEmpresa = 1 AND cn.Num1 = os.id_canal_confirmacion
    LEFT JOIN contacto_cliente ct ON ct.id_contacto = os.id_contacto_confirma
    WHERE os.id_os = v_id_os;

    -- 4. Personal técnico asignado
    SELECT p.id_usuario, CONCAT(u.nombre, ' ', u.apellido) AS nombre, u.cargo, p.rol_en_servicio, p.estado_ssoma
    FROM os_personal p LEFT JOIN usuario u ON u.id_usuario = p.id_usuario
    WHERE p.id_os = v_id_os AND p.eliminado_en IS NULL ORDER BY p.id;

    -- 5. Equipos a intervenir
    SELECT oe.id_equipo, COALESCE(ec.codigo_tw, e.codigo_tw) AS codigo_tw, ec.codigo_cliente,
           COALESCE(ec.marca, NULL) AS marca, COALESCE(ec.modelo, e.modelo) AS modelo,
           COALESCE(ec.num_serie, e.numero_serie) AS numero_serie, COALESCE(ec.ubicacion_especifica, e.ubicacion) AS ubicacion,
           ti.String1 AS tipo_intervencion, oe.ingresado_en_campo,
           COALESCE(tc.String1, ec.clasificacion) AS clasificacion, oe.estado_ejecucion, oe.fecha_ejecucion
    FROM os_equipo oe
    LEFT JOIN equipo_cliente ec ON ec.id_equipo = oe.id_equipo
    LEFT JOIN equipo e          ON e.id_equipo = oe.id_equipo
    LEFT JOIN tabla_maestra ti  ON ti.IdMaestro = 31 AND ti.IdEmpresa = 1 AND ti.Num1 = oe.id_tipo_intervencion
    LEFT JOIN tabla_maestra tc  ON tc.IdMaestro = 71 AND tc.IdEmpresa = 1 AND tc.String2 = ec.clasificacion
    WHERE oe.id_os = v_id_os AND oe.eliminado_en IS NULL ORDER BY IFNULL(oe.orden, oe.id), oe.id;

    -- 6. Viáticos y gastos
    SELECT g.id_gasto, g.tipo, cg.String1 AS concepto, g.monto, m.String2 AS simbolo_moneda, g.descripcion, g.estado,
           g.fecha_solicitud, CONCAT(u.nombre, ' ', u.apellido) AS usuario
    FROM gasto_viatico g
    LEFT JOIN tabla_maestra cg ON cg.IdMaestro = 25 AND cg.IdEmpresa = 1 AND cg.Num1 = g.id_concepto
    LEFT JOIN tabla_maestra m  ON m.IdMaestro = 1 AND m.IdEmpresa = 1 AND m.Num1 = g.id_moneda
    LEFT JOIN usuario u        ON u.id_usuario = g.id_usuario
    WHERE g.id_os = v_id_os AND g.eliminado_en IS NULL ORDER BY g.fecha_solicitud, g.id_gasto;

    -- 7. Órdenes de metrología del expediente
    SELECT om.id_om, om.numero, om.estado, om.fecha_calibracion, om.numero_certificado, om.fecha_emision_certificado,
           CONCAT(u.nombre, ' ', u.apellido) AS metrologo
    FROM orden_metrologia om LEFT JOIN usuario u ON u.id_usuario = om.id_metrologo
    WHERE om.id_expediente = p_id_expediente AND om.eliminado_en IS NULL ORDER BY om.id_om;

    -- 8. Conceptos de la OS (módulo comercial)
    SELECT oc.id AS id_os_concepto, oc.orden, oc.codigo, oc.descripcion, oc.alcance,
           (SELECT GROUP_CONCAT(ec.codigo_tw ORDER BY IFNULL(oe.orden, oe.id) SEPARATOR ', ')
            FROM os_concepto_equipo ce
            JOIN os_equipo oe ON oe.id = ce.id_os_equipo AND oe.eliminado_en IS NULL
            JOIN equipo_cliente ec ON ec.id_equipo = oe.id_equipo
            WHERE ce.id_os_concepto = oc.id AND ce.eliminado_en IS NULL) AS equipos_aplicados,
           pi.id_item, pi.cantidad, pi.frecuencia, pi.precio_unitario, pi.subtotal, v_simbolo AS simbolo_moneda
    FROM os_concepto oc
    -- Ítem de la propuesta que originó el concepto (mismo suministro y alcance)
    LEFT JOIN propuesta_item pi ON pi.id_item = (
              SELECT MIN(i.id_item) FROM propuesta_item i
              WHERE i.id_propuesta = v_id_prop AND i.id_catalogo_item = oc.id_suministro
                AND i.eliminado_en IS NULL AND IFNULL(i.es_espaciado, 0) = 0
                AND IFNULL(NULLIF(TRIM(i.alcance), ''), '') = IFNULL(NULLIF(TRIM(oc.alcance), ''), ''))
    WHERE oc.id_os = v_id_os AND oc.eliminado_en IS NULL
    ORDER BY oc.orden, oc.id;

    -- 9. Programaciones de la OS (Módulo 8): una visita = fecha + técnico principal (+ apoyo)
    SELECT pg.id_programacion, pg.codigo, pg.fecha_ejecucion,
           TIME_FORMAT(pg.hora_inicio, '%H:%i') AS hora_inicio, TIME_FORMAT(pg.hora_fin_estimada, '%H:%i') AS hora_fin,
           pg.estado,
           CASE pg.estado WHEN 'pendiente_confirmacion' THEN 'Pendiente confirmación cliente'
                          WHEN 'confirmada' THEN 'Programado' ELSE pg.estado END AS estado_label,
           pg.id_tecnico_principal AS id_tecnico, CONCAT(ut.nombre, ' ', ut.apellido) AS tecnico,
           (SELECT GROUP_CONCAT(CONCAT(ua.nombre, ' ', ua.apellido) ORDER BY ua.nombre SEPARATOR ', ')
            FROM programacion_tecnico pt JOIN usuario ua ON ua.id_usuario = pt.id_usuario
            WHERE pt.id_programacion = pg.id_programacion AND pt.eliminado_en IS NULL AND pt.rol = 'apoyo') AS tecnicos_apoyo
    FROM programacion pg
    LEFT JOIN usuario ut ON ut.id_usuario = pg.id_tecnico_principal
    WHERE pg.id_os = v_id_os AND pg.eliminado_en IS NULL AND pg.estado <> 'cancelada'
    ORDER BY pg.fecha_ejecucion, pg.hora_inicio, pg.id_programacion;

    -- 10. Equipos de cada programación
    SELECT pe.id_programacion, ec.id_equipo, ec.codigo_tw, ec.marca, ec.modelo, ec.num_serie AS numero_serie
    FROM programacion pg
    JOIN programacion_equipo pe ON pe.id_programacion = pg.id_programacion AND pe.eliminado_en IS NULL
    JOIN equipo_cliente ec      ON ec.id_equipo = pe.id_equipo
    WHERE pg.id_os = v_id_os AND pg.eliminado_en IS NULL AND pg.estado <> 'cancelada'
    ORDER BY pe.id_programacion, pe.id;
END$$

DELIMITER ;
