-- ============================================================
-- SP_ObtenerContactosPorCliente
-- Devuelve los contactos activos de un cliente (HU-81)
-- ============================================================

DROP PROCEDURE IF EXISTS SP_ObtenerContactosPorCliente;

DELIMITER $$
CREATE PROCEDURE SP_ObtenerContactosPorCliente(
    IN p_id_cliente BIGINT
)
BEGIN
    DECLARE v_total INT;

    SELECT COUNT(*) INTO v_total
    FROM contacto_cliente
    WHERE id_cliente = p_id_cliente AND SoftDelete = 0;

    SELECT 2 AS IdTipoMensaje,
           CONCAT(v_total, ' contacto(s) encontrado(s).') AS Mensaje;

    SELECT
        id_contacto,
        id_cliente,
        id_sede,
        nombres,
        documento_identidad,
        cargo,
        area,
        correo,
        telefono_movil,
        telefono_anexo,
        es_contacto_principal,
        autorizado_aprobar_cotizaciones,
        recibe_alertas_calibracion,
        autorizado_recepcion_tecnica,
        estado
    FROM contacto_cliente
    WHERE id_cliente = p_id_cliente AND SoftDelete = 0
    ORDER BY es_contacto_principal DESC, nombres ASC;
END$$
DELIMITER ;
