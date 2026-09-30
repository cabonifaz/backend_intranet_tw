-- ============================================================
-- SP_ObtenerClientePorId
-- Detalle completo de un cliente para la ficha de edición.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerClientePorId;

DELIMITER //

CREATE PROCEDURE SP_ObtenerClientePorId(
    IN p_id_cliente BIGINT
)
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM cliente
        WHERE id_cliente = p_id_cliente AND SoftDelete = 0
    ) THEN
        SELECT 1 AS IdTipoMensaje, 'Cliente no encontrado.' AS Mensaje;
    ELSE
        SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

        SELECT
            c.id_cliente,
            c.tipo_documento,
            c.ruc,
            c.tipo_cliente,
            c.razon_social,
            c.nombre_comercial,
            c.condicion_fiscal,
            c.condicion_contribuyente,
            c.condicion_pago,
            c.linea_credito_usd,
            c.telefono_central,
            c.domicilio_fiscal,
            c.es_vip,
            c.regla_vip,
            c.descuento_vip_pct,
            c.patron_masas_asignado,
            c.ssoma_poliza_sctr,
            c.ssoma_camioneta_4x4,
            c.ssoma_induccion_ssoma,
            c.ssoma_examen_medico,
            c.ssoma_notas,
            c.id_categoria,
            cc.nombre AS nombre_categoria,
            c.estado
        FROM cliente c
        LEFT JOIN categoria_cliente cc
            ON cc.id_categoria = c.id_categoria AND cc.SoftDelete = 0
        WHERE c.id_cliente = p_id_cliente AND c.SoftDelete = 0;
    END IF;
END //

DELIMITER ;
