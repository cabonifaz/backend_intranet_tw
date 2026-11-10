-- ============================================================
-- SP_ContextoEquipoMovil  (App Mobile HU-10 / HU-11 — apoyo, no es un endpoint)
-- Valida y arma, UNA sola vez, el contexto básico para trabajar en un equipo de una OS. Lo usan SP_ContextoEnsayoMovil (ensayos) y las evidencias.
--   - La OS debe ser del técnico. Hard Stop (HU-06): llegada registrada y servicio en curso (p_habilitado). El equipo debe estar iniciado
--     (en ejecución, pausado o completado); p_estado_equipo lo dice y quien escribe exige 'en_ejecucion'.
--   p_mensaje trae el texto para el técnico cuando algo impide continuar (lo demás queda NULL). Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ContextoEquipoMovil;

DELIMITER $$

CREATE PROCEDURE SP_ContextoEquipoMovil(
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
    OUT p_servicio      VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
BEGIN
    DECLARE v_estado_os   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_salida_utc  DATETIME;
    DECLARE v_llegada_utc DATETIME;
    DECLARE v_motivo      VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    SET p_mensaje = NULL, p_id_equipo = NULL, p_estado_equipo = NULL, p_habilitado = 0, p_numero = NULL, p_nombre_equipo = NULL, p_numero_os = NULL, p_servicio = NULL;

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
            SELECT t.id_equipo, t.estado, t.numero, t.nombre, COALESCE(t.tipo_corto, t.tipo_intervencion)
            INTO   p_id_equipo, p_estado_equipo, p_numero, p_nombre_equipo, p_servicio
            FROM   tmp_obj_mov t WHERE t.id_os_equipo = p_id_os_equipo;
            IF p_id_equipo IS NULL THEN
                SET p_mensaje = 'El equipo no forma parte de los objetivos de este servicio.';
            ELSEIF p_estado_equipo NOT IN ('en_ejecucion', 'pausado', 'completado') THEN
                SET p_mensaje = 'Primero inicia el trabajo en este equipo desde los objetivos.';
            END IF;
        END IF;
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
    END IF;
END$$

DELIMITER ;
