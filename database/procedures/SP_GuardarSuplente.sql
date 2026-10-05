-- HU-84 — Crear (p_id_asignacion = 0) o editar una asignación de suplencia
--   Validaciones: suplente ≠ titular, fin ≥ inicio, suplente comercial activo,
--   sin otra asignación activa del mismo par en un periodo que se cruce.
DROP PROCEDURE IF EXISTS SP_GuardarSuplente;

DELIMITER $$

CREATE PROCEDURE SP_GuardarSuplente(
    IN p_id_asignacion INT,
    IN p_id_titular    BIGINT,
    IN p_id_suplente   BIGINT,
    IN p_fecha_inicio  DATE,
    IN p_fecha_fin     DATE,
    IN p_activo        TINYINT,
    IN p_usuario       VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_id INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            @err_msg  = MESSAGE_TEXT,
            @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje,
               CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    -- ── Validaciones ─────────────────────────────────────────────────────
    IF p_id_titular = p_id_suplente THEN
        SELECT 1 AS IdTipoMensaje, 'El titular y el suplente no pueden ser la misma persona.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF p_fecha_inicio IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'La fecha de inicio es obligatoria.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF p_fecha_fin IS NOT NULL AND p_fecha_fin < p_fecha_inicio THEN
        SELECT 1 AS IdTipoMensaje, 'La fecha de fin debe ser igual o posterior a la fecha de inicio.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM usuario WHERE id_usuario = p_id_titular AND eliminado_en IS NULL
    ) THEN
        SELECT 1 AS IdTipoMensaje, 'El usuario titular no existe.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM usuario
        WHERE id_usuario = p_id_suplente
          AND estado = 'activo'
          AND eliminado_en IS NULL
    ) THEN
        SELECT 1 AS IdTipoMensaje, 'El suplente debe ser un usuario activo.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF p_id_asignacion <> 0 AND NOT EXISTS (
        SELECT 1 FROM usuario_suplente WHERE id = p_id_asignacion AND SoftDelete = 0
    ) THEN
        SELECT 1 AS IdTipoMensaje, 'Asignación no encontrada.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF p_activo = 1 AND EXISTS (
        SELECT 1 FROM usuario_suplente
        WHERE id_titular  = p_id_titular
          AND id_suplente = p_id_suplente
          AND activo = 1
          AND SoftDelete = 0
          AND id <> p_id_asignacion
          AND fecha_inicio <= IFNULL(p_fecha_fin, '9999-12-31')
          AND IFNULL(fecha_fin, '9999-12-31') >= p_fecha_inicio
    ) THEN
        SELECT 1 AS IdTipoMensaje, 'Ya existe una asignación activa de este suplente para el mismo titular en ese periodo.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- ── Crear o actualizar ───────────────────────────────────────────────
    IF p_id_asignacion = 0 THEN
        INSERT INTO usuario_suplente (
            id_titular, id_suplente, fecha_inicio, fecha_fin,
            activo, SoftDelete, UsuCre, FchCre
        ) VALUES (
            p_id_titular, p_id_suplente, p_fecha_inicio, p_fecha_fin,
            IFNULL(p_activo, 1), 0, p_usuario, NOW()
        );
        SET v_id = LAST_INSERT_ID();
    ELSE
        UPDATE usuario_suplente SET
            id_titular   = p_id_titular,
            id_suplente  = p_id_suplente,
            fecha_inicio = p_fecha_inicio,
            fecha_fin    = p_fecha_fin,
            activo       = IFNULL(p_activo, 1),
            UsuMod       = p_usuario,
            FchMod       = NOW()
        WHERE id = p_id_asignacion;
        SET v_id = p_id_asignacion;
    END IF;

    SELECT 2 AS IdTipoMensaje,
           IF(p_id_asignacion = 0, 'Suplencia registrada correctamente.', 'Suplencia actualizada correctamente.') AS Mensaje;
    SELECT v_id AS id_asignacion;
END$$

DELIMITER ;
