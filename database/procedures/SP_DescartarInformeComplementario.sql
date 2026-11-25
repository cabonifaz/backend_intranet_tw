-- ============================================================
-- SP_DescartarInformeComplementario  (Revisión Técnica — descartar un Informe Complementario sin guardar · escritura)
-- Acceso: rt_editar, original en el alcance y aún sin revisar. Solo un complementario en 'borrador' (nunca guardado) y sin precotización:
-- uno guardado ya forma parte del informe y no se descarta. Queda eliminado (soft delete) con sus observaciones, recomendaciones y fotos.
-- Después se puede volver a generar otro.
-- Resultados: 1 mensaje; 2 rutas de archivos que subió el supervisor y ya nadie usa (el back los borra): (ruta, ruta_cuadro).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_DescartarInformeComplementario;

DELIMITER $$

CREATE PROCEDURE SP_DescartarInformeComplementario(
    IN p_id_usuario        BIGINT,
    IN p_id_complementario BIGINT
)
proc: BEGIN
    DECLARE v_msg       VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_padre     BIGINT;
    DECLARE v_estado    VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_est_padre VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_editable  TINYINT;
    DECLARE v_numero    VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_cm_archivos;
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
    SELECT estado INTO v_est_padre FROM informe_tecnico WHERE id_informe = v_padre FOR UPDATE;
    SET v_estado = NULL;
    SELECT estado, numero INTO v_estado, v_numero FROM informe_tecnico
    WHERE id_informe = p_id_complementario AND eliminado_en IS NULL FOR UPDATE;
    IF v_estado IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'El informe complementario ya no existe.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_estado <> 'borrador' THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'El informe complementario ya fue guardado: no se puede descartar.' AS Mensaje; LEAVE proc;
    END IF;
    IF EXISTS (SELECT 1 FROM precotizacion WHERE id_informe = p_id_complementario AND eliminado_en IS NULL) THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'El informe complementario tiene una precotización: no se puede descartar.' AS Mensaje; LEAVE proc;
    END IF;

    -- Archivos que subió el supervisor y que ninguna otra fila usa (se devuelven para borrarlos)
    DROP TEMPORARY TABLE IF EXISTS tmp_cm_archivos;
    CREATE TEMPORARY TABLE tmp_cm_archivos AS
    SELECT f.url_archivo AS ruta, f.ruta_cuadro
    FROM evidencia_fotografica f
    WHERE f.id_informe = p_id_complementario AND f.id_evidencia_origen IS NULL AND f.eliminado_en IS NULL
      AND NOT EXISTS (SELECT 1 FROM evidencia_fotografica g
                      WHERE g.url_archivo = f.url_archivo AND g.id_evidencia <> f.id_evidencia AND g.eliminado_en IS NULL);

    UPDATE evidencia_fotografica  SET eliminado_en = NOW(), eliminado_por = p_id_usuario WHERE id_informe = p_id_complementario AND eliminado_en IS NULL;
    UPDATE informe_recomendacion  SET eliminado_en = NOW(), eliminado_por = p_id_usuario WHERE id_informe = p_id_complementario AND eliminado_en IS NULL;
    UPDATE informe_observacion    SET eliminado_en = NOW(), eliminado_por = p_id_usuario WHERE id_informe = p_id_complementario AND eliminado_en IS NULL;
    UPDATE informe_tecnico        SET eliminado_en = NOW(), eliminado_por = p_id_usuario WHERE id_informe = p_id_complementario;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('informe_tecnico', v_padre, 'complementario_descartado', CONCAT('Descartó el informe complementario ', v_numero, ' sin guardarlo'),
            p_id_usuario, NOW(), JSON_OBJECT('categoria', 'edicion', 'id_complementario', p_id_complementario));
    COMMIT;

    SELECT 2 AS IdTipoMensaje, 'Informe complementario descartado.' AS Mensaje;
    SELECT ruta, ruta_cuadro FROM tmp_cm_archivos;
    DROP TEMPORARY TABLE IF EXISTS tmp_cm_archivos;
END$$

DELIMITER ;
