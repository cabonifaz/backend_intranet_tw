-- ============================================================
-- SP_ObtenerUbigeoPorCoordenadas  (Maestros › Clientes › Sede: mapa → departamento, provincia y distrito · solo lectura)
-- Traduce una coordenada (pin del mapa) al ubigeo INEI con los polígonos de ubigeo_poligono (migración 115).
--   1. Fuera del recuadro de Perú (latitud -18.5..-0.5, longitud -82..-68)  → 1 'La ubicación debe estar dentro del Perú.'
--   2. Distrito cuyo polígono contiene el punto (si por la simplificación cae en dos, el más pequeño).
--   3. Si no cae en ninguno (borde costero o de un río, por la simplificación de ~50 m): el distrito más cercano a menos de ~1 km (aproximado = 1).
--   4. Si tampoco                                                            → 1 'No se pudo determinar el ubigeo (punto fuera de los distritos del Perú).'
--   Los nombres salen de la tabla ubigeo (los mismos de los selects en cascada); si el código no estuviera ahí, los del polígono.
-- Resultados: 1 mensaje · 2 ubigeo (1 fila).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerUbigeoPorCoordenadas;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerUbigeoPorCoordenadas(
    IN p_latitud  DECIMAL(10,7),
    IN p_longitud DECIMAL(10,7)
)
proc: BEGIN
    DECLARE v_punto      GEOMETRY;
    DECLARE v_caja       GEOMETRY;
    DECLARE v_codigo     CHAR(6) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_aproximado TINYINT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF p_latitud IS NULL OR p_longitud IS NULL OR p_latitud NOT BETWEEN -18.5 AND -0.5 OR p_longitud NOT BETWEEN -82 AND -68 THEN
        SELECT 1 AS IdTipoMensaje, 'La ubicación debe estar dentro del Perú.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM ubigeo_poligono) THEN
        SELECT 1 AS IdTipoMensaje, 'Los límites distritales aún no están cargados. Completa el departamento, la provincia y el distrito a mano.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_punto = POINT(p_longitud, p_latitud);

    SELECT p.codigo INTO v_codigo
    FROM   ubigeo_poligono p
    WHERE  ST_Contains(p.geom, v_punto)
    ORDER BY ST_Area(p.geom), p.codigo
    LIMIT 1;

    IF v_codigo IS NULL THEN
        SET v_caja = ST_Envelope(LINESTRING(POINT(p_longitud - 0.01, p_latitud - 0.01), POINT(p_longitud + 0.01, p_latitud + 0.01)));
        SELECT p.codigo INTO v_codigo
        FROM   ubigeo_poligono p
        WHERE  MBRIntersects(p.geom, v_caja) AND ST_Distance(p.geom, v_punto) <= 0.01
        ORDER BY ST_Distance(p.geom, v_punto), p.codigo
        LIMIT 1;
        SET v_aproximado = 1;
    END IF;

    IF v_codigo IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'No se pudo determinar el ubigeo (punto fuera de los distritos del Perú).' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;
    SELECT LEFT(p.codigo, 2)                        AS departamento_codigo,
           COALESCE(u.departamento, p.departamento) AS departamento,
           LEFT(p.codigo, 4)                        AS provincia_codigo,
           COALESCE(u.provincia, p.provincia)       AS provincia,
           p.codigo                                 AS distrito_codigo,
           COALESCE(u.distrito, p.distrito)         AS distrito,
           v_aproximado                             AS aproximado
    FROM   ubigeo_poligono p
    LEFT JOIN ubigeo u ON u.codigo = p.codigo
    WHERE  p.codigo = v_codigo;
END$$

DELIMITER ;
