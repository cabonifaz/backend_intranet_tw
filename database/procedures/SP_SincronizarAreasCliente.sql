-- Reemplaza las áreas asignadas a un cliente (códigos de AREA_USUARIO).
-- p_areas NULL = no cambia nada. Arreglo vacío = quita todas las áreas.
-- No devuelve resultados: lo llama SP_GuardarCliente.
DROP PROCEDURE IF EXISTS SP_SincronizarAreasCliente;

DELIMITER $$

CREATE PROCEDURE SP_SincronizarAreasCliente(
    IN p_id_cliente BIGINT,
    IN p_areas      JSON,
    IN p_usuario    VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
BEGIN
    IF p_areas IS NOT NULL THEN
        DELETE FROM cliente_area WHERE id_cliente = p_id_cliente;

        INSERT IGNORE INTO cliente_area (id_cliente, area, UsuCre, FchCre)
        SELECT p_id_cliente, j.area, p_usuario, NOW()
        FROM JSON_TABLE(p_areas, '$[*]' COLUMNS (area VARCHAR(60) PATH '$')) j
        JOIN tabla_maestra t
          ON t.IdMaestro = 79 AND t.IdEmpresa = 1 AND t.String2 = j.area;
    END IF;
END$$

DELIMITER ;
