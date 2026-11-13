-- ============================================================
-- SP_ObtenerSedesSinUbicacion  (Maestros › Clientes: sedes que faltan marcar en el mapa · solo lectura)
-- Sedes activas (de clientes activos) sin latitud/longitud. Sin ubicación, la llegada del técnico no se valida por GPS y el seguimiento
-- no puede dibujar la planta ni calcular la distancia y la ETA. Primero las que tienen servicios próximos (OS no anuladas de hoy en adelante, hora de Lima).
-- p_id_cliente opcional (NULL = todas). Resultados: 1 mensaje · 2 sedes.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerSedesSinUbicacion;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerSedesSinUbicacion(
    IN p_id_cliente BIGINT
)
proc: BEGIN
    DECLARE v_hoy DATE;

    IF p_id_cliente IS NOT NULL AND p_id_cliente <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El cliente no es válido.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_hoy = DATE(UTC_TIMESTAMP() - INTERVAL 5 HOUR);

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;
    SELECT s.id_sede, s.id_cliente, c.razon_social AS cliente, s.nombre AS sede, s.direccion_exacta,
           s.region, s.provincia, s.distrito,
           (SELECT COUNT(*) FROM orden_servicio os
            WHERE os.id_sede = s.id_sede AND os.eliminado_en IS NULL AND os.estado <> 'anulada' AND os.fecha_ejecucion >= v_hoy) AS servicios_proximos,
           (SELECT MIN(os.fecha_ejecucion) FROM orden_servicio os
            WHERE os.id_sede = s.id_sede AND os.eliminado_en IS NULL AND os.estado <> 'anulada' AND os.fecha_ejecucion >= v_hoy) AS proximo_servicio
    FROM   sede_cliente s
    JOIN   cliente c ON c.id_cliente = s.id_cliente AND c.SoftDelete = 0 AND c.estado = 'Activo'
    WHERE  s.SoftDelete = 0 AND s.estado = 'Activo' AND (s.latitud IS NULL OR s.longitud IS NULL)
      AND  (p_id_cliente IS NULL OR s.id_cliente = p_id_cliente)
    ORDER BY servicios_proximos DESC, proximo_servicio IS NULL, proximo_servicio, c.razon_social, s.nombre
    LIMIT 500;
END$$

DELIMITER ;
