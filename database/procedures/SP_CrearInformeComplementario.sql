-- ============================================================
-- SP_CrearInformeComplementario  (Revisión Técnica — "Generar Informe Complementario", 23/11/2026 · escritura)
-- El Supervisor Técnico ya no edita el informe del técnico (es inmutable): si hace falta, genera un INFORME COMPLEMENTARIO, una fila nueva de
-- informe_tecnico con id_informe_padre = informe original. Uno solo por informe: si ya existe, se devuelve el mismo (no crea otro).
-- Acceso: rt_editar y el informe original en el alcance del usuario (SP_ArmarBaseInformes). El original no debe estar revisado.
-- Qué precarga desde el original (copias propias del complementario, editables):
--   · fotos y videos vigentes del servicio (misma regla que el detalle; mismo archivo, fila nueva con id_evidencia_origen)
--   · observaciones (con su foto vinculada) y recomendaciones (con su observación vinculada)
--   · descripción complementaria (observaciones generales) y diagnóstico
--   Los datos generales, el procedimiento y los ensayos NO se copian: se leen del original (solo lectura) en SP_ObtenerInformeComplementario.
-- El complementario va SIN id_os ni id_equipo (y sus fotos también) para que la app móvil nunca lo tome como el informe del técnico.
-- Nace en estado 'borrador' (pasa a 'complementario' al guardarlo con cambios). El original pasa a 'en_revision' si aún no lo estaba.
-- Resultados: 1 mensaje; 2 (id_informe_complementario, numero, estado, creado, fotos, observaciones, recomendaciones).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_CrearInformeComplementario;

DELIMITER $$

CREATE PROCEDURE SP_CrearInformeComplementario(
    IN p_id_usuario BIGINT,
    IN p_id_informe BIGINT
)
proc: BEGIN
    DECLARE v_existe   INT DEFAULT 0;
    DECLARE v_id_os    BIGINT;
    DECLARE v_id_eq    BIGINT;
    DECLARE v_estado   VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_numero   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_comp  BIGINT DEFAULT NULL;
    DECLARE v_num_comp VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_est_comp VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_n_fotos  INT DEFAULT 0;
    DECLARE v_n_obs    INT DEFAULT 0;
    DECLARE v_n_rec    INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF FN_PermisoAccion(p_id_usuario, 'rt_editar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para generar informes complementarios.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_ArmarBaseInformes(p_id_usuario, IFNULL(p_id_informe, 0));
    SELECT COUNT(*), MAX(id_os), MAX(id_equipo) INTO v_existe, v_id_os, v_id_eq FROM tmp_rt_base;
    DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;
    IF v_existe = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El informe no existe o no está en tu alcance.' AS Mensaje;
        LEAVE proc;
    END IF;

    START TRANSACTION;

    SELECT estado, numero INTO v_estado, v_numero FROM informe_tecnico WHERE id_informe = p_id_informe FOR UPDATE;
    IF v_estado IN ('revisado', 'aprobado') THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'El informe ya fue revisado: no se puede generar un informe complementario.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Uno solo por informe: si ya existe (guardado o en borrador) se abre el mismo
    SELECT c.id_informe, c.numero, c.estado INTO v_id_comp, v_num_comp, v_est_comp
    FROM informe_tecnico c
    WHERE c.id_informe = (SELECT MAX(c2.id_informe) FROM informe_tecnico c2 WHERE c2.id_informe_padre = p_id_informe AND c2.eliminado_en IS NULL);
    IF v_id_comp IS NOT NULL THEN
        COMMIT;
        SELECT 2 AS IdTipoMensaje, 'El informe ya tiene un informe complementario: se abre el existente.' AS Mensaje;
        SELECT v_id_comp AS id_informe_complementario, v_num_comp AS numero, v_est_comp AS estado, 0 AS creado,
               (SELECT COUNT(*) FROM evidencia_fotografica f WHERE f.id_informe = v_id_comp AND f.eliminado_en IS NULL)   AS fotos,
               (SELECT COUNT(*) FROM informe_observacion o WHERE o.id_informe = v_id_comp AND o.eliminado_en IS NULL)     AS observaciones,
               (SELECT COUNT(*) FROM informe_recomendacion r WHERE r.id_informe = v_id_comp AND r.eliminado_en IS NULL)   AS recomendaciones;
        LEAVE proc;
    END IF;

    -- Fila del complementario (sin OS ni equipo: se enlaza solo por id_informe_padre)
    INSERT INTO informe_tecnico (numero, id_os, id_equipo, id_tecnico, id_revisor, diagnostico_principal, descripcion_complementaria,
                                 estado, version, id_informe_padre, fecha_creacion, creado_por)
    SELECT CONCAT('CMP-TMP-', FLOOR(RAND() * 1000000000)), NULL, NULL, p_id_usuario, p_id_usuario, o.diagnostico_principal, o.descripcion_complementaria,
           'borrador', 1, o.id_informe, NOW(), p_id_usuario
    FROM informe_tecnico o WHERE o.id_informe = p_id_informe;
    SET v_id_comp = LAST_INSERT_ID();
    SET v_num_comp = CONCAT('CMP-', LPAD(v_id_comp, 8, '0'));
    UPDATE informe_tecnico SET numero = v_num_comp WHERE id_informe = v_id_comp;

    -- Fotos y videos vigentes del servicio (la misma regla de SP_ObtenerDetalleInformeTecnico): mismo archivo, fila propia
    INSERT INTO evidencia_fotografica (id_os, id_equipo, id_informe, id_usuario, id_tipo_evidencia, url_archivo, descripcion, latitud, longitud,
                                       timestamp_captura, validacion_ia, override_aprobado, id_usuario_override, codigo, pagina, es_video,
                                       duracion_seg, ruta_cuadro, vigente, motivo_forzado, forzada_en, motivo_rechazo_ia,
                                       id_evidencia_origen, creado_por)
    SELECT NULL, NULL, v_id_comp, f.id_usuario, f.id_tipo_evidencia, f.url_archivo, f.descripcion, f.latitud, f.longitud,
           f.timestamp_captura, f.validacion_ia, f.override_aprobado, f.id_usuario_override, f.codigo, f.pagina, f.es_video,
           f.duracion_seg, f.ruta_cuadro, 1, f.motivo_forzado, f.forzada_en, f.motivo_rechazo_ia,
           f.id_evidencia, p_id_usuario
    FROM evidencia_fotografica f
    WHERE f.eliminado_en IS NULL AND f.id_tipo_evidencia NOT IN (6, 7) AND f.url_archivo NOT LIKE 'qr://%' AND IFNULL(f.vigente, 1) = 1
      AND (f.id_informe = p_id_informe
           OR (f.id_informe IS NULL AND f.id_os = v_id_os AND (f.id_equipo = v_id_eq OR f.id_equipo IS NULL)))
    ORDER BY f.timestamp_captura, f.id_evidencia;
    SET v_n_fotos = ROW_COUNT();

    -- Observaciones (la foto vinculada pasa a ser su copia en el complementario)
    INSERT INTO informe_observacion (id_informe, codigo, orden, titulo, descripcion, ubicacion, detalle_extra, nivel_afectacion, id_evidencia,
                                     origen, clasificacion, componente, id_observacion_origen, creado_por)
    SELECT v_id_comp, o.codigo, o.orden, o.titulo, o.descripcion, o.ubicacion, o.detalle_extra, o.nivel_afectacion, fc.id_evidencia,
           o.origen, o.clasificacion, o.componente, o.id_observacion, p_id_usuario
    FROM informe_observacion o
    LEFT JOIN evidencia_fotografica fc ON fc.id_informe = v_id_comp AND fc.id_evidencia_origen = o.id_evidencia AND fc.eliminado_en IS NULL
    WHERE o.id_informe = p_id_informe AND o.eliminado_en IS NULL
    ORDER BY o.orden, o.id_observacion;
    SET v_n_obs = ROW_COUNT();

    -- Fotos vinculadas a una observación (desde la foto): apuntan a la copia de la observación
    UPDATE evidencia_fotografica fc
    JOIN evidencia_fotografica fo ON fo.id_evidencia = fc.id_evidencia_origen
    JOIN informe_observacion oc   ON oc.id_informe = v_id_comp AND oc.id_observacion_origen = fo.id_observacion AND oc.eliminado_en IS NULL
    SET fc.id_observacion = oc.id_observacion
    WHERE fc.id_informe = v_id_comp AND fo.id_observacion IS NOT NULL;

    -- Recomendaciones (la observación vinculada pasa a ser su copia)
    INSERT INTO informe_recomendacion (id_informe, codigo, orden, titulo, descripcion, prioridad, plazo, id_observacion, origen, creado_por)
    SELECT v_id_comp, r.codigo, r.orden, r.titulo, r.descripcion, r.prioridad, r.plazo, oc.id_observacion, r.origen, p_id_usuario
    FROM informe_recomendacion r
    LEFT JOIN informe_observacion oc ON oc.id_informe = v_id_comp AND oc.id_observacion_origen = r.id_observacion AND oc.eliminado_en IS NULL
    WHERE r.id_informe = p_id_informe AND r.eliminado_en IS NULL
    ORDER BY r.orden, r.id_recomendacion;
    SET v_n_rec = ROW_COUNT();

    -- Generar el complementario es empezar la revisión
    IF v_estado IN ('pendiente_revision', 'observado') THEN
        UPDATE informe_tecnico
        SET estado = 'en_revision', fecha_inicio_revision = IFNULL(fecha_inicio_revision, NOW()), id_revisor = p_id_usuario, modificado_por = p_id_usuario
        WHERE id_informe = p_id_informe;
        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
        VALUES ('informe_tecnico', p_id_informe, 'inicio_revision', v_estado, 'en_revision', 'Inició la revisión del informe',
                p_id_usuario, NOW(), JSON_OBJECT('categoria', 'revision', 'detalle', 'Generó el informe complementario'));
    END IF;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('informe_tecnico', p_id_informe, 'complementario_generado',
            CONCAT('Generó el informe complementario ', v_num_comp, ' (', v_n_fotos, IF(v_n_fotos = 1, ' foto, ', ' fotos, '),
                   v_n_obs, IF(v_n_obs = 1, ' observación y ', ' observaciones y '), v_n_rec, IF(v_n_rec = 1, ' recomendación', ' recomendaciones'),
                   ' precargadas del informe del técnico)'),
            p_id_usuario, NOW(), JSON_OBJECT('categoria', 'edicion', 'id_complementario', v_id_comp));

    COMMIT;

    SELECT 2 AS IdTipoMensaje, CONCAT('Informe complementario ', v_num_comp, ' generado.') AS Mensaje;
    SELECT v_id_comp AS id_informe_complementario, v_num_comp AS numero, 'borrador' AS estado, 1 AS creado,
           v_n_fotos AS fotos, v_n_obs AS observaciones, v_n_rec AS recomendaciones;
END$$

DELIMITER ;
