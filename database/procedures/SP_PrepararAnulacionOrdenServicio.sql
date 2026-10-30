-- HU-40 (Sprint 4) Modal "Anular Orden de Servicio": motivos y el impacto de la anulación.
-- Se puede anular en BORRADOR, EMITIDA o PROGRAMADA (no en ejecución ni finalizada: regla por defecto de la HU,
-- pendiente de validar con el cliente). Con programación asignada (Módulo 8) se muestran los recursos que se liberan:
-- técnico asignado, fecha/hora reservada y viáticos asignados.
-- Resultados: 1 mensaje, 2 orden e impacto, 3 personal asignado, 4 motivos (MOTIVO_ANULACION_OS).
DROP PROCEDURE IF EXISTS SP_PrepararAnulacionOrdenServicio;

DELIMITER $$

CREATE PROCEDURE SP_PrepararAnulacionOrdenServicio(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT
)
proc: BEGIN
    DECLARE v_estado VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    SELECT estado INTO v_estado FROM orden_servicio WHERE id_os = p_id_os AND eliminado_en IS NULL;
    IF v_estado IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Orden de servicio no encontrada.' AS Mensaje; LEAVE proc;
    END IF;
    IF FN_PermisoAccion(p_id_usuario, 'os_anular') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para anular órdenes de servicio.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_estado NOT IN ('borrador', 'emitida', 'programada', 'reprogramada') THEN
        SELECT 1 AS IdTipoMensaje, CONCAT('La orden está ', UPPER(REPLACE(v_estado, '_', ' ')), ': ya no se puede anular.') AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT os.id_os, os.numero, os.tipo, os.estado, c.razon_social,
           (os.estado IN ('programada', 'reprogramada') OR os.id_tecnico_principal IS NOT NULL OR os.fecha_ejecucion IS NOT NULL
            OR EXISTS (SELECT 1 FROM os_personal op WHERE op.id_os = os.id_os AND op.eliminado_en IS NULL))   AS tiene_programacion,
           os.id_tecnico_principal, CONCAT(ut.nombre, ' ', ut.apellido)                                       AS tecnico,
           os.fecha_ejecucion, os.hora_inicio, os.hora_fin_estimada,
           (SELECT SUM(g.monto) FROM gasto_viatico g WHERE g.id_os = os.id_os AND g.eliminado_en IS NULL
              AND g.tipo = 'viatico_asignado' AND g.estado IN ('pendiente', 'aprobado'))                     AS viaticos,
           (SELECT MAX(m.String2) FROM gasto_viatico g JOIN tabla_maestra m ON m.IdMaestro = 1 AND m.IdEmpresa = 1 AND m.Num1 = g.id_moneda
            WHERE g.id_os = os.id_os AND g.eliminado_en IS NULL AND g.tipo = 'viatico_asignado')             AS simbolo_moneda
    FROM orden_servicio os
    LEFT JOIN cliente c  ON c.id_cliente  = os.id_cliente
    LEFT JOIN usuario ut ON ut.id_usuario = os.id_tecnico_principal
    WHERE os.id_os = p_id_os;

    SELECT op.id_usuario, CONCAT(u.nombre, ' ', u.apellido) AS nombre, op.rol_en_servicio
    FROM os_personal op JOIN usuario u ON u.id_usuario = op.id_usuario
    WHERE op.id_os = p_id_os AND op.eliminado_en IS NULL
    ORDER BY op.id;

    SELECT Num1 AS id, String1 AS nombre, String2 AS codigo
    FROM tabla_maestra WHERE Descripcion = 'MOTIVO_ANULACION_OS' AND eliminado_en IS NULL ORDER BY Num1;
END$$

DELIMITER ;
