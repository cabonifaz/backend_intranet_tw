-- ============================================================
-- SP_ResolverConflictoAgendaMovil  (App Mobile HU-37 — «Resolver» un conflicto de programación desde la agenda del área · escritura)
-- ENVUELVE SP_ResolverConflictoProgramacion (HU-39 de la intranet), que a su vez delega en SP_ReprogramarProgramacion (HU-38): vuelve a detectar el conflicto, valida las opciones y decide por el
-- permiso del usuario del token si es EDICIÓN DIRECTA (prog_aprobar_reprogramacion) o una SOLICITUD de reprogramación pendiente (solo prog_gestionar). Aquí NO se repite ninguna de esas reglas
-- (ni el cruce de horarios, ni la SSOMA, ni el aviso a los técnicos «Servicio reprogramado: …» / «Asignación retirada: …»); solo se añade:
--   · el ALCANCE Área + Rol del jefe (SP_ArmarEquipoAgendaMovil): el técnico del conflicto y, al reasignar, el técnico nuevo deben ser de su equipo; si no, mensaje de negocio.
--   · el MOTIVO elegido en la app (p_id_motivo, del catálogo MOTIVO_REPROGRAMACION): si no viene, se usa el del conflicto (el que ya sugiere la HU-39); el SP de la intranet lo respeta mediante las
--     variables @tw_cf_motivo / @tw_cf_motivo_usuario, que aquí se fijan justo antes y se limpian al terminar (también si falla).
-- Opciones (p_opcion): reasignar (Cambiar técnico: requiere p_id_nuevo_tecnico) · reprogramar (Cambiar horario = la misma fecha con otras horas; Reprogramar con motivo = otra fecha y horas: requiere
--   p_fecha, p_hora_inicio y p_hora_fin). p_id_os_objetivo = la orden a mover (NULL = p_id_os_a). p_comentario hasta 400 (se antepone el motivo autocompletado del conflicto).
-- Resultados: los de SP_ResolverConflictoProgramacion: 1 mensaje, 2 resultado (modo: directa | solicitud).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ResolverConflictoAgendaMovil;

DELIMITER $$

CREATE PROCEDURE SP_ResolverConflictoAgendaMovil(
    IN p_id_usuario       BIGINT,
    IN p_tipo             VARCHAR(25) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_tecnico       BIGINT,
    IN p_id_os_a          BIGINT,
    IN p_id_os_b          BIGINT,
    IN p_opcion           VARCHAR(15) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_os_objetivo   BIGINT,
    IN p_id_nuevo_tecnico BIGINT,
    IN p_fecha            DATE,
    IN p_hora_inicio      TIME,
    IN p_hora_fin         TIME,
    IN p_id_motivo        INT,
    IN p_comentario       VARCHAR(400) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_sin_menu TINYINT DEFAULT 0;
    DECLARE v_en       INT DEFAULT 0;
    DECLARE v_opcion   VARCHAR(15) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SET @tw_eq_inactivos = 0;
        SET @tw_cf_motivo = NULL;
        SET @tw_cf_motivo_usuario = NULL;
        DROP TEMPORARY TABLE IF EXISTS tmp_eq;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0
       OR NOT EXISTS (SELECT 1 FROM usuario u WHERE u.id_usuario = p_id_usuario AND u.eliminado_en IS NULL AND u.estado = 'activo') THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no válido.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF IFNULL(p_id_tecnico, 0) <= 0 OR IFNULL(p_id_os_a, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Indica el técnico y la orden del conflicto.' AS Mensaje;
        LEAVE proc;
    END IF;
    SET v_opcion = LOWER(TRIM(IFNULL(p_opcion, '')));

    -- Alcance Área + Rol: el técnico del conflicto y, al reasignar, el técnico nuevo
    CALL SP_ArmarEquipoAgendaMovil(p_id_usuario, NULL, v_sin_menu);
    IF v_sin_menu = 1 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_eq;
        SELECT 1 AS IdTipoMensaje, 'Tu cargo no tiene el menú de Jefatura.' AS Mensaje;
        LEAVE proc;
    END IF;
    SELECT COUNT(*) INTO v_en FROM tmp_eq e WHERE e.id_usuario = p_id_tecnico;
    IF v_en = 0 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_eq;
        SELECT 1 AS IdTipoMensaje, 'El técnico del conflicto no pertenece a tu equipo.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_opcion = 'reasignar' AND IFNULL(p_id_nuevo_tecnico, 0) > 0 THEN
        SELECT COUNT(*) INTO v_en FROM tmp_eq e WHERE e.id_usuario = p_id_nuevo_tecnico;
        IF v_en = 0 OR NOT EXISTS (SELECT 1 FROM usuario u WHERE u.id_usuario = p_id_nuevo_tecnico AND u.eliminado_en IS NULL AND u.estado = 'activo') THEN
            DROP TEMPORARY TABLE IF EXISTS tmp_eq;
            SELECT 1 AS IdTipoMensaje, 'El técnico elegido no pertenece a tu equipo o no está activo.' AS Mensaje;
            LEAVE proc;
        END IF;
    END IF;
    DROP TEMPORARY TABLE IF EXISTS tmp_eq;

    -- Motivo elegido en la app (opcional): del catálogo MOTIVO_REPROGRAMACION
    IF p_id_motivo IS NOT NULL THEN
        IF NOT EXISTS (SELECT 1 FROM tabla_maestra t WHERE t.IdMaestro = 13 AND t.IdEmpresa = 1 AND t.eliminado_en IS NULL AND t.Num1 = p_id_motivo) THEN
            SELECT 1 AS IdTipoMensaje, 'El motivo de reprogramación no es válido.' AS Mensaje;
            LEAVE proc;
        END IF;
        SET @tw_cf_motivo = p_id_motivo;
        SET @tw_cf_motivo_usuario = p_id_usuario;
    ELSE
        SET @tw_cf_motivo = NULL;
        SET @tw_cf_motivo_usuario = NULL;
    END IF;

    -- La resolución es la de la intranet (permisos, cruces de horario, SSOMA, directa o solicitud, avisos y auditoría)
    CALL SP_ResolverConflictoProgramacion(p_id_usuario, p_tipo, p_id_tecnico, p_id_os_a, p_id_os_b, p_opcion, p_id_os_objetivo, p_id_nuevo_tecnico,
                                          p_fecha, p_hora_inicio, p_hora_fin, p_comentario);

    SET @tw_cf_motivo = NULL;
    SET @tw_cf_motivo_usuario = NULL;
END$$

DELIMITER ;
