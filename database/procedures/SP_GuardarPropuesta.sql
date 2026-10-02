-- HU-07 — Crear o actualizar una propuesta completa (borrador) en una transacción.
--   p_id_propuesta = 0  → nueva propuesta
--     · p_id_propuesta_base > 0 → NUEVA VERSIÓN de esa propuesta (mismo número, versión + 1)
--   p_id_propuesta > 0  → actualizar (solo si está en 'borrador')
--   Ítems, textos, formas de pago y equipos llegan como arreglos JSON y se
--   reemplazan completos. Los totales los recalcula el SP (no se confía en el front).
DROP PROCEDURE IF EXISTS SP_GuardarPropuesta;

DELIMITER $$

CREATE PROCEDURE SP_GuardarPropuesta(
    IN p_id_propuesta            BIGINT,
    IN p_id_propuesta_base       BIGINT,
    IN p_id_requerimiento        BIGINT,
    IN p_id_sede                 BIGINT,
    IN p_id_contacto             BIGINT,
    IN p_id_responsable          BIGINT,
    IN p_tipo_servicio           VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_referencia              VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_introduccion            TEXT         CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_notas_generales         TEXT         CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_secciones_activas       TEXT         CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_es_tercerizado          TINYINT,
    IN p_tercero_ruc             VARCHAR(11)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_tercero_razon_social    VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_tercero_direccion       VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_moneda               INT,
    IN p_tipo_cambio             DECIMAL(8,4),
    IN p_garantia_meses          INT,
    IN p_mostrar_garantia        TINYINT,
    IN p_plazo_entrega_dias      INT,
    IN p_plazo_entrega_unidad    VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_plazo_entrega_condicion VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_vigencia_dias           INT,
    IN p_aplica_igv              TINYINT,
    IN p_precios_incluyen_igv    TINYINT,
    IN p_descuento_pct           DECIMAL(5,2),
    IN p_descuento_monto         DECIMAL(14,2),
    IN p_id_motivo_descuento     INT,
    IN p_descuento_opcionales    DECIMAL(14,2),
    IN p_items_json              LONGTEXT,
    IN p_textos_json             LONGTEXT,
    IN p_pagos_json              LONGTEXT,
    IN p_equipos_json            LONGTEXT,
    IN p_id_usuario              BIGINT
)
proc: BEGIN
    DECLARE v_id            BIGINT;
    DECLARE v_numero        VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_version       INT;
    DECLARE v_padre         BIGINT;
    DECLARE v_estado        VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_rq_actual  BIGINT;
    DECLARE v_id_cliente    BIGINT;
    DECLARE v_estado_rq     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_numero_rq     VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_sede_rq       BIGINT;
    DECLARE v_contacto_rq   BIGINT;
    DECLARE v_usu           VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_usu_nombre    VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_igv_pct       DECIMAL(5,2) DEFAULT 18.00;
    DECLARE v_sub           DECIMAL(14,2) DEFAULT 0;
    DECLARE v_desc          DECIMAL(14,2) DEFAULT 0;
    DECLARE v_base          DECIMAL(14,2) DEFAULT 0;
    DECLARE v_igv           DECIMAL(14,2) DEFAULT 0;
    DECLARE v_total         DECIMAL(14,2) DEFAULT 0;
    DECLARE v_sub_opc       DECIMAL(14,2) DEFAULT 0;
    DECLARE v_desc_opc      DECIMAL(14,2) DEFAULT 0;
    DECLARE v_total_opc     DECIMAL(14,2) DEFAULT 0;
    DECLARE v_pagos_n       INT DEFAULT 0;
    DECLARE v_pagos_suma    DECIMAL(7,2) DEFAULT 0;
    DECLARE v_n             INT DEFAULT 0;
    DECLARE v_es_nueva      TINYINT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1
            @err_msg  = MESSAGE_TEXT,
            @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_prop_eq_prev;
        SELECT 3 AS IdTipoMensaje,
               CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SET p_items_json   = IFNULL(NULLIF(p_items_json,   ''), '[]');
    SET p_textos_json  = IFNULL(NULLIF(p_textos_json,  ''), '[]');
    SET p_pagos_json   = IFNULL(NULLIF(p_pagos_json,   ''), '[]');
    SET p_equipos_json = IFNULL(NULLIF(p_equipos_json, ''), '[]');

    -- ── Requerimiento de origen ──────────────────────────────────────────
    SELECT id_cliente, estado, numero, id_sede, id_contacto
      INTO v_id_cliente, v_estado_rq, v_numero_rq, v_sede_rq, v_contacto_rq
    FROM requerimiento
    WHERE id_requerimiento = p_id_requerimiento AND SoftDelete = 0
    LIMIT 1;

    IF v_id_cliente IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Requerimiento no encontrado.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF p_id_propuesta = 0 AND v_estado_rq IN ('anulado', 'cerrado') THEN
        SELECT 1 AS IdTipoMensaje, 'No se puede crear una propuesta para un requerimiento anulado o cerrado.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM tabla_maestra WHERE IdMaestro = 1 AND IdEmpresa = 1 AND Num1 = p_id_moneda) THEN
        SELECT 1 AS IdTipoMensaje, 'La moneda seleccionada no es válida.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF IFNULL(p_es_tercerizado, 0) = 1
       AND (IFNULL(p_tercero_ruc, '') = '' OR IFNULL(p_tercero_razon_social, '') = '') THEN
        SELECT 1 AS IdTipoMensaje, 'Para un servicio tercerizado indique el RUC y la razón social del titular del certificado.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- ── Propuesta existente / nueva versión ─────────────────────────────
    IF p_id_propuesta <> 0 THEN
        SELECT estado, id_requerimiento INTO v_estado, v_id_rq_actual
        FROM propuesta_comercial
        WHERE id_propuesta = p_id_propuesta AND eliminado_en IS NULL;

        IF v_estado IS NULL THEN
            SELECT 1 AS IdTipoMensaje, 'Propuesta no encontrada.' AS Mensaje;
            LEAVE proc;
        END IF;
        IF v_estado <> 'borrador' THEN
            SELECT 1 AS IdTipoMensaje, 'La propuesta ya no está en borrador y no puede modificarse. Genere una nueva versión.' AS Mensaje;
            LEAVE proc;
        END IF;
        IF v_id_rq_actual <> p_id_requerimiento THEN
            SELECT 1 AS IdTipoMensaje, 'La propuesta pertenece a otro requerimiento.' AS Mensaje;
            LEAVE proc;
        END IF;
    ELSEIF IFNULL(p_id_propuesta_base, 0) <> 0 THEN
        SELECT numero, id_requerimiento INTO v_numero, v_id_rq_actual
        FROM propuesta_comercial
        WHERE id_propuesta = p_id_propuesta_base AND eliminado_en IS NULL;

        IF v_numero IS NULL THEN
            SELECT 1 AS IdTipoMensaje, 'La propuesta base para la nueva versión no existe.' AS Mensaje;
            LEAVE proc;
        END IF;
        IF v_id_rq_actual <> p_id_requerimiento THEN
            SELECT 1 AS IdTipoMensaje, 'La propuesta base pertenece a otro requerimiento.' AS Mensaje;
            LEAVE proc;
        END IF;
        IF EXISTS (
            SELECT 1 FROM propuesta_comercial
            WHERE numero = v_numero AND estado = 'borrador' AND eliminado_en IS NULL
        ) THEN
            SELECT 1 AS IdTipoMensaje,
                   CONCAT('Ya existe una versión en borrador de ', v_numero, '. Edítela en lugar de crear otra.') AS Mensaje;
            LEAVE proc;
        END IF;

        SELECT MAX(version) + 1 INTO v_version FROM propuesta_comercial WHERE numero = v_numero;
        SET v_padre = p_id_propuesta_base;
    END IF;

    -- ── Formas de pago: deben sumar 100 % ───────────────────────────────
    SELECT COUNT(*), IFNULL(SUM(j.porcentaje), 0) INTO v_pagos_n, v_pagos_suma
    FROM JSON_TABLE(p_pagos_json, '$[*]' COLUMNS (porcentaje DECIMAL(5,2) PATH '$.porcentaje')) AS j;

    IF v_pagos_n > 0 AND v_pagos_suma <> 100 THEN
        SELECT 1 AS IdTipoMensaje, CONCAT('Las formas de pago deben sumar 100 % (suman ', v_pagos_suma, ' %).') AS Mensaje;
        LEAVE proc;
    END IF;

    -- ── Equipos del maestro: deben ser del mismo cliente ────────────────
    SELECT COUNT(*) INTO v_n
    FROM JSON_TABLE(p_equipos_json, '$[*]' COLUMNS (id_equipo BIGINT PATH '$.id_equipo')) AS j
    LEFT JOIN equipo_cliente ec ON ec.id_equipo = j.id_equipo
    WHERE j.id_equipo IS NOT NULL AND (ec.id_equipo IS NULL OR ec.id_cliente <> v_id_cliente);

    IF v_n > 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Uno o más equipos seleccionados no existen o no pertenecen al cliente de la propuesta.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- ── Totales (los recalcula el back) ─────────────────────────────────
    SELECT
        IFNULL(SUM(CASE WHEN j.seccion = 'principal' THEN
            GREATEST(ROUND(IFNULL(j.cantidad,0) * IFNULL(j.frecuencia,1) * IFNULL(j.precio_unitario,0) - IFNULL(j.descuento,0), 2), 0)
        END), 0),
        IFNULL(SUM(CASE WHEN j.seccion = 'opcional' THEN
            GREATEST(ROUND(IFNULL(j.cantidad,0) * IFNULL(j.frecuencia,1) * IFNULL(j.precio_unitario,0) - IFNULL(j.descuento,0), 2), 0)
        END), 0)
      INTO v_sub, v_sub_opc
    FROM JSON_TABLE(p_items_json, '$[*]' COLUMNS (
            seccion         VARCHAR(20)   PATH '$.seccion',
            cantidad        DECIMAL(10,2) PATH '$.cantidad',
            frecuencia      DECIMAL(10,2) PATH '$.frecuencia',
            precio_unitario DECIMAL(12,2) PATH '$.precio_unitario',
            descuento       DECIMAL(14,2) PATH '$.descuento',
            es_espaciado    TINYINT       PATH '$.es_espaciado'
         )) AS j
    WHERE IFNULL(j.es_espaciado, 0) = 0;

    SET v_desc = IF(IFNULL(p_descuento_pct, 0) > 0,
                    ROUND(v_sub * p_descuento_pct / 100, 2),
                    IFNULL(p_descuento_monto, 0));

    IF v_desc > v_sub THEN
        SELECT 1 AS IdTipoMensaje, 'El descuento no puede ser mayor que el subtotal.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_desc_opc = IFNULL(p_descuento_opcionales, 0);
    IF v_desc_opc > v_sub_opc THEN
        SELECT 1 AS IdTipoMensaje, 'El descuento de opcionales no puede ser mayor que su subtotal.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_base = v_sub - v_desc;
    IF IFNULL(p_precios_incluyen_igv, 0) = 1 THEN
        SET v_total = v_base;
        SET v_igv   = ROUND(v_base - v_base / (1 + v_igv_pct / 100), 2);
    ELSEIF IFNULL(p_aplica_igv, 1) = 1 THEN
        SET v_igv   = ROUND(v_base * v_igv_pct / 100, 2);
        SET v_total = v_base + v_igv;
    ELSE
        SET v_igv   = 0;
        SET v_total = v_base;
    END IF;
    SET v_total_opc = v_sub_opc - v_desc_opc;

    SELECT correo, CONCAT(nombre, ' ', apellido) INTO v_usu, v_usu_nombre
    FROM usuario WHERE id_usuario = p_id_usuario LIMIT 1;

    -- Copia de los equipos actuales: serie/marca/modelo no se pueden cambiar
    DROP TEMPORARY TABLE IF EXISTS tmp_prop_eq_prev;
    CREATE TEMPORARY TABLE tmp_prop_eq_prev AS
        SELECT id, num_serie, marca, modelo FROM propuesta_equipo WHERE id_propuesta = p_id_propuesta;

    START TRANSACTION;

    -- ── Cabecera ────────────────────────────────────────────────────────
    IF p_id_propuesta = 0 THEN
        SET v_es_nueva = 1;
        INSERT INTO propuesta_comercial (
            numero, version, id_requerimiento, id_cliente, id_sede, id_contacto, id_responsable,
            id_moneda, subtotal, descuento_monto, descuento_pct, id_motivo_descuento,
            igv_pct, igv_monto, total, aplica_igv, precios_incluyen_igv,
            plazo_entrega_dias, plazo_entrega_unidad, plazo_entrega_condicion, vigencia_dias,
            introduccion, notas_generales, tipo_servicio, referencia, secciones_activas,
            es_tercerizado, tercero_ruc, tercero_razon_social, tercero_direccion,
            tipo_cambio, garantia_meses, mostrar_garantia,
            subtotal_opcionales, descuento_opcionales, total_opcionales,
            estado, id_propuesta_padre, id_creador, fecha_creacion, fecha_expiracion,
            creado_en, creado_por
        ) VALUES (
            IFNULL(v_numero, 'PROP-TEMP'), IFNULL(v_version, 1), p_id_requerimiento, v_id_cliente,
            COALESCE(p_id_sede, v_sede_rq), COALESCE(p_id_contacto, v_contacto_rq), COALESCE(p_id_responsable, p_id_usuario),
            p_id_moneda, v_sub, v_desc, NULLIF(p_descuento_pct, 0), p_id_motivo_descuento,
            v_igv_pct, v_igv, v_total, IFNULL(p_aplica_igv, 1), IFNULL(p_precios_incluyen_igv, 0),
            p_plazo_entrega_dias, p_plazo_entrega_unidad, p_plazo_entrega_condicion, p_vigencia_dias,
            p_introduccion, p_notas_generales, p_tipo_servicio, p_referencia, NULLIF(p_secciones_activas, ''),
            IFNULL(p_es_tercerizado, 0), p_tercero_ruc, p_tercero_razon_social, p_tercero_direccion,
            p_tipo_cambio, p_garantia_meses, IFNULL(p_mostrar_garantia, 1),
            v_sub_opc, v_desc_opc, v_total_opc,
            'borrador', v_padre, p_id_usuario, NOW(),
            IF(p_vigencia_dias IS NULL, NULL, DATE_ADD(CURDATE(), INTERVAL p_vigencia_dias DAY)),
            NOW(), p_id_usuario
        );
        SET v_id = LAST_INSERT_ID();

        IF v_numero IS NULL THEN
            SET v_numero  = CONCAT('PROP-', LPAD(v_id, 6, '0'));
            SET v_version = 1;
            UPDATE propuesta_comercial SET numero = v_numero WHERE id_propuesta = v_id;
        END IF;
    ELSE
        SET v_id = p_id_propuesta;
        UPDATE propuesta_comercial SET
            id_sede                 = COALESCE(p_id_sede, v_sede_rq),
            id_contacto             = COALESCE(p_id_contacto, v_contacto_rq),
            id_responsable          = COALESCE(p_id_responsable, id_responsable),
            id_moneda               = p_id_moneda,
            subtotal                = v_sub,
            descuento_monto         = v_desc,
            descuento_pct           = NULLIF(p_descuento_pct, 0),
            id_motivo_descuento     = p_id_motivo_descuento,
            igv_pct                 = v_igv_pct,
            igv_monto               = v_igv,
            total                   = v_total,
            aplica_igv              = IFNULL(p_aplica_igv, 1),
            precios_incluyen_igv    = IFNULL(p_precios_incluyen_igv, 0),
            plazo_entrega_dias      = p_plazo_entrega_dias,
            plazo_entrega_unidad    = p_plazo_entrega_unidad,
            plazo_entrega_condicion = p_plazo_entrega_condicion,
            vigencia_dias           = p_vigencia_dias,
            fecha_expiracion        = IF(p_vigencia_dias IS NULL, NULL, DATE_ADD(DATE(fecha_creacion), INTERVAL p_vigencia_dias DAY)),
            introduccion            = p_introduccion,
            notas_generales         = p_notas_generales,
            tipo_servicio           = p_tipo_servicio,
            referencia              = p_referencia,
            secciones_activas       = NULLIF(p_secciones_activas, ''),
            es_tercerizado          = IFNULL(p_es_tercerizado, 0),
            tercero_ruc             = p_tercero_ruc,
            tercero_razon_social    = p_tercero_razon_social,
            tercero_direccion       = p_tercero_direccion,
            tipo_cambio             = p_tipo_cambio,
            garantia_meses          = p_garantia_meses,
            mostrar_garantia        = IFNULL(p_mostrar_garantia, 1),
            subtotal_opcionales     = v_sub_opc,
            descuento_opcionales    = v_desc_opc,
            total_opcionales        = v_total_opc,
            modificado_en           = NOW(),
            modificado_por          = p_id_usuario
        WHERE id_propuesta = v_id;

        SELECT numero, version INTO v_numero, v_version FROM propuesta_comercial WHERE id_propuesta = v_id;
    END IF;

    -- ── Ítems ───────────────────────────────────────────────────────────
    DELETE FROM propuesta_item WHERE id_propuesta = v_id;

    INSERT INTO propuesta_item (
        id_propuesta, seccion, id_catalogo_item, descripcion, alcance, puntos_calibracion,
        cantidad, frecuencia, precio_unitario, descuento, subtotal, es_espaciado, orden,
        creado_en, creado_por
    )
    SELECT
        v_id,
        IF(j.seccion = 'opcional', 'opcional', 'principal'),
        j.id_catalogo_item,
        IFNULL(j.descripcion, ''),
        j.alcance, j.puntos_calibracion,
        IFNULL(j.cantidad, 0), IFNULL(j.frecuencia, 1), IFNULL(j.precio_unitario, 0), IFNULL(j.descuento, 0),
        IF(IFNULL(j.es_espaciado, 0) = 1, 0,
           GREATEST(ROUND(IFNULL(j.cantidad,0) * IFNULL(j.frecuencia,1) * IFNULL(j.precio_unitario,0) - IFNULL(j.descuento,0), 2), 0)),
        IFNULL(j.es_espaciado, 0),
        IFNULL(j.orden, j.fila),
        NOW(), p_id_usuario
    FROM JSON_TABLE(p_items_json, '$[*]' COLUMNS (
            fila               FOR ORDINALITY,
            seccion            VARCHAR(20)   PATH '$.seccion',
            id_catalogo_item   BIGINT        PATH '$.id_catalogo_item',
            descripcion        VARCHAR(300)  PATH '$.descripcion',
            alcance            VARCHAR(100)  PATH '$.alcance',
            puntos_calibracion VARCHAR(100)  PATH '$.puntos_calibracion',
            cantidad           DECIMAL(10,2) PATH '$.cantidad',
            frecuencia         DECIMAL(10,2) PATH '$.frecuencia',
            precio_unitario    DECIMAL(12,2) PATH '$.precio_unitario',
            descuento          DECIMAL(14,2) PATH '$.descuento',
            es_espaciado       TINYINT       PATH '$.es_espaciado',
            orden              INT           PATH '$.orden'
         )) AS j;

    -- ── Textos por sección ──────────────────────────────────────────────
    DELETE FROM propuesta_texto WHERE id_propuesta = v_id;

    INSERT INTO propuesta_texto (id_propuesta, seccion, tipo, texto, id_texto_base, orden, UsuCre, FchCre)
    SELECT v_id, j.seccion, IF(j.tipo = 'titulo', 'titulo', 'vineta'), j.texto, j.id_texto_base,
           IFNULL(j.orden, j.fila), v_usu, NOW()
    FROM JSON_TABLE(p_textos_json, '$[*]' COLUMNS (
            fila          FOR ORDINALITY,
            seccion       VARCHAR(30) PATH '$.seccion',
            tipo          VARCHAR(10) PATH '$.tipo',
            texto         TEXT        PATH '$.texto',
            id_texto_base BIGINT      PATH '$.id_texto_base',
            orden         INT         PATH '$.orden'
         )) AS j
    WHERE IFNULL(j.texto, '') <> '';

    -- ── Formas de pago ──────────────────────────────────────────────────
    DELETE FROM propuesta_forma_pago WHERE id_propuesta = v_id;

    INSERT INTO propuesta_forma_pago (id_propuesta, porcentaje, condicion, orden, UsuCre, FchCre)
    SELECT v_id, j.porcentaje, j.condicion, IFNULL(j.orden, j.fila), v_usu, NOW()
    FROM JSON_TABLE(p_pagos_json, '$[*]' COLUMNS (
            fila       FOR ORDINALITY,
            porcentaje DECIMAL(5,2) PATH '$.porcentaje',
            condicion  VARCHAR(40)  PATH '$.condicion',
            orden      INT          PATH '$.orden'
         )) AS j;

    -- ── Equipos (serie/marca/modelo: del maestro o de la versión ya guardada) ──
    DELETE FROM propuesta_equipo WHERE id_propuesta = v_id;

    INSERT INTO propuesta_equipo (
        id_propuesta, id_equipo, local_sede, tipo, subtipo, num_serie, marca, modelo,
        codigo_cliente, codigo_tw, orden, UsuCre, FchCre
    )
    SELECT
        v_id, j.id_equipo,
        COALESCE(NULLIF(j.local_sede, ''), sc.nombre),
        COALESCE(NULLIF(j.tipo, ''), 'Equipo'),
        COALESCE(NULLIF(j.subtipo, ''), ec.clasificacion),
        COALESCE(ec.num_serie, pv.num_serie, j.num_serie),
        COALESCE(ec.marca,     pv.marca,     j.marca),
        COALESCE(ec.modelo,    pv.modelo,    j.modelo),
        COALESCE(NULLIF(j.codigo_cliente, ''), ec.codigo_cliente),
        COALESCE(ec.codigo_tw, NULLIF(j.codigo_tw, '')),
        IFNULL(j.orden, j.fila), v_usu, NOW()
    FROM JSON_TABLE(p_equipos_json, '$[*]' COLUMNS (
            fila           FOR ORDINALITY,
            id             BIGINT       PATH '$.id',
            id_equipo      BIGINT       PATH '$.id_equipo',
            local_sede     VARCHAR(200) PATH '$.local_sede',
            tipo           VARCHAR(60)  PATH '$.tipo',
            subtipo        VARCHAR(100) PATH '$.subtipo',
            num_serie      VARCHAR(80)  PATH '$.num_serie',
            marca          VARCHAR(80)  PATH '$.marca',
            modelo         VARCHAR(80)  PATH '$.modelo',
            codigo_cliente VARCHAR(80)  PATH '$.codigo_cliente',
            codigo_tw      VARCHAR(30)  PATH '$.codigo_tw',
            orden          INT          PATH '$.orden'
         )) AS j
    LEFT JOIN equipo_cliente ec   ON ec.id_equipo = j.id_equipo
    LEFT JOIN sede_cliente sc     ON sc.id_sede   = ec.id_sede
    LEFT JOIN tmp_prop_eq_prev pv ON pv.id        = j.id;

    DROP TEMPORARY TABLE IF EXISTS tmp_prop_eq_prev;

    -- ── Al crear: RQ pasa a "con propuesta" + historial ─────────────────
    IF v_es_nueva = 1 THEN
        UPDATE requerimiento SET estado = 'con_propuesta', modificado_en = NOW(), modificado_por = p_id_usuario
        WHERE id_requerimiento = p_id_requerimiento AND estado IN ('nuevo', 'en_proceso');

        INSERT INTO historial_requerimiento (id_requerimiento, tipo, tipo_label, icono, descripcion, usuario, fecha, creado_en, creado_por)
        VALUES (p_id_requerimiento, 'propuesta',
                IF(v_version > 1, 'Nueva versión de propuesta', 'Propuesta creada'), 'description',
                CONCAT('Propuesta ', v_numero, ' v', v_version, ' registrada en borrador.'),
                v_usu_nombre, NOW(), NOW(), p_id_usuario);
    END IF;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('propuesta', v_id, IF(v_es_nueva = 1, IF(v_version > 1, 'nueva_version', 'creacion'), 'edicion'),
            IF(v_es_nueva = 1, NULL, 'borrador'), 'borrador',
            CONCAT('Propuesta ', v_numero, ' v', v_version, IF(v_es_nueva = 1, ' creada.', ' actualizada.')),
            p_id_usuario, NOW(),
            JSON_OBJECT('total', v_total, 'total_opcionales', v_total_opc));

    COMMIT;

    SELECT 2 AS IdTipoMensaje,
           IF(v_es_nueva = 1, CONCAT('Propuesta ', v_numero, ' v', v_version, ' creada en borrador.'),
                              'Propuesta guardada correctamente.') AS Mensaje;
    SELECT v_id AS id_propuesta, v_numero AS numero, v_version AS version,
           v_sub AS subtotal, v_desc AS descuento_monto, v_igv AS igv_monto, v_total AS total,
           v_sub_opc AS subtotal_opcionales, v_desc_opc AS descuento_opcionales, v_total_opc AS total_opcionales;
END$$

DELIMITER ;
