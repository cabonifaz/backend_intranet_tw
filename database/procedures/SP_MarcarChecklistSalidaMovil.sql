-- ============================================================
-- SP_MarcarChecklistSalidaMovil  (App Mobile HU-04)
-- El técnico confirma (o desmarca) un ítem manual del checklist de pre-salida.
--   p_codigo: expediente | epp | materiales | herramientas | pesas_patron  (lista blanca)
-- Solo mientras la OS siga programada/reprogramada. Deja registro en auditoria_evento.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_MarcarChecklistSalidaMovil;

DELIMITER $$

CREATE PROCEDURE SP_MarcarChecklistSalidaMovil(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT,
    IN p_codigo     VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_confirmado TINYINT
)
proc: BEGIN
    DECLARE v_estado   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id       BIGINT;
    DECLARE v_anterior TINYINT DEFAULT 0;
    DECLARE v_nombre   VARCHAR(60) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SET v_nombre = CASE p_codigo
                       WHEN 'expediente'   THEN 'Expediente revisado'
                       WHEN 'epp'          THEN 'EPP revisado'
                       WHEN 'materiales'   THEN 'Materiales e insumos'
                       WHEN 'herramientas' THEN 'Herramientas listas'
                       WHEN 'pesas_patron' THEN 'Pesas patrón asignadas'
                   END;

    IF v_nombre IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Ítem del checklist no válido.' AS Mensaje;
        LEAVE proc;
    END IF;

    START TRANSACTION;

    SELECT os.estado INTO v_estado
    FROM   orden_servicio os
    WHERE  os.id_os = p_id_os AND os.eliminado_en IS NULL
      AND  (os.id_tecnico_principal = p_id_usuario
            OR EXISTS (SELECT 1 FROM os_personal op
                       WHERE op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL))
    FOR UPDATE;

    IF v_estado IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Servicio no encontrado o no asignado a tu usuario.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF v_estado NOT IN ('programada', 'reprogramada') THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'El traslado ya se inició: el checklist ya no se puede cambiar.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT c.id_checklist, c.confirmado INTO v_id, v_anterior
    FROM   checklist_presalida_os c
    WHERE  c.id_os = p_id_os AND c.codigo = p_codigo AND c.eliminado_en IS NULL
    ORDER BY c.id_checklist DESC LIMIT 1;

    IF v_id IS NULL THEN
        INSERT INTO checklist_presalida_os (id_os, codigo, confirmado, confirmado_por, confirmado_en, creado_por)
        VALUES (p_id_os, p_codigo, IF(p_confirmado = 1, 1, 0),
                IF(p_confirmado = 1, p_id_usuario, NULL), IF(p_confirmado = 1, NOW(), NULL), p_id_usuario);
    ELSE
        UPDATE checklist_presalida_os
        SET    confirmado     = IF(p_confirmado = 1, 1, 0),
               confirmado_por = IF(p_confirmado = 1, p_id_usuario, NULL),
               confirmado_en  = IF(p_confirmado = 1, NOW(), NULL),
               modificado_por = p_id_usuario
        WHERE  id_checklist = v_id;
    END IF;

    IF IFNULL(v_anterior, 0) <> IF(p_confirmado = 1, 1, 0) THEN
        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en)
        VALUES ('orden_servicio', p_id_os, 'checklist_salida',
                IF(IFNULL(v_anterior, 0) = 1, 'conforme', 'pendiente'),
                IF(p_confirmado = 1, 'conforme', 'pendiente'),
                CONCAT(v_nombre, IF(p_confirmado = 1, ': confirmado por el técnico.', ': desmarcado por el técnico.')),
                p_id_usuario, NOW());
    END IF;

    COMMIT;

    SELECT 2 AS IdTipoMensaje, CONCAT(v_nombre, IF(p_confirmado = 1, ' confirmado.', ' desmarcado.')) AS Mensaje;
END$$

DELIMITER ;
