-- ============================================================
-- SP_ObtenerDetalleNotificacion  (HU-90 Centro de Notificaciones — panel de detalle derecho)
-- Devuelve la notificación completa y, como pide la HU, la MARCA COMO LEÍDA al abrirla (si aún no lo estaba).
-- Solo una notificación del usuario que inició sesión (el id sale del token): una ajena responde "no encontrada" (sin IDOR).
-- Requiere la migración 102.
-- Resultados: 1 mensaje · 2 la notificación (formato de fila + mensaje completo + fecha_lectura + no_leidas).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerDetalleNotificacion;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerDetalleNotificacion(
    IN p_id_usuario      BIGINT,
    IN p_id_notificacion BIGINT
)
proc: BEGIN
    DECLARE v_no_leidas INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no encontrado.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF IFNULL(p_id_notificacion, 0) <= 0
       OR NOT EXISTS (SELECT 1 FROM notificacion
                      WHERE id_notificacion = p_id_notificacion AND id_usuario_destino = p_id_usuario AND eliminado_en IS NULL) THEN
        SELECT 1 AS IdTipoMensaje, 'Notificación no encontrada.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Al abrirla se marca como leída (no leída → leída)
    UPDATE notificacion
    SET    leido = 1, fecha_lectura = NOW(), modificado_por = p_id_usuario
    WHERE  id_notificacion = p_id_notificacion AND id_usuario_destino = p_id_usuario AND eliminado_en IS NULL AND leido = 0;

    SELECT COUNT(*) INTO v_no_leidas
    FROM   notificacion
    WHERE  id_usuario_destino = p_id_usuario AND eliminado_en IS NULL AND archivado = 0 AND leido = 0;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT n.id_notificacion,
           n.titulo,
           LEFT(n.cuerpo, 160)                                                                    AS resumen,
           n.cuerpo                                                                               AS mensaje,
           n.modulo,
           n.tipo_notificacion                                                                    AS tipo,
           n.prioridad,
           n.leido                                                                                AS leida,
           n.archivado                                                                            AS archivada,
           n.fecha_lectura,
           n.fecha_archivado,
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
           v_no_leidas                                                                            AS no_leidas
    FROM   notificacion n
    LEFT JOIN usuario r ON r.id_usuario = n.creado_por
    WHERE  n.id_notificacion = p_id_notificacion;
END$$

DELIMITER ;
