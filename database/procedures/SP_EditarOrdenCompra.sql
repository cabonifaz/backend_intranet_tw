-- HU-25/26 (Sprint 4) Editar la OC desde la ficha: datos, propuestas vinculadas (agregar, quitar, cambiar monto o
-- reemplazar por la versión nueva aceptada: "Validar contra propuesta") y, opcionalmente, el PDF.
-- Vuelve a validar contra todas las propuestas vinculadas y aplica la decisión del comercial (como al registrar).
-- p_tipo_pdf (si llega un PDF): reemplazo (reemplazar PDF) u oc_corregida (subir la OC corregida por el cliente).
-- Reglas: acción oc_editar; OC del área del usuario, no anulada, no autogenerada; p_motivo_pdf obligatorio si hay PDF.
-- Resultados: 1 mensaje, 2 OC, 3 vinculaciones.
DROP PROCEDURE IF EXISTS SP_EditarOrdenCompraInterno;

DELIMITER $$

CREATE PROCEDURE SP_EditarOrdenCompraInterno(
    IN p_id_usuario       BIGINT,
    IN p_id_oc            BIGINT,
    IN p_datos            JSON,
    IN p_vinculaciones    JSON,
    IN p_evaluaciones_ia  JSON,
    IN p_decision         VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_tipo_pdf         VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_motivo_pdf       VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_ruta_pdf         VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_nombre_pdf       VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_tamano_pdf       BIGINT,
    IN p_hash_pdf         CHAR(64)     CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_tc          DECIMAL(12,6);
    DECLARE v_existe     INT DEFAULT 0;
    DECLARE v_estado     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_auto       TINYINT;
    DECLARE v_id_cliente BIGINT;
    DECLARE v_error      VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_hay_pdf    TINYINT;
    DECLARE v_version    INT;
    DECLARE v_cambios    VARCHAR(1000) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_numero_oc  VARCHAR(50)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_monto      DECIMAL(14,2);
    DECLARE v_n          INT;
    DECLARE v_i          INT DEFAULT 1;
    DECLARE v_id_prop    BIGINT;
    DECLARE v_asignado   DECIMAL(14,2);
    DECLARE v_eval       JSON;
    DECLARE v_id_val     BIGINT;
    DECLARE v_res        VARCHAR(20);
    DECLARE v_sug        VARCHAR(30);
    DECLARE v_viejos     JSON;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_oc_eval;
        DROP TEMPORARY TABLE IF EXISTS tmp_oc_cmp;
        DROP TEMPORARY TABLE IF EXISTS tmp_oc_disp;
        DROP TEMPORARY TABLE IF EXISTS tmp_oc;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF FN_PermisoAccion(p_id_usuario, 'oc_editar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para editar órdenes de compra.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_CalcularOrdenesCompra(p_id_usuario, p_id_oc);
    SELECT COUNT(*), MAX(estado), MAX(es_autogenerada), MAX(id_cliente) INTO v_existe, v_estado, v_auto, v_id_cliente
    FROM tmp_oc;
    DROP TEMPORARY TABLE IF EXISTS tmp_oc;

    IF v_existe = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'La orden de compra no existe o no pertenece a tu área.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_estado = 'anulada' THEN
        SELECT 1 AS IdTipoMensaje, 'La orden de compra está anulada: no se puede editar.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF EXISTS (SELECT 1 FROM orden_compra WHERE id_oc = p_id_oc AND reemplazada_por IS NOT NULL) THEN
        SELECT 1 AS IdTipoMensaje, 'La orden de compra fue reemplazada por otra OC del cliente: es de solo lectura.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_auto = 1 THEN
        SELECT 1 AS IdTipoMensaje, 'La OC autogenerada no se edita: reemplázala por la OC del cliente.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF p_decision IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Indique qué hacer con la orden de compra (validar, observar, solicitar corrección o nueva versión).' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_hay_pdf = (NULLIF(TRIM(IFNULL(p_ruta_pdf, '')), '') IS NOT NULL);
    IF v_hay_pdf = 1 AND IFNULL(p_tipo_pdf, '') NOT IN ('reemplazo', 'oc_corregida') THEN
        SELECT 1 AS IdTipoMensaje, 'Indique si el PDF es un reemplazo o la OC corregida por el cliente.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_hay_pdf = 1 AND CHAR_LENGTH(TRIM(IFNULL(p_motivo_pdf, ''))) < 5 THEN
        SELECT 1 AS IdTipoMensaje, 'Indique el motivo del cambio de PDF (mínimo 5 caracteres).' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_EvaluarDatosOrdenCompra(p_id_usuario, p_id_oc, p_id_oc, v_id_cliente, p_datos, p_vinculaciones,
                                    p_evaluaciones_ia, p_decision, v_error);
    IF v_error IS NOT NULL THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_oc_eval;
        SELECT 1 AS IdTipoMensaje, v_error AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_numero_oc = FN_JsonTexto(p_datos, '$.numeroOc');
    SET v_monto     = CAST(FN_JsonTexto(p_datos, '$.montoTotal') AS DECIMAL(14,2));
    SET v_viejos    = FN_DatosOrdenCompraJson(p_id_oc);
    -- Tipo de cambio: solo se guarda si alguna propuesta vinculada está en otra moneda (ticket E)
    SET v_tc        = IF(EXISTS (SELECT 1 FROM tmp_oc_eval WHERE monto_cubierto IS NOT NULL),
                         CAST(FN_JsonTexto(p_datos, '$.tipoCambio') AS DECIMAL(12,6)), NULL);

    START TRANSACTION;

    SELECT estado INTO v_estado FROM orden_compra WHERE id_oc = p_id_oc FOR UPDATE;

    -- Campos que cambian (para el timeline)
    SELECT CONCAT_WS(', ',
               IF(NOT (FN_JsonTexto(v_viejos, '$.numeroOc')       <=> v_numero_oc), 'N° OC', NULL),
               IF(NOT (CAST(FN_JsonTexto(v_viejos, '$.montoTotal') AS DECIMAL(14,2)) <=> v_monto), 'monto', NULL),
               IF(NOT (FN_JsonTexto(v_viejos, '$.idMoneda')       <=> FN_JsonTexto(p_datos, '$.idMoneda')), 'moneda', NULL),
               IF(NOT (CAST(FN_JsonTexto(v_viejos, '$.tipoCambio') AS DECIMAL(12,6))
                       <=> v_tc), 'tipo de cambio', NULL),
               IF(NOT (FN_JsonTexto(v_viejos, '$.ruc')            <=> NULLIF(REGEXP_REPLACE(IFNULL(FN_JsonTexto(p_datos, '$.ruc'), ''), '[^0-9]', ''), '')), 'RUC', NULL),
               IF(NOT (FN_JsonTexto(v_viejos, '$.razonSocial')    <=> FN_JsonTexto(p_datos, '$.razonSocial')), 'razón social', NULL),
               IF(NOT (JSON_LENGTH(IFNULL(JSON_EXTRACT(v_viejos, '$.conceptos'), JSON_ARRAY()))
                       <=> JSON_LENGTH(IFNULL(JSON_EXTRACT(p_datos, '$.conceptos'), JSON_ARRAY()))), 'conceptos', NULL),
               IF(NOT (FN_JsonTexto(v_viejos, '$.fechaEmision')   <=> LEFT(FN_JsonTexto(p_datos, '$.fechaEmision'), 10)), 'fecha de emisión', NULL),
               IF(NOT (FN_JsonTexto(v_viejos, '$.fechaRecepcion') <=> LEFT(FN_JsonTexto(p_datos, '$.fechaRecepcion'), 10)), 'fecha de recepción', NULL),
               IF(NOT (FN_JsonTexto(v_viejos, '$.idCondicionPago') <=> FN_JsonTexto(p_datos, '$.idCondicionPago')), 'forma de pago', NULL),
               IF(NOT (FN_JsonTexto(v_viejos, '$.facturaIgualOc') <=> IFNULL(FN_JsonTexto(p_datos, '$.facturaIgualOc'), 'true')), '¿factura = OC?', NULL),
               IF(NOT (FN_JsonTexto(v_viejos, '$.observaciones')  <=> FN_JsonTexto(p_datos, '$.observaciones')), 'observaciones', NULL))
      INTO v_cambios;

    UPDATE orden_compra SET
        numero_oc            = v_numero_oc,
        referencia           = FN_JsonTexto(p_datos, '$.referencia'),
        ruc_cliente_oc       = NULLIF(REGEXP_REPLACE(IFNULL(FN_JsonTexto(p_datos, '$.ruc'), ''), '[^0-9]', ''), ''),
        razon_social_oc      = FN_JsonTexto(p_datos, '$.razonSocial'),
        numero_propuesta_ref = FN_JsonTexto(p_datos, '$.numeroPropuesta'),
        id_moneda            = CAST(FN_JsonTexto(p_datos, '$.idMoneda') AS SIGNED),
        monto_total          = v_monto,
        tipo_cambio          = v_tc,
        id_condicion_pago    = CAST(FN_JsonTexto(p_datos, '$.idCondicionPago') AS SIGNED),
        forma_pago           = FN_JsonTexto(p_datos, '$.formaPago'),
        igv_incluido         = CASE LOWER(IFNULL(FN_JsonTexto(p_datos, '$.igvIncluido'), '')) WHEN 'true' THEN 1 WHEN '1' THEN 1
                                                                                              WHEN 'false' THEN 0 WHEN '0' THEN 0 END,
        igv_pct              = CAST(FN_JsonTexto(p_datos, '$.igvPct') AS DECIMAL(5,2)),
        descuento_monto      = CAST(FN_JsonTexto(p_datos, '$.descuento') AS DECIMAL(14,2)),
        factura_igual_oc     = IF(LOWER(IFNULL(FN_JsonTexto(p_datos, '$.facturaIgualOc'), 'true')) IN ('false', '0'), 0, 1),
        fecha_oc             = STR_TO_DATE(LEFT(FN_JsonTexto(p_datos, '$.fechaEmision'), 10), '%Y-%m-%d'),
        fecha_recepcion      = STR_TO_DATE(LEFT(FN_JsonTexto(p_datos, '$.fechaRecepcion'), 10), '%Y-%m-%d'),
        vigencia_hasta       = STR_TO_DATE(LEFT(FN_JsonTexto(p_datos, '$.vigenciaHasta'), 10), '%Y-%m-%d'),
        observaciones        = FN_JsonTexto(p_datos, '$.observaciones'),
        conceptos            = JSON_EXTRACT(p_datos, '$.conceptos'),
        campos_ia            = IF(JSON_EXTRACT(p_datos, '$.camposIa') IS NULL, campos_ia, JSON_EXTRACT(p_datos, '$.camposIa')),
        campos_manuales      = JSON_EXTRACT(p_datos, '$.camposManuales'),
        id_propuesta         = (SELECT id_propuesta FROM tmp_oc_eval WHERE orden = 1),
        modificado_por       = p_id_usuario
    WHERE id_oc = p_id_oc;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion,
                                  id_usuario, registrado_en, metadata)
    VALUES ('orden_compra', p_id_oc, 'editar_oc', v_estado, NULL,
            CONCAT('Orden de compra editada', IF(IFNULL(v_cambios, '') = '', '.', CONCAT(': ', v_cambios, '.'))),
            p_id_usuario, NOW(), JSON_OBJECT('antes', v_viejos));

    -- Correcciones manuales nuevas (las que no estaban guardadas)
    IF JSON_EXTRACT(p_datos, '$.camposManuales') IS NOT NULL AND JSON_TYPE(JSON_EXTRACT(p_datos, '$.camposManuales')) = 'ARRAY' THEN
        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion,
                                      id_usuario, registrado_en, metadata)
        SELECT 'orden_compra', p_id_oc, 'corregir_campo_oc', LEFT(j.valor_ia, 80), LEFT(j.valor_nuevo, 80),
               CONCAT('Corrección manual de ', IFNULL(j.campo, 'un campo'), ': "', IFNULL(j.valor_ia, '-'),
                      '" → "', IFNULL(j.valor_nuevo, '-'), '".'),
               p_id_usuario, NOW(), JSON_OBJECT('campo', j.campo, 'valor_ia', j.valor_ia, 'valor_nuevo', j.valor_nuevo)
        FROM JSON_TABLE(JSON_EXTRACT(p_datos, '$.camposManuales'), '$[*]' COLUMNS (
                campo       VARCHAR(60)  PATH '$.campo',
                valor_ia    VARCHAR(400) PATH '$.valorIa',
                valor_nuevo VARCHAR(400) PATH '$.valorNuevo')) j
        WHERE NOT EXISTS (SELECT 1 FROM auditoria_evento a
                          WHERE a.entidad_tipo = 'orden_compra' AND a.id_entidad = p_id_oc AND a.accion = 'corregir_campo_oc'
                            AND JSON_UNQUOTE(JSON_EXTRACT(a.metadata, '$.campo')) <=> j.campo
                            AND JSON_UNQUOTE(JSON_EXTRACT(a.metadata, '$.valor_nuevo')) <=> j.valor_nuevo);
    END IF;

    -- PDF nuevo (reemplazo u OC corregida)
    IF v_hay_pdf = 1 THEN
        SELECT IFNULL(MAX(version), 0) + 1 INTO v_version
        FROM documento_adjunto WHERE entidad_tipo = 'orden_compra' AND id_entidad = p_id_oc;

        UPDATE orden_compra SET url_archivo_pdf = p_ruta_pdf, nombre_archivo_pdf = p_nombre_pdf,
                                tamano_pdf_bytes = p_tamano_pdf, hash_pdf = p_hash_pdf
        WHERE id_oc = p_id_oc;

        INSERT INTO documento_adjunto (entidad_tipo, id_entidad, id_tipo_documento, nombre_archivo, url_archivo,
                                       version, id_visibilidad, metadatos, subido_por, fecha_carga, creado_por)
        VALUES ('orden_compra', p_id_oc, 1, LEFT(IFNULL(p_nombre_pdf, CONCAT('OC-', v_numero_oc, '.pdf')), 200),
                p_ruta_pdf, v_version, 1,
                JSON_OBJECT('motivo', TRIM(p_motivo_pdf), 'tipo', p_tipo_pdf, 'tamano_bytes', p_tamano_pdf, 'hash', p_hash_pdf),
                p_id_usuario, NOW(), p_id_usuario);

        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion,
                                      id_usuario, registrado_en, metadata)
        VALUES ('orden_compra', p_id_oc, IF(p_tipo_pdf = 'oc_corregida', 'subir_oc_corregida', 'reemplazar_pdf'), NULL, NULL,
                CONCAT(IF(p_tipo_pdf = 'oc_corregida', 'Se cargó la OC corregida por el cliente', 'Se reemplazó el PDF'),
                       ' (', IFNULL(p_nombre_pdf, ''), '). Motivo: ', TRIM(p_motivo_pdf)),
                p_id_usuario, NOW(), JSON_OBJECT('version', v_version, 'motivo', TRIM(p_motivo_pdf), 'nombre', p_nombre_pdf));
    END IF;

    -- Vinculaciones: quitadas, nuevas y con monto distinto
    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion,
                                  id_usuario, registrado_en, metadata)
    SELECT 'orden_compra', p_id_oc, 'desvincular_propuesta', op.estado_validacion, NULL,
           CONCAT('Se quitó la propuesta ', p.numero, ' v', p.version, ' (', FORMAT(op.monto_asignado, 2), ').'),
           p_id_usuario, NOW(), JSON_OBJECT('id_propuesta', op.id_propuesta, 'monto_asignado', op.monto_asignado)
    FROM oc_propuesta op JOIN propuesta_comercial p ON p.id_propuesta = op.id_propuesta
    WHERE op.id_oc = p_id_oc AND op.eliminado_en IS NULL
      AND op.id_propuesta NOT IN (SELECT id_propuesta FROM tmp_oc_eval);

    UPDATE oc_propuesta SET eliminado_en = NOW(), eliminado_por = p_id_usuario
    WHERE id_oc = p_id_oc AND eliminado_en IS NULL
      AND id_propuesta NOT IN (SELECT id_propuesta FROM tmp_oc_eval);

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion,
                                  id_usuario, registrado_en, metadata)
    SELECT 'orden_compra', p_id_oc, 'editar_vinculacion', NULL, NULL,
           CONCAT('Monto asignado a ', e.numero, ': ', FORMAT(op.monto_asignado, 2), ' → ', FORMAT(e.monto_asignado, 2), '.'),
           p_id_usuario, NOW(), JSON_OBJECT('id_propuesta', e.id_propuesta, 'antes', op.monto_asignado, 'despues', e.monto_asignado)
    FROM tmp_oc_eval e
    JOIN oc_propuesta op ON op.id_oc = p_id_oc AND op.id_propuesta = e.id_propuesta AND op.eliminado_en IS NULL
    WHERE ABS(op.monto_asignado - e.monto_asignado) >= 0.01;

    UPDATE oc_propuesta op
    JOIN tmp_oc_eval e ON e.id_propuesta = op.id_propuesta
    SET op.monto_asignado = e.monto_asignado, op.monto_cubierto = e.monto_cubierto, op.modificado_por = p_id_usuario
    WHERE op.id_oc = p_id_oc AND op.eliminado_en IS NULL
      AND (ABS(op.monto_asignado - e.monto_asignado) >= 0.01 OR NOT (op.monto_cubierto <=> e.monto_cubierto));

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion,
                                  id_usuario, registrado_en, metadata)
    SELECT 'orden_compra', p_id_oc, 'vincular_propuesta', NULL, NULL,
           CONCAT('Se vinculó la propuesta ', e.numero, ' por ', FORMAT(e.monto_asignado, 2),
                  ' (', IF(v_monto > 0, ROUND(e.monto_asignado * 100 / v_monto, 1), 0), '% de la OC).'),
           p_id_usuario, NOW(), JSON_OBJECT('id_propuesta', e.id_propuesta, 'monto_asignado', e.monto_asignado)
    FROM tmp_oc_eval e
    WHERE NOT EXISTS (SELECT 1 FROM oc_propuesta op WHERE op.id_oc = p_id_oc AND op.id_propuesta = e.id_propuesta
                        AND op.eliminado_en IS NULL);

    INSERT INTO oc_propuesta (id_oc, id_propuesta, monto_asignado, monto_cubierto, estado_validacion, creado_por)
    SELECT p_id_oc, e.id_propuesta, e.monto_asignado, e.monto_cubierto, 'pendiente', p_id_usuario
    FROM tmp_oc_eval e
    WHERE NOT EXISTS (SELECT 1 FROM oc_propuesta op WHERE op.id_oc = p_id_oc AND op.id_propuesta = e.id_propuesta
                        AND op.eliminado_en IS NULL)
    ORDER BY e.orden;

    -- Una corrida de validación por propuesta (origen: OC corregida, reemplazo de PDF o edición)
    SELECT COUNT(*) INTO v_n FROM tmp_oc_eval;
    WHILE v_i <= v_n DO
        SELECT id_propuesta, monto_asignado, eval_ia INTO v_id_prop, v_asignado, v_eval FROM tmp_oc_eval WHERE orden = v_i;
        CALL SP_RegistrarValidacionOrdenCompra(p_id_oc, v_id_prop, p_datos, v_asignado, v_eval,
                                               CASE WHEN v_hay_pdf = 1 AND p_tipo_pdf = 'oc_corregida' THEN 'oc_corregida'
                                                    WHEN v_hay_pdf = 1 THEN 'reemplazo_pdf' ELSE 'edicion' END,
                                               p_id_usuario, v_id_val, v_res, v_sug);
        SET v_i = v_i + 1;
    END WHILE;

    DROP TEMPORARY TABLE IF EXISTS tmp_oc_eval;
    DROP TEMPORARY TABLE IF EXISTS tmp_oc_cmp;

    CALL SP_AplicarDecisionOrdenCompra(p_id_oc, p_decision, p_id_usuario);

    COMMIT;

    SELECT estado INTO v_estado FROM orden_compra WHERE id_oc = p_id_oc;
    SELECT 2 AS IdTipoMensaje, CONCAT('Orden de compra actualizada (', UPPER(REPLACE(v_estado, '_', ' ')), ').') AS Mensaje;

    SELECT oc.id_oc, oc.numero_oc, oc.estado, oc.monto_total, NULL AS id_oc_reemplazada, NULL AS numero_oc_reemplazada,
           0 AS notificados
    FROM orden_compra oc WHERE oc.id_oc = p_id_oc;

    SELECT op.id_propuesta, p.numero, p.version, op.monto_asignado, op.estado_validacion, op.tipo_observacion,
           op.resultado_ia, op.id_propuesta_nueva_version, v.sugerencia, v.coincidencias, v.advertencias, v.criticas
    FROM oc_propuesta op
    JOIN propuesta_comercial p ON p.id_propuesta = op.id_propuesta
    LEFT JOIN orden_compra_validacion v ON v.id_validacion = op.id_validacion
    WHERE op.id_oc = p_id_oc AND op.eliminado_en IS NULL
    ORDER BY op.id;
END$$

DELIMITER ;


DROP PROCEDURE IF EXISTS SP_EditarOrdenCompra;

DELIMITER $$

CREATE PROCEDURE SP_EditarOrdenCompra(
    IN p_id_usuario       BIGINT,
    IN p_id_oc            BIGINT,
    IN p_datos            JSON,
    IN p_vinculaciones    JSON,
    IN p_evaluaciones_ia  JSON,
    IN p_decision         VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_tipo_pdf         VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_motivo_pdf       VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_ruta_pdf         VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_nombre_pdf       VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_tamano_pdf       BIGINT,
    IN p_hash_pdf         CHAR(64)     CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_bloqueo VARCHAR(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        DO RELEASE_LOCK(v_bloqueo);
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SET v_bloqueo = CONCAT('tw_oc_cliente_', IFNULL((SELECT id_cliente FROM orden_compra WHERE id_oc = p_id_oc), 0));
    IF IFNULL(GET_LOCK(v_bloqueo, 15), 0) <> 1 THEN
        SELECT 1 AS IdTipoMensaje,
               'Hay otra operación en curso sobre las órdenes de compra de este cliente. Intente nuevamente en unos segundos.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_EditarOrdenCompraInterno(p_id_usuario, p_id_oc, p_datos, p_vinculaciones, p_evaluaciones_ia, p_decision,
                                     p_tipo_pdf, p_motivo_pdf, p_ruta_pdf, p_nombre_pdf, p_tamano_pdf, p_hash_pdf);

    DO RELEASE_LOCK(v_bloqueo);
END$$

DELIMITER ;
