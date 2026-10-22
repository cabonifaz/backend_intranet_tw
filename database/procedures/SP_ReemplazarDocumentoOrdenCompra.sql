-- HU-26 (Sprint 4) Reemplazar el PDF de la OC o subir la OC corregida por el cliente (pestaña Documento).
-- Solo se conserva el PDF vigente (sin versiones navegables); cada cambio queda en el timeline con fecha, usuario y motivo.
-- Al cambiar el PDF se vuelve a validar automáticamente contra todas las propuestas vinculadas.
-- p_tipo: reemplazo | oc_corregida. Con oc_corregida, las vinculaciones observadas "pendiente de corrección del cliente"
--   que ahora no tienen diferencias pasan a VALIDADA; si persisten diferencias, el ciclo continúa (sin límite).
-- p_datos (opcional): datos que la IA extrajo del PDF nuevo (mismo formato que el registro). Si llega, reemplaza los
--   datos extraídos de la OC (N° OC, monto, moneda y fechas se conservan si no vienen).
-- Reglas: acción oc_documento_reemplazar; OC del área, no anulada, no autogenerada; motivo obligatorio (5+ caracteres);
--   oc_corregida solo si hay alguna vinculación pendiente de corrección del cliente.
-- Resultados: 1 mensaje, 2 OC, 3 vinculaciones.
DROP PROCEDURE IF EXISTS SP_ReemplazarDocumentoOrdenCompraInterno;

DELIMITER $$

CREATE PROCEDURE SP_ReemplazarDocumentoOrdenCompraInterno(
    IN p_id_usuario      BIGINT,
    IN p_id_oc           BIGINT,
    IN p_tipo            VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_motivo          VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_datos           JSON,
    IN p_evaluaciones_ia JSON,
    IN p_ruta_pdf        VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_nombre_pdf      VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_tamano_pdf      BIGINT,
    IN p_hash_pdf        CHAR(64)     CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_solo_validar    TINYINT
)
proc: BEGIN
    DECLARE v_existe   INT DEFAULT 0;
    DECLARE v_estado   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_auto     TINYINT;
    DECLARE v_pend     INT DEFAULT 0;
    DECLARE v_version  INT;
    DECLARE v_numero   VARCHAR(50)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_datos    JSON;
    DECLARE v_id_prop  BIGINT;
    DECLARE v_asignado DECIMAL(14,2);
    DECLARE v_eval     JSON;
    DECLARE v_id_val   BIGINT;
    DECLARE v_res      VARCHAR(20);
    DECLARE v_sug      VARCHAR(30);
    DECLARE v_validadas INT DEFAULT 0;
    DECLARE v_fin      INT DEFAULT 0;
    DECLARE cur CURSOR FOR
        SELECT id_propuesta, monto_asignado FROM tmp_oc_doc_vinc ORDER BY id;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_fin = 1;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_oc_doc_vinc;
        DROP TEMPORARY TABLE IF EXISTS tmp_oc_cmp;
        DROP TEMPORARY TABLE IF EXISTS tmp_oc;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF FN_PermisoAccion(p_id_usuario, 'oc_documento_reemplazar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para reemplazar el PDF de la orden de compra.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_CalcularOrdenesCompra(p_id_usuario, p_id_oc);
    SELECT COUNT(*), MAX(estado), MAX(es_autogenerada), MAX(pendientes_correccion), MAX(numero_oc)
      INTO v_existe, v_estado, v_auto, v_pend, v_numero
    FROM tmp_oc;
    DROP TEMPORARY TABLE IF EXISTS tmp_oc;

    IF v_existe = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'La orden de compra no existe o no pertenece a tu área.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_estado = 'anulada' THEN
        SELECT 1 AS IdTipoMensaje, 'La orden de compra está anulada: no se puede cambiar su PDF.' AS Mensaje; LEAVE proc;
    END IF;
    IF EXISTS (SELECT 1 FROM orden_compra WHERE id_oc = p_id_oc AND reemplazada_por IS NOT NULL) THEN
        SELECT 1 AS IdTipoMensaje, 'La orden de compra fue reemplazada por otra OC del cliente: es de solo lectura.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_auto = 1 THEN
        SELECT 1 AS IdTipoMensaje, 'La OC autogenerada no tiene PDF: reemplázala por la OC del cliente.' AS Mensaje; LEAVE proc;
    END IF;
    IF IFNULL(p_tipo, '') NOT IN ('reemplazo', 'oc_corregida') THEN
        SELECT 1 AS IdTipoMensaje, 'Indique si es un reemplazo del PDF o la OC corregida por el cliente.' AS Mensaje; LEAVE proc;
    END IF;
    IF p_tipo = 'oc_corregida' AND v_pend = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'La orden de compra no está pendiente de corrección del cliente.' AS Mensaje; LEAVE proc;
    END IF;
    IF CHAR_LENGTH(TRIM(IFNULL(p_motivo, ''))) < 5 THEN
        SELECT 1 AS IdTipoMensaje, 'Indique el motivo del cambio de PDF (mínimo 5 caracteres).' AS Mensaje; LEAVE proc;
    END IF;
    IF CHAR_LENGTH(TRIM(p_motivo)) > 500 THEN
        SELECT 1 AS IdTipoMensaje, 'El motivo admite hasta 500 caracteres.' AS Mensaje; LEAVE proc;
    END IF;

    IF IFNULL(p_solo_validar, 0) = 1 THEN
        SELECT 2 AS IdTipoMensaje, 'Validado.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF NULLIF(TRIM(IFNULL(p_ruta_pdf, '')), '') IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Adjunte el PDF.' AS Mensaje; LEAVE proc;
    END IF;

    START TRANSACTION;

    SELECT IFNULL(MAX(version), 0) + 1 INTO v_version
    FROM documento_adjunto WHERE entidad_tipo = 'orden_compra' AND id_entidad = p_id_oc;

    UPDATE orden_compra SET url_archivo_pdf = p_ruta_pdf, nombre_archivo_pdf = p_nombre_pdf,
                            tamano_pdf_bytes = p_tamano_pdf, hash_pdf = p_hash_pdf, modificado_por = p_id_usuario
    WHERE id_oc = p_id_oc;

    -- Datos extraídos del PDF nuevo (si la IA los leyó)
    IF p_datos IS NOT NULL AND JSON_TYPE(p_datos) = 'OBJECT' THEN
        UPDATE orden_compra SET
            ruc_cliente_oc       = IFNULL(NULLIF(REGEXP_REPLACE(IFNULL(FN_JsonTexto(p_datos, '$.ruc'), ''), '[^0-9]', ''), ''), ruc_cliente_oc),
            razon_social_oc      = IFNULL(FN_JsonTexto(p_datos, '$.razonSocial'), razon_social_oc),
            numero_propuesta_ref = IFNULL(FN_JsonTexto(p_datos, '$.numeroPropuesta'), numero_propuesta_ref),
            id_condicion_pago    = IFNULL(CAST(FN_JsonTexto(p_datos, '$.idCondicionPago') AS SIGNED), id_condicion_pago),
            forma_pago           = IFNULL(FN_JsonTexto(p_datos, '$.formaPago'), forma_pago),
            igv_incluido         = IFNULL(CASE LOWER(IFNULL(FN_JsonTexto(p_datos, '$.igvIncluido'), ''))
                                              WHEN 'true' THEN 1 WHEN '1' THEN 1 WHEN 'false' THEN 0 WHEN '0' THEN 0 END,
                                          igv_incluido),
            igv_pct              = IFNULL(CAST(FN_JsonTexto(p_datos, '$.igvPct') AS DECIMAL(5,2)), igv_pct),
            descuento_monto      = IFNULL(CAST(FN_JsonTexto(p_datos, '$.descuento') AS DECIMAL(14,2)), descuento_monto),
            tipo_cambio          = IFNULL(CAST(FN_JsonTexto(p_datos, '$.tipoCambio') AS DECIMAL(12,6)), tipo_cambio),
            fecha_oc             = IFNULL(STR_TO_DATE(LEFT(FN_JsonTexto(p_datos, '$.fechaEmision'), 10), '%Y-%m-%d'), fecha_oc),
            vigencia_hasta       = IFNULL(STR_TO_DATE(LEFT(FN_JsonTexto(p_datos, '$.vigenciaHasta'), 10), '%Y-%m-%d'), vigencia_hasta),
            conceptos            = IFNULL(JSON_EXTRACT(p_datos, '$.conceptos'), conceptos),
            campos_ia            = IFNULL(JSON_EXTRACT(p_datos, '$.camposIa'), campos_ia)
        WHERE id_oc = p_id_oc;
    END IF;

    INSERT INTO documento_adjunto (entidad_tipo, id_entidad, id_tipo_documento, nombre_archivo, url_archivo,
                                   version, id_visibilidad, metadatos, subido_por, fecha_carga, creado_por)
    VALUES ('orden_compra', p_id_oc, 1, LEFT(IFNULL(p_nombre_pdf, CONCAT('OC-', v_numero, '.pdf')), 200),
            p_ruta_pdf, v_version, 1,
            JSON_OBJECT('motivo', TRIM(p_motivo), 'tipo', p_tipo, 'tamano_bytes', p_tamano_pdf, 'hash', p_hash_pdf),
            p_id_usuario, NOW(), p_id_usuario);

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion,
                                  id_usuario, registrado_en, metadata)
    VALUES ('orden_compra', p_id_oc, IF(p_tipo = 'oc_corregida', 'subir_oc_corregida', 'reemplazar_pdf'), NULL, NULL,
            CONCAT(IF(p_tipo = 'oc_corregida', 'Se cargó la OC corregida por el cliente', 'Se reemplazó el PDF'),
                   ' (', IFNULL(p_nombre_pdf, ''), '). Motivo: ', TRIM(p_motivo)),
            p_id_usuario, NOW(), JSON_OBJECT('version', v_version, 'motivo', TRIM(p_motivo), 'nombre', p_nombre_pdf));

    -- Re-validación automática contra todas las propuestas vinculadas
    SET v_datos = FN_DatosOrdenCompraJson(p_id_oc);

    DROP TEMPORARY TABLE IF EXISTS tmp_oc_doc_vinc;
    CREATE TEMPORARY TABLE tmp_oc_doc_vinc AS
    SELECT id, id_propuesta, monto_asignado FROM oc_propuesta WHERE id_oc = p_id_oc AND eliminado_en IS NULL;

    OPEN cur;
    leer: LOOP
        FETCH cur INTO v_id_prop, v_asignado;
        IF v_fin = 1 THEN LEAVE leer; END IF;

        SET v_eval = NULL;
        IF p_evaluaciones_ia IS NOT NULL AND JSON_TYPE(p_evaluaciones_ia) = 'ARRAY' THEN
            SELECT j.obj INTO v_eval
            FROM JSON_TABLE(p_evaluaciones_ia, '$[*]' COLUMNS (id BIGINT PATH '$.idPropuesta', obj JSON PATH '$')) j
            WHERE j.id = v_id_prop LIMIT 1;
            SET v_fin = 0;
        END IF;

        CALL SP_RegistrarValidacionOrdenCompra(p_id_oc, v_id_prop, v_datos, v_asignado, v_eval,
                                               IF(p_tipo = 'oc_corregida', 'oc_corregida', 'reemplazo_pdf'),
                                               p_id_usuario, v_id_val, v_res, v_sug);
        SET v_fin = 0;

        -- OC corregida: la vinculación pendiente de corrección que ya coincide pasa a VALIDADA
        IF p_tipo = 'oc_corregida' AND v_res = 'ok' THEN
            UPDATE oc_propuesta SET estado_validacion = 'validada', tipo_observacion = NULL,
                                    fecha_decision = NOW(), decidido_por = p_id_usuario, modificado_por = p_id_usuario
            WHERE id_oc = p_id_oc AND id_propuesta = v_id_prop AND eliminado_en IS NULL
              AND estado_validacion = 'observada' AND tipo_observacion = 'correccion_cliente';
            SET v_validadas = v_validadas + ROW_COUNT();
        END IF;
    END LOOP;
    CLOSE cur;

    DROP TEMPORARY TABLE IF EXISTS tmp_oc_doc_vinc;
    DROP TEMPORARY TABLE IF EXISTS tmp_oc_cmp;

    CALL SP_RecalcularEstadoOrdenCompra(p_id_oc, p_id_usuario);
    CALL SP_PasarExpedientesAProgramacion(p_id_oc, p_id_usuario);

    COMMIT;

    SELECT estado INTO v_estado FROM orden_compra WHERE id_oc = p_id_oc;
    SELECT 2 AS IdTipoMensaje,
           CONCAT(IF(p_tipo = 'oc_corregida', 'OC corregida cargada y re-validada', 'PDF reemplazado y re-validado'),
                  IF(v_validadas > 0, CONCAT('. ', v_validadas, ' propuesta(s) pasaron a VALIDADA'), ''),
                  ' (', UPPER(REPLACE(v_estado, '_', ' ')), ').') AS Mensaje;

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


DROP PROCEDURE IF EXISTS SP_ReemplazarDocumentoOrdenCompra;

DELIMITER $$

CREATE PROCEDURE SP_ReemplazarDocumentoOrdenCompra(
    IN p_id_usuario      BIGINT,
    IN p_id_oc           BIGINT,
    IN p_tipo            VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_motivo          VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_datos           JSON,
    IN p_evaluaciones_ia JSON,
    IN p_ruta_pdf        VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_nombre_pdf      VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_tamano_pdf      BIGINT,
    IN p_hash_pdf        CHAR(64)     CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_solo_validar    TINYINT
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

    CALL SP_ReemplazarDocumentoOrdenCompraInterno(p_id_usuario, p_id_oc, p_tipo, p_motivo, p_datos, p_evaluaciones_ia,
                                                  p_ruta_pdf, p_nombre_pdf, p_tamano_pdf, p_hash_pdf, p_solo_validar);

    DO RELEASE_LOCK(v_bloqueo);
END$$

DELIMITER ;
