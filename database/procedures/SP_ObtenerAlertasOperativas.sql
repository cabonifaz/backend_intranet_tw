-- ============================================================
-- SP_ObtenerAlertasOperativas
-- Alertas operativas del dashboard (data mockeada).
-- Reemplazar con SELECTs reales cuando los módulos estén listos.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerAlertasOperativas;

DELIMITER //

CREATE PROCEDURE SP_ObtenerAlertasOperativas()
BEGIN
    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT * FROM (
        SELECT
            1                       AS id_alerta,
            'ALTA'                  AS nivel,
            'EXP-2024-0887'         AS numero_expediente,
            'Minera Chinalco'       AS cliente,
            'Conformidad'           AS tipo_servicio,
            'Operaciones'           AS area_responsable,
            'Vence en 4 días sin firma del cliente' AS motivo_alerta,
            '4d 2h'                 AS tiempo_detenido,
            'Vencido'               AS estado,
            NOW()                   AS creado_en
        UNION ALL
        SELECT
            2,
            'MEDIA',
            'EXP-2024-0891',
            'Yanacocha S.A.',
            'SSOMA',
            'Sin asignar',
            '3 revisiones de seguridad sin asignar técnico',
            '1d 4h',
            'En curso',
            NOW() - INTERVAL 30 MINUTE
        UNION ALL
        SELECT
            3,
            'CRÍTICA',
            'EXP-2024-0903',
            'Toquepala Mine',
            'SLA',
            'SLA',
            'SLA vencido — requiere atención inmediata',
            '2h 15m',
            'Vencido',
            NOW() - INTERVAL 2 HOUR
    ) AS alertas;
END //

DELIMITER ;
