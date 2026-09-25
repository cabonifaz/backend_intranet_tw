-- ============================================================
-- SP_ObtenerRequerimientoPorId
-- Devuelve los datos completos de un RQ para el formulario de edición.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerRequerimientoPorId;

DELIMITER //

CREATE PROCEDURE SP_ObtenerRequerimientoPorId(
    IN p_id_requerimiento BIGINT
)
BEGIN
    -- 1. Header
    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Datos reales del RQ
    SELECT
        r.id_requerimiento,
        r.numero,
        r.id_cliente,
        c.razon_social,
        c.ruc,
        r.id_contacto,
        r.id_sede,
        co.nombres                      AS nombre_contacto,
        sc.nombre                       AS nombre_sede,
        CONCAT(u.nombre, ' ', u.apellido) AS responsable,
        r.id_origen,
        tm_orig.String1                 AS origen_label,
        r.id_area,
        tm_area.String1                 AS area_label,
        r.id_prioridad,
        tm_prio.String1                 AS prioridad_label,
        r.fecha_necesidad,
        r.descripcion,
        r.notificar_correo,
        r.requiere_visita,
        r.cliente_deuda,
        r.estado,
        CASE r.estado
            WHEN 'nuevo'         THEN 'Nueva'
            WHEN 'en_proceso'    THEN 'En proceso'
            WHEN 'con_propuesta' THEN 'Con propuesta'
            WHEN 'cerrado'       THEN 'Cerrado'
            WHEN 'anulado'       THEN 'Anulado'
            ELSE r.estado
        END AS estado_label
    FROM requerimiento r
    JOIN cliente c ON c.id_cliente = r.id_cliente
    LEFT JOIN contacto_cliente co ON co.id_contacto = r.id_contacto
    LEFT JOIN sede_cliente sc ON sc.id_sede = r.id_sede AND sc.SoftDelete = 0
    LEFT JOIN usuario u ON u.id_usuario = r.id_usuario_creador
    LEFT JOIN tabla_maestra tm_orig ON tm_orig.IdMaestro = 63 AND tm_orig.Num1 = r.id_origen  AND tm_orig.IdEmpresa = 1
    LEFT JOIN tabla_maestra tm_area ON tm_area.IdMaestro = 64 AND tm_area.Num1 = r.id_area    AND tm_area.IdEmpresa = 1
    LEFT JOIN tabla_maestra tm_prio ON tm_prio.IdMaestro = 65 AND tm_prio.Num1 = r.id_prioridad AND tm_prio.IdEmpresa = 1
    WHERE r.id_requerimiento = p_id_requerimiento
      AND r.eliminado_en IS NULL;
END //

DELIMITER ;
