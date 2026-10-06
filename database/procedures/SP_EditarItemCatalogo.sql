-- Renombra un valor de un catálogo editable (ej. "Nueva área" → "Área de Calidad").
-- Solo cambia la etiqueta (String1): el código (String2) no cambia porque otros
-- registros lo referencian (usuario.area, suministros.tipo, etc.).
DROP PROCEDURE IF EXISTS SP_EditarItemCatalogo;

DELIMITER $$

CREATE PROCEDURE SP_EditarItemCatalogo(
    IN p_descripcion VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_codigo      VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_string1     VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_usuario  BIGINT
)
proc: BEGIN
    DECLARE v_id_maestro INT;

    SELECT MAX(IdMaestro) INTO v_id_maestro
    FROM tabla_maestra WHERE Descripcion = p_descripcion AND IdEmpresa = 1;

    IF v_id_maestro IS NULL THEN
        SELECT 1 AS IdTipoMensaje, CONCAT('Catálogo no encontrado: ', p_descripcion) AS Mensaje;
        LEAVE proc;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM tabla_maestra
                   WHERE IdMaestro = v_id_maestro AND IdEmpresa = 1 AND String2 = p_codigo) THEN
        SELECT 1 AS IdTipoMensaje, 'El valor a editar no existe.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF EXISTS (SELECT 1 FROM tabla_maestra
               WHERE IdMaestro = v_id_maestro AND IdEmpresa = 1
                 AND String1 = p_string1 AND String2 <> p_codigo) THEN
        SELECT 1 AS IdTipoMensaje, CONCAT('Ya existe "', p_string1, '" en el catálogo.') AS Mensaje;
        LEAVE proc;
    END IF;

    UPDATE tabla_maestra
    SET String1 = p_string1
    WHERE IdMaestro = v_id_maestro AND IdEmpresa = 1 AND String2 = p_codigo;

    SELECT 2 AS IdTipoMensaje, CONCAT('"', p_string1, '" actualizado correctamente.') AS Mensaje;
    SELECT Num1 AS id, String1 AS nombre, String2 AS codigo, String3 AS string3
    FROM tabla_maestra WHERE IdMaestro = v_id_maestro AND IdEmpresa = 1 AND String2 = p_codigo;
END$$

DELIMITER ;
