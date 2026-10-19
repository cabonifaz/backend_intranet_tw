-- HU-13b — Solicitar revocación de visto bueno
--   El comercial autor pide revertir la aprobación de VB porque la propuesta aún no
--   ha salido al cliente y necesita ajustes de fondo o abandonar la oportunidad.
--   Reglas:
--     * La propuesta debe estar en estado 'aprobado' (ya pasó VB, no se ha enviado).
--     * El usuario debe ser el autor responsable y tener la acción propuesta_solicitar_revocacion.
--     * Debe existir un VB anterior aprobado para esa propuesta (la aprobación a revocar).
--     * El motivo es obligatorio, mínimo 10 caracteres.
--   Efectos:
--     * Inserta un NUEVO registro visto_bueno con tipo='revocacion' y estado='revocacion_pendiente',
--       enlazado al VB aprobado anterior vía id_vb_padre.
--     * Propuesta pasa a 'pendiente_revocacion'.
--     * Notifica al equipo del área (bandeja compartida) y audita.
DROP PROCEDURE IF EXISTS SP_SolicitarRevocacionVB;

DELIMITER $$

CREATE PROCEDURE SP_SolicitarRevocacionVB(
    IN p_id_propuesta BIGINT,
    IN p_motivo       TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_usuario   BIGINT
)
proc: BEGIN
    DECLARE v_estado      VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_numero      VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_version     INT;
    DECLARE v_id_rq       BIGINT;
    DECLARE v_autor       BIGINT;
    DECLARE v_id_vb_prev  BIGINT;
    DECLARE v_sla         INT;
    DECLARE v_id_vb       BIGINT;
    DECLARE v_usu_nombre  VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SET p_motivo = NULLIF(TRIM(p_motivo), '');

    IF p_motivo IS NULL OR CHAR_LENGTH(p_motivo) < 10 THEN
        SELECT 1 AS IdTipoMensaje, 'Indique el motivo de la revocación (mínimo 10 caracteres).' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT estado, numero, version, id_requerimiento, COALESCE(id_responsable, id_creador)
      INTO v_estado, v_numero, v_version, v_id_rq, v_autor
    FROM propuesta_comercial
    WHERE id_propuesta = p_id_propuesta AND eliminado_en IS NULL;

    IF v_estado IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Propuesta no encontrada.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF v_estado <> 'aprobado' THEN
        SELECT 1 AS IdTipoMensaje,
               CONCAT('Solo puede solicitarse la revocación de una propuesta aprobada. Estado actual: ', v_estado, '.') AS Mensaje;
        LEAVE proc;
    END IF;

    IF FN_PermisoAccion(p_id_usuario, 'propuesta_solicitar_revocacion') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tiene permiso para solicitar la revocación.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF p_id_usuario <> v_autor AND FN_PermisoAccion(p_id_usuario, 'propuesta_vb_todas') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Solo el comercial responsable puede solicitar la revocación.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Último VB aprobado para esta propuesta (padre de la revocación)
    SELECT id_vb, sla_horas INTO v_id_vb_prev, v_sla
    FROM visto_bueno
    WHERE id_propuesta = p_id_propuesta AND estado = 'aprobado' AND IFNULL(tipo, 'aprobacion') = 'aprobacion'
      AND eliminado_en IS NULL
    ORDER BY id_vb DESC LIMIT 1;

    IF v_id_vb_prev IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'No se encontró la aprobación de VB a revocar.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT CONCAT(nombre, ' ', apellido) INTO v_usu_nombre FROM usuario WHERE id_usuario = p_id_usuario;

    START TRANSACTION;

    -- Nuevo registro de VB tipo revocación, hereda el SLA del VB padre
    INSERT INTO visto_bueno (
        id_propuesta, id_aprobador, estado, tipo, motivo_revocacion, id_vb_padre,
        comentario, sla_horas, fecha_solicitud, creado_en, creado_por
    ) VALUES (
        p_id_propuesta, 0, 'revocacion_pendiente', 'revocacion', p_motivo, v_id_vb_prev,
        p_motivo, v_sla, NOW(), NOW(), p_id_usuario
    );
    SET v_id_vb = LAST_INSERT_ID();

    UPDATE propuesta_comercial
       SET estado = 'pendiente_revocacion', modificado_en = NOW(), modificado_por = p_id_usuario
     WHERE id_propuesta = p_id_propuesta;

    IF v_id_rq IS NOT NULL THEN
        INSERT INTO historial_requerimiento (id_requerimiento, tipo, tipo_label, icono, descripcion, usuario, fecha, creado_en, creado_por)
        VALUES (v_id_rq, 'propuesta', 'Revocación de VB solicitada', 'undo',
                CONCAT('Se solicitó revocar la aprobación de VB de la propuesta ', v_numero, ' v', v_version, ': ', p_motivo),
                v_usu_nombre, NOW(), NOW(), p_id_usuario);
    END IF;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('propuesta', p_id_propuesta, 'solicitar_revocacion_vb', 'aprobado', 'pendiente_revocacion',
            CONCAT('Solicitud de revocación de VB creada por ', v_usu_nombre, ': ', p_motivo),
            p_id_usuario, NOW(),
            JSON_OBJECT('id_vb', v_id_vb, 'id_vb_padre', v_id_vb_prev, 'motivo', p_motivo));

    COMMIT;

    SELECT 2 AS IdTipoMensaje, 'Solicitud de revocación enviada. El supervisor del área la revisará.' AS Mensaje;
    SELECT p_id_propuesta AS id_propuesta, v_numero AS numero, v_version AS version,
           'pendiente_revocacion' AS estado, v_id_vb AS id_vb, v_id_vb_prev AS id_vb_padre;
END$$

DELIMITER ;
