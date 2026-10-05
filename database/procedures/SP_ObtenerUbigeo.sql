-- Ubigeo INEI en cascada: departamentos → provincias → distritos (sedes del cliente)
--   p_nivel = 'departamentos'                         → lista de departamentos
--   p_nivel = 'provincias' + p_departamento           → provincias del departamento
--   p_nivel = 'distritos'  + p_departamento + p_provincia → distritos (con código ubigeo)
DROP PROCEDURE IF EXISTS SP_ObtenerUbigeo;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerUbigeo(
    IN p_nivel        VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_departamento VARCHAR(60) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_provincia    VARCHAR(60) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
BEGIN
    IF p_nivel = 'departamentos' THEN
        SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;
        SELECT LEFT(MIN(codigo), 2) AS codigo, departamento AS nombre
        FROM ubigeo GROUP BY departamento ORDER BY departamento;
    ELSEIF p_nivel = 'provincias' THEN
        SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;
        SELECT LEFT(MIN(codigo), 4) AS codigo, provincia AS nombre
        FROM ubigeo WHERE departamento = p_departamento
        GROUP BY provincia ORDER BY provincia;
    ELSEIF p_nivel = 'distritos' THEN
        SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;
        SELECT codigo, distrito AS nombre
        FROM ubigeo WHERE departamento = p_departamento AND provincia = p_provincia
        ORDER BY distrito;
    ELSE
        SELECT 1 AS IdTipoMensaje, 'Nivel no válido. Use departamentos, provincias o distritos.' AS Mensaje;
    END IF;
END$$

DELIMITER ;
