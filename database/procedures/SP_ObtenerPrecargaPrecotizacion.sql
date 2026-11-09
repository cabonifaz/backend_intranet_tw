-- HU-60 (Sprint 5) "Generar Propuesta Comercial" desde una precotización técnica: datos para precargar el wizard de la
-- nueva propuesta (el front abre la propuesta del RQ de origen con estos datos; al guardarla llama a /convertir).
-- Acceso: precot_convertir y la precotización pendiente en el alcance del usuario.
-- Resultados: 1 mensaje, 2 cabecera (RQ, cliente, contacto, sede, OS / expediente de origen, nota del supervisor),
--   3 ítems a inyectar (sección: principal; los de prioridad "opcional" van a la sección opcional), con el precio de referencia
--   del catálogo cuando el concepto viene del maestro de suministros.
DROP PROCEDURE IF EXISTS SP_ObtenerPrecargaPrecotizacion;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerPrecargaPrecotizacion(
    IN p_id_usuario       BIGINT,
    IN p_id_precotizacion BIGINT
)
proc: BEGIN
    DECLARE v_existe INT DEFAULT 0;
    DECLARE v_grupo  VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    IF FN_PermisoAccion(p_id_usuario, 'precot_convertir') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para convertir precotizaciones en propuesta.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_ArmarBasePrecotizaciones(p_id_usuario, IFNULL(p_id_precotizacion, 0));
    SELECT COUNT(*), MAX(estado_grupo) INTO v_existe, v_grupo FROM tmp_pct_base;
    IF v_existe = 0 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_pct_base;
        SELECT 1 AS IdTipoMensaje, 'La precotización no existe o no está en tu alcance.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_grupo = 'convertida' THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_pct_base;
        SELECT 1 AS IdTipoMensaje, 'La precotización ya fue convertida en propuesta.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT b.id_precotizacion, b.numero, b.id_requerimiento, b.numero_rq, b.id_cliente, b.razon_social, b.ruc,
           rq.id_contacto, co.nombres AS contacto, rq.id_sede, b.sede,
           b.id_os, b.numero_os, os.id_expediente, ex.numero AS numero_expediente,
           b.id_supervisor, b.supervisor, b.fecha, b.equipo, b.tipo_servicio,
           COALESCE(b.nota_supervisor, b.diagnostico) AS nota,
           b.items
    FROM tmp_pct_base b
    LEFT JOIN requerimiento rq      ON rq.id_requerimiento = b.id_requerimiento
    LEFT JOIN contacto_cliente co   ON co.id_contacto = rq.id_contacto
    LEFT JOIN orden_servicio os     ON os.id_os = b.id_os
    LEFT JOIN expediente_digital ex ON ex.id_expediente = os.id_expediente;

    SELECT pi.id_item, pi.orden, pi.concepto, pi.codigo, pi.id_suministro,
           CONCAT_WS(' — ', pi.concepto, pi.descripcion_tecnica) AS descripcion,
           pi.descripcion_tecnica, pi.cantidad, pi.unidad, pi.prioridad,
           IF(pi.prioridad = 'opcional', 'opcional', 'principal') AS seccion,
           s.precio_referencia, s.id_moneda AS id_moneda_referencia, o.codigo AS codigo_observacion
    FROM precotizacion_item pi
    LEFT JOIN suministros s         ON s.id_suministro = pi.id_suministro AND s.eliminado_en IS NULL
    LEFT JOIN informe_observacion o ON o.id_observacion = pi.id_observacion AND o.eliminado_en IS NULL
    WHERE pi.id_precotizacion = p_id_precotizacion AND pi.eliminado_en IS NULL
    ORDER BY pi.orden, pi.id_item;

    DROP TEMPORARY TABLE IF EXISTS tmp_pct_base;
END$$

DELIMITER ;
