-- HU-42 (Sprint 4) Tabs del Modal de Detalle de OS/OM (carga perezosa: cada tab se pide al seleccionarlo).
-- p_tab:
--   propuesta     2: los 10 campos de contexto de la propuesta aceptada
--   equipos       2: equipos/instrumentos con los conceptos que les aplican (columnas condicionales por clasificación)
--   conceptos     2: conceptos con los equipos a los que aplican (sin equipos = "General")
--   observaciones 2: texto libre para el técnico/metrólogo
--   programacion  2: programación del Módulo 8 (técnico, fecha y hora, estado, viáticos)  3: personal asignado
--   certificado   2: datos para la emisión del certificado (solo OM)
-- Acceso: os_bandeja u os_bandeja_operaciones (Operaciones no ve borradores).
DROP PROCEDURE IF EXISTS SP_ObtenerTabOrdenServicio;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerTabOrdenServicio(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT,
    IN p_tab        VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_comercial TINYINT;
    DECLARE v_estado    VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tipo      CHAR(2);
    DECLARE v_id_prop   BIGINT;

    SET v_comercial = FN_PermisoAccion(p_id_usuario, 'os_bandeja');
    SET p_tab = LOWER(TRIM(IFNULL(p_tab, '')));
    SELECT os.estado, os.tipo, COALESCE(os.id_propuesta, e.id_propuesta) INTO v_estado, v_tipo, v_id_prop
    FROM orden_servicio os LEFT JOIN expediente_digital e ON e.id_expediente = os.id_expediente
    WHERE os.id_os = p_id_os AND os.eliminado_en IS NULL;

    IF v_comercial = 0 AND FN_PermisoAccion(p_id_usuario, 'os_bandeja_operaciones') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver las órdenes de servicio.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_estado IS NULL OR (v_estado = 'borrador' AND v_comercial = 0) THEN
        SELECT 1 AS IdTipoMensaje, 'Orden de servicio no encontrada.' AS Mensaje; LEAVE proc;
    END IF;
    IF p_tab NOT IN ('propuesta', 'equipos', 'conceptos', 'observaciones', 'programacion', 'certificado') THEN
        SELECT 1 AS IdTipoMensaje, 'Tab no válido.' AS Mensaje; LEAVE proc;
    END IF;
    IF p_tab = 'certificado' AND v_tipo <> 'OM' THEN
        SELECT 1 AS IdTipoMensaje, 'Los datos del certificado solo aplican a una Orden de Metrología (OM).' AS Mensaje; LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    IF p_tab = 'propuesta' THEN
        SELECT p.id_propuesta, p.numero, p.version, p.estado,
               COALESCE(NULLIF(TRIM(IF(p.tipo_servicio REGEXP '^[0-9]+$',
                                       (SELECT ts.String1 FROM tabla_maestra ts WHERE ts.IdMaestro = 3 AND ts.IdEmpresa = 1
                                          AND ts.Num1 = CAST(p.tipo_servicio AS UNSIGNED) LIMIT 1), p.tipo_servicio)), ''),
                        (SELECT GROUP_CONCAT(DISTINCT ts.String1 ORDER BY ts.String1 SEPARATOR ', ')
                         FROM propuesta_item i JOIN tabla_maestra ts ON ts.IdMaestro = 3 AND ts.IdEmpresa = 1 AND ts.Num1 = i.id_tipo_servicio
                         WHERE i.id_propuesta = p.id_propuesta AND i.eliminado_en IS NULL)) AS tipo_servicio,
               COALESCE((SELECT MIN(IFNULL(s.fecha_interaccion, s.creado_en)) FROM seguimiento_comercial s
                         WHERE s.id_propuesta = p.id_propuesta AND s.eliminado_en IS NULL AND s.estado = 'cerrado_aceptacion'),
                        (SELECT MIN(ae.registrado_en) FROM auditoria_evento ae
                         WHERE ae.entidad_tipo = 'propuesta' AND ae.id_entidad = p.id_propuesta AND ae.estado_nuevo = 'aceptado'),
                        IF(p.estado = 'aceptado', p.modificado_en, NULL)) AS fecha_aceptacion,
               CONCAT(uc.nombre, ' ', uc.apellido) AS comercial,
               (SELECT CONCAT(ua.nombre, ' ', ua.apellido) FROM visto_bueno v
                JOIN usuario ua ON ua.id_usuario = FN_AprobadorVistoBuenoExpediente(v.id_vb)
                WHERE v.id_propuesta = p.id_propuesta AND v.tipo = 'aprobacion' AND v.estado = 'aprobado' AND v.eliminado_en IS NULL
                ORDER BY v.id_vb DESC LIMIT 1) AS aprobador_vb,
               p.total AS monto_total, m.String2 AS simbolo_moneda,
               (SELECT COUNT(*) FROM propuesta_equipo pe WHERE pe.id_propuesta = p.id_propuesta) AS equipos_cotizados,
               (SELECT COUNT(*) FROM orden_servicio o2 JOIN propuesta_comercial p2 ON p2.id_propuesta = o2.id_propuesta
                WHERE p2.numero = p.numero AND o2.eliminado_en IS NULL AND o2.estado <> 'anulada') AS os_activas,
               (SELECT COUNT(*) FROM propuesta_item i WHERE i.id_propuesta = p.id_propuesta AND i.seccion = 'principal'
                  AND IFNULL(i.es_espaciado, 0) = 0 AND i.eliminado_en IS NULL) AS conceptos_cotizados,
               COALESCE((SELECT cp.String1 FROM tabla_maestra cp WHERE cp.IdMaestro = 39 AND cp.IdEmpresa = 1
                           AND cp.Num1 = p.id_condicion_pago AND cp.eliminado_en IS NULL LIMIT 1),
                        (SELECT GROUP_CONCAT(CONCAT(TRIM(TRAILING '.' FROM TRIM(TRAILING '0' FROM CAST(f.porcentaje AS CHAR))), '% ',
                                                    IFNULL((SELECT MAX(tm.String1) FROM tabla_maestra tm WHERE tm.IdMaestro = 39
                                                              AND tm.IdEmpresa = 1 AND tm.String2 = f.condicion), f.condicion))
                                             ORDER BY f.orden, f.id SEPARATOR ' · ')
                         FROM propuesta_forma_pago f WHERE f.id_propuesta = p.id_propuesta)) AS condicion_pago
        FROM propuesta_comercial p
        LEFT JOIN usuario uc      ON uc.id_usuario = COALESCE(p.id_responsable, p.id_creador)
        LEFT JOIN tabla_maestra m ON m.IdMaestro = 1 AND m.IdEmpresa = 1 AND m.Num1 = p.id_moneda
        WHERE p.id_propuesta = v_id_prop;

    ELSEIF p_tab = 'equipos' THEN
        SELECT oe.id AS id_os_equipo, IFNULL(oe.orden, oe.id) AS orden, ec.id_equipo, ec.codigo_tw, ec.num_serie, ec.codigo_cliente,
               ec.clasificacion, COALESCE(tc.String1, ec.clasificacion) AS clasificacion_label,
               ec.marca, ec.modelo, ec.alcance_maximo, ec.ubicacion_especifica, sc.nombre AS sede,
               ec.division_minima, ec.division_verif, ec.clase_exactitud, ec.escala_graduacion, ec.puntos_calibracion, ec.valor_nominal,
               oe.estado_ejecucion,
               (SELECT GROUP_CONCAT(oc.id_suministro ORDER BY oc.orden SEPARATOR ',')
                FROM os_concepto_equipo ce JOIN os_concepto oc ON oc.id = ce.id_os_concepto AND oc.eliminado_en IS NULL
                WHERE ce.id_os_equipo = oe.id AND ce.eliminado_en IS NULL)                         AS conceptos_ids,
               (SELECT GROUP_CONCAT(CONCAT(oc.descripcion, IFNULL(CONCAT(' (', oc.alcance, ')'), '')) ORDER BY oc.orden SEPARATOR ' | ')
                FROM os_concepto_equipo ce JOIN os_concepto oc ON oc.id = ce.id_os_concepto AND oc.eliminado_en IS NULL
                WHERE ce.id_os_equipo = oe.id AND ce.eliminado_en IS NULL)                         AS conceptos,
               (SELECT GROUP_CONCAT(oc.id ORDER BY oc.orden SEPARATOR ',')
                FROM os_concepto_equipo ce JOIN os_concepto oc ON oc.id = ce.id_os_concepto AND oc.eliminado_en IS NULL
                WHERE ce.id_os_equipo = oe.id AND ce.eliminado_en IS NULL)                         AS conceptos_os,
               EXISTS (SELECT 1 FROM propuesta_equipo pe WHERE pe.id_propuesta = v_id_prop AND pe.id_equipo = ec.id_equipo) AS de_la_propuesta
        FROM os_equipo oe
        JOIN equipo_cliente ec     ON ec.id_equipo = oe.id_equipo
        LEFT JOIN sede_cliente sc  ON sc.id_sede = ec.id_sede
        LEFT JOIN tabla_maestra tc ON tc.IdMaestro = 71 AND tc.IdEmpresa = 1 AND tc.String2 = ec.clasificacion
        WHERE oe.id_os = p_id_os AND oe.eliminado_en IS NULL
        ORDER BY IFNULL(oe.orden, oe.id), oe.id;

    ELSEIF p_tab = 'conceptos' THEN
        SELECT oc.id AS id_os_concepto, oc.orden, oc.id_suministro, oc.codigo, oc.descripcion, oc.alcance,
               EXISTS (SELECT 1 FROM propuesta_item pi WHERE pi.id_propuesta = v_id_prop AND pi.id_catalogo_item = oc.id_suministro
                         AND pi.eliminado_en IS NULL AND IFNULL(pi.es_espaciado, 0) = 0) AS de_la_propuesta,
               (SELECT GROUP_CONCAT(ec.codigo_tw ORDER BY IFNULL(oe.orden, oe.id) SEPARATOR ',')
                FROM os_concepto_equipo ce
                JOIN os_equipo oe ON oe.id = ce.id_os_equipo AND oe.eliminado_en IS NULL
                JOIN equipo_cliente ec ON ec.id_equipo = oe.id_equipo
                WHERE ce.id_os_concepto = oc.id AND ce.eliminado_en IS NULL)                       AS equipos_aplicados
        FROM os_concepto oc
        WHERE oc.id_os = p_id_os AND oc.eliminado_en IS NULL
        ORDER BY oc.orden, oc.id;

    ELSEIF p_tab = 'observaciones' THEN
        SELECT os.observaciones FROM orden_servicio os WHERE os.id_os = p_id_os;

    ELSEIF p_tab = 'programacion' THEN
        SELECT os.estado,
               (os.estado IN ('programada', 'reprogramada', 'en_ruta', 'en_ejecucion', 'pausada', 'bloqueada', 'finalizada')
                OR os.id_tecnico_principal IS NOT NULL OR os.fecha_ejecucion IS NOT NULL)          AS tiene_programacion,
               os.id_tecnico_principal, CONCAT(ut.nombre, ' ', ut.apellido) AS tecnico,
               os.fecha_ejecucion, os.hora_inicio, os.hora_fin_estimada, os.hora_llegada_real, os.hora_fin_real,
               (SELECT b.estado FROM backlog_programacion b WHERE b.id_os = os.id_os AND b.eliminado_en IS NULL
                ORDER BY b.id_backlog DESC LIMIT 1)                                                AS estado_preparacion,
               os.confirmacion_cliente,
               (SELECT SUM(g.monto) FROM gasto_viatico g WHERE g.id_os = os.id_os AND g.eliminado_en IS NULL
                  AND g.tipo = 'viatico_asignado' AND g.estado <> 'rechazado')                     AS viaticos,
               (SELECT MAX(mn.String2) FROM gasto_viatico g JOIN tabla_maestra mn ON mn.IdMaestro = 1 AND mn.IdEmpresa = 1 AND mn.Num1 = g.id_moneda
                WHERE g.id_os = os.id_os AND g.eliminado_en IS NULL)                               AS simbolo_moneda,
               os.notas_operativas
        FROM orden_servicio os
        LEFT JOIN usuario ut ON ut.id_usuario = os.id_tecnico_principal
        WHERE os.id_os = p_id_os;

        SELECT op.id_usuario, CONCAT(u.nombre, ' ', u.apellido) AS nombre, op.rol_en_servicio, op.estado_ssoma
        FROM os_personal op JOIN usuario u ON u.id_usuario = op.id_usuario
        WHERE op.id_os = p_id_os AND op.eliminado_en IS NULL
        ORDER BY op.id;

    ELSE
        SELECT os.es_tercerizado, os.cert_razon_social, os.cert_ruc, os.cert_direccion, os.cert_contacto
        FROM orden_servicio os WHERE os.id_os = p_id_os;
    END IF;
END$$

DELIMITER ;
