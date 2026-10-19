-- HU-13b — Resolver solicitud de revocación de visto bueno
--   El supervisor del área decide si acepta o rechaza la solicitud del comercial.
--   Reglas:
--     * El VB a resolver debe estar en estado 'revocacion_pendiente' y tipo 'revocacion'.
--     * El usuario necesita la acción vb_resolver_revocacion.
--     * Debe pertenecer a la misma área que el comercial autor (modelo bandeja compartida)
--       o tener propuesta_vb_todas.
--     * No puede resolver su propia solicitud.
--     * p_accion in ('aprobar', 'rechazar'); comentario mínimo 10 caracteres si rechaza.
--   Efectos:
--     * aprobar  → VB pasa a 'revocacion_aprobada'. La propuesta aprobada queda terminal
--                   como 'revocada' (preserva auditoría de que fue aprobada y revocada) y
--                   se auto-crea una nueva versión (v+1) en 'borrador', clonando el
--                   contenido completo (cabecera, ítems, textos, formas de pago, equipos).
--                   El comercial edita la nueva versión y la reenvía a VB.
--     * rechazar → VB pasa a 'revocacion_rechazada', propuesta vuelve a 'aprobado'.
--                   El comercial debe enviarla al cliente o aceptar la decisión del jefe.
--   Notifica al comercial, deja historial y auditoría.
--   Devuelve id_nueva_version solo si action='aprobar' (0 si rechazar).
DROP PROCEDURE IF EXISTS SP_ResolverRevocacionVB;

DELIMITER $$

CREATE PROCEDURE SP_ResolverRevocacionVB(
    IN p_id_propuesta BIGINT,
    IN p_accion       VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_comentario   TEXT        CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_usuario   BIGINT
)
proc: BEGIN
    DECLARE v_id_vb         BIGINT;
    DECLARE v_estado_prop   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_numero        VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_version       INT;
    DECLARE v_version_nueva INT;
    DECLARE v_id_rq         BIGINT;
    DECLARE v_autor         BIGINT;
    DECLARE v_estado_vb     VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tipo_vb       VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_solicitante   BIGINT;
    DECLARE v_motivo        TEXT         CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_nuevo_estado_vb   VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_nuevo_estado_prop VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_etiqueta      VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_usu_nombre    VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_usu_correo    VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_nueva      BIGINT       DEFAULT 0;

    -- Variables de totales para recalcular en la nueva versión
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
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SET p_accion     = LOWER(TRIM(IFNULL(p_accion, '')));
    SET p_comentario = NULLIF(TRIM(p_comentario), '');

    IF p_accion NOT IN ('aprobar', 'rechazar') THEN
        SELECT 1 AS IdTipoMensaje, 'Acción no válida. Use aprobar o rechazar.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF p_accion = 'rechazar' AND (p_comentario IS NULL OR CHAR_LENGTH(p_comentario) < 10) THEN
        SELECT 1 AS IdTipoMensaje, 'Indique el motivo del rechazo (mínimo 10 caracteres).' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT estado, numero, version, id_requerimiento, COALESCE(id_responsable, id_creador)
      INTO v_estado_prop, v_numero, v_version, v_id_rq, v_autor
    FROM propuesta_comercial
    WHERE id_propuesta = p_id_propuesta AND eliminado_en IS NULL;

    IF v_estado_prop IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Propuesta no encontrada.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT id_vb, estado, tipo, motivo_revocacion, creado_por
      INTO v_id_vb, v_estado_vb, v_tipo_vb, v_motivo, v_solicitante
    FROM visto_bueno
    WHERE id_propuesta = p_id_propuesta AND estado = 'revocacion_pendiente'
      AND tipo = 'revocacion' AND eliminado_en IS NULL
    ORDER BY id_vb DESC LIMIT 1;

    IF v_id_vb IS NULL OR v_estado_prop <> 'pendiente_revocacion' THEN
        SELECT 1 AS IdTipoMensaje, 'No hay una solicitud de revocación pendiente para esta propuesta.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF FN_PermisoAccion(p_id_usuario, 'vb_resolver_revocacion') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tiene permiso para resolver solicitudes de revocación.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF FN_PermisoAccion(p_id_usuario, 'propuesta_vb_todas') = 0 AND NOT EXISTS (
        SELECT 1 FROM usuario u
        JOIN usuario a ON a.id_usuario = v_autor
        WHERE u.id_usuario = p_id_usuario AND u.eliminado_en IS NULL AND u.estado = 'activo'
          AND u.rol_sistema IN ('supervisor', 'administrador')
          AND u.area        = a.area
    ) THEN
        SELECT 1 AS IdTipoMensaje,
               'Solo supervisores o administradores del área del comercial pueden resolver esta revocación.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF p_id_usuario = v_solicitante AND FN_PermisoAccion(p_id_usuario, 'propuesta_vb_todas') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No puede resolver su propia solicitud de revocación.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_nuevo_estado_vb = IF(p_accion = 'aprobar', 'revocacion_aprobada', 'revocacion_rechazada');
    -- aprobar → propuesta origen queda 'revocada' (terminal, pre-serva historial)
    -- rechazar → vuelve a 'aprobado'
    SET v_nuevo_estado_prop = IF(p_accion = 'aprobar', 'revocada', 'aprobado');
    SET v_etiqueta = IF(p_accion = 'aprobar',
                        'revocación aprobada — se generó una nueva versión en borrador',
                        'revocación rechazada — la propuesta se mantiene aprobada');
    SELECT CONCAT(nombre, ' ', apellido), correo INTO v_usu_nombre, v_usu_correo
    FROM usuario WHERE id_usuario = p_id_usuario;

    START TRANSACTION;

    -- 1. Actualiza el VB de revocación
    UPDATE visto_bueno
       SET estado = v_nuevo_estado_vb, fecha_respuesta = NOW(), resuelto_por = p_id_usuario,
           comentario_respuesta = p_comentario, modificado_en = NOW(), modificado_por = p_id_usuario
     WHERE id_vb = v_id_vb;

    -- 2. Actualiza la propuesta
    UPDATE propuesta_comercial
       SET estado = v_nuevo_estado_prop, modificado_en = NOW(), modificado_por = p_id_usuario
     WHERE id_propuesta = p_id_propuesta;

    -- 3. Si se aprobó la revocación → clona a nueva versión v+1 en borrador
    IF p_accion = 'aprobar' THEN
        SET v_version_nueva = v_version + 1;

        -- Cabecera clonada
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
            o.numero, v_version_nueva, o.id_requerimiento, o.id_cliente,
            o.id_sede, o.id_contacto, o.id_responsable, o.id_moneda,
            0,
            o.descuento_monto, o.descuento_pct, o.id_motivo_descuento,
            o.igv_pct, 0, 0, o.aplica_igv, o.precios_incluyen_igv,
            o.plazo_entrega_dias, o.plazo_entrega_unidad, o.plazo_entrega_condicion, o.vigencia_dias,
            o.introduccion, o.notas_generales, o.tipo_servicio, o.referencia, o.secciones_activas,
            o.es_tercerizado, o.tercero_ruc, o.tercero_razon_social, o.tercero_direccion,
            o.tipo_cambio, o.garantia_meses, o.mostrar_garantia,
            0, o.descuento_opcionales, 0,
            'borrador', o.id_propuesta, NULL,
            CONCAT('Versión generada tras aprobación de revocación de VB. Motivo original: ', IFNULL(v_motivo, '—')),
            o.id_responsable, NOW(),
            IF(o.vigencia_dias IS NOT NULL, DATE_ADD(CURDATE(), INTERVAL o.vigencia_dias DAY), NULL),
            NOW(), p_id_usuario
        FROM propuesta_comercial o
        WHERE o.id_propuesta = p_id_propuesta;

        SET v_id_nueva = LAST_INSERT_ID();

        -- Ítems
        INSERT INTO propuesta_item (
            id_propuesta, seccion, id_catalogo_item, descripcion, alcance, puntos_calibracion,
            cantidad, frecuencia, precio_unitario, descuento, subtotal, es_espaciado, orden,
            creado_en, creado_por
        )
        SELECT v_id_nueva, seccion, id_catalogo_item, descripcion, alcance, puntos_calibracion,
               cantidad, frecuencia, precio_unitario, descuento, subtotal, es_espaciado, orden,
               NOW(), p_id_usuario
        FROM propuesta_item
        WHERE id_propuesta = p_id_propuesta AND eliminado_en IS NULL
        ORDER BY seccion, orden, id_item;

        -- Textos
        INSERT INTO propuesta_texto (id_propuesta, seccion, tipo, texto, id_texto_base, orden, UsuCre, FchCre)
        SELECT v_id_nueva, seccion, tipo, texto, id_texto_base, orden, v_usu_correo, NOW()
        FROM propuesta_texto
        WHERE id_propuesta = p_id_propuesta
        ORDER BY seccion, orden, id;

        -- Formas de pago
        INSERT INTO propuesta_forma_pago (id_propuesta, porcentaje, condicion, orden, UsuCre, FchCre)
        SELECT v_id_nueva, porcentaje, condicion, orden, v_usu_correo, NOW()
        FROM propuesta_forma_pago
        WHERE id_propuesta = p_id_propuesta
        ORDER BY orden, id;

        -- Equipos
        INSERT INTO propuesta_equipo (
            id_propuesta, id_equipo, local_sede, tipo, subtipo, num_serie, marca, modelo,
            codigo_cliente, codigo_tw, orden, UsuCre, FchCre
        )
        SELECT v_id_nueva, id_equipo, local_sede, tipo, subtipo, num_serie, marca, modelo,
               codigo_cliente, codigo_tw, orden, v_usu_correo, NOW()
        FROM propuesta_equipo
        WHERE id_propuesta = p_id_propuesta
        ORDER BY orden, id;

        -- Recalcular totales (misma fórmula que SP_GuardarPropuesta y SP_CrearNuevaVersionPropuesta)
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

        -- Auditoría de la nueva versión
        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
        VALUES ('propuesta', v_id_nueva, 'nueva_version_por_revocacion', NULL, 'borrador',
                CONCAT('Propuesta ', v_numero, ' v', v_version_nueva, ' creada en borrador tras aprobación de revocación de VB.'),
                p_id_usuario, NOW(),
                JSON_OBJECT('id_propuesta_origen', p_id_propuesta,
                            'version_origen',      v_version,
                            'motivo_revocacion',   v_motivo,
                            'total',               v_total));
    END IF;

    -- 4. Notificación al solicitante (comercial)
    INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
    VALUES (v_solicitante, 5,
            CONCAT('Solicitud de revocación ',
                   IF(p_accion = 'aprobar', 'aprobada: ', 'rechazada: '), v_numero, ' v', v_version),
            CONCAT(v_usu_nombre, ' ',
                   IF(p_accion = 'aprobar',
                      CONCAT('aprobó revocar la aprobación. Se creó la v', v_version + 1, ' en borrador para que la ajustes y la reenvíes a VB.'),
                      CONCAT('rechazó revocar la aprobación: ', IFNULL(p_comentario, '')))),
            'propuesta', IF(p_accion = 'aprobar', v_id_nueva, p_id_propuesta), NOW(), p_id_usuario);

    -- 5. Historial del RQ
    IF v_id_rq IS NOT NULL THEN
        INSERT INTO historial_requerimiento (id_requerimiento, tipo, tipo_label, icono, descripcion, usuario, fecha, creado_en, creado_por)
        VALUES (v_id_rq, 'propuesta',
                CONCAT('Revocación ', IF(p_accion = 'aprobar', 'aprobada', 'rechazada')),
                IF(p_accion = 'aprobar', 'restart_alt', 'cancel'),
                CONCAT('Propuesta ', v_numero, ' v', v_version, ': ', v_etiqueta, '.'),
                v_usu_nombre, NOW(), NOW(), p_id_usuario);
    END IF;

    -- 6. Auditoría de la decisión
    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('propuesta', p_id_propuesta, CONCAT('resolver_revocacion_', p_accion),
            'pendiente_revocacion', v_nuevo_estado_prop,
            CONCAT('Revocación ', IF(p_accion = 'aprobar', 'aprobada', 'rechazada'),
                   ' por ', v_usu_nombre,
                   IF(p_comentario IS NULL, '', CONCAT(': ', p_comentario))),
            p_id_usuario, NOW(),
            JSON_OBJECT('id_vb', v_id_vb, 'motivo_solicitud', v_motivo,
                        'comentario_resolucion', p_comentario,
                        'solicitante', v_solicitante,
                        'id_nueva_version', v_id_nueva));

    COMMIT;

    SELECT 2 AS IdTipoMensaje,
           IF(p_accion = 'aprobar',
              CONCAT('Revocación aprobada. Se creó la v', v_version + 1, ' en borrador.'),
              'Revocación rechazada. La propuesta se mantiene aprobada.') AS Mensaje;
    SELECT p_id_propuesta AS id_propuesta, v_numero AS numero, v_version AS version,
           v_nuevo_estado_prop AS estado, v_nuevo_estado_vb AS estado_vb, v_id_vb AS id_vb,
           v_id_nueva AS id_nueva_version;
END$$

DELIMITER ;
