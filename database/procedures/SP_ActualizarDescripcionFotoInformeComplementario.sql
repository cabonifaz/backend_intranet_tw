-- ============================================================
-- SP_ActualizarDescripcionFotoInformeComplementario  (Revisión Técnica — editar la descripción de una foto del Informe Complementario · escritura)
-- OBS #4478 (26/11/2026). Solo las fotos y videos que subió el supervisor (id_evidencia_origen NULL); las copiadas del técnico no se editan.
-- Acceso: rt_editar, original en el alcance y aún sin revisar (SP_ContextoInformeComplementario, igual que la subida).
-- p_descripcion: hasta 200 caracteres; NULL o vacío borra la descripción. Si no cambia, no escribe auditoría.
-- Resultados: 1 mensaje; 2 (id_evidencia, descripcion).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ActualizarDescripcionFotoInformeComplementario;

DELIMITER $$

CREATE PROCEDURE SP_ActualizarDescripcionFotoInformeComplementario(
    IN p_id_usuario        BIGINT,
    IN p_id_complementario BIGINT,
    IN p_id_evidencia      BIGINT,
    IN p_descripcion       VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_msg       VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_padre     BIGINT;
    DECLARE v_estado    VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_est_padre VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_editable  TINYINT;
    DECLARE v_existe    BIGINT       DEFAULT NULL;
    DECLARE v_origen    BIGINT       DEFAULT NULL;
    DECLARE v_video     TINYINT      DEFAULT 0;
    DECLARE v_anterior  VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_nueva     VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_numero    VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SET v_nueva = NULLIF(TRIM(IFNULL(p_descripcion, '')), '');
    IF CHAR_LENGTH(IFNULL(v_nueva, '')) > 200 THEN
        SELECT 1 AS IdTipoMensaje, 'La descripción puede tener hasta 200 caracteres.' AS Mensaje; LEAVE proc;
    END IF;

    CALL SP_ContextoInformeComplementario(p_id_usuario, p_id_complementario, 'rt_editar', v_msg, v_padre, v_estado, v_est_padre, v_editable);
    IF v_msg IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje; LEAVE proc;
    END IF;
    IF v_editable = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El informe ya fue revisado: el informe complementario es inmutable.' AS Mensaje; LEAVE proc;
    END IF;

    START TRANSACTION;
    SELECT numero INTO v_numero FROM informe_tecnico WHERE id_informe = p_id_complementario FOR UPDATE;
    SELECT f.id_evidencia, f.id_evidencia_origen, f.es_video, f.descripcion INTO v_existe, v_origen, v_video, v_anterior
    FROM   evidencia_fotografica f
    WHERE  f.id_evidencia = p_id_evidencia AND f.id_informe = p_id_complementario AND f.eliminado_en IS NULL
    FOR UPDATE;
    IF v_existe IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Foto no encontrada.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_origen IS NOT NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Las fotos del técnico no se pueden editar.' AS Mensaje; LEAVE proc;
    END IF;

    IF NOT (v_anterior <=> v_nueva) THEN
        UPDATE evidencia_fotografica SET descripcion = v_nueva, modificado_por = p_id_usuario WHERE id_evidencia = p_id_evidencia;
        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, descripcion, id_usuario, registrado_en, metadata)
        VALUES ('informe_tecnico', v_padre, 'complementario_foto',
                CONCAT(IF(v_video = 1, 'Editó la descripción de un video', 'Editó la descripción de una foto'), ' del informe complementario ', v_numero),
                p_id_usuario, NOW(), JSON_OBJECT('categoria', 'edicion', 'id_complementario', p_id_complementario, 'id_evidencia', p_id_evidencia));
    END IF;
    COMMIT;

    SELECT 2 AS IdTipoMensaje, IF(v_nueva IS NULL, 'Descripción borrada.', 'Descripción actualizada.') AS Mensaje;
    SELECT p_id_evidencia AS id_evidencia, v_nueva AS descripcion;
END$$

DELIMITER ;
