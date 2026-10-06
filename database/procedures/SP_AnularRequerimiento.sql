-- ============================================================
-- SP_AnularRequerimiento
-- Cambia el estado de un requerimiento a 'anulado' y registra
-- el motivo y justificación en el historial.
-- Reglas de permiso:
--   comercial  → solo puede anular si es responsable y
--                estado IN ('nuevo', 'en_proceso')
--   administrador / supervisor → cualquier estado activo (jefe_comercial/admin: tokens anteriores)
-- ============================================================
DROP PROCEDURE IF EXISTS SP_AnularRequerimiento;

DELIMITER //

CREATE PROCEDURE SP_AnularRequerimiento(
    IN p_id_requerimiento BIGINT,
    IN p_id_motivo        INT,
    IN p_justificacion    TEXT,
    IN p_id_usuario       BIGINT,
    IN p_rol              VARCHAR(80)
)
BEGIN
    DECLARE v_numero      VARCHAR(30);
    DECLARE v_responsable VARCHAR(100);
    DECLARE v_motivo_txt  VARCHAR(200);
    DECLARE v_estado_rq   VARCHAR(30);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            @err_msg  = MESSAGE_TEXT,
            @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje,
               CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    -- Validar que existe y no está en estado final
    IF NOT EXISTS (
        SELECT 1 FROM requerimiento
        WHERE id_requerimiento = p_id_requerimiento
          AND SoftDelete = 0
          AND estado NOT IN ('anulado', 'cerrado')
    ) THEN
        SELECT 1 AS IdTipoMensaje,
               'El requerimiento no existe o ya está en estado final (anulado o cerrado).' AS Mensaje;
    ELSE
        -- Obtener estado actual y datos básicos
        SELECT estado INTO v_estado_rq
        FROM requerimiento
        WHERE id_requerimiento = p_id_requerimiento LIMIT 1;

        SELECT numero INTO v_numero
        FROM requerimiento
        WHERE id_requerimiento = p_id_requerimiento LIMIT 1;

        SELECT CONCAT(nombre, ' ', apellido) INTO v_responsable
        FROM usuario WHERE id_usuario = p_id_usuario LIMIT 1;

        IF v_responsable IS NULL THEN
            SELECT 1 AS IdTipoMensaje, 'El usuario ejecutor no existe en el sistema.' AS Mensaje;

        -- Validación RBAC: comercial solo puede anular sus RQs en estado nuevo/en_proceso
        ELSEIF p_rol NOT IN ('administrador', 'supervisor', 'jefe_comercial', 'admin')
               AND (
                   v_estado_rq NOT IN ('nuevo', 'en_proceso')
                   OR NOT EXISTS (
                       SELECT 1 FROM requerimiento
                       WHERE id_requerimiento = p_id_requerimiento
                         AND id_responsable   = p_id_usuario
                         AND SoftDelete = 0
                   )
               )
        THEN
            SELECT 1 AS IdTipoMensaje,
                   'No tienes permiso para anular este requerimiento en su estado actual.' AS Mensaje;

        ELSE
            SELECT String1 INTO v_motivo_txt
            FROM tabla_maestra
            WHERE IdMaestro = 66 AND Descripcion = 'MOTIVO_ANULACION' AND Num1 = p_id_motivo AND IdEmpresa = 1 LIMIT 1;

            -- Anular
            UPDATE requerimiento SET
                estado         = 'anulado',
                modificado_en  = NOW(),
                modificado_por = p_id_usuario
            WHERE id_requerimiento = p_id_requerimiento AND SoftDelete = 0;

            -- Registrar en historial
            INSERT INTO historial_requerimiento (
                id_requerimiento, tipo, tipo_label, icono,
                descripcion, usuario, fecha, creado_en, creado_por
            ) VALUES (
                p_id_requerimiento,
                'anulacion',
                'Requerimiento anulado',
                'cancel',
                CONCAT(
                    'Motivo: ', IFNULL(v_motivo_txt, '—'), '. ',
                    'Justificación: ', p_justificacion
                ),
                v_responsable,
                NOW(), NOW(), p_id_usuario
            );

            SELECT 2 AS IdTipoMensaje, 'Requerimiento anulado exitosamente.' AS Mensaje;
            SELECT p_id_requerimiento AS id_requerimiento;
        END IF;
    END IF;
END //

DELIMITER ;
