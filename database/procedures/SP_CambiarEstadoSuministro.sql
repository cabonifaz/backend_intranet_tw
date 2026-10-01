-- HU-86 — Activar / desactivar un suministro (no se elimina) + auditoría
DROP PROCEDURE IF EXISTS SP_CambiarEstadoSuministro;

DELIMITER $$

CREATE PROCEDURE SP_CambiarEstadoSuministro(
    IN p_id_suministro BIGINT,
    IN p_estado        VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_usuario    BIGINT
)
BEGIN
    DECLARE v_estado      VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado_ant  VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_codigo      VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_descripcion VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    SET v_estado = LOWER(TRIM(p_estado));

    SELECT estado, codigo, descripcion INTO v_estado_ant, v_codigo, v_descripcion
    FROM catalogo_item WHERE id_catalogo_item = p_id_suministro AND eliminado_en IS NULL LIMIT 1;

    IF v_estado NOT IN ('activo', 'inactivo') THEN
        SELECT 1 AS IdTipoMensaje, 'Estado no válido. Use Activo o Inactivo.' AS Mensaje;
    ELSEIF v_estado_ant IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Suministro no encontrado.' AS Mensaje;
    ELSEIF v_estado = 'activo' AND EXISTS (
        SELECT 1 FROM catalogo_item
        WHERE descripcion = v_descripcion AND estado = 'activo'
          AND eliminado_en IS NULL AND id_catalogo_item <> p_id_suministro
    ) THEN
        SELECT 1 AS IdTipoMensaje, 'No se puede activar: ya existe otro suministro activo con la misma descripción.' AS Mensaje;
    ELSE
        UPDATE catalogo_item SET
            estado         = v_estado,
            activo         = IF(v_estado = 'activo', 1, 0),
            modificado_en  = NOW(),
            modificado_por = p_id_usuario
        WHERE id_catalogo_item = p_id_suministro;

        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en)
        VALUES ('suministro', p_id_suministro, 'cambio_estado', v_estado_ant, v_estado,
                CONCAT('Suministro ', v_codigo, ': ', v_estado_ant, ' → ', v_estado, '.'), p_id_usuario, NOW());

        SELECT 2 AS IdTipoMensaje, 'Estado actualizado correctamente.' AS Mensaje;
    END IF;
END$$

DELIMITER ;
