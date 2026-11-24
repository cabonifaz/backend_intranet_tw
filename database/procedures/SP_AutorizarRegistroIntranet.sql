-- ============================================================
-- SP_AutorizarRegistroIntranet  (HU-55 — puerta de entrada de CADA lectura o escritura del registro del informe desde la intranet · apoyo de la API)
-- Valida el permiso (acción seg_registrar_informe), resuelve el técnico asignado de la OS (el que se pasa a los casos de uso móviles: nunca el id de quien registra) y, en escritura,
-- exige y renueva el bloqueo del equipo (registro_informe_intranet).
--   p_modo = 'lectura'   permiso + técnico + OS no anulada; p_id_os_equipo puede ser NULL (pasos a nivel de OS: firma y constancia después de generar, cuando el bloqueo ya se liberó).
--            No toca el bloqueo.
--   p_modo = 'escritura' además exige p_id_os_equipo y la sesión ACTIVA PROPIA de ese equipo y renueva ultima_actividad. Sin sesión: "Primero inicia el registro de este equipo.".
--            Si otra persona la tiene con actividad en los últimos 30 min: regla de negocio con el prefijo "[409] " (la API lo convierte en HTTP 409). Si la sesión propia
--            estaba inactiva más de 30 min pero nadie la tomó, se renueva (el bloqueo solo se libera cuando otra persona lo pide en SP_IniciarRegistroIntranet).
-- No valida el estado de la OS ni del equipo más allá de "no anulada": eso lo hacen los SP móviles que se llaman después con el técnico.
-- Resultados: 1 mensaje (1 regla de negocio · 2 éxito · 3 error) · solo con 2: id_tecnico, id_registro (NULL en lectura), informe_fisico (0/1).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_AutorizarRegistroIntranet;

DELIMITER $$

CREATE PROCEDURE SP_AutorizarRegistroIntranet(
    IN p_id_registrador BIGINT,
    IN p_id_os          BIGINT,
    IN p_id_os_equipo   BIGINT,
    IN p_modo           VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_modo       VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado_os  VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_tecnico    BIGINT       DEFAULT NULL;
    DECLARE v_fisico     TINYINT      DEFAULT 1;
    DECLARE v_id_equipo  BIGINT       DEFAULT NULL;
    DECLARE v_reg_id     BIGINT       DEFAULT NULL;
    DECLARE v_reg_user   BIGINT       DEFAULT NULL;
    DECLARE v_reg_act    DATETIME     DEFAULT NULL;
    DECLARE v_reg_nombre VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_ahora      DATETIME;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SET v_modo = LOWER(TRIM(IFNULL(p_modo, '')));
    IF IFNULL(p_id_registrador, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio o equipo no encontrado.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_modo NOT IN ('lectura', 'escritura') THEN
        SELECT 1 AS IdTipoMensaje, 'El modo de acceso no es válido.' AS Mensaje; LEAVE proc;
    END IF;
    IF FN_PermisoAccion(p_id_registrador, 'seg_registrar_informe') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para registrar informes desde la intranet.' AS Mensaje; LEAVE proc;
    END IF;

    SELECT os.estado, os.id_tecnico_principal, IF(os.informe_fisico = 0, 0, 1) INTO v_estado_os, v_tecnico, v_fisico
    FROM   orden_servicio os
    WHERE  os.id_os = p_id_os AND os.eliminado_en IS NULL;
    IF v_estado_os IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio no encontrado.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_estado_os = 'anulada' THEN
        SELECT 1 AS IdTipoMensaje, 'La OS está anulada.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_tecnico IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'El servicio no tiene un técnico asignado.' AS Mensaje; LEAVE proc;
    END IF;

    IF p_id_os_equipo IS NOT NULL THEN
        SELECT oe.id_equipo INTO v_id_equipo FROM os_equipo oe WHERE oe.id = p_id_os_equipo AND oe.id_os = p_id_os AND oe.eliminado_en IS NULL;
        IF v_id_equipo IS NULL THEN
            SELECT 1 AS IdTipoMensaje, 'El equipo no pertenece a este servicio.' AS Mensaje; LEAVE proc;
        END IF;
    END IF;

    IF v_modo = 'lectura' THEN
        SELECT 2 AS IdTipoMensaje, 'Autorizado.' AS Mensaje;
        SELECT v_tecnico AS id_tecnico, NULL AS id_registro, v_fisico AS informe_fisico;
        LEAVE proc;
    END IF;

    -- Escritura: exige la sesión propia del equipo
    IF IFNULL(p_id_os_equipo, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Indica el equipo.' AS Mensaje; LEAVE proc;
    END IF;

    SET v_ahora = UTC_TIMESTAMP();
    START TRANSACTION;

    SELECT r.id_registro, r.id_registrador, r.ultima_actividad INTO v_reg_id, v_reg_user, v_reg_act
    FROM   registro_informe_intranet r
    WHERE  r.id_os_equipo = p_id_os_equipo AND r.id_os = p_id_os AND r.estado = 'activo'
    ORDER BY r.id_registro DESC LIMIT 1
    FOR UPDATE;

    IF v_reg_id IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Primero inicia el registro de este equipo.' AS Mensaje; LEAVE proc;
    END IF;

    IF v_reg_user = p_id_registrador THEN
        UPDATE registro_informe_intranet SET ultima_actividad = v_ahora WHERE id_registro = v_reg_id;
        COMMIT;
        SELECT 2 AS IdTipoMensaje, 'Autorizado.' AS Mensaje;
        SELECT v_tecnico AS id_tecnico, v_reg_id AS id_registro, v_fisico AS informe_fisico;
        LEAVE proc;
    END IF;

    -- La sesión es de otra persona
    IF v_reg_act >= v_ahora - INTERVAL 30 MINUTE THEN
        SELECT TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))) INTO v_reg_nombre FROM usuario u WHERE u.id_usuario = v_reg_user LIMIT 1;
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje,
               CONCAT('[409] ', IFNULL(NULLIF(v_reg_nombre, ''), 'Otra persona'), ' está registrando el informe de este equipo. Inténtalo cuando termine o pasen 30 minutos sin actividad.') AS Mensaje;
        LEAVE proc;
    END IF;

    -- Esa sesión caducó y quien llama no la tiene: se libera y debe iniciar el registro
    UPDATE registro_informe_intranet SET estado = 'caducado', liberado_en = v_ahora WHERE id_registro = v_reg_id;
    COMMIT;
    SELECT 1 AS IdTipoMensaje, 'Primero inicia el registro de este equipo.' AS Mensaje;
END$$

DELIMITER ;
