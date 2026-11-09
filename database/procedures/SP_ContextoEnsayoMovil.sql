-- ============================================================
-- SP_ContextoEnsayoMovil  (App Mobile HU-10 — apoyo, no es un endpoint)
-- Valida y arma, UNA sola vez, el contexto de los ensayos de un equipo. Lo usan SP_ObtenerEnsayosMovil, SP_GuardarEnsayosMovil y
-- SP_RegistrarLlamadaEnsayoMovil. Si algo impide trabajar, p_mensaje trae el texto para el técnico (y lo demás queda NULL).
--   - La OS debe ser del técnico. Hard Stop (HU-06): llegada registrada y servicio en curso. El equipo debe estar EN EJECUCIÓN o PAUSADO (lectura) —
--     p_estado_equipo lo dice, quien escribe exige 'en_ejecucion'.
--   - HU-09: antes de los ensayos deben estar guardadas las variables ambientales (temperatura y humedad).
--   - Especificaciones del equipo (equipo_cliente): clase de exactitud, capacidad máxima, d y e. Vienen como texto ("80 000 kg", "10 kg", "0,5 g"):
--     se toma el número (coma decimal o separador de miles) y la unidad (kg por defecto). e = división de verificación; si no tiene, d.
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ContextoEnsayoMovil;

DELIMITER $$

CREATE PROCEDURE SP_ContextoEnsayoMovil(
    IN  p_id_usuario    BIGINT,
    IN  p_id_os         BIGINT,
    IN  p_id_os_equipo  BIGINT,
    OUT p_mensaje       VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    OUT p_id_equipo     BIGINT,
    OUT p_estado_equipo VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    OUT p_habilitado    TINYINT,
    OUT p_numero        INT,
    OUT p_nombre_equipo VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    OUT p_numero_os     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    OUT p_clase         VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    OUT p_unidad        VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    OUT p_cap_max       DECIMAL(14,4),
    OUT p_d             DECIMAL(14,4),
    OUT p_e             DECIMAL(14,4)
)
BEGIN
    DECLARE v_estado_os   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_salida_utc  DATETIME;
    DECLARE v_llegada_utc DATETIME;
    DECLARE v_motivo      VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_vars        INT DEFAULT 0;
    DECLARE v_cap_txt     VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_d_txt       VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_e_txt       VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    SET p_mensaje = NULL, p_id_equipo = NULL, p_estado_equipo = NULL, p_habilitado = 0, p_numero = NULL, p_nombre_equipo = NULL, p_numero_os = NULL,
        p_clase = NULL, p_unidad = 'kg', p_cap_max = NULL, p_d = NULL, p_e = NULL;

    SELECT os.estado, os.numero INTO v_estado_os, p_numero_os
    FROM   orden_servicio os
    WHERE  os.id_os = p_id_os AND os.eliminado_en IS NULL
      AND  (os.id_tecnico_principal = p_id_usuario
            OR EXISTS (SELECT 1 FROM os_personal op
                       WHERE op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL));
    IF v_estado_os IS NULL THEN
        SET p_mensaje = 'Servicio no encontrado o no asignado a tu usuario.';
    ELSE
        CALL SP_ArmarObjetivosMovil(p_id_os, v_estado_os, v_salida_utc, v_llegada_utc, p_habilitado, v_motivo);
        IF v_llegada_utc IS NULL THEN
            SET p_mensaje = v_motivo;
        ELSE
            SELECT t.id_equipo, t.estado, t.numero, t.nombre INTO p_id_equipo, p_estado_equipo, p_numero, p_nombre_equipo
            FROM   tmp_obj_mov t WHERE t.id_os_equipo = p_id_os_equipo;
            IF p_id_equipo IS NULL THEN
                SET p_mensaje = 'El equipo no forma parte de los objetivos de este servicio.';
            ELSEIF p_estado_equipo NOT IN ('en_ejecucion', 'pausado', 'completado') THEN
                SET p_mensaje = 'Primero inicia el trabajo en este equipo desde los objetivos.';
            END IF;
        END IF;
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
    END IF;

    IF p_mensaje IS NULL THEN
        SELECT COUNT(*) INTO v_vars
        FROM   variable_ambiental va
        WHERE  va.id_os = p_id_os AND va.id_equipo = p_id_equipo AND va.eliminado_en IS NULL
          AND  va.temperatura_c IS NOT NULL AND va.humedad_pct IS NOT NULL;
        IF v_vars = 0 THEN
            SET p_mensaje = 'Primero registra las variables ambientales: Ensayos y Calibración se habilita al guardarlas.';
        END IF;
    END IF;

    IF p_mensaje IS NULL THEN
        SELECT UPPER(NULLIF(TRIM(ec.clase_exactitud), '')), ec.alcance_maximo, ec.division_minima, IF(ec.division_verif_igual = 1, NULL, ec.division_verif)
        INTO   p_clase, v_cap_txt, v_d_txt, v_e_txt
        FROM   equipo_cliente ec WHERE ec.id_equipo = p_id_equipo;

        -- Número: "80,000" y "80 000" son miles; "0,5" es decimal. Unidad: letras del primer dato (kg por defecto).
        SET p_cap_max = CAST(NULLIF(REGEXP_SUBSTR(IF(REGEXP_LIKE(TRIM(IFNULL(v_cap_txt, '')), '^[0-9]+,[0-9]{1,2}([^0-9]|$)'), REPLACE(v_cap_txt, ',', '.'), REPLACE(REPLACE(IFNULL(v_cap_txt, ''), ',', ''), ' ', '')), '[0-9]+(\\.[0-9]+)?'), '') AS DECIMAL(14,4));
        SET p_d       = CAST(NULLIF(REGEXP_SUBSTR(IF(REGEXP_LIKE(TRIM(IFNULL(v_d_txt, '')), '^[0-9]+,[0-9]{1,2}([^0-9]|$)'), REPLACE(v_d_txt, ',', '.'), REPLACE(REPLACE(IFNULL(v_d_txt, ''), ',', ''), ' ', '')), '[0-9]+(\\.[0-9]+)?'), '') AS DECIMAL(14,4));
        SET p_e       = CAST(NULLIF(REGEXP_SUBSTR(IF(REGEXP_LIKE(TRIM(IFNULL(v_e_txt, '')), '^[0-9]+,[0-9]{1,2}([^0-9]|$)'), REPLACE(v_e_txt, ',', '.'), REPLACE(REPLACE(IFNULL(v_e_txt, ''), ',', ''), ' ', '')), '[0-9]+(\\.[0-9]+)?'), '') AS DECIMAL(14,4));
        SET p_e       = COALESCE(p_e, p_d);
        SET p_unidad  = LOWER(IFNULL(NULLIF(REGEXP_SUBSTR(COALESCE(v_cap_txt, v_d_txt, ''), '[A-Za-z]+'), ''), 'kg'));
    END IF;
END$$

DELIMITER ;
