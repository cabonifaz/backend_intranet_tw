-- HU-40 / HU-43 / HU-44 (Sprint 4) Guardar borrador, emitir o guardar la edición autorizada de una OS/OM.
--   p_id_os = 0: crea la orden desde la propuesta aceptada p_id_propuesta (una propuesta genera UNA OS u OM).
--   p_datos: { idContacto, fechaProgramadaDesde, fechaProgramadaHasta (solo OS, AAAA-MM-DD), observaciones,
--              certRazonSocial, certRuc, certDireccion, certContacto (solo OM; editables solo si es tercerizado) }
--   p_conceptos: [{ idSuministro }]  suministros de clase servicio, sin precios
--   p_equipos:   [{ idEquipo, conceptos: [idSuministro, ...] }]  equipos del cliente y los conceptos que les aplican
--                (un concepto que ningún equipo elige aplica a toda la orden: "General")
--   p_emitir = 1: el borrador pasa a EMITIDA (queda disponible para Programación). Exige contacto, al menos un concepto,
--                 el rango de fecha programada (OS) y los datos del certificado (OM).
--   Orden ya emitida: solo con una solicitud de edición APROBADA del usuario; al guardar, la solicitud queda ejecutada.
--   p_importacion (opcional, HU-44): resumen de la importación por Excel aplicada en el formulario
--     { nombreArchivo, modo (fusionar|reemplazar), conceptos, equipos, relaciones, advertencias } → auditoría.
-- Resultados: 1 mensaje, 2 orden (id_os, numero, tipo, estado).
DROP PROCEDURE IF EXISTS SP_GuardarOrdenServicio;

DELIMITER $$

CREATE PROCEDURE SP_GuardarOrdenServicio(
    IN p_id_usuario   BIGINT,
    IN p_id_os        BIGINT,
    IN p_id_propuesta BIGINT,
    IN p_datos        JSON,
    IN p_conceptos    JSON,
    IN p_equipos      JSON,
    IN p_emitir       TINYINT,
    IN p_importacion  JSON
)
proc: BEGIN
    DECLARE v_id_os      BIGINT DEFAULT NULL;
    DECLARE v_id_prop    BIGINT;
    DECLARE v_estado     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado_nue VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tipo       CHAR(2);
    DECLARE v_resp       BIGINT;
    DECLARE v_id_cliente BIGINT;
    DECLARE v_id_sol     BIGINT DEFAULT NULL;
    DECLARE v_numero     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_otra       VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tercero    TINYINT DEFAULT 0;
    DECLARE v_contacto   BIGINT;
    DECLARE v_desde      DATE;
    DECLARE v_hasta      DATE;
    DECLARE v_obs        TEXT         CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_c_razon    VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_c_ruc      VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_c_dir      VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_c_cont     VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_emitida    TINYINT DEFAULT 0;
    DECLARE v_n_conc     INT DEFAULT 0;
    DECLARE v_n_eq       INT DEFAULT 0;
    DECLARE v_n_rel      INT DEFAULT 0;
    DECLARE v_error      VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_usuario    VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cliente    VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_os_g_conc;
        DROP TEMPORARY TABLE IF EXISTS tmp_os_g_eq;
        DROP TEMPORARY TABLE IF EXISTS tmp_os_g_rel;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF FN_PermisoAccion(p_id_usuario, 'os_guardar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para crear o editar órdenes de servicio.' AS Mensaje; LEAVE proc;
    END IF;

    -- ── Orden: nueva o existente ────────────────────────────────────────────
    IF IFNULL(p_id_os, 0) > 0 THEN
        SELECT os.id_os, os.id_propuesta, os.estado, os.tipo, os.id_responsable_comercial, os.numero
          INTO v_id_os, v_id_prop, v_estado, v_tipo, v_resp, v_numero
        FROM orden_servicio os WHERE os.id_os = p_id_os AND os.eliminado_en IS NULL;
        IF v_id_os IS NULL THEN
            SELECT 1 AS IdTipoMensaje, 'Orden de servicio no encontrada.' AS Mensaje; LEAVE proc;
        END IF;
        IF v_id_prop IS NULL THEN
            SELECT 1 AS IdTipoMensaje, 'Esta orden es anterior al módulo y no tiene propuesta origen: no se puede editar aquí.' AS Mensaje;
            LEAVE proc;
        END IF;
        IF v_estado = 'borrador' THEN
            IF NOT (v_resp IS NULL OR v_resp = p_id_usuario OR FN_PermisoAccion(p_id_usuario, 'os_aprobar_edicion') = 1) THEN
                SELECT 1 AS IdTipoMensaje, 'Solo el responsable de la orden o el Jefe Comercial pueden editar el borrador.' AS Mensaje;
                LEAVE proc;
            END IF;
        ELSE
            SELECT MAX(s.id_solicitud) INTO v_id_sol FROM os_solicitud s
            WHERE s.id_os = v_id_os AND s.tipo = 'edicion' AND s.estado = 'aprobada' AND s.id_solicitante = p_id_usuario
              AND s.eliminado_en IS NULL;
            IF v_id_sol IS NULL OR v_estado NOT IN ('emitida', 'programada', 'reprogramada') THEN
                SELECT 1 AS IdTipoMensaje,
                       CONCAT('La orden está ', UPPER(REPLACE(v_estado, '_', ' ')),
                              ': para modificarla solicite la edición al Jefe Comercial.') AS Mensaje;
                LEAVE proc;
            END IF;
            SET v_emitida = 1;
        END IF;
    ELSE
        SET v_id_prop = p_id_propuesta;
        IF NOT EXISTS (SELECT 1 FROM propuesta_comercial WHERE id_propuesta = v_id_prop AND eliminado_en IS NULL) THEN
            SELECT 1 AS IdTipoMensaje, 'Propuesta no encontrada.' AS Mensaje; LEAVE proc;
        END IF;
        IF NOT EXISTS (SELECT 1 FROM propuesta_comercial WHERE id_propuesta = v_id_prop AND estado = 'aceptado') THEN
            SELECT 1 AS IdTipoMensaje, 'La OS/OM solo se genera desde una propuesta aceptada por el cliente.' AS Mensaje; LEAVE proc;
        END IF;
        SELECT CONCAT(os.numero, ' (', UPPER(REPLACE(os.estado, '_', ' ')), ')') INTO v_otra
        FROM orden_servicio os
        WHERE os.id_propuesta = v_id_prop AND os.eliminado_en IS NULL AND os.estado <> 'anulada'
        ORDER BY os.id_os DESC LIMIT 1;
        IF v_otra IS NOT NULL THEN
            SELECT 1 AS IdTipoMensaje, CONCAT('La propuesta ya tiene la orden ', v_otra, ': una propuesta genera una sola OS u OM.') AS Mensaje;
            LEAVE proc;
        END IF;
        SELECT IF(IFNULL(a.String1, '') LIKE '%metrolog%', 'OM', 'OS'), COALESCE(p.id_responsable, p.id_creador)
          INTO v_tipo, v_resp
        FROM propuesta_comercial p
        LEFT JOIN requerimiento r ON r.id_requerimiento = p.id_requerimiento
        LEFT JOIN tabla_maestra a ON a.IdMaestro = 64 AND a.IdEmpresa = 1 AND a.Num1 = r.id_area
        WHERE p.id_propuesta = v_id_prop;
        SET v_estado = 'borrador';
    END IF;

    SELECT p.id_cliente, IFNULL(p.es_tercerizado, 0), c.razon_social
      INTO v_id_cliente, v_tercero, v_cliente
    FROM propuesta_comercial p JOIN cliente c ON c.id_cliente = p.id_cliente
    WHERE p.id_propuesta = v_id_prop;

    -- ── Datos del documento ─────────────────────────────────────────────────
    SET p_datos    = IFNULL(p_datos, JSON_OBJECT());
    SET v_contacto = CAST(NULLIF(FN_JsonTexto(p_datos, '$.idContacto'), '') AS UNSIGNED);
    SET v_obs      = NULLIF(TRIM(FN_JsonTexto(p_datos, '$.observaciones')), '');
    IF v_tipo = 'OS' THEN
        SET v_desde = STR_TO_DATE(LEFT(FN_JsonTexto(p_datos, '$.fechaProgramadaDesde'), 10), '%Y-%m-%d');
        SET v_hasta = STR_TO_DATE(LEFT(FN_JsonTexto(p_datos, '$.fechaProgramadaHasta'), 10), '%Y-%m-%d');
    END IF;

    IF v_contacto IS NOT NULL AND NOT EXISTS (SELECT 1 FROM contacto_cliente WHERE id_contacto = v_contacto
                                                AND id_cliente = v_id_cliente AND SoftDelete = 0) THEN
        SET v_error = 'El contacto no pertenece al cliente.';
    ELSEIF v_desde IS NOT NULL AND v_hasta IS NOT NULL AND v_desde > v_hasta THEN
        SET v_error = 'La fecha programada "Desde" no puede ser posterior a "Hasta".';
    ELSEIF CHAR_LENGTH(IFNULL(v_obs, '')) > 2000 THEN
        SET v_error = 'Las observaciones admiten hasta 2000 caracteres.';
    END IF;

    -- Certificado (solo OM): si no es tercerizado, son los datos del cliente contratante (no editables)
    IF v_tipo = 'OM' THEN
        IF v_tercero = 1 THEN
            SET v_c_razon = NULLIF(TRIM(FN_JsonTexto(p_datos, '$.certRazonSocial')), '');
            SET v_c_ruc   = NULLIF(REGEXP_REPLACE(IFNULL(FN_JsonTexto(p_datos, '$.certRuc'), ''), '[^0-9]', ''), '');
            SET v_c_dir   = NULLIF(TRIM(FN_JsonTexto(p_datos, '$.certDireccion')), '');
            SET v_c_cont  = NULLIF(TRIM(FN_JsonTexto(p_datos, '$.certContacto')), '');
        ELSE
            SELECT c.razon_social, c.ruc, COALESCE(NULLIF(c.direccion_fiscal, ''), c.domicilio_fiscal)
              INTO v_c_razon, v_c_ruc, v_c_dir
            FROM cliente c WHERE c.id_cliente = v_id_cliente;
            SELECT nombres INTO v_c_cont FROM contacto_cliente WHERE id_contacto = v_contacto;
        END IF;
        IF v_error IS NULL AND v_c_ruc IS NOT NULL AND v_c_ruc NOT REGEXP '^[0-9]{11}$' THEN
            SET v_error = 'El RUC del certificado debe tener 11 dígitos.';
        ELSEIF v_error IS NULL AND (CHAR_LENGTH(IFNULL(v_c_razon, '')) > 300 OR CHAR_LENGTH(IFNULL(v_c_dir, '')) > 500
                                    OR CHAR_LENGTH(IFNULL(v_c_cont, '')) > 200) THEN
            SET v_error = 'Algún dato del certificado es demasiado largo.';
        END IF;
    END IF;

    IF v_error IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, v_error AS Mensaje; LEAVE proc;
    END IF;

    -- ── Conceptos y equipos ─────────────────────────────────────────────────
    DROP TEMPORARY TABLE IF EXISTS tmp_os_g_conc;
    CREATE TEMPORARY TABLE tmp_os_g_conc (orden INT, id_suministro BIGINT, PRIMARY KEY (id_suministro));
    INSERT IGNORE INTO tmp_os_g_conc
    SELECT j.orden, j.id FROM JSON_TABLE(IFNULL(p_conceptos, JSON_ARRAY()), '$[*]'
                          COLUMNS (orden FOR ORDINALITY, id BIGINT PATH '$.idSuministro')) j
    WHERE j.id IS NOT NULL;

    DROP TEMPORARY TABLE IF EXISTS tmp_os_g_eq;
    CREATE TEMPORARY TABLE tmp_os_g_eq (orden INT, id_equipo BIGINT, PRIMARY KEY (id_equipo));
    INSERT IGNORE INTO tmp_os_g_eq
    SELECT j.orden, j.id FROM JSON_TABLE(IFNULL(p_equipos, JSON_ARRAY()), '$[*]'
                          COLUMNS (orden FOR ORDINALITY, id BIGINT PATH '$.idEquipo')) j
    WHERE j.id IS NOT NULL;

    DROP TEMPORARY TABLE IF EXISTS tmp_os_g_rel;
    CREATE TEMPORARY TABLE tmp_os_g_rel (id_equipo BIGINT, id_suministro BIGINT, PRIMARY KEY (id_equipo, id_suministro));
    INSERT IGNORE INTO tmp_os_g_rel
    SELECT j.id, j.id_sum
    FROM JSON_TABLE(IFNULL(p_equipos, JSON_ARRAY()), '$[*]'
                    COLUMNS (id BIGINT PATH '$.idEquipo',
                             NESTED PATH '$.conceptos[*]' COLUMNS (id_sum BIGINT PATH '$'))) j
    WHERE j.id IS NOT NULL AND j.id_sum IS NOT NULL;

    SELECT COUNT(*) INTO v_n_conc FROM tmp_os_g_conc;
    SELECT COUNT(*) INTO v_n_eq   FROM tmp_os_g_eq;
    SELECT COUNT(*) INTO v_n_rel  FROM tmp_os_g_rel;

    IF v_n_conc > 200 THEN
        SET v_error = 'Una orden admite hasta 200 conceptos.';
    ELSEIF v_n_eq > 1000 THEN
        SET v_error = 'Una orden admite hasta 1000 equipos.';
    ELSEIF EXISTS (SELECT 1 FROM tmp_os_g_conc t
                   WHERE NOT EXISTS (SELECT 1 FROM suministros s WHERE s.id_suministro = t.id_suministro
                                       AND s.clase = 'servicio' AND s.eliminado_en IS NULL AND s.estado = 'activo')
                     -- un concepto ya guardado se conserva aunque el suministro se haya desactivado después
                     AND NOT EXISTS (SELECT 1 FROM os_concepto oc WHERE oc.id_os = IFNULL(v_id_os, 0)
                                       AND oc.id_suministro = t.id_suministro AND oc.eliminado_en IS NULL)) THEN
        SET v_error = 'Hay conceptos que no son suministros de tipo Servicio activos del catálogo.';
    ELSEIF EXISTS (SELECT 1 FROM tmp_os_g_eq t
                   WHERE NOT EXISTS (SELECT 1 FROM equipo_cliente ec WHERE ec.id_equipo = t.id_equipo
                                       AND ec.id_cliente = v_id_cliente AND ec.SoftDelete = 0)) THEN
        SET v_error = 'Hay equipos que no pertenecen al catálogo del cliente.';
    ELSEIF EXISTS (SELECT 1 FROM tmp_os_g_rel r
                   WHERE NOT EXISTS (SELECT 1 FROM tmp_os_g_conc c WHERE c.id_suministro = r.id_suministro)) THEN
        SET v_error = 'Un equipo tiene asignado un concepto que no está en la sección Conceptos del Servicio.';
    END IF;

    -- Emitir (o guardar una orden ya emitida): la orden debe estar completa
    IF v_error IS NULL AND (IFNULL(p_emitir, 0) = 1 OR v_emitida = 1) THEN
        IF v_contacto IS NULL THEN
            SET v_error = 'Seleccione el contacto del cliente.';
        ELSEIF v_n_conc = 0 THEN
            SET v_error = 'Agregue al menos un concepto del servicio.';
        ELSEIF v_tipo = 'OS' AND (v_desde IS NULL OR v_hasta IS NULL) THEN
            SET v_error = 'Indique el rango de fecha programada tentativa (Desde y Hasta).';
        ELSEIF v_tipo = 'OM' AND (v_c_razon IS NULL OR v_c_ruc IS NULL) THEN
            SET v_error = 'Complete la razón social y el RUC para la emisión del certificado.';
        END IF;
    END IF;

    IF v_error IS NOT NULL THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_os_g_conc;
        DROP TEMPORARY TABLE IF EXISTS tmp_os_g_eq;
        DROP TEMPORARY TABLE IF EXISTS tmp_os_g_rel;
        SELECT 1 AS IdTipoMensaje, v_error AS Mensaje; LEAVE proc;
    END IF;

    SELECT CONCAT(nombre, ' ', apellido) INTO v_usuario FROM usuario WHERE id_usuario = p_id_usuario;

    START TRANSACTION;

    -- ── Cabecera ────────────────────────────────────────────────────────────
    IF v_id_os IS NULL THEN
        SELECT CONCAT(v_tipo, '-', LPAD(IFNULL(MAX(CAST(SUBSTRING(numero, 4) AS UNSIGNED)), 0) + 1, 6, '0')) INTO v_numero
        FROM orden_servicio WHERE numero REGEXP CONCAT('^', v_tipo, '-[0-9]+$') FOR UPDATE;

        INSERT INTO orden_servicio (numero, tipo, id_expediente, id_propuesta, id_requerimiento, id_cliente, id_sede, id_contacto,
                                    id_responsable_comercial, estado, fecha_programada_desde, fecha_programada_hasta,
                                    observaciones, es_tercerizado, cert_razon_social, cert_ruc, cert_direccion, cert_contacto,
                                    confirmacion_cliente, fecha_creacion, creado_en, creado_por)
        SELECT v_numero, v_tipo, FN_ExpedienteDePropuesta(p.id_propuesta), p.id_propuesta, p.id_requerimiento, p.id_cliente,
               p.id_sede, v_contacto, v_resp, 'borrador', v_desde, v_hasta, v_obs, v_tercero,
               v_c_razon, v_c_ruc, v_c_dir, v_c_cont, 0, NOW(), NOW(), p_id_usuario
        FROM propuesta_comercial p WHERE p.id_propuesta = v_id_prop;
        SET v_id_os = LAST_INSERT_ID();
    ELSE
        UPDATE orden_servicio SET
            id_contacto            = v_contacto,
            fecha_programada_desde = v_desde,
            fecha_programada_hasta = v_hasta,
            observaciones          = v_obs,
            cert_razon_social      = v_c_razon,
            cert_ruc               = v_c_ruc,
            cert_direccion         = v_c_dir,
            cert_contacto          = v_c_cont,
            id_expediente          = IFNULL(id_expediente, FN_ExpedienteDePropuesta(v_id_prop)),
            modificado_por         = p_id_usuario,
            modificado_en          = NOW()
        WHERE id_os = v_id_os;
    END IF;

    -- ── Conceptos: se conservan los que siguen, se agregan los nuevos y se quitan los demás ──
    UPDATE os_concepto oc
    LEFT JOIN tmp_os_g_conc t ON t.id_suministro = oc.id_suministro
    SET oc.eliminado_en = IF(t.id_suministro IS NULL, NOW(), oc.eliminado_en),
        oc.eliminado_por = IF(t.id_suministro IS NULL, p_id_usuario, oc.eliminado_por),
        oc.orden = IFNULL(t.orden, oc.orden),
        oc.modificado_por = p_id_usuario
    WHERE oc.id_os = v_id_os AND oc.eliminado_en IS NULL;

    INSERT INTO os_concepto (id_os, id_suministro, codigo, descripcion, orden, creado_por)
    SELECT v_id_os, s.id_suministro, s.codigo, LEFT(s.descripcion, 300), t.orden, p_id_usuario
    FROM tmp_os_g_conc t
    JOIN suministros s ON s.id_suministro = t.id_suministro
    WHERE NOT EXISTS (SELECT 1 FROM os_concepto oc WHERE oc.id_os = v_id_os AND oc.id_suministro = t.id_suministro
                        AND oc.eliminado_en IS NULL);

    -- ── Equipos (se conserva su avance de ejecución) ────────────────────────
    UPDATE os_equipo oe
    LEFT JOIN tmp_os_g_eq t ON t.id_equipo = oe.id_equipo
    SET oe.eliminado_en = IF(t.id_equipo IS NULL, NOW(), oe.eliminado_en),
        oe.eliminado_por = IF(t.id_equipo IS NULL, p_id_usuario, oe.eliminado_por),
        oe.orden = IFNULL(t.orden, oe.orden),
        oe.modificado_por = p_id_usuario
    WHERE oe.id_os = v_id_os AND oe.eliminado_en IS NULL;

    INSERT INTO os_equipo (id_os, id_equipo, orden, ingresado_en_campo, estado_ejecucion, creado_por)
    SELECT v_id_os, t.id_equipo, t.orden, 0, 'pendiente', p_id_usuario
    FROM tmp_os_g_eq t
    WHERE NOT EXISTS (SELECT 1 FROM os_equipo oe WHERE oe.id_os = v_id_os AND oe.id_equipo = t.id_equipo
                        AND oe.eliminado_en IS NULL);

    -- ── Concepto ↔ equipo: se reemplaza la relación completa ────────────────
    UPDATE os_concepto_equipo SET eliminado_en = NOW(), eliminado_por = p_id_usuario
    WHERE id_os = v_id_os AND eliminado_en IS NULL;

    INSERT INTO os_concepto_equipo (id_os, id_os_concepto, id_os_equipo, creado_por)
    SELECT v_id_os, oc.id, oe.id, p_id_usuario
    FROM tmp_os_g_rel r
    JOIN os_concepto oc ON oc.id_os = v_id_os AND oc.id_suministro = r.id_suministro AND oc.eliminado_en IS NULL
    JOIN os_equipo oe   ON oe.id_os = v_id_os AND oe.id_equipo = r.id_equipo AND oe.eliminado_en IS NULL;

    DROP TEMPORARY TABLE IF EXISTS tmp_os_g_conc;
    DROP TEMPORARY TABLE IF EXISTS tmp_os_g_eq;
    DROP TEMPORARY TABLE IF EXISTS tmp_os_g_rel;

    -- ── Importación por Excel (HU-44): queda en la auditoría ────────────────
    IF p_importacion IS NOT NULL AND JSON_TYPE(p_importacion) = 'OBJECT' THEN
        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion,
                                      id_usuario, registrado_en, metadata)
        VALUES ('orden_servicio', v_id_os, 'importar_excel_os', NULL, NULL,
                LEFT(CONCAT('Importación desde Excel', IFNULL(CONCAT(' (', FN_JsonTexto(p_importacion, '$.nombreArchivo'), ')'), ''),
                            ': ', IFNULL(FN_JsonTexto(p_importacion, '$.conceptos'), '0'), ' conceptos, ',
                            IFNULL(FN_JsonTexto(p_importacion, '$.equipos'), '0'), ' equipos y ',
                            IFNULL(FN_JsonTexto(p_importacion, '$.relaciones'), '0'), ' relaciones',
                            IF(IFNULL(FN_JsonTexto(p_importacion, '$.modo'), '') = 'reemplazar', ' (reemplazó lo anterior)',
                               ' (fusionado con lo existente)'),
                            IF(CAST(IFNULL(FN_JsonTexto(p_importacion, '$.advertencias'), '0') AS UNSIGNED) > 0,
                               CONCAT('; ', FN_JsonTexto(p_importacion, '$.advertencias'), ' advertencias aceptadas'), ''),
                            '.'), 1000),
                p_id_usuario, NOW(), p_importacion);
    END IF;

    -- ── Emisión / edición autorizada ────────────────────────────────────────
    SET v_estado_nue = v_estado;
    IF IFNULL(p_emitir, 0) = 1 AND v_estado = 'borrador' THEN
        SET v_estado_nue = 'emitida';
        UPDATE orden_servicio SET estado = 'emitida', fecha_emision = NOW(), emitido_por = p_id_usuario
        WHERE id_os = v_id_os;

        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion,
                                      id_usuario, registrado_en, metadata)
        VALUES ('orden_servicio', v_id_os, 'emitir_os', 'borrador', 'emitida',
                CONCAT(v_tipo, ' ', v_numero, ' emitida: ', v_n_eq, ' equipos y ', v_n_conc, ' conceptos. Pasa a Programación.'),
                p_id_usuario, NOW(), JSON_OBJECT('equipos', v_n_eq, 'conceptos', v_n_conc));

        -- Aviso a Operaciones (supervisores y administradores): la orden queda disponible para programar
        INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
        SELECT u.id_usuario, 5, CONCAT(v_tipo, ' emitida: ', v_numero),
               CONCAT(IFNULL(v_usuario, 'Comercial'), ' emitió la ', v_tipo, ' ', v_numero, ' de ', IFNULL(v_cliente, 'el cliente'),
                      ' (', v_n_eq, ' equipos, ', v_n_conc, ' conceptos). Está lista para Programación.'),
               'orden_servicio', v_id_os, NOW(), p_id_usuario
        FROM usuario u
        WHERE u.eliminado_en IS NULL AND u.estado = 'activo' AND u.id_usuario <> p_id_usuario
          AND u.area = 'operaciones' AND u.rol_sistema IN ('supervisor', 'administrador');
    ELSEIF v_id_sol IS NOT NULL THEN
        UPDATE os_solicitud SET estado = 'ejecutada', fecha_ejecucion = NOW(), modificado_por = p_id_usuario
        WHERE id_solicitud = v_id_sol;

        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion,
                                      id_usuario, registrado_en, metadata)
        VALUES ('orden_servicio', v_id_os, 'editar_os', v_estado, v_estado,
                CONCAT(v_tipo, ' ', v_numero, ' editada con la autorización del Jefe Comercial y re-emitida: ',
                       v_n_eq, ' equipos y ', v_n_conc, ' conceptos.'),
                p_id_usuario, NOW(), JSON_OBJECT('id_solicitud', v_id_sol));

        INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
        SELECT u.id_usuario, 5, CONCAT(v_tipo, ' modificada: ', v_numero),
               CONCAT(IFNULL(v_usuario, 'Comercial'), ' modificó y re-emitió la ', v_tipo, ' ', v_numero, ' de ',
                      IFNULL(v_cliente, 'el cliente'), '. Revise la programación.'),
               'orden_servicio', v_id_os, NOW(), p_id_usuario
        FROM usuario u
        WHERE u.eliminado_en IS NULL AND u.estado = 'activo' AND u.id_usuario <> p_id_usuario
          AND u.area = 'operaciones' AND u.rol_sistema IN ('supervisor', 'administrador');
    END IF;

    COMMIT;

    SELECT 2 AS IdTipoMensaje,
           CASE WHEN v_estado_nue = 'emitida' AND v_estado = 'borrador' THEN CONCAT(v_tipo, ' ', v_numero, ' emitida. Quedó disponible para Programación.')
                WHEN v_id_sol IS NOT NULL THEN CONCAT('Cambios guardados: ', v_tipo, ' ', v_numero, ' re-emitida.')
                ELSE CONCAT('Borrador ', v_numero, ' guardado.') END AS Mensaje;

    SELECT v_id_os AS id_os, v_numero AS numero, v_tipo AS tipo, v_estado_nue AS estado;
END$$

DELIMITER ;
