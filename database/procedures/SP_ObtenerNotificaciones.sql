-- ============================================================
-- SP_ObtenerNotificaciones
-- Notificaciones del topbar del usuario autenticado.
-- Trae las 20 más recientes no eliminadas, ordenadas por fecha de creación DESC.
-- El campo `tiempo` se calcula en runtime en formato humano ("Hace 2m", "Hace 1h", "Hace 3d").
-- El `tipo_dot` sale del canal (verde/azul/ámbar/rojo/gris según severidad).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerNotificaciones;

DELIMITER //

CREATE PROCEDURE SP_ObtenerNotificaciones(
    IN p_id_usuario BIGINT
)
BEGIN
    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT
        n.id_notificacion,
        CASE
            WHEN n.entidad_tipo IS NOT NULL THEN UPPER(n.entidad_tipo)
            ELSE 'SISTEMA'
        END                                             AS tipo,
        n.titulo,
        n.cuerpo,
        CASE n.id_canal
            WHEN 1 THEN '#E31B23'  -- correo urgente / crítico
            WHEN 2 THEN '#D97706'  -- SMS / alerta
            WHEN 3 THEN '#059669'  -- éxito
            WHEN 4 THEN '#6B7280'  -- sistema / informativo
            WHEN 5 THEN '#2563EB'  -- plataforma (campana)
            ELSE        '#6B7280'
        END                                             AS tipo_dot,
        CASE
            WHEN TIMESTAMPDIFF(MINUTE, n.fecha_creacion, NOW()) < 1  THEN 'Ahora'
            WHEN TIMESTAMPDIFF(MINUTE, n.fecha_creacion, NOW()) < 60 THEN CONCAT('Hace ', TIMESTAMPDIFF(MINUTE, n.fecha_creacion, NOW()), 'm')
            WHEN TIMESTAMPDIFF(HOUR,   n.fecha_creacion, NOW()) < 24 THEN CONCAT('Hace ', TIMESTAMPDIFF(HOUR,   n.fecha_creacion, NOW()), 'h')
            WHEN TIMESTAMPDIFF(DAY,    n.fecha_creacion, NOW()) < 7  THEN CONCAT('Hace ', TIMESTAMPDIFF(DAY,    n.fecha_creacion, NOW()), 'd')
            ELSE DATE_FORMAT(n.fecha_creacion, '%d/%m/%Y')
        END                                             AS tiempo,
        n.leido                                          AS leida,
        n.fecha_creacion                                 AS creado_en
    FROM notificacion n
    WHERE n.id_usuario_destino = p_id_usuario
      AND n.eliminado_en IS NULL
    ORDER BY n.fecha_creacion DESC
    LIMIT 20;
END //

DELIMITER ;
