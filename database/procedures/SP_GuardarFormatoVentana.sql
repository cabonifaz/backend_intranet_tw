-- Asignar / actualizar el código de formato de una ventana (crea la clave si no existe).
--   Ej.: clave 'requerimiento_ficha', código 'MTW97', versión 10 → se muestra "MTW97-10".
DROP PROCEDURE IF EXISTS SP_GuardarFormatoVentana;

DELIMITER $$

CREATE PROCEDURE SP_GuardarFormatoVentana(
    IN p_clave          VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_nombre_ventana VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_codigo_formato VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_version        INT,
    IN p_id_usuario     BIGINT
)
BEGIN
    DECLARE v_usu VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    IF IFNULL(TRIM(p_clave), '') = '' THEN
        SELECT 1 AS IdTipoMensaje, 'La clave de la ventana es obligatoria.' AS Mensaje;
    ELSEIF NOT EXISTS (SELECT 1 FROM formato_ventana WHERE clave = p_clave) AND IFNULL(TRIM(p_nombre_ventana), '') = '' THEN
        SELECT 1 AS IdTipoMensaje, 'Para una ventana nueva indique su nombre.' AS Mensaje;
    ELSE
        SELECT correo INTO v_usu FROM usuario WHERE id_usuario = p_id_usuario LIMIT 1;

        INSERT INTO formato_ventana (clave, nombre_ventana, codigo_formato, version, UsuMod, FchMod)
        VALUES (TRIM(p_clave),
                COALESCE(NULLIF(TRIM(p_nombre_ventana), ''), (SELECT f.nombre_ventana FROM formato_ventana f WHERE f.clave = p_clave)),
                NULLIF(TRIM(p_codigo_formato), ''), p_version, v_usu, NOW())
        ON DUPLICATE KEY UPDATE
            nombre_ventana = COALESCE(NULLIF(TRIM(p_nombre_ventana), ''), nombre_ventana),
            codigo_formato = NULLIF(TRIM(p_codigo_formato), ''),
            version        = p_version,
            UsuMod         = v_usu,
            FchMod         = NOW();

        SELECT 2 AS IdTipoMensaje, 'Código de formato guardado correctamente.' AS Mensaje;
    END IF;
END$$

DELIMITER ;
