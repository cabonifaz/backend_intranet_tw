-- ============================================================
-- SP_ObtenerEnsayosMovil  (App Mobile HU-10 — Ensayos y Calibración · lectura)
-- Lo que necesita la pantalla: especificaciones del equipo (unidad, clase, capacidad máxima, d, e), la forma del plato, las lecturas ya guardadas de
-- pesaje y excentricidad (con su error, EMP y conformidad, calculados por el servidor al guardar), el estado de la etapa y el encargado del área a quien
-- llamar. Las reglas de acceso (Hard Stop, equipo iniciado, variables ambientales guardadas) están en SP_ContextoEnsayoMovil.
--   puede_registrar = el equipo está EN EJECUCIÓN. Sin clase de exactitud o sin e el EMP no se puede evaluar (evaluable = 0).
--   acepta_error = el técnico guardó "de todas formas" con un motivo (error_critico_motivo).
-- Resultados: 1 mensaje · 2 cabecera (1 fila) · 3 pesaje · 4 excentricidad · 5 encargado (0 o 1 fila).
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerEnsayosMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerEnsayosMovil(
    IN p_id_usuario   BIGINT,
    IN p_id_os        BIGINT,
    IN p_id_os_equipo BIGINT
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
    DECLARE v_informe  BIGINT DEFAULT NULL;
    DECLARE v_forma    VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_motivo   VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_final    DATETIME DEFAULT NULL;
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

    CALL SP_ContextoEnsayoMovil(p_id_usuario, p_id_os, p_id_os_equipo, v_msg, v_id_eq, v_est_eq, v_hab, v_numero, v_nombre, v_num_os, v_clase, v_unidad, v_cap, v_d, v_e);
    IF v_msg IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT it.id_informe, it.forma_plato, it.error_critico_motivo, it.ensayos_finalizado_en INTO v_informe, v_forma, v_motivo, v_final
    FROM   informe_tecnico it
    WHERE  it.id_os = p_id_os AND it.id_equipo = v_id_eq AND it.eliminado_en IS NULL
    ORDER BY it.id_informe DESC LIMIT 1;

    CALL SP_ContactoEncargadoEnsayoMovil(p_id_os, v_area, v_id_enc, v_nom_enc, v_car_enc, v_tel_enc);

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Cabecera
    SELECT p_id_os AS id_os, p_id_os_equipo AS id_os_equipo, v_num_os AS numero_os, v_nombre AS nombre, v_numero AS numero,
           v_unidad AS unidad, v_clase AS clase, v_cap AS cap_maxima, v_d AS d, v_e AS e, IF(v_clase IS NOT NULL AND v_e IS NOT NULL AND v_e > 0, 1, 0) AS evaluable,
           IFNULL(v_forma, 'rectangular') AS forma_plato, v_motivo AS motivo_error_critico, IF(v_motivo IS NULL, 0, 1) AS acepta_error,
           IF(v_final IS NULL, 0, 1) AS finalizado,
           IF(v_final IS NULL, NULL, CONVERT_TZ(v_final, '+00:00', '-05:00')) AS finalizado_en,
           IF(v_est_eq = 'en_ejecucion' AND v_hab = 1, 1, 0) AS puede_registrar,
           v_area AS area_encargado;

    -- 3. Pesaje (carga L, indicación I, error E, EMP y conformidad guardados)
    SELECT ie.orden, ie.carga, ie.lectura AS indicacion, ie.error, ie.tolerancia AS emp, ie.resultado, ie.critico
    FROM   informe_ensayo ie
    WHERE  ie.id_informe = v_informe AND ie.tipo = 'pesaje' AND ie.eliminado_en IS NULL
    ORDER BY ie.orden, ie.id_ensayo;

    -- 4. Excentricidad (grupo = número de la carga de prueba; orden = posición)
    SELECT ie.grupo, ie.orden AS posicion, ie.carga, ie.lectura AS indicacion, ie.error, ie.tolerancia AS emp, ie.resultado, ie.critico
    FROM   informe_ensayo ie
    WHERE  ie.id_informe = v_informe AND ie.tipo = 'excentricidad' AND ie.eliminado_en IS NULL
    ORDER BY ie.grupo, ie.orden, ie.id_ensayo;

    -- 5. Encargado del área (a quien llamar)
    SELECT v_id_enc AS id_usuario, v_nom_enc AS nombre, v_car_enc AS cargo, v_tel_enc AS telefono, v_area AS area
    FROM   DUAL WHERE v_nom_enc IS NOT NULL;
END$$

DELIMITER ;
