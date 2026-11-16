-- ============================================================
-- SP_ReasignarTecnicoMovil  (App Mobile HU-32 — "Reasignar a <técnico>" · escritura)
-- El jefe pasa el servicio a otro técnico cercano, de la misma especialidad y con SSOMA conforme.
--   - La OS debe estar en el alcance del jefe y no estar finalizada ni anulada. El nuevo técnico debe ser candidato habilitado
--     (SP_ObtenerTecnicosReasignacionMovil: misma especialidad, SSOMA conforme o por vencer, con cupo en el día).
--   - Cambia el técnico principal de la OS (orden_servicio) y de su programación confirmada (programacion), que es de donde lee la bandeja de Seguimiento.
--     El técnico anterior, si integraba el personal (os_personal), se quita; el nuevo queda como principal.
--   - Avisa por notificación al técnico anterior ("Servicio reasignado") y al nuevo ("Nuevo servicio: reasignado…", abre el servicio). Deja auditoría.
--   - OJO: no copia la salida / llegada ya registradas del técnico anterior: el nuevo técnico registra las suyas. Aviso al cliente: no hay canal en el sistema todavía.
-- Resultados: 1 mensaje; 2 (id_os, id_tecnico, tecnico, notificados).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ReasignarTecnicoMovil;

DELIMITER $$

CREATE PROCEDURE SP_ReasignarTecnicoMovil(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT,
    IN p_id_tecnico BIGINT
)
proc: BEGIN
    DECLARE v_area      VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_sede      VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_aut_area  VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_aut_gen   TINYINT;
    DECLARE v_existe    INT DEFAULT 0;
    DECLARE v_num_os    VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado    VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tec_ant   BIGINT DEFAULT NULL;
    DECLARE v_habil     TINYINT DEFAULT 0;
    DECLARE v_nom_nuevo VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_nom_ant   VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_nom_jefe  VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_notif     INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_jf_alc;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_os, 0) <= 0 OR IFNULL(p_id_tecnico, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Elige el técnico al que se reasigna el servicio.' AS Mensaje; LEAVE proc;
    END IF;
    CALL SP_ResolverJefaturaMovil(p_id_usuario, v_area, v_sede, v_aut_area, v_aut_gen);
    IF v_area IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Tu cargo no tiene el menú de Jefatura.' AS Mensaje; LEAVE proc;
    END IF;
    CALL SP_ArmarAlcanceJefaturaMovil(v_area, p_id_os);
    SELECT COUNT(*) INTO v_existe FROM tmp_jf_alc WHERE id_os = p_id_os;
    DROP TEMPORARY TABLE IF EXISTS tmp_jf_alc;
    IF v_existe = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El servicio no existe o no pertenece a tu área.' AS Mensaje; LEAVE proc;
    END IF;

    SELECT os.numero, os.estado, os.id_tecnico_principal INTO v_num_os, v_estado, v_tec_ant FROM orden_servicio os WHERE os.id_os = p_id_os AND os.eliminado_en IS NULL;
    IF v_estado IN ('finalizada', 'anulada', 'borrador', 'emitida') THEN
        SELECT 1 AS IdTipoMensaje, 'Este servicio ya no se puede reasignar.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_tec_ant = p_id_tecnico THEN
        SELECT 1 AS IdTipoMensaje, 'Ese técnico ya está asignado al servicio.' AS Mensaje; LEAVE proc;
    END IF;

    -- El nuevo técnico debe ser de la misma especialidad y tener la SSOMA habilitada (misma regla que la lista de candidatos)
    SELECT TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))) INTO v_nom_nuevo
    FROM   usuario u
    WHERE  u.id_usuario = p_id_tecnico AND u.eliminado_en IS NULL AND u.estado = 'activo' AND u.area IN ('servicio_tecnico', 'metrologia')
      AND  (u.cargo IS NULL OR (u.cargo NOT LIKE 'jefe\_%' AND u.cargo NOT LIKE 'asistente\_%'))
      AND  (v_tec_ant IS NULL OR u.area = (SELECT x.area FROM usuario x WHERE x.id_usuario = v_tec_ant));
    IF v_nom_nuevo IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Ese técnico no es de la misma especialidad o no está activo.' AS Mensaje; LEAVE proc;
    END IF;

    DROP TEMPORARY TABLE IF EXISTS tmp_ssoma_in;
    CREATE TEMPORARY TABLE tmp_ssoma_in (id_usuario BIGINT NOT NULL, PRIMARY KEY (id_usuario));
    INSERT INTO tmp_ssoma_in (id_usuario) VALUES (p_id_tecnico);
    CALL SP_EvaluarSsomaProgramacion(p_id_os, NULL);
    SELECT IF(IFNULL(s.estado, 'conforme') IN ('conforme', 'por_vencer'), 1, 0) INTO v_habil FROM tmp_ssoma_res s WHERE s.id_usuario = p_id_tecnico;
    SET v_habil = IFNULL(v_habil, 1);
    DROP TEMPORARY TABLE IF EXISTS tmp_ssoma_in;
    CALL SP_LimpiarSsomaProgramacion();
    IF v_habil = 0 THEN
        SELECT 1 AS IdTipoMensaje, CONCAT(v_nom_nuevo, ' no tiene la SSOMA conforme para este servicio.') AS Mensaje; LEAVE proc;
    END IF;

    SELECT TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))) INTO v_nom_ant FROM usuario u WHERE u.id_usuario = v_tec_ant;
    SELECT TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))) INTO v_nom_jefe FROM usuario u WHERE u.id_usuario = p_id_usuario;

    START TRANSACTION;

    UPDATE orden_servicio SET id_tecnico_principal = p_id_tecnico WHERE id_os = p_id_os;
    UPDATE programacion SET id_tecnico_principal = p_id_tecnico WHERE id_os = p_id_os AND estado = 'confirmada' AND eliminado_en IS NULL;
    IF v_tec_ant IS NOT NULL THEN
        UPDATE os_personal SET eliminado_en = NOW() WHERE id_os = p_id_os AND id_usuario = v_tec_ant AND eliminado_en IS NULL;
    END IF;

    IF v_tec_ant IS NOT NULL AND v_tec_ant <> p_id_usuario THEN
        INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
        VALUES (v_tec_ant, 5, 'Servicio reasignado', LEFT(CONCAT(v_nom_jefe, ' reasignó ', v_num_os, ' a ', v_nom_nuevo, '. Ya no es tu servicio.'), 500), 'orden_servicio', p_id_os, NOW(), p_id_usuario);
        SET v_notif = v_notif + 1;
    END IF;
    INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
    VALUES (p_id_tecnico, 5, CONCAT('Nuevo servicio: ', v_num_os), LEFT(CONCAT(v_nom_jefe, ' te reasignó el servicio ', v_num_os, IF(v_nom_ant IS NULL, '', CONCAT(' (antes de ', v_nom_ant, ')')), '. Revísalo y sal a planta.'), 500),
            'orden_servicio', p_id_os, NOW(), p_id_usuario);
    SET v_notif = v_notif + 1;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('orden_servicio', p_id_os, 'reasignar_tecnico', v_nom_ant, v_nom_nuevo,
            LEFT(CONCAT(v_nom_jefe, ' reasignó ', v_num_os, ' de ', IFNULL(v_nom_ant, 'sin técnico'), ' a ', v_nom_nuevo), 900),
            p_id_usuario, NOW(), JSON_OBJECT('id_os', p_id_os, 'id_tecnico_anterior', v_tec_ant, 'id_tecnico_nuevo', p_id_tecnico));

    COMMIT;

    SELECT 2 AS IdTipoMensaje, CONCAT(v_num_os, ' reasignado a ', v_nom_nuevo, '.') AS Mensaje;
    SELECT p_id_os AS id_os, p_id_tecnico AS id_tecnico, v_nom_nuevo AS tecnico, v_notif AS notificados;
END$$

DELIMITER ;
