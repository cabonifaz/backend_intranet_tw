-- HU-40 (Sprint 4) Anular una OS/OM (BORRADOR, EMITIDA o PROGRAMADA).
-- Motivo tipificado (MOTIVO_ANULACION_OS) + justificación (20 a 500 caracteres).
-- Libera lo que reservó Programación: personal asignado (os_personal), backlog (cancelado) y viáticos asignados que aún
-- no se rindieron. Cancela las solicitudes de edición abiertas. Notifica a Operaciones si la orden ya estaba emitida.
-- Resultados: 1 mensaje, 2 orden anulada.
DROP PROCEDURE IF EXISTS SP_AnularOrdenServicio;

DELIMITER $$

CREATE PROCEDURE SP_AnularOrdenServicio(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT,
    IN p_id_motivo  INT,
    IN p_comentario VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_estado   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_numero   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tipo     CHAR(2);
    DECLARE v_motivo   VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_usuario  VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cliente  VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_personal INT DEFAULT 0;
    DECLARE v_viaticos INT DEFAULT 0;
    DECLARE v_error    VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SET p_comentario = TRIM(IFNULL(p_comentario, ''));
    SELECT os.estado, os.numero, os.tipo, c.razon_social INTO v_estado, v_numero, v_tipo, v_cliente
    FROM orden_servicio os LEFT JOIN cliente c ON c.id_cliente = os.id_cliente
    WHERE os.id_os = p_id_os AND os.eliminado_en IS NULL;
    SELECT String1 INTO v_motivo FROM tabla_maestra
    WHERE Descripcion = 'MOTIVO_ANULACION_OS' AND Num1 = p_id_motivo AND eliminado_en IS NULL LIMIT 1;

    IF v_estado IS NULL THEN
        SET v_error = 'Orden de servicio no encontrada.';
    ELSEIF FN_PermisoAccion(p_id_usuario, 'os_anular') = 0 THEN
        SET v_error = 'No tienes permiso para anular órdenes de servicio.';
    ELSEIF v_estado NOT IN ('borrador', 'emitida', 'programada', 'reprogramada') THEN
        SET v_error = CONCAT('La orden está ', UPPER(REPLACE(v_estado, '_', ' ')), ': ya no se puede anular.');
    ELSEIF v_motivo IS NULL THEN
        SET v_error = 'Seleccione el motivo de anulación.';
    ELSEIF CHAR_LENGTH(p_comentario) < 20 THEN
        SET v_error = 'La justificación es obligatoria (mínimo 20 caracteres).';
    END IF;
    IF v_error IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, v_error AS Mensaje; LEAVE proc;
    END IF;

    SELECT CONCAT(nombre, ' ', apellido) INTO v_usuario FROM usuario WHERE id_usuario = p_id_usuario;

    START TRANSACTION;

    UPDATE orden_servicio
    SET estado = 'anulada', id_motivo_anulacion = p_id_motivo, comentario_anulacion = p_comentario,
        anulado_en = NOW(), anulado_por = p_id_usuario, modificado_por = p_id_usuario
    WHERE id_os = p_id_os;

    -- Recursos de Programación
    UPDATE os_personal SET eliminado_en = NOW(), eliminado_por = p_id_usuario WHERE id_os = p_id_os AND eliminado_en IS NULL;
    SET v_personal = ROW_COUNT();
    UPDATE backlog_programacion SET estado = 'cancelado', modificado_por = p_id_usuario
    WHERE id_os = p_id_os AND eliminado_en IS NULL AND estado <> 'cancelado';
    UPDATE gasto_viatico SET eliminado_en = NOW(), eliminado_por = p_id_usuario
    WHERE id_os = p_id_os AND eliminado_en IS NULL AND tipo = 'viatico_asignado' AND estado IN ('pendiente', 'aprobado');
    SET v_viaticos = ROW_COUNT();

    UPDATE os_solicitud SET estado = 'cancelada', modificado_por = p_id_usuario
    WHERE id_os = p_id_os AND estado IN ('pendiente', 'aprobada') AND eliminado_en IS NULL;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion,
                                  id_usuario, registrado_en, metadata)
    VALUES ('orden_servicio', p_id_os, 'anular_os', v_estado, 'anulada',
            LEFT(CONCAT(v_tipo, ' ', v_numero, ' anulada. Motivo: ', v_motivo, '. ', p_comentario), 1000),
            p_id_usuario, NOW(), JSON_OBJECT('id_motivo', p_id_motivo, 'personal_liberado', v_personal, 'viaticos_liberados', v_viaticos));

    IF v_estado <> 'borrador' THEN
        INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
        SELECT u.id_usuario, 5, CONCAT(v_tipo, ' anulada: ', v_numero),
               LEFT(CONCAT(IFNULL(v_usuario, 'Comercial'), ' anuló la ', v_tipo, ' ', v_numero, ' de ', IFNULL(v_cliente, 'el cliente'),
                           '. Motivo: ', v_motivo, '.', IF(v_estado IN ('programada', 'reprogramada'),
                           ' Se liberó la programación asignada (técnico, fecha y viáticos).', '')), 1000),
               'orden_servicio', p_id_os, NOW(), p_id_usuario
        FROM usuario u
        WHERE u.eliminado_en IS NULL AND u.estado = 'activo' AND u.id_usuario <> p_id_usuario
          AND u.area = 'operaciones' AND u.rol_sistema IN ('supervisor', 'administrador');
    END IF;

    COMMIT;

    SELECT 2 AS IdTipoMensaje, CONCAT(v_tipo, ' ', v_numero, ' anulada.') AS Mensaje;
    SELECT p_id_os AS id_os, v_numero AS numero, 'anulada' AS estado, v_personal AS personal_liberado, v_viaticos AS viaticos_liberados;
END$$

DELIMITER ;
