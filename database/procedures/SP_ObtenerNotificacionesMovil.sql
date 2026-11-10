-- ============================================================
-- SP_ObtenerNotificacionesMovil  (App Mobile HU-02 / HU-04 — pestaña Notificaciones)
-- Avisos del usuario que inició sesión (el id sale del token): las 60 más recientes, no eliminadas.
-- Son las mismas de la campana de la intranet (tabla notificacion), con el tipo ya clasificado para el ícono y la acción de la app.
--   tipo (según el título que dejan los demás SP):
--     autorizacion_aprobada   "Autorización de salida aprobada" (y el texto anterior "Visto bueno de salida: …")
--     autorizacion_rechazada  "Autorización de salida rechazada" (y "Salida no autorizada: …")
--     autorizacion_solicitud  "Autorización de salida · …" (le llega al jefe cuando un técnico pide su visto bueno)
--     solicitud_enviada       "Solicitud de autorización enviada" (confirmación para el técnico)
--     gasto_aprobado | gasto_observado | gasto_rechazado   gastos revisados por el Jefe de Operaciones
--     servicio                "Nueva programación: …" (se asignó un servicio)
--     demora                  "Demora en ruta" (le llega a Operaciones)
--     ensayo_critico          "Ensayo con error crítico" (HU-10: le llega al encargado del área; el técnico pidió apoyo o aceptó guardar con una lectura fuera del EMP)
--     evidencia_forzada       "Evidencia forzada" (HU-12: una foto rechazada por la IA que el técnico aceptó con un motivo)
--     equipo_nuevo            "Equipo nuevo por aprobar" (HU-07: equipo NEW registrado en campo)
--     servicio_detenido       "Servicio detenido: …" (Control de Campo)
--     alerta_campo            otra alerta operativa del Control de Campo (tipo_notificacion = alerta_operativa)
--     general                 cualquier otro
--   critica / prioridad: la prioridad que ya clasifica el Centro de Notificaciones (HU-90, migración 102_centro_notificaciones: columna
--     notificacion.prioridad = critica | alta | normal). Es lo que filtra "Críticas" en la pestaña Notificaciones del jefe. No se repite la regla aquí.
--   Las archivadas en la intranet no se muestran.
--   pendientes_aprobados: solo en autorizacion_aprobada, los pendientes con los que el jefe autorizó la salida.
--   entidad_tipo / id_entidad: a qué abre la app ('orden_servicio' = el detalle del servicio).
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerNotificacionesMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerNotificacionesMovil(
    IN p_id_usuario BIGINT
)
proc: BEGIN
    IF NOT EXISTS (SELECT 1 FROM usuario WHERE id_usuario = p_id_usuario AND eliminado_en IS NULL) THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no encontrado.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT x.id_notificacion, x.tipo, x.titulo, x.cuerpo, x.entidad_tipo, x.id_entidad, x.leida, x.fecha_creacion,
           x.prioridad, IF(x.prioridad = 'critica', 1, 0) AS critica,
           CASE WHEN x.tipo = 'autorizacion_aprobada' AND x.entidad_tipo = 'orden_servicio'
                THEN (SELECT a.pendientes FROM autorizacion_salida_os a
                      WHERE  a.id_os = x.id_entidad AND a.eliminado_en IS NULL
                      ORDER BY a.id_autorizacion DESC LIMIT 1)
           END AS pendientes_aprobados
    FROM (
        SELECT n.id_notificacion,
               CASE WHEN n.titulo LIKE 'Autorización de salida aprobada%' OR n.titulo LIKE 'Visto bueno de salida%'     THEN 'autorizacion_aprobada'
                    WHEN n.titulo LIKE 'Autorización de salida rechazada%' OR n.titulo LIKE 'Salida no autorizada%'     THEN 'autorizacion_rechazada'
                    WHEN n.titulo LIKE 'Solicitud de autorización enviada%'                                             THEN 'solicitud_enviada'
                    WHEN n.titulo LIKE 'Autorización de salida%'                                                        THEN 'autorizacion_solicitud'
                    WHEN n.titulo LIKE 'Gasto aprobado%'                                                                THEN 'gasto_aprobado'
                    WHEN n.titulo LIKE 'Gasto observado%'                                                               THEN 'gasto_observado'
                    WHEN n.titulo LIKE 'Gasto rechazado%'                                                               THEN 'gasto_rechazado'
                    WHEN n.titulo LIKE 'Nueva programación%' OR n.titulo LIKE 'Nuevo servicio%'                         THEN 'servicio'
                    WHEN n.titulo LIKE 'Demora en ruta%'                                                                THEN 'demora'
                    WHEN n.titulo LIKE 'Ensayo con error cr%'                                                           THEN 'ensayo_critico'
                    WHEN n.titulo LIKE 'Evidencia forzada%'                                                             THEN 'evidencia_forzada'
                    WHEN n.titulo LIKE 'Equipo nuevo por aprobar%'                                                      THEN 'equipo_nuevo'
                    WHEN n.titulo LIKE 'Servicio detenido:%'                                                            THEN 'servicio_detenido'
                    WHEN n.tipo_notificacion = 'alerta_operativa'                                                       THEN 'alerta_campo'
                    ELSE 'general' END AS tipo,
               n.titulo,
               n.cuerpo,
               n.entidad_tipo,
               n.id_entidad,
               n.leido                AS leida,
               n.fecha_creacion,
               n.prioridad
        FROM   notificacion n
        WHERE  n.id_usuario_destino = p_id_usuario AND n.eliminado_en IS NULL AND n.archivado = 0
        ORDER BY n.fecha_creacion DESC, n.id_notificacion DESC
        LIMIT 60
    ) x
    ORDER BY x.fecha_creacion DESC, x.id_notificacion DESC;
END$$

DELIMITER ;
