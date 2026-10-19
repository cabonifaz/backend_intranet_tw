-- Consulta de RUC — consumo por mes y proveedor (llamadas externas reales)
--   p_meses = cuántos meses hacia atrás incluir (incluye el actual)
DROP PROCEDURE IF EXISTS SP_ObtenerUsoConsultaRuc;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerUsoConsultaRuc(
    IN p_meses INT
)
BEGIN
    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT DATE_FORMAT(l.FchCre, '%Y-%m')                     AS periodo,
           l.proveedor,
           COUNT(*)                                            AS llamadas,
           SUM(l.resultado = 'encontrado')                     AS encontrados,
           SUM(l.resultado = 'no_encontrado')                  AS no_encontrados,
           SUM(l.resultado = 'limite')                         AS limitados,
           SUM(l.resultado = 'error')                          AS errores,
           ROUND(AVG(l.duracion_ms))                           AS duracion_promedio_ms
    FROM consulta_ruc_log l
    WHERE l.SoftDelete = 0
      AND l.FchCre >= DATE_FORMAT(NOW() - INTERVAL (GREATEST(IFNULL(p_meses, 1), 1) - 1) MONTH, '%Y-%m-01')
    GROUP BY DATE_FORMAT(l.FchCre, '%Y-%m'), l.proveedor
    ORDER BY periodo DESC, l.proveedor;

    SELECT COUNT(*) AS rucs_en_cache FROM consulta_ruc WHERE SoftDelete = 0;
END$$

DELIMITER ;
