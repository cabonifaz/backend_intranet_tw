-- HU-38 (Sprint 5) Retira (cancela) una solicitud de reprogramación pendiente. Puede hacerlo quien la envió (Asistente) o el Jefe.
-- La programación no cambia. Acceso: prog_gestionar. Solo una solicitud pendiente se puede retirar (una resuelta no).
-- Concurrencia: OS → programación → solicitud. Resultados: 1 mensaje, 2 resultado.
DROP PROCEDURE IF EXISTS SP_RetirarSolicitudReprogramacion;

DELIMITER $$

CREATE PROCEDURE SP_RetirarSolicitudReprogramacion(
    IN p_id_usuario    BIGINT,
    IN p_id_solicitud  BIGINT
)
proc: BEGIN
    DECLARE v_id_os        BIGINT DEFAULT NULL;
    DECLARE v_id_prog      BIGINT DEFAULT NULL;
    DECLARE v_estado       VARCHAR(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_solicitante  BIGINT DEFAULT NULL;
    DECLARE v_numero       VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_codigo       VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado_prg   VARCHAR(25) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        ROLLBACK;
        IF @err_code IN (1213, 1205) THEN   -- interbloqueo / espera de bloqueo por otra operación simultánea: se reintenta
            SELECT 1 AS IdTipoMensaje, 'Otra persona está modificando esta programación en este momento. Inténtalo de nuevo.' AS Mensaje;
        ELSE
            SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
        END IF;
    END;

    IF FN_PermisoAccion(p_id_usuario, 'prog_gestionar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para retirar solicitudes de reprogramación.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT rp.id_os, IFNULL(rp.id_programacion, (SELECT MAX(pr.id_programacion) FROM programacion pr
                                                  WHERE pr.id_os = rp.id_os AND pr.estado <> 'cancelada' AND pr.eliminado_en IS NULL))
      INTO v_id_os, v_id_prog
    FROM os_reprogramacion rp WHERE rp.id_reprogramacion = IFNULL(p_id_solicitud, 0) AND rp.eliminado_en IS NULL;
    IF v_id_os IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'La solicitud de reprogramación no existe.' AS Mensaje;
        LEAVE proc;
    END IF;

    START TRANSACTION;

    SELECT numero INTO v_numero FROM orden_servicio WHERE id_os = v_id_os FOR UPDATE;
    IF v_id_prog IS NOT NULL THEN
        SELECT codigo, estado INTO v_codigo, v_estado_prg FROM programacion WHERE id_programacion = v_id_prog FOR UPDATE;
    END IF;
    SELECT estado, id_solicitante INTO v_estado, v_solicitante
    FROM os_reprogramacion WHERE id_reprogramacion = p_id_solicitud AND eliminado_en IS NULL FOR UPDATE;

    IF v_estado IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'La solicitud de reprogramación no existe.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_estado <> 'pendiente' THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, CONCAT('La solicitud ya fue resuelta: está ', v_estado, '.') AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_solicitante <> p_id_usuario AND FN_PermisoAccion(p_id_usuario, 'prog_aprobar_reprogramacion') = 0 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Solo quien envió la solicitud o el Jefe pueden retirarla.' AS Mensaje;
        LEAVE proc;
    END IF;

    UPDATE os_reprogramacion
    SET estado = 'cancelada', resuelto_por = p_id_usuario, fecha_resolucion = NOW(),
        comentario_resolucion = 'Solicitud retirada.', modificado_por = p_id_usuario
    WHERE id_reprogramacion = p_id_solicitud;

    IF v_id_prog IS NOT NULL THEN
        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion,
                                      id_usuario, registrado_en, metadata)
        VALUES ('programacion', v_id_prog, 'retirar_solicitud_reprogramacion', v_estado_prg, v_estado_prg,
                'Solicitud de reprogramación retirada.', p_id_usuario, NOW(), JSON_OBJECT('idSolicitud', p_id_solicitud));
    END IF;

    COMMIT;

    SELECT 2 AS IdTipoMensaje, 'Solicitud retirada. La programación sigue como estaba.' AS Mensaje;
    SELECT p_id_solicitud AS id_solicitud, 'cancelada' AS estado_solicitud, v_id_prog AS id_programacion, v_codigo AS codigo;
END$$

DELIMITER ;
