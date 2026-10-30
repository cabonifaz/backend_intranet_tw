-- HU-24 (Sprint 4) Modal "Detalle de Validación IA" de una vinculación OC ↔ propuesta (informativo).
-- p_id_propuesta NULL = la primera propuesta vinculada (las demás se eligen con las pills, resultado 7).
-- Resultados:
--   1 mensaje
--   2 cabecera: OC y propuesta comparadas, KPIs de la última validación (coincidencias, advertencias, críticas,
--     validaciones corridas), dictamen, confianza, motor y sugerencia
--   3 comparación campo por campo (última validación)
--   4 detalle de conceptos (última validación)
--   5 insights de la IA (última validación; vacío si se validó solo con reglas)
--   6 historial: validaciones corridas, reemplazos de PDF, OC corregidas y correcciones manuales
--   7 propuestas vinculadas (pills para cambiar de propuesta)
DROP PROCEDURE IF EXISTS SP_ObtenerValidacionOrdenCompra;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerValidacionOrdenCompra(
    IN p_id_usuario   BIGINT,
    IN p_id_oc        BIGINT,
    IN p_id_propuesta BIGINT
)
proc: BEGIN
    DECLARE v_existe  INT DEFAULT 0;
    DECLARE v_id_prop BIGINT;
    DECLARE v_id_val  BIGINT;

    IF FN_PermisoAccion(p_id_usuario, 'oc_bandeja') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver las órdenes de compra.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_CalcularOrdenesCompra(p_id_usuario, p_id_oc);
    SELECT COUNT(*) INTO v_existe FROM tmp_oc;
    DROP TEMPORARY TABLE IF EXISTS tmp_oc;
    IF v_existe = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'La orden de compra no existe o no pertenece a tu área.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT op.id_propuesta, op.id_validacion INTO v_id_prop, v_id_val
    FROM oc_propuesta op
    WHERE op.id_oc = p_id_oc AND op.eliminado_en IS NULL
      AND (IFNULL(p_id_propuesta, 0) = 0 OR op.id_propuesta = p_id_propuesta)
    ORDER BY op.id LIMIT 1;

    IF v_id_prop IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'La propuesta no está vinculada a la orden de compra.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- 1. Header
    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Cabecera
    SELECT oc.id_oc, oc.numero_oc, oc.fecha_oc, c.razon_social, c.ruc,
           oc.nombre_archivo_pdf, oc.tamano_pdf_bytes, (oc.url_archivo_pdf IS NOT NULL) AS tiene_pdf,
           p.id_propuesta, p.numero AS numero_propuesta, p.version AS version_propuesta, p.estado AS estado_propuesta,
           (SELECT MAX(s.fecha_interaccion) FROM seguimiento_comercial s WHERE s.id_propuesta = p.id_propuesta
              AND s.estado = 'cerrado_aceptacion' AND s.eliminado_en IS NULL)                              AS fecha_aceptacion,
           (SELECT e.numero FROM expediente_digital e WHERE e.id_expediente = FN_ExpedienteDePropuesta(p.id_propuesta)) AS numero_expediente,
           op.estado_validacion, op.tipo_observacion,
           v.id_validacion, v.corrida, v.origen, v.resultado, v.coincidencias, v.advertencias, v.criticas, v.total_campos,
           (SELECT COUNT(*) FROM orden_compra_validacion v2 WHERE v2.id_oc = p_id_oc AND v2.id_propuesta = v_id_prop) AS validaciones_corridas,
           v.dictamen, v.confianza, v.motor, v.sugerencia, v.fecha_validacion
    FROM orden_compra oc
    JOIN cliente c                    ON c.id_cliente   = oc.id_cliente
    JOIN oc_propuesta op              ON op.id_oc = oc.id_oc AND op.id_propuesta = v_id_prop AND op.eliminado_en IS NULL
    JOIN propuesta_comercial p        ON p.id_propuesta = v_id_prop
    LEFT JOIN orden_compra_validacion v ON v.id_validacion = v_id_val
    WHERE oc.id_oc = p_id_oc;

    -- 3. Comparación campo por campo
    SELECT d.orden, d.campo, d.etiqueta, d.valor_oc, d.valor_propuesta, d.severidad, d.mensaje, d.accion
    FROM orden_compra_validacion v
    JOIN JSON_TABLE(v.detalle, '$[*]' COLUMNS (
            orden           INT          PATH '$.orden',
            campo           VARCHAR(30)  PATH '$.campo',
            etiqueta        VARCHAR(60)  PATH '$.etiqueta',
            valor_oc        VARCHAR(400) PATH '$.valorOc',
            valor_propuesta VARCHAR(400) PATH '$.valorPropuesta',
            severidad       VARCHAR(15)  PATH '$.severidad',
            mensaje         VARCHAR(400) PATH '$.mensaje',
            accion          VARCHAR(200) PATH '$.accion')) d
    WHERE v.id_validacion = IFNULL(v_id_val, 0)
    ORDER BY d.orden;

    -- 4. Conceptos
    SELECT k.descripcion, k.monto_oc, k.monto_propuesta, k.estado
    FROM orden_compra_validacion v
    JOIN JSON_TABLE(v.conceptos, '$[*]' COLUMNS (
            descripcion     VARCHAR(300)  PATH '$.descripcion',
            monto_oc        DECIMAL(14,2) PATH '$.montoOc',
            monto_propuesta DECIMAL(14,2) PATH '$.montoPropuesta',
            estado          VARCHAR(30)   PATH '$.estado')) k
    WHERE v.id_validacion = IFNULL(v_id_val, 0);

    -- 5. Insights de la IA
    SELECT i.campo, i.titulo, i.explicacion, i.accion, IFNULL(i.recomendado, 0) AS recomendado
    FROM orden_compra_validacion v
    JOIN JSON_TABLE(IFNULL(v.insights, JSON_ARRAY()), '$[*]' COLUMNS (
            campo       VARCHAR(30)   PATH '$.campo',
            titulo      VARCHAR(200)  PATH '$.titulo',
            explicacion VARCHAR(2000) PATH '$.explicacion',
            accion      VARCHAR(300)  PATH '$.accion',
            recomendado TINYINT       PATH '$.recomendado')) i
    WHERE v.id_validacion = IFNULL(v_id_val, 0);

    -- 6. Historial
    SELECT h.fecha, h.tipo, h.titulo, h.descripcion, h.resultado, h.coincidencias, h.advertencias, h.criticas,
           IFNULL(CONCAT(u.nombre, ' ', u.apellido), 'Sistema') AS usuario
    FROM (
        SELECT v.fecha_validacion AS fecha, 'validacion' AS tipo,
               CONCAT('Validación #', v.corrida, ' (', REPLACE(v.origen, '_', ' '), ')') AS titulo,
               v.dictamen AS descripcion, v.resultado, v.coincidencias, v.advertencias, v.criticas, v.id_usuario
        FROM orden_compra_validacion v
        WHERE v.id_oc = p_id_oc AND v.id_propuesta = v_id_prop
        UNION ALL
        SELECT a.registrado_en,
               CASE a.accion WHEN 'reemplazar_pdf' THEN 'reemplazo_pdf' WHEN 'subir_oc_corregida' THEN 'oc_corregida'
                             ELSE 'correccion_manual' END,
               CASE a.accion WHEN 'reemplazar_pdf' THEN 'Reemplazo del PDF' WHEN 'subir_oc_corregida' THEN 'OC corregida por el cliente'
                             ELSE 'Corrección manual' END,
               a.descripcion, NULL, NULL, NULL, NULL, a.id_usuario
        FROM auditoria_evento a
        WHERE a.entidad_tipo = 'orden_compra' AND a.id_entidad = p_id_oc
          AND a.accion IN ('reemplazar_pdf', 'subir_oc_corregida', 'corregir_campo_oc')
    ) h
    LEFT JOIN usuario u ON u.id_usuario = h.id_usuario
    ORDER BY h.fecha DESC;

    -- 7. Propuestas vinculadas
    SELECT op.id_propuesta, p.numero, p.version, op.resultado_ia, op.estado_validacion, (op.id_propuesta = v_id_prop) AS seleccionada
    FROM oc_propuesta op JOIN propuesta_comercial p ON p.id_propuesta = op.id_propuesta
    WHERE op.id_oc = p_id_oc AND op.eliminado_en IS NULL
    ORDER BY op.id;
END$$

DELIMITER ;
