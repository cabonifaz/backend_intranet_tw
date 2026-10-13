-- HU-25 "Historial de Expediente Industrial": auditoría completa y trazabilidad de la OC (ISO 9001).
-- Acción oc_bandeja y OC del área del usuario.
-- Todo sale de registros de solo inserción o de fechas de creación que no se editan (timeline inmutable).
-- p_registrar_exportacion = 1 deja constancia de la descarga del reporte (exportar_auditoria_oc).
-- Resultados:
--   1 mensaje
--   2 cabecera: expediente, OC, propuesta, RQ, cliente y fecha de generación
--   3 timeline de eventos críticos (HU-27: distribución de saldo y OC complementaria): RQ, expediente, versiones de la propuesta, visto bueno, envío al
--     cliente, aceptación, registro de la OC, documentos, ediciones, validación u observación y OS
--   4 registro de auditoría (CRM): auditoria_evento de RQ, propuestas, OC y expediente, y accesos al PDF
--   5 aplicaciones relacionadas (propuestas vinculadas a la OC)
--   6 documentación SSOMA de las OS del expediente
--   7 versiones del PDF de la OC
DROP PROCEDURE IF EXISTS SP_ObtenerAuditoriaOrdenCompra;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerAuditoriaOrdenCompra(
    IN p_id_usuario            BIGINT,
    IN p_id_oc                 BIGINT,
    IN p_registrar_exportacion TINYINT
)
proc: BEGIN
    DECLARE v_existe        INT DEFAULT 0;
    DECLARE v_id_prop       BIGINT;
    DECLARE v_numero_prop   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_rq         BIGINT;
    DECLARE v_id_exp        BIGINT;
    DECLARE v_estado_visual VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_max_doc       INT DEFAULT 0;

    IF FN_PermisoAccion(p_id_usuario, 'oc_bandeja') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver las órdenes de compra.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_CalcularOrdenesCompra(p_id_usuario, p_id_oc);
    SELECT COUNT(*), MAX(id_propuesta), MAX(numero_propuesta), MAX(id_requerimiento), MAX(id_expediente), MAX(estado_visual)
      INTO v_existe, v_id_prop, v_numero_prop, v_id_rq, v_id_exp, v_estado_visual
    FROM tmp_oc;
    DROP TEMPORARY TABLE IF EXISTS tmp_oc;

    IF v_existe = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'La orden de compra no existe o no pertenece a tu área.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF IFNULL(p_registrar_exportacion, 0) = 1 THEN
        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, descripcion, id_usuario, registrado_en)
        VALUES ('orden_compra', p_id_oc, 'exportar_auditoria_oc', 'Descarga del historial de auditoría (XLSX).',
                p_id_usuario, NOW());
    END IF;

    SELECT IFNULL(MAX(version), 0) INTO v_max_doc
    FROM documento_adjunto
    WHERE entidad_tipo = 'orden_compra' AND id_entidad = p_id_oc AND eliminado_en IS NULL;

    -- 1. Header
    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Cabecera
    SELECT oc.id_oc, oc.numero_oc, oc.estado, v_estado_visual AS estado_visual,
           e.id_expediente, e.numero AS numero_expediente, e.estado AS estado_expediente, e.etapa_actual AS etapa_expediente,
           p.id_propuesta, p.numero AS numero_propuesta, p.version AS version_propuesta,
           r.id_requerimiento, r.numero AS numero_rq,
           c.id_cliente, c.razon_social, c.ruc,
           NOW() AS generado_en, CONCAT(u.nombre, ' ', u.apellido) AS generado_por
    FROM orden_compra oc
    LEFT JOIN expediente_digital e  ON e.id_expediente    = v_id_exp
    LEFT JOIN propuesta_comercial p ON p.id_propuesta     = v_id_prop
    LEFT JOIN requerimiento r       ON r.id_requerimiento = v_id_rq
    LEFT JOIN cliente c             ON c.id_cliente       = oc.id_cliente
    LEFT JOIN usuario u             ON u.id_usuario       = p_id_usuario
    WHERE oc.id_oc = p_id_oc;

    -- 3. Timeline de eventos críticos
    SELECT t.fecha, t.codigo, t.titulo, t.descripcion, t.nivel, t.referencia, t.url,
           t.id_usuario, CONCAT(u.nombre, ' ', u.apellido) AS usuario, u.area, u.rol_sistema AS rol
    FROM (
        SELECT r.fecha_creacion AS fecha, 'rq_creado' AS codigo, 'Requerimiento registrado' AS titulo,
               LEFT(r.descripcion, 300) AS descripcion, 'neutro' AS nivel, r.numero AS referencia, NULL AS url,
               r.id_usuario_creador AS id_usuario
        FROM requerimiento r WHERE r.id_requerimiento = v_id_rq
        UNION ALL
        SELECT e.fecha_creacion, 'expediente_creado', 'Expediente creado en sistema',
               CONCAT('Expediente ', e.numero, ' (etapa ', REPLACE(e.etapa_actual, '_', ' '), ').'),
               'neutro', e.numero, NULL, e.creado_por
        FROM expediente_digital e WHERE e.id_expediente = v_id_exp
        UNION ALL
        SELECT p.fecha_creacion, 'propuesta_creada',
               IF(p.version = 1, 'Propuesta creada', CONCAT('Nueva versión de la propuesta (v', p.version, ')')),
               CONCAT(p.numero, ' v', p.version, ' por ', FORMAT(p.total, 2), '.'),
               'info', CONCAT(p.numero, ' v', p.version), CONCAT('/api/crm/propuestas/', p.id_propuesta, '/pdf'), p.id_creador
        FROM propuesta_comercial p WHERE p.numero = v_numero_prop AND p.eliminado_en IS NULL
        UNION ALL
        SELECT vb.fecha_solicitud, 'vb_solicitado', 'Visto bueno solicitado',
               CONCAT('Propuesta ', p.numero, ' v', p.version, ' enviada a visto bueno.'),
               'info', CONCAT(p.numero, ' v', p.version), NULL, vb.creado_por
        FROM visto_bueno vb
        JOIN propuesta_comercial p ON p.id_propuesta = vb.id_propuesta
        WHERE p.numero = v_numero_prop AND vb.eliminado_en IS NULL
        UNION ALL
        SELECT vb.fecha_respuesta, CONCAT('vb_', vb.estado),
               CASE vb.estado WHEN 'aprobado' THEN 'Visto bueno aprobado' WHEN 'rechazado' THEN 'Visto bueno rechazado'
                              ELSE 'Visto bueno reasignado' END,
               IFNULL(LEFT(vb.comentario, 300), CONCAT('Propuesta ', p.numero, ' v', p.version, '.')),
               IF(vb.estado = 'aprobado', 'exito', 'alerta'), CONCAT(p.numero, ' v', p.version), NULL, vb.id_aprobador
        FROM visto_bueno vb
        JOIN propuesta_comercial p ON p.id_propuesta = vb.id_propuesta
        WHERE p.numero = v_numero_prop AND vb.eliminado_en IS NULL AND vb.fecha_respuesta IS NOT NULL
        UNION ALL
        SELECT p.fecha_envio_cliente, 'propuesta_enviada', 'Propuesta enviada al cliente',
               CONCAT(p.numero, ' v', p.version, ' enviada al cliente.'),
               'info', CONCAT(p.numero, ' v', p.version), NULL, p.enviado_cliente_por
        FROM propuesta_comercial p
        WHERE p.numero = v_numero_prop AND p.eliminado_en IS NULL AND p.fecha_envio_cliente IS NOT NULL
        UNION ALL
        SELECT s.fecha_interaccion, 'aceptacion_cliente', 'Propuesta aceptada por el cliente',
               IFNULL(LEFT(s.notas, 300), CONCAT(p.numero, ' v', p.version, ' aceptada.')),
               'exito', CONCAT(p.numero, ' v', p.version), NULL, s.id_responsable
        FROM seguimiento_comercial s
        JOIN propuesta_comercial p ON p.id_propuesta = s.id_propuesta
        WHERE p.numero = v_numero_prop AND s.estado = 'cerrado_aceptacion' AND s.eliminado_en IS NULL
        UNION ALL
        SELECT oc.fecha_registro, 'oc_registrada', 'Orden de compra registrada',
               CONCAT('OC ', oc.numero_oc, ' por ', IFNULL(m.String2, ''), ' ', FORMAT(oc.monto_total, 2), '.'),
               'documento', oc.numero_oc, NULL, oc.creado_por
        FROM orden_compra oc
        LEFT JOIN tabla_maestra m ON m.IdMaestro = 1 AND m.IdEmpresa = 1 AND m.Num1 = oc.id_moneda
        WHERE oc.id_oc = p_id_oc
        UNION ALL
        SELECT d.fecha_carga, IF(d.version = 1, 'oc_adjuntada', 'oc_documento_reemplazado'),
               IF(d.version = 1, 'Orden de compra adjuntada', CONCAT('Documento de la OC reemplazado (v', d.version, ')')),
               CONCAT(d.nombre_archivo, ' · ', IFNULL(JSON_UNQUOTE(JSON_EXTRACT(d.metadatos, '$.motivo')), ''),
                      IFNULL(CONCAT(' · ', ROUND(CAST(JSON_UNQUOTE(JSON_EXTRACT(d.metadatos, '$.tamano_bytes')) AS DECIMAL(14,2))
                                                 / 1048576, 2), ' MB'), '')),
               'documento', CONCAT('v', d.version),
               CONCAT('/api/crm/ordenes-compra/', p_id_oc, '/documentos/', d.id_documento), d.subido_por
        FROM documento_adjunto d
        WHERE d.entidad_tipo = 'orden_compra' AND d.id_entidad = p_id_oc AND d.eliminado_en IS NULL
        UNION ALL
        SELECT oc.fecha_registro, 'oc_adjuntada', 'Orden de compra adjuntada',
               COALESCE(oc.nombre_archivo_pdf, CONCAT('OC-', oc.numero_oc, '.pdf')),
               'documento', 'v1', CONCAT('/api/crm/ordenes-compra/', oc.id_oc, '/pdf'), oc.creado_por
        FROM orden_compra oc
        WHERE oc.id_oc = p_id_oc AND oc.url_archivo_pdf IS NOT NULL AND v_max_doc = 0
        UNION ALL
        SELECT a.registrado_en, a.accion,
               CASE a.accion
                   WHEN 'editar_oc'              THEN 'Orden de compra editada'
                   WHEN 'editar_oc_revalidacion' THEN 'OC editada y enviada a revalidación'
                   WHEN 'validar_oc'             THEN 'Orden de compra validada'
                   WHEN 'observar_oc'            THEN 'Orden de compra observada'
                   WHEN 'anular_oc'              THEN 'Orden de compra anulada'
                   WHEN 'distribuir_oc'          THEN 'Saldo de la OC distribuido'
                   WHEN 'liberar_oc'             THEN 'Expediente liberado para programación'
                   WHEN 'registrar_oc_complementaria' THEN 'OC complementaria registrada'
               END,
               a.descripcion,
               CASE WHEN a.accion IN ('validar_oc', 'liberar_oc') THEN 'exito'
                    WHEN a.accion IN ('observar_oc', 'anular_oc', 'editar_oc_revalidacion') THEN 'alerta'
                    ELSE 'info' END,
               NULL, NULL, a.id_usuario
        FROM auditoria_evento a
        WHERE a.entidad_tipo = 'orden_compra' AND a.id_entidad = p_id_oc
          AND a.accion IN ('editar_oc', 'editar_oc_revalidacion', 'validar_oc', 'observar_oc', 'anular_oc',
                           'distribuir_oc', 'registrar_oc_complementaria', 'liberar_oc')
        UNION ALL
        SELECT os.fecha_creacion, 'os_creada', 'Orden de servicio programada',
               CONCAT('OS ', os.numero, ' para el ', DATE_FORMAT(os.fecha_ejecucion, '%d/%m/%Y'), ' (', os.estado, ').'),
               'info', os.numero, NULL, os.creado_por
        FROM orden_servicio os
        WHERE os.id_expediente = v_id_exp AND os.eliminado_en IS NULL
    ) t
    LEFT JOIN usuario u ON u.id_usuario = t.id_usuario
    WHERE t.fecha IS NOT NULL
    ORDER BY t.fecha DESC, t.codigo;

    -- 4. Registro de auditoría (CRM)
    SELECT x.fecha, x.entidad, x.id_entidad, x.referencia, x.accion, x.estado_anterior, x.estado_nuevo, x.descripcion,
           x.id_usuario, CONCAT(u.nombre, ' ', u.apellido) AS usuario
    FROM (
        SELECT a.registrado_en AS fecha, a.entidad_tipo AS entidad, a.id_entidad,
               CASE a.entidad_tipo
                   WHEN 'orden_compra'  THEN (SELECT numero_oc FROM orden_compra WHERE id_oc = a.id_entidad)
                   WHEN 'requerimiento' THEN (SELECT numero FROM requerimiento WHERE id_requerimiento = a.id_entidad)
                   WHEN 'expediente'    THEN (SELECT numero FROM expediente_digital WHERE id_expediente = a.id_entidad)
                   ELSE (SELECT CONCAT(numero, ' v', version) FROM propuesta_comercial WHERE id_propuesta = a.id_entidad)
               END AS referencia,
               a.accion, a.estado_anterior, a.estado_nuevo, a.descripcion, a.id_usuario
        FROM auditoria_evento a
        WHERE (a.entidad_tipo = 'orden_compra'  AND a.id_entidad = p_id_oc)
           OR (a.entidad_tipo = 'requerimiento' AND a.id_entidad = v_id_rq)
           OR (a.entidad_tipo = 'expediente'    AND a.id_entidad = v_id_exp)
           OR (a.entidad_tipo = 'propuesta'     AND a.id_entidad IN (SELECT p.id_propuesta FROM propuesta_comercial p
                                                                     WHERE p.numero = v_numero_prop))
        UNION ALL
        SELECT dd.registrado_en, 'orden_compra', dd.id_entidad, oc.numero_oc, 'acceso_documento', NULL, NULL,
               CONCAT('Visualizó o descargó el PDF (', SUBSTRING_INDEX(dd.url_archivo, '/', -1), ').'), dd.id_usuario
        FROM descarga_documento dd
        JOIN orden_compra oc ON oc.id_oc = dd.id_entidad
        WHERE dd.entidad_tipo = 'orden_compra' AND dd.id_entidad = p_id_oc
    ) x
    LEFT JOIN usuario u ON u.id_usuario = x.id_usuario
    ORDER BY x.fecha DESC;

    -- 5. Aplicaciones relacionadas
    SELECT p.id_propuesta, p.numero, p.version, p.estado, p.total AS monto_propuesta,
           m.String2 AS moneda_simbolo, op.monto_asignado, op.creado_en AS fecha_asignacion,
           CONCAT(u.nombre, ' ', u.apellido) AS asignado_por
    FROM oc_propuesta op
    JOIN propuesta_comercial p ON p.id_propuesta = op.id_propuesta
    LEFT JOIN tabla_maestra m  ON m.IdMaestro = 1 AND m.IdEmpresa = 1 AND m.Num1 = p.id_moneda
    LEFT JOIN usuario u        ON u.id_usuario = op.creado_por
    WHERE op.id_oc = p_id_oc AND op.eliminado_en IS NULL
    ORDER BY op.creado_en;

    -- 6. Documentación SSOMA de las OS del expediente
    SELECT os.numero AS numero_os, sd.id_ssoma_doc, sd.id_requisito, td.String1 AS requisito,
           CONCAT(u.nombre, ' ', u.apellido) AS trabajador, sd.estado, sd.version,
           sd.fecha_carga, sd.fecha_vencimiento, sd.motivo_observacion
    FROM ssoma_documento sd
    JOIN orden_servicio os    ON os.id_os = sd.id_os AND os.eliminado_en IS NULL
    LEFT JOIN usuario u       ON u.id_usuario = sd.id_usuario
    LEFT JOIN tabla_maestra td ON td.IdMaestro = 36 AND td.IdEmpresa = 1 AND td.Num1 = sd.id_requisito
    WHERE os.id_expediente = v_id_exp AND sd.eliminado_en IS NULL
    ORDER BY os.numero, sd.fecha_carga DESC;

    -- 7. Versiones del PDF
    SELECT d.version, d.nombre_archivo, d.fecha_carga, CONCAT(u.nombre, ' ', u.apellido) AS subido_por,
           JSON_UNQUOTE(JSON_EXTRACT(d.metadatos, '$.motivo'))                       AS motivo,
           CAST(JSON_UNQUOTE(JSON_EXTRACT(d.metadatos, '$.tamano_bytes')) AS SIGNED) AS tamano_bytes,
           JSON_UNQUOTE(JSON_EXTRACT(d.metadatos, '$.hash'))                         AS hash
    FROM documento_adjunto d
    LEFT JOIN usuario u ON u.id_usuario = d.subido_por
    WHERE d.entidad_tipo = 'orden_compra' AND d.id_entidad = p_id_oc AND d.eliminado_en IS NULL
    ORDER BY d.version DESC;
END$$

DELIMITER ;
