-- HU-32 (complemento) Registrar a mano un bloqueo o una excepción en el expediente.
-- Acción expediente_resolver_bloqueo (jefes). Expediente no cerrado.
--   p_clase      'bloqueo' (impide avanzar) o 'excepcion' (requisito pendiente aceptado: no impide avanzar)
--   p_tipo       documento_faltante, ssoma, cobertura_oc, sin_aprobacion u otro
--   p_id_motivo  bloqueo SSOMA: MOTIVO_BLOQUEO_SSOMA (16) · excepción: MOTIVO_EXCEPCION_EXPEDIENTE (17). Opcional.
--   descripción (5 a 300), tipo documental e impacto (opcionales, hasta 150 y 300), crítico (bloqueos) y responsable.
-- El estado del expediente se actualiza y se notifica al área responsable de la etapa.
-- Resultados: 1 mensaje · 2 registro
DROP PROCEDURE IF EXISTS SP_RegistrarBloqueoExpediente;

DELIMITER $$

CREATE PROCEDURE SP_RegistrarBloqueoExpediente(
    IN p_id_usuario      BIGINT,
    IN p_id_expediente   BIGINT,
    IN p_clase           VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_tipo            VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_motivo       INT,
    IN p_descripcion     VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_tipo_documental VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_impacto         VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_critico         TINYINT,
    IN p_id_responsable  BIGINT
)
proc: BEGIN
    DECLARE v_existe      INT DEFAULT 0;
    DECLARE v_etapa       VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_area        VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_numero      VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_clase       VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_descripcion VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_motivo      VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id          BIGINT;
    DECLARE v_notificados INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_exp;
        GET DIAGNOSTICS CONDITION 1
            @err_msg  = MESSAGE_TEXT,
            @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje,
               CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SET v_clase       = LOWER(TRIM(IFNULL(p_clase, '')));
    SET v_descripcion = NULLIF(TRIM(IFNULL(p_descripcion, '')), '');

    IF FN_PermisoAccion(p_id_usuario, 'expediente_resolver_bloqueo') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para registrar bloqueos o excepciones.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_CalcularExpedientes(p_id_usuario, p_id_expediente);
    SELECT COUNT(*), MAX(etapa), MAX(area), MAX(numero) INTO v_existe, v_etapa, v_area, v_numero FROM tmp_exp;
    DROP TEMPORARY TABLE IF EXISTS tmp_exp;

    IF v_existe = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El expediente no existe.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_etapa = 'cerrado' THEN
        SELECT 1 AS IdTipoMensaje, 'El expediente está cerrado.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_clase NOT IN ('bloqueo', 'excepcion') THEN
        SELECT 1 AS IdTipoMensaje, 'Indique si es un bloqueo o una excepción.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF IFNULL(p_tipo, '') NOT IN ('documento_faltante', 'ssoma', 'cobertura_oc', 'sin_aprobacion', 'otro') THEN
        SELECT 1 AS IdTipoMensaje, 'Tipo no válido: documento_faltante, ssoma, cobertura_oc, sin_aprobacion u otro.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_descripcion IS NULL OR CHAR_LENGTH(v_descripcion) < 5 THEN
        SELECT 1 AS IdTipoMensaje, 'Describa el bloqueo o la excepción (mínimo 5 caracteres).' AS Mensaje;
        LEAVE proc;
    END IF;
    IF p_id_motivo IS NOT NULL THEN
        SELECT String1 INTO v_motivo FROM tabla_maestra
        WHERE IdEmpresa = 1 AND Num1 = p_id_motivo AND IdMaestro = IF(v_clase = 'excepcion', 17, 16);
        IF v_motivo IS NULL THEN
            SELECT 1 AS IdTipoMensaje, 'El motivo no es válido.' AS Mensaje;
            LEAVE proc;
        END IF;
    END IF;
    IF p_id_responsable IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM usuario WHERE id_usuario = p_id_responsable AND estado = 'activo' AND eliminado_en IS NULL) THEN
        SELECT 1 AS IdTipoMensaje, 'El responsable no es un usuario activo.' AS Mensaje;
        LEAVE proc;
    END IF;

    START TRANSACTION;

    INSERT INTO expediente_bloqueador (id_expediente, clase, descripcion, tipo, etapa, id_motivo, tipo_documental, impacto,
                                       critico, origen_tipo, id_responsable, resuelto, creado_por)
    VALUES (p_id_expediente, v_clase, v_descripcion, p_tipo, v_etapa, p_id_motivo,
            NULLIF(TRIM(IFNULL(p_tipo_documental, '')), ''), NULLIF(TRIM(IFNULL(p_impacto, '')), ''),
            IF(v_clase = 'excepcion', 0, IFNULL(p_critico, 1)), 'manual', p_id_responsable, 0, p_id_usuario);
    SET v_id = LAST_INSERT_ID();

    CALL SP_ActualizarEstadoExpediente(p_id_expediente, p_id_usuario);

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario,
                                  registrado_en, metadata)
    VALUES ('expediente', p_id_expediente, IF(v_clase = 'excepcion', 'registrar_excepcion', 'registrar_bloqueo'), NULL, NULL,
            CONCAT(v_descripcion, IFNULL(CONCAT(' (', v_motivo, ')'), ''),
                   IFNULL(CONCAT('. Impacto: ', NULLIF(TRIM(IFNULL(p_impacto, '')), '')), '')),
            p_id_usuario, NOW(), JSON_OBJECT('etapa', v_etapa, 'id_bloqueador', v_id, 'tipo', p_tipo));

    CALL SP_NotificarAreaExpediente(p_id_expediente, v_area, p_id_responsable,
        CONCAT(IF(v_clase = 'excepcion', 'Excepción', 'Bloqueo'), ' en el expediente ', v_numero),
        CONCAT(IF(v_clase = 'excepcion', 'Se registró una excepción: ', 'Se registró un bloqueo: '), v_descripcion, '.'),
        p_id_usuario, v_notificados);

    COMMIT;

    SELECT 2 AS IdTipoMensaje, IF(v_clase = 'excepcion', 'Excepción registrada.', 'Bloqueo registrado.') AS Mensaje;
    SELECT v_id AS id_bloqueador, v_clase AS clase, v_etapa AS etapa,
           (SELECT estado FROM expediente_digital WHERE id_expediente = p_id_expediente) AS estado_expediente,
           v_notificados AS notificados;
END$$

DELIMITER ;
