-- ============================================================
-- SP_ContextoAsistenteMovil  (App Mobile HU-19 — apoyo, no es un endpoint)
-- Valida y arma, UNA sola vez, el equipo que el técnico usa como contexto del Asistente IA. Lo usan SP_InicioAsistenteMovil, SP_DocumentosAsistenteMovil
-- y SP_RegistrarConsultaAsistenteMovil.
--   - La OS debe ser del técnico (principal o personal asignado), igual que SP_ContextoEquipoMovil.
--   - NO exige el Hard Stop de llegada ni que el equipo esté iniciado: consultar un manual no es registrar trabajo. Sí debe ser un objetivo de la OS
--     (SP_ArmarObjetivosMovil) y la OS no puede estar finalizada ni anulada.
--   p_mensaje trae el texto para el técnico cuando algo impide continuar (lo demás queda NULL). Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ContextoAsistenteMovil;

DELIMITER $$

CREATE PROCEDURE SP_ContextoAsistenteMovil(
    IN  p_id_usuario     BIGINT,
    IN  p_id_os          BIGINT,
    IN  p_id_os_equipo   BIGINT,
    OUT p_mensaje        VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    OUT p_id_equipo      BIGINT,
    OUT p_id_suministro  BIGINT,
    OUT p_estado_equipo  VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    OUT p_numero         INT,
    OUT p_nombre_equipo  VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    OUT p_numero_os      VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    OUT p_servicio       VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    OUT p_marca          VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    OUT p_modelo         VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    OUT p_codigo_cliente VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    OUT p_num_serie      VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
BEGIN
    DECLARE v_estado_os   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_salida_utc  DATETIME;
    DECLARE v_llegada_utc DATETIME;
    DECLARE v_hab         TINYINT;
    DECLARE v_motivo      VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    SET p_mensaje = NULL, p_id_equipo = NULL, p_id_suministro = NULL, p_estado_equipo = NULL, p_numero = NULL, p_nombre_equipo = NULL, p_numero_os = NULL,
        p_servicio = NULL, p_marca = NULL, p_modelo = NULL, p_codigo_cliente = NULL, p_num_serie = NULL;

    SELECT os.estado, os.numero INTO v_estado_os, p_numero_os
    FROM   orden_servicio os
    WHERE  os.id_os = p_id_os AND os.eliminado_en IS NULL
      AND  (os.id_tecnico_principal = p_id_usuario
            OR EXISTS (SELECT 1 FROM os_personal op
                       WHERE op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL));
    IF v_estado_os IS NULL THEN
        SET p_mensaje = 'Servicio no encontrado o no asignado a tu usuario.';
    ELSEIF v_estado_os IN ('finalizada', 'anulada') THEN
        SET p_mensaje = 'Este servicio ya no está activo.';
    ELSE
        -- Solo se aprovecha la tabla de objetivos (equipo, número, nombre): el Hard Stop (llegada) no se exige
        CALL SP_ArmarObjetivosMovil(p_id_os, v_estado_os, v_salida_utc, v_llegada_utc, v_hab, v_motivo);
        SELECT t.id_equipo, t.estado, t.numero, t.nombre, COALESCE(t.tipo_corto, t.tipo_intervencion), t.marca, t.modelo, t.codigo_cliente, t.num_serie
        INTO   p_id_equipo, p_estado_equipo, p_numero, p_nombre_equipo, p_servicio, p_marca, p_modelo, p_codigo_cliente, p_num_serie
        FROM   tmp_obj_mov t WHERE t.id_os_equipo = p_id_os_equipo;
        IF p_id_equipo IS NULL THEN
            SET p_mensaje = 'El equipo no forma parte de los objetivos de este servicio.';
        ELSE
            SELECT ec.id_suministro INTO p_id_suministro FROM equipo_cliente ec WHERE ec.id_equipo = p_id_equipo LIMIT 1;
        END IF;
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
    END IF;
END$$

DELIMITER ;
