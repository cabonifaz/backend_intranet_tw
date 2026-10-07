-- Valores ya registrados de un campo (ticket #4290, evitar duplicados).
-- El back los compara con lo que el usuario escribe y avisa si hay alguno parecido.
--   p_campo: tipo_suministro | subtipo | marca | modelo | area_cliente (requiere p_id_cliente)
DROP PROCEDURE IF EXISTS SP_ObtenerValoresExistentes;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerValoresExistentes(
    IN p_campo      VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_cliente BIGINT
)
BEGIN
    IF p_campo = 'tipo_suministro' THEN
        SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;
        SELECT t.String1 AS valor, t.String3 AS detalle,
               (SELECT COUNT(*) FROM suministros s WHERE s.tipo = t.String2 AND s.eliminado_en IS NULL) AS usos
        FROM tabla_maestra t
        WHERE t.IdMaestro = 72 AND t.IdEmpresa = 1;
    ELSEIF p_campo = 'subtipo' THEN
        SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;
        SELECT s.subtipo AS valor, '' AS detalle, COUNT(*) AS usos
        FROM suministros s
        WHERE s.eliminado_en IS NULL AND IFNULL(TRIM(s.subtipo), '') <> ''
        GROUP BY s.subtipo;
    ELSEIF p_campo = 'marca' THEN
        SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;
        SELECT x.valor, '' AS detalle, CAST(SUM(x.usos) AS SIGNED) AS usos
        FROM (SELECT t.String1 AS valor, 0 AS usos FROM tabla_maestra t WHERE t.IdMaestro = 77 AND t.IdEmpresa = 1
              UNION ALL
              SELECT s.marca, COUNT(*) FROM suministros s
              WHERE s.eliminado_en IS NULL AND IFNULL(TRIM(s.marca), '') <> '' GROUP BY s.marca) x
        GROUP BY x.valor;
    ELSEIF p_campo = 'modelo' THEN
        SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;
        SELECT x.valor, '' AS detalle, CAST(SUM(x.usos) AS SIGNED) AS usos
        FROM (SELECT t.String1 AS valor, 0 AS usos FROM tabla_maestra t WHERE t.IdMaestro = 78 AND t.IdEmpresa = 1
              UNION ALL
              SELECT s.modelo, COUNT(*) FROM suministros s
              WHERE s.eliminado_en IS NULL AND IFNULL(TRIM(s.modelo), '') <> '' GROUP BY s.modelo) x
        GROUP BY x.valor;
    ELSEIF p_campo = 'area_cliente' THEN
        SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;
        SELECT a.nombre AS valor, a.estado AS detalle,
               (SELECT COUNT(*) FROM equipo_cliente e
                WHERE e.id_cliente = a.id_cliente AND e.ubicacion_especifica = a.nombre AND e.SoftDelete = 0) AS usos
        FROM area_cliente a
        WHERE a.id_cliente = p_id_cliente AND a.SoftDelete = 0;
    ELSE
        SELECT 1 AS IdTipoMensaje, 'Campo no válido. Use tipo_suministro, subtipo, marca, modelo o area_cliente.' AS Mensaje;
    END IF;
END$$

DELIMITER ;
