-- ============================================================
-- SP_ObtenerNotificacionesNuevas  (HU-90 parte 2 — tiempo real con SignalR)
-- Lo llama el worker de la API (NotificacionesTiempoRealWorker) cada pocos segundos para emitir "notificacion.creada" sin tocar
-- los ~40 SPs que insertan en notificacion. Proceso del sistema: no valida permisos (cada fila va solo a su destinatario).
--   p_desde_id < 0 ... solo inicializa: devuelve el último id y ninguna fila (al arrancar no se reenvía lo antiguo).
--   p_desde_id >= 0 .. filas con id_notificacion > p_desde_id (orden ascendente, máximo p_limite; NULL o < 1 = 1000, tope 5000),
--                      creadas en los últimos 10 minutos y no eliminadas. El worker vuelve a pedir una ventana corta hacia atrás y
--                      descarta las que ya emitió: así no pierde las que se confirmaron (COMMIT) después que otras con id mayor.
-- Lectura por la PK (rango de id). Requiere la migración 102.
-- Resultados: 1 mensaje · 2 ultimo_id · 3 filas (formato de la bandeja + id_usuario_destino + no_leidas de ese destinatario).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerNotificacionesNuevas;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerNotificacionesNuevas(
    IN p_desde_id BIGINT,
    IN p_limite   INT
)
BEGIN
    DECLARE v_ultimo BIGINT DEFAULT 0;
    DECLARE v_desde  BIGINT;
    DECLARE v_limite INT;

    SELECT IFNULL(MAX(id_notificacion), 0) INTO v_ultimo FROM notificacion;

    -- Inicialización: ninguna fila (v_desde = v_ultimo)
    SET v_desde  = IF(IFNULL(p_desde_id, -1) < 0, v_ultimo, p_desde_id);
    SET v_limite = IF(IFNULL(p_limite, 0) < 1, 1000, LEAST(p_limite, 5000));

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT v_ultimo AS ultimo_id;

    SELECT n.id_notificacion,
           n.id_usuario_destino,
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
           IF(n.tipo_notificacion = 'alerta_operativa' AND n.entidad_tipo = 'orden_servicio', 'mapa', NULL) AS destino_tab,
           (SELECT COUNT(*) FROM notificacion c
            WHERE  c.id_usuario_destino = n.id_usuario_destino AND c.eliminado_en IS NULL
              AND  c.archivado = 0 AND c.leido = 0)                                               AS no_leidas
    FROM   notificacion n
    LEFT JOIN usuario r ON r.id_usuario = n.creado_por
    WHERE  n.id_notificacion > v_desde AND n.id_notificacion <= v_ultimo
      AND  n.eliminado_en IS NULL
      AND  n.fecha_creacion >= NOW() - INTERVAL 10 MINUTE
    ORDER BY n.id_notificacion
    LIMIT v_limite;
END$$

DELIMITER ;
