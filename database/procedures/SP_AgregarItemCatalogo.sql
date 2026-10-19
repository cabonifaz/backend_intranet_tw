-- HU-86 — Agrega un valor a un catálogo existente de tabla_maestra
--   (modales "Nuevo Tipo / Subtipo / Marca / Modelo" de Suministros).
--   Num1 = siguiente correlativo del catálogo. Valida duplicados.
DROP PROCEDURE IF EXISTS SP_AgregarItemCatalogo;

DELIMITER $$

CREATE PROCEDURE SP_AgregarItemCatalogo(
    IN p_descripcion VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_string1     VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_string2     VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_string3     VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_usuario  BIGINT
)
proc: BEGIN
    DECLARE v_id_maestro INT;
    DECLARE v_num1       INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1
            @err_msg  = MESSAGE_TEXT,
            @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje,
               CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SELECT MAX(IdMaestro) INTO v_id_maestro
    FROM tabla_maestra
    WHERE Descripcion = p_descripcion AND IdEmpresa = 1;

    IF v_id_maestro IS NULL THEN
        SELECT 1 AS IdTipoMensaje, CONCAT('Catálogo no encontrado: ', p_descripcion) AS Mensaje;
        LEAVE proc;
    END IF;

    -- TIPO_SUMINISTRO: String3 = clase a la que pertenece el tipo (obligatoria)
    IF p_descripcion = 'TIPO_SUMINISTRO' AND NOT EXISTS (
        SELECT 1 FROM tabla_maestra WHERE IdMaestro = 71 AND IdEmpresa = 1 AND String2 = p_string3
    ) THEN
        SELECT 1 AS IdTipoMensaje, 'Indique la clase (servicio, equipo, instrumento o pesa) del nuevo tipo.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF EXISTS (
        SELECT 1 FROM tabla_maestra
        WHERE IdMaestro = v_id_maestro AND IdEmpresa = 1 AND eliminado_en IS NULL
          AND (String1 = p_string1 OR String2 = p_string2)
    ) THEN
        SELECT 1 AS IdTipoMensaje, CONCAT('Ya existe "', p_string1, '" en el catálogo.') AS Mensaje;
        LEAVE proc;
    END IF;

    START TRANSACTION;

    SELECT IFNULL(MAX(Num1), 0) + 1 INTO v_num1
    FROM tabla_maestra
    WHERE IdMaestro = v_id_maestro AND IdEmpresa = 1
    FOR UPDATE;

    INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2, String3, creado_en, creado_por)
    VALUES (1, v_id_maestro, p_descripcion, v_num1, p_string1, p_string2, NULLIF(p_string3, ''), NOW(), p_id_usuario);

    COMMIT;

    SELECT 2 AS IdTipoMensaje, CONCAT('"', p_string1, '" agregado correctamente.') AS Mensaje;
    SELECT v_num1 AS id, p_string1 AS nombre, p_string2 AS codigo, NULLIF(p_string3, '') AS string3;
END$$

DELIMITER ;
