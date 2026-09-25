-- ============================================================
-- SP_GuardarRequerimiento
-- Crea o actualiza un requerimiento.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_GuardarRequerimiento;

DELIMITER //

CREATE PROCEDURE SP_GuardarRequerimiento(
    IN p_id_requerimiento BIGINT,
    IN p_id_cliente       BIGINT,
    IN p_id_sede          BIGINT,
    IN p_id_contacto      BIGINT,
    IN p_id_origen        INT,
    IN p_id_area          INT,
    IN p_id_prioridad     INT,
    IN p_fecha_necesidad  DATE,
    IN p_descripcion      TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci,
    IN p_notificar_correo TINYINT,
    IN p_requiere_visita  TINYINT,
    IN p_cliente_deuda    TINYINT,
    IN p_id_usuario       BIGINT
)
BEGIN
    DECLARE v_new_id BIGINT;

    IF p_id_requerimiento = 0 THEN
        INSERT INTO requerimiento (
            numero,
            id_cliente, id_sede, id_contacto,
            id_origen, id_area, id_prioridad,
            descripcion, fecha_necesidad,
            notificar_correo, requiere_visita, cliente_deuda,
            estado, id_usuario_creador,
            fecha_creacion, creado_en, creado_por
        ) VALUES (
            'RQ-TEMP',
            p_id_cliente, p_id_sede, p_id_contacto,
            p_id_origen, p_id_area, p_id_prioridad,
            p_descripcion, p_fecha_necesidad,
            p_notificar_correo, p_requiere_visita, p_cliente_deuda,
            'nuevo', p_id_usuario,
            NOW(), NOW(), p_id_usuario
        );

        SET v_new_id = LAST_INSERT_ID();

        UPDATE requerimiento
        SET numero = CONCAT('RQ-', YEAR(NOW()), '-', LPAD(v_new_id, 4, '0'))
        WHERE id_requerimiento = v_new_id;

        SELECT 2 AS IdTipoMensaje, 'Requerimiento creado exitosamente.' AS Mensaje;
        SELECT v_new_id AS id_requerimiento;

    ELSE
        UPDATE requerimiento SET
            id_cliente       = p_id_cliente,
            id_sede          = p_id_sede,
            id_contacto      = p_id_contacto,
            id_origen        = p_id_origen,
            id_area          = p_id_area,
            id_prioridad     = p_id_prioridad,
            descripcion      = p_descripcion,
            fecha_necesidad  = p_fecha_necesidad,
            notificar_correo = p_notificar_correo,
            requiere_visita  = p_requiere_visita,
            cliente_deuda    = p_cliente_deuda,
            modificado_en    = NOW(),
            modificado_por   = p_id_usuario
        WHERE id_requerimiento = p_id_requerimiento
          AND SoftDelete = 0;

        SELECT 2 AS IdTipoMensaje, 'Requerimiento actualizado exitosamente.' AS Mensaje;
        SELECT p_id_requerimiento AS id_requerimiento;
    END IF;
END //

DELIMITER ;
