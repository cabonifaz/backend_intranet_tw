-- Crear (p_id_area = 0) o renombrar un área del cliente.
--   Normaliza espacios ("Área   4" → "Área 4") y evita duplicados en la misma empresa
--   (la comparación ignora mayúsculas y tildes: "AREA 4" = "Área 4").
--   Al renombrar, actualiza la ubicación de los equipos del cliente que la usaban.
DROP PROCEDURE IF EXISTS SP_GuardarAreaCliente;

DELIMITER $$

CREATE PROCEDURE SP_GuardarAreaCliente(
    IN p_id_area    BIGINT,
    IN p_id_cliente BIGINT,
    IN p_nombre     VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_usuario BIGINT
)
proc: BEGIN
    DECLARE v_nombre     VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_nombre_ant VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_usu        VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_existente  VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id         BIGINT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SET v_nombre = TRIM(REGEXP_REPLACE(IFNULL(p_nombre, ''), ' +', ' '));

    IF v_nombre = '' THEN
        SELECT 1 AS IdTipoMensaje, 'El nombre del área es obligatorio.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM cliente WHERE id_cliente = p_id_cliente AND SoftDelete = 0) THEN
        SELECT 1 AS IdTipoMensaje, 'Cliente no encontrado.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF p_id_area <> 0 THEN
        SELECT nombre INTO v_nombre_ant FROM area_cliente
        WHERE id_area = p_id_area AND id_cliente = p_id_cliente AND SoftDelete = 0;
        IF v_nombre_ant IS NULL THEN
            SELECT 1 AS IdTipoMensaje, 'Área no encontrada.' AS Mensaje;
            LEAVE proc;
        END IF;
    END IF;

    SELECT nombre INTO v_existente FROM area_cliente
    WHERE id_cliente = p_id_cliente AND nombre = v_nombre
      AND (p_id_area = 0 OR id_area <> p_id_area)
    LIMIT 1;

    IF v_existente IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, CONCAT('El cliente ya tiene el área "', v_existente, '".') AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT correo INTO v_usu FROM usuario WHERE id_usuario = p_id_usuario LIMIT 1;

    START TRANSACTION;
    IF p_id_area = 0 THEN
        INSERT INTO area_cliente (id_cliente, nombre, UsuCre, FchCre) VALUES (p_id_cliente, v_nombre, v_usu, NOW());
        SET v_id = LAST_INSERT_ID();
    ELSE
        UPDATE area_cliente SET nombre = v_nombre, UsuMod = v_usu, FchMod = NOW() WHERE id_area = p_id_area;
        UPDATE equipo_cliente SET ubicacion_especifica = v_nombre
        WHERE id_cliente = p_id_cliente AND ubicacion_especifica = v_nombre_ant;
        SET v_id = p_id_area;
    END IF;
    COMMIT;

    SELECT 2 AS IdTipoMensaje, IF(p_id_area = 0, 'Área registrada correctamente.', 'Área actualizada correctamente.') AS Mensaje;
    SELECT v_id AS id_area, v_nombre AS nombre;
END$$

DELIMITER ;
