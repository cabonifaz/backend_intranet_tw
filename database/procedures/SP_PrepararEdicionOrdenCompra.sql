-- HU-25/26 (Sprint 4) Datos de la ficha en modo edición. Los botones del detalle (Editar OC, Subir OC corregida,
-- Agregar propuesta vinculada, Validar contra propuesta) redirigen a esta ficha.
-- Reglas: acción oc_editar; OC del área del usuario, no anulada; la OC autogenerada no se edita (se reemplaza).
-- Resultados:
--   1 mensaje
--   2 OC: datos extraídos/corregidos, conceptos, campos IA y manuales, PDF vigente
--   3 propuestas vinculadas: monto asignado, saldo de la propuesta, estado de la vinculación y versión nueva
--     (cuando existe una versión nueva aceptada, "Validar contra propuesta" la reemplaza en la vinculación)
--   4 otras propuestas aceptadas del mismo cliente con saldo   5 monedas   6 condiciones de pago
DROP PROCEDURE IF EXISTS SP_PrepararEdicionOrdenCompra;

DELIMITER $$

CREATE PROCEDURE SP_PrepararEdicionOrdenCompra(
    IN p_id_usuario BIGINT,
    IN p_id_oc      BIGINT
)
proc: BEGIN
    DECLARE v_existe     INT DEFAULT 0;
    DECLARE v_estado     VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_auto       TINYINT;
    DECLARE v_id_cliente BIGINT;

    IF FN_PermisoAccion(p_id_usuario, 'oc_editar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para editar órdenes de compra.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_CalcularOrdenesCompra(p_id_usuario, p_id_oc);
    SELECT COUNT(*), MAX(estado), MAX(es_autogenerada), MAX(id_cliente) INTO v_existe, v_estado, v_auto, v_id_cliente
    FROM tmp_oc;
    DROP TEMPORARY TABLE IF EXISTS tmp_oc;

    IF v_existe = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'La orden de compra no existe o no pertenece a tu área.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_estado = 'anulada' THEN
        SELECT 1 AS IdTipoMensaje, 'La orden de compra está anulada: no se puede editar.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF EXISTS (SELECT 1 FROM orden_compra WHERE id_oc = p_id_oc AND reemplazada_por IS NOT NULL) THEN
        SELECT 1 AS IdTipoMensaje, 'La orden de compra fue reemplazada por otra OC del cliente: es de solo lectura.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_auto = 1 THEN
        SELECT 1 AS IdTipoMensaje, 'La OC autogenerada no se edita: reemplázala por la OC del cliente.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- 1. Header
    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. OC
    SELECT oc.id_oc, oc.numero_oc, oc.estado, oc.id_cliente, c.razon_social, c.ruc,
           oc.id_propuesta, oc.ruc_cliente_oc, oc.razon_social_oc, oc.numero_propuesta_ref,
           oc.id_moneda, oc.monto_total, oc.id_condicion_pago, oc.forma_pago, oc.igv_incluido, oc.igv_pct,
           oc.descuento_monto, oc.factura_igual_oc, oc.fecha_oc, oc.fecha_recepcion, oc.vigencia_hasta,
           oc.referencia, oc.observaciones, oc.conceptos, oc.campos_ia, oc.campos_manuales,
           oc.nombre_archivo_pdf, oc.tamano_pdf_bytes, (oc.url_archivo_pdf IS NOT NULL) AS tiene_pdf,
           IF(oc.url_archivo_pdf IS NULL, NULL, CONCAT('/api/crm/ordenes-compra/', oc.id_oc, '/pdf')) AS url_pdf,
           EXISTS (SELECT 1 FROM oc_propuesta op WHERE op.id_oc = oc.id_oc AND op.eliminado_en IS NULL
                     AND op.estado_validacion = 'observada' AND op.tipo_observacion = 'correccion_cliente') AS pendiente_correccion,
           oc.fecha_registro
    FROM orden_compra oc
    JOIN cliente c ON c.id_cliente = oc.id_cliente
    WHERE oc.id_oc = p_id_oc;

    -- 3. Propuestas vinculadas
    SELECT op.id_propuesta, p.numero, p.version, p.total, FN_SaldoPropuestaOc(op.id_propuesta, p_id_oc) AS saldo,
           p.id_moneda, op.monto_asignado, op.estado_validacion, op.tipo_observacion, op.resultado_ia,
           p.id_contacto, ct.nombres AS contacto, p.id_requerimiento, r.numero AS numero_rq,
           op.id_propuesta_nueva_version, nv.numero AS numero_nueva_version, nv.version AS version_nueva_version,
           nv.estado AS estado_nueva_version,
           (nv.id_propuesta IS NOT NULL
            AND (EXISTS (SELECT 1 FROM seguimiento_comercial s WHERE s.id_propuesta = nv.id_propuesta
                           AND s.estado = 'cerrado_aceptacion' AND s.eliminado_en IS NULL)))      AS nueva_version_aceptada
    FROM oc_propuesta op
    JOIN propuesta_comercial p     ON p.id_propuesta  = op.id_propuesta
    LEFT JOIN contacto_cliente ct  ON ct.id_contacto  = p.id_contacto
    LEFT JOIN requerimiento r      ON r.id_requerimiento = p.id_requerimiento
    LEFT JOIN propuesta_comercial nv ON nv.id_propuesta = op.id_propuesta_nueva_version
    WHERE op.id_oc = p_id_oc AND op.eliminado_en IS NULL
    ORDER BY op.id;

    -- 4. Otras propuestas del mismo cliente con saldo
    CALL SP_CalcularPropuestasDisponiblesOc(p_id_usuario, v_id_cliente, p_id_oc);
    SELECT d.id_propuesta, d.numero, d.version, d.id_requerimiento, d.numero_rq, d.id_contacto, d.contacto,
           d.total, d.saldo, d.id_moneda, d.moneda, d.moneda_simbolo, d.fecha_aceptacion, d.responsable, d.tipo_servicio
    FROM tmp_oc_disp d
    WHERE NOT EXISTS (SELECT 1 FROM oc_propuesta op WHERE op.id_oc = p_id_oc AND op.id_propuesta = d.id_propuesta
                        AND op.eliminado_en IS NULL)
    ORDER BY d.fecha_aceptacion DESC;
    DROP TEMPORARY TABLE IF EXISTS tmp_oc_disp;

    -- 5. Monedas
    SELECT Num1 AS id, String1 AS nombre, String2 AS simbolo, String3 AS codigo
    FROM tabla_maestra WHERE IdMaestro = 1 AND IdEmpresa = 1 AND eliminado_en IS NULL ORDER BY Num1;

    -- 6. Condiciones de pago
    SELECT Num1 AS id, MAX(String1) AS nombre, MAX(String2) AS codigo
    FROM tabla_maestra WHERE IdMaestro = 39 AND IdEmpresa = 1 AND eliminado_en IS NULL GROUP BY Num1 ORDER BY Num1;
END$$

DELIMITER ;
