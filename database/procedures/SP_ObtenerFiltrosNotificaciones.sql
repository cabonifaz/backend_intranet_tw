-- ============================================================
-- SP_ObtenerFiltrosNotificaciones  (HU-90 Centro de Notificaciones — opciones de los filtros de la bandeja)
-- Cuántas notificaciones tiene el usuario (no archivadas / no leídas) por módulo y por tipo, y quiénes se las enviaron.
-- El caso de uso completa el catálogo con las etiquetas (los módulos y tipos sin notificaciones salen con 0).
-- Solo del usuario que inició sesión (el id sale del token). Solo lectura. Requiere la migración 102.
-- Resultados: 1 mensaje · 2 módulos · 3 tipos · 4 remitentes (id_remitente 0 = Sistema).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerFiltrosNotificaciones;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerFiltrosNotificaciones(
    IN p_id_usuario BIGINT
)
proc: BEGIN
    IF IFNULL(p_id_usuario, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no encontrado.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT modulo                                   AS valor,
           SUM(archivado = 0)                       AS total,
           SUM(archivado = 0 AND leido = 0)         AS no_leidas
    FROM   notificacion
    WHERE  id_usuario_destino = p_id_usuario AND eliminado_en IS NULL
    GROUP BY modulo;

    SELECT tipo_notificacion                        AS valor,
           SUM(archivado = 0)                       AS total,
           SUM(archivado = 0 AND leido = 0)         AS no_leidas
    FROM   notificacion
    WHERE  id_usuario_destino = p_id_usuario AND eliminado_en IS NULL
    GROUP BY tipo_notificacion;

    SELECT IFNULL(r.id_usuario, 0)                                                     AS id_remitente,
           IFNULL(MAX(TRIM(CONCAT(r.nombre, ' ', r.apellido))), 'Sistema TotalWeight')  AS remitente,
           COUNT(*)                                                                    AS total
    FROM   notificacion n
    LEFT JOIN usuario r ON r.id_usuario = n.creado_por
    WHERE  n.id_usuario_destino = p_id_usuario AND n.eliminado_en IS NULL
    GROUP BY IFNULL(r.id_usuario, 0)
    ORDER BY (IFNULL(r.id_usuario, 0) = 0) DESC, remitente;
END$$

DELIMITER ;
