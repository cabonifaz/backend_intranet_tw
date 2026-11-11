-- ============================================================
-- SP_RegistrarSeguimientoJefaturaMovil  (App Mobile HU-30 — escritura: "Cambiar estado operativo" y "Avisar al cliente")
-- El jefe registra, desde la app, un cambio manual de estado del servicio o el aviso que dio al cliente. NO duplica reglas: valida que el servicio sea de su alcance
-- (SP_ResolverJefaturaMovil + SP_ArmarAlcanceJefaturaMovil) y delega la escritura en SP_RegistrarAsistenteServicioRuta (HU-53), que ya hace TODO lo demás:
-- permiso seg_registrar (y seg_bandeja), servicio de hoy y no finalizado, solo avanzar de estado, motivo del catálogo MOTIVO_CAMBIO_MANUAL, comentario obligatorio
-- (10 a 1000 caracteres), evento de campo del técnico, auditoría en la OS y el expediente (con el usuario y la hora), aviso a Jefatura, antiduplicado (15 s) y
-- límite de frecuencia, todo en una transacción con candado por usuario.
--   p_modo = cambio_estado : p_nuevo_estado (salida | en_ruta | llegada | ingreso | inicio | finalizado), p_id_motivo, p_texto = comentario (10 a 1000).
--   p_modo = aviso_cliente : p_texto = lo que se le avisó al cliente (5 a 450). Queda como NOTA del seguimiento ("Aviso al cliente (app de Jefatura): …") en el historial
--                            del servicio. NO envía correos ni mensajes: el aviso al cliente lo hace el jefe por llamada o mensaje y aquí solo se deja constancia.
-- Resultados: 1 mensaje (1 regla de negocio · 2 éxito · 3 error) · 2 (solo éxito) IdRegistro, Modo, Notificados, EstadoNuevo — los de SP_RegistrarAsistenteServicioRuta.
-- Requiere las migraciones 90 a 92.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_RegistrarSeguimientoJefaturaMovil;

DELIMITER $$

CREATE PROCEDURE SP_RegistrarSeguimientoJefaturaMovil(
    IN p_id_usuario   BIGINT,
    IN p_id_os        BIGINT,
    IN p_modo         VARCHAR(20)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_nuevo_estado VARCHAR(20)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_motivo    INT,
    IN p_texto        VARCHAR(1000) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_area        VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_sede        VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_aut_area    VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_aut_general TINYINT DEFAULT 0;
    DECLARE v_en_alcance  INT DEFAULT 0;
    DECLARE v_texto       VARCHAR(1000) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_jf_alc;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SET v_texto = TRIM(IFNULL(p_texto, ''));
    IF IFNULL(p_id_os, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El servicio indicado no es válido.' AS Mensaje;
        LEAVE proc;
    ELSEIF IFNULL(p_modo, '') NOT IN ('cambio_estado', 'aviso_cliente') THEN
        SELECT 1 AS IdTipoMensaje, 'El tipo de registro no es válido.' AS Mensaje;
        LEAVE proc;
    ELSEIF p_modo = 'cambio_estado' AND IFNULL(p_nuevo_estado, '') NOT IN ('salida', 'en_ruta', 'llegada', 'ingreso', 'inicio', 'finalizado') THEN
        SELECT 1 AS IdTipoMensaje, 'El nuevo estado no es válido.' AS Mensaje;
        LEAVE proc;
    ELSEIF p_modo = 'cambio_estado' AND IFNULL(p_id_motivo, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Elige el motivo del cambio.' AS Mensaje;
        LEAVE proc;
    ELSEIF p_modo = 'cambio_estado' AND CHAR_LENGTH(v_texto) < 10 THEN
        SELECT 1 AS IdTipoMensaje, 'El comentario es obligatorio (mínimo 10 caracteres).' AS Mensaje;
        LEAVE proc;
    ELSEIF p_modo = 'cambio_estado' AND CHAR_LENGTH(v_texto) > 1000 THEN
        SELECT 1 AS IdTipoMensaje, 'El comentario no puede superar los 1000 caracteres.' AS Mensaje;
        LEAVE proc;
    ELSEIF p_modo = 'aviso_cliente' AND CHAR_LENGTH(v_texto) < 5 THEN
        SELECT 1 AS IdTipoMensaje, 'Escribe lo que se le avisó al cliente (mínimo 5 caracteres).' AS Mensaje;
        LEAVE proc;
    ELSEIF p_modo = 'aviso_cliente' AND CHAR_LENGTH(v_texto) > 450 THEN
        SELECT 1 AS IdTipoMensaje, 'El aviso no puede superar los 450 caracteres.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_ResolverJefaturaMovil(p_id_usuario, v_area, v_sede, v_aut_area, v_aut_general);
    IF v_area IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Tu cargo no tiene el menú de Jefatura.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- El servicio debe ser de su alcance (misma regla del menú y del Panel de Campo)
    CALL SP_ArmarAlcanceJefaturaMovil(v_area, p_id_os);
    SELECT COUNT(*) INTO v_en_alcance FROM tmp_jf_alc WHERE id_os = p_id_os;
    DROP TEMPORARY TABLE IF EXISTS tmp_jf_alc;
    IF v_en_alcance = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El servicio no existe o no pertenece a tu área.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF p_modo = 'cambio_estado' THEN
        CALL SP_RegistrarAsistenteServicioRuta(p_id_usuario, p_id_os, 'cambio_estado', NULL, NULL, NULL, NULL, NULL, NULL, NULL, p_nuevo_estado, p_id_motivo, v_texto);
    ELSE
        CALL SP_RegistrarAsistenteServicioRuta(p_id_usuario, p_id_os, 'observacion', CONCAT('Aviso al cliente (app de Jefatura): ', v_texto), NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL);
    END IF;
END$$

DELIMITER ;
