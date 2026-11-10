-- ============================================================
-- SP_EliminarGuardadoAsistenteMovil  (App Mobile HU-19 — quitar un guardado · escritura)
-- Eliminación lógica (eliminado_en / eliminado_por) de un guardado del propio técnico; queda en la bitácora de auditoría (auditoria_evento).
-- Repetir la petición sobre un guardado ya eliminado responde éxito sin duplicar nada.
-- Resultados: 1 mensaje.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_EliminarGuardadoAsistenteMovil;

DELIMITER $$

CREATE PROCEDURE SP_EliminarGuardadoAsistenteMovil(
    IN p_id_usuario  BIGINT,
    IN p_id_guardado BIGINT
)
proc: BEGIN
    DECLARE v_id       BIGINT DEFAULT NULL;
    DECLARE v_eliminado DATETIME DEFAULT NULL;
    DECLARE v_titulo   VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_tipo     VARCHAR(12)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_consulta BIGINT DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_guardado, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Guardado no encontrado.' AS Mensaje; LEAVE proc;
    END IF;

    START TRANSACTION;
    SELECT g.id_guardado, g.eliminado_en, g.titulo, g.tipo, g.id_consulta INTO v_id, v_eliminado, v_titulo, v_tipo, v_consulta
    FROM   asistente_guardado g
    WHERE  g.id_guardado = p_id_guardado AND g.id_usuario = p_id_usuario
    FOR UPDATE;
    IF v_id IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Guardado no encontrado.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_eliminado IS NOT NULL THEN
        COMMIT;
        SELECT 2 AS IdTipoMensaje, 'El guardado ya estaba eliminado.' AS Mensaje; LEAVE proc;
    END IF;

    UPDATE asistente_guardado SET eliminado_en = UTC_TIMESTAMP(), eliminado_por = p_id_usuario WHERE id_guardado = p_id_guardado;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('asistente_guardado', p_id_guardado, 'eliminar_guardado', 'guardado', 'eliminado',
            LEFT(CONCAT('Guardado del Asistente IA eliminado: ', v_titulo), 900), p_id_usuario, NOW(),
            JSON_OBJECT('id_guardado', p_id_guardado, 'id_consulta', v_consulta, 'tipo', v_tipo));
    COMMIT;

    SELECT 2 AS IdTipoMensaje, 'Guardado eliminado.' AS Mensaje;
END$$

DELIMITER ;
