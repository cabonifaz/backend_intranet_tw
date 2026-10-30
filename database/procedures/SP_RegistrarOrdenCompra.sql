-- HU-23 (Sprint 4) Registrar la orden de compra del cliente con su PDF, validada contra las propuestas vinculadas.
-- Los datos llegan extraídos por la IA (y/o corregidos a mano) en p_datos; la validación contra cada propuesta la
-- hace SP_CompararOcPropuesta (más la evaluación de conceptos de la IA, si la hay). La IA no decide: el comercial
-- elige qué hacer (p_decision):
--   validar             "Guardar y validar"                 → VALIDADA (sin diferencias críticas)
--   observar            "Guardar con observaciones"         → OBSERVADA informativa en las propuestas con diferencias
--   correccion_cliente  "Solicitar corrección al cliente"   → OBSERVADA pendiente de corrección del cliente
--   nueva_version       "Generar nueva versión de propuesta" → OBSERVADA hasta validar contra la versión nueva
--                       (la versión nueva la crea el back después, con SP_CrearNuevaVersionPropuesta)
-- p_id_oc_reemplaza (opcional): OC que esta OC reemplaza (debe estar vinculada a alguna de las propuestas vinculadas):
--   autogenerada         su vinculación pasa a esta OC y la OC-AUTO queda dada de baja (no tiene PDF que conservar)
--   pendiente_reemplazo  la OC observada por diferencias críticas queda con reemplazada_por = esta OC; conserva su
--                        PDF, vinculaciones y timeline para auditoría, pero deja de contar en el saldo de las propuestas
--                        (FN_SaldoPropuestaOc) y se oculta de la bandeja
-- Multi-propuesta (ticket B): además, las OC autogeneradas (OC-AUTO) vigentes de TODAS las propuestas vinculadas se
--   dan de baja solas (no hace falta indicarlas). Mientras se registra, no descuentan el saldo (ticket A).
-- p_datos.tipoCambio (ticket E): soles por 1 unidad de moneda extranjera; obligatorio si alguna propuesta vinculada
--   está en otra moneda que la OC. Se guarda en orden_compra.tipo_cambio y el monto en la moneda de cada propuesta en
--   oc_propuesta.monto_cubierto.
-- Reglas: acción oc_registrar; la propuesta de origen debe estar vinculada; todas las propuestas del mismo cliente,
--   aceptadas y con saldo; lo asignado no supera el monto de la OC; PDF obligatorio; N° OC único por cliente.
-- Efectos: orden_compra + oc_propuesta + una corrida de validación por propuesta + PDF versión 1 + timeline,
--   estado consolidado, expedientes con vinculación validada a Programación y notificación a Contabilidad,
--   Operaciones y al responsable comercial.
-- Resultados: 1 mensaje, 2 OC registrada (ocs_reemplazadas: JSON con las OC que reemplazó), 3 vinculaciones
--   (estado y resultado de la validación).
DROP PROCEDURE IF EXISTS SP_RegistrarOrdenCompraInterno;

DELIMITER $$

CREATE PROCEDURE SP_RegistrarOrdenCompraInterno(
    IN p_id_usuario       BIGINT,
    IN p_id_propuesta     BIGINT,
    IN p_id_oc_reemplaza  BIGINT,
    IN p_datos            JSON,
    IN p_vinculaciones    JSON,
    IN p_evaluaciones_ia  JSON,
    IN p_decision         VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_ruta_pdf         VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_nombre_pdf       VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_tamano_pdf       BIGINT,
    IN p_hash_pdf         CHAR(64)     CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_id_cliente  BIGINT;
    DECLARE v_id_resp     BIGINT;
    DECLARE v_numero_prop VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_error       VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_numero_oc   VARCHAR(50)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_numero_auto VARCHAR(1000) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado_reemp VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_monto       DECIMAL(14,2);
    DECLARE v_simbolo     VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_oc       BIGINT;
    DECLARE v_n           INT;
    DECLARE v_i           INT DEFAULT 1;
    DECLARE v_id_prop     BIGINT;
    DECLARE v_asignado    DECIMAL(14,2);
    DECLARE v_eval        JSON;
    DECLARE v_id_val      BIGINT;
    DECLARE v_res         VARCHAR(20);
    DECLARE v_sug         VARCHAR(30);
    DECLARE v_usuario     VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cliente     VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado      VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_notificados INT DEFAULT 0;
    DECLARE v_id_reemp    BIGINT;
    DECLARE v_num_reemp   VARCHAR(50)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_est_reemp   VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_ocs_reemp   JSON;
    DECLARE v_id_primera  BIGINT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_oc_eval;
        DROP TEMPORARY TABLE IF EXISTS tmp_oc_cmp;
        DROP TEMPORARY TABLE IF EXISTS tmp_oc_disp;
        DROP TEMPORARY TABLE IF EXISTS tmp_oc_reemp;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF FN_PermisoAccion(p_id_usuario, 'oc_registrar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para registrar órdenes de compra.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT id_cliente, COALESCE(id_responsable, id_creador), CONCAT(numero, ' v', version)
      INTO v_id_cliente, v_id_resp, v_numero_prop
    FROM propuesta_comercial WHERE id_propuesta = p_id_propuesta;
    IF v_id_cliente IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'La propuesta no existe.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF p_vinculaciones IS NULL OR JSON_TYPE(p_vinculaciones) <> 'ARRAY'
       OR NOT EXISTS (SELECT 1 FROM JSON_TABLE(p_vinculaciones, '$[*]' COLUMNS (id BIGINT PATH '$.idPropuesta')) j
                      WHERE j.id = p_id_propuesta) THEN
        SELECT 1 AS IdTipoMensaje, 'La propuesta de origen debe estar entre las propuestas vinculadas.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF IFNULL(p_id_oc_reemplaza, 0) > 0 THEN
        SELECT oc.numero_oc, oc.estado INTO v_numero_auto, v_estado_reemp
        FROM orden_compra oc
        WHERE oc.id_oc = p_id_oc_reemplaza AND oc.reemplazada_por IS NULL
          AND oc.estado IN ('autogenerada', 'pendiente_reemplazo') AND oc.eliminado_en IS NULL
          AND oc.id_cliente = v_id_cliente
          AND EXISTS (SELECT 1 FROM oc_propuesta op
                      JOIN JSON_TABLE(p_vinculaciones, '$[*]' COLUMNS (id BIGINT PATH '$.idPropuesta')) jv ON jv.id = op.id_propuesta
                      WHERE op.id_oc = oc.id_oc AND op.eliminado_en IS NULL);
        IF v_numero_auto IS NULL THEN
            SELECT 1 AS IdTipoMensaje,
                   'La OC a reemplazar no existe, ya fue reemplazada, está anulada, no está pendiente de reemplazo o no corresponde a las propuestas vinculadas.' AS Mensaje;
            LEAVE proc;
        END IF;
    END IF;

    IF p_decision IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Indique qué hacer con la orden de compra (validar, observar, solicitar corrección o nueva versión).' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_EvaluarDatosOrdenCompra(p_id_usuario, NULL, p_id_oc_reemplaza, v_id_cliente, p_datos, p_vinculaciones,
                                    p_evaluaciones_ia, p_decision, v_error);
    IF v_error IS NOT NULL THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_oc_eval;
        SELECT 1 AS IdTipoMensaje, v_error AS Mensaje;
        LEAVE proc;
    END IF;

    IF NULLIF(TRIM(IFNULL(p_ruta_pdf, '')), '') IS NULL THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_oc_eval;
        SELECT 1 AS IdTipoMensaje, 'Adjunte el PDF de la orden de compra.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_numero_oc = FN_JsonTexto(p_datos, '$.numeroOc');
    SET v_monto     = CAST(FN_JsonTexto(p_datos, '$.montoTotal') AS DECIMAL(14,2));

    -- OC que se reemplazan: la indicada y las OC-AUTO vigentes de las propuestas vinculadas (ticket B)
    DROP TEMPORARY TABLE IF EXISTS tmp_oc_reemp;
    CREATE TEMPORARY TABLE tmp_oc_reemp (
        orden     INT AUTO_INCREMENT PRIMARY KEY,
        id_oc     BIGINT,
        numero_oc VARCHAR(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        estado    VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
    );
    IF v_numero_auto IS NOT NULL THEN
        INSERT INTO tmp_oc_reemp (id_oc, numero_oc, estado) VALUES (p_id_oc_reemplaza, v_numero_auto, v_estado_reemp);
    END IF;
    INSERT INTO tmp_oc_reemp (id_oc, numero_oc, estado)
    SELECT DISTINCT oc.id_oc, oc.numero_oc, oc.estado
    FROM orden_compra oc
    JOIN oc_propuesta op ON op.id_oc = oc.id_oc AND op.eliminado_en IS NULL
    JOIN tmp_oc_eval e   ON e.id_propuesta = op.id_propuesta
    WHERE oc.estado = 'autogenerada' AND oc.reemplazada_por IS NULL AND oc.eliminado_en IS NULL
      AND oc.id_cliente = v_id_cliente AND oc.id_oc <> IFNULL(p_id_oc_reemplaza, 0)
    ORDER BY oc.id_oc;

    SELECT MIN(orden) INTO v_i FROM tmp_oc_reemp;
    SELECT id_oc INTO v_id_primera FROM tmp_oc_reemp WHERE orden = v_i;
    SELECT JSON_ARRAYAGG(JSON_OBJECT('idOc', id_oc, 'numeroOc', numero_oc, 'estado', estado)) INTO v_ocs_reemp
    FROM tmp_oc_reemp;
    SELECT GROUP_CONCAT(numero_oc ORDER BY orden SEPARATOR ', ') INTO v_numero_auto FROM tmp_oc_reemp;
    SET v_i = 1;

    START TRANSACTION;

    INSERT INTO orden_compra (
        numero_oc, es_autogenerada, id_oc_reemplazada, referencia, id_propuesta, id_cliente,
        ruc_cliente_oc, razon_social_oc, numero_propuesta_ref, id_moneda, monto_total, tipo_cambio,
        id_condicion_pago, forma_pago, igv_incluido, igv_pct, descuento_monto, factura_igual_oc,
        fecha_oc, fecha_recepcion, vigencia_hasta, observaciones, conceptos, campos_ia, campos_manuales,
        url_archivo_pdf, nombre_archivo_pdf, tamano_pdf_bytes, hash_pdf,
        estado, fecha_registro, creado_por)
    VALUES (
        v_numero_oc, 0, v_id_primera, FN_JsonTexto(p_datos, '$.referencia'), p_id_propuesta, v_id_cliente,
        NULLIF(REGEXP_REPLACE(IFNULL(FN_JsonTexto(p_datos, '$.ruc'), ''), '[^0-9]', ''), ''),
        FN_JsonTexto(p_datos, '$.razonSocial'), FN_JsonTexto(p_datos, '$.numeroPropuesta'),
        CAST(FN_JsonTexto(p_datos, '$.idMoneda') AS SIGNED), v_monto,
        IF(EXISTS (SELECT 1 FROM tmp_oc_eval WHERE monto_cubierto IS NOT NULL),
           CAST(FN_JsonTexto(p_datos, '$.tipoCambio') AS DECIMAL(12,6)), NULL),
        CAST(FN_JsonTexto(p_datos, '$.idCondicionPago') AS SIGNED), FN_JsonTexto(p_datos, '$.formaPago'),
        CASE LOWER(IFNULL(FN_JsonTexto(p_datos, '$.igvIncluido'), '')) WHEN 'true' THEN 1 WHEN '1' THEN 1
                                                                       WHEN 'false' THEN 0 WHEN '0' THEN 0 END,
        CAST(FN_JsonTexto(p_datos, '$.igvPct') AS DECIMAL(5,2)),
        CAST(FN_JsonTexto(p_datos, '$.descuento') AS DECIMAL(14,2)),
        IF(LOWER(IFNULL(FN_JsonTexto(p_datos, '$.facturaIgualOc'), 'true')) IN ('false', '0'), 0, 1),
        STR_TO_DATE(LEFT(FN_JsonTexto(p_datos, '$.fechaEmision'), 10), '%Y-%m-%d'),
        STR_TO_DATE(LEFT(FN_JsonTexto(p_datos, '$.fechaRecepcion'), 10), '%Y-%m-%d'),
        STR_TO_DATE(LEFT(FN_JsonTexto(p_datos, '$.vigenciaHasta'), 10), '%Y-%m-%d'),
        FN_JsonTexto(p_datos, '$.observaciones'),
        JSON_EXTRACT(p_datos, '$.conceptos'), JSON_EXTRACT(p_datos, '$.camposIa'), JSON_EXTRACT(p_datos, '$.camposManuales'),
        p_ruta_pdf, p_nombre_pdf, p_tamano_pdf, p_hash_pdf,
        'observada', NOW(), p_id_usuario);

    SET v_id_oc = LAST_INSERT_ID();

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion,
                                  id_usuario, registrado_en, metadata)
    VALUES ('orden_compra', v_id_oc, 'registrar_oc', NULL, 'registrada',
            CONCAT('Orden de compra ', v_numero_oc, ' registrada a partir de la propuesta ', v_numero_prop,
                   IF(v_numero_auto IS NULL, '', CONCAT(', en reemplazo de ', v_numero_auto)), '.'),
            p_id_usuario, NOW(), JSON_OBJECT('id_propuesta', p_id_propuesta, 'id_oc_reemplazada', v_id_primera,
                                             'ocs_reemplazadas', v_ocs_reemp));

    -- PDF (versión 1)
    INSERT INTO documento_adjunto (entidad_tipo, id_entidad, id_tipo_documento, nombre_archivo, url_archivo,
                                   version, id_visibilidad, metadatos, subido_por, fecha_carga, creado_por)
    VALUES ('orden_compra', v_id_oc, 1, LEFT(IFNULL(p_nombre_pdf, CONCAT('OC-', v_numero_oc, '.pdf')), 200),
            p_ruta_pdf, 1, 1, JSON_OBJECT('motivo', 'Versión inicial', 'tamano_bytes', p_tamano_pdf, 'hash', p_hash_pdf),
            p_id_usuario, NOW(), p_id_usuario);

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion,
                                  id_usuario, registrado_en, metadata)
    VALUES ('orden_compra', v_id_oc, 'cargar_pdf_oc', NULL, NULL,
            CONCAT('Se cargó el PDF ', IFNULL(p_nombre_pdf, ''), ' (', ROUND(IFNULL(p_tamano_pdf, 0) / 1048576, 2), ' MB).'),
            p_id_usuario, NOW(), JSON_OBJECT('nombre', p_nombre_pdf, 'tamano_bytes', p_tamano_pdf));

    -- Extracción de la IA y correcciones manuales
    IF JSON_EXTRACT(p_datos, '$.camposIa') IS NOT NULL AND JSON_TYPE(JSON_EXTRACT(p_datos, '$.camposIa')) = 'OBJECT' THEN
        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion,
                                      id_usuario, registrado_en, metadata)
        VALUES ('orden_compra', v_id_oc, 'extraccion_ia', NULL, NULL,
                CONCAT('La IA extrajo ', JSON_LENGTH(JSON_EXTRACT(p_datos, '$.camposIa')), ' dato(s) del PDF.'),
                p_id_usuario, NOW(), JSON_EXTRACT(p_datos, '$.camposIa'));
    END IF;
    IF JSON_EXTRACT(p_datos, '$.camposManuales') IS NOT NULL AND JSON_TYPE(JSON_EXTRACT(p_datos, '$.camposManuales')) = 'ARRAY' THEN
        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion,
                                      id_usuario, registrado_en, metadata)
        SELECT 'orden_compra', v_id_oc, 'corregir_campo_oc', LEFT(j.valor_ia, 80), LEFT(j.valor_nuevo, 80),
               CONCAT('Corrección manual de ', IFNULL(j.campo, 'un campo'), ': "', IFNULL(j.valor_ia, '-'),
                      '" → "', IFNULL(j.valor_nuevo, '-'), '".'),
               p_id_usuario, NOW(), JSON_OBJECT('campo', j.campo, 'valor_ia', j.valor_ia, 'valor_nuevo', j.valor_nuevo)
        FROM JSON_TABLE(JSON_EXTRACT(p_datos, '$.camposManuales'), '$[*]' COLUMNS (
                campo       VARCHAR(60)  PATH '$.campo',
                valor_ia    VARCHAR(400) PATH '$.valorIa',
                valor_nuevo VARCHAR(400) PATH '$.valorNuevo')) j;
    END IF;

    -- Reemplazo de las OC autogeneradas (baja lógica) y de la OC pendiente de reemplazo (se conserva para auditoría)
    SELECT COUNT(*) INTO v_n FROM tmp_oc_reemp;
    WHILE v_i <= v_n DO
        SELECT id_oc, numero_oc, estado INTO v_id_reemp, v_num_reemp, v_est_reemp FROM tmp_oc_reemp WHERE orden = v_i;
        IF v_est_reemp = 'autogenerada' THEN
            UPDATE oc_propuesta SET eliminado_en = NOW(), eliminado_por = p_id_usuario
            WHERE id_oc = v_id_reemp AND eliminado_en IS NULL;
        END IF;
        UPDATE orden_compra
        SET reemplazada_por = v_id_oc, fecha_reemplazo = NOW(), modificado_por = p_id_usuario,
            eliminado_en = IF(v_est_reemp = 'autogenerada', NOW(), eliminado_en)
        WHERE id_oc = v_id_reemp;
        CALL SP_SincronizarBloqueosOrdenCompra(v_id_reemp, p_id_usuario);
        -- El expediente que apuntaba a la OC reemplazada pasa a apuntar a la OC del cliente
        UPDATE expediente_digital SET id_orden_compra = v_id_oc, modificado_por = p_id_usuario
        WHERE id_orden_compra = v_id_reemp AND eliminado_en IS NULL;
        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion,
                                      id_usuario, registrado_en, metadata)
        VALUES ('orden_compra', v_id_reemp,
                IF(v_est_reemp = 'autogenerada', 'reemplazar_oc_auto', 'reemplazar_oc'), v_est_reemp, 'reemplazada',
                CONCAT(IF(v_est_reemp = 'autogenerada', 'OC autogenerada', 'OC pendiente de reemplazo'),
                       ' reemplazada por la OC del cliente ', v_numero_oc, '.'),
                p_id_usuario, NOW(), JSON_OBJECT('id_oc_real', v_id_oc));
        SET v_i = v_i + 1;
    END WHILE;
    DROP TEMPORARY TABLE IF EXISTS tmp_oc_reemp;
    SET v_i = 1;

    -- Vinculaciones (todas primero) y luego una corrida de validación por propuesta
    INSERT INTO oc_propuesta (id_oc, id_propuesta, monto_asignado, monto_cubierto, estado_validacion, creado_por)
    SELECT v_id_oc, id_propuesta, monto_asignado, monto_cubierto, 'pendiente', p_id_usuario FROM tmp_oc_eval ORDER BY orden;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion,
                                  id_usuario, registrado_en, metadata)
    SELECT 'orden_compra', v_id_oc, 'vincular_propuesta', NULL, NULL,
           CONCAT('Se vinculó la propuesta ', numero, ' por ', FORMAT(monto_asignado, 2),
                  ' (', IF(v_monto > 0, ROUND(monto_asignado * 100 / v_monto, 1), 0), '% de la OC).'),
           p_id_usuario, NOW(), JSON_OBJECT('id_propuesta', id_propuesta, 'monto_asignado', monto_asignado)
    FROM tmp_oc_eval ORDER BY orden;

    SELECT COUNT(*) INTO v_n FROM tmp_oc_eval;
    WHILE v_i <= v_n DO
        SELECT id_propuesta, monto_asignado, eval_ia INTO v_id_prop, v_asignado, v_eval
        FROM tmp_oc_eval WHERE orden = v_i;
        CALL SP_RegistrarValidacionOrdenCompra(v_id_oc, v_id_prop, p_datos, v_asignado, v_eval, 'registro', p_id_usuario,
                                               v_id_val, v_res, v_sug);
        SET v_i = v_i + 1;
    END WHILE;

    DROP TEMPORARY TABLE IF EXISTS tmp_oc_eval;
    DROP TEMPORARY TABLE IF EXISTS tmp_oc_cmp;

    CALL SP_AplicarDecisionOrdenCompra(v_id_oc, p_decision, p_id_usuario);

    -- Al registrar no hay "cambio de estado": el estado inicial queda en el evento de registro
    SELECT estado INTO v_estado FROM orden_compra WHERE id_oc = v_id_oc;
    DELETE FROM auditoria_evento WHERE entidad_tipo = 'orden_compra' AND id_entidad = v_id_oc AND accion = 'cambio_estado_oc';
    UPDATE auditoria_evento SET estado_nuevo = v_estado
    WHERE entidad_tipo = 'orden_compra' AND id_entidad = v_id_oc AND accion = 'registrar_oc';

    -- Notificación a Contabilidad, Operaciones y al responsable comercial
    SELECT CONCAT(nombre, ' ', apellido) INTO v_usuario FROM usuario WHERE id_usuario = p_id_usuario;
    SELECT razon_social INTO v_cliente FROM cliente WHERE id_cliente = v_id_cliente;
    SELECT String2 INTO v_simbolo FROM tabla_maestra
    WHERE IdMaestro = 1 AND IdEmpresa = 1 AND Num1 = CAST(FN_JsonTexto(p_datos, '$.idMoneda') AS SIGNED);

    INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
    SELECT u.id_usuario, 5,
           CONCAT('Nueva orden de compra: ', v_numero_oc),
           CONCAT(v_usuario, ' registró la OC ', v_numero_oc, ' de ', IFNULL(v_cliente, 'el cliente'),
                  ' por ', IFNULL(v_simbolo, ''), ' ', FORMAT(v_monto, 2), ' (propuesta ', v_numero_prop, '). Estado: ',
                  UPPER(REPLACE(v_estado, '_', ' ')), '.'),
           'orden_compra', v_id_oc, NOW(), p_id_usuario
    FROM usuario u
    WHERE u.eliminado_en IS NULL AND u.estado = 'activo' AND u.id_usuario <> p_id_usuario
      AND ((u.area IN ('operaciones', 'administracion') AND u.rol_sistema IN ('supervisor', 'administrador'))
           OR u.id_usuario = v_id_resp);
    SET v_notificados = ROW_COUNT();

    COMMIT;

    SELECT 2 AS IdTipoMensaje,
           CONCAT('Orden de compra registrada (', UPPER(REPLACE(v_estado, '_', ' ')), '). Se notificó a Contabilidad y Operaciones.') AS Mensaje;

    SELECT oc.id_oc, oc.numero_oc, oc.estado, oc.monto_total, oc.id_oc_reemplazada, v_numero_auto AS numero_oc_reemplazada,
           v_notificados AS notificados, v_ocs_reemp AS ocs_reemplazadas, oc.tipo_cambio
    FROM orden_compra oc WHERE oc.id_oc = v_id_oc;

    SELECT op.id_propuesta, p.numero, p.version, op.monto_asignado, op.estado_validacion, op.tipo_observacion,
           op.resultado_ia, op.id_propuesta_nueva_version, v.sugerencia, v.coincidencias, v.advertencias, v.criticas
    FROM oc_propuesta op
    JOIN propuesta_comercial p ON p.id_propuesta = op.id_propuesta
    LEFT JOIN orden_compra_validacion v ON v.id_validacion = op.id_validacion
    WHERE op.id_oc = v_id_oc AND op.eliminado_en IS NULL
    ORDER BY op.id;
END$$

DELIMITER ;


-- SP_RegistrarOrdenCompra: punto de entrada. Toma un bloqueo por cliente (GET_LOCK) para que dos registros simultáneos
-- sobre las OC del mismo cliente no pasen las mismas validaciones a la vez (OC duplicada o saldo sobreasignado).
DROP PROCEDURE IF EXISTS SP_RegistrarOrdenCompra;

DELIMITER $$

CREATE PROCEDURE SP_RegistrarOrdenCompra(
    IN p_id_usuario       BIGINT,
    IN p_id_propuesta     BIGINT,
    IN p_id_oc_reemplaza  BIGINT,
    IN p_datos            JSON,
    IN p_vinculaciones    JSON,
    IN p_evaluaciones_ia  JSON,
    IN p_decision         VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
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

    SET v_bloqueo = CONCAT('tw_oc_cliente_', IFNULL((SELECT id_cliente FROM propuesta_comercial WHERE id_propuesta = p_id_propuesta), 0));
    IF IFNULL(GET_LOCK(v_bloqueo, 15), 0) <> 1 THEN
        SELECT 1 AS IdTipoMensaje,
               'Hay otra operación en curso sobre las órdenes de compra de este cliente. Intente nuevamente en unos segundos.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_RegistrarOrdenCompraInterno(p_id_usuario, p_id_propuesta, p_id_oc_reemplaza, p_datos, p_vinculaciones,
                                        p_evaluaciones_ia, p_decision, p_ruta_pdf, p_nombre_pdf, p_tamano_pdf, p_hash_pdf);

    DO RELEASE_LOCK(v_bloqueo);
END$$

DELIMITER ;
