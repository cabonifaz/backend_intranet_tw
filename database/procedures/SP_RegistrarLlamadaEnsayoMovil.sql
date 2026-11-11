-- ============================================================
-- SP_RegistrarLlamadaEnsayoMovil  (App Mobile HU-10 — "Llamar" al encargado ante un error crítico · escritura)
-- El técnico llama al encargado del área (según la RQ) para comunicarle el error en la calibración. Se REGISTRA la llamada en el ensayo (hora y error
-- reportado) en auditoria_evento, y se devuelve a quién llamar. La llamada en sí la hace el teléfono; aquí solo queda constancia.
--   - Mismo acceso que los ensayos (SP_ContextoEnsayoMovil). p_detalle = el error reportado (hasta 300 caracteres).
-- Resultados: 1 mensaje; 2 (nombre, cargo, telefono, area). Sin encargado con teléfono responde la regla de negocio.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_RegistrarLlamadaEnsayoMovil;

DELIMITER $$

CREATE PROCEDURE SP_RegistrarLlamadaEnsayoMovil(
    IN p_id_usuario   BIGINT,
    IN p_id_os        BIGINT,
    IN p_id_os_equipo BIGINT,
    IN p_detalle      VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_msg      VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_eq    BIGINT;
    DECLARE v_est_eq   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_hab      TINYINT;
    DECLARE v_numero   INT;
    DECLARE v_nombre   VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_num_os   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_clase    VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_unidad   VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cap      DECIMAL(14,4);
    DECLARE v_d        DECIMAL(14,4);
    DECLARE v_e        DECIMAL(14,4);
    DECLARE v_area     VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_enc   BIGINT;
    DECLARE v_nom_enc  VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_car_enc  VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tel_enc  VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF CHAR_LENGTH(IFNULL(p_detalle, '')) > 300 THEN
        SELECT 1 AS IdTipoMensaje, 'El detalle puede tener hasta 300 caracteres.' AS Mensaje; LEAVE proc;
    END IF;

    CALL SP_ContextoEnsayoMovil(p_id_usuario, p_id_os, p_id_os_equipo, v_msg, v_id_eq, v_est_eq, v_hab, v_numero, v_nombre, v_num_os, v_clase, v_unidad, v_cap, v_d, v_e);
    IF v_msg IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje; LEAVE proc;
    END IF;

    CALL SP_ContactoEncargadoEnsayoMovil(p_id_os, v_area, v_id_enc, v_nom_enc, v_car_enc, v_tel_enc);
    IF v_nom_enc IS NULL OR v_tel_enc IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'No hay un encargado del área con teléfono registrado. Comunícate con Operaciones.' AS Mensaje; LEAVE proc;
    END IF;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('os_equipo', p_id_os_equipo, 'llamar_encargado_ensayo', NULL, NULL,
            LEFT(CONCAT('Llamada al encargado ', v_nom_enc, ' (', IFNULL(v_area, ''), ') por error en el ensayo de ', v_nombre, ' en ', v_num_os,
                        IF(NULLIF(TRIM(IFNULL(p_detalle, '')), '') IS NULL, '', CONCAT(': ', TRIM(p_detalle)))), 900),
            p_id_usuario, NOW(),
            JSON_OBJECT('id_os', p_id_os, 'id_encargado', v_id_enc, 'telefono', v_tel_enc));

    SELECT 2 AS IdTipoMensaje, 'Llamada registrada en el ensayo.' AS Mensaje;
    SELECT v_nom_enc AS nombre, v_car_enc AS cargo, v_tel_enc AS telefono, v_area AS area;
END$$

DELIMITER ;
