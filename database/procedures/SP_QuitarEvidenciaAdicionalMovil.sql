-- ============================================================
-- SP_QuitarEvidenciaAdicionalMovil  (App Mobile — quita una foto adicional del registro fotográfico · escritura)
-- El técnico quita una de sus FOTOS ADICIONALES (las extras opcionales, codigo 'adicional') mientras el equipo siga en ejecución. Solo estas: las 9 evidencias
-- del panel no se quitan (se repiten). Borrado lógico (eliminado_en / eliminado_por); el archivo se conserva. Acceso: SP_ContextoEquipoMovil (OS del técnico, Hard Stop).
-- Deja el registro en auditoria_evento.
-- Resultados: 1 mensaje.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_QuitarEvidenciaAdicionalMovil;

DELIMITER $$

CREATE PROCEDURE SP_QuitarEvidenciaAdicionalMovil(
    IN p_id_usuario   BIGINT,
    IN p_id_os        BIGINT,
    IN p_id_os_equipo BIGINT,
    IN p_id_evidencia BIGINT
)
proc: BEGIN
    DECLARE v_msg      VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_eq    BIGINT;
    DECLARE v_est_eq   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_hab      TINYINT;
    DECLARE v_numero   INT;
    DECLARE v_nombre   VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_num_os   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_servicio VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_pagina   INT DEFAULT NULL;
    DECLARE v_filas    INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 OR IFNULL(p_id_os_equipo, 0) <= 0 OR IFNULL(p_id_evidencia, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Foto no encontrada.' AS Mensaje; LEAVE proc;
    END IF;

    START TRANSACTION;

    CALL SP_ContextoEquipoMovil(p_id_usuario, p_id_os, p_id_os_equipo, v_msg, v_id_eq, v_est_eq, v_hab, v_numero, v_nombre, v_num_os, v_servicio);
    IF v_msg IS NULL AND (v_hab = 0 OR v_est_eq <> 'en_ejecucion') THEN
        SET v_msg = IF(v_est_eq = 'pausado', 'El equipo está pausado: reanúdalo para quitar fotos.',
                       IF(v_est_eq = 'completado', 'Este equipo ya está completado.', 'El servicio ya no está en curso: no se pueden quitar fotos.'));
    END IF;
    IF v_msg IS NOT NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje; LEAVE proc;
    END IF;

    SELECT f.pagina INTO v_pagina
    FROM   evidencia_fotografica f
    WHERE  f.id_evidencia = p_id_evidencia AND f.id_os = p_id_os AND f.id_equipo = v_id_eq AND f.codigo = 'adicional' AND f.eliminado_en IS NULL
    FOR UPDATE;

    IF v_pagina IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Foto adicional no encontrada.' AS Mensaje; LEAVE proc;
    END IF;

    UPDATE evidencia_fotografica SET eliminado_en = NOW(), eliminado_por = p_id_usuario WHERE id_evidencia = p_id_evidencia AND eliminado_en IS NULL;
    SET v_filas = ROW_COUNT();

    IF v_filas = 1 THEN
        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
        VALUES ('os_equipo', p_id_os_equipo, 'quitar_evidencia_adicional', NULL, 'quitada',
                LEFT(CONCAT('Foto adicional ', v_pagina, ' de ', v_num_os, ' quitada por el técnico.'), 900),
                p_id_usuario, NOW(), JSON_OBJECT('id_evidencia', p_id_evidencia, 'numero', v_pagina));
    END IF;

    COMMIT;
    SELECT 2 AS IdTipoMensaje, 'Foto adicional quitada.' AS Mensaje;
END$$

DELIMITER ;
