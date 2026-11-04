-- HU-38 (Sprint 5) Datos del modal "Cancelar Programación": programación, orden, viáticos ya depositados que quedarán a disposición de
-- Contabilidad, si hay solicitud de reprogramación pendiente, el largo mínimo del comentario y los motivos tipificados.
-- Solo lectura. Acceso: prog_gestionar. Resultados: 1 mensaje, 2 programación, 3 motivos.
DROP PROCEDURE IF EXISTS SP_PrepararCancelacionProgramacion;

DELIMITER $$

CREATE PROCEDURE SP_PrepararCancelacionProgramacion(
    IN p_id_usuario      BIGINT,
    IN p_id_programacion BIGINT
)
proc: BEGIN
    DECLARE v_id_os    BIGINT DEFAULT NULL;
    DECLARE v_min      DECIMAL(18,6) DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF FN_PermisoAccion(p_id_usuario, 'prog_gestionar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para cancelar programaciones.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT id_os INTO v_id_os FROM programacion WHERE id_programacion = p_id_programacion AND eliminado_en IS NULL;
    IF v_id_os IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'La programación no existe.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_LeerParametroProgramacion('CANCELACION_COMENTARIO_MIN', 0, v_min);

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT pr.id_programacion, pr.codigo, pr.estado,
           CASE pr.estado WHEN 'pendiente_confirmacion' THEN 'Pendiente confirmación cliente'
                          WHEN 'confirmada' THEN 'Programado' ELSE 'Cancelada' END                      AS estado_label,
           os.id_os, os.numero AS numero_os, os.tipo, os.estado AS estado_os, c.razon_social,
           IF(pr.estado <> 'cancelada' AND os.estado IN ('programada', 'reprogramada'), 1, 0)            AS puede_cancelar,
           CASE WHEN pr.estado = 'cancelada' THEN 'La programación ya está cancelada.'
                WHEN os.estado NOT IN ('programada', 'reprogramada') THEN 'El servicio ya empezó: no se cancela desde aquí.'
                ELSE NULL END                                                                             AS motivo_no_cancelable,
           IFNULL((SELECT SUM(g.monto) FROM gasto_viatico g
                   WHERE g.id_os = os.id_os AND g.eliminado_en IS NULL AND g.tipo = 'viatico_asignado' AND g.estado = 'aprobado'), 0) AS viaticos_depositados,
           (SELECT MAX(g.id_moneda) FROM gasto_viatico g
            WHERE g.id_os = os.id_os AND g.eliminado_en IS NULL AND g.tipo = 'viatico_asignado' AND g.estado = 'aprobado')            AS id_moneda,
           (SELECT MAX(rp.id_reprogramacion) FROM os_reprogramacion rp
            WHERE rp.id_programacion = pr.id_programacion AND rp.estado = 'pendiente' AND rp.eliminado_en IS NULL)                     AS id_solicitud_pendiente,
           CAST(v_min AS UNSIGNED)                                                                        AS comentario_minimo,
           500                                                                                            AS comentario_maximo
    FROM programacion pr
    JOIN orden_servicio os ON os.id_os = pr.id_os
    LEFT JOIN cliente c    ON c.id_cliente = os.id_cliente
    WHERE pr.id_programacion = p_id_programacion;

    SELECT t.Num1 AS id_motivo, t.String1 AS nombre, t.String2 AS codigo
    FROM tabla_maestra t
    WHERE t.Descripcion = 'MOTIVO_CANCELACION_PROGRAMACION' AND t.IdEmpresa = 1 AND t.eliminado_en IS NULL
    ORDER BY t.Num1;
END$$

DELIMITER ;
