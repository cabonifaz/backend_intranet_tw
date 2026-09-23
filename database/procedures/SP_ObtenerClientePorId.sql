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
        SELECT 1 FROM clientes
        WHERE id_cliente = p_id_cliente AND SoftDelete = 0
    ) THEN
        SELECT 1 AS IdTipoMensaje, 'Cliente no encontrado.' AS Mensaje;
    ELSE
        SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

        SELECT
            id_cliente,
            tipo_documento,
            ruc,
            tipo_cliente,
            razon_social,
            nombre_comercial,
            condicion_fiscal,
            condicion_contribuyente,
            condicion_pago,
            linea_credito_usd,
            telefono_central,
            domicilio_fiscal,
            es_vip,
            regla_vip,
            descuento_vip_pct,
            patron_masas_asignado,
            ssoma_pase_ingreso,
            ssoma_trabajo_altura,
            ssoma_espacio_confinado,
            ssoma_induccion_previa,
            ssoma_notas,
            estado
        FROM clientes
        WHERE id_cliente = p_id_cliente AND SoftDelete = 0;
    END IF;
END //

DELIMITER ;
