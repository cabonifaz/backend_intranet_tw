-- HU-45 (Sprint 5) Comprobante de un gasto para el modal secundario [Ver imagen/PDF]. Requiere ver la bandeja de programaciones (prog_bandeja).
-- Solo devuelve la URL del comprobante de un gasto de ESA programación. Resultados: 1 mensaje, 2 comprobante.
DROP PROCEDURE IF EXISTS SP_ObtenerComprobanteGasto;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerComprobanteGasto(
    IN p_id_usuario      BIGINT,
    IN p_id_programacion BIGINT,
    IN p_id_gasto        BIGINT
)
proc: BEGIN
    DECLARE v_id_os BIGINT DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            @err_msg  = MESSAGE_TEXT,
            @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF FN_PermisoAccion(p_id_usuario, 'prog_bandeja') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver los comprobantes.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF IFNULL(p_id_programacion, 0) <= 0 OR IFNULL(p_id_gasto, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El comprobante no existe.' AS Mensaje;
        LEAVE proc;
    END IF;
    SELECT id_os INTO v_id_os FROM programacion WHERE id_programacion = p_id_programacion AND eliminado_en IS NULL;
    IF v_id_os IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'La programación no existe.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM gasto_viatico g WHERE g.id_gasto = p_id_gasto AND g.tipo = 'gasto_solicitado' AND g.eliminado_en IS NULL
                   AND NULLIF(TRIM(IFNULL(g.url_comprobante, '')), '') IS NOT NULL
                   AND (g.id_programacion = p_id_programacion OR (g.id_programacion IS NULL AND g.id_os = v_id_os))) THEN
        SELECT 1 AS IdTipoMensaje, 'El gasto no tiene comprobante adjunto.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'OK' AS Mensaje;
    SELECT g.id_gasto, g.url_comprobante AS url, g.monto, g.estado, g.fecha_gasto AS fecha,
           IFNULL(c.String1, 'Gasto') AS concepto, TRIM(CONCAT(u.nombre, ' ', u.apellido)) AS tecnico
    FROM gasto_viatico g
    JOIN usuario u ON u.id_usuario = g.id_usuario
    LEFT JOIN tabla_maestra c ON c.IdMaestro = 25 AND c.IdEmpresa = 1 AND c.Num1 = g.id_concepto
    WHERE g.id_gasto = p_id_gasto;
END$$

DELIMITER ;
