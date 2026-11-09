-- HU-60 (Sprint 5) Modal "Detalle de Precotización Técnica" (CRM).
-- Acceso: precot_ver y la precotización en el alcance del usuario (SP_ArmarBasePrecotizaciones).
-- Resultados: 1 mensaje, 2 cabecera (datos, resumen del servicio, propuesta derivada y acciones), 3 observaciones detectadas,
--   4 ítems sugeridos, 5 trazabilidad del flujo comercial (RQ → propuesta de origen → OC → OS → precotización → propuesta derivada).
DROP PROCEDURE IF EXISTS SP_ObtenerDetallePrecotizacion;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerDetallePrecotizacion(
    IN p_id_usuario       BIGINT,
    IN p_id_precotizacion BIGINT
)
proc: BEGIN
    DECLARE v_existe    INT DEFAULT 0;
    DECLARE v_convertir TINYINT DEFAULT 0;
    DECLARE v_numero_rq      VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_fecha_rq       DATETIME;
    DECLARE v_id_prop_origen BIGINT;
    DECLARE v_id_os          BIGINT;
    DECLARE v_numero         VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_fecha          DATETIME;
    DECLARE v_grupo          VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_gen         BIGINT;
    DECLARE v_numero_gen     VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_version_gen    INT;
    DECLARE v_estado_gen     VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_fecha_conv     DATETIME;

    IF FN_PermisoAccion(p_id_usuario, 'precot_ver') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver las precotizaciones técnicas.' AS Mensaje;
        LEAVE proc;
    END IF;
    SET v_convertir = FN_PermisoAccion(p_id_usuario, 'precot_convertir');

    CALL SP_ArmarBasePrecotizaciones(p_id_usuario, IFNULL(p_id_precotizacion, 0));
    SELECT COUNT(*) INTO v_existe FROM tmp_pct_base;
    IF v_existe = 0 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_pct_base;
        SELECT 1 AS IdTipoMensaje, 'La precotización no existe o no está en tu alcance.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Cabecera
    SELECT b.*,
           IF(b.estado_grupo = 'convertida', 'Convertida en Propuesta', 'Pendiente de Cotizar')           AS estado_detalle,
           (v_convertir = 1 AND b.estado_grupo = 'pendiente')                                           AS puede_convertir,
           IF(b.estado_grupo = 'convertida',
              CONCAT('Esta precotización fue convertida en la Propuesta Comercial ', b.numero_propuesta_generada,
                     IF(b.convertido_por IS NULL, '', CONCAT(' por ', b.convertido_por)),
                     IF(b.fecha_conversion IS NULL, '', CONCAT(' el ', DATE_FORMAT(b.fecha_conversion, '%d/%m/%Y %H:%i'))), '.'),
              NULL)                                                                                      AS mensaje_conversion
    FROM tmp_pct_base b;

    -- 3. Observaciones detectadas (del informe de origen)
    SELECT o.id_observacion, o.codigo, o.titulo, o.descripcion, o.ubicacion, o.nivel_afectacion
    FROM informe_observacion o
    JOIN tmp_pct_base b ON b.id_informe = o.id_informe
    WHERE o.eliminado_en IS NULL
    ORDER BY o.orden, o.id_observacion;

    -- 4. Ítems sugeridos
    SELECT pi.id_item, pi.orden, pi.concepto, pi.codigo, pi.id_suministro, pi.descripcion_tecnica, pi.cantidad, pi.unidad,
           pi.prioridad, pi.id_observacion, o.codigo AS codigo_observacion, s.precio_referencia
    FROM precotizacion_item pi
    LEFT JOIN informe_observacion o ON o.id_observacion = pi.id_observacion AND o.eliminado_en IS NULL
    LEFT JOIN suministros s         ON s.id_suministro = pi.id_suministro
    WHERE pi.id_precotizacion = p_id_precotizacion AND pi.eliminado_en IS NULL
    ORDER BY pi.orden, pi.id_item;

    -- 5. Trazabilidad del flujo comercial
    SELECT numero_rq, fecha_rq, id_propuesta_origen, id_os, numero, fecha, estado_grupo,
           id_propuesta_generada, numero_propuesta_generada, version_propuesta_generada, estado_propuesta_generada, fecha_conversion
      INTO v_numero_rq, v_fecha_rq, v_id_prop_origen, v_id_os, v_numero, v_fecha, v_grupo,
           v_id_gen, v_numero_gen, v_version_gen, v_estado_gen, v_fecha_conv
    FROM tmp_pct_base LIMIT 1;

    SELECT x.orden, x.codigo, x.titulo, x.detalle, x.fecha, x.completado, x.actual
    FROM (
        SELECT 1 AS orden, 'rq' AS codigo, CONCAT(v_numero_rq, ' generado') AS titulo, 'Requerimiento de origen' AS detalle,
               v_fecha_rq AS fecha, 1 AS completado, 0 AS actual
        FROM DUAL WHERE v_numero_rq IS NOT NULL
        UNION ALL
        SELECT 2, 'propuesta_origen', CONCAT(p.numero, ' ', IF(p.estado = 'aceptado', 'aceptada', p.estado)),
               'Propuesta del servicio', COALESCE(p.fecha_envio_cliente, p.fecha_creacion), 1, 0
        FROM propuesta_comercial p WHERE p.id_propuesta = v_id_prop_origen
        UNION ALL
        SELECT 3, 'oc', CONCAT(oc.numero_oc, ' emitida'), 'Orden de compra formalizada', COALESCE(oc.fecha_oc, oc.fecha_registro), 1, 0
        FROM orden_compra oc
        WHERE oc.id_oc = (SELECT MIN(o2.id_oc) FROM orden_compra o2
                          WHERE o2.eliminado_en IS NULL AND o2.estado <> 'anulada' AND o2.id_propuesta = v_id_prop_origen)
        UNION ALL
        SELECT 4, 'os', CONCAT(os.numero, ' ejecutada'), 'Servicio en planta', os.fecha_ejecucion, 1, 0
        FROM orden_servicio os WHERE os.id_os = v_id_os
        UNION ALL
        SELECT 5, 'precotizacion', CONCAT('Precotización ', v_numero, ' recibida'),
               IF(v_grupo = 'pendiente', 'Lista para derivar a propuesta', 'Derivada a propuesta'),
               v_fecha, 1, IF(v_grupo = 'pendiente', 1, 0)
        FROM DUAL
        UNION ALL
        SELECT 6, 'propuesta_derivada',
               IF(v_id_gen IS NULL, 'Propuesta derivada', CONCAT(v_numero_gen, ' generada')),
               IF(v_id_gen IS NULL, 'Pendiente', CONCAT('Estado: ', v_estado_gen)),
               v_fecha_conv, IF(v_id_gen IS NULL, 0, 1), IF(v_id_gen IS NULL, 0, 1)
        FROM DUAL
    ) x
    ORDER BY x.orden;

    DROP TEMPORARY TABLE IF EXISTS tmp_pct_base;
END$$

DELIMITER ;
