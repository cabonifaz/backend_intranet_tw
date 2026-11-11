-- ============================================================
-- SP_SolicitarCorrelativoMovil  (App Mobile HU-14 — "Solicitar correlativo")
-- El técnico pide a Metrología el correlativo de certificación de UN equipo de su OS. Crea el ticket TK-MET-##### (ticket_metrologia, estado solicitado).
--   Reglas (el contexto lo valida SP_ContextoCorrelativoMovil, una sola vez): la OS es suya, Hard Stop de llegada, equipo EN EJECUCIÓN, ensayos finalizados
--   (HU-10), el equipo aún sin certificado y sin otro ticket abierto (solicitado o asignado). Observación opcional de hasta 300 caracteres.
--   Se serializa por equipo bloqueando su informe técnico; luego el ticket. Avisos (notificacion, canal 5): al técnico "Solicitud de correlativo enviada" y a los
--   jefes de Metrología (SP_ArmarJefesMetrologiaMovil) "Solicitud de correlativo". Auditoría: auditoria_evento (entidad ticket_metrologia).
-- Resultados: 1 mensaje (1 regla de negocio · 2 éxito · 3 error) · 2 (solo éxito) id_ticket, numero, estado, solicitado_en (hora de Lima), notificados.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_SolicitarCorrelativoMovil;

DELIMITER $$

CREATE PROCEDURE SP_SolicitarCorrelativoMovil(
    IN p_id_usuario   BIGINT,
    IN p_id_os        BIGINT,
    IN p_id_os_equipo BIGINT,
    IN p_id_tipo      INT,
    IN p_observacion  VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_msg      VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_id_eq    BIGINT DEFAULT NULL;
    DECLARE v_estado   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_hab      TINYINT DEFAULT 0;
    DECLARE v_num_os   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_informe  BIGINT DEFAULT NULL;
    DECLARE v_final    DATETIME DEFAULT NULL;
    DECLARE v_cert     VARCHAR(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_cod_eq   VARCHAR(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_obs      VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_tipo     VARCHAR(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_dup_num  VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_ticket   BIGINT DEFAULT NULL;
    DECLARE v_numero   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_nombre   VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_ahora    DATETIME;
    DECLARE v_jefes    INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_cc_ctx;
        DROP TEMPORARY TABLE IF EXISTS tmp_jm_jefes;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 OR IFNULL(p_id_os_equipo, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio o equipo no válido.' AS Mensaje; LEAVE proc;
    END IF;
    SELECT m.String1 INTO v_tipo
    FROM   tabla_maestra m
    WHERE  m.Descripcion = 'TIPO_CERTIFICADO_MET' AND m.IdEmpresa = 1 AND m.Num1 = p_id_tipo AND m.eliminado_en IS NULL LIMIT 1;
    IF IFNULL(p_id_tipo, 0) <= 0 OR v_tipo IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Elige el tipo de certificado.' AS Mensaje; LEAVE proc;
    END IF;
    SET v_obs = NULLIF(TRIM(IFNULL(p_observacion, '')), '');
    IF CHAR_LENGTH(v_obs) > 300 THEN
        SELECT 1 AS IdTipoMensaje, 'La observación puede tener hasta 300 caracteres.' AS Mensaje; LEAVE proc;
    END IF;

    START TRANSACTION;

    CALL SP_ContextoCorrelativoMovil(p_id_usuario, p_id_os, p_id_os_equipo);
    SELECT c.mensaje, c.id_equipo, c.estado_equipo, c.habilitado, c.numero_os, c.id_informe, c.ens_final, c.numero_certificado, COALESCE(c.codigo_cliente, c.codigo_tw)
    INTO   v_msg, v_id_eq, v_estado, v_hab, v_num_os, v_informe, v_final, v_cert, v_cod_eq
    FROM   tmp_cc_ctx c LIMIT 1;
    DROP TEMPORARY TABLE IF EXISTS tmp_cc_ctx;

    IF v_msg IS NULL AND (v_hab = 0 OR v_estado <> 'en_ejecucion') THEN
        SET v_msg = IF(v_estado = 'pausado', 'El equipo está pausado: reanúdalo para solicitar el correlativo.',
                       IF(v_estado = 'completado', 'Este equipo ya está completado.', 'El servicio ya no está en curso.'));
    ELSEIF v_msg IS NULL AND (v_informe IS NULL OR v_final IS NULL) THEN
        SET v_msg = 'Primero finaliza los ensayos y la calibración del equipo.';
    ELSEIF v_msg IS NULL AND v_cert IS NOT NULL THEN
        SET v_msg = CONCAT('Este equipo ya tiene el certificado ', v_cert, '.');
    END IF;
    IF v_msg IS NOT NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje; LEAVE proc;
    END IF;

    -- Se serializa por equipo (su informe técnico) para no crear dos tickets a la vez
    SELECT it.id_informe INTO v_informe FROM informe_tecnico it WHERE it.id_informe = v_informe FOR UPDATE;
    SELECT t.numero INTO v_dup_num
    FROM   ticket_metrologia t
    WHERE  t.id_os = p_id_os AND t.id_equipo = v_id_eq AND t.estado IN ('solicitado', 'asignado') AND t.eliminado_en IS NULL
    ORDER BY t.id_ticket_met DESC LIMIT 1 FOR UPDATE;
    IF v_dup_num IS NOT NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, CONCAT('Ya hay un ticket abierto para este equipo (', v_dup_num, ').') AS Mensaje; LEAVE proc;
    END IF;

    SET v_ahora = UTC_TIMESTAMP();
    INSERT INTO ticket_metrologia (numero, id_os, id_equipo, id_tecnico_solicitante, id_tipo_certificado, estado, notas, fecha_solicitud, creado_por)
    VALUES (CONCAT('TMP-', FLOOR(RAND() * 1000000000)), p_id_os, v_id_eq, p_id_usuario, p_id_tipo, 'solicitado', v_obs, v_ahora, p_id_usuario);
    SET v_ticket = LAST_INSERT_ID();
    SET v_numero = CONCAT('TK-MET-', LPAD(v_ticket, 5, '0'));
    UPDATE ticket_metrologia SET numero = v_numero WHERE id_ticket_met = v_ticket;

    SELECT TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))) INTO v_nombre FROM usuario u WHERE u.id_usuario = p_id_usuario LIMIT 1;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('ticket_metrologia', v_ticket, 'solicitar_correlativo', NULL, 'solicitado',
            LEFT(CONCAT(v_nombre, ' solicitó el correlativo del equipo ', IFNULL(v_cod_eq, ''), ' (', v_num_os, '). Tipo: ', v_tipo, '.'), 900),
            p_id_usuario, NOW(),
            JSON_OBJECT('ticket', v_numero, 'id_os', p_id_os, 'id_equipo', v_id_eq, 'id_tipo_certificado', p_id_tipo, 'observacion', v_obs));

    -- Avisos: a los jefes de Metrología y la confirmación al técnico
    CALL SP_ArmarJefesMetrologiaMovil();
    INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
    SELECT j.id_usuario, 5, 'Solicitud de correlativo',
           LEFT(CONCAT(v_nombre, ' solicita un correlativo · ', v_numero, ' · ', v_num_os, ' · ', IFNULL(v_cod_eq, ''), ' · ', v_tipo), 500),
           'ticket_metrologia', v_ticket, NOW(), p_id_usuario
    FROM   tmp_jm_jefes j WHERE j.id_usuario <> p_id_usuario;
    SET v_jefes = ROW_COUNT();
    DROP TEMPORARY TABLE IF EXISTS tmp_jm_jefes;

    INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
    VALUES (p_id_usuario, 5, 'Solicitud de correlativo enviada',
            CONCAT(v_numero, IF(v_jefes > 0, ' · avisado al supervisor de Metrología', ' · en espera de Metrología')),
            'ticket_metrologia', v_ticket, NOW(), p_id_usuario);

    COMMIT;

    SELECT 2 AS IdTipoMensaje, CONCAT('Solicitud enviada · ticket ', v_numero, ' creado.') AS Mensaje;
    SELECT v_ticket AS id_ticket, v_numero AS numero, 'solicitado' AS estado, CONVERT_TZ(v_ahora, '+00:00', '-05:00') AS solicitado_en, v_jefes AS notificados;
END$$

DELIMITER ;
