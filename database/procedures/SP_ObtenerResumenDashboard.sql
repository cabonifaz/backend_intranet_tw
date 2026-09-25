-- ============================================================
-- SP_ObtenerResumenDashboard
-- KPIs operativos del dashboard principal (data mockeada).
-- Cuando los módulos estén implementados, reemplazar los
-- valores hardcodeados por SELECTs reales a las tablas.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerResumenDashboard;

DELIMITER //

CREATE PROCEDURE SP_ObtenerResumenDashboard()
BEGIN
    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT
        24    AS servicios_programados,
        12    AS servicios_en_ejecucion,
        5     AS expedientes_bloqueados,
        8     AS pendientes_ssoma,
        15    AS pendientes_conformidad,
        20    AS listos_facturar,
        3     AS sla_vencidos,
        9     AS tecnicos_en_ruta,
        94.2  AS cumplimiento_sla,
        2.4   AS variacion_sla;
END //

DELIMITER ;
