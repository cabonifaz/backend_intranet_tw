-- ============================================================
-- SP_ObtenerCatalogosRequerimiento
-- Catálogos para el formulario de RQ (Origen, Área, Prioridad).
-- Mock: devuelve los valores que ya están en tabla_maestra.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerCatalogosRequerimiento;

DELIMITER //

CREATE PROCEDURE SP_ObtenerCatalogosRequerimiento()
BEGIN
    -- 1. Header
    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Origen (IdMaestro = 63)
    SELECT Num1 AS id_item, String1 AS label
    FROM (
        SELECT 1 AS Num1, 'Llamada telefónica'  AS String1
        UNION ALL SELECT 2, 'Correo electrónico'
        UNION ALL SELECT 3, 'WhatsApp'
        UNION ALL SELECT 4, 'Visita presencial'
        UNION ALL SELECT 5, 'Plataforma extranet'
    ) AS origen
    ORDER BY Num1;

    -- 3. Área (IdMaestro = 64)
    SELECT Num1 AS id_item, String1 AS label
    FROM (
        SELECT 1 AS Num1, 'Calibración'    AS String1
        UNION ALL SELECT 2, 'Mantenimiento'
        UNION ALL SELECT 3, 'Metrología'
        UNION ALL SELECT 4, 'Soporte técnico'
        UNION ALL SELECT 5, 'Instalación'
    ) AS area
    ORDER BY Num1;

    -- 4. Prioridad (IdMaestro = 65)
    SELECT Num1 AS id_item, String1 AS label
    FROM (
        SELECT 1 AS Num1, 'Alta'  AS String1
        UNION ALL SELECT 2, 'Media'
        UNION ALL SELECT 3, 'Baja'
    ) AS prioridad
    ORDER BY Num1;
END //

DELIMITER ;
