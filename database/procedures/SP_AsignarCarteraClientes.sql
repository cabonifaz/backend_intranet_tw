-- Observaciones 31/10 (#4) — Asignar (o quitar) clientes de la cartera de un comercial. Solo el Administrador
-- (acción cartera_asignar). p_id_comercial NULL o 0 = quitar la asignación. p_ids_clientes = JSON [id_cliente, ...].
-- El comercial debe ser un usuario activo del área comercial. Registra auditoría por cliente y avisa al comercial.
-- Resultados: 1 mensaje, 2 clientes actualizados.
DROP PROCEDURE IF EXISTS SP_AsignarCarteraClientes;

DELIMITER $$

CREATE PROCEDURE SP_AsignarCarteraClientes(
    IN p_id_usuario    BIGINT,
    IN p_id_comercial  BIGINT,
    IN p_ids_clientes  JSON
)
proc: BEGIN
    DECLARE v_comercial VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_usuario   VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_n         INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_cartera_asig;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF FN_PermisoAccion(p_id_usuario, 'cartera_asignar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Solo el Administrador puede asignar la cartera de clientes.' AS Mensaje; LEAVE proc;
    END IF;

    SET p_id_comercial = NULLIF(p_id_comercial, 0);
    IF p_id_comercial IS NOT NULL THEN
        SELECT CONCAT(nombre, ' ', apellido) INTO v_comercial
        FROM usuario WHERE id_usuario = p_id_comercial AND eliminado_en IS NULL AND estado = 'activo' AND area = 'comercial';
        IF v_comercial IS NULL THEN
            SELECT 1 AS IdTipoMensaje, 'El comercial no existe, no está activo o no es del área comercial.' AS Mensaje; LEAVE proc;
        END IF;
    END IF;

    IF p_ids_clientes IS NULL OR JSON_TYPE(p_ids_clientes) <> 'ARRAY' OR JSON_LENGTH(p_ids_clientes) = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Seleccione al menos un cliente.' AS Mensaje; LEAVE proc;
    END IF;

    DROP TEMPORARY TABLE IF EXISTS tmp_cartera_asig;
    CREATE TEMPORARY TABLE tmp_cartera_asig (id_cliente BIGINT PRIMARY KEY, id_anterior BIGINT);
    INSERT IGNORE INTO tmp_cartera_asig
    SELECT c.id_cliente, c.id_comercial_cartera
    FROM JSON_TABLE(p_ids_clientes, '$[*]' COLUMNS (id BIGINT PATH '$')) j
    JOIN cliente c ON c.id_cliente = j.id AND c.SoftDelete = 0 AND c.eliminado_en IS NULL;

    SELECT COUNT(*) INTO v_n FROM tmp_cartera_asig;
    IF v_n = 0 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_cartera_asig;
        SELECT 1 AS IdTipoMensaje, 'Los clientes seleccionados no existen.' AS Mensaje; LEAVE proc;
    END IF;

    SELECT CONCAT(nombre, ' ', apellido) INTO v_usuario FROM usuario WHERE id_usuario = p_id_usuario;

    START TRANSACTION;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    SELECT 'cliente', t.id_cliente, 'asignar_cartera', CAST(t.id_anterior AS CHAR), CAST(p_id_comercial AS CHAR),
           IF(p_id_comercial IS NULL, CONCAT(c.razon_social, ': se quitó de la cartera.'),
              CONCAT(c.razon_social, ': asignado a la cartera de ', v_comercial, '.')),
           p_id_usuario, NOW(), JSON_OBJECT('id_comercial_anterior', t.id_anterior, 'id_comercial', p_id_comercial)
    FROM tmp_cartera_asig t JOIN cliente c ON c.id_cliente = t.id_cliente
    WHERE NOT (t.id_anterior <=> p_id_comercial);

    UPDATE cliente c
    JOIN tmp_cartera_asig t ON t.id_cliente = c.id_cliente
    SET c.id_comercial_cartera = p_id_comercial,
        c.cartera_asignado_en  = IF(p_id_comercial IS NULL, NULL, NOW()),
        c.cartera_asignado_por = IF(p_id_comercial IS NULL, NULL, p_id_usuario),
        c.modificado_en = NOW(), c.modificado_por = p_id_usuario;

    IF p_id_comercial IS NOT NULL AND p_id_comercial <> p_id_usuario THEN
        INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
        VALUES (p_id_comercial, 5, 'Clientes asignados a tu cartera',
                CONCAT(v_usuario, ' te asignó ', v_n, IF(v_n = 1, ' cliente', ' clientes'), ' en tu cartera.'),
                'cliente', (SELECT MIN(id_cliente) FROM tmp_cartera_asig), NOW(), p_id_usuario);
    END IF;

    COMMIT;
    DROP TEMPORARY TABLE IF EXISTS tmp_cartera_asig;

    SELECT 2 AS IdTipoMensaje,
           IF(p_id_comercial IS NULL, CONCAT(v_n, IF(v_n = 1, ' cliente quitado', ' clientes quitados'), ' de la cartera.'),
              CONCAT(v_n, IF(v_n = 1, ' cliente asignado', ' clientes asignados'), ' a ', v_comercial, '.')) AS Mensaje;
    SELECT v_n AS clientes;
END$$

DELIMITER ;
