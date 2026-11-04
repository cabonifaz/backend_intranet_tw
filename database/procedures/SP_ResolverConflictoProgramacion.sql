-- HU-39 (Sprint 5) "Aplicar Resolución" del modal Resolver Conflicto de Programación. Acceso: prog_gestionar.
-- No inventa un circuito nuevo: vuelve a detectar el conflicto (si ya cambió, avisa) y delega en SP_ReprogramarProgramacion (HU-38), que
-- decide por el permiso del usuario del token: Jefe (prog_aprobar_reprogramacion) = edición directa; Asistente = Solicitud de
-- Reprogramación pendiente. Así no se otorgan permisos nuevos y la auditoría/historial son los mismos de la HU-38.
--   p_tipo / p_id_tecnico / p_id_os_a / p_id_os_b: identifican el conflicto (igual que SP_ObtenerConflictoProgramacion).
--   p_opcion: reasignar (cambia el técnico del servicio; mantiene el estado confirmado) | reprogramar (nueva fecha y horas; vuelve a
--             Pendiente confirmación cliente). La cancelación se hace con SP_CancelarProgramacion (HU-38), siempre disponible.
--   p_id_os_objetivo: la orden afectada por la resolución (debe formar parte del conflicto). NULL = p_id_os_a.
--   p_id_nuevo_tecnico: solo en reasignar. p_fecha, p_hora_inicio, p_hora_fin: solo en reprogramar.
--   p_comentario: opcional; se antepone el motivo autocompletado del conflicto (p. ej. 'SSOMA vencido del técnico Juan Pérez').
-- Resultados: 1 mensaje, 2 resultado (los de SP_ReprogramarProgramacion: modo directa | solicitud).
DROP PROCEDURE IF EXISTS SP_ResolverConflictoProgramacion;

DELIMITER $$

CREATE PROCEDURE SP_ResolverConflictoProgramacion(
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
    IN p_comentario       VARCHAR(400) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_tipo      VARCHAR(25) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_opcion    VARCHAR(15) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_clave     VARCHAR(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_objetivo  BIGINT;
    DECLARE v_id_prog   BIGINT DEFAULT NULL;
    DECLARE v_rol       VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_motivo INT DEFAULT NULL;
    DECLARE v_sugerido  VARCHAR(400) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_coment    VARCHAR(400) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_principal BIGINT DEFAULT NULL;
    DECLARE v_apoyo     JSON DEFAULT NULL;
    DECLARE v_tec_param BIGINT DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            @err_msg  = MESSAGE_TEXT,
            @err_code = MYSQL_ERRNO;
        CALL SP_LimpiarConflictosProgramacion();
        IF @err_code IN (1213, 1205) THEN
            SELECT 1 AS IdTipoMensaje, 'Otra persona está modificando esta programación en este momento. Inténtalo de nuevo.' AS Mensaje;
        ELSE
            SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
        END IF;
    END;

    IF FN_PermisoAccion(p_id_usuario, 'prog_gestionar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para resolver conflictos de programación.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_tipo   = LOWER(TRIM(IFNULL(p_tipo, '')));
    SET v_opcion = LOWER(TRIM(IFNULL(p_opcion, '')));
    IF v_tipo NOT IN ('baja', 'ssoma_vencido', 'solapamiento', 'extension_duracion') THEN
        SELECT 1 AS IdTipoMensaje, 'El tipo de conflicto no es válido.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF IFNULL(p_id_tecnico, 0) <= 0 OR IFNULL(p_id_os_a, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Indica el técnico y la orden del conflicto.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_tipo IN ('solapamiento', 'extension_duracion') THEN
        IF IFNULL(p_id_os_b, 0) <= 0 OR p_id_os_b = p_id_os_a THEN
            SELECT 1 AS IdTipoMensaje, 'Indica las dos órdenes que se cruzan.' AS Mensaje;
            LEAVE proc;
        END IF;
        SET v_clave = CONCAT(v_tipo, ':', p_id_tecnico, ':', LEAST(p_id_os_a, p_id_os_b), ':', GREATEST(p_id_os_a, p_id_os_b));
    ELSE
        SET v_clave = CONCAT(v_tipo, ':', p_id_tecnico);
    END IF;
    IF v_opcion NOT IN ('reasignar', 'reprogramar') THEN
        SELECT 1 AS IdTipoMensaje, 'Selecciona cómo resolver el conflicto: reasignar o reprogramar.' AS Mensaje;
        LEAVE proc;
    END IF;
    SET v_objetivo = IFNULL(p_id_os_objetivo, p_id_os_a);
    IF v_objetivo NOT IN (p_id_os_a, IFNULL(p_id_os_b, 0)) THEN
        SELECT 1 AS IdTipoMensaje, 'La orden a resolver no forma parte de este conflicto.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_opcion = 'reasignar' THEN
        IF IFNULL(p_id_nuevo_tecnico, 0) <= 0 THEN
            SELECT 1 AS IdTipoMensaje, 'Selecciona el técnico que asumirá el servicio.' AS Mensaje;
            LEAVE proc;
        END IF;
        IF p_id_nuevo_tecnico = p_id_tecnico THEN
            SELECT 1 AS IdTipoMensaje, 'El nuevo técnico debe ser distinto del técnico en conflicto.' AS Mensaje;
            LEAVE proc;
        END IF;
    ELSE
        IF p_fecha IS NULL OR p_hora_inicio IS NULL OR p_hora_fin IS NULL THEN
            SELECT 1 AS IdTipoMensaje, 'Indica la nueva fecha y el horario del servicio.' AS Mensaje;
            LEAVE proc;
        END IF;
    END IF;

    -- Se vuelve a detectar: nada de datos viejos
    CALL SP_ArmarConflictosProgramacion();
    IF NOT EXISTS (SELECT 1 FROM tmp_cf WHERE clave = v_clave) THEN
        CALL SP_LimpiarConflictosProgramacion();
        SELECT 1 AS IdTipoMensaje, 'El conflicto ya no existe o cambió: actualiza la lista de alertas.' AS Mensaje;
        LEAVE proc;
    END IF;
    SELECT c.id_motivo, c.motivo_sugerido INTO v_id_motivo, v_sugerido FROM tmp_cf c WHERE c.clave = v_clave;
    SELECT a.id_programacion, a.rol INTO v_id_prog, v_rol
    FROM tmp_cf_asig a WHERE a.id_os = v_objetivo AND a.id_usuario = p_id_tecnico;
    IF v_rol IS NULL THEN
        CALL SP_LimpiarConflictosProgramacion();
        SELECT 1 AS IdTipoMensaje, 'El conflicto ya no existe o cambió: actualiza la lista de alertas.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_id_prog IS NULL THEN
        CALL SP_LimpiarConflictosProgramacion();
        SELECT 1 AS IdTipoMensaje, 'Este servicio no tiene una programación vigente: edítalo desde su ficha.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_id_motivo IS NULL THEN
        CALL SP_LimpiarConflictosProgramacion();
        SELECT 1 AS IdTipoMensaje, 'No hay un motivo de reprogramación configurado para este conflicto.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_coment = LEFT(CONCAT(IFNULL(v_sugerido, ''),
                               IF(NULLIF(TRIM(IFNULL(p_comentario, '')), '') IS NULL, '', CONCAT(' — ', TRIM(p_comentario)))), 400);

    IF v_opcion = 'reasignar' THEN
        SELECT os.id_tecnico_principal INTO v_principal FROM orden_servicio os WHERE os.id_os = v_objetivo;
        IF v_rol = 'principal' THEN
            SET v_tec_param = p_id_nuevo_tecnico;
        ELSE
            -- El técnico en conflicto es de apoyo: se sustituye dentro de la lista de apoyo
            SELECT JSON_ARRAYAGG(x.id_usuario) INTO v_apoyo FROM (
                SELECT DISTINCT IF(pe.id_usuario = p_id_tecnico, p_id_nuevo_tecnico, pe.id_usuario) AS id_usuario
                FROM os_personal pe
                WHERE pe.id_os = v_objetivo AND pe.eliminado_en IS NULL AND pe.id_usuario <> IFNULL(v_principal, 0)
            ) x;
        END IF;
    END IF;

    CALL SP_LimpiarConflictosProgramacion();

    IF v_opcion = 'reasignar' THEN
        CALL SP_ReprogramarProgramacion(p_id_usuario, v_id_prog, NULL, NULL, NULL, v_tec_param, v_apoyo, NULL, v_id_motivo, v_coment);
    ELSE
        CALL SP_ReprogramarProgramacion(p_id_usuario, v_id_prog, p_fecha, p_hora_inicio, p_hora_fin, NULL, NULL, NULL, v_id_motivo, v_coment);
    END IF;
END$$

DELIMITER ;
