-- HU-58 (Sprint 5) Revisión Técnica: "Guardar cambios" de la edición del informe de servicio técnico (pasos 1 a 4).
-- Acceso: rt_editar. El informe debe estar en el alcance del usuario y NO estar revisado (el revisado es inmutable).
-- Cada sección es opcional: NULL = no se envió y no cambia. Una lista enviada es la lista completa de esa sección:
--   los elementos con id se actualizan, los sin id se agregan (origen 'supervisor') y los que faltan se eliminan.
--   p_procedimientos  [{id, titulo, detalle, realizado, nota}]
--   p_ensayos         [{id, tipo: pesaje|excentricidad, punto, notaPunto, carga, lectura, error, tolerancia, resultado: conforme|no_conforme}]
--                     resultado vacío con error y tolerancia → se calcula (|error| <= tolerancia → conforme)
--   p_observaciones   [{id, titulo, descripcion, ubicacion, detalleExtra, nivelAfectacion: critico|alto|medio|bajo, idEvidencia}]
--                     las nuevas reciben el siguiente código OBS-NN
--   p_recomendaciones [{id, titulo, descripcion, prioridad: alta|media|baja, plazo, idObservacion | indiceObservacion}]
--                     indiceObservacion = posición (desde 0) en p_observaciones, para vincular una observación nueva
--   p_resultado       {normativa, patronEnsayo, toleranciaExcentricidad, resultadoGlobal: dentro|fuera, errorMaximo,
--                      errorMaximoDetalle, incertidumbre, factorK, decisionTecnica}
--   p_cambiar_descripcion = 1 → guarda p_descripcion (descripción complementaria, hasta 1000 caracteres)
-- La primera edición pasa el informe a 'en_revision' ("Inició la revisión del informe").
-- Cada cambio queda en auditoria_evento (entidad 'informe_tecnico', metadata.categoria = 'edicion', metadata.cambios).
-- Resultados: 1 mensaje, 2 resumen (cambios registrados y estado).
DROP PROCEDURE IF EXISTS SP_GuardarInformeTecnico;

DELIMITER $$

CREATE PROCEDURE SP_GuardarInformeTecnico(
    IN p_id_usuario          BIGINT,
    IN p_id_informe          BIGINT,
    IN p_cambiar_descripcion TINYINT,
    IN p_descripcion         TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_resultado           JSON,
    IN p_procedimientos      JSON,
    IN p_ensayos             JSON,
    IN p_observaciones       JSON,
    IN p_recomendaciones     JSON
)
proc: BEGIN
    DECLARE v_existe   INT DEFAULT 0;
    DECLARE v_estado   VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_os    BIGINT;
    DECLARE v_n        INT DEFAULT 0;
    DECLARE v_cambios  INT DEFAULT 0;
    DECLARE v_max      INT DEFAULT 0;
    DECLARE v_texto    TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_previo   TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_in_paso;
        DROP TEMPORARY TABLE IF EXISTS tmp_in_ens;
        DROP TEMPORARY TABLE IF EXISTS tmp_in_obs;
        DROP TEMPORARY TABLE IF EXISTS tmp_obs_nuevas;
        DROP TEMPORARY TABLE IF EXISTS tmp_in_rec;
        DROP TEMPORARY TABLE IF EXISTS tmp_rec_nuevas;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF FN_PermisoAccion(p_id_usuario, 'rt_editar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para editar informes técnicos.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_ArmarBaseInformes(p_id_usuario, IFNULL(p_id_informe, 0));
    SELECT COUNT(*) INTO v_existe FROM tmp_rt_base;
    DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;
    IF v_existe = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El informe no existe o no está en tu alcance.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- ── Validación de las listas (antes de tocar nada) ──────────────────────────────────────
    IF (p_procedimientos  IS NOT NULL AND JSON_TYPE(p_procedimientos)  <> 'ARRAY')
    OR (p_ensayos         IS NOT NULL AND JSON_TYPE(p_ensayos)         <> 'ARRAY')
    OR (p_observaciones   IS NOT NULL AND JSON_TYPE(p_observaciones)   <> 'ARRAY')
    OR (p_recomendaciones IS NOT NULL AND JSON_TYPE(p_recomendaciones) <> 'ARRAY')
    OR (p_resultado       IS NOT NULL AND JSON_TYPE(p_resultado)       <> 'OBJECT') THEN
        SELECT 1 AS IdTipoMensaje, 'Formato de datos no válido.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF IFNULL(p_cambiar_descripcion, 0) = 1 AND CHAR_LENGTH(IFNULL(p_descripcion, '')) > 1000 THEN
        SELECT 1 AS IdTipoMensaje, 'La descripción complementaria admite hasta 1000 caracteres.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Procedimiento
    DROP TEMPORARY TABLE IF EXISTS tmp_in_paso;
    CREATE TEMPORARY TABLE tmp_in_paso (
        ord INT, id BIGINT NULL,
        titulo VARCHAR(200) NULL, detalle VARCHAR(500) NULL, realizado TINYINT NULL, nota VARCHAR(300) NULL
    ) DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;
    IF p_procedimientos IS NOT NULL THEN
        INSERT INTO tmp_in_paso
        SELECT j.ord, NULLIF(j.id, 0), NULLIF(TRIM(j.titulo), ''), NULLIF(TRIM(j.detalle), ''), IFNULL(j.realizado, 0), NULLIF(TRIM(j.nota), '')
        FROM JSON_TABLE(p_procedimientos, '$[*]' COLUMNS (
            ord FOR ORDINALITY, id BIGINT PATH '$.id', titulo VARCHAR(200) PATH '$.titulo', detalle VARCHAR(500) PATH '$.detalle',
            realizado TINYINT PATH '$.realizado', nota VARCHAR(300) PATH '$.nota')) j;
        IF EXISTS (SELECT 1 FROM tmp_in_paso WHERE titulo IS NULL) THEN
            SELECT 1 AS IdTipoMensaje, 'Cada paso del procedimiento debe tener un título.' AS Mensaje; LEAVE proc;
        END IF;
        IF EXISTS (SELECT 1 FROM tmp_in_paso t WHERE t.id IS NOT NULL AND NOT EXISTS (
                       SELECT 1 FROM informe_procedimiento ip WHERE ip.id_paso = t.id AND ip.id_informe = p_id_informe AND ip.eliminado_en IS NULL)) THEN
            SELECT 1 AS IdTipoMensaje, 'Un paso del procedimiento no pertenece a este informe.' AS Mensaje; LEAVE proc;
        END IF;
    END IF;

    -- Ensayos
    DROP TEMPORARY TABLE IF EXISTS tmp_in_ens;
    CREATE TEMPORARY TABLE tmp_in_ens (
        ord INT, id BIGINT NULL, tipo VARCHAR(20) NULL, punto VARCHAR(100) NULL, nota_punto VARCHAR(60) NULL,
        carga DECIMAL(14,4) NULL, lectura DECIMAL(14,4) NULL, error DECIMAL(14,4) NULL, tolerancia DECIMAL(14,4) NULL,
        resultado VARCHAR(20) NULL
    ) DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;
    IF p_ensayos IS NOT NULL THEN
        INSERT INTO tmp_in_ens
        SELECT j.ord, NULLIF(j.id, 0), LOWER(TRIM(j.tipo)), NULLIF(TRIM(j.punto), ''), NULLIF(TRIM(j.nota_punto), ''),
               j.carga, j.lectura, j.error, j.tolerancia, NULLIF(LOWER(TRIM(j.resultado)), '')
        FROM JSON_TABLE(p_ensayos, '$[*]' COLUMNS (
            ord FOR ORDINALITY, id BIGINT PATH '$.id', tipo VARCHAR(20) PATH '$.tipo', punto VARCHAR(100) PATH '$.punto',
            nota_punto VARCHAR(60) PATH '$.notaPunto', carga DECIMAL(14,4) PATH '$.carga', lectura DECIMAL(14,4) PATH '$.lectura',
            error DECIMAL(14,4) PATH '$.error', tolerancia DECIMAL(14,4) PATH '$.tolerancia', resultado VARCHAR(20) PATH '$.resultado')) j;
        UPDATE tmp_in_ens SET resultado = IF(ABS(error) <= ABS(tolerancia), 'conforme', 'no_conforme')
        WHERE resultado IS NULL AND error IS NOT NULL AND tolerancia IS NOT NULL;
        IF EXISTS (SELECT 1 FROM tmp_in_ens WHERE tipo IS NULL OR tipo NOT IN ('pesaje', 'excentricidad')) THEN
            SELECT 1 AS IdTipoMensaje, 'Tipo de ensayo no válido: use pesaje o excentricidad.' AS Mensaje; LEAVE proc;
        END IF;
        IF EXISTS (SELECT 1 FROM tmp_in_ens WHERE punto IS NULL) THEN
            SELECT 1 AS IdTipoMensaje, 'Cada lectura del ensayo debe indicar el punto de carga o la posición.' AS Mensaje; LEAVE proc;
        END IF;
        IF EXISTS (SELECT 1 FROM tmp_in_ens WHERE resultado IS NOT NULL AND resultado NOT IN ('conforme', 'no_conforme')) THEN
            SELECT 1 AS IdTipoMensaje, 'Resultado del ensayo no válido: use conforme o no_conforme.' AS Mensaje; LEAVE proc;
        END IF;
        IF EXISTS (SELECT 1 FROM tmp_in_ens t WHERE t.id IS NOT NULL AND NOT EXISTS (
                       SELECT 1 FROM informe_ensayo e WHERE e.id_ensayo = t.id AND e.id_informe = p_id_informe AND e.eliminado_en IS NULL)) THEN
            SELECT 1 AS IdTipoMensaje, 'Una lectura de ensayo no pertenece a este informe.' AS Mensaje; LEAVE proc;
        END IF;
    END IF;

    -- Observaciones
    SELECT id_os INTO v_id_os FROM informe_tecnico WHERE id_informe = p_id_informe;
    DROP TEMPORARY TABLE IF EXISTS tmp_in_obs;
    CREATE TEMPORARY TABLE tmp_in_obs (
        ord INT, id BIGINT NULL, titulo VARCHAR(200) NULL, descripcion VARCHAR(1000) NULL, ubicacion VARCHAR(200) NULL,
        detalle_extra VARCHAR(200) NULL, nivel VARCHAR(20) NULL, id_evidencia BIGINT NULL, codigo VARCHAR(10) NULL
    ) DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;
    IF p_observaciones IS NOT NULL THEN
        INSERT INTO tmp_in_obs
        SELECT j.ord, NULLIF(j.id, 0), NULLIF(TRIM(j.titulo), ''), NULLIF(TRIM(j.descripcion), ''), NULLIF(TRIM(j.ubicacion), ''),
               NULLIF(TRIM(j.detalle_extra), ''), NULLIF(LOWER(TRIM(j.nivel)), ''), NULLIF(j.id_evidencia, 0), NULL
        FROM JSON_TABLE(p_observaciones, '$[*]' COLUMNS (
            ord FOR ORDINALITY, id BIGINT PATH '$.id', titulo VARCHAR(200) PATH '$.titulo', descripcion VARCHAR(1000) PATH '$.descripcion',
            ubicacion VARCHAR(200) PATH '$.ubicacion', detalle_extra VARCHAR(200) PATH '$.detalleExtra',
            nivel VARCHAR(20) PATH '$.nivelAfectacion', id_evidencia BIGINT PATH '$.idEvidencia')) j;
        IF EXISTS (SELECT 1 FROM tmp_in_obs WHERE titulo IS NULL) THEN
            SELECT 1 AS IdTipoMensaje, 'Cada observación debe tener un título.' AS Mensaje; LEAVE proc;
        END IF;
        IF EXISTS (SELECT 1 FROM tmp_in_obs WHERE nivel IS NOT NULL AND nivel NOT IN ('critico', 'alto', 'medio', 'bajo')) THEN
            SELECT 1 AS IdTipoMensaje, 'Nivel de afectación no válido: use critico, alto, medio o bajo.' AS Mensaje; LEAVE proc;
        END IF;
        IF EXISTS (SELECT 1 FROM tmp_in_obs t WHERE t.id IS NOT NULL AND NOT EXISTS (
                       SELECT 1 FROM informe_observacion o WHERE o.id_observacion = t.id AND o.id_informe = p_id_informe AND o.eliminado_en IS NULL)) THEN
            SELECT 1 AS IdTipoMensaje, 'Una observación no pertenece a este informe.' AS Mensaje; LEAVE proc;
        END IF;
        IF EXISTS (SELECT 1 FROM tmp_in_obs t WHERE t.id_evidencia IS NOT NULL AND NOT EXISTS (
                       SELECT 1 FROM evidencia_fotografica f WHERE f.id_evidencia = t.id_evidencia AND f.eliminado_en IS NULL
                         AND (f.id_informe = p_id_informe OR f.id_os = v_id_os))) THEN
            SELECT 1 AS IdTipoMensaje, 'La foto elegida no pertenece a este servicio.' AS Mensaje; LEAVE proc;
        END IF;
    END IF;

    -- Recomendaciones
    DROP TEMPORARY TABLE IF EXISTS tmp_in_rec;
    CREATE TEMPORARY TABLE tmp_in_rec (
        ord INT, id BIGINT NULL, titulo VARCHAR(200) NULL, descripcion VARCHAR(1000) NULL, prioridad VARCHAR(10) NULL,
        plazo VARCHAR(100) NULL, id_observacion BIGINT NULL, indice_observacion INT NULL
    ) DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;
    IF p_recomendaciones IS NOT NULL THEN
        INSERT INTO tmp_in_rec
        SELECT j.ord, NULLIF(j.id, 0), NULLIF(TRIM(j.titulo), ''), NULLIF(TRIM(j.descripcion), ''),
               IFNULL(NULLIF(LOWER(TRIM(j.prioridad)), ''), 'media'), NULLIF(TRIM(j.plazo), ''), NULLIF(j.id_observacion, 0), j.indice
        FROM JSON_TABLE(p_recomendaciones, '$[*]' COLUMNS (
            ord FOR ORDINALITY, id BIGINT PATH '$.id', titulo VARCHAR(200) PATH '$.titulo', descripcion VARCHAR(1000) PATH '$.descripcion',
            prioridad VARCHAR(10) PATH '$.prioridad', plazo VARCHAR(100) PATH '$.plazo', id_observacion BIGINT PATH '$.idObservacion',
            indice INT PATH '$.indiceObservacion')) j;
        IF EXISTS (SELECT 1 FROM tmp_in_rec WHERE titulo IS NULL) THEN
            SELECT 1 AS IdTipoMensaje, 'Cada recomendación debe tener un título.' AS Mensaje; LEAVE proc;
        END IF;
        IF EXISTS (SELECT 1 FROM tmp_in_rec WHERE prioridad NOT IN ('alta', 'media', 'baja')) THEN
            SELECT 1 AS IdTipoMensaje, 'Prioridad no válida: use alta, media o baja.' AS Mensaje; LEAVE proc;
        END IF;
        IF EXISTS (SELECT 1 FROM tmp_in_rec t WHERE t.id IS NOT NULL AND NOT EXISTS (
                       SELECT 1 FROM informe_recomendacion r WHERE r.id_recomendacion = t.id AND r.id_informe = p_id_informe AND r.eliminado_en IS NULL)) THEN
            SELECT 1 AS IdTipoMensaje, 'Una recomendación no pertenece a este informe.' AS Mensaje; LEAVE proc;
        END IF;
        IF EXISTS (SELECT 1 FROM tmp_in_rec t WHERE t.id_observacion IS NOT NULL AND NOT EXISTS (
                       SELECT 1 FROM informe_observacion o WHERE o.id_observacion = t.id_observacion AND o.id_informe = p_id_informe
                         AND o.eliminado_en IS NULL)) THEN
            SELECT 1 AS IdTipoMensaje, 'La observación vinculada a una recomendación no pertenece a este informe.' AS Mensaje; LEAVE proc;
        END IF;
        SELECT COUNT(*) INTO v_n FROM tmp_in_obs;
        IF EXISTS (SELECT 1 FROM tmp_in_rec WHERE indice_observacion IS NOT NULL AND (indice_observacion < 0 OR indice_observacion >= v_n)) THEN
            SELECT 1 AS IdTipoMensaje, 'La observación vinculada a una recomendación no existe en la lista enviada.' AS Mensaje; LEAVE proc;
        END IF;
    END IF;

    IF p_resultado IS NOT NULL AND IFNULL(LOWER(JSON_UNQUOTE(JSON_EXTRACT(p_resultado, '$.resultadoGlobal'))), 'null') NOT IN ('null', '', 'dentro', 'fuera') THEN
        SELECT 1 AS IdTipoMensaje, 'Resultado global no válido: use dentro o fuera.' AS Mensaje; LEAVE proc;
    END IF;

    -- ── Escritura ───────────────────────────────────────────────────────────────────────────
    START TRANSACTION;

    SELECT estado INTO v_estado FROM informe_tecnico WHERE id_informe = p_id_informe FOR UPDATE;
    IF v_estado IN ('revisado', 'aprobado') THEN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_in_paso; DROP TEMPORARY TABLE IF EXISTS tmp_in_ens;
        DROP TEMPORARY TABLE IF EXISTS tmp_in_obs;  DROP TEMPORARY TABLE IF EXISTS tmp_in_rec;
        SELECT 1 AS IdTipoMensaje, 'El informe ya fue revisado: es inmutable y no se puede editar.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF v_estado IN ('pendiente_revision', 'observado') THEN
        UPDATE informe_tecnico
        SET estado = 'en_revision', fecha_inicio_revision = IFNULL(fecha_inicio_revision, NOW()), id_revisor = p_id_usuario,
            modificado_por = p_id_usuario
        WHERE id_informe = p_id_informe;
        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
        VALUES ('informe_tecnico', p_id_informe, 'inicio_revision', v_estado, 'en_revision', 'Inició la revisión del informe',
                p_id_usuario, NOW(), JSON_OBJECT('categoria', 'revision', 'detalle', 'Edición del informe'));
    END IF;

    -- Procedimiento
    IF p_procedimientos IS NOT NULL THEN
        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, descripcion, id_usuario, registrado_en, metadata)
        SELECT 'informe_tecnico', p_id_informe, 'edicion_procedimiento', CONCAT('Eliminó el paso del procedimiento «', ip.titulo, '»'),
               p_id_usuario, NOW(), JSON_OBJECT('categoria', 'edicion', 'cambios', 'Paso eliminado')
        FROM informe_procedimiento ip
        WHERE ip.id_informe = p_id_informe AND ip.eliminado_en IS NULL
          AND ip.id_paso NOT IN (SELECT t.id FROM tmp_in_paso t WHERE t.id IS NOT NULL);
        SET v_cambios = v_cambios + ROW_COUNT();
        UPDATE informe_procedimiento SET eliminado_en = NOW(), eliminado_por = p_id_usuario
        WHERE id_informe = p_id_informe AND eliminado_en IS NULL
          AND id_paso NOT IN (SELECT t.id FROM tmp_in_paso t WHERE t.id IS NOT NULL);

        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, descripcion, id_usuario, registrado_en, metadata)
        SELECT 'informe_tecnico', p_id_informe, 'edicion_procedimiento', CONCAT('Editó el paso del procedimiento «', t.titulo, '»'),
               p_id_usuario, NOW(),
               JSON_OBJECT('categoria', 'edicion', 'cambios', CONCAT_WS(' · ',
                   IF(ip.titulo    <=> t.titulo,    NULL, CONCAT('Título: «', ip.titulo, '» → «', t.titulo, '»')),
                   IF(ip.detalle   <=> t.detalle,   NULL, CONCAT('Detalle: «', IFNULL(ip.detalle, '—'), '» → «', IFNULL(t.detalle, '—'), '»')),
                   IF(ip.realizado <=> t.realizado, NULL, IF(t.realizado = 1, 'Marcado como realizado', 'Marcado como no realizado')),
                   IF(ip.nota      <=> t.nota,      NULL, CONCAT('Nota: «', IFNULL(ip.nota, '—'), '» → «', IFNULL(t.nota, '—'), '»'))))
        FROM informe_procedimiento ip
        JOIN tmp_in_paso t ON t.id = ip.id_paso
        WHERE NOT (ip.titulo <=> t.titulo AND ip.detalle <=> t.detalle AND ip.realizado <=> t.realizado AND ip.nota <=> t.nota);
        SET v_cambios = v_cambios + ROW_COUNT();

        UPDATE informe_procedimiento ip
        JOIN tmp_in_paso t ON t.id = ip.id_paso
        SET ip.titulo = t.titulo, ip.detalle = t.detalle, ip.realizado = t.realizado, ip.nota = t.nota, ip.orden = t.ord,
            ip.modificado_por = p_id_usuario;

        INSERT INTO informe_procedimiento (id_informe, orden, titulo, detalle, realizado, nota, origen, creado_por)
        SELECT p_id_informe, t.ord, t.titulo, t.detalle, t.realizado, t.nota, 'supervisor', p_id_usuario
        FROM tmp_in_paso t WHERE t.id IS NULL;
        SET v_n = ROW_COUNT();
        IF v_n > 0 THEN
            INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, descripcion, id_usuario, registrado_en, metadata)
            SELECT 'informe_tecnico', p_id_informe, 'edicion_procedimiento', CONCAT('Agregó el paso del procedimiento «', t.titulo, '»'),
                   p_id_usuario, NOW(), JSON_OBJECT('categoria', 'edicion', 'cambios', IF(t.realizado = 1, 'Realizado', 'No realizado'))
            FROM tmp_in_paso t WHERE t.id IS NULL;
            SET v_cambios = v_cambios + v_n;
        END IF;
    END IF;

    -- Ensayos
    IF p_ensayos IS NOT NULL THEN
        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, descripcion, id_usuario, registrado_en, metadata)
        SELECT 'informe_tecnico', p_id_informe, 'edicion_ensayo',
               CONCAT('Eliminó la lectura «', e.punto, '» del ensayo de ', e.tipo), p_id_usuario, NOW(),
               JSON_OBJECT('categoria', 'edicion', 'cambios', 'Lectura eliminada')
        FROM informe_ensayo e
        WHERE e.id_informe = p_id_informe AND e.eliminado_en IS NULL
          AND e.id_ensayo NOT IN (SELECT t.id FROM tmp_in_ens t WHERE t.id IS NOT NULL);
        SET v_cambios = v_cambios + ROW_COUNT();
        UPDATE informe_ensayo SET eliminado_en = NOW(), eliminado_por = p_id_usuario
        WHERE id_informe = p_id_informe AND eliminado_en IS NULL
          AND id_ensayo NOT IN (SELECT t.id FROM tmp_in_ens t WHERE t.id IS NOT NULL);

        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, descripcion, id_usuario, registrado_en, metadata)
        SELECT 'informe_tecnico', p_id_informe, 'edicion_ensayo', CONCAT('Editó la lectura «', t.punto, '» del ensayo de ', t.tipo),
               p_id_usuario, NOW(),
               JSON_OBJECT('categoria', 'edicion', 'cambios', CONCAT_WS(' · ',
                   IF(e.punto      <=> t.punto,      NULL, CONCAT('Punto: ', e.punto, ' → ', t.punto)),
                   IF(e.carga      <=> t.carga,      NULL, CONCAT('Carga: ', IFNULL(CAST(e.carga AS DOUBLE), '—'), ' → ', IFNULL(CAST(t.carga AS DOUBLE), '—'))),
                   IF(e.lectura    <=> t.lectura,    NULL, CONCAT('Lectura: ', IFNULL(CAST(e.lectura AS DOUBLE), '—'), ' → ', IFNULL(CAST(t.lectura AS DOUBLE), '—'))),
                   IF(e.error      <=> t.error,      NULL, CONCAT('Error: ', IFNULL(CAST(e.error AS DOUBLE), '—'), ' → ', IFNULL(CAST(t.error AS DOUBLE), '—'))),
                   IF(e.tolerancia <=> t.tolerancia, NULL, CONCAT('Tolerancia: ', IFNULL(CAST(e.tolerancia AS DOUBLE), '—'), ' → ', IFNULL(CAST(t.tolerancia AS DOUBLE), '—'))),
                   IF(e.resultado  <=> t.resultado,  NULL, CONCAT('Resultado: ', IFNULL(e.resultado, '—'), ' → ', IFNULL(t.resultado, '—')))))
        FROM informe_ensayo e
        JOIN tmp_in_ens t ON t.id = e.id_ensayo
        WHERE NOT (e.punto <=> t.punto AND e.nota_punto <=> t.nota_punto AND e.carga <=> t.carga AND e.lectura <=> t.lectura
                   AND e.error <=> t.error AND e.tolerancia <=> t.tolerancia AND e.resultado <=> t.resultado AND e.tipo <=> t.tipo);
        SET v_cambios = v_cambios + ROW_COUNT();

        UPDATE informe_ensayo e
        JOIN tmp_in_ens t ON t.id = e.id_ensayo
        SET e.tipo = t.tipo, e.punto = t.punto, e.nota_punto = t.nota_punto, e.carga = t.carga, e.lectura = t.lectura,
            e.error = t.error, e.tolerancia = t.tolerancia, e.resultado = t.resultado, e.orden = t.ord, e.modificado_por = p_id_usuario;

        INSERT INTO informe_ensayo (id_informe, tipo, orden, punto, nota_punto, carga, lectura, error, tolerancia, resultado, origen, creado_por)
        SELECT p_id_informe, t.tipo, t.ord, t.punto, t.nota_punto, t.carga, t.lectura, t.error, t.tolerancia, t.resultado, 'supervisor', p_id_usuario
        FROM tmp_in_ens t WHERE t.id IS NULL;
        SET v_n = ROW_COUNT();
        IF v_n > 0 THEN
            INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, descripcion, id_usuario, registrado_en, metadata)
            SELECT 'informe_tecnico', p_id_informe, 'edicion_ensayo', CONCAT('Agregó la lectura «', t.punto, '» al ensayo de ', t.tipo),
                   p_id_usuario, NOW(), JSON_OBJECT('categoria', 'edicion', 'cambios',
                       CONCAT('Lectura: ', IFNULL(CAST(t.lectura AS DOUBLE), '—'), ' · Resultado: ', IFNULL(t.resultado, '—')))
            FROM tmp_in_ens t WHERE t.id IS NULL;
            SET v_cambios = v_cambios + v_n;
        END IF;
    END IF;

    -- Observaciones
    IF p_observaciones IS NOT NULL THEN
        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, descripcion, id_usuario, registrado_en, metadata)
        SELECT 'informe_tecnico', p_id_informe, 'edicion_observacion', CONCAT('Eliminó Observación ', o.codigo, ' — ', o.titulo),
               p_id_usuario, NOW(), JSON_OBJECT('categoria', 'edicion', 'cambios', 'Observación eliminada')
        FROM informe_observacion o
        WHERE o.id_informe = p_id_informe AND o.eliminado_en IS NULL
          AND o.id_observacion NOT IN (SELECT t.id FROM tmp_in_obs t WHERE t.id IS NOT NULL);
        SET v_cambios = v_cambios + ROW_COUNT();
        -- Las recomendaciones e ítems vinculados a una observación eliminada quedan sin vínculo
        UPDATE informe_recomendacion r
        JOIN informe_observacion o ON o.id_observacion = r.id_observacion
        SET r.id_observacion = NULL
        WHERE o.id_informe = p_id_informe AND o.eliminado_en IS NULL
          AND o.id_observacion NOT IN (SELECT t.id FROM tmp_in_obs t WHERE t.id IS NOT NULL);
        UPDATE precotizacion_item pi
        JOIN informe_observacion o ON o.id_observacion = pi.id_observacion
        SET pi.id_observacion = NULL
        WHERE o.id_informe = p_id_informe AND o.eliminado_en IS NULL
          AND o.id_observacion NOT IN (SELECT t.id FROM tmp_in_obs t WHERE t.id IS NOT NULL);
        UPDATE informe_observacion SET eliminado_en = NOW(), eliminado_por = p_id_usuario
        WHERE id_informe = p_id_informe AND eliminado_en IS NULL
          AND id_observacion NOT IN (SELECT t.id FROM tmp_in_obs t WHERE t.id IS NOT NULL);

        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, descripcion, id_usuario, registrado_en, metadata)
        SELECT 'informe_tecnico', p_id_informe, 'edicion_observacion', CONCAT('Editó Observación ', o.codigo, ' — ', t.titulo),
               p_id_usuario, NOW(),
               JSON_OBJECT('categoria', 'edicion', 'cambios', CONCAT_WS(' · ',
                   IF(o.titulo           <=> t.titulo,        NULL, CONCAT('Título: «', o.titulo, '» → «', t.titulo, '»')),
                   IF(o.descripcion      <=> t.descripcion,   NULL, 'Descripción actualizada'),
                   IF(o.ubicacion        <=> t.ubicacion,     NULL, IF(o.ubicacion IS NULL, CONCAT('Agregó: Ubicación «', t.ubicacion, '»'),
                                                                       CONCAT('Ubicación: «', o.ubicacion, '» → «', IFNULL(t.ubicacion, '—'), '»'))),
                   IF(o.detalle_extra    <=> t.detalle_extra, NULL, CONCAT('Detalle: «', IFNULL(o.detalle_extra, '—'), '» → «', IFNULL(t.detalle_extra, '—'), '»')),
                   IF(o.nivel_afectacion <=> t.nivel,         NULL, CONCAT('Nivel de afectación: ', IFNULL(o.nivel_afectacion, '—'), ' → ', IFNULL(t.nivel, '—'))),
                   IF(o.id_evidencia     <=> t.id_evidencia,  NULL, 'Foto vinculada actualizada')))
        FROM informe_observacion o
        JOIN tmp_in_obs t ON t.id = o.id_observacion
        WHERE NOT (o.titulo <=> t.titulo AND o.descripcion <=> t.descripcion AND o.ubicacion <=> t.ubicacion
                   AND o.detalle_extra <=> t.detalle_extra AND o.nivel_afectacion <=> t.nivel AND o.id_evidencia <=> t.id_evidencia);
        SET v_cambios = v_cambios + ROW_COUNT();

        UPDATE informe_observacion o
        JOIN tmp_in_obs t ON t.id = o.id_observacion
        SET o.titulo = t.titulo, o.descripcion = t.descripcion, o.ubicacion = t.ubicacion, o.detalle_extra = t.detalle_extra,
            o.nivel_afectacion = t.nivel, o.id_evidencia = t.id_evidencia, o.orden = t.ord, o.modificado_por = p_id_usuario;

        -- Códigos de las nuevas: siguiente OBS-NN (cuenta también las eliminadas para no reutilizar códigos)
        SELECT IFNULL(MAX(CAST(SUBSTRING(codigo, 5) AS UNSIGNED)), 0) INTO v_max
        FROM informe_observacion WHERE id_informe = p_id_informe;
        DROP TEMPORARY TABLE IF EXISTS tmp_obs_nuevas;
        CREATE TEMPORARY TABLE tmp_obs_nuevas AS
        SELECT t.ord, CONCAT('OBS-', LPAD(v_max + ROW_NUMBER() OVER (ORDER BY t.ord), 2, '0')) AS codigo
        FROM tmp_in_obs t WHERE t.id IS NULL;

        INSERT INTO informe_observacion (id_informe, codigo, orden, titulo, descripcion, ubicacion, detalle_extra, nivel_afectacion,
                                         id_evidencia, origen, creado_por)
        SELECT p_id_informe, n.codigo, t.ord, t.titulo, t.descripcion, t.ubicacion, t.detalle_extra, t.nivel, t.id_evidencia,
               'supervisor', p_id_usuario
        FROM tmp_in_obs t JOIN tmp_obs_nuevas n ON n.ord = t.ord;
        SET v_n = ROW_COUNT();
        IF v_n > 0 THEN
            INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, descripcion, id_usuario, registrado_en, metadata)
            SELECT 'informe_tecnico', p_id_informe, 'edicion_observacion', CONCAT('Agregó Observación ', n.codigo, ' — ', t.titulo),
                   p_id_usuario, NOW(), JSON_OBJECT('categoria', 'edicion', 'cambios', CONCAT_WS(' · ',
                       IF(t.ubicacion IS NULL, NULL, CONCAT('Ubicación «', t.ubicacion, '»')),
                       IF(t.nivel IS NULL, NULL, CONCAT('Nivel de afectación ', t.nivel))))
            FROM tmp_in_obs t JOIN tmp_obs_nuevas n ON n.ord = t.ord;
            SET v_cambios = v_cambios + v_n;
            UPDATE tmp_in_obs t
            JOIN tmp_obs_nuevas n ON n.ord = t.ord
            JOIN informe_observacion o ON o.id_informe = p_id_informe AND o.codigo = n.codigo AND o.eliminado_en IS NULL
            SET t.id = o.id_observacion;
        END IF;
        DROP TEMPORARY TABLE IF EXISTS tmp_obs_nuevas;
    END IF;

    -- Recomendaciones (después de las observaciones, para vincular las nuevas)
    IF p_recomendaciones IS NOT NULL THEN
        UPDATE tmp_in_rec r
        JOIN tmp_in_obs o ON o.ord = r.indice_observacion + 1
        SET r.id_observacion = o.id
        WHERE r.indice_observacion IS NOT NULL;

        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, descripcion, id_usuario, registrado_en, metadata)
        SELECT 'informe_tecnico', p_id_informe, 'edicion_recomendacion', CONCAT('Eliminó Recomendación ', r.codigo, ' — ', r.titulo),
               p_id_usuario, NOW(), JSON_OBJECT('categoria', 'edicion', 'cambios', 'Recomendación eliminada')
        FROM informe_recomendacion r
        WHERE r.id_informe = p_id_informe AND r.eliminado_en IS NULL
          AND r.id_recomendacion NOT IN (SELECT t.id FROM tmp_in_rec t WHERE t.id IS NOT NULL);
        SET v_cambios = v_cambios + ROW_COUNT();
        UPDATE informe_recomendacion SET eliminado_en = NOW(), eliminado_por = p_id_usuario
        WHERE id_informe = p_id_informe AND eliminado_en IS NULL
          AND id_recomendacion NOT IN (SELECT t.id FROM tmp_in_rec t WHERE t.id IS NOT NULL);

        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, descripcion, id_usuario, registrado_en, metadata)
        SELECT 'informe_tecnico', p_id_informe, 'edicion_recomendacion', CONCAT('Editó Recomendación ', r.codigo, ' — ', t.titulo),
               p_id_usuario, NOW(),
               JSON_OBJECT('categoria', 'edicion', 'cambios', CONCAT_WS(' · ',
                   IF(r.titulo         <=> t.titulo,         NULL, CONCAT('Título: «', r.titulo, '» → «', t.titulo, '»')),
                   IF(r.descripcion    <=> t.descripcion,    NULL, 'Descripción actualizada'),
                   IF(r.prioridad      <=> t.prioridad,      NULL, CONCAT('Prioridad: ', r.prioridad, ' → ', t.prioridad)),
                   IF(r.plazo          <=> t.plazo,          NULL, CONCAT('Plazo: «', IFNULL(r.plazo, '—'), '» → «', IFNULL(t.plazo, '—'), '»')),
                   IF(r.id_observacion <=> t.id_observacion, NULL, 'Observación vinculada actualizada')))
        FROM informe_recomendacion r
        JOIN tmp_in_rec t ON t.id = r.id_recomendacion
        WHERE NOT (r.titulo <=> t.titulo AND r.descripcion <=> t.descripcion AND r.prioridad <=> t.prioridad
                   AND r.plazo <=> t.plazo AND r.id_observacion <=> t.id_observacion);
        SET v_cambios = v_cambios + ROW_COUNT();

        UPDATE informe_recomendacion r
        JOIN tmp_in_rec t ON t.id = r.id_recomendacion
        SET r.titulo = t.titulo, r.descripcion = t.descripcion, r.prioridad = t.prioridad, r.plazo = t.plazo,
            r.id_observacion = t.id_observacion, r.orden = t.ord, r.modificado_por = p_id_usuario;

        SELECT IFNULL(MAX(CAST(SUBSTRING(codigo, 5) AS UNSIGNED)), 0) INTO v_max
        FROM informe_recomendacion WHERE id_informe = p_id_informe;
        DROP TEMPORARY TABLE IF EXISTS tmp_rec_nuevas;
        CREATE TEMPORARY TABLE tmp_rec_nuevas AS
        SELECT t.ord, CONCAT('REC-', LPAD(v_max + ROW_NUMBER() OVER (ORDER BY t.ord), 2, '0')) AS codigo
        FROM tmp_in_rec t WHERE t.id IS NULL;

        INSERT INTO informe_recomendacion (id_informe, codigo, orden, titulo, descripcion, prioridad, plazo, id_observacion, origen, creado_por)
        SELECT p_id_informe, n.codigo, t.ord, t.titulo, t.descripcion, t.prioridad, t.plazo, t.id_observacion, 'supervisor', p_id_usuario
        FROM tmp_in_rec t JOIN tmp_rec_nuevas n ON n.ord = t.ord;
        SET v_n = ROW_COUNT();
        IF v_n > 0 THEN
            INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, descripcion, id_usuario, registrado_en, metadata)
            SELECT 'informe_tecnico', p_id_informe, 'edicion_recomendacion', CONCAT('Agregó Recomendación ', n.codigo, ' — ', t.titulo),
                   p_id_usuario, NOW(), JSON_OBJECT('categoria', 'edicion', 'cambios', CONCAT('Prioridad ', t.prioridad,
                       IF(t.plazo IS NULL, '', CONCAT(' · Plazo «', t.plazo, '»'))))
            FROM tmp_in_rec t JOIN tmp_rec_nuevas n ON n.ord = t.ord;
            SET v_cambios = v_cambios + v_n;
        END IF;
        DROP TEMPORARY TABLE IF EXISTS tmp_rec_nuevas;
    END IF;

    -- Resultado global de los ensayos
    IF p_resultado IS NOT NULL THEN
        SELECT CONCAT_WS(' · ',
                   IF(normativa <=> NULLIF(TRIM(JSON_UNQUOTE(JSON_EXTRACT(p_resultado, '$.normativa'))), 'null'), NULL, 'Normativa'),
                   IF(patron_ensayo <=> NULLIF(TRIM(JSON_UNQUOTE(JSON_EXTRACT(p_resultado, '$.patronEnsayo'))), 'null'), NULL, 'Patrón'),
                   IF(resultado_global <=> NULLIF(LOWER(TRIM(JSON_UNQUOTE(JSON_EXTRACT(p_resultado, '$.resultadoGlobal')))), 'null'), NULL,
                      CONCAT('Resultado global: ', IFNULL(resultado_global, '—'), ' → ',
                             IFNULL(NULLIF(LOWER(TRIM(JSON_UNQUOTE(JSON_EXTRACT(p_resultado, '$.resultadoGlobal')))), 'null'), '—'))),
                   IF(decision_tecnica <=> NULLIF(TRIM(JSON_UNQUOTE(JSON_EXTRACT(p_resultado, '$.decisionTecnica'))), 'null'), NULL, 'Decisión técnica'))
        INTO v_texto
        FROM informe_tecnico WHERE id_informe = p_id_informe;

        UPDATE informe_tecnico SET
            normativa                = LEFT(NULLIF(NULLIF(TRIM(JSON_UNQUOTE(JSON_EXTRACT(p_resultado, '$.normativa'))), 'null'), ''), 120),
            patron_ensayo            = LEFT(NULLIF(NULLIF(TRIM(JSON_UNQUOTE(JSON_EXTRACT(p_resultado, '$.patronEnsayo'))), 'null'), ''), 200),
            tolerancia_excentricidad = CAST(NULLIF(JSON_UNQUOTE(JSON_EXTRACT(p_resultado, '$.toleranciaExcentricidad')), 'null') AS DECIMAL(14,4)),
            resultado_global         = NULLIF(NULLIF(LOWER(TRIM(JSON_UNQUOTE(JSON_EXTRACT(p_resultado, '$.resultadoGlobal')))), 'null'), ''),
            error_maximo             = CAST(NULLIF(JSON_UNQUOTE(JSON_EXTRACT(p_resultado, '$.errorMaximo')), 'null') AS DECIMAL(10,4)),
            error_maximo_detalle     = LEFT(NULLIF(NULLIF(TRIM(JSON_UNQUOTE(JSON_EXTRACT(p_resultado, '$.errorMaximoDetalle'))), 'null'), ''), 150),
            incertidumbre            = CAST(NULLIF(JSON_UNQUOTE(JSON_EXTRACT(p_resultado, '$.incertidumbre')), 'null') AS DECIMAL(10,4)),
            factor_k                 = CAST(NULLIF(JSON_UNQUOTE(JSON_EXTRACT(p_resultado, '$.factorK')), 'null') AS DECIMAL(4,2)),
            decision_tecnica         = LEFT(NULLIF(NULLIF(TRIM(JSON_UNQUOTE(JSON_EXTRACT(p_resultado, '$.decisionTecnica'))), 'null'), ''), 300),
            modificado_por           = p_id_usuario
        WHERE id_informe = p_id_informe;

        IF IFNULL(v_texto, '') <> '' THEN
            INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, descripcion, id_usuario, registrado_en, metadata)
            VALUES ('informe_tecnico', p_id_informe, 'edicion_ensayo', 'Editó el resultado global de los ensayos',
                    p_id_usuario, NOW(), JSON_OBJECT('categoria', 'edicion', 'cambios', v_texto));
            SET v_cambios = v_cambios + 1;
        END IF;
    END IF;

    -- Descripción complementaria
    IF IFNULL(p_cambiar_descripcion, 0) = 1 THEN
        SELECT descripcion_complementaria INTO v_previo FROM informe_tecnico WHERE id_informe = p_id_informe;
        IF NOT (v_previo <=> NULLIF(TRIM(p_descripcion), '')) THEN
            UPDATE informe_tecnico SET descripcion_complementaria = NULLIF(TRIM(p_descripcion), ''), modificado_por = p_id_usuario
            WHERE id_informe = p_id_informe;
            INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, descripcion, id_usuario, registrado_en, metadata)
            VALUES ('informe_tecnico', p_id_informe, 'edicion_descripcion',
                    IF(v_previo IS NULL, 'Agregó la descripción complementaria', 'Editó la descripción complementaria'),
                    p_id_usuario, NOW(), JSON_OBJECT('categoria', 'edicion', 'cambios',
                        CONCAT(CHAR_LENGTH(IFNULL(NULLIF(TRIM(p_descripcion), ''), '')), ' caracteres')));
            SET v_cambios = v_cambios + 1;
        END IF;
    END IF;

    COMMIT;

    DROP TEMPORARY TABLE IF EXISTS tmp_in_paso;
    DROP TEMPORARY TABLE IF EXISTS tmp_in_ens;
    DROP TEMPORARY TABLE IF EXISTS tmp_in_obs;
    DROP TEMPORARY TABLE IF EXISTS tmp_in_rec;

    SELECT 2 AS IdTipoMensaje,
           IF(v_cambios = 0, 'No hubo cambios que guardar.', CONCAT('Cambios guardados (', v_cambios, ').')) AS Mensaje;
    SELECT p_id_informe AS id_informe, v_cambios AS cambios_registrados,
           (SELECT estado FROM informe_tecnico WHERE id_informe = p_id_informe) AS estado;
END$$

DELIMITER ;
