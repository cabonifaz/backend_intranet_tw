-- ============================================================
-- SP_GuardarCategoria
-- Inserta o actualiza una categoría de cliente.
-- p_id_categoria = 0 → INSERT; caso contrario → UPDATE.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_GuardarCategoria;

DELIMITER //

CREATE PROCEDURE SP_GuardarCategoria(
    IN p_id_categoria       INT,
    IN p_nombre             VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_descripcion        VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_prioridad_atencion INT,
    IN p_pct_ganancia_min   DECIMAL(5,2),
    IN p_pct_ganancia_max   DECIMAL(5,2),
    IN p_usu_cre            VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
BEGIN
    IF EXISTS (
        SELECT 1 FROM categoria_cliente
        WHERE nombre = p_nombre
          AND SoftDelete = 0
          AND (p_id_categoria = 0 OR id_categoria <> p_id_categoria)
    ) THEN
        SELECT 1 AS IdTipoMensaje, 'Ya existe una categoría con ese nombre.' AS Mensaje;
    ELSEIF p_id_categoria = 0 THEN
        INSERT INTO categoria_cliente (
            nombre, descripcion, prioridad_atencion,
            pct_ganancia_min, pct_ganancia_max,
            estado, SoftDelete, UsuCre, FchCre
        ) VALUES (
            p_nombre, p_descripcion, p_prioridad_atencion,
            p_pct_ganancia_min, p_pct_ganancia_max,
            'Activo', 0, p_usu_cre, NOW()
        );

        SELECT 2 AS IdTipoMensaje, 'Categoría registrada correctamente.' AS Mensaje;
        SELECT LAST_INSERT_ID() AS id_categoria;
    ELSE
        UPDATE categoria_cliente SET
            nombre              = p_nombre,
            descripcion         = p_descripcion,
            prioridad_atencion  = p_prioridad_atencion,
            pct_ganancia_min    = p_pct_ganancia_min,
            pct_ganancia_max    = p_pct_ganancia_max,
            UsuMod              = p_usu_cre,
            FchMod              = NOW()
        WHERE id_categoria = p_id_categoria AND SoftDelete = 0;

        SELECT 2 AS IdTipoMensaje, 'Categoría actualizada correctamente.' AS Mensaje;
        SELECT p_id_categoria AS id_categoria;
    END IF;
END //

DELIMITER ;
