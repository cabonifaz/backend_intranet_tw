-- ============================================================
-- SP_QuitarFotoInformeComplementario  (Revisión Técnica — quitar una foto o video del Informe Complementario · escritura)
-- Acceso: rt_editar, original en el alcance y aún sin revisar. Sirve para las copiadas del original y para las que subió el supervisor.
-- La fila queda eliminada (soft delete) y las observaciones que la usaban quedan sin foto.
-- ruta_borrable: ruta del archivo SOLO si lo subió el supervisor y ninguna otra fila lo usa (el back lo borra); las copiadas comparten el
-- archivo con el informe del técnico y nunca se borran.
-- Resultados: 1 mensaje; 2 (id_evidencia, ruta_borrable, ruta_cuadro_borrable).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_QuitarFotoInformeComplementario;

DELIMITER $$

CREATE PROCEDURE SP_QuitarFotoInformeComplementario(
    IN p_id_usuario        BIGINT,
    IN p_id_complementario BIGINT,
    IN p_id_evidencia      BIGINT
)
proc: BEGIN
    DECLARE v_msg       VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_padre     BIGINT;
    DECLARE v_estado    VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_est_padre VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_editable  TINYINT;
    DECLARE v_ruta      VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_cuadro    VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_origen    BIGINT;
    DECLARE v_video     TINYINT DEFAULT 0;
    DECLARE v_numero    VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_borrar    TINYINT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    CALL SP_ContextoInformeComplementario(p_id_usuario, p_id_complementario, 'rt_editar', v_msg, v_padre, v_estado, v_est_padre, v_editable);
    IF v_msg IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje; LEAVE proc;
    END IF;
    IF v_editable = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El informe ya fue revisado: el informe complementario es inmutable.' AS Mensaje; LEAVE proc;
    END IF;

    START TRANSACTION;
    SELECT numero INTO v_numero FROM informe_tecnico WHERE id_informe = p_id_complementario FOR UPDATE;
    SELECT f.url_archivo, f.ruta_cuadro, f.id_evidencia_origen, f.es_video INTO v_ruta, v_cuadro, v_origen, v_video
    FROM evidencia_fotografica f
    WHERE f.id_evidencia = p_id_evidencia AND f.id_informe = p_id_complementario AND f.eliminado_en IS NULL
    FOR UPDATE;
    IF v_ruta IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Foto no encontrada.' AS Mensaje; LEAVE proc;
    END IF;

    UPDATE informe_observacion SET id_evidencia = NULL, modificado_por = p_id_usuario
    WHERE id_informe = p_id_complementario AND id_evidencia = p_id_evidencia AND eliminado_en IS NULL;
    UPDATE evidencia_fotografica SET eliminado_en = NOW(), eliminado_por = p_id_usuario WHERE id_evidencia = p_id_evidencia;

    -- El archivo se borra solo si lo subió el supervisor y ninguna otra fila lo usa
    SET v_borrar = IF(v_origen IS NULL AND NOT EXISTS (SELECT 1 FROM evidencia_fotografica f
                                                       WHERE f.url_archivo = v_ruta AND f.id_evidencia <> p_id_evidencia AND f.eliminado_en IS NULL), 1, 0);

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('informe_tecnico', v_padre, 'complementario_foto',
            CONCAT(IF(v_video = 1, 'Quitó un video', 'Quitó una foto'), IF(v_origen IS NULL, '', ' del técnico'), ' del informe complementario ', v_numero),
            p_id_usuario, NOW(), JSON_OBJECT('categoria', 'edicion', 'id_complementario', p_id_complementario, 'id_evidencia', p_id_evidencia));
    COMMIT;

    SELECT 2 AS IdTipoMensaje, IF(v_video = 1, 'Video quitado.', 'Foto quitada.') AS Mensaje;
    SELECT p_id_evidencia AS id_evidencia, IF(v_borrar = 1, v_ruta, NULL) AS ruta_borrable, IF(v_borrar = 1, v_cuadro, NULL) AS ruta_cuadro_borrable;
END$$

DELIMITER ;
