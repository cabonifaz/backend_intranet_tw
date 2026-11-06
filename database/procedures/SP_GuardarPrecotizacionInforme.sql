-- HU-58 (Sprint 5) Revisión Técnica: paso 4 "Hallazgos y Precotización" (obligatoria si el servicio tiene observaciones).
-- Acceso: rt_editar. El informe no debe estar revisado y debe tener al menos una observación.
--   p_nota  : observaciones del supervisor para Comercial (hasta 1000; se copia como nota en la nueva propuesta).
--   p_items : lista completa [{id, concepto, codigo, idSuministro, descripcionTecnica, cantidad, unidad, prioridad: alta|media|opcional,
--                              idObservacion}]  (al menos 1 ítem; con id = se actualiza, sin id = se agrega, los que faltan se eliminan).
-- Una precotización por informe (PCT-NNNNNN). Al guardarla queda ENVIADA a la bandeja "Precotizaciones Técnicas" del área Comercial,
-- asociada al RQ de origen, y se avisa al responsable del RQ. Una precotización ya convertida en propuesta no se edita.
-- Resultados: 1 mensaje, 2 precotización (id, número, ítems, estado).
DROP PROCEDURE IF EXISTS SP_GuardarPrecotizacionInforme;

DELIMITER $$

CREATE PROCEDURE SP_GuardarPrecotizacionInforme(
    IN p_id_usuario BIGINT,
    IN p_id_informe BIGINT,
    IN p_nota       VARCHAR(1000) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_items      JSON
)
proc: BEGIN
    DECLARE v_existe     INT DEFAULT 0;
    DECLARE v_estado     VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_n_obs      INT DEFAULT 0;
    DECLARE v_id_pc      BIGINT DEFAULT NULL;
    DECLARE v_estado_pc  VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_numero     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_os      BIGINT;
    DECLARE v_id_equipo  BIGINT;
    DECLARE v_id_rq      BIGINT;
    DECLARE v_id_cliente BIGINT;
    DECLARE v_id_resp    BIGINT;
    DECLARE v_numero_os  VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cliente    VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_diag       TEXT         CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tipo_serv  INT;
    DECLARE v_nuevo      TINYINT DEFAULT 0;
    DECLARE v_cambios    INT DEFAULT 0;
    DECLARE v_n          INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_in_pci;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF FN_PermisoAccion(p_id_usuario, 'rt_editar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para registrar precotizaciones.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_ArmarBaseInformes(p_id_usuario, IFNULL(p_id_informe, 0));
    SELECT COUNT(*), MAX(n_observaciones), MAX(id_os), MAX(id_equipo), MAX(id_requerimiento), MAX(id_cliente), MAX(id_responsable_rq),
           MAX(numero_os), MAX(razon_social), MAX(diagnostico), MAX(id_tipo_servicio)
      INTO v_existe, v_n_obs, v_id_os, v_id_equipo, v_id_rq, v_id_cliente, v_id_resp, v_numero_os, v_cliente, v_diag, v_tipo_serv
    FROM tmp_rt_base;
    DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;
    IF v_existe = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El informe no existe o no está en tu alcance.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_n_obs = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El servicio no tiene observaciones: no requiere precotización.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF p_items IS NULL OR JSON_TYPE(p_items) <> 'ARRAY' OR JSON_LENGTH(p_items) = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Agrega al menos un concepto a la precotización.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF JSON_LENGTH(p_items) > 50 THEN
        SELECT 1 AS IdTipoMensaje, 'La precotización admite hasta 50 conceptos.' AS Mensaje;
        LEAVE proc;
    END IF;

    DROP TEMPORARY TABLE IF EXISTS tmp_in_pci;
    CREATE TEMPORARY TABLE tmp_in_pci (
        ord INT, id BIGINT NULL, concepto VARCHAR(200) NULL, codigo VARCHAR(60) NULL, id_suministro BIGINT NULL,
        descripcion VARCHAR(500) NULL, cantidad DECIMAL(10,2) NULL, unidad VARCHAR(20) NULL, prioridad VARCHAR(10) NULL,
        id_observacion BIGINT NULL
    ) DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;
    INSERT INTO tmp_in_pci
    SELECT j.ord, NULLIF(j.id, 0), NULLIF(TRIM(j.concepto), ''), NULLIF(TRIM(j.codigo), ''), NULLIF(j.id_suministro, 0),
           NULLIF(TRIM(j.descripcion), ''), j.cantidad, IFNULL(NULLIF(TRIM(j.unidad), ''), 'un'),
           IFNULL(NULLIF(LOWER(TRIM(j.prioridad)), ''), 'media'), NULLIF(j.id_observacion, 0)
    FROM JSON_TABLE(p_items, '$[*]' COLUMNS (
        ord FOR ORDINALITY, id BIGINT PATH '$.id', concepto VARCHAR(200) PATH '$.concepto', codigo VARCHAR(60) PATH '$.codigo',
        id_suministro BIGINT PATH '$.idSuministro', descripcion VARCHAR(500) PATH '$.descripcionTecnica',
        cantidad DECIMAL(10,2) PATH '$.cantidad', unidad VARCHAR(20) PATH '$.unidad', prioridad VARCHAR(10) PATH '$.prioridad',
        id_observacion BIGINT PATH '$.idObservacion')) j;

    -- Concepto del catálogo: completa nombre y código si no vinieron
    UPDATE tmp_in_pci t
    JOIN suministros s ON s.id_suministro = t.id_suministro AND s.eliminado_en IS NULL
    SET t.concepto = IFNULL(t.concepto, s.descripcion), t.codigo = IFNULL(t.codigo, s.codigo);

    IF EXISTS (SELECT 1 FROM tmp_in_pci WHERE concepto IS NULL) THEN
        SELECT 1 AS IdTipoMensaje, 'Cada concepto debe tener un nombre o elegirse del catálogo.' AS Mensaje; LEAVE proc;
    END IF;
    IF EXISTS (SELECT 1 FROM tmp_in_pci WHERE cantidad IS NULL OR cantidad <= 0) THEN
        SELECT 1 AS IdTipoMensaje, 'La cantidad de cada concepto debe ser mayor que cero.' AS Mensaje; LEAVE proc;
    END IF;
    IF EXISTS (SELECT 1 FROM tmp_in_pci WHERE prioridad NOT IN ('alta', 'media', 'opcional')) THEN
        SELECT 1 AS IdTipoMensaje, 'Prioridad no válida: use alta, media u opcional.' AS Mensaje; LEAVE proc;
    END IF;
    IF EXISTS (SELECT 1 FROM tmp_in_pci t WHERE t.id_suministro IS NOT NULL
                 AND NOT EXISTS (SELECT 1 FROM suministros s WHERE s.id_suministro = t.id_suministro AND s.eliminado_en IS NULL)) THEN
        SELECT 1 AS IdTipoMensaje, 'Un concepto elegido del catálogo no existe.' AS Mensaje; LEAVE proc;
    END IF;
    IF EXISTS (SELECT 1 FROM tmp_in_pci t WHERE t.id_observacion IS NOT NULL
                 AND NOT EXISTS (SELECT 1 FROM informe_observacion o WHERE o.id_observacion = t.id_observacion
                                   AND o.id_informe = p_id_informe AND o.eliminado_en IS NULL)) THEN
        SELECT 1 AS IdTipoMensaje, 'La observación vinculada a un concepto no pertenece a este informe.' AS Mensaje; LEAVE proc;
    END IF;

    START TRANSACTION;

    SELECT estado INTO v_estado FROM informe_tecnico WHERE id_informe = p_id_informe FOR UPDATE;
    IF v_estado IN ('revisado', 'aprobado') THEN
        ROLLBACK; DROP TEMPORARY TABLE IF EXISTS tmp_in_pci;
        SELECT 1 AS IdTipoMensaje, 'El informe ya fue revisado: es inmutable y no se puede editar.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT MAX(id_precotizacion) INTO v_id_pc FROM precotizacion WHERE id_informe = p_id_informe AND eliminado_en IS NULL;
    IF v_id_pc IS NOT NULL THEN
        SELECT estado, numero INTO v_estado_pc, v_numero FROM precotizacion WHERE id_precotizacion = v_id_pc FOR UPDATE;
        IF v_estado_pc = 'convertido_propuesta' THEN
            ROLLBACK; DROP TEMPORARY TABLE IF EXISTS tmp_in_pci;
            SELECT 1 AS IdTipoMensaje, 'La precotización ya fue convertida en propuesta: no se puede editar.' AS Mensaje;
            LEAVE proc;
        END IF;
    END IF;
    IF EXISTS (SELECT 1 FROM tmp_in_pci t WHERE t.id IS NOT NULL AND NOT EXISTS (
                   SELECT 1 FROM precotizacion_item pi WHERE pi.id_item = t.id AND pi.id_precotizacion <=> v_id_pc AND pi.eliminado_en IS NULL)) THEN
        ROLLBACK; DROP TEMPORARY TABLE IF EXISTS tmp_in_pci;
        SELECT 1 AS IdTipoMensaje, 'Un concepto no pertenece a esta precotización.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF v_estado IN ('pendiente_revision', 'observado') THEN
        UPDATE informe_tecnico
        SET estado = 'en_revision', fecha_inicio_revision = IFNULL(fecha_inicio_revision, NOW()), id_revisor = p_id_usuario,
            modificado_por = p_id_usuario
        WHERE id_informe = p_id_informe;
        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
        VALUES ('informe_tecnico', p_id_informe, 'inicio_revision', v_estado, 'en_revision', 'Inició la revisión del informe',
                p_id_usuario, NOW(), JSON_OBJECT('categoria', 'revision', 'detalle', 'Registro de la precotización'));
    END IF;

    IF v_id_pc IS NULL THEN
        SET v_nuevo = 1;
        SELECT CONCAT('PCT-', LPAD(IFNULL(MAX(CAST(SUBSTRING(numero, 5) AS UNSIGNED)), 0) + 1, 6, '0')) INTO v_numero
        FROM precotizacion WHERE numero LIKE 'PCT-%';
        INSERT INTO precotizacion (numero, id_requerimiento, id_informe, id_os, id_equipo, id_cliente, id_creador, id_tipo_servicio,
                                   descripcion_servicio, nota_supervisor, id_moneda, estado, fecha_creacion, fecha_envio, creado_por)
        VALUES (v_numero, v_id_rq, p_id_informe, v_id_os, v_id_equipo, v_id_cliente, p_id_usuario, v_tipo_serv,
                v_diag, NULLIF(TRIM(p_nota), ''), NULL, 'enviado', NOW(), NOW(), p_id_usuario);
        SET v_id_pc = LAST_INSERT_ID();
    ELSE
        UPDATE precotizacion
        SET nota_supervisor = NULLIF(TRIM(p_nota), ''), descripcion_servicio = v_diag, estado = 'enviado',
            fecha_envio = IFNULL(fecha_envio, NOW()), modificado_por = p_id_usuario
        WHERE id_precotizacion = v_id_pc;
        SET v_cambios = v_cambios + ROW_COUNT();
    END IF;

    -- Ítems: eliminados, editados y nuevos
    UPDATE precotizacion_item SET eliminado_en = NOW(), eliminado_por = p_id_usuario
    WHERE id_precotizacion = v_id_pc AND eliminado_en IS NULL
      AND id_item NOT IN (SELECT t.id FROM tmp_in_pci t WHERE t.id IS NOT NULL);
    SET v_cambios = v_cambios + ROW_COUNT();

    UPDATE precotizacion_item pi
    JOIN tmp_in_pci t ON t.id = pi.id_item
    SET pi.concepto = t.concepto, pi.codigo = t.codigo, pi.id_suministro = t.id_suministro, pi.descripcion_tecnica = t.descripcion,
        pi.cantidad = t.cantidad, pi.unidad = t.unidad, pi.prioridad = t.prioridad, pi.id_observacion = t.id_observacion,
        pi.orden = t.ord, pi.modificado_por = p_id_usuario;
    SET v_cambios = v_cambios + ROW_COUNT();

    INSERT INTO precotizacion_item (id_precotizacion, orden, concepto, codigo, id_suministro, descripcion_tecnica, cantidad, unidad,
                                    prioridad, id_observacion, creado_por)
    SELECT v_id_pc, t.ord, t.concepto, t.codigo, t.id_suministro, t.descripcion, t.cantidad, t.unidad, t.prioridad, t.id_observacion, p_id_usuario
    FROM tmp_in_pci t WHERE t.id IS NULL;
    SET v_cambios = v_cambios + ROW_COUNT();

    SELECT COUNT(*) INTO v_n FROM precotizacion_item WHERE id_precotizacion = v_id_pc AND eliminado_en IS NULL;

    IF v_nuevo = 1 OR v_cambios > 0 THEN
        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, descripcion, id_usuario, registrado_en, metadata)
        VALUES ('informe_tecnico', p_id_informe, IF(v_nuevo = 1, 'precotizacion_registrada', 'precotizacion_actualizada'),
                IF(v_nuevo = 1, CONCAT('Registró la precotización ', v_numero, ' (', v_n, IF(v_n = 1, ' concepto', ' conceptos'), ')'),
                                CONCAT('Actualizó la precotización ', v_numero, ' (', v_n, IF(v_n = 1, ' concepto', ' conceptos'), ')')),
                p_id_usuario, NOW(),
                JSON_OBJECT('categoria', 'precotizacion', 'id_precotizacion', v_id_pc,
                            'cambios', (SELECT GROUP_CONCAT(CONCAT(pi.concepto, ' × ', CAST(pi.cantidad AS DOUBLE)) ORDER BY pi.orden SEPARATOR ' · ')
                                        FROM precotizacion_item pi WHERE pi.id_precotizacion = v_id_pc AND pi.eliminado_en IS NULL)));
        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, descripcion, id_usuario, registrado_en, metadata)
        VALUES ('precotizacion', v_id_pc, IF(v_nuevo = 1, 'registrada', 'actualizada'),
                CONCAT(IF(v_nuevo = 1, 'Precotización enviada a Comercial desde el informe ', 'Precotización actualizada desde el informe '), v_numero_os),
                p_id_usuario, NOW(), JSON_OBJECT('id_informe', p_id_informe, 'items', v_n));
    END IF;

    -- Aviso al responsable del RQ (solo al enviarla por primera vez)
    IF v_nuevo = 1 AND v_id_resp IS NOT NULL AND v_id_resp <> p_id_usuario THEN
        INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
        VALUES (v_id_resp, 5, CONCAT('Nueva precotización técnica ', v_numero),
                CONCAT('Servicio Técnico generó la precotización ', v_numero, ' (', v_n, IF(v_n = 1, ' concepto', ' conceptos'),
                       ') a partir de la ', v_numero_os, IF(v_cliente IS NULL, '', CONCAT(' de ', v_cliente)), '. Está lista para convertirla en propuesta.'),
                'precotizacion', v_id_pc, NOW(), p_id_usuario);
    END IF;

    COMMIT;
    DROP TEMPORARY TABLE IF EXISTS tmp_in_pci;

    SELECT 2 AS IdTipoMensaje,
           IF(v_nuevo = 1, CONCAT('Precotización ', v_numero, ' registrada y enviada a Comercial.'),
                           CONCAT('Precotización ', v_numero, ' actualizada.')) AS Mensaje;
    SELECT v_id_pc AS id_precotizacion, v_numero AS numero, v_n AS items, 'enviado' AS estado;
END$$

DELIMITER ;
