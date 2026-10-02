-- ============================================================
-- SP_ObtenerNotificaciones
-- Notificaciones del topbar (data mockeada).
-- Reemplazar con SELECTs reales cuando los módulos estén listos.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerNotificaciones;

DELIMITER //

CREATE PROCEDURE SP_ObtenerNotificaciones(
    IN p_id_usuario BIGINT
)
BEGIN
    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT * FROM (
        SELECT
            1                   AS id_notificacion,
            'SLA_VENCIDO'       AS tipo,
            'SLA CRÍTICO VENCIDO' AS titulo,
            'El expediente EXP-2024-012 (Refinería Talara) excedió el tiempo límite. Se requiere repuesto urgente.' AS cuerpo,
            '#E31B23'           AS tipo_dot,
            'Hace 2m'           AS tiempo,
            0                   AS leida,
            NOW()               AS creado_en
        UNION ALL
        SELECT
            2,
            'BLOQUEADO',
            'EXPEDIENTE BLOQUEADO',
            'EXP-2024-001 (Minera Antamina) ha sido bloqueado en SSOMA por falta de SCTR vigente.',
            '#D97706',
            'Hace 15m',
            0,
            NOW() - INTERVAL 15 MINUTE
        UNION ALL
        SELECT
            3,
            'DEMORA',
            'DEMORA EN RUTA',
            'El técnico asignado para EXP-2024-005 (Aceros Arequipa) reporta tráfico pesado en la Panamericana.',
            '#2563EB',
            'Hace 45m',
            1,
            NOW() - INTERVAL 45 MINUTE
        UNION ALL
        SELECT
            4,
            'FACTURACION',
            'LISTO PARA FACTURAR',
            'La conformidad para EXP-2024-008 ha sido aprobada. Expediente listo para emisión de factura.',
            '#059669',
            'Hace 2h',
            1,
            NOW() - INTERVAL 2 HOUR
        UNION ALL
        SELECT
            5,
            'SISTEMA',
            'NUEVO SERVICIO ASIGNADO',
            'Se ha registrado un requerimiento de Calibración de Balanzas de plataforma de Cerro Verde.',
            '#6B7280',
            'Hace 4h',
            1,
            NOW() - INTERVAL 4 HOUR
    ) AS notificaciones;
END //

DELIMITER ;
