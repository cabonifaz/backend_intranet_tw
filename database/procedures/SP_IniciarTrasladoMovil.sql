-- ============================================================
-- SP_IniciarTrasladoMovil  (App Mobile HU-04)
-- El técnico inicia el traslado hacia el cliente: la OS pasa a 'en_ruta', se registra el
-- evento de campo "Salida desde base" y queda en auditoria_evento.
-- El back valida antes el checklist (ReglasChecklistSalida). Aquí se vuelve a validar lo
-- que podría cambiar en el medio: estado de la OS y, si se usa, el visto bueno vigente.
--   p_con_visto_bueno = 1 → sale con pendientes gracias al visto bueno del jefe.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_IniciarTrasladoMovil;

DELIMITER $$

CREATE PROCEDURE SP_IniciarTrasladoMovil(
    IN p_id_usuario      BIGINT,
    IN p_id_os           BIGINT,
    IN p_con_visto_bueno TINYINT
)
proc: BEGIN
    DECLARE v_estado     VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_aut_estado VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tipo       INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

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
        SELECT 1 AS IdTipoMensaje, CONCAT('No se puede iniciar el traslado: el servicio está ', REPLACE(v_estado, '_', ' '), '.') AS Mensaje;
        LEAVE proc;
    END IF;

    IF p_con_visto_bueno = 1 THEN
        SELECT a.estado INTO v_aut_estado
        FROM   autorizacion_salida_os a
        WHERE  a.id_os = p_id_os AND a.eliminado_en IS NULL
        ORDER BY a.id_autorizacion DESC LIMIT 1;

        IF IFNULL(v_aut_estado, '') <> 'aprobada' THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, 'El visto bueno del encargado del área ya no está vigente.' AS Mensaje;
            LEAVE proc;
        END IF;
    END IF;

    SELECT t.Num1 INTO v_tipo
    FROM   tabla_maestra t
    WHERE  t.Descripcion = 'TIPO_EVENTO_CAMPO' AND t.IdEmpresa = 1 AND t.String2 = 'SALIDA_BASE'
    ORDER BY t.IdMaestro DESC LIMIT 1;

    UPDATE orden_servicio
    SET    estado = 'en_ruta', modificado_por = p_id_usuario
    WHERE  id_os = p_id_os;

    INSERT INTO evento_campo (id_os, id_usuario, id_tipo_evento, timestamp_utc, sincronizado, notas, creado_por)
    VALUES (p_id_os, p_id_usuario, IFNULL(v_tipo, 1), UTC_TIMESTAMP(), 1,
            IF(p_con_visto_bueno = 1, 'Inicio de traslado con visto bueno del encargado del área.', 'Inicio de traslado con checklist completo.'),
            p_id_usuario);

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en)
    VALUES ('orden_servicio', p_id_os, 'iniciar_traslado', v_estado, 'en_ruta',
            IF(p_con_visto_bueno = 1, 'Inicio de traslado con pendientes, autorizado por el encargado del área.',
                                      'Inicio de traslado con el checklist de salida completo.'),
            p_id_usuario, NOW());

    COMMIT;

    SELECT 2 AS IdTipoMensaje, 'Traslado iniciado. ¡Buen viaje!' AS Mensaje;
END$$

DELIMITER ;
