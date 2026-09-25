-- ============================================================
-- SP_ObtenerCatalogosRequerimiento
-- Catálogos para el formulario de RQ (Origen, Área, Prioridad).
-- Lee directamente de tabla_maestra (IdMaestro 63, 64, 65).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerCatalogosRequerimiento;

DELIMITER //

CREATE PROCEDURE SP_ObtenerCatalogosRequerimiento()
BEGIN
    -- 1. Header
    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Origen (IdMaestro = 63)
    SELECT Num1 AS id, String1 AS nombre
    FROM tabla_maestra
    WHERE IdMaestro = 63 AND IdEmpresa = 1 AND eliminado_en IS NULL
    ORDER BY Num1;

    -- 3. Área (IdMaestro = 64)
    SELECT Num1 AS id, String1 AS nombre
    FROM tabla_maestra
    WHERE IdMaestro = 64 AND IdEmpresa = 1 AND eliminado_en IS NULL
    ORDER BY Num1;

    -- 4. Prioridad (IdMaestro = 65)
    SELECT Num1 AS id, String1 AS nombre
    FROM tabla_maestra
    WHERE IdMaestro = 65 AND IdEmpresa = 1 AND eliminado_en IS NULL
    ORDER BY Num1;
END //

DELIMITER ;
