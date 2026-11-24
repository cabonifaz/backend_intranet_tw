-- ============================================================
-- SP_ContextoEquipoPrevioMovil  (App Mobile HU-18 · trabajo sin señal — apoyo, no es un endpoint · SOLO LECTURA)
-- Igual que SP_ContextoEquipoMovil pero SIN el Hard Stop de la llegada ni el de "equipo iniciado": sirve para que la app descargue por adelantado, con señal, lo que el técnico
-- necesitará sin señal (cabecera del informe y evidencias del equipo). Lo llaman solo las lecturas con p_previo = 1; ninguna escritura lo usa, así que nunca habilita trabajar.
--   - La OS debe ser del técnico y estar programada, reprogramada, en ruta, en ejecución o pausada.
--   - El equipo debe ser un objetivo de la OS. p_estado_equipo trae su estado real (por_iniciar, en_ejecucion, pausado…) y p_habilitado queda como lo arma SP_ArmarObjetivosMovil
--     (0 antes de la llegada): por eso lo que se descarga sale con "puede registrar / puede editar" en 0.
--   p_mensaje trae el texto para el técnico cuando algo impide continuar (lo demás queda NULL). Mismos parámetros que SP_ContextoEquipoMovil.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ContextoEquipoPrevioMovil;

DELIMITER $$

CREATE PROCEDURE SP_ContextoEquipoPrevioMovil(
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
    ELSEIF v_estado_os NOT IN ('programada', 'reprogramada', 'en_ruta', 'en_ejecucion', 'pausada') THEN
        SET p_mensaje = 'El servicio no está disponible para trabajar.';
    ELSE
        CALL SP_ArmarObjetivosMovil(p_id_os, v_estado_os, v_salida_utc, v_llegada_utc, p_habilitado, v_motivo);
        SELECT t.id_equipo, t.estado, t.numero, t.nombre, COALESCE(t.tipo_corto, t.tipo_intervencion)
        INTO   p_id_equipo, p_estado_equipo, p_numero, p_nombre_equipo, p_servicio
        FROM   tmp_obj_mov t WHERE t.id_os_equipo = p_id_os_equipo;
        IF p_id_equipo IS NULL THEN
            SET p_mensaje = 'El equipo no forma parte de los objetivos de este servicio.';
        END IF;
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
    END IF;
END$$

DELIMITER ;
