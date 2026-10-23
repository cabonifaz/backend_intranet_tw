-- ============================================================
-- SP_ObtenerChecklistSalidaMovil  (App Mobile HU-04 — Checklist de pre-salida)
-- Datos con los que el back arma el checklist (las reglas viven en C#: ReglasChecklistSalida).
-- Solo lectura. Mismo control de acceso que el detalle (OS del técnico que inició sesión).
-- Resultados:
--   1. Encabezado
--   2. Una fila: datos de la tarjeta + estado de cada ítem + autorización vigente
--      + área que autoriza la salida (según la RQ) y su(s) encargado(s)
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerChecklistSalidaMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerChecklistSalidaMovil(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT
)
proc: BEGIN
    IF NOT EXISTS (SELECT 1 FROM orden_servicio os
                   WHERE os.id_os = p_id_os AND os.eliminado_en IS NULL
                     AND (os.id_tecnico_principal = p_id_usuario
                          OR EXISTS (SELECT 1 FROM os_personal op
                                     WHERE op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL))) THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio no encontrado o no asignado a tu usuario.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT os.id_os,
           os.numero                                                        AS numero_os,
           COALESCE(NULLIF(cl.nombre_comercial, ''), cl.razon_social)       AS cliente,
           os.fecha_ejecucion,
           TIME_FORMAT(os.hora_inicio, '%H:%i')                             AS hora_inicio,
           TRIM(CONCAT(IFNULL(tp.nombre, ''), ' ', IFNULL(tp.apellido, '')))  AS tecnico,
           os.estado                                                        AS estado_os,
           os.id_tipo_servicio,
           os.confirmacion_cliente                                          AS cliente_confirmado,
           COALESCE(
               (SELECT op.estado_ssoma FROM os_personal op
                WHERE  op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL LIMIT 1),
               (SELECT CASE WHEN SUM(op.estado_ssoma = 'bloqueado') > 0 THEN 'bloqueado'
                            WHEN SUM(op.estado_ssoma = 'pendiente') > 0 THEN 'pendiente'
                            WHEN COUNT(*) > 0 THEN 'habilitado' END
                FROM   os_personal op WHERE op.id_os = os.id_os AND op.eliminado_en IS NULL),
               'pendiente')                                                 AS estado_ssoma,
           (ed.id_orden_compra IS NOT NULL)                                 AS tiene_oc,
           (SELECT COUNT(*) FROM item_presalida ip
            WHERE  ip.id_os = os.id_os AND ip.id_tipo_item = 1 AND ip.eliminado_en IS NULL)                     AS repuestos_total,
           (SELECT COUNT(*) FROM item_presalida ip
            WHERE  ip.id_os = os.id_os AND ip.id_tipo_item = 1 AND ip.confirmado = 0 AND ip.eliminado_en IS NULL) AS repuestos_pendientes,
           (SELECT COUNT(*) FROM alerta_predictiva ap
            WHERE  ap.id_os = os.id_os AND ap.resuelta = 0 AND ap.eliminado_en IS NULL)                         AS alertas_pendientes,
           -- Confirmaciones del técnico
           IFNULL((SELECT c.confirmado FROM checklist_presalida_os c WHERE c.id_os = os.id_os AND c.codigo = 'expediente'
                   AND c.eliminado_en IS NULL ORDER BY c.id_checklist DESC LIMIT 1), 0)   AS chk_expediente,
           IFNULL((SELECT c.confirmado FROM checklist_presalida_os c WHERE c.id_os = os.id_os AND c.codigo = 'epp'
                   AND c.eliminado_en IS NULL ORDER BY c.id_checklist DESC LIMIT 1), 0)   AS chk_epp,
           IFNULL((SELECT c.confirmado FROM checklist_presalida_os c WHERE c.id_os = os.id_os AND c.codigo = 'materiales'
                   AND c.eliminado_en IS NULL ORDER BY c.id_checklist DESC LIMIT 1), 0)   AS chk_materiales,
           IFNULL((SELECT c.confirmado FROM checklist_presalida_os c WHERE c.id_os = os.id_os AND c.codigo = 'herramientas'
                   AND c.eliminado_en IS NULL ORDER BY c.id_checklist DESC LIMIT 1), 0)   AS chk_herramientas,
           IFNULL((SELECT c.confirmado FROM checklist_presalida_os c WHERE c.id_os = os.id_os AND c.codigo = 'pesas_patron'
                   AND c.eliminado_en IS NULL ORDER BY c.id_checklist DESC LIMIT 1), 0)   AS chk_pesas_patron,
           -- Autorización vigente (la última de la OS)
           au.estado                                                        AS aut_estado,
           au.comentario                                                    AS aut_comentario,
           au.solicitado_en                                                 AS aut_solicitado_en,
           au.resuelto_en                                                   AS aut_resuelto_en,
           NULLIF(TRIM(CONCAT(IFNULL(jf.nombre, ''), ' ', IFNULL(jf.apellido, ''))), '') AS aut_jefe,
           -- Área que autoriza (la de la solicitud vigente o, si no hay, la de la RQ)
           COALESCE(au.area_destino, asr.area_usuario)                      AS area_autoriza_codigo,
           (SELECT t.String1 FROM tabla_maestra t
            WHERE  t.IdMaestro = 79 AND t.IdEmpresa = 1
              AND  t.String2 = COALESCE(au.area_destino, asr.area_usuario) LIMIT 1)          AS area_autoriza,
           (SELECT c.String1 FROM tabla_maestra c
            WHERE  c.IdMaestro = 80 AND c.IdEmpresa = 1 AND c.String2 LIKE 'jefe\_%'
              AND  c.String3 = COALESCE(au.area_destino, asr.area_usuario) LIMIT 1)          AS cargo_encargado,
           (SELECT GROUP_CONCAT(TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))) ORDER BY u.nombre SEPARATOR ', ')
            FROM   usuario u
            JOIN   tabla_maestra c ON c.IdMaestro = 80 AND c.IdEmpresa = 1 AND c.String2 = u.cargo
            WHERE  u.eliminado_en IS NULL AND u.estado = 'activo' AND c.String2 LIKE 'jefe\_%'
              AND  c.String3 = COALESCE(au.area_destino, asr.area_usuario))                 AS encargado_area
    FROM   orden_servicio os
    LEFT JOIN cliente            cl ON cl.id_cliente    = os.id_cliente
    LEFT JOIN usuario            tp ON tp.id_usuario    = os.id_tecnico_principal
    LEFT JOIN expediente_digital ed ON ed.id_expediente = os.id_expediente
    LEFT JOIN autorizacion_salida_os au
           ON au.id_autorizacion = (SELECT MAX(a2.id_autorizacion) FROM autorizacion_salida_os a2
                                    WHERE a2.id_os = os.id_os AND a2.eliminado_en IS NULL)
    LEFT JOIN usuario            jf ON jf.id_usuario    = au.id_jefe
    LEFT JOIN requerimiento      rq ON rq.id_requerimiento = ed.id_requerimiento
    LEFT JOIN area_servicio_rq   asr ON asr.id_area_rq  = rq.id_area
    WHERE  os.id_os = p_id_os;
END$$

DELIMITER ;
