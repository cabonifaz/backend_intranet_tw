-- Datos guardados de una orden de compra en el formato que usa SP_CompararOcPropuesta (para re-validarla).
DROP FUNCTION IF EXISTS FN_DatosOrdenCompraJson;

DELIMITER $$

CREATE FUNCTION FN_DatosOrdenCompraJson(p_id_oc BIGINT) RETURNS JSON
READS SQL DATA
BEGIN
    DECLARE v_json JSON;

    SELECT JSON_OBJECT(
               'numeroOc',        numero_oc,
               'ruc',             ruc_cliente_oc,
               'razonSocial',     razon_social_oc,
               'numeroPropuesta', numero_propuesta_ref,
               'idMoneda',        id_moneda,
               'montoTotal',      monto_total,
               'tipoCambio',      tipo_cambio,
               'idCondicionPago', id_condicion_pago,
               'formaPago',       forma_pago,
               'igvIncluido',     CASE igv_incluido WHEN 1 THEN CAST('true' AS JSON) WHEN 0 THEN CAST('false' AS JSON) END,
               'igvPct',          igv_pct,
               'descuento',       descuento_monto,
               'fechaEmision',    DATE_FORMAT(fecha_oc, '%Y-%m-%d'),
               'fechaRecepcion',  DATE_FORMAT(fecha_recepcion, '%Y-%m-%d'),
               'vigenciaHasta',   DATE_FORMAT(vigencia_hasta, '%Y-%m-%d'),
               'facturaIgualOc',  IF(factura_igual_oc = 1, CAST('true' AS JSON), CAST('false' AS JSON)),
               'conceptos',       IFNULL(conceptos, JSON_ARRAY()))
      INTO v_json
    FROM orden_compra WHERE id_oc = p_id_oc;

    RETURN v_json;
END$$

DELIMITER ;
