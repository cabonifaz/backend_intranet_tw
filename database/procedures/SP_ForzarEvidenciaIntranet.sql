-- ============================================================
-- SP_ForzarEvidenciaIntranet  (HU-55 — forzar una evidencia que la IA rechazó, desde la intranet · escritura)
-- Copia ADAPTADA de SP_ForzarEvidenciaMovil (que no se toca) para quien registra el informe en nombre del técnico:
--   - El técnico se resuelve dentro (orden_servicio.id_tecnico_principal) y el acceso móvil (OS del técnico, llegada, equipo EN EJECUCIÓN) lo valida SP_ContextoEquipoMovil con ese técnico.
--     Acción seg_registrar_informe (FN_PermisoAccion).
--   - Solo con un MOTIVO ESCRITO (3 a 300 caracteres), solo la última captura vigente y solo si está rechazada. Repetirlo sobre una ya forzada responde éxito sin duplicar nada.
--   - Marca la evidencia FORZADA (override_aprobado = 1) con el motivo, quién la forzó (id_usuario_override = QUIEN REGISTRA, no el técnico) y cuándo.
--   - NO suma foto_override_count al scorecard del técnico (la decisión no es suya), a diferencia del SP móvil.
--   - Deja el forzado en auditoria_evento (con quién, en nombre de quién y via = intranet) y avisa a Jefatura igual que el SP móvil (Área + Rol, SP_ArmarAprobadoresOsMovil; si no hay, el
--     encargado del área según la RQ; si tampoco, los administradores), sin avisar a quien registra.
-- Resultados: 1 mensaje; 2 (id_evidencia, forzada_en en Lima, intentos_previos, notificados) — los mismos que SP_ForzarEvidenciaMovil.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ForzarEvidenciaIntranet;

DELIMITER $$

CREATE PROCEDURE SP_ForzarEvidenciaIntranet(
    IN p_id_registrador BIGINT,
    IN p_id_os          BIGINT,
    IN p_id_os_equipo   BIGINT,
    IN p_id_evidencia   BIGINT,
    IN p_motivo         VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_msg      VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tecnico  BIGINT       DEFAULT NULL;
    DECLARE v_id_eq    BIGINT;
    DECLARE v_est_eq   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_hab      TINYINT;
    DECLARE v_numero   INT;
    DECLARE v_nombre   VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_num_os   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_servicio VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_motivo   VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_codigo   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_valida   VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_ya       TINYINT DEFAULT 0;
    DECLARE v_vigente  TINYINT DEFAULT 0;
    DECLARE v_intento  INT DEFAULT 1;
    DECLARE v_motivo_ia VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_forzada  DATETIME DEFAULT NULL;
    DECLARE v_area     VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_enc   BIGINT;
    DECLARE v_nom_enc  VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_car_enc  VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tel_enc  VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_nom_reg  VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_nom_tec  VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_texto    VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_notif    INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov, tmp_aprobadores;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_registrador, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 OR IFNULL(p_id_os_equipo, 0) <= 0 OR IFNULL(p_id_evidencia, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Evidencia no encontrada.' AS Mensaje; LEAVE proc;
    END IF;
    IF FN_PermisoAccion(p_id_registrador, 'seg_registrar_informe') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para registrar informes desde la intranet.' AS Mensaje; LEAVE proc;
    END IF;
    SET v_motivo = NULLIF(TRIM(IFNULL(p_motivo, '')), '');
    IF v_motivo IS NULL OR CHAR_LENGTH(v_motivo) < 3 THEN
        SELECT 1 AS IdTipoMensaje, 'Escribe el motivo por el que se acepta la foto (mínimo 3 caracteres).' AS Mensaje; LEAVE proc;
    END IF;
    IF CHAR_LENGTH(v_motivo) > 300 THEN
        SELECT 1 AS IdTipoMensaje, 'El motivo puede tener hasta 300 caracteres.' AS Mensaje; LEAVE proc;
    END IF;

    SELECT os.id_tecnico_principal INTO v_tecnico FROM orden_servicio os WHERE os.id_os = p_id_os AND os.eliminado_en IS NULL;
    IF v_tecnico IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio no encontrado o sin técnico asignado.' AS Mensaje; LEAVE proc;
    END IF;

    START TRANSACTION;

    CALL SP_ContextoEquipoMovil(v_tecnico, p_id_os, p_id_os_equipo, v_msg, v_id_eq, v_est_eq, v_hab, v_numero, v_nombre, v_num_os, v_servicio);
    IF v_msg IS NULL AND (v_hab = 0 OR v_est_eq <> 'en_ejecucion') THEN
        SET v_msg = IF(v_est_eq = 'pausado', 'El equipo está pausado: reanúdalo para registrar evidencias.',
                       IF(v_est_eq = 'completado', 'Este equipo ya está completado.', 'El servicio ya no está en curso: no se pueden registrar evidencias.'));
    END IF;
    IF v_msg IS NOT NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje; LEAVE proc;
    END IF;

    SELECT f.codigo, f.validacion_ia, f.override_aprobado, f.vigente, f.intento, f.motivo_rechazo_ia, f.forzada_en
    INTO   v_codigo, v_valida, v_ya, v_vigente, v_intento, v_motivo_ia, v_forzada
    FROM   evidencia_fotografica f
    WHERE  f.id_evidencia = p_id_evidencia AND f.id_os = p_id_os AND f.id_equipo = v_id_eq AND f.eliminado_en IS NULL
    FOR UPDATE;

    IF v_codigo IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Evidencia no encontrada.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_ya = 1 THEN
        COMMIT;
        SELECT 2 AS IdTipoMensaje, 'Esta evidencia ya estaba aceptada como forzada.' AS Mensaje;
        SELECT p_id_evidencia AS id_evidencia, CONVERT_TZ(v_forzada, '+00:00', '-05:00') AS forzada_en, v_intento - 1 AS intentos_previos, 0 AS notificados;
        LEAVE proc;
    END IF;
    IF v_valida <> 'rechazada' THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Solo se puede forzar una foto que la IA rechazó.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_vigente = 0 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Esa toma ya fue reemplazada por una más reciente.' AS Mensaje; LEAVE proc;
    END IF;

    SELECT TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))) INTO v_nom_reg FROM usuario u WHERE u.id_usuario = p_id_registrador LIMIT 1;
    SELECT TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))) INTO v_nom_tec FROM usuario u WHERE u.id_usuario = v_tecnico LIMIT 1;

    -- Quien fuerza es QUIEN REGISTRA; el scorecard del técnico NO se toca
    SET v_forzada = UTC_TIMESTAMP();
    UPDATE evidencia_fotografica
    SET    override_aprobado = 1, id_usuario_override = p_id_registrador, motivo_forzado = v_motivo, forzada_en = v_forzada, modificado_por = p_id_registrador
    WHERE  id_evidencia = p_id_evidencia;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('os_equipo', p_id_os_equipo, 'forzar_evidencia', 'rechazada', 'forzada',
            LEFT(CONCAT('Evidencia ', v_codigo, ' de ', v_num_os, ' aceptada a la fuerza tras ', v_intento, IF(v_intento = 1, ' intento', ' intentos'),
                        ' desde la intranet por ', IFNULL(v_nom_reg, ''), ' en nombre del técnico ', IFNULL(v_nom_tec, ''),
                        '. Rechazo de la IA: ', IFNULL(v_motivo_ia, '—'), '. Motivo: ', v_motivo), 900),
            p_id_registrador, NOW(),
            JSON_OBJECT('id_evidencia', p_id_evidencia, 'codigo', v_codigo, 'intentos', v_intento, 'motivo', v_motivo, 'motivo_ia', v_motivo_ia,
                        'via', 'intranet', 'id_registrador', p_id_registrador, 'id_tecnico', v_tecnico));

    -- Visible para Jefatura (igual que el SP móvil): aviso al encargado del área (si no hay, a los administradores); nunca a quien registra
    CALL SP_ContactoEncargadoEnsayoMovil(p_id_os, v_area, v_id_enc, v_nom_enc, v_car_enc, v_tel_enc);
    SET v_texto = LEFT(CONCAT(IFNULL(v_nom_reg, ''), ' (desde la intranet, en nombre de ', IFNULL(v_nom_tec, ''), ') aceptó a la fuerza la evidencia «', v_codigo, '» de ', v_nombre,
                              ' (', v_num_os, '), rechazada por la IA. Motivo: ', v_motivo), 500);
    CALL SP_ArmarAprobadoresOsMovil(p_id_os);
    INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
    SELECT a.id_usuario, 5, 'Evidencia forzada', v_texto, 'orden_servicio', p_id_os, NOW(), p_id_registrador
    FROM   tmp_aprobadores a
    WHERE  a.id_usuario <> p_id_registrador;
    SET v_notif = ROW_COUNT();
    DROP TEMPORARY TABLE IF EXISTS tmp_aprobadores;
    IF v_notif > 0 THEN
        SET v_notif = v_notif;
    ELSEIF v_id_enc IS NOT NULL AND v_id_enc <> p_id_registrador THEN
        INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
        VALUES (v_id_enc, 5, 'Evidencia forzada', v_texto, 'orden_servicio', p_id_os, NOW(), p_id_registrador);
        SET v_notif = 1;
    ELSE
        INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
        SELECT u.id_usuario, 5, 'Evidencia forzada', v_texto, 'orden_servicio', p_id_os, NOW(), p_id_registrador
        FROM   usuario u
        WHERE  u.eliminado_en IS NULL AND u.estado = 'activo' AND u.id_usuario <> p_id_registrador AND u.rol_sistema IN ('administrador', 'admin');
        SET v_notif = ROW_COUNT();
    END IF;

    COMMIT;

    SELECT 2 AS IdTipoMensaje, 'Foto aceptada como evidencia forzada: quedó registrada y visible para Jefatura.' AS Mensaje;
    SELECT p_id_evidencia AS id_evidencia, CONVERT_TZ(v_forzada, '+00:00', '-05:00') AS forzada_en, v_intento - 1 AS intentos_previos, v_notif AS notificados;
END$$

DELIMITER ;
