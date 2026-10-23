-- HU-30 Tab 📄 RQ de la ficha del expediente (carga perezosa, solo lectura). Acción expediente_bandeja.
-- Resultados: 1 mensaje · 2 datos del requerimiento (código, estado, origen, grado de necesidad, área, descripción,
--   fechas, responsable) con contacto y sede del cliente · 3 archivos adjuntos (clave para ver/descargar en
--   /documentos/{clave}) · 4 timeline del RQ · 5 propuestas generadas desde el RQ (última versión de cada una)
DROP PROCEDURE IF EXISTS SP_ObtenerRqExpediente;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerRqExpediente(
    IN p_id_usuario    BIGINT,
    IN p_id_expediente BIGINT
)
proc: BEGIN
    DECLARE v_id_rq BIGINT;

    IF FN_PermisoAccion(p_id_usuario, 'expediente_bandeja') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver los expedientes digitales.' AS Mensaje;
        LEAVE proc;
    END IF;
    SELECT id_requerimiento INTO v_id_rq FROM expediente_digital WHERE id_expediente = p_id_expediente AND eliminado_en IS NULL;
    IF NOT EXISTS (SELECT 1 FROM expediente_digital WHERE id_expediente = p_id_expediente AND eliminado_en IS NULL) THEN
        SELECT 1 AS IdTipoMensaje, 'El expediente no existe.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_id_rq IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'El expediente no tiene requerimiento vinculado.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Datos del requerimiento, contacto y sede
    SELECT r.id_requerimiento, r.numero, r.estado, er.String1 AS estado_nombre,
           r.id_origen, o.String1 AS origen, r.id_prioridad, pr.String1 AS grado_necesidad,
           r.id_area, ar.String1 AS area_servicio, r.descripcion,
           r.fecha_necesidad AS fecha_requerida, r.fecha_creacion AS fecha_registro, r.fecha_cierre,
           r.requiere_visita, r.es_inacal,
           COALESCE(r.id_responsable, r.id_usuario_creador) AS id_responsable,
           CONCAT(u.nombre, ' ', u.apellido) AS responsable, u.cargo AS cargo_responsable,
           r.id_cliente, c.razon_social, c.ruc,
           r.id_contacto, ct.nombres AS contacto_nombre, ct.cargo AS contacto_cargo, ct.area AS contacto_area,
           ct.correo AS contacto_correo, ct.telefono_movil AS contacto_telefono,
           r.id_sede, s.nombre AS sede_nombre,
           NULLIF(CONCAT_WS(', ', NULLIF(s.distrito, ''), NULLIF(s.provincia, ''), NULLIF(s.region, '')), '') AS sede_ubicacion,
           s.direccion_exacta AS sede_direccion
    FROM requerimiento r
    LEFT JOIN tabla_maestra er ON er.IdMaestro = 67 AND er.IdEmpresa = 1 AND er.String2 = r.estado
    LEFT JOIN tabla_maestra o  ON o.IdMaestro = 63 AND o.IdEmpresa = 1 AND o.Num1 = r.id_origen
    LEFT JOIN tabla_maestra pr ON pr.IdMaestro = 65 AND pr.IdEmpresa = 1 AND pr.Num1 = r.id_prioridad
    LEFT JOIN tabla_maestra ar ON ar.IdMaestro = 64 AND ar.IdEmpresa = 1 AND ar.Num1 = r.id_area
    LEFT JOIN usuario u        ON u.id_usuario = COALESCE(r.id_responsable, r.id_usuario_creador)
    LEFT JOIN cliente c        ON c.id_cliente = r.id_cliente
    LEFT JOIN contacto_cliente ct ON ct.id_contacto = r.id_contacto
    LEFT JOIN sede_cliente s   ON s.id_sede = r.id_sede
    WHERE r.id_requerimiento = v_id_rq;

    -- 3. Archivos adjuntos del RQ
    SELECT CONCAT('doc-', d.id_documento) AS clave, d.nombre_archivo, IFNULL(td.String1, 'Adjunto del requerimiento') AS tipo,
           CAST(NULLIF(JSON_UNQUOTE(JSON_EXTRACT(d.metadatos, '$.tamano_bytes')), 'null') AS SIGNED) AS tamano_bytes,
           d.fecha_carga, d.subido_por AS id_usuario, CONCAT(u.nombre, ' ', u.apellido) AS usuario
    FROM documento_adjunto d
    LEFT JOIN tabla_maestra td ON td.IdMaestro = 96 AND td.IdEmpresa = 1 AND td.Num1 = d.id_tipo_documento
    LEFT JOIN usuario u ON u.id_usuario = d.subido_por
    WHERE d.entidad_tipo = 'requerimiento' AND d.id_entidad = v_id_rq AND d.eliminado_en IS NULL
    ORDER BY d.fecha_carga DESC;

    -- 4. Timeline del RQ
    SELECT h.fecha, h.tipo, h.tipo_label AS titulo, h.descripcion, h.icono, h.creado_por AS id_usuario,
           IFNULL(CONCAT(u.nombre, ' ', u.apellido), h.usuario) AS usuario
    FROM historial_requerimiento h
    LEFT JOIN usuario u ON u.id_usuario = h.creado_por
    WHERE h.id_requerimiento = v_id_rq AND IFNULL(h.SoftDelete, 0) = 0
    ORDER BY h.fecha DESC, h.id_historial DESC;

    -- 5. Propuestas generadas desde el RQ (última versión de cada una)
    SELECT p.id_propuesta, p.numero, p.version, p.estado, p.total, p.id_moneda, m.String2 AS simbolo_moneda,
           COALESCE(p.id_responsable, p.id_creador) AS id_responsable, CONCAT(u.nombre, ' ', u.apellido) AS responsable,
           p.fecha_creacion, COALESCE(p.fecha_envio_cliente, p.fecha_envio) AS fecha_envio,
           (SELECT MIN(IFNULL(s.fecha_interaccion, s.creado_en)) FROM seguimiento_comercial s
            WHERE s.id_propuesta = p.id_propuesta AND s.eliminado_en IS NULL AND s.estado = 'cerrado_aceptacion') AS fecha_aceptacion,
           (SELECT MIN(IFNULL(s.fecha_interaccion, s.creado_en)) FROM seguimiento_comercial s
            WHERE s.id_propuesta = p.id_propuesta AND s.eliminado_en IS NULL AND s.estado = 'cerrado_rechazo')   AS fecha_rechazo,
           (SELECT LEFT(CONCAT_WS(': ', mr.String1, NULLIF(TRIM(IFNULL(s.notas, '')), '')), 500) FROM seguimiento_comercial s
            LEFT JOIN tabla_maestra mr ON mr.IdMaestro = 10 AND mr.IdEmpresa = 1 AND mr.Num1 = s.id_motivo_cierre
            WHERE s.id_propuesta = p.id_propuesta AND s.eliminado_en IS NULL AND s.estado = 'cerrado_rechazo'
            ORDER BY s.id_seguimiento DESC LIMIT 1)                                                             AS motivo_rechazo
    FROM propuesta_comercial p
    LEFT JOIN tabla_maestra m ON m.IdMaestro = 1 AND m.IdEmpresa = 1 AND m.Num1 = p.id_moneda
    LEFT JOIN usuario u       ON u.id_usuario = COALESCE(p.id_responsable, p.id_creador)
    WHERE p.id_requerimiento = v_id_rq AND p.eliminado_en IS NULL
      AND p.version = (SELECT MAX(p2.version) FROM propuesta_comercial p2 WHERE p2.numero = p.numero AND p2.eliminado_en IS NULL)
    ORDER BY p.id_propuesta;
END$$

DELIMITER ;
