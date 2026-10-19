-- Requisitos SSOMA asignados a un cliente. Devuelve [{codigo, nombre}] donde
-- codigo = String2 del catálogo REQUISITO_SSOMA (IdMaestro=48).
-- Alimenta los checkboxes de la sección SSOMA de la ficha de cliente.
DROP PROCEDURE IF EXISTS SP_ObtenerRequisitosDelCliente;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerRequisitosDelCliente(
    IN p_id_cliente BIGINT
)
BEGIN
    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT t.String2 AS codigo, t.String1 AS nombre
    FROM requisito_ssoma_cliente rsc
    JOIN tabla_maestra t
      ON t.IdMaestro = 48 AND t.IdEmpresa = 1 AND t.Num1 = rsc.id_requisito
    WHERE rsc.id_cliente = p_id_cliente
      AND rsc.eliminado_en IS NULL
    ORDER BY t.String1;
END$$

DELIMITER ;
