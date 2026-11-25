-- ============================================================
-- SP_RegistrarFotoInformeComplementario  (Revisión Técnica — foto o video que sube el supervisor al Informe Complementario · escritura)
-- El back ya guardó el archivo (JPEG, PNG o MP4) y llama con su ruta. Acceso: rt_editar, original en el alcance y aún sin revisar.
--   p_momento: antes | durante | despues (por defecto durante) → id_tipo_evidencia 1 | 2 | 3 (igual que las fotos de la app).
--   p_descripcion: hasta 200 caracteres (opcional). p_id_observacion: observación del complementario a la que se vincula (opcional).
--   Hasta 60 fotos y videos por complementario. La foto no lleva id_os ni id_equipo (no aparece en la app móvil).
-- Resultados: 1 mensaje; 2 (id_evidencia, es_video, total_fotos).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_RegistrarFotoInformeComplementario;

DELIMITER $$

CREATE PROCEDURE SP_RegistrarFotoInformeComplementario(
    IN p_id_usuario        BIGINT,
    IN p_id_complementario BIGINT,
    IN p_ruta              VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_es_video          TINYINT,
    IN p_momento           VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_descripcion       VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_observacion    BIGINT
)
proc: BEGIN
    DECLARE v_msg       VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_padre     BIGINT;
    DECLARE v_estado    VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_est_padre VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_editable  TINYINT;
    DECLARE v_tipo      INT;
    DECLARE v_total     INT DEFAULT 0;
    DECLARE v_id        BIGINT;
    DECLARE v_numero    VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF NULLIF(TRIM(IFNULL(p_ruta, '')), '') IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Falta el archivo.' AS Mensaje; LEAVE proc;
    END IF;
    SET v_tipo = CASE LOWER(TRIM(IFNULL(p_momento, ''))) WHEN 'antes' THEN 1 WHEN 'despues' THEN 3 WHEN '' THEN 2 WHEN 'durante' THEN 2 ELSE NULL END;
    IF v_tipo IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Momento no válido: use antes, durante o despues.' AS Mensaje; LEAVE proc;
    END IF;

    CALL SP_ContextoInformeComplementario(p_id_usuario, p_id_complementario, 'rt_editar', v_msg, v_padre, v_estado, v_est_padre, v_editable);
    IF v_msg IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje; LEAVE proc;
    END IF;
    IF v_editable = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El informe ya fue revisado: el informe complementario es inmutable.' AS Mensaje; LEAVE proc;
    END IF;
    IF IFNULL(p_id_observacion, 0) > 0 AND NOT EXISTS (
           SELECT 1 FROM informe_observacion o WHERE o.id_observacion = p_id_observacion AND o.id_informe = p_id_complementario AND o.eliminado_en IS NULL) THEN
        SELECT 1 AS IdTipoMensaje, 'La observación no pertenece a este informe complementario.' AS Mensaje; LEAVE proc;
    END IF;

    START TRANSACTION;
    SELECT numero INTO v_numero FROM informe_tecnico WHERE id_informe = p_id_complementario FOR UPDATE;
    SELECT COUNT(*) INTO v_total FROM evidencia_fotografica WHERE id_informe = p_id_complementario AND eliminado_en IS NULL;
    IF v_total >= 60 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'El informe complementario admite hasta 60 fotos y videos. Quita alguno para agregar otro.' AS Mensaje; LEAVE proc;
    END IF;

    INSERT INTO evidencia_fotografica (id_os, id_equipo, id_informe, id_observacion, id_usuario, id_tipo_evidencia, url_archivo, descripcion,
                                       timestamp_captura, validacion_ia, override_aprobado, codigo, pagina, es_video, vigente,
                                       id_evidencia_origen, creado_por)
    VALUES (NULL, NULL, p_id_complementario, NULLIF(p_id_observacion, 0), p_id_usuario, v_tipo, TRIM(p_ruta), NULLIF(TRIM(p_descripcion), ''),
            UTC_TIMESTAMP(), 'omitida', 0, 'complementario', 1, IF(IFNULL(p_es_video, 0) = 1, 1, 0), 1,
            NULL, p_id_usuario);
    SET v_id = LAST_INSERT_ID();

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('informe_tecnico', v_padre, 'complementario_foto',
            CONCAT(IF(IFNULL(p_es_video, 0) = 1, 'Agregó un video', 'Agregó una foto'), ' al informe complementario ', v_numero),
            p_id_usuario, NOW(), JSON_OBJECT('categoria', 'edicion', 'id_complementario', p_id_complementario, 'id_evidencia', v_id));
    COMMIT;

    SELECT 2 AS IdTipoMensaje, IF(IFNULL(p_es_video, 0) = 1, 'Video agregado.', 'Foto agregada.') AS Mensaje;
    SELECT v_id AS id_evidencia, IF(IFNULL(p_es_video, 0) = 1, 1, 0) AS es_video, v_total + 1 AS total_fotos;
END$$

DELIMITER ;
