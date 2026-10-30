-- HU-40 (Sprint 4) El comercial responsable solicita al Jefe Comercial la edición de una OS/OM emitida.
-- Motivo tipificado (MOTIVO_EDICION_OS) + comentario (20 a 500 caracteres). Notifica al Jefe Comercial (campanita;
-- el correo lo envía la aplicación con los datos que devuelve) y queda en la auditoría.
-- Resultados: 1 mensaje, 2 datos de la solicitud (para el correo).
DROP PROCEDURE IF EXISTS SP_SolicitarEdicionOrdenServicio;

DELIMITER $$

CREATE PROCEDURE SP_SolicitarEdicionOrdenServicio(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT,
    IN p_id_motivo  INT,
    IN p_comentario VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_estado    VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_resp      BIGINT;
    DECLARE v_numero    VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tipo      CHAR(2);
    DECLARE v_aprobador BIGINT;
    DECLARE v_motivo    VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_usuario   VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cliente   VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_sol    BIGINT;
    DECLARE v_error     VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SET p_comentario = TRIM(IFNULL(p_comentario, ''));
    SELECT os.estado, os.id_responsable_comercial, os.numero, os.tipo, c.razon_social
      INTO v_estado, v_resp, v_numero, v_tipo, v_cliente
    FROM orden_servicio os LEFT JOIN cliente c ON c.id_cliente = os.id_cliente
    WHERE os.id_os = p_id_os AND os.eliminado_en IS NULL;
    SELECT String1 INTO v_motivo FROM tabla_maestra
    WHERE Descripcion = 'MOTIVO_EDICION_OS' AND Num1 = p_id_motivo AND eliminado_en IS NULL LIMIT 1;

    IF v_estado IS NULL THEN
        SET v_error = 'Orden de servicio no encontrada.';
    ELSEIF FN_PermisoAccion(p_id_usuario, 'os_guardar') = 0 OR NOT (v_resp <=> p_id_usuario) THEN
        SET v_error = 'Solo el comercial responsable de la orden puede solicitar su edición.';
    ELSEIF v_estado NOT IN ('emitida', 'programada', 'reprogramada') THEN
        SET v_error = IF(v_estado = 'borrador', 'La orden está en borrador: puede editarla directamente.',
                         CONCAT('La orden está ', UPPER(REPLACE(v_estado, '_', ' ')), ': ya no se puede editar.'));
    ELSEIF EXISTS (SELECT 1 FROM os_solicitud WHERE id_os = p_id_os AND tipo = 'edicion' AND estado IN ('pendiente', 'aprobada')
                     AND eliminado_en IS NULL) THEN
        SET v_error = 'Ya hay una solicitud de edición pendiente o aprobada para esta orden.';
    ELSEIF v_motivo IS NULL THEN
        SET v_error = 'Seleccione el motivo de la edición.';
    ELSEIF CHAR_LENGTH(p_comentario) < 20 THEN
        SET v_error = 'El comentario es obligatorio (mínimo 20 caracteres).';
    END IF;
    IF v_error IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, v_error AS Mensaje; LEAVE proc;
    END IF;

    -- Jefe Comercial (misma regla que SP_PrepararSolicitudEdicionOrdenServicio)
    SELECT u.id_supervisor, CONCAT(u.nombre, ' ', u.apellido) INTO v_aprobador, v_usuario FROM usuario u WHERE u.id_usuario = p_id_usuario;
    IF v_aprobador IS NULL OR v_aprobador = p_id_usuario
       OR NOT EXISTS (SELECT 1 FROM usuario j WHERE j.id_usuario = v_aprobador AND j.estado = 'activo' AND j.eliminado_en IS NULL)
       OR FN_PermisoAccion(v_aprobador, 'os_aprobar_edicion') = 0 THEN
        SET v_aprobador = NULL;
        SELECT j.id_usuario INTO v_aprobador FROM usuario j
        WHERE j.estado = 'activo' AND j.eliminado_en IS NULL AND j.id_usuario <> p_id_usuario
          AND j.area = 'comercial' AND FN_PermisoAccion(j.id_usuario, 'os_aprobar_edicion') = 1
        ORDER BY (j.rol_sistema = 'supervisor') DESC, j.id_usuario LIMIT 1;
    END IF;
    IF v_aprobador IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'No hay un Jefe Comercial activo con permiso para aprobar la edición.' AS Mensaje; LEAVE proc;
    END IF;

    START TRANSACTION;

    INSERT INTO os_solicitud (id_os, tipo, id_motivo, comentario, estado, id_solicitante, id_aprobador, fecha_solicitud, creado_por)
    VALUES (p_id_os, 'edicion', p_id_motivo, p_comentario, 'pendiente', p_id_usuario, v_aprobador, NOW(), p_id_usuario);
    SET v_id_sol = LAST_INSERT_ID();

    INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
    VALUES (v_aprobador, 5, CONCAT('Solicitud de edición: ', v_numero),
            LEFT(CONCAT(IFNULL(v_usuario, 'Un comercial'), ' solicita editar la ', v_tipo, ' ', v_numero, ' de ',
                        IFNULL(v_cliente, 'el cliente'), '. Motivo: ', v_motivo, '. ', p_comentario), 1000),
            'orden_servicio', p_id_os, NOW(), p_id_usuario);

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion,
                                  id_usuario, registrado_en, metadata)
    VALUES ('orden_servicio', p_id_os, 'solicitar_edicion_os', v_estado, v_estado,
            LEFT(CONCAT('Solicitud de edición al Jefe Comercial. Motivo: ', v_motivo, '. ', p_comentario), 1000),
            p_id_usuario, NOW(), JSON_OBJECT('id_solicitud', v_id_sol, 'id_motivo', p_id_motivo, 'id_aprobador', v_aprobador));

    COMMIT;

    SELECT 2 AS IdTipoMensaje, 'Solicitud enviada al Jefe Comercial.' AS Mensaje;

    SELECT v_id_sol AS id_solicitud, p_id_os AS id_os, v_numero AS numero, v_tipo AS tipo, v_cliente AS razon_social,
           v_motivo AS motivo, p_comentario AS comentario, v_usuario AS solicitante,
           j.id_usuario AS id_destinatario, CONCAT(j.nombre, ' ', j.apellido) AS destinatario, j.correo AS correo_destinatario
    FROM usuario j WHERE j.id_usuario = v_aprobador;
END$$

DELIMITER ;
