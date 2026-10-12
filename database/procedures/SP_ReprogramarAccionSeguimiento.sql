-- HU-20 Reprogramar la próxima acción pendiente de una propuesta en seguimiento.
-- Reglas:
--   Acción propuesta_seguimiento_reprogramar, propuesta en seguimiento ABIERTO y del área del usuario.
--   Tipo de acción, nueva fecha y hora (futura y distinta de la actual), prioridad,
--   responsable activo del área y motivo obligatorios. Detalle obligatorio (10 a 500 caracteres).
--   Si la propuesta ya tiene seguimientos, se actualiza la acción del último seguimiento (así el
--   detalle, la bandeja y el siguiente registro la toman). Si aún no tiene, se reprograma el
--   "Primer seguimiento" (queda en seguimiento_reprogramacion con id_seguimiento NULL).
--   Siempre se guarda el historial con la acción anterior y la nueva.
--   Si el nuevo responsable es otra persona, se le notifica.
-- Resultados: 1 mensaje, 2 id_reprogramacion.
DROP PROCEDURE IF EXISTS SP_ReprogramarAccionSeguimiento;

DELIMITER $$

CREATE PROCEDURE SP_ReprogramarAccionSeguimiento(
    IN p_id_usuario      BIGINT,
    IN p_id_propuesta    BIGINT,
    IN p_id_tipo_accion  INT,
    IN p_fecha_nueva     DATETIME,
    IN p_id_prioridad    INT,
    IN p_id_responsable  BIGINT,
    IN p_id_motivo       INT,
    IN p_detalle         VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_dias_sin_resp  INT;
    DECLARE v_meta           INT;
    DECLARE v_sla_horas      INT;
    DECLARE v_alerta_horas   INT;
    DECLARE v_existe         INT DEFAULT 0;
    DECLARE v_abierta        INT DEFAULT 0;
    DECLARE v_numero         VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_ult_seg     BIGINT;
    DECLARE v_estado_ult     VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_resp_prop   BIGINT;
    DECLARE v_fecha_ant      DATETIME;
    DECLARE v_tipo_ant       INT;
    DECLARE v_prioridad_ant  INT;
    DECLARE v_resp_ant       BIGINT;
    DECLARE v_area           VARCHAR(60)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tipo_nombre    VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_detalle        VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_usuario        VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_reprog      BIGINT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_seg;
        GET DIAGNOSTICS CONDITION 1
            @err_msg  = MESSAGE_TEXT,
            @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje,
               CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SET v_detalle = NULLIF(TRIM(IFNULL(p_detalle, '')), '');

    IF FN_PermisoAccion(p_id_usuario, 'propuesta_seguimiento_reprogramar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para reprogramar acciones de seguimiento.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_CalcularSeguimientoComercial(p_id_usuario, p_id_propuesta,
                                         v_dias_sin_resp, v_meta, v_sla_horas, v_alerta_horas);
    SELECT COUNT(*), MAX(numero), MAX(id_ult_seg), MAX(estado_ult_seg), MAX(id_responsable),
           MAX(vence_accion), MAX(id_tipo_proxima_accion), MAX(id_prioridad_accion),
           MAX(COALESCE(id_responsable_accion, id_responsable)),
           IFNULL(SUM(estado_seguimiento IN ('en_seguimiento', 'sin_respuesta', 'requiere_ajuste')), 0)
      INTO v_existe, v_numero, v_id_ult_seg, v_estado_ult, v_id_resp_prop,
           v_fecha_ant, v_tipo_ant, v_prioridad_ant, v_resp_ant, v_abierta
    FROM tmp_seg;
    DROP TEMPORARY TABLE IF EXISTS tmp_seg;

    IF v_existe = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'La propuesta no está en seguimiento comercial o no pertenece a tu área.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_abierta = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El seguimiento de esta propuesta ya está cerrado (aceptada o rechazada).' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Tipo de acción
    SELECT MAX(String1) INTO v_tipo_nombre
    FROM tabla_maestra
    WHERE Descripcion = 'TIPO_ACCION_SEGUIMIENTO' AND IdEmpresa = 1 AND Num1 = p_id_tipo_accion;
    IF v_tipo_nombre IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Seleccione el tipo de acción.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Nueva fecha
    IF p_fecha_nueva IS NULL OR p_fecha_nueva <= NOW() THEN
        SELECT 1 AS IdTipoMensaje, 'La nueva fecha y hora deben ser futuras.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_fecha_ant IS NOT NULL AND p_fecha_nueva = v_fecha_ant THEN
        SELECT 1 AS IdTipoMensaje, 'La nueva fecha y hora son iguales a las programadas. Elija otra fecha u hora.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Prioridad
    IF p_id_prioridad IS NULL OR NOT EXISTS (
        SELECT 1 FROM tabla_maestra WHERE IdMaestro = 7 AND IdEmpresa = 1 AND Num1 = p_id_prioridad) THEN
        SELECT 1 AS IdTipoMensaje, 'Seleccione la prioridad.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Responsable
    SELECT area INTO v_area FROM usuario WHERE id_usuario = v_id_resp_prop;
    IF p_id_responsable IS NULL OR NOT EXISTS (
        SELECT 1 FROM usuario
        WHERE id_usuario = p_id_responsable AND eliminado_en IS NULL AND estado = 'activo'
          AND (area = v_area OR id_usuario = p_id_usuario)) THEN
        SELECT 1 AS IdTipoMensaje, 'Seleccione un responsable activo del área.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Motivo y detalle
    IF p_id_motivo IS NULL OR NOT EXISTS (
        SELECT 1 FROM tabla_maestra
        WHERE Descripcion = 'MOTIVO_REPROGRAMACION_SEGUIMIENTO' AND IdEmpresa = 1 AND Num1 = p_id_motivo) THEN
        SELECT 1 AS IdTipoMensaje, 'Seleccione el motivo de la reprogramación.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_detalle IS NULL OR CHAR_LENGTH(v_detalle) < 10 THEN
        SELECT 1 AS IdTipoMensaje, 'Explique el motivo de la reprogramación (mínimo 10 caracteres).' AS Mensaje;
        LEAVE proc;
    END IF;

    START TRANSACTION;

    -- Con seguimientos: se actualiza la acción del último seguimiento (siempre está activo si la propuesta está abierta)
    IF v_id_ult_seg IS NOT NULL THEN
        UPDATE seguimiento_comercial
        SET proxima_accion_fecha   = p_fecha_nueva,
            id_tipo_proxima_accion = p_id_tipo_accion,
            id_prioridad_accion    = p_id_prioridad,
            id_responsable         = p_id_responsable,
            modificado_por         = p_id_usuario
        WHERE id_seguimiento = v_id_ult_seg;
    END IF;

    INSERT INTO seguimiento_reprogramacion (
        id_propuesta, id_seguimiento,
        fecha_anterior, id_tipo_accion_anterior, id_prioridad_anterior, id_responsable_anterior,
        fecha_nueva, id_tipo_accion_nueva, id_prioridad_nueva, id_responsable_nuevo,
        id_motivo, detalle, creado_por)
    VALUES (
        p_id_propuesta, v_id_ult_seg,
        v_fecha_ant, v_tipo_ant, v_prioridad_ant, v_resp_ant,
        p_fecha_nueva, p_id_tipo_accion, p_id_prioridad, p_id_responsable,
        p_id_motivo, v_detalle, p_id_usuario);

    SET v_id_reprog = LAST_INSERT_ID();

    IF p_id_responsable <> p_id_usuario THEN
        SELECT CONCAT(nombre, ' ', apellido) INTO v_usuario FROM usuario WHERE id_usuario = p_id_usuario;
        INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
        VALUES (p_id_responsable, 5,
                CONCAT('Acción reprogramada: ', v_numero),
                CONCAT(v_usuario, ' reprogramó "', v_tipo_nombre, '" de la propuesta ', v_numero,
                       ' para el ', DATE_FORMAT(p_fecha_nueva, '%d/%m/%Y %H:%i'), '. Motivo: ', v_detalle),
                'propuesta', p_id_propuesta, NOW(), p_id_usuario);
    END IF;

    COMMIT;

    SELECT 2 AS IdTipoMensaje, 'Acción reprogramada.' AS Mensaje;
    SELECT v_id_reprog AS id_reprogramacion;
END$$

DELIMITER ;
