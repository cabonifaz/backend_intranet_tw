-- ============================================================
-- SP_ObtenerResumenNotificaciones  (HU-90 Centro de Notificaciones — campana del header)
-- Badge rojo + popover: cantidad de no leídas y las 5 últimas no leídas (orden cronológico descendente).
-- Solo del usuario que inició sesión (el id sale del token). Solo lectura. Requiere la migración 102.
-- Resultados: 1 mensaje · 2 no_leidas · 3 filas (mismo formato que la bandeja: SP_ObtenerBandejaNotificaciones).
--   destino_accion / entidad_tipo / id_entidad / destino_tab: a qué elemento lleva "Ir al elemento origen" (NULL = sin enlace).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerResumenNotificaciones;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerResumenNotificaciones(
    IN p_id_usuario BIGINT
)
proc: BEGIN
    IF IFNULL(p_id_usuario, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no encontrado.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT COUNT(*) AS no_leidas
    FROM   notificacion
    WHERE  id_usuario_destino = p_id_usuario AND eliminado_en IS NULL AND archivado = 0 AND leido = 0;

    SELECT n.id_notificacion,
           n.titulo,
           LEFT(n.cuerpo, 160)                                                                    AS resumen,
           n.modulo,
           n.tipo_notificacion                                                                    AS tipo,
           n.prioridad,
           n.leido                                                                                AS leida,
           n.archivado                                                                            AS archivada,
           r.id_usuario                                                                           AS id_remitente,
           IFNULL(TRIM(CONCAT(r.nombre, ' ', r.apellido)), 'Sistema TotalWeight')                 AS remitente,
           IF(r.id_usuario IS NULL, 'S', UPPER(CONCAT(LEFT(r.nombre, 1), LEFT(r.apellido, 1))))   AS iniciales,
           n.fecha_creacion,
           CASE WHEN n.fecha_creacion >= CURDATE()                                     THEN 'hoy'
                WHEN n.fecha_creacion >= CURDATE() - INTERVAL 1 DAY                    THEN 'ayer'
                WHEN n.fecha_creacion >= CURDATE() - INTERVAL WEEKDAY(CURDATE()) DAY   THEN 'semana'
                ELSE 'antiguas' END                                                               AS grupo,
           CASE WHEN n.entidad_tipo IS NULL OR n.id_entidad IS NULL                        THEN NULL
                WHEN n.entidad_tipo = 'orden_servicio' AND n.modulo = 'control_campo'      THEN 'seguimiento.servicio'
                WHEN n.entidad_tipo = 'orden_servicio' AND n.modulo = 'programacion'       THEN 'programacion.os'
                WHEN n.entidad_tipo = 'orden_servicio'                                     THEN 'os.detalle'
                WHEN n.entidad_tipo = 'propuesta' AND n.modulo = 'visto_bueno'             THEN 'vb.detalle'
                WHEN n.entidad_tipo = 'propuesta' AND n.modulo = 'seguimiento'             THEN 'seguimiento.propuesta'
                WHEN n.entidad_tipo = 'propuesta'                                          THEN 'propuesta.detalle'
                WHEN n.entidad_tipo = 'precotizacion'                                      THEN 'propuesta.precotizacion'
                WHEN n.entidad_tipo = 'orden_compra'                                       THEN 'oc.detalle'
                WHEN n.entidad_tipo = 'expediente'                                         THEN 'expediente.detalle'
                WHEN n.entidad_tipo = 'programacion'                                       THEN 'programacion.detalle'
                WHEN n.entidad_tipo = 'informe_tecnico'                                    THEN 'informe.detalle'
                WHEN n.entidad_tipo = 'equipo_cliente'                                     THEN 'equipo.detalle'
                WHEN n.entidad_tipo = 'cliente'                                            THEN 'cliente.detalle'
                ELSE NULL END                                                                     AS destino_accion,
           n.entidad_tipo,
           n.id_entidad,
           IF(n.tipo_notificacion = 'alerta_operativa' AND n.entidad_tipo = 'orden_servicio', 'mapa', NULL) AS destino_tab
    FROM   notificacion n
    LEFT JOIN usuario r ON r.id_usuario = n.creado_por
    WHERE  n.id_usuario_destino = p_id_usuario AND n.eliminado_en IS NULL AND n.archivado = 0 AND n.leido = 0
    ORDER BY n.fecha_creacion DESC, n.id_notificacion DESC
    LIMIT 5;
END$$

DELIMITER ;
