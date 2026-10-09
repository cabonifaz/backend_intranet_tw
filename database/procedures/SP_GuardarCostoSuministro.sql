-- Registrar el precio de costo de un suministro (HU-14). NULL = quitar el costo.
-- Se guarda en la moneda del suministro.
DROP PROCEDURE IF EXISTS SP_GuardarCostoSuministro;

DELIMITER $$

CREATE PROCEDURE SP_GuardarCostoSuministro(
    IN p_id_suministro BIGINT,
    IN p_precio_costo  DECIMAL(12,2),
    IN p_id_usuario    BIGINT
)
proc: BEGIN
    IF NOT EXISTS (SELECT 1 FROM suministros WHERE id_suministro = p_id_suministro AND eliminado_en IS NULL) THEN
        SELECT 1 AS IdTipoMensaje, 'Suministro no encontrado.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF p_precio_costo IS NOT NULL AND p_precio_costo < 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El precio de costo no puede ser negativo.' AS Mensaje;
        LEAVE proc;
    END IF;

    UPDATE suministros
       SET precio_costo = p_precio_costo, costo_actualizado_en = NOW(), costo_actualizado_por = p_id_usuario
     WHERE id_suministro = p_id_suministro;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('suministro', p_id_suministro, 'costo_actualizado',
            IF(p_precio_costo IS NULL, 'Se quitó el precio de costo.', CONCAT('Precio de costo: ', FORMAT(p_precio_costo, 2), '.')),
            p_id_usuario, NOW(), JSON_OBJECT('precio_costo', p_precio_costo));

    SELECT 2 AS IdTipoMensaje, 'Precio de costo actualizado.' AS Mensaje;
END$$

DELIMITER ;
