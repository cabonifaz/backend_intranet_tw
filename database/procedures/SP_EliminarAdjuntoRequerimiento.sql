-- Observaciones 31/10 (RQ) — Quitar un adjunto del requerimiento (baja lógica; el archivo se conserva).
-- Si el RQ entra al sistema de acreditación, debe quedar al menos un adjunto.
-- Resultados: 1 mensaje.
DROP PROCEDURE IF EXISTS SP_EliminarAdjuntoRequerimiento;

DELIMITER $$

CREATE PROCEDURE SP_EliminarAdjuntoRequerimiento(
    IN p_id_usuario   BIGINT,
    IN p_id_documento BIGINT
)
proc: BEGIN
    DECLARE v_id_rq   BIGINT;
    DECLARE v_estado  VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_acred   TINYINT DEFAULT 0;
    DECLARE v_nombre  VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_total   INT DEFAULT 0;
    DECLARE v_usuario VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    IF FN_PermisoAccion(p_id_usuario, 'rq_guardar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para editar requerimientos.' AS Mensaje; LEAVE proc;
    END IF;

    SELECT d.id_entidad, d.nombre_archivo, r.estado, IFNULL(r.es_inacal, 0)
      INTO v_id_rq, v_nombre, v_estado, v_acred
    FROM documento_adjunto d
    JOIN requerimiento r ON r.id_requerimiento = d.id_entidad
    WHERE d.id_documento = p_id_documento AND d.entidad_tipo = 'requerimiento' AND d.eliminado_en IS NULL;

    IF v_id_rq IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'El adjunto no existe.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_estado IN ('anulado', 'cerrado') THEN
        SELECT 1 AS IdTipoMensaje, 'No se pueden quitar adjuntos de un requerimiento anulado o cerrado.' AS Mensaje; LEAVE proc;
    END IF;

    SELECT COUNT(*) INTO v_total FROM documento_adjunto
    WHERE entidad_tipo = 'requerimiento' AND id_entidad = v_id_rq AND eliminado_en IS NULL;
    IF v_acred = 1 AND v_total <= 1 THEN
        SELECT 1 AS IdTipoMensaje,
               'El requerimiento entra al sistema de acreditación: debe tener al menos un documento adjunto.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT CONCAT(nombre, ' ', apellido) INTO v_usuario FROM usuario WHERE id_usuario = p_id_usuario;

    UPDATE documento_adjunto SET eliminado_en = NOW(), eliminado_por = p_id_usuario
    WHERE id_documento = p_id_documento;

    INSERT INTO historial_requerimiento (id_requerimiento, tipo, tipo_label, icono, descripcion, usuario, fecha, creado_en, creado_por)
    VALUES (v_id_rq, 'adjunto', 'Documento quitado', 'delete', CONCAT('Se quitó el adjunto ', v_nombre, '.'),
            v_usuario, NOW(), NOW(), p_id_usuario);

    SELECT 2 AS IdTipoMensaje, 'Adjunto eliminado.' AS Mensaje;
END$$

DELIMITER ;
