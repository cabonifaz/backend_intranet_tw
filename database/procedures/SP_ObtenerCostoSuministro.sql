-- Precio de costo de un suministro (HU-14, margen). Solo jefaturas (acción suministro_costo_ver).
DROP PROCEDURE IF EXISTS SP_ObtenerCostoSuministro;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerCostoSuministro(
    IN p_id_suministro BIGINT
)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM suministros WHERE id_suministro = p_id_suministro AND eliminado_en IS NULL) THEN
        SELECT 1 AS IdTipoMensaje, 'Suministro no encontrado.' AS Mensaje;
    ELSE
        SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;
        SELECT s.id_suministro, s.precio_costo, s.id_moneda, m.String3 AS moneda,
               s.precio_nivel_estandar,
               IF(s.precio_costo > 0 AND s.precio_nivel_estandar > 0,
                  ROUND((s.precio_nivel_estandar - s.precio_costo) * 100 / s.precio_nivel_estandar, 2), NULL) AS margen_estandar_pct,
               s.costo_actualizado_en,
               (SELECT CONCAT(u.nombre, ' ', u.apellido) FROM usuario u WHERE u.id_usuario = s.costo_actualizado_por) AS costo_actualizado_por
        FROM suministros s
        LEFT JOIN tabla_maestra m ON m.IdMaestro = 1 AND m.IdEmpresa = 1 AND m.Num1 = s.id_moneda
        WHERE s.id_suministro = p_id_suministro;
    END IF;
END$$

DELIMITER ;
