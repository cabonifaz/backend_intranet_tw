-- ============================================================
-- SP_ObtenerDetalleServicioMovil  (App Mobile HU-04 — Detalle del servicio)
-- Detalle de una OS para el técnico que inició sesión. Solo lectura.
-- Seguridad: si la OS no existe o el técnico no es principal ni integra el personal,
-- responde el MISMO mensaje (no se revela si la OS existe: evita IDOR / enumeración).
-- Resultados:
--   1. Encabezado (IdTipoMensaje, Mensaje)
--   2. Detalle: destino, contacto, documentos (RQ / OS / OM), estado y chips
--   3. Alertas predictivas sin resolver
--   4. Riesgos identificados (os_riesgo + catálogo RIESGO_OPERATIVO)
--   5. Repuestos a llevar (item_presalida tipo REPUESTO)
--   6. Historial: cambios del equipo (equipo_historial) y del servicio (auditoria_evento),
--      cada uno con su valor anterior y actual
--   7. Documentación (adjuntos de la OS y del expediente visibles para todos)
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerDetalleServicioMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerDetalleServicioMovil(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT
)
proc: BEGIN
    DECLARE v_id_expediente BIGINT;
    DECLARE v_id_cliente    BIGINT;
    DECLARE v_id_sede       BIGINT;
    DECLARE v_id_contacto   BIGINT;

    IF NOT EXISTS (SELECT 1 FROM usuario WHERE id_usuario = p_id_usuario AND eliminado_en IS NULL) THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no encontrado.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT os.id_expediente, os.id_cliente, os.id_sede
    INTO   v_id_expediente, v_id_cliente, v_id_sede
    FROM   orden_servicio os
    WHERE  os.id_os = p_id_os
      AND  os.eliminado_en IS NULL
      AND  (os.id_tecnico_principal = p_id_usuario
            OR EXISTS (SELECT 1 FROM os_personal op
                       WHERE op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL));

    IF v_id_cliente IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio no encontrado o no asignado a tu usuario.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Contacto: principal de la sede, si no el principal del cliente, si no cualquiera activo de la sede.
    SELECT c.id_contacto INTO v_id_contacto
    FROM   contacto_cliente c
    LEFT JOIN contacto_sede cs ON cs.id_contacto = c.id_contacto AND cs.id_sede = v_id_sede
    WHERE  c.id_cliente = v_id_cliente AND c.SoftDelete = 0 AND IFNULL(c.estado, 'Activo') = 'Activo'
    ORDER BY (cs.es_principal_sede = 1) DESC,
             (cs.id_sede IS NOT NULL OR c.id_sede = v_id_sede) DESC,
             (c.es_contacto_principal = 1) DESC,
             c.id_contacto
    LIMIT 1;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Detalle
    SELECT os.id_os,
           os.numero                                                        AS numero_os,
           rq.numero                                                        AS numero_rq,
           (SELECT om.numero FROM orden_metrologia om
            WHERE  om.id_os = os.id_os AND om.eliminado_en IS NULL
            ORDER BY om.id_om LIMIT 1)                                      AS numero_om,
           COALESCE(NULLIF(cl.nombre_comercial, ''), cl.razon_social)       AS cliente,
           os.id_tipo_servicio,
           (SELECT t.String1 FROM tabla_maestra t
            WHERE  t.Descripcion = 'TIPO_SERVICIO' AND t.IdEmpresa = 1 AND t.Num1 = os.id_tipo_servicio
            ORDER BY t.IdMaestro DESC LIMIT 1)                              AS tipo_servicio,
           os.fecha_ejecucion,
           TIME_FORMAT(os.hora_inicio, '%H:%i')                             AS hora_inicio,
           os.estado                                                        AS estado_os,
           s.nombre                                                         AS sede,
           NULLIF(CONCAT_WS(', ', NULLIF(s.direccion_exacta, ''), NULLIF(s.distrito, ''), NULLIF(s.provincia, '')), '') AS direccion,
           ct.nombres                                                       AS contacto_nombre,
           ct.cargo                                                         AS contacto_cargo,
           COALESCE(NULLIF(ct.telefono_movil, ''), NULLIF(ct.telefono_anexo, '')) AS contacto_telefono,
           TRIM(CONCAT(IFNULL(tp.nombre, ''), ' ', IFNULL(tp.apellido, '')))  AS responsable,
           os.confirmacion_cliente                                          AS cliente_confirmado,
           COALESCE(
               (SELECT op.estado_ssoma FROM os_personal op
                WHERE  op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL LIMIT 1),
               (SELECT CASE WHEN SUM(op.estado_ssoma = 'bloqueado') > 0 THEN 'bloqueado'
                            WHEN SUM(op.estado_ssoma = 'pendiente') > 0 THEN 'pendiente'
                            WHEN COUNT(*) > 0 THEN 'habilitado' END
                FROM   os_personal op WHERE op.id_os = os.id_os AND op.eliminado_en IS NULL),
               'pendiente')                                                 AS estado_ssoma,
           (SELECT COUNT(*) FROM os_equipo oe WHERE oe.id_os = os.id_os AND oe.eliminado_en IS NULL) AS objetivos_total,
           os.notas_operativas
    FROM   orden_servicio os
    LEFT JOIN cliente            cl ON cl.id_cliente       = os.id_cliente
    LEFT JOIN sede_cliente       s  ON s.id_sede           = os.id_sede
    LEFT JOIN usuario            tp ON tp.id_usuario       = os.id_tecnico_principal
    LEFT JOIN expediente_digital ed ON ed.id_expediente    = os.id_expediente
    LEFT JOIN requerimiento      rq ON rq.id_requerimiento = ed.id_requerimiento
    LEFT JOIN contacto_cliente   ct ON ct.id_contacto      = v_id_contacto
    WHERE  os.id_os = p_id_os;

    -- 3. Alertas predictivas sin resolver
    SELECT ap.id_alerta,
           (SELECT t.String1 FROM tabla_maestra t
            WHERE  t.Descripcion = 'TIPO_ALERTA_PREDICTIVA' AND t.IdEmpresa = 1 AND t.Num1 = ap.id_tipo_alerta
            ORDER BY t.IdMaestro DESC LIMIT 1)                   AS tipo,
           ap.descripcion,
           (SELECT t.String1 FROM tabla_maestra t
            WHERE  t.Descripcion = 'PRIORIDAD' AND t.IdEmpresa = 1 AND t.Num1 = ap.id_prioridad
            ORDER BY t.IdMaestro DESC LIMIT 1)                   AS prioridad,
           NULLIF(CONCAT_WS(' · ', e.codigo_tw, NULLIF(e.modelo, '')), '') AS equipo,
           ap.fecha_generacion
    FROM   alerta_predictiva ap
    LEFT JOIN equipo e ON e.id_equipo = ap.id_equipo
    WHERE  ap.id_os = p_id_os AND ap.resuelta = 0 AND ap.eliminado_en IS NULL
    ORDER BY ap.id_prioridad DESC, ap.fecha_generacion DESC;

    -- 4. Riesgos identificados
    SELECT r.id_riesgo,
           t.String1                                            AS nombre,
           t.String2                                            AS codigo,
           t.String3                                            AS icono,
           r.observacion
    FROM   os_riesgo r
    LEFT JOIN tabla_maestra t ON t.Descripcion = 'RIESGO_OPERATIVO' AND t.IdEmpresa = 1 AND t.Num1 = r.id_riesgo
                             AND t.eliminado_en IS NULL
    WHERE  r.id_os = p_id_os AND r.eliminado_en IS NULL
    ORDER BY r.id;

    -- 5. Repuestos a llevar (asignado = confirmado por programación / almacén)
    SELECT ip.id_item,
           ip.descripcion,
           ip.confirmado                                         AS asignado
    FROM   item_presalida ip
    WHERE  ip.id_os = p_id_os AND ip.id_tipo_item = 1 AND ip.eliminado_en IS NULL
    ORDER BY ip.confirmado, ip.id_item;

    -- 6. Historial: modificación anterior y actual
    SELECT h.fecha, h.origen, h.titulo, h.referencia, h.valor_anterior, h.valor_nuevo, h.detalle, h.usuario
    FROM (
        SELECT eh.registrado_en                                              AS fecha,
               'equipo'                                                      AS origen,
               eh.campo_modificado                                           AS titulo,
               NULLIF(CONCAT_WS(' · ', e.codigo_tw, NULLIF(e.modelo, '')), '') AS referencia,
               eh.valor_anterior,
               eh.valor_nuevo,
               eh.motivo                                                     AS detalle,
               TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))) AS usuario
        FROM   equipo_historial eh
        JOIN   os_equipo oe ON oe.id_equipo = eh.id_equipo AND oe.id_os = p_id_os AND oe.eliminado_en IS NULL
        LEFT JOIN equipo  e ON e.id_equipo  = eh.id_equipo
        LEFT JOIN usuario u ON u.id_usuario = eh.registrado_por
        UNION ALL
        SELECT a.registrado_en,
               'servicio',
               CASE a.accion
                   WHEN 'checklist_salida'               THEN 'Checklist de salida'
                   WHEN 'solicitar_autorizacion_salida'  THEN 'Solicitud de autorización'
                   WHEN 'visto_bueno_salida'             THEN 'Visto bueno de salida del encargado del área'
                   WHEN 'iniciar_traslado'               THEN 'Inicio de traslado'
                   ELSE REPLACE(a.accion, '_', ' ')
               END,
               NULL,
               a.estado_anterior,
               a.estado_nuevo,
               a.descripcion,
               TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, '')))
        FROM   auditoria_evento a
        LEFT JOIN usuario u ON u.id_usuario = a.id_usuario
        WHERE  a.entidad_tipo = 'orden_servicio' AND a.id_entidad = p_id_os
    ) h
    ORDER BY h.fecha DESC
    LIMIT 20;

    -- 7. Documentación (visibilidad 1 = interno y 5 = cliente: las ven todos)
    SELECT d.id_documento,
           d.nombre_archivo,
           (SELECT t.String1 FROM tabla_maestra t
            WHERE  t.IdMaestro = 96 AND t.IdEmpresa = 1 AND t.Num1 = d.id_tipo_documento LIMIT 1) AS tipo,
           d.version,
           d.fecha_carga
    FROM   documento_adjunto d
    WHERE  d.eliminado_en IS NULL
      AND  ((d.entidad_tipo = 'orden_servicio' AND d.id_entidad = p_id_os)
            OR (d.entidad_tipo = 'expediente' AND d.id_entidad = v_id_expediente AND d.id_visibilidad IN (1, 5)))
    ORDER BY d.fecha_carga DESC
    LIMIT 30;
END$$

DELIMITER ;
