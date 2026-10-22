-- HU-25 (Sprint 4) Detalle de la orden de compra con sus sub-aplicaciones (propuestas vinculadas). Solo lectura:
-- los botones (Editar OC, Reemplazar PDF, Subir OC corregida, Agregar propuesta vinculada, Validar contra propuesta)
-- redirigen a la ficha; Anular abre su modal.
-- Resultados:
--   1 mensaje
--   2 cabecera: datos extraídos, montos (OC, asignado, saldo), estado consolidado, validación IA, PDF, anulación,
--     OC autogenerada / reemplazo y permisos de los botones
--   3 propuestas vinculadas: monto y % asignado, contacto, RQ, servicios, estado de la vinculación, última validación,
--     versión nueva (y si ya está aceptada) y si la facturación está habilitada
--   4 diferencias de la última validación de cada propuesta (sección "Validación IA" por propuesta seleccionada)
DROP PROCEDURE IF EXISTS SP_ObtenerDetalleOrdenCompra;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerDetalleOrdenCompra(
    IN p_id_usuario BIGINT,
    IN p_id_oc      BIGINT
)
proc: BEGIN
    DECLARE v_existe INT DEFAULT 0;

    IF FN_PermisoAccion(p_id_usuario, 'oc_bandeja') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver las órdenes de compra.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_CalcularOrdenesCompra(p_id_usuario, p_id_oc);
    SELECT COUNT(*) INTO v_existe FROM tmp_oc;
    IF v_existe = 0 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_oc;
        SELECT 1 AS IdTipoMensaje, 'La orden de compra no existe o no pertenece a tu área.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- 1. Header
    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Cabecera
    SELECT
        t.id_oc, t.numero_oc, t.estado, t.estado_visual, t.es_autogenerada, t.pendiente_reemplazo,
        t.reemplazada_por, (SELECT o2.numero_oc FROM orden_compra o2 WHERE o2.id_oc = t.reemplazada_por) AS numero_oc_reemplazo,
        t.fecha_reemplazo,
        t.id_oc_reemplazada, (SELECT o3.numero_oc FROM orden_compra o3 WHERE o3.id_oc = t.id_oc_reemplazada) AS numero_oc_reemplazada,
        t.id_cliente, c.razon_social, c.ruc,
        t.fecha_registro, t.creado_por, IFNULL(CONCAT(uc.nombre, ' ', uc.apellido), 'Sistema') AS registrado_por,
        t.id_responsable, CONCAT(ur.nombre, ' ', ur.apellido) AS responsable,
        t.id_moneda,
        (SELECT MAX(m.String1) FROM tabla_maestra m WHERE m.IdMaestro = 1 AND m.IdEmpresa = 1 AND m.Num1 = t.id_moneda) AS moneda_nombre,
        (SELECT MAX(m.String2) FROM tabla_maestra m WHERE m.IdMaestro = 1 AND m.IdEmpresa = 1 AND m.Num1 = t.id_moneda) AS moneda_simbolo,
        (SELECT MAX(m.String3) FROM tabla_maestra m WHERE m.IdMaestro = 1 AND m.IdEmpresa = 1 AND m.Num1 = t.id_moneda) AS moneda,
        t.monto_oc, t.propuestas_vinculadas, t.monto_asignado, t.saldo_oc, t.asignado_pct,
        t.resultado_ia, t.alertas_ia, t.vinculaciones_validadas, t.vinculaciones_observadas, t.pendientes_correccion,
        oc.ruc_cliente_oc, oc.razon_social_oc, oc.numero_propuesta_ref,
        oc.id_condicion_pago,
        (SELECT MAX(cp.String1) FROM tabla_maestra cp WHERE cp.IdMaestro = 39 AND cp.IdEmpresa = 1 AND cp.Num1 = oc.id_condicion_pago) AS condicion_pago,
        oc.forma_pago, oc.igv_incluido, oc.igv_pct, oc.descuento_monto,
        oc.fecha_oc, oc.fecha_recepcion, oc.vigencia_hasta, oc.factura_igual_oc,
        oc.referencia, oc.observaciones, oc.conceptos, oc.campos_ia, oc.campos_manuales,
        t.tiene_pdf, oc.nombre_archivo_pdf, oc.tamano_pdf_bytes,
        IF(t.tiene_pdf = 1, CONCAT('/api/crm/ordenes-compra/', t.id_oc, '/pdf'), NULL)                   AS url_pdf,
        oc.id_motivo_anulacion,
        (SELECT MAX(ma.String1) FROM tabla_maestra ma WHERE ma.IdMaestro = 102 AND ma.IdEmpresa = 1
           AND ma.Num1 = oc.id_motivo_anulacion)                                                        AS motivo_anulacion,
        oc.justificacion_anulacion, oc.fecha_anulacion,
        (SELECT CONCAT(ua.nombre, ' ', ua.apellido) FROM usuario ua WHERE ua.id_usuario = oc.anulado_por) AS anulado_por,
        t.id_expediente, (SELECT e.numero FROM expediente_digital e WHERE e.id_expediente = t.id_expediente) AS numero_expediente,
        -- Botones
        (t.estado <> 'anulada' AND t.es_autogenerada = 0 AND FN_PermisoAccion(p_id_usuario, 'oc_editar') = 1)     AS puede_editar,
        (t.estado <> 'anulada' AND t.es_autogenerada = 0
         AND FN_PermisoAccion(p_id_usuario, 'oc_documento_reemplazar') = 1)                                    AS puede_reemplazar_pdf,
        (t.estado <> 'anulada' AND t.pendientes_correccion > 0
         AND FN_PermisoAccion(p_id_usuario, 'oc_documento_reemplazar') = 1)                                    AS puede_subir_corregida,
        (t.estado <> 'anulada' AND t.es_autogenerada = 0 AND t.saldo_oc > 0
         AND FN_PermisoAccion(p_id_usuario, 'oc_editar') = 1)                                                  AS puede_agregar_propuesta,
        (t.estado <> 'anulada' AND t.es_autogenerada = 0 AND FN_PermisoAccion(p_id_usuario, 'oc_validar') = 1)   AS puede_revalidar,
        (t.estado NOT IN ('anulada', 'autogenerada') AND t.reemplazada_por IS NULL AND FN_PermisoAccion(p_id_usuario, 'oc_anular') = 1) AS puede_anular,
        (t.pendiente_reemplazo = 1 AND FN_PermisoAccion(p_id_usuario, 'oc_registrar') = 1)                     AS puede_reemplazar_auto,
        -- Registrar la OC del cliente que reemplaza a esta (OC autogenerada o pendiente de reemplazo)
        (t.pendiente_reemplazo = 1 AND FN_PermisoAccion(p_id_usuario, 'oc_registrar') = 1)                     AS puede_reemplazar
    FROM tmp_oc t
    JOIN orden_compra oc  ON oc.id_oc       = t.id_oc
    JOIN cliente c        ON c.id_cliente   = t.id_cliente
    LEFT JOIN usuario uc  ON uc.id_usuario  = t.creado_por
    LEFT JOIN usuario ur  ON ur.id_usuario  = t.id_responsable;

    DROP TEMPORARY TABLE IF EXISTS tmp_oc;

    -- 3. Propuestas vinculadas
    SELECT op.id_propuesta, p.numero, p.version, p.estado AS estado_propuesta,
           (p.estado NOT IN ('anulado', 'revocada'))                                                      AS aceptada,
           p.total AS monto_propuesta, op.monto_asignado,
           IF(oc.monto_total > 0, ROUND(op.monto_asignado * 100 / oc.monto_total, 2), 0)                 AS pct_oc,
           FN_SaldoPropuestaOc(op.id_propuesta, NULL)                                                    AS saldo_propuesta,
           p.id_contacto, ct.nombres AS contacto, ct.cargo AS cargo_contacto,
           p.id_requerimiento, r.numero AS numero_rq,
           (SELECT COUNT(*) FROM propuesta_item i WHERE i.id_propuesta = p.id_propuesta AND i.seccion = 'principal'
              AND IFNULL(i.es_espaciado, 0) = 0)                                                         AS servicios,
           (SELECT GROUP_CONCAT(i.descripcion ORDER BY i.orden SEPARATOR ', ') FROM propuesta_item i
            WHERE i.id_propuesta = p.id_propuesta AND i.seccion = 'principal' AND IFNULL(i.es_espaciado, 0) = 0) AS servicios_detalle,
           op.estado_validacion, op.tipo_observacion, op.resultado_ia, op.fecha_decision,
           v.id_validacion, v.corrida, v.coincidencias, v.advertencias, v.criticas, v.total_campos, v.sugerencia,
           v.dictamen, v.fecha_validacion,
           op.id_propuesta_nueva_version, nv.numero AS numero_nueva_version, nv.version AS version_nueva_version,
           nv.estado AS estado_nueva_version,
           (nv.id_propuesta IS NOT NULL AND EXISTS (SELECT 1 FROM seguimiento_comercial s2 WHERE s2.id_propuesta = nv.id_propuesta
                                                      AND s2.estado = 'cerrado_aceptacion' AND s2.eliminado_en IS NULL)) AS nueva_version_aceptada,
           (op.estado_validacion = 'validada' AND oc.es_autogenerada = 0 AND oc.estado <> 'anulada')     AS facturacion_habilitada
    FROM oc_propuesta op
    JOIN orden_compra oc             ON oc.id_oc         = op.id_oc
    JOIN propuesta_comercial p       ON p.id_propuesta   = op.id_propuesta
    LEFT JOIN contacto_cliente ct    ON ct.id_contacto   = p.id_contacto
    LEFT JOIN requerimiento r        ON r.id_requerimiento = p.id_requerimiento
    LEFT JOIN orden_compra_validacion v ON v.id_validacion = op.id_validacion
    LEFT JOIN propuesta_comercial nv ON nv.id_propuesta  = op.id_propuesta_nueva_version
    WHERE op.id_oc = p_id_oc
      AND (op.eliminado_en IS NULL
           -- La OC autogenerada ya reemplazada muestra la propuesta que cubría
           OR (oc.reemplazada_por IS NOT NULL AND op.eliminado_en = (SELECT MAX(o4.eliminado_en) FROM oc_propuesta o4
                                                                     WHERE o4.id_oc = p_id_oc)))
    ORDER BY op.id;

    -- 4. Diferencias de la última validación de cada propuesta
    SELECT op.id_propuesta, d.orden, d.campo, d.etiqueta, d.valor_oc, d.valor_propuesta, d.severidad, d.mensaje, d.accion
    FROM oc_propuesta op
    JOIN orden_compra_validacion v ON v.id_validacion = op.id_validacion
    JOIN JSON_TABLE(v.detalle, '$[*]' COLUMNS (
            orden           INT          PATH '$.orden',
            campo           VARCHAR(30)  PATH '$.campo',
            etiqueta        VARCHAR(60)  PATH '$.etiqueta',
            valor_oc        VARCHAR(400) PATH '$.valorOc',
            valor_propuesta VARCHAR(400) PATH '$.valorPropuesta',
            severidad       VARCHAR(15)  PATH '$.severidad',
            mensaje         VARCHAR(400) PATH '$.mensaje',
            accion          VARCHAR(200) PATH '$.accion')) d
    WHERE op.id_oc = p_id_oc AND op.eliminado_en IS NULL
    ORDER BY op.id, d.orden;
END$$

DELIMITER ;
