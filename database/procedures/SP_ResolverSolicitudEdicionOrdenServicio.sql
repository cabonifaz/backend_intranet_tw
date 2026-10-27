-- HU-40 / HU-42 (Sprint 4) El Jefe Comercial aprueba o rechaza la solicitud de edición de una OS/OM.
--   Aprobar: el comercial ya puede entrar a "Editar OS/OM". Rechazar: comentario obligatorio (mínimo 10 caracteres).
--   Notifica al comercial (campanita; el correo lo envía la aplicación) y queda en la auditoría.
-- Resultados: 1 mensaje, 2 datos para el correo al comercial.
DROP PROCEDURE IF EXISTS SP_ResolverSolicitudEdicionOrdenServicio;

DELIMITER $$

CREATE PROCEDURE SP_ResolverSolicitudEdicionOrdenServicio(
    IN p_id_usuario   BIGINT,
    IN p_id_solicitud BIGINT,
    IN p_aprobar      TINYINT,
    IN p_comentario   VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_id_os     BIGINT;
    DECLARE v_estado    VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado_os VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_solic     BIGINT;
    DECLARE v_aprobador BIGINT;
    DECLARE v_numero    VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tipo      CHAR(2);
    DECLARE v_motivo    VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_usuario   VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_error     VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SET p_comentario = NULLIF(TRIM(IFNULL(p_comentario, '')), '');
    SELECT s.id_os, s.estado, s.id_solicitante, s.id_aprobador, os.numero, os.tipo, os.estado, me.String1
      INTO v_id_os, v_estado, v_solic, v_aprobador, v_numero, v_tipo, v_estado_os, v_motivo
    FROM os_solicitud s
    JOIN orden_servicio os ON os.id_os = s.id_os
    LEFT JOIN tabla_maestra me ON me.Descripcion = 'MOTIVO_EDICION_OS' AND me.Num1 = s.id_motivo
    WHERE s.id_solicitud = p_id_solicitud AND s.tipo = 'edicion' AND s.eliminado_en IS NULL;

    IF v_id_os IS NULL THEN
        SET v_error = 'Solicitud no encontrada.';
    ELSEIF FN_PermisoAccion(p_id_usuario, 'os_aprobar_edicion') = 0 THEN
        SET v_error = 'Solo el Jefe Comercial puede aprobar o rechazar la edición.';
    ELSEIF v_solic = p_id_usuario THEN
        SET v_error = 'No puede resolver su propia solicitud de edición.';
    ELSEIF v_estado <> 'pendiente' THEN
        SET v_error = CONCAT('La solicitud ya fue ', IF(v_estado = 'aprobada', 'aprobada', IF(v_estado = 'rechazada', 'rechazada', 'resuelta')), '.');
    ELSEIF IFNULL(p_aprobar, 0) = 0 AND CHAR_LENGTH(IFNULL(p_comentario, '')) < 10 THEN
        SET v_error = 'Indique el motivo del rechazo (mínimo 10 caracteres).';
    END IF;
    IF v_error IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, v_error AS Mensaje; LEAVE proc;
    END IF;

    SELECT CONCAT(nombre, ' ', apellido) INTO v_usuario FROM usuario WHERE id_usuario = p_id_usuario;

    START TRANSACTION;

    UPDATE os_solicitud
    SET estado = IF(IFNULL(p_aprobar, 0) = 1, 'aprobada', 'rechazada'), resuelto_por = p_id_usuario, fecha_resolucion = NOW(),
        comentario_resolucion = p_comentario, modificado_por = p_id_usuario
    WHERE id_solicitud = p_id_solicitud;

    INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
    VALUES (v_solic, 5,
            CONCAT(IF(IFNULL(p_aprobar, 0) = 1, 'Edición aprobada: ', 'Edición rechazada: '), v_numero),
            LEFT(IF(IFNULL(p_aprobar, 0) = 1,
                    CONCAT(IFNULL(v_usuario, 'El Jefe Comercial'), ' aprobó la edición de la ', v_tipo, ' ', v_numero,
                           '. Ya puede editarla.', IFNULL(CONCAT(' ', p_comentario), '')),
                    CONCAT(IFNULL(v_usuario, 'El Jefe Comercial'), ' rechazó la edición de la ', v_tipo, ' ', v_numero,
                           '. Motivo: ', p_comentario)), 1000),
            'orden_servicio', v_id_os, NOW(), p_id_usuario);

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion,
                                  id_usuario, registrado_en, metadata)
    VALUES ('orden_servicio', v_id_os, IF(IFNULL(p_aprobar, 0) = 1, 'aprobar_edicion_os', 'rechazar_edicion_os'),
            v_estado_os, v_estado_os,
            LEFT(CONCAT(IF(IFNULL(p_aprobar, 0) = 1, 'Edición aprobada por el Jefe Comercial', 'Edición rechazada por el Jefe Comercial'),
                        ' (motivo de la solicitud: ', IFNULL(v_motivo, '—'), ')', IFNULL(CONCAT('. ', p_comentario), ''), '.'), 1000),
            p_id_usuario, NOW(), JSON_OBJECT('id_solicitud', p_id_solicitud));

    COMMIT;

    SELECT 2 AS IdTipoMensaje,
           IF(IFNULL(p_aprobar, 0) = 1, 'Edición aprobada. Se notificó al comercial.', 'Edición rechazada. Se notificó al comercial.') AS Mensaje;

    SELECT p_id_solicitud AS id_solicitud, v_id_os AS id_os, v_numero AS numero, v_tipo AS tipo,
           (IFNULL(p_aprobar, 0) = 1) AS aprobada, v_motivo AS motivo, p_comentario AS comentario, v_usuario AS resuelto_por,
           u.id_usuario AS id_destinatario, CONCAT(u.nombre, ' ', u.apellido) AS destinatario, u.correo AS correo_destinatario,
           (SELECT c.razon_social FROM orden_servicio os JOIN cliente c ON c.id_cliente = os.id_cliente WHERE os.id_os = v_id_os) AS razon_social
    FROM usuario u WHERE u.id_usuario = v_solic;
END$$

DELIMITER ;
