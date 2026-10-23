-- HU-30 Tab 📝 Propuestas (N) de la ficha del expediente (carga perezosa, solo lectura). Acción expediente_bandeja.
-- Pills por propuesta y por versión; p_id_propuesta = versión elegida (por defecto la última versión de la propuesta
-- activa del expediente). "Comparar versiones" usa GET /api/expedientes/{id}/propuestas/comparar.
-- Resultados: 1 mensaje
--   2 versiones: todas las versiones de las propuestas del RQ (para las pills; es_activa = propuesta activa del
--     expediente, seleccionada = la versión que se muestra)
--   3 detalle de la versión: estado, responsable, montos (subtotal, descuento, IGV, total), moneda, condición y plazo
--     de pago, fechas (creación, envío, aceptación), secciones incluidas, PDF (clave prop-<id>)
--   4 formas de pago · 5 ítems (principal y opcional) · 6 equipos a intervenir
--   7 visto bueno de la versión (aprobador, decisión, comentario, fechas) · 8 timeline de la versión
--   9 órdenes de compra vinculadas a la versión (número, estado, monto asignado, responsable, emisión, recepción y
--     resultado de la validación)
-- El detalle (3) trae también el contacto y la sede de la propuesta y cuántos suministros del cliente incluye.
DROP PROCEDURE IF EXISTS SP_ObtenerPropuestasExpediente;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerPropuestasExpediente(
    IN p_id_usuario    BIGINT,
    IN p_id_expediente BIGINT,
    IN p_id_propuesta  BIGINT
)
proc: BEGIN
    DECLARE v_id_rq   BIGINT;
    DECLARE v_id_prop BIGINT;
    DECLARE v_activa  BIGINT;

    IF FN_PermisoAccion(p_id_usuario, 'expediente_bandeja') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver los expedientes digitales.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM expediente_digital WHERE id_expediente = p_id_expediente AND eliminado_en IS NULL) THEN
        SELECT 1 AS IdTipoMensaje, 'El expediente no existe.' AS Mensaje;
        LEAVE proc;
    END IF;
    SELECT id_requerimiento INTO v_id_rq FROM expediente_digital WHERE id_expediente = p_id_expediente;

    DROP TEMPORARY TABLE IF EXISTS tmp_exp_pv;
    CREATE TEMPORARY TABLE tmp_exp_pv AS
    SELECT p.id_propuesta, p.numero, p.version, p.estado, p.total, p.id_moneda, p.fecha_creacion,
           (p.version = (SELECT MAX(p2.version) FROM propuesta_comercial p2 WHERE p2.numero = p.numero AND p2.eliminado_en IS NULL)) AS es_ultima
    FROM propuesta_comercial p
    WHERE p.eliminado_en IS NULL AND p.id_requerimiento = v_id_rq;

    -- Propuesta activa: la más avanzada entre las últimas versiones (misma regla del cálculo del expediente)
    SELECT id_propuesta INTO v_activa FROM tmp_exp_pv
    WHERE es_ultima = 1 AND estado <> 'anulado'
    ORDER BY CASE estado WHEN 'aceptado' THEN 1 WHEN 'enviado' THEN 2 WHEN 'aprobado' THEN 2
                         WHEN 'pendiente_vb' THEN 3 WHEN 'pendiente_revocacion' THEN 3 WHEN 'rechazado' THEN 6 ELSE 4 END,
             id_propuesta DESC
    LIMIT 1;

    IF IFNULL(p_id_propuesta, 0) > 0 THEN
        SELECT id_propuesta INTO v_id_prop FROM tmp_exp_pv WHERE id_propuesta = p_id_propuesta;
        IF v_id_prop IS NULL THEN
            DROP TEMPORARY TABLE IF EXISTS tmp_exp_pv;
            SELECT 1 AS IdTipoMensaje, 'La propuesta no pertenece a este expediente.' AS Mensaje;
            LEAVE proc;
        END IF;
    ELSE
        SET v_id_prop = IFNULL(v_activa, (SELECT MAX(id_propuesta) FROM tmp_exp_pv));
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Versiones (pills)
    SELECT v.id_propuesta, v.numero, v.version, v.estado, v.total, m.String2 AS simbolo_moneda, v.fecha_creacion,
           v.es_ultima, (v.numero = (SELECT p.numero FROM propuesta_comercial p WHERE p.id_propuesta = v_activa)) AS es_activa,
           (v.id_propuesta = v_id_prop) AS seleccionada
    FROM tmp_exp_pv v
    LEFT JOIN tabla_maestra m ON m.IdMaestro = 1 AND m.IdEmpresa = 1 AND m.Num1 = v.id_moneda
    ORDER BY v.numero, v.version;

    DROP TEMPORARY TABLE IF EXISTS tmp_exp_pv;

    -- 3. Detalle de la versión elegida
    SELECT p.id_propuesta, p.numero, p.version, p.estado, p.tipo_servicio, p.referencia,
           COALESCE(p.id_responsable, p.id_creador) AS id_responsable, CONCAT(u.nombre, ' ', u.apellido) AS responsable,
           p.id_moneda, m.String1 AS moneda, m.String2 AS simbolo_moneda,
           p.subtotal, IFNULL(p.descuento_monto, 0) AS descuento_monto, IFNULL(p.descuento_pct, 0) AS descuento_pct,
           p.aplica_igv, IFNULL(p.igv_pct, 0) AS igv_pct, IFNULL(p.igv_monto, 0) AS igv_monto, p.total,
           p.id_condicion_pago,
           (SELECT cp.String1 FROM tabla_maestra cp WHERE cp.IdMaestro = 39 AND cp.IdEmpresa = 1 AND cp.Num1 = p.id_condicion_pago
              AND cp.eliminado_en IS NULL LIMIT 1) AS condicion_pago,
           p.plazo_entrega_dias, p.vigencia_dias, p.fecha_expiracion,
           p.fecha_creacion, COALESCE(p.fecha_envio_cliente, p.fecha_envio) AS fecha_envio,
           (SELECT MIN(IFNULL(s.fecha_interaccion, s.creado_en)) FROM seguimiento_comercial s
            WHERE s.id_propuesta = p.id_propuesta AND s.eliminado_en IS NULL AND s.estado = 'cerrado_aceptacion') AS fecha_aceptacion,
           p.descripcion_cambios, mv.String1 AS motivo_nueva_version,
           -- Completas (obligatorias + opcionales activas), en el orden del wizard
           CAST(FN_SeccionesActivasPropuesta(p.secciones_activas) AS CHAR) AS secciones_activas,
           CONCAT('prop-', p.id_propuesta) AS clave_pdf, CONCAT(p.numero, '-v', p.version, '.pdf') AS nombre_pdf,
           r.numero AS numero_rq,
           p.id_contacto, ct.nombres AS contacto, ct.cargo AS cargo_contacto, ct.correo AS correo_contacto,
           ct.telefono_movil AS telefono_contacto, ct.area AS area_contacto, p.id_sede, sc.nombre AS sede,
           NULLIF(CONCAT_WS(', ', NULLIF(sc.distrito, ''), NULLIF(sc.provincia, ''), NULLIF(sc.region, '')), '') AS sede_ubicacion,
           sc.direccion_exacta AS sede_direccion,
           (SELECT COUNT(*) FROM propuesta_texto tx WHERE tx.id_propuesta = p.id_propuesta
              AND tx.seccion = 'suministros_cliente' AND tx.tipo <> 'titulo')       AS suministros
    FROM propuesta_comercial p
    LEFT JOIN contacto_cliente ct ON ct.id_contacto = p.id_contacto
    LEFT JOIN sede_cliente sc     ON sc.id_sede = p.id_sede
    LEFT JOIN usuario u        ON u.id_usuario = COALESCE(p.id_responsable, p.id_creador)
    LEFT JOIN tabla_maestra m  ON m.IdMaestro = 1 AND m.IdEmpresa = 1 AND m.Num1 = p.id_moneda
    LEFT JOIN tabla_maestra mv ON mv.IdMaestro = 11 AND mv.IdEmpresa = 1 AND mv.Num1 = p.id_motivo_nueva_version
    LEFT JOIN requerimiento r  ON r.id_requerimiento = p.id_requerimiento
    WHERE p.id_propuesta = v_id_prop;

    -- 4. Formas de pago
    SELECT f.porcentaje, f.condicion, f.orden FROM propuesta_forma_pago f WHERE f.id_propuesta = v_id_prop ORDER BY f.orden;

    -- 5. Ítems
    SELECT i.id_item, i.seccion, i.descripcion, i.cantidad, i.precio_unitario, IFNULL(i.descuento, 0) AS descuento,
           i.subtotal, i.alcance, i.puntos_calibracion, i.frecuencia
    FROM propuesta_item i
    WHERE i.id_propuesta = v_id_prop AND i.eliminado_en IS NULL AND IFNULL(i.es_espaciado, 0) = 0
    ORDER BY (i.seccion = 'opcional'), i.orden, i.id_item;

    -- 6. Equipos a intervenir
    SELECT e.id_equipo, e.tipo, e.subtipo, e.marca, e.modelo, e.num_serie, e.codigo_cliente, e.codigo_tw, e.local_sede
    FROM propuesta_equipo e WHERE e.id_propuesta = v_id_prop ORDER BY e.orden, e.id;

    -- 7. Visto bueno de la versión
    --    (el VB va a la bandeja del área sin aprobador fijo: aprobador efectivo con FN_AprobadorVistoBueno)
    SELECT v.id_vb, v.estado, FN_AprobadorVistoBuenoExpediente(v.id_vb) AS id_aprobador,
           CONCAT(ua.nombre, ' ', ua.apellido) AS aprobador, ua.cargo AS cargo_aprobador,
           v.fecha_solicitud, v.fecha_respuesta, IF(v.estado = 'pendiente', NULL, FN_AprobadorVistoBuenoExpediente(v.id_vb)) AS id_resuelto_por,
           CONCAT(ur.nombre, ' ', ur.apellido) AS resuelto_por, v.comentario_respuesta, mr.String1 AS motivo_rechazo
    FROM visto_bueno v
    LEFT JOIN usuario ua ON ua.id_usuario = FN_AprobadorVistoBuenoExpediente(v.id_vb)
    LEFT JOIN usuario ur ON ur.id_usuario = IF(v.estado = 'pendiente', NULL, FN_AprobadorVistoBuenoExpediente(v.id_vb))
    LEFT JOIN tabla_maestra mr ON mr.IdMaestro = 10 AND mr.IdEmpresa = 1 AND mr.Num1 = v.id_motivo_rechazo
    WHERE v.id_propuesta = v_id_prop AND v.tipo = 'aprobacion' AND v.eliminado_en IS NULL
    ORDER BY v.id_vb DESC;

    -- 8. Timeline de la versión (auditoría de la propuesta, respuestas de VB y seguimiento)
    SELECT t.fecha, t.tipo, t.titulo, t.descripcion, t.id_usuario, IFNULL(CONCAT(u.nombre, ' ', u.apellido), 'Sistema') AS usuario
    FROM (
        SELECT a.registrado_en AS fecha, a.accion AS tipo,
               CASE a.accion WHEN 'creacion' THEN 'Propuesta creada' WHEN 'nueva_version' THEN 'Nueva versión creada'
                             WHEN 'nueva_version_por_revocacion' THEN 'Nueva versión por revocación'
                             WHEN 'edicion' THEN 'Propuesta actualizada' WHEN 'envio_vb' THEN 'Enviada a visto bueno'
                             WHEN 'envio_cliente' THEN 'Propuesta enviada al cliente' WHEN 'anulacion' THEN 'Propuesta anulada'
                             WHEN 'anulacion_por_version' THEN 'Versión reemplazada'
                             WHEN 'reasignar_responsable' THEN 'Responsable reasignado'
                             ELSE CONCAT(UPPER(LEFT(REPLACE(a.accion, '_', ' '), 1)), SUBSTRING(REPLACE(a.accion, '_', ' '), 2)) END AS titulo,
               a.descripcion, a.id_usuario
        FROM auditoria_evento a
        WHERE a.entidad_tipo = 'propuesta' AND a.id_entidad = v_id_prop AND a.accion NOT LIKE 'vb\_%'
        UNION ALL
        SELECT v.fecha_respuesta, CONCAT('vb_', v.estado),
               CASE v.estado WHEN 'aprobado' THEN 'VB aprobado' WHEN 'rechazado' THEN 'VB rechazado'
                             WHEN 'devuelto' THEN 'VB devuelto para ajuste' ELSE CONCAT('VB ', REPLACE(v.estado, '_', ' ')) END,
               v.comentario_respuesta, FN_AprobadorVistoBuenoExpediente(v.id_vb)
        FROM visto_bueno v
        WHERE v.id_propuesta = v_id_prop AND v.tipo = 'aprobacion' AND v.eliminado_en IS NULL AND v.fecha_respuesta IS NOT NULL
        UNION ALL
        SELECT IFNULL(s.fecha_interaccion, s.creado_en), CONCAT('seguimiento_', s.estado),
               CASE s.estado WHEN 'cerrado_aceptacion' THEN 'Propuesta ACEPTADA por el cliente'
                             WHEN 'cerrado_rechazo' THEN 'Propuesta rechazada por el cliente' ELSE 'Interacción de seguimiento' END,
               NULLIF(TRIM(IFNULL(s.notas, '')), ''), s.creado_por
        FROM seguimiento_comercial s
        WHERE s.id_propuesta = v_id_prop AND s.eliminado_en IS NULL
    ) t
    LEFT JOIN usuario u ON u.id_usuario = t.id_usuario
    ORDER BY t.fecha DESC;

    -- 9. Órdenes de compra vinculadas a la versión (también las reemplazadas, marcadas)
    SELECT oc.id_oc, oc.numero_oc, oc.estado, oc.es_autogenerada, (oc.reemplazada_por IS NOT NULL) AS reemplazada,
           oc.id_moneda AS id_moneda_oc, mo.String2 AS simbolo_moneda_oc, oc.monto_total, op.monto_asignado, op.monto_cubierto,
           op.estado_validacion, op.resultado_ia, va.criticas, va.advertencias,
           COALESCE(oc.id_responsable, pr.id_responsable, pr.id_creador) AS id_responsable,
           CONCAT(ur.nombre, ' ', ur.apellido) AS responsable,
           oc.fecha_oc AS fecha_emision, oc.fecha_recepcion, oc.fecha_registro
    FROM oc_propuesta op
    JOIN orden_compra oc          ON oc.id_oc = op.id_oc AND oc.eliminado_en IS NULL
    JOIN propuesta_comercial pr   ON pr.id_propuesta = op.id_propuesta
    LEFT JOIN orden_compra_validacion va ON va.id_validacion = op.id_validacion
    LEFT JOIN usuario ur          ON ur.id_usuario = COALESCE(oc.id_responsable, pr.id_responsable, pr.id_creador)
    LEFT JOIN tabla_maestra mo    ON mo.IdMaestro = 1 AND mo.IdEmpresa = 1 AND mo.Num1 = oc.id_moneda
    WHERE op.id_propuesta = v_id_prop AND op.eliminado_en IS NULL
    ORDER BY oc.fecha_registro DESC, oc.id_oc DESC;
END$$

DELIMITER ;
