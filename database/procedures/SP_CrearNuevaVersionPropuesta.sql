-- HU-10 — Crear una nueva versión de una propuesta a partir de la vigente.
--   · Solo desde la ÚLTIMA versión y si ya salió de borrador
--     (pendiente_vb, aprobado, enviado, rechazado, vencido).
--   · Motivo (MOTIVO_NUEVA_VERSION, IdMaestro 11) y descripción obligatorios.
--   · La nueva versión nace en 'borrador' con el mismo número y versión + 1.
--   · Bloques copiables (1 = copiar, 0 = empezar vacío):
--       configuracion  → tipo, referencia, introducción, notas internas, sede,
--                        contacto, tercerización, tipo de cambio, IGV, vigencia
--                        y estructura del PDF (secciones_activas)
--       detalle        → textos 'detalle', 'recomendaciones', 'suministros_cliente'
--       condiciones    → textos 'condiciones', garantía y plazo de entrega
--       items          → ítems principales/opcionales y descuentos
--       forma_pago     → formas de pago
--       equipos        → equipos seleccionados
--     Siempre se heredan: requerimiento, cliente, moneda y responsable.
--   · Si la anterior estaba en 'pendiente_vb' o 'aprobado' (aún no enviada al
--     cliente) queda 'anulado' y su VB pendiente se cancela. Si ya fue
--     enviada / rechazada / vencida se conserva intacta como historial.
--   · Totales recalculados con la misma fórmula que SP_GuardarPropuesta.
DROP PROCEDURE IF EXISTS SP_CrearNuevaVersionPropuesta;

DELIMITER $$

CREATE PROCEDURE SP_CrearNuevaVersionPropuesta(
    IN p_id_propuesta_origen  BIGINT,
    IN p_id_motivo            INT,
    IN p_descripcion_cambios  VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_copiar_configuracion TINYINT,
    IN p_copiar_detalle       TINYINT,
    IN p_copiar_condiciones   TINYINT,
    IN p_copiar_items         TINYINT,
    IN p_copiar_forma_pago    TINYINT,
    IN p_copiar_equipos       TINYINT,
    IN p_id_usuario           BIGINT
)
proc: BEGIN
    DECLARE v_id_nueva      BIGINT;
    DECLARE v_numero        VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_version_orig  INT;
    DECLARE v_version       INT;
    DECLARE v_estado        VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_rq         BIGINT;
    DECLARE v_estado_rq     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_motivo_label  VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_usu           VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_usu_nombre    VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_anula_origen  TINYINT DEFAULT 0;
    DECLARE v_igv_pct       DECIMAL(5,2);
    DECLARE v_aplica_igv    TINYINT;
    DECLARE v_incluye_igv   TINYINT;
    DECLARE v_desc_pct      DECIMAL(5,2);
    DECLARE v_desc_monto    DECIMAL(14,2);
    DECLARE v_desc_opc      DECIMAL(14,2);
    DECLARE v_sub           DECIMAL(14,2) DEFAULT 0;
    DECLARE v_desc          DECIMAL(14,2) DEFAULT 0;
    DECLARE v_base          DECIMAL(14,2) DEFAULT 0;
    DECLARE v_igv           DECIMAL(14,2) DEFAULT 0;
    DECLARE v_total         DECIMAL(14,2) DEFAULT 0;
    DECLARE v_sub_opc       DECIMAL(14,2) DEFAULT 0;
    DECLARE v_total_opc     DECIMAL(14,2) DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1
            @err_msg  = MESSAGE_TEXT,
            @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje,
               CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SET p_copiar_configuracion = IFNULL(p_copiar_configuracion, 1);
    SET p_copiar_detalle       = IFNULL(p_copiar_detalle, 1);
    SET p_copiar_condiciones   = IFNULL(p_copiar_condiciones, 1);
    SET p_copiar_items         = IFNULL(p_copiar_items, 1);
    SET p_copiar_forma_pago    = IFNULL(p_copiar_forma_pago, 1);
    SET p_copiar_equipos       = IFNULL(p_copiar_equipos, 1);

    -- ── Validaciones ────────────────────────────────────────────────────
    SELECT p.numero, p.version, p.estado, p.id_requerimiento, r.estado
      INTO v_numero, v_version_orig, v_estado, v_id_rq, v_estado_rq
    FROM propuesta_comercial p
    JOIN requerimiento r ON r.id_requerimiento = p.id_requerimiento
    WHERE p.id_propuesta = p_id_propuesta_origen AND p.eliminado_en IS NULL;

    IF v_numero IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Propuesta no encontrada.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF v_estado = 'borrador' THEN
        SELECT 1 AS IdTipoMensaje, 'La propuesta está en borrador: edítela directamente, no necesita una nueva versión.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF v_estado = 'anulado' THEN
        SELECT 1 AS IdTipoMensaje, 'No se puede generar una nueva versión de una propuesta anulada.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF EXISTS (SELECT 1 FROM propuesta_comercial
               WHERE numero = v_numero AND version > v_version_orig AND eliminado_en IS NULL) THEN
        SELECT 1 AS IdTipoMensaje,
               CONCAT('Solo se puede versionar la última versión de ', v_numero, '.') AS Mensaje;
        LEAVE proc;
    END IF;

    IF EXISTS (SELECT 1 FROM propuesta_comercial
               WHERE numero = v_numero AND estado = 'borrador' AND eliminado_en IS NULL) THEN
        SELECT 1 AS IdTipoMensaje,
               CONCAT('Ya existe una versión en borrador de ', v_numero, '. Edítela en lugar de crear otra.') AS Mensaje;
        LEAVE proc;
    END IF;

    IF v_estado_rq IN ('anulado', 'cerrado') THEN
        SELECT 1 AS IdTipoMensaje, 'El requerimiento de origen está anulado o cerrado.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT String1 INTO v_motivo_label
    FROM tabla_maestra
    WHERE IdMaestro = 11 AND IdEmpresa = 1 AND Num1 = p_id_motivo AND eliminado_en IS NULL
    LIMIT 1;

    IF v_motivo_label IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Seleccione un motivo válido para la nueva versión.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF TRIM(IFNULL(p_descripcion_cambios, '')) = '' THEN
        SELECT 1 AS IdTipoMensaje, 'Describa brevemente los cambios de la nueva versión.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_version      = v_version_orig + 1;
    SET v_anula_origen = IF(v_estado IN ('pendiente_vb', 'aprobado'), 1, 0);

    SELECT correo, CONCAT(nombre, ' ', apellido) INTO v_usu, v_usu_nombre
    FROM usuario WHERE id_usuario = p_id_usuario LIMIT 1;

    START TRANSACTION;

    -- ── Cabecera (totales en 0; se recalculan al final) ─────────────────
    INSERT INTO propuesta_comercial (
        numero, version, id_requerimiento, id_cliente, id_sede, id_contacto, id_responsable,
        id_moneda, subtotal, descuento_monto, descuento_pct, id_motivo_descuento,
        igv_pct, igv_monto, total, aplica_igv, precios_incluyen_igv,
        plazo_entrega_dias, plazo_entrega_unidad, plazo_entrega_condicion, vigencia_dias,
        introduccion, notas_generales, tipo_servicio, referencia, secciones_activas,
        es_tercerizado, tercero_ruc, tercero_razon_social, tercero_direccion,
        tipo_cambio, garantia_meses, mostrar_garantia,
        subtotal_opcionales, descuento_opcionales, total_opcionales,
        estado, id_propuesta_padre, id_motivo_nueva_version, descripcion_cambios,
        id_creador, fecha_creacion, fecha_expiracion,
        creado_en, creado_por
    )
    SELECT
        o.numero, v_version, o.id_requerimiento, o.id_cliente,
        IF(p_copiar_configuracion = 1, o.id_sede,     NULL),
        IF(p_copiar_configuracion = 1, o.id_contacto, NULL),
        o.id_responsable, o.id_moneda,
        0,
        IF(p_copiar_items = 1, o.descuento_monto, 0),
        IF(p_copiar_items = 1, o.descuento_pct, NULL),
        IF(p_copiar_items = 1, o.id_motivo_descuento, NULL),
        o.igv_pct, 0, 0,
        IF(p_copiar_configuracion = 1, o.aplica_igv, 1),
        IF(p_copiar_configuracion = 1, o.precios_incluyen_igv, 0),
        IF(p_copiar_condiciones = 1, o.plazo_entrega_dias, NULL),
        IF(p_copiar_condiciones = 1, o.plazo_entrega_unidad, NULL),
        IF(p_copiar_condiciones = 1, o.plazo_entrega_condicion, NULL),
        IF(p_copiar_configuracion = 1, o.vigencia_dias, NULL),
        IF(p_copiar_configuracion = 1, o.introduccion, NULL),
        IF(p_copiar_configuracion = 1, o.notas_generales, NULL),
        IF(p_copiar_configuracion = 1, o.tipo_servicio, NULL),
        IF(p_copiar_configuracion = 1, o.referencia, NULL),
        IF(p_copiar_configuracion = 1, o.secciones_activas, NULL),
        IF(p_copiar_configuracion = 1, o.es_tercerizado, 0),
        IF(p_copiar_configuracion = 1, o.tercero_ruc, NULL),
        IF(p_copiar_configuracion = 1, o.tercero_razon_social, NULL),
        IF(p_copiar_configuracion = 1, o.tercero_direccion, NULL),
        IF(p_copiar_configuracion = 1, o.tipo_cambio, NULL),
        IF(p_copiar_condiciones = 1, o.garantia_meses, NULL),
        IF(p_copiar_condiciones = 1, o.mostrar_garantia, 1),
        0,
        IF(p_copiar_items = 1, o.descuento_opcionales, 0),
        0,
        'borrador', o.id_propuesta, p_id_motivo, TRIM(p_descripcion_cambios),
        p_id_usuario, NOW(),
        IF(p_copiar_configuracion = 1 AND o.vigencia_dias IS NOT NULL,
           DATE_ADD(CURDATE(), INTERVAL o.vigencia_dias DAY), NULL),
        NOW(), p_id_usuario
    FROM propuesta_comercial o
    WHERE o.id_propuesta = p_id_propuesta_origen;

    SET v_id_nueva = LAST_INSERT_ID();

    -- ── Ítems ───────────────────────────────────────────────────────────
    IF p_copiar_items = 1 THEN
        INSERT INTO propuesta_item (
            id_propuesta, seccion, id_catalogo_item, descripcion, alcance, puntos_calibracion,
            cantidad, frecuencia, precio_unitario, descuento, subtotal, es_espaciado, orden,
            creado_en, creado_por
        )
        SELECT v_id_nueva, seccion, id_catalogo_item, descripcion, alcance, puntos_calibracion,
               cantidad, frecuencia, precio_unitario, descuento, subtotal, es_espaciado, orden,
               NOW(), p_id_usuario
        FROM propuesta_item
        WHERE id_propuesta = p_id_propuesta_origen AND eliminado_en IS NULL
        ORDER BY seccion, orden, id_item;
    END IF;

    -- ── Textos: detalle descriptivo y/o condiciones ─────────────────────
    INSERT INTO propuesta_texto (id_propuesta, seccion, tipo, texto, id_texto_base, orden, UsuCre, FchCre)
    SELECT v_id_nueva, seccion, tipo, texto, id_texto_base, orden, v_usu, NOW()
    FROM propuesta_texto
    WHERE id_propuesta = p_id_propuesta_origen
      AND (   (p_copiar_detalle     = 1 AND seccion IN ('detalle', 'recomendaciones', 'suministros_cliente'))
           OR (p_copiar_condiciones = 1 AND seccion = 'condiciones'))
    ORDER BY seccion, orden, id;

    -- ── Formas de pago ──────────────────────────────────────────────────
    IF p_copiar_forma_pago = 1 THEN
        INSERT INTO propuesta_forma_pago (id_propuesta, porcentaje, condicion, orden, UsuCre, FchCre)
        SELECT v_id_nueva, porcentaje, condicion, orden, v_usu, NOW()
        FROM propuesta_forma_pago
        WHERE id_propuesta = p_id_propuesta_origen
        ORDER BY orden, id;
    END IF;

    -- ── Equipos ─────────────────────────────────────────────────────────
    IF p_copiar_equipos = 1 THEN
        INSERT INTO propuesta_equipo (
            id_propuesta, id_equipo, local_sede, tipo, subtipo, num_serie, marca, modelo,
            codigo_cliente, codigo_tw, orden, UsuCre, FchCre
        )
        SELECT v_id_nueva, id_equipo, local_sede, tipo, subtipo, num_serie, marca, modelo,
               codigo_cliente, codigo_tw, orden, v_usu, NOW()
        FROM propuesta_equipo
        WHERE id_propuesta = p_id_propuesta_origen
        ORDER BY orden, id;
    END IF;

    -- ── Totales (misma fórmula que SP_GuardarPropuesta) ─────────────────
    SELECT igv_pct, aplica_igv, precios_incluyen_igv, descuento_pct, descuento_monto, descuento_opcionales
      INTO v_igv_pct, v_aplica_igv, v_incluye_igv, v_desc_pct, v_desc_monto, v_desc_opc
    FROM propuesta_comercial WHERE id_propuesta = v_id_nueva;

    SELECT IFNULL(SUM(CASE WHEN seccion = 'principal' AND es_espaciado = 0 THEN subtotal END), 0),
           IFNULL(SUM(CASE WHEN seccion = 'opcional'  AND es_espaciado = 0 THEN subtotal END), 0)
      INTO v_sub, v_sub_opc
    FROM propuesta_item
    WHERE id_propuesta = v_id_nueva AND eliminado_en IS NULL;

    SET v_desc = LEAST(IF(IFNULL(v_desc_pct, 0) > 0, ROUND(v_sub * v_desc_pct / 100, 2), IFNULL(v_desc_monto, 0)), v_sub);
    SET v_desc_opc = LEAST(IFNULL(v_desc_opc, 0), v_sub_opc);
    SET v_base = v_sub - v_desc;

    IF IFNULL(v_incluye_igv, 0) = 1 THEN
        SET v_total = v_base;
        SET v_igv   = ROUND(v_base - v_base / (1 + v_igv_pct / 100), 2);
    ELSEIF IFNULL(v_aplica_igv, 1) = 1 THEN
        SET v_igv   = ROUND(v_base * v_igv_pct / 100, 2);
        SET v_total = v_base + v_igv;
    ELSE
        SET v_igv   = 0;
        SET v_total = v_base;
    END IF;
    SET v_total_opc = v_sub_opc - v_desc_opc;

    UPDATE propuesta_comercial SET
        subtotal             = v_sub,
        descuento_monto      = v_desc,
        igv_monto            = v_igv,
        total                = v_total,
        subtotal_opcionales  = v_sub_opc,
        descuento_opcionales = v_desc_opc,
        total_opcionales     = v_total_opc
    WHERE id_propuesta = v_id_nueva;

    -- ── Versión anterior aún no enviada al cliente → anulada ────────────
    IF v_anula_origen = 1 THEN
        UPDATE propuesta_comercial
           SET estado = 'anulado', modificado_en = NOW(), modificado_por = p_id_usuario
         WHERE id_propuesta = p_id_propuesta_origen;

        UPDATE visto_bueno
           SET estado = 'cancelado', fecha_respuesta = NOW(),
               comentario = CONCAT('Cancelado: se generó ', v_numero, ' v', v_version, '.'),
               modificado_en = NOW(), modificado_por = p_id_usuario
         WHERE id_propuesta = p_id_propuesta_origen AND estado = 'pendiente' AND eliminado_en IS NULL;

        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
        VALUES ('propuesta', p_id_propuesta_origen, 'anulacion_por_version', v_estado, 'anulado',
                CONCAT('Propuesta ', v_numero, ' v', v_version_orig, ' anulada al generarse la v', v_version, '.'),
                p_id_usuario, NOW(), JSON_OBJECT('id_propuesta_nueva', v_id_nueva));
    END IF;

    -- ── Historial del RQ y auditoría ────────────────────────────────────
    INSERT INTO historial_requerimiento (id_requerimiento, tipo, tipo_label, icono, descripcion, usuario, fecha, creado_en, creado_por)
    VALUES (v_id_rq, 'propuesta', 'Nueva versión de propuesta', 'description',
            CONCAT('Propuesta ', v_numero, ' v', v_version, ' creada desde la v', v_version_orig, ' (', v_motivo_label, ').'),
            v_usu_nombre, NOW(), NOW(), p_id_usuario);

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('propuesta', v_id_nueva, 'nueva_version', NULL, 'borrador',
            CONCAT('Propuesta ', v_numero, ' v', v_version, ' creada desde la v', v_version_orig, ': ', TRIM(p_descripcion_cambios)),
            p_id_usuario, NOW(),
            JSON_OBJECT('id_propuesta_origen', p_id_propuesta_origen,
                        'id_motivo',           p_id_motivo,
                        'motivo',              v_motivo_label,
                        'copiado', JSON_OBJECT('configuracion', p_copiar_configuracion = 1,
                                               'detalle',       p_copiar_detalle = 1,
                                               'condiciones',   p_copiar_condiciones = 1,
                                               'items',         p_copiar_items = 1,
                                               'forma_pago',    p_copiar_forma_pago = 1,
                                               'equipos',       p_copiar_equipos = 1),
                        'total', v_total));

    COMMIT;

    SELECT 2 AS IdTipoMensaje,
           CONCAT('Versión v', v_version, ' de ', v_numero, ' creada en borrador.') AS Mensaje;

    SELECT v_id_nueva AS id_propuesta, v_numero AS numero, v_version AS version,
           v_anula_origen AS version_anterior_anulada;
END$$

DELIMITER ;
