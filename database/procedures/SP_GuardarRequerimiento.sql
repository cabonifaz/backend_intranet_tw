-- Crear / editar requerimiento. Número: RQ-0003-2026 (correlativo-año).
DROP PROCEDURE IF EXISTS SP_GuardarRequerimiento;
DELIMITER $$
CREATE PROCEDURE SP_GuardarRequerimiento(
    IN p_id_requerimiento BIGINT,
    IN p_id_cliente       BIGINT,
    IN p_id_sede          BIGINT,
    IN p_id_contacto      BIGINT,
    IN p_id_origen        INT,
    IN p_id_area          INT,
    IN p_id_prioridad     INT,
    IN p_fecha_necesidad  DATE,
    IN p_descripcion      TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_notificar_correo TINYINT,
    IN p_requiere_visita  TINYINT,
    IN p_cliente_deuda    TINYINT,
    IN p_id_usuario       BIGINT
)
BEGIN
    DECLARE v_new_id       BIGINT;
    DECLARE v_numero       VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_responsable  VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cambios      TEXT         CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT '';

    DECLARE v_old_desc     TEXT         CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_old_prio     INT;
    DECLARE v_old_fecha    DATE;
    DECLARE v_old_origen   INT;
    DECLARE v_old_area     INT;
    DECLARE v_old_contacto BIGINT;
    DECLARE v_old_sede     BIGINT;
    DECLARE v_estado_actual VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            @err_msg  = MESSAGE_TEXT,
            @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje,
               CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SELECT CONCAT(nombre, ' ', apellido) INTO v_responsable
    FROM usuario WHERE id_usuario = p_id_usuario LIMIT 1;

    IF v_responsable IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'El usuario ejecutor no existe en el sistema.' AS Mensaje;
    ELSEIF p_id_requerimiento = 0 THEN
        INSERT INTO requerimiento (
            numero,
            id_cliente, id_sede, id_contacto,
            id_origen, id_area, id_prioridad,
            descripcion, fecha_necesidad,
            notificar_correo, requiere_visita, cliente_deuda,
            estado, id_usuario_creador, id_responsable,
            fecha_creacion, creado_en, creado_por
        ) VALUES (
            'RQ-TEMP',
            p_id_cliente, p_id_sede, p_id_contacto,
            p_id_origen, p_id_area, p_id_prioridad,
            p_descripcion, p_fecha_necesidad,
            p_notificar_correo, p_requiere_visita, p_cliente_deuda,
            'nuevo', p_id_usuario, p_id_usuario,
            NOW(), NOW(), p_id_usuario
        );

        SET v_new_id = LAST_INSERT_ID();
        SET v_numero = CONCAT('RQ-', LPAD(v_new_id, 4, '0'), '-', YEAR(NOW()));

        UPDATE requerimiento SET numero = v_numero
        WHERE id_requerimiento = v_new_id;

        INSERT INTO historial_requerimiento (
            id_requerimiento, tipo, tipo_label, icono,
            descripcion, usuario, fecha, creado_en, creado_por
        ) VALUES (
            v_new_id, 'creacion', 'Requerimiento creado', 'add_circle',
            CONCAT('Requerimiento ', v_numero, ' registrado. Estado inicial: Nueva.'),
            v_responsable, NOW(), NOW(), p_id_usuario
        );

        SELECT 2 AS IdTipoMensaje, 'Requerimiento creado exitosamente.' AS Mensaje;
        SELECT v_new_id AS id_requerimiento;

    ELSE
        SELECT estado INTO v_estado_actual
        FROM   requerimiento
        WHERE  id_requerimiento = p_id_requerimiento AND SoftDelete = 0
        LIMIT  1;

        IF v_estado_actual IS NULL THEN
            SELECT 1 AS IdTipoMensaje, 'El requerimiento no existe o fue eliminado.' AS Mensaje;
        ELSEIF v_estado_actual IN ('anulado', 'cerrado') THEN
            SELECT 1 AS IdTipoMensaje, 'No se puede editar un requerimiento anulado o cerrado.' AS Mensaje;
        ELSE
        SELECT descripcion, id_prioridad, fecha_necesidad, id_origen, id_area, id_contacto, id_sede
        INTO   v_old_desc, v_old_prio, v_old_fecha, v_old_origen, v_old_area, v_old_contacto, v_old_sede
        FROM   requerimiento
        WHERE  id_requerimiento = p_id_requerimiento AND SoftDelete = 0;

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
        WHERE id_requerimiento = p_id_requerimiento AND SoftDelete = 0;

        IF v_old_prio != p_id_prioridad THEN
            SET v_cambios = CONCAT(v_cambios, 'Prioridad: ',
                IFNULL((SELECT String1 FROM tabla_maestra WHERE IdMaestro = 65 AND Num1 = v_old_prio    AND IdEmpresa = 1 LIMIT 1), '—'),
                ' → ',
                IFNULL((SELECT String1 FROM tabla_maestra WHERE IdMaestro = 65 AND Num1 = p_id_prioridad AND IdEmpresa = 1 LIMIT 1), '—'),
                '. ');
        END IF;

        IF v_old_origen != p_id_origen THEN
            SET v_cambios = CONCAT(v_cambios, 'Origen: ',
                IFNULL((SELECT String1 FROM tabla_maestra WHERE IdMaestro = 63 AND Num1 = v_old_origen AND IdEmpresa = 1 LIMIT 1), '—'),
                ' → ',
                IFNULL((SELECT String1 FROM tabla_maestra WHERE IdMaestro = 63 AND Num1 = p_id_origen  AND IdEmpresa = 1 LIMIT 1), '—'),
                '. ');
        END IF;

        IF v_old_area != p_id_area THEN
            SET v_cambios = CONCAT(v_cambios, 'Área: ',
                IFNULL((SELECT String1 FROM tabla_maestra WHERE IdMaestro = 64 AND Num1 = v_old_area AND IdEmpresa = 1 LIMIT 1), '—'),
                ' → ',
                IFNULL((SELECT String1 FROM tabla_maestra WHERE IdMaestro = 64 AND Num1 = p_id_area  AND IdEmpresa = 1 LIMIT 1), '—'),
                '. ');
        END IF;

        IF (v_old_fecha IS NULL AND p_fecha_necesidad IS NOT NULL)
           OR (v_old_fecha IS NOT NULL AND p_fecha_necesidad IS NULL)
           OR (v_old_fecha IS NOT NULL AND p_fecha_necesidad IS NOT NULL AND v_old_fecha != p_fecha_necesidad) THEN
            SET v_cambios = CONCAT(v_cambios, 'Fecha requerida: ',
                IFNULL(DATE_FORMAT(v_old_fecha, '%d/%m/%Y'), 'Sin fecha'), ' → ',
                IFNULL(DATE_FORMAT(p_fecha_necesidad, '%d/%m/%Y'), 'Sin fecha'), '. ');
        END IF;

        IF v_old_desc != p_descripcion THEN
            SET v_cambios = CONCAT(v_cambios, 'Descripción actualizada. ');
        END IF;

        IF (v_old_sede IS NULL AND p_id_sede IS NOT NULL)
           OR (v_old_sede IS NOT NULL AND p_id_sede IS NULL)
           OR (v_old_sede IS NOT NULL AND p_id_sede IS NOT NULL AND v_old_sede != p_id_sede) THEN
            SET v_cambios = CONCAT(v_cambios, 'Sede modificada. ');
        END IF;

        IF (v_old_contacto IS NULL AND p_id_contacto IS NOT NULL)
           OR (v_old_contacto IS NOT NULL AND p_id_contacto IS NULL)
           OR (v_old_contacto IS NOT NULL AND p_id_contacto IS NOT NULL AND v_old_contacto != p_id_contacto) THEN
            SET v_cambios = CONCAT(v_cambios, 'Contacto modificado. ');
        END IF;

        IF v_cambios = '' THEN
            SET v_cambios = 'Sin cambios detectados.';
        END IF;

        INSERT INTO historial_requerimiento (
            id_requerimiento, tipo, tipo_label, icono,
            descripcion, usuario, fecha, creado_en, creado_por
        ) VALUES (
            p_id_requerimiento, 'edicion', 'Requerimiento editado', 'edit',
            v_cambios,
            v_responsable, NOW(), NOW(), p_id_usuario
        );

        SELECT 2 AS IdTipoMensaje, 'Requerimiento actualizado exitosamente.' AS Mensaje;
        SELECT p_id_requerimiento AS id_requerimiento;
        END IF;
    END IF;
END$$
DELIMITER ;
