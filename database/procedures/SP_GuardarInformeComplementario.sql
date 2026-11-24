-- ============================================================
-- SP_GuardarInformeComplementario  (Revisión Técnica — "Guardar" del Informe Complementario, 23/11/2026 · escritura)
-- Acceso: rt_editar, el informe original en el alcance del usuario y aún sin revisar (SP_ContextoInformeComplementario).
-- Cada sección es opcional (NULL = no cambia). Una lista enviada es la lista COMPLETA de esa sección: con id = se actualiza,
-- sin id = se agrega, las que faltan se eliminan.
--   p_cambiar_descripcion = 1 → p_descripcion son las observaciones generales ("" las borra).
--   p_observaciones   [{id, titulo, descripcion, ubicacion, detalleExtra, nivelAfectacion: critico|alto|medio|bajo, idEvidencia}]
--   p_recomendaciones [{id, titulo, descripcion, prioridad: alta|media|baja, plazo, idObservacion | indiceObservacion}]
--   p_precotizacion   {nota, items: [{id, concepto, codigo, idSuministro, descripcionTecnica, cantidad, unidad, prioridad: alta|media|opcional,
--                                     idObservacion | indiceObservacion}]}
--                     items vacío = quita la precotización (si aún no se convirtió en propuesta). Opcional: el complementario puede no tenerla.
--     indiceObservacion = posición (desde 0) en p_observaciones, para vincular una observación NUEVA de este mismo guardado.
-- Regla "complementario vacío": al terminar debe tener algo propio frente al original —precotización, fotos agregadas o quitadas, u
-- observaciones, recomendaciones u observaciones generales distintas—; si no, no se guarda nada.
-- Efectos: el complementario pasa de 'borrador' a 'complementario'. La precotización queda ENVIADA a Comercial (PCT-NNNNNN) con
-- id_informe = complementario, y la primera vez se avisa al responsable del RQ. Todo queda en el historial del informe original.
-- Resultados: 1 mensaje; 2 (id_informe_complementario, estado, cambios_registrados, id_precotizacion, numero_precotizacion, items_precotizacion, precotizacion_nueva).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_GuardarInformeComplementario;

DELIMITER $$

CREATE PROCEDURE SP_GuardarInformeComplementario(
    IN p_id_usuario          BIGINT,
    IN p_id_complementario   BIGINT,
    IN p_cambiar_descripcion TINYINT,
    IN p_descripcion         TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_observaciones       JSON,
    IN p_recomendaciones     JSON,
    IN p_precotizacion       JSON
)
proc: BEGIN
    DECLARE v_msg        VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_padre      BIGINT;
    DECLARE v_estado     VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_est_padre  VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_editable   TINYINT;
    DECLARE v_numero     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cambios    INT DEFAULT 0;
    DECLARE v_n          INT DEFAULT 0;
    DECLARE v_max        INT DEFAULT 0;
    DECLARE v_items      JSON;
    DECLARE v_nota       VARCHAR(1000) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_pc      BIGINT DEFAULT NULL;
    DECLARE v_estado_pc  VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_numero_pc  VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_pc_nueva   TINYINT DEFAULT 0;
    DECLARE v_pc_quitada TINYINT DEFAULT 0;
    DECLARE v_n_items    INT DEFAULT 0;
    DECLARE v_id_os      BIGINT;
    DECLARE v_id_equipo  BIGINT;
    DECLARE v_id_rq      BIGINT;
    DECLARE v_id_cliente BIGINT;
    DECLARE v_id_resp    BIGINT;
    DECLARE v_numero_os  VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cliente    VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_diag       TEXT         CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tipo_serv  INT;
    DECLARE v_firma_c    CHAR(32);
    DECLARE v_firma_o    CHAR(32);
    DECLARE v_propio     TINYINT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_cm_obs;
        DROP TEMPORARY TABLE IF EXISTS tmp_cm_rec;
        DROP TEMPORARY TABLE IF EXISTS tmp_cm_pci;
        DROP TEMPORARY TABLE IF EXISTS tmp_cm_nuevas;
        DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    CALL SP_ContextoInformeComplementario(p_id_usuario, p_id_complementario, 'rt_editar', v_msg, v_padre, v_estado, v_est_padre, v_editable);
    IF v_msg IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje; LEAVE proc;
    END IF;
    IF v_editable = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El informe ya fue revisado: el informe complementario es inmutable.' AS Mensaje; LEAVE proc;
    END IF;

    IF (p_observaciones   IS NOT NULL AND JSON_TYPE(p_observaciones)   <> 'ARRAY')
    OR (p_recomendaciones IS NOT NULL AND JSON_TYPE(p_recomendaciones) <> 'ARRAY')
    OR (p_precotizacion   IS NOT NULL AND JSON_TYPE(p_precotizacion)   <> 'OBJECT') THEN
        SELECT 1 AS IdTipoMensaje, 'Formato de datos no válido.' AS Mensaje; LEAVE proc;
    END IF;
    IF IFNULL(p_cambiar_descripcion, 0) = 1 AND CHAR_LENGTH(IFNULL(p_descripcion, '')) > 1000 THEN
        SELECT 1 AS IdTipoMensaje, 'Las observaciones generales admiten hasta 1000 caracteres.' AS Mensaje; LEAVE proc;
    END IF;

    -- ── Observaciones ────────────────────────────────────────────────────────────────────────
    DROP TEMPORARY TABLE IF EXISTS tmp_cm_obs;
    CREATE TEMPORARY TABLE tmp_cm_obs (
        ord INT, id BIGINT NULL, titulo VARCHAR(200) NULL, descripcion VARCHAR(1000) NULL, ubicacion VARCHAR(200) NULL,
        detalle_extra VARCHAR(200) NULL, nivel VARCHAR(20) NULL, id_evidencia BIGINT NULL
    ) DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;
    IF p_observaciones IS NOT NULL THEN
        IF JSON_LENGTH(p_observaciones) > 100 THEN
            SELECT 1 AS IdTipoMensaje, 'Cada sección admite hasta 100 elementos.' AS Mensaje; LEAVE proc;
        END IF;
        INSERT INTO tmp_cm_obs
        SELECT j.ord, NULLIF(j.id, 0), NULLIF(TRIM(j.titulo), ''), NULLIF(TRIM(j.descripcion), ''), NULLIF(TRIM(j.ubicacion), ''),
               NULLIF(TRIM(j.detalle_extra), ''), NULLIF(LOWER(TRIM(j.nivel)), ''), NULLIF(j.id_evidencia, 0)
        FROM JSON_TABLE(p_observaciones, '$[*]' COLUMNS (
            ord FOR ORDINALITY, id BIGINT PATH '$.id', titulo VARCHAR(200) PATH '$.titulo', descripcion VARCHAR(1000) PATH '$.descripcion',
            ubicacion VARCHAR(200) PATH '$.ubicacion', detalle_extra VARCHAR(200) PATH '$.detalleExtra',
            nivel VARCHAR(20) PATH '$.nivelAfectacion', id_evidencia BIGINT PATH '$.idEvidencia')) j;
        IF EXISTS (SELECT 1 FROM tmp_cm_obs WHERE titulo IS NULL) THEN
            SELECT 1 AS IdTipoMensaje, 'Cada observación debe tener un título.' AS Mensaje; LEAVE proc;
        END IF;
        IF EXISTS (SELECT 1 FROM tmp_cm_obs WHERE nivel IS NOT NULL AND nivel NOT IN ('critico', 'alto', 'medio', 'bajo')) THEN
            SELECT 1 AS IdTipoMensaje, 'Nivel de afectación no válido: use critico, alto, medio o bajo.' AS Mensaje; LEAVE proc;
        END IF;
        IF EXISTS (SELECT 1 FROM tmp_cm_obs t WHERE t.id IS NOT NULL AND NOT EXISTS (
                       SELECT 1 FROM informe_observacion o WHERE o.id_observacion = t.id AND o.id_informe = p_id_complementario AND o.eliminado_en IS NULL)) THEN
            SELECT 1 AS IdTipoMensaje, 'Una observación no pertenece a este informe complementario.' AS Mensaje; LEAVE proc;
        END IF;
        IF EXISTS (SELECT 1 FROM tmp_cm_obs t WHERE t.id_evidencia IS NOT NULL AND NOT EXISTS (
                       SELECT 1 FROM evidencia_fotografica f WHERE f.id_evidencia = t.id_evidencia AND f.id_informe = p_id_complementario
                         AND f.eliminado_en IS NULL)) THEN
            SELECT 1 AS IdTipoMensaje, 'La foto elegida no pertenece a este informe complementario.' AS Mensaje; LEAVE proc;
        END IF;
    END IF;

    -- ── Recomendaciones ──────────────────────────────────────────────────────────────────────
    DROP TEMPORARY TABLE IF EXISTS tmp_cm_rec;
    CREATE TEMPORARY TABLE tmp_cm_rec (
        ord INT, id BIGINT NULL, titulo VARCHAR(200) NULL, descripcion VARCHAR(1000) NULL, prioridad VARCHAR(10) NULL,
        plazo VARCHAR(100) NULL, id_observacion BIGINT NULL, indice_observacion INT NULL
    ) DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;
    SELECT COUNT(*) INTO v_n FROM tmp_cm_obs;
    IF p_recomendaciones IS NOT NULL THEN
        IF JSON_LENGTH(p_recomendaciones) > 100 THEN
            SELECT 1 AS IdTipoMensaje, 'Cada sección admite hasta 100 elementos.' AS Mensaje; LEAVE proc;
        END IF;
        INSERT INTO tmp_cm_rec
        SELECT j.ord, NULLIF(j.id, 0), NULLIF(TRIM(j.titulo), ''), NULLIF(TRIM(j.descripcion), ''),
               IFNULL(NULLIF(LOWER(TRIM(j.prioridad)), ''), 'media'), NULLIF(TRIM(j.plazo), ''), NULLIF(j.id_observacion, 0), j.indice
        FROM JSON_TABLE(p_recomendaciones, '$[*]' COLUMNS (
            ord FOR ORDINALITY, id BIGINT PATH '$.id', titulo VARCHAR(200) PATH '$.titulo', descripcion VARCHAR(1000) PATH '$.descripcion',
            prioridad VARCHAR(10) PATH '$.prioridad', plazo VARCHAR(100) PATH '$.plazo', id_observacion BIGINT PATH '$.idObservacion',
            indice INT PATH '$.indiceObservacion')) j;
        IF EXISTS (SELECT 1 FROM tmp_cm_rec WHERE titulo IS NULL) THEN
            SELECT 1 AS IdTipoMensaje, 'Cada recomendación debe tener un título.' AS Mensaje; LEAVE proc;
        END IF;
        IF EXISTS (SELECT 1 FROM tmp_cm_rec WHERE prioridad NOT IN ('alta', 'media', 'baja')) THEN
            SELECT 1 AS IdTipoMensaje, 'Prioridad no válida: use alta, media o baja.' AS Mensaje; LEAVE proc;
        END IF;
        IF EXISTS (SELECT 1 FROM tmp_cm_rec t WHERE t.id IS NOT NULL AND NOT EXISTS (
                       SELECT 1 FROM informe_recomendacion r WHERE r.id_recomendacion = t.id AND r.id_informe = p_id_complementario AND r.eliminado_en IS NULL)) THEN
            SELECT 1 AS IdTipoMensaje, 'Una recomendación no pertenece a este informe complementario.' AS Mensaje; LEAVE proc;
        END IF;
        IF EXISTS (SELECT 1 FROM tmp_cm_rec t WHERE t.id_observacion IS NOT NULL AND NOT EXISTS (
                       SELECT 1 FROM informe_observacion o WHERE o.id_observacion = t.id_observacion AND o.id_informe = p_id_complementario
                         AND o.eliminado_en IS NULL)) THEN
            SELECT 1 AS IdTipoMensaje, 'La observación vinculada a una recomendación no pertenece a este informe complementario.' AS Mensaje; LEAVE proc;
        END IF;
        IF EXISTS (SELECT 1 FROM tmp_cm_rec WHERE indice_observacion IS NOT NULL AND (indice_observacion < 0 OR indice_observacion >= v_n)) THEN
            SELECT 1 AS IdTipoMensaje, 'La observación vinculada a una recomendación no existe en la lista enviada.' AS Mensaje; LEAVE proc;
        END IF;
    END IF;

    -- ── Precotización ────────────────────────────────────────────────────────────────────────
    DROP TEMPORARY TABLE IF EXISTS tmp_cm_pci;
    CREATE TEMPORARY TABLE tmp_cm_pci (
        ord INT, id BIGINT NULL, concepto VARCHAR(200) NULL, codigo VARCHAR(60) NULL, id_suministro BIGINT NULL,
        descripcion VARCHAR(500) NULL, cantidad DECIMAL(10,2) NULL, unidad VARCHAR(20) NULL, prioridad VARCHAR(10) NULL,
        id_observacion BIGINT NULL, indice_observacion INT NULL
    ) DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;
    IF p_precotizacion IS NOT NULL THEN
        SET v_nota  = LEFT(NULLIF(TRIM(JSON_UNQUOTE(JSON_EXTRACT(p_precotizacion, '$.nota'))), 'null'), 1000);
        SET v_nota  = NULLIF(v_nota, '');
        SET v_items = JSON_EXTRACT(p_precotizacion, '$.items');
        IF v_items IS NULL OR JSON_TYPE(v_items) <> 'ARRAY' THEN SET v_items = JSON_ARRAY(); END IF;
        IF JSON_LENGTH(v_items) > 50 THEN
            SELECT 1 AS IdTipoMensaje, 'La precotización admite hasta 50 conceptos.' AS Mensaje; LEAVE proc;
        END IF;
        INSERT INTO tmp_cm_pci
        SELECT j.ord, NULLIF(j.id, 0), NULLIF(TRIM(j.concepto), ''), NULLIF(TRIM(j.codigo), ''), NULLIF(j.id_suministro, 0),
               NULLIF(TRIM(j.descripcion), ''), j.cantidad, IFNULL(NULLIF(TRIM(j.unidad), ''), 'un'),
               IFNULL(NULLIF(LOWER(TRIM(j.prioridad)), ''), 'media'), NULLIF(j.id_observacion, 0), j.indice
        FROM JSON_TABLE(v_items, '$[*]' COLUMNS (
            ord FOR ORDINALITY, id BIGINT PATH '$.id', concepto VARCHAR(200) PATH '$.concepto', codigo VARCHAR(60) PATH '$.codigo',
            id_suministro BIGINT PATH '$.idSuministro', descripcion VARCHAR(500) PATH '$.descripcionTecnica',
            cantidad DECIMAL(10,2) PATH '$.cantidad', unidad VARCHAR(20) PATH '$.unidad', prioridad VARCHAR(10) PATH '$.prioridad',
            id_observacion BIGINT PATH '$.idObservacion', indice INT PATH '$.indiceObservacion')) j;

        UPDATE tmp_cm_pci t
        JOIN suministros s ON s.id_suministro = t.id_suministro AND s.eliminado_en IS NULL
        SET t.concepto = IFNULL(t.concepto, s.descripcion), t.codigo = IFNULL(t.codigo, s.codigo);

        IF EXISTS (SELECT 1 FROM tmp_cm_pci WHERE concepto IS NULL) THEN
            SELECT 1 AS IdTipoMensaje, 'Cada concepto debe tener un nombre o elegirse del catálogo.' AS Mensaje; LEAVE proc;
        END IF;
        IF EXISTS (SELECT 1 FROM tmp_cm_pci WHERE cantidad IS NULL OR cantidad <= 0) THEN
            SELECT 1 AS IdTipoMensaje, 'La cantidad de cada concepto debe ser mayor que cero.' AS Mensaje; LEAVE proc;
        END IF;
        IF EXISTS (SELECT 1 FROM tmp_cm_pci WHERE prioridad NOT IN ('alta', 'media', 'opcional')) THEN
            SELECT 1 AS IdTipoMensaje, 'Prioridad no válida: use alta, media u opcional.' AS Mensaje; LEAVE proc;
        END IF;
        IF EXISTS (SELECT 1 FROM tmp_cm_pci t WHERE t.id_suministro IS NOT NULL
                     AND NOT EXISTS (SELECT 1 FROM suministros s WHERE s.id_suministro = t.id_suministro AND s.eliminado_en IS NULL)) THEN
            SELECT 1 AS IdTipoMensaje, 'Un concepto elegido del catálogo no existe.' AS Mensaje; LEAVE proc;
        END IF;
        IF EXISTS (SELECT 1 FROM tmp_cm_pci t WHERE t.id_observacion IS NOT NULL AND NOT EXISTS (
                       SELECT 1 FROM informe_observacion o WHERE o.id_observacion = t.id_observacion AND o.id_informe = p_id_complementario
                         AND o.eliminado_en IS NULL)) THEN
            SELECT 1 AS IdTipoMensaje, 'La observación vinculada a un concepto no pertenece a este informe complementario.' AS Mensaje; LEAVE proc;
        END IF;
        IF EXISTS (SELECT 1 FROM tmp_cm_pci WHERE indice_observacion IS NOT NULL AND (indice_observacion < 0 OR indice_observacion >= v_n)) THEN
            SELECT 1 AS IdTipoMensaje, 'La observación vinculada a un concepto no existe en la lista enviada.' AS Mensaje; LEAVE proc;
        END IF;

        -- Datos del servicio para la precotización (del informe original)
        CALL SP_ArmarBaseInformes(p_id_usuario, v_padre);
        SELECT MAX(id_os), MAX(id_equipo), MAX(id_requerimiento), MAX(id_cliente), MAX(id_responsable_rq), MAX(numero_os), MAX(razon_social),
               MAX(diagnostico), MAX(id_tipo_servicio)
          INTO v_id_os, v_id_equipo, v_id_rq, v_id_cliente, v_id_resp, v_numero_os, v_cliente, v_diag, v_tipo_serv
        FROM tmp_rt_base;
        DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;
    END IF;

    START TRANSACTION;

    -- Bloqueo en el mismo orden que la revisión: primero el original, luego el complementario
    SELECT estado INTO v_est_padre FROM informe_tecnico WHERE id_informe = v_padre FOR UPDATE;
    SET v_estado = NULL;
    SELECT estado, numero INTO v_estado, v_numero FROM informe_tecnico
    WHERE id_informe = p_id_complementario AND eliminado_en IS NULL FOR UPDATE;
    IF v_est_padre IN ('revisado', 'aprobado') THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'El informe ya fue revisado: el informe complementario es inmutable.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_estado IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'El informe complementario ya no existe (fue descartado).' AS Mensaje; LEAVE proc;
    END IF;

    SELECT MAX(id_precotizacion) INTO v_id_pc FROM precotizacion WHERE id_informe = p_id_complementario AND eliminado_en IS NULL;
    IF v_id_pc IS NOT NULL THEN
        SELECT estado, numero INTO v_estado_pc, v_numero_pc FROM precotizacion WHERE id_precotizacion = v_id_pc FOR UPDATE;
    END IF;
    IF p_precotizacion IS NOT NULL AND v_estado_pc = 'convertido_propuesta' THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'La precotización ya fue convertida en propuesta: no se puede editar.' AS Mensaje; LEAVE proc;
    END IF;
    IF EXISTS (SELECT 1 FROM tmp_cm_pci t WHERE t.id IS NOT NULL AND NOT EXISTS (
                   SELECT 1 FROM precotizacion_item pi WHERE pi.id_item = t.id AND pi.id_precotizacion <=> v_id_pc AND pi.eliminado_en IS NULL)) THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Un concepto no pertenece a esta precotización.' AS Mensaje; LEAVE proc;
    END IF;

    -- ── Observaciones generales ──────────────────────────────────────────────────────────────
    IF IFNULL(p_cambiar_descripcion, 0) = 1 THEN
        UPDATE informe_tecnico SET descripcion_complementaria = NULLIF(TRIM(p_descripcion), ''), modificado_por = p_id_usuario
        WHERE id_informe = p_id_complementario AND NOT (descripcion_complementaria <=> NULLIF(TRIM(p_descripcion), ''));
        SET v_cambios = v_cambios + ROW_COUNT();
    END IF;

    -- ── Observaciones ────────────────────────────────────────────────────────────────────────
    IF p_observaciones IS NOT NULL THEN
        -- Las recomendaciones, fotos e ítems vinculados a una observación eliminada quedan sin vínculo
        UPDATE informe_recomendacion r
        JOIN informe_observacion o ON o.id_observacion = r.id_observacion
        SET r.id_observacion = NULL
        WHERE o.id_informe = p_id_complementario AND o.eliminado_en IS NULL
          AND o.id_observacion NOT IN (SELECT t.id FROM tmp_cm_obs t WHERE t.id IS NOT NULL);
        UPDATE evidencia_fotografica f
        JOIN informe_observacion o ON o.id_observacion = f.id_observacion
        SET f.id_observacion = NULL
        WHERE o.id_informe = p_id_complementario AND o.eliminado_en IS NULL
          AND o.id_observacion NOT IN (SELECT t.id FROM tmp_cm_obs t WHERE t.id IS NOT NULL);
        UPDATE precotizacion_item pi
        JOIN informe_observacion o ON o.id_observacion = pi.id_observacion
        SET pi.id_observacion = NULL
        WHERE o.id_informe = p_id_complementario AND o.eliminado_en IS NULL
          AND o.id_observacion NOT IN (SELECT t.id FROM tmp_cm_obs t WHERE t.id IS NOT NULL);
        UPDATE informe_observacion SET eliminado_en = NOW(), eliminado_por = p_id_usuario
        WHERE id_informe = p_id_complementario AND eliminado_en IS NULL
          AND id_observacion NOT IN (SELECT t.id FROM tmp_cm_obs t WHERE t.id IS NOT NULL);
        SET v_cambios = v_cambios + ROW_COUNT();

        UPDATE informe_observacion o
        JOIN tmp_cm_obs t ON t.id = o.id_observacion
        SET o.titulo = t.titulo, o.descripcion = t.descripcion, o.ubicacion = t.ubicacion, o.detalle_extra = t.detalle_extra,
            o.nivel_afectacion = t.nivel, o.id_evidencia = t.id_evidencia, o.orden = t.ord, o.modificado_por = p_id_usuario;
        SET v_cambios = v_cambios + ROW_COUNT();

        -- Códigos de las nuevas: siguiente OBS-NN (cuenta también las eliminadas para no reutilizar códigos)
        SELECT IFNULL(MAX(CAST(SUBSTRING(codigo, 5) AS UNSIGNED)), 0) INTO v_max
        FROM informe_observacion WHERE id_informe = p_id_complementario AND codigo LIKE 'OBS-%';
        DROP TEMPORARY TABLE IF EXISTS tmp_cm_nuevas;
        CREATE TEMPORARY TABLE tmp_cm_nuevas AS
        SELECT t.ord, CONCAT('OBS-', LPAD(v_max + ROW_NUMBER() OVER (ORDER BY t.ord), 2, '0')) AS codigo
        FROM tmp_cm_obs t WHERE t.id IS NULL;

        INSERT INTO informe_observacion (id_informe, codigo, orden, titulo, descripcion, ubicacion, detalle_extra, nivel_afectacion,
                                         id_evidencia, origen, creado_por)
        SELECT p_id_complementario, n.codigo, t.ord, t.titulo, t.descripcion, t.ubicacion, t.detalle_extra, t.nivel, t.id_evidencia,
               'supervisor', p_id_usuario
        FROM tmp_cm_obs t JOIN tmp_cm_nuevas n ON n.ord = t.ord;
        SET v_cambios = v_cambios + ROW_COUNT();

        UPDATE tmp_cm_obs t
        JOIN tmp_cm_nuevas n ON n.ord = t.ord
        JOIN informe_observacion o ON o.id_informe = p_id_complementario AND o.codigo = n.codigo AND o.eliminado_en IS NULL
        SET t.id = o.id_observacion;
        DROP TEMPORARY TABLE IF EXISTS tmp_cm_nuevas;
    END IF;

    -- ── Recomendaciones (después de las observaciones, para vincular las nuevas) ─────────────
    IF p_recomendaciones IS NOT NULL THEN
        UPDATE tmp_cm_rec r
        JOIN tmp_cm_obs o ON o.ord = r.indice_observacion + 1
        SET r.id_observacion = o.id
        WHERE r.indice_observacion IS NOT NULL;

        UPDATE informe_recomendacion SET eliminado_en = NOW(), eliminado_por = p_id_usuario
        WHERE id_informe = p_id_complementario AND eliminado_en IS NULL
          AND id_recomendacion NOT IN (SELECT t.id FROM tmp_cm_rec t WHERE t.id IS NOT NULL);
        SET v_cambios = v_cambios + ROW_COUNT();

        UPDATE informe_recomendacion r
        JOIN tmp_cm_rec t ON t.id = r.id_recomendacion
        SET r.titulo = t.titulo, r.descripcion = t.descripcion, r.prioridad = t.prioridad, r.plazo = t.plazo,
            r.id_observacion = t.id_observacion, r.orden = t.ord, r.modificado_por = p_id_usuario;
        SET v_cambios = v_cambios + ROW_COUNT();

        SELECT IFNULL(MAX(CAST(SUBSTRING(codigo, 5) AS UNSIGNED)), 0) INTO v_max
        FROM informe_recomendacion WHERE id_informe = p_id_complementario AND codigo LIKE 'REC-%';
        DROP TEMPORARY TABLE IF EXISTS tmp_cm_nuevas;
        CREATE TEMPORARY TABLE tmp_cm_nuevas AS
        SELECT t.ord, CONCAT('REC-', LPAD(v_max + ROW_NUMBER() OVER (ORDER BY t.ord), 2, '0')) AS codigo
        FROM tmp_cm_rec t WHERE t.id IS NULL;

        INSERT INTO informe_recomendacion (id_informe, codigo, orden, titulo, descripcion, prioridad, plazo, id_observacion, origen, creado_por)
        SELECT p_id_complementario, n.codigo, t.ord, t.titulo, t.descripcion, t.prioridad, t.plazo, t.id_observacion, 'supervisor', p_id_usuario
        FROM tmp_cm_rec t JOIN tmp_cm_nuevas n ON n.ord = t.ord;
        SET v_cambios = v_cambios + ROW_COUNT();
        DROP TEMPORARY TABLE IF EXISTS tmp_cm_nuevas;
    END IF;

    -- ── Precotización ────────────────────────────────────────────────────────────────────────
    IF p_precotizacion IS NOT NULL THEN
        UPDATE tmp_cm_pci i
        JOIN tmp_cm_obs o ON o.ord = i.indice_observacion + 1
        SET i.id_observacion = o.id
        WHERE i.indice_observacion IS NOT NULL;
        SELECT COUNT(*) INTO v_n FROM tmp_cm_pci;

        IF v_n = 0 THEN
            -- Sin conceptos: se quita la precotización (si existe y aún no se convirtió)
            IF v_id_pc IS NOT NULL THEN
                UPDATE precotizacion_item SET eliminado_en = NOW(), eliminado_por = p_id_usuario
                WHERE id_precotizacion = v_id_pc AND eliminado_en IS NULL;
                UPDATE precotizacion SET eliminado_en = NOW(), eliminado_por = p_id_usuario WHERE id_precotizacion = v_id_pc;
                SET v_pc_quitada = 1, v_cambios = v_cambios + 1;
                INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, descripcion, id_usuario, registrado_en, metadata)
                VALUES ('precotizacion', v_id_pc, 'eliminada', CONCAT('Precotización retirada del informe complementario ', v_numero),
                        p_id_usuario, NOW(), JSON_OBJECT('id_informe', p_id_complementario));
                SET v_id_pc = NULL, v_numero_pc = NULL;
            END IF;
        ELSE
            IF v_id_pc IS NULL THEN
                SET v_pc_nueva = 1;
                SELECT CONCAT('PCT-', LPAD(IFNULL(MAX(CAST(SUBSTRING(numero, 5) AS UNSIGNED)), 0) + 1, 6, '0')) INTO v_numero_pc
                FROM precotizacion WHERE numero LIKE 'PCT-%';
                INSERT INTO precotizacion (numero, id_requerimiento, id_informe, id_os, id_equipo, id_cliente, id_creador, id_tipo_servicio,
                                           descripcion_servicio, nota_supervisor, id_moneda, estado, fecha_creacion, fecha_envio, creado_por)
                VALUES (v_numero_pc, v_id_rq, p_id_complementario, v_id_os, v_id_equipo, v_id_cliente, p_id_usuario, v_tipo_serv,
                        v_diag, v_nota, NULL, 'enviado', NOW(), NOW(), p_id_usuario);
                SET v_id_pc = LAST_INSERT_ID();
                SET v_cambios = v_cambios + 1;
            ELSE
                UPDATE precotizacion
                SET nota_supervisor = v_nota, descripcion_servicio = v_diag, estado = 'enviado',
                    fecha_envio = IFNULL(fecha_envio, NOW()), modificado_por = p_id_usuario
                WHERE id_precotizacion = v_id_pc AND NOT (nota_supervisor <=> v_nota AND descripcion_servicio <=> v_diag AND estado = 'enviado');
                SET v_cambios = v_cambios + ROW_COUNT();
            END IF;

            UPDATE precotizacion_item SET eliminado_en = NOW(), eliminado_por = p_id_usuario
            WHERE id_precotizacion = v_id_pc AND eliminado_en IS NULL
              AND id_item NOT IN (SELECT t.id FROM tmp_cm_pci t WHERE t.id IS NOT NULL);
            SET v_cambios = v_cambios + ROW_COUNT();

            UPDATE precotizacion_item pi
            JOIN tmp_cm_pci t ON t.id = pi.id_item
            SET pi.concepto = t.concepto, pi.codigo = t.codigo, pi.id_suministro = t.id_suministro, pi.descripcion_tecnica = t.descripcion,
                pi.cantidad = t.cantidad, pi.unidad = t.unidad, pi.prioridad = t.prioridad, pi.id_observacion = t.id_observacion,
                pi.orden = t.ord, pi.modificado_por = p_id_usuario;
            SET v_cambios = v_cambios + ROW_COUNT();

            INSERT INTO precotizacion_item (id_precotizacion, orden, concepto, codigo, id_suministro, descripcion_tecnica, cantidad, unidad,
                                            prioridad, id_observacion, creado_por)
            SELECT v_id_pc, t.ord, t.concepto, t.codigo, t.id_suministro, t.descripcion, t.cantidad, t.unidad, t.prioridad, t.id_observacion, p_id_usuario
            FROM tmp_cm_pci t WHERE t.id IS NULL;
            SET v_cambios = v_cambios + ROW_COUNT();

            SELECT COUNT(*) INTO v_n_items FROM precotizacion_item WHERE id_precotizacion = v_id_pc AND eliminado_en IS NULL;

            INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, descripcion, id_usuario, registrado_en, metadata)
            VALUES ('informe_tecnico', v_padre, IF(v_pc_nueva = 1, 'precotizacion_registrada', 'precotizacion_actualizada'),
                    CONCAT(IF(v_pc_nueva = 1, 'Registró la precotización ', 'Actualizó la precotización '), v_numero_pc,
                           ' en el informe complementario ', v_numero, ' (', v_n_items, IF(v_n_items = 1, ' concepto)', ' conceptos)')),
                    p_id_usuario, NOW(),
                    JSON_OBJECT('categoria', 'precotizacion', 'id_precotizacion', v_id_pc, 'id_complementario', p_id_complementario,
                                'cambios', (SELECT GROUP_CONCAT(CONCAT(pi.concepto, ' × ', CAST(pi.cantidad AS DOUBLE)) ORDER BY pi.orden SEPARATOR ' · ')
                                            FROM precotizacion_item pi WHERE pi.id_precotizacion = v_id_pc AND pi.eliminado_en IS NULL)));
            INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, descripcion, id_usuario, registrado_en, metadata)
            VALUES ('precotizacion', v_id_pc, IF(v_pc_nueva = 1, 'registrada', 'actualizada'),
                    CONCAT(IF(v_pc_nueva = 1, 'Precotización enviada a Comercial desde el informe complementario ',
                                              'Precotización actualizada desde el informe complementario '), v_numero,
                           IF(v_numero_os IS NULL, '', CONCAT(' (', v_numero_os, ')'))),
                    p_id_usuario, NOW(), JSON_OBJECT('id_informe', p_id_complementario, 'items', v_n_items));

            -- Aviso al responsable del RQ (solo al enviarla por primera vez)
            IF v_pc_nueva = 1 AND v_id_resp IS NOT NULL AND v_id_resp <> p_id_usuario THEN
                INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
                VALUES (v_id_resp, 5, CONCAT('Nueva precotización técnica ', v_numero_pc),
                        CONCAT('Servicio Técnico generó la precotización ', v_numero_pc, ' (', v_n_items, IF(v_n_items = 1, ' concepto', ' conceptos'),
                               ') a partir de la ', IFNULL(v_numero_os, 'orden'), IF(v_cliente IS NULL, '', CONCAT(' de ', v_cliente)),
                               '. Está lista para convertirla en propuesta.'),
                        'precotizacion', v_id_pc, NOW(), p_id_usuario);
            END IF;
        END IF;
    END IF;

    -- ── Regla "complementario vacío": algo propio frente al original ─────────────────────────
    SET SESSION group_concat_max_len = 1048576;
    SELECT MD5(IFNULL(GROUP_CONCAT(CONCAT_WS('|', titulo, IFNULL(descripcion, ''), IFNULL(ubicacion, ''), IFNULL(detalle_extra, ''),
                                             IFNULL(nivel_afectacion, '')) ORDER BY orden, id_observacion SEPARATOR '§'), ''))
      INTO v_firma_c FROM informe_observacion WHERE id_informe = p_id_complementario AND eliminado_en IS NULL;
    SELECT MD5(IFNULL(GROUP_CONCAT(CONCAT_WS('|', titulo, IFNULL(descripcion, ''), IFNULL(ubicacion, ''), IFNULL(detalle_extra, ''),
                                             IFNULL(nivel_afectacion, '')) ORDER BY orden, id_observacion SEPARATOR '§'), ''))
      INTO v_firma_o FROM informe_observacion WHERE id_informe = v_padre AND eliminado_en IS NULL;
    SET v_propio = IF(v_firma_c <> v_firma_o, 1, 0);
    IF v_propio = 0 THEN
        SELECT MD5(IFNULL(GROUP_CONCAT(CONCAT_WS('|', titulo, IFNULL(descripcion, ''), prioridad, IFNULL(plazo, ''))
                                       ORDER BY orden, id_recomendacion SEPARATOR '§'), ''))
          INTO v_firma_c FROM informe_recomendacion WHERE id_informe = p_id_complementario AND eliminado_en IS NULL;
        SELECT MD5(IFNULL(GROUP_CONCAT(CONCAT_WS('|', titulo, IFNULL(descripcion, ''), prioridad, IFNULL(plazo, ''))
                                       ORDER BY orden, id_recomendacion SEPARATOR '§'), ''))
          INTO v_firma_o FROM informe_recomendacion WHERE id_informe = v_padre AND eliminado_en IS NULL;
        SET v_propio = IF(v_firma_c <> v_firma_o, 1, 0);
    END IF;
    IF v_propio = 0 AND (
           EXISTS (SELECT 1 FROM precotizacion p JOIN precotizacion_item pi ON pi.id_precotizacion = p.id_precotizacion AND pi.eliminado_en IS NULL
                   WHERE p.id_informe = p_id_complementario AND p.eliminado_en IS NULL)
        OR EXISTS (SELECT 1 FROM evidencia_fotografica f WHERE f.id_informe = p_id_complementario AND f.eliminado_en IS NULL AND f.id_evidencia_origen IS NULL)
        OR EXISTS (SELECT 1 FROM evidencia_fotografica f WHERE f.id_informe = p_id_complementario AND f.eliminado_en IS NOT NULL AND f.id_evidencia_origen IS NOT NULL)
        OR NOT ((SELECT c.descripcion_complementaria FROM informe_tecnico c WHERE c.id_informe = p_id_complementario)
                <=> (SELECT o.descripcion_complementaria FROM informe_tecnico o WHERE o.id_informe = v_padre))) THEN
        SET v_propio = 1;
    END IF;
    IF v_propio = 0 THEN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_cm_obs;
        DROP TEMPORARY TABLE IF EXISTS tmp_cm_rec;
        DROP TEMPORARY TABLE IF EXISTS tmp_cm_pci;
        SELECT 1 AS IdTipoMensaje,
               'El informe complementario no tiene cambios respecto al informe del técnico: agrega fotos, observaciones, recomendaciones o una precotización antes de guardarlo.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- ── Guardado: borrador → complementario ──────────────────────────────────────────────────
    UPDATE informe_tecnico SET estado = 'complementario', modificado_por = p_id_usuario
    WHERE id_informe = p_id_complementario AND estado = 'borrador';
    IF ROW_COUNT() > 0 THEN SET v_cambios = v_cambios + 1; END IF;

    IF v_cambios > 0 THEN
        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
        VALUES ('informe_tecnico', v_padre, 'complementario_guardado', v_estado, 'complementario',
                CONCAT(IF(v_estado = 'borrador', 'Guardó el informe complementario ', 'Actualizó el informe complementario '), v_numero,
                       IF(v_pc_quitada = 1, ' (retiró la precotización)', '')),
                p_id_usuario, NOW(), JSON_OBJECT('categoria', 'edicion', 'id_complementario', p_id_complementario, 'cambios', v_cambios));
    END IF;

    COMMIT;
    DROP TEMPORARY TABLE IF EXISTS tmp_cm_obs;
    DROP TEMPORARY TABLE IF EXISTS tmp_cm_rec;
    DROP TEMPORARY TABLE IF EXISTS tmp_cm_pci;

    SELECT 2 AS IdTipoMensaje,
           CASE WHEN v_pc_nueva = 1 THEN CONCAT('Informe complementario guardado. Precotización ', v_numero_pc, ' enviada a Comercial.')
                WHEN v_cambios = 0  THEN 'No hubo cambios que guardar.'
                ELSE 'Informe complementario guardado.' END AS Mensaje;
    SELECT p_id_complementario AS id_informe_complementario, 'complementario' AS estado, v_cambios AS cambios_registrados,
           v_id_pc AS id_precotizacion, v_numero_pc AS numero_precotizacion, v_n_items AS items_precotizacion, v_pc_nueva AS precotizacion_nueva;
END$$

DELIMITER ;
