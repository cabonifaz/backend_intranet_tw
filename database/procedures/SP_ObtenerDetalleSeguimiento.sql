-- HU-18 Vista Detalle del Seguimiento de una propuesta.
-- Usa SP_CalcularSeguimientoComercial (mismo cálculo que la bandeja HU-17), así el estado,
-- la próxima acción y el SLA coinciden con lo que se ve en la bandeja.
-- Solo propuestas en seguimiento (enviadas al cliente o aceptadas con OC) y del área del usuario
-- (o todas con la acción propuesta_seguimiento_todas).
-- Resultados:
--   1 mensaje
--   2 cabecera: panel superior (monto, días, SLA restante), datos de la oportunidad,
--     próxima acción con prioridad y asignado, y permisos de los botones
--   3 timeline: creación y versiones, visto bueno, envío al cliente, seguimientos y OC
--     (de todas las versiones de la propuesta), del más reciente al más antiguo
--   4 próximas acciones programadas (pendiente, realizada o cancelada)
--   5 contactos del cliente (primero el de la propuesta)
--   6 documentos: PDF de cada versión, órdenes de compra y adjuntos de los seguimientos (HU-19)
DROP PROCEDURE IF EXISTS SP_ObtenerDetalleSeguimiento;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerDetalleSeguimiento(
    IN p_id_usuario   BIGINT,
    IN p_id_propuesta BIGINT
)
BEGIN
    DECLARE v_dias_sin_resp  INT DEFAULT 7;
    DECLARE v_meta           INT DEFAULT 8;
    DECLARE v_sla_horas      INT DEFAULT 48;
    DECLARE v_alerta_horas   INT DEFAULT 24;
    DECLARE v_existe         INT DEFAULT 0;
    DECLARE v_abierta        INT DEFAULT 0;
    DECLARE v_id_cliente     BIGINT;
    DECLARE v_id_contacto    BIGINT;
    DECLARE v_numero         VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_registrar      TINYINT DEFAULT 0;
    DECLARE v_cerrar         TINYINT DEFAULT 0;

    CALL SP_CalcularSeguimientoComercial(p_id_usuario, p_id_propuesta,
                                         v_dias_sin_resp, v_meta, v_sla_horas, v_alerta_horas);

    SELECT COUNT(*), MAX(id_cliente), MAX(id_contacto),
           IFNULL(SUM(estado_seguimiento IN ('en_seguimiento', 'sin_respuesta', 'requiere_ajuste')), 0)
      INTO v_existe, v_id_cliente, v_id_contacto, v_abierta
    FROM tmp_seg;

    IF v_existe = 0 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_seg;
        IF NOT EXISTS (SELECT 1 FROM propuesta_comercial
                       WHERE id_propuesta = p_id_propuesta AND eliminado_en IS NULL) THEN
            SELECT 1 AS IdTipoMensaje, 'La propuesta no existe.' AS Mensaje;
        ELSE
            SELECT 1 AS IdTipoMensaje,
                   'La propuesta no está en seguimiento comercial (debe ser la versión vigente y estar enviada al cliente) o no pertenece a tu área.' AS Mensaje;
        END IF;
    ELSE
        SELECT numero INTO v_numero FROM propuesta_comercial WHERE id_propuesta = p_id_propuesta;
        SET v_registrar = FN_PermisoAccion(p_id_usuario, 'propuesta_seguimiento_registrar');
        SET v_cerrar    = FN_PermisoAccion(p_id_usuario, 'propuesta_seguimiento_cerrar');

        -- 1. Header
        SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

        -- 2. Cabecera
        SELECT
            t.id_propuesta, t.numero, t.version,
            t.id_requerimiento, r.numero                      AS numero_rq,
            t.id_cliente, c.razon_social, c.ruc,
            t.id_contacto, co.nombres                         AS contacto, co.cargo AS cargo_contacto,
            co.telefono_movil                                 AS telefono_contacto, co.correo AS correo_contacto,
            t.total, t.id_moneda, m.String3                   AS moneda, m.String2 AS moneda_simbolo,
            t.fecha_envio, t.dias_transcurridos, t.dias_sin_respuesta,
            t.id_responsable, CONCAT(u.nombre, ' ', u.apellido) AS responsable,
            t.interacciones, t.fecha_ult_interaccion,
            t.resultado_ult_codigo, t.resultado_ult,
            t.proxima_accion_codigo, t.proxima_accion, t.proxima_accion_detalle,
            t.vence_accion                                    AS proxima_accion_fecha,
            IF(t.vence_accion IS NULL, NULL, DATEDIFF(DATE(t.vence_accion), CURDATE()))   AS dias_para_accion,
            IF(t.vence_accion IS NULL, NULL, TIMESTAMPDIFF(HOUR, NOW(), t.vence_accion))   AS horas_para_accion,
            IF(t.vence_accion IS NULL, NULL, TIMESTAMPDIFF(MINUTE, NOW(), t.vence_accion)) AS minutos_para_accion,
            t.id_prioridad_accion, pr.String1                 AS prioridad_accion, pr.String3 AS prioridad_accion_codigo,
            COALESCE(IF(t.estado_ult_seg = 'activo', s.id_responsable, NULL), t.id_responsable) AS id_asignado,
            (SELECT CONCAT(ua.nombre, ' ', ua.apellido) FROM usuario ua
             WHERE ua.id_usuario = COALESCE(IF(t.estado_ult_seg = 'activo', s.id_responsable, NULL), t.id_responsable)) AS asignado,
            t.estado_seguimiento, t.estado_propuesta,
            t.sla_estado,
            CASE
                WHEN t.sla_estado = 'cumplido' THEN 100
                WHEN t.sla_estado = 'cerrado'  THEN NULL
                WHEN t.vence_accion IS NULL    THEN 0
                WHEN t.vence_accion <= t.inicio_sla OR NOW() >= t.vence_accion THEN 100
                ELSE LEAST(100, GREATEST(0, ROUND(TIMESTAMPDIFF(MINUTE, t.inicio_sla, NOW()) * 100
                                                  / TIMESTAMPDIFF(MINUTE, t.inicio_sla, t.vence_accion))))
            END                                               AS sla_pct,
            v_sla_horas                                       AS sla_horas,
            t.fecha_aceptacion, t.fecha_rechazo,
            (t.fecha_primera_oc IS NOT NULL)                  AS tiene_oc,
            t.oc_por_validar,
            -- Botones (las acciones se registran en sus propias HU)
            (v_abierta > 0 AND v_registrar = 1)               AS puede_registrar_seguimiento,
            (v_abierta > 0 AND v_registrar = 1)               AS puede_ejecutar_accion,
            (v_abierta > 0 AND v_cerrar = 1)                  AS puede_registrar_aceptacion,
            (v_abierta > 0 AND v_cerrar = 1)                  AS puede_registrar_rechazo
        FROM tmp_seg t
        LEFT JOIN seguimiento_comercial s ON s.id_seguimiento   = t.id_ult_seg
        LEFT JOIN requerimiento r         ON r.id_requerimiento = t.id_requerimiento
        LEFT JOIN cliente c               ON c.id_cliente       = t.id_cliente
        LEFT JOIN contacto_cliente co     ON co.id_contacto     = t.id_contacto
        LEFT JOIN usuario u               ON u.id_usuario       = t.id_responsable
        LEFT JOIN tabla_maestra m         ON m.IdMaestro  = 1 AND m.IdEmpresa  = 1 AND m.Num1  = t.id_moneda
        LEFT JOIN tabla_maestra pr        ON pr.IdMaestro = 7 AND pr.IdEmpresa = 1 AND pr.Num1 = t.id_prioridad_accion;

        DROP TEMPORARY TABLE IF EXISTS tmp_seg;

        -- 3. Timeline (todas las versiones de la propuesta)
        SELECT x.* FROM (
            -- Creación de cada versión
            SELECT p.fecha_creacion AS fecha, 'propuesta_creada' AS tipo,
                   IF(p.version = 1, 'Propuesta generada', CONCAT('Nueva versión v', p.version)) AS titulo,
                   IF(p.version = 1, CONCAT('Se creó la propuesta ', p.numero, '.'),
                      IFNULL(p.descripcion_cambios, CONCAT('Se creó la versión ', p.version, ' de la propuesta.'))) AS descripcion,
                   p.version, p.id_creador AS id_usuario, CONCAT(u.nombre, ' ', u.apellido) AS usuario,
                   NULL AS canal_codigo, NULL AS canal, NULL AS resultado_codigo, NULL AS id_seguimiento,
                   NULL AS duracion_minutos, NULL AS asunto, 0 AS adjuntos
            FROM propuesta_comercial p
            LEFT JOIN usuario u ON u.id_usuario = p.id_creador
            WHERE p.numero = v_numero AND p.eliminado_en IS NULL

            UNION ALL
            -- Solicitud de visto bueno
            SELECT vb.fecha_solicitud, 'vb_solicitado', 'Enviada a visto bueno',
                   IFNULL(vb.comentario, 'Se solicitó el visto bueno de la propuesta.'),
                   p.version, vb.creado_por, CONCAT(u.nombre, ' ', u.apellido),
                   NULL, NULL, NULL, NULL, NULL, NULL, 0
            FROM visto_bueno vb
            JOIN propuesta_comercial p ON p.id_propuesta = vb.id_propuesta
            LEFT JOIN usuario u ON u.id_usuario = vb.creado_por
            WHERE p.numero = v_numero AND p.eliminado_en IS NULL AND vb.eliminado_en IS NULL

            UNION ALL
            -- Respuesta del visto bueno
            SELECT vb.fecha_respuesta, CONCAT('vb_', vb.estado),
                   CASE vb.estado
                       WHEN 'aprobado'  THEN 'Visto bueno aprobado'
                       WHEN 'devuelto'  THEN 'Devuelta para corrección'
                       WHEN 'rechazado' THEN 'Visto bueno rechazado'
                       WHEN 'cancelado' THEN 'Visto bueno cancelado'
                       ELSE CONCAT('Visto bueno ', vb.estado)
                   END,
                   vb.comentario_respuesta,
                   p.version, vb.resuelto_por, CONCAT(u.nombre, ' ', u.apellido),
                   NULL, NULL, NULL, NULL, NULL, NULL, 0
            FROM visto_bueno vb
            JOIN propuesta_comercial p ON p.id_propuesta = vb.id_propuesta
            LEFT JOIN usuario u ON u.id_usuario = vb.resuelto_por
            WHERE p.numero = v_numero AND p.eliminado_en IS NULL AND vb.eliminado_en IS NULL
              AND vb.fecha_respuesta IS NOT NULL

            UNION ALL
            -- Envío al cliente
            SELECT p.fecha_envio, 'enviada_cliente', 'Propuesta enviada al cliente',
                   CONCAT('Se envió la versión ', p.version, ' al cliente.'),
                   p.version, COALESCE(p.id_responsable, p.id_creador), CONCAT(u.nombre, ' ', u.apellido),
                   NULL, NULL, NULL, NULL, NULL, NULL, 0
            FROM propuesta_comercial p
            LEFT JOIN usuario u ON u.id_usuario = COALESCE(p.id_responsable, p.id_creador)
            WHERE p.numero = v_numero AND p.eliminado_en IS NULL AND p.fecha_envio IS NOT NULL

            UNION ALL
            -- Interacciones de seguimiento
            SELECT s.fecha_interaccion,
                   CASE s.estado
                       WHEN 'cerrado_aceptacion' THEN 'cierre_aceptacion'
                       WHEN 'cerrado_rechazo'    THEN 'cierre_rechazo'
                       WHEN 'cerrado_sin_venta'  THEN 'cierre_sin_venta'
                       ELSE 'seguimiento'
                   END,
                   CASE s.estado
                       WHEN 'cerrado_aceptacion' THEN 'Propuesta aceptada por el cliente'
                       WHEN 'cerrado_rechazo'    THEN 'Propuesta rechazada por el cliente'
                       WHEN 'cerrado_sin_venta'  THEN 'Seguimiento cerrado sin venta'
                       ELSE IF(cn.String2 = 'CORREO' AND s.asunto IS NOT NULL,
                               CONCAT('Correo: ', s.asunto),
                               CONCAT(IFNULL(cn.String1, 'Seguimiento'),
                                      IF(rs.String1 IS NULL, '', CONCAT(' - ', rs.String1))))
                   END,
                   s.notas,
                   p.version, COALESCE(s.creado_por, s.id_responsable), CONCAT(u.nombre, ' ', u.apellido),
                   cn.String2, cn.String1, rs.String2, s.id_seguimiento,
                   s.duracion_minutos, s.asunto,
                   (SELECT COUNT(*) FROM seguimiento_adjunto a
                    WHERE a.id_seguimiento = s.id_seguimiento AND a.eliminado_en IS NULL)
            FROM seguimiento_comercial s
            JOIN propuesta_comercial p ON p.id_propuesta = s.id_propuesta
            LEFT JOIN tabla_maestra cn ON cn.IdMaestro = 26 AND cn.IdEmpresa = 1 AND cn.Num1 = s.id_canal
            LEFT JOIN tabla_maestra rs ON rs.IdMaestro = 27 AND rs.IdEmpresa = 1 AND rs.Num1 = s.id_resultado
            LEFT JOIN usuario u ON u.id_usuario = COALESCE(s.creado_por, s.id_responsable)
            WHERE p.numero = v_numero AND p.eliminado_en IS NULL AND s.eliminado_en IS NULL

            UNION ALL
            -- Órdenes de compra
            SELECT oc.fecha_registro, 'orden_compra',
                   CONCAT('Orden de compra ', oc.numero_oc, ' registrada'),
                   CONCAT('Estado: ', REPLACE(oc.estado, '_', ' ')),
                   p.version, oc.creado_por, CONCAT(u.nombre, ' ', u.apellido),
                   NULL, NULL, NULL, NULL, NULL, NULL, 0
            FROM orden_compra oc
            JOIN propuesta_comercial p ON p.numero = v_numero AND p.eliminado_en IS NULL
                                      AND (oc.id_propuesta = p.id_propuesta
                                           OR oc.id_oc IN (SELECT op.id_oc FROM oc_propuesta op
                                                           WHERE op.id_propuesta = p.id_propuesta AND op.eliminado_en IS NULL))
            LEFT JOIN usuario u ON u.id_usuario = oc.creado_por
            WHERE oc.eliminado_en IS NULL
        ) x
        WHERE x.fecha IS NOT NULL
        ORDER BY x.fecha DESC, x.id_seguimiento DESC;

        -- 4. Próximas acciones programadas (versión vigente)
        SELECT
            s.id_seguimiento,
            s.proxima_accion_fecha                    AS fecha,
            ta.String2                                AS tipo_codigo,
            IFNULL(ta.String1, 'Seguimiento')         AS tipo,
            s.proxima_accion_detalle                  AS detalle,
            s.id_prioridad_accion,
            pr.String1                                AS prioridad,
            pr.String3                                AS prioridad_codigo,
            s.id_responsable                          AS id_asignado,
            CONCAT(u.nombre, ' ', u.apellido)         AS asignado,
            CASE
                WHEN EXISTS (SELECT 1 FROM seguimiento_comercial s2
                             WHERE s2.id_propuesta = s.id_propuesta AND s2.eliminado_en IS NULL
                               AND (s2.fecha_interaccion > s.fecha_interaccion
                                    OR (s2.fecha_interaccion = s.fecha_interaccion AND s2.id_seguimiento > s.id_seguimiento)))
                    THEN 'realizada'
                WHEN s.estado = 'activo' AND s.proxima_accion_fecha < NOW() THEN 'vencida'
                WHEN s.estado = 'activo' THEN 'pendiente'
                ELSE 'cancelada'
            END                                       AS estado,
            s.fecha_interaccion                       AS programada_en
        FROM seguimiento_comercial s
        LEFT JOIN tabla_maestra ta ON ta.Descripcion = 'TIPO_ACCION_SEGUIMIENTO' AND ta.IdEmpresa = 1
                                  AND ta.Num1 = s.id_tipo_proxima_accion
        LEFT JOIN tabla_maestra pr ON pr.IdMaestro = 7 AND pr.IdEmpresa = 1 AND pr.Num1 = s.id_prioridad_accion
        LEFT JOIN usuario u        ON u.id_usuario = s.id_responsable
        WHERE s.id_propuesta = p_id_propuesta AND s.eliminado_en IS NULL
          AND s.proxima_accion_fecha IS NOT NULL
          -- Una acción que se mantuvo en seguimientos posteriores se muestra una sola vez (la última copia)
          AND NOT EXISTS (SELECT 1 FROM seguimiento_comercial s3
                          WHERE s3.id_propuesta = s.id_propuesta AND s3.eliminado_en IS NULL
                            AND s3.proxima_accion_fecha = s.proxima_accion_fecha
                            AND IFNULL(s3.id_tipo_proxima_accion, 0) = IFNULL(s.id_tipo_proxima_accion, 0)
                            AND (s3.fecha_interaccion > s.fecha_interaccion
                                 OR (s3.fecha_interaccion = s.fecha_interaccion AND s3.id_seguimiento > s.id_seguimiento)))
        ORDER BY s.proxima_accion_fecha DESC, s.id_seguimiento DESC;

        -- 5. Contactos del cliente
        SELECT
            co.id_contacto, co.nombres, co.cargo, co.area, co.correo,
            co.telefono_movil, co.telefono_anexo, co.estado,
            CAST(co.es_contacto_principal AS UNSIGNED)           AS es_contacto_principal,
            CAST(co.autorizado_aprobar_cotizaciones AS UNSIGNED) AS autorizado_aprobar_cotizaciones,
            (co.id_contacto = IFNULL(v_id_contacto, 0))          AS es_contacto_propuesta
        FROM contacto_cliente co
        WHERE co.id_cliente = v_id_cliente AND co.SoftDelete = 0
        ORDER BY (co.id_contacto = IFNULL(v_id_contacto, 0)) DESC,
                 co.es_contacto_principal DESC, co.nombres;

        -- 6. Documentos
        SELECT d.* FROM (
            SELECT 'propuesta_pdf' AS tipo,
                   CONCAT(p.numero, '-V', p.version, '.pdf') AS nombre,
                   COALESCE(p.fecha_envio, p.fecha_creacion) AS fecha,
                   p.version,
                   CONCAT('/api/crm/propuestas/', p.id_propuesta, '/pdf') AS url,
                   p.estado
            FROM propuesta_comercial p
            WHERE p.numero = v_numero AND p.eliminado_en IS NULL

            UNION ALL
            SELECT 'orden_compra', CONCAT('OC ', oc.numero_oc), oc.fecha_registro,
                   p.version, oc.url_archivo_pdf, oc.estado
            FROM orden_compra oc
            JOIN propuesta_comercial p ON p.numero = v_numero AND p.eliminado_en IS NULL
                                      AND (oc.id_propuesta = p.id_propuesta
                                           OR oc.id_oc IN (SELECT op.id_oc FROM oc_propuesta op
                                                           WHERE op.id_propuesta = p.id_propuesta AND op.eliminado_en IS NULL))
            WHERE oc.eliminado_en IS NULL

            UNION ALL
            SELECT 'adjunto_seguimiento', a.nombre_archivo, a.creado_en,
                   p.version, CONCAT('/api/crm/seguimiento/adjuntos/', a.id_adjunto), NULL
            FROM seguimiento_adjunto a
            JOIN seguimiento_comercial s ON s.id_seguimiento = a.id_seguimiento AND s.eliminado_en IS NULL
            JOIN propuesta_comercial p   ON p.id_propuesta   = s.id_propuesta
            WHERE p.numero = v_numero AND p.eliminado_en IS NULL AND a.eliminado_en IS NULL
        ) d
        ORDER BY d.fecha DESC;
    END IF;
END$$

DELIMITER ;
