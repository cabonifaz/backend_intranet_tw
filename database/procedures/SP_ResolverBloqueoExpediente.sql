-- HU-32 Resolver un bloqueo o cerrar una excepción del expediente.
-- Acción expediente_resolver_bloqueo (Jefe de Operaciones / Jefe Comercial).
--   Bloqueo:   tipo de resolución (TIPO_RESOLUCION_BLOQUEO 98) y evidencia obligatorios, comentario opcional.
--   Excepción: resultado de cierre (RESULTADO_CIERRE_EXCEPCION 99), sustento (10 a 1000) y evidencia obligatorios.
-- Los bloqueos de una OC observada se resuelven corrigiendo y revalidando la OC (Órdenes de Compra).
-- La evidencia queda como documento interno del expediente (etapa del bloqueo). Al resolver: el estado del expediente
-- se actualiza solo, queda auditado y se notifica al área responsable de la etapa (jefes) y al responsable.
-- p_solo_validar = 1 valida sin guardar (antes de escribir el archivo).
-- Resultados: 1 mensaje · 2 resultado
DROP PROCEDURE IF EXISTS SP_ResolverBloqueoExpediente;

DELIMITER $$

CREATE PROCEDURE SP_ResolverBloqueoExpediente(
    IN p_id_usuario     BIGINT,
    IN p_id_expediente  BIGINT,
    IN p_id_bloqueador  BIGINT,
    IN p_id_opcion      INT,
    IN p_sustento       VARCHAR(1000) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_ruta           VARCHAR(500)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_nombre_archivo VARCHAR(200)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_tamano         BIGINT,
    IN p_tipo_contenido VARCHAR(100)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_hash           CHAR(64)      CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_solo_validar   TINYINT
)
proc: BEGIN
    DECLARE v_clase       VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_resuelto    TINYINT;
    DECLARE v_origen      VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tipo        VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_descripcion VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_etapa_b     VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_resp_b   BIGINT;
    DECLARE v_opcion      VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_sustento    VARCHAR(1000) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_etapa       VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_area        VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_resp     BIGINT;
    DECLARE v_numero      VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_tipo_doc INT;
    DECLARE v_id_doc      BIGINT;
    DECLARE v_notificados INT DEFAULT 0;
    DECLARE v_estado      VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_resuelto_bd TINYINT;

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

    SET v_sustento = NULLIF(TRIM(IFNULL(p_sustento, '')), '');

    IF FN_PermisoAccion(p_id_usuario, 'expediente_resolver_bloqueo') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para resolver bloqueos o cerrar excepciones.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT clase, resuelto, origen_tipo, tipo, descripcion, etapa, id_responsable
      INTO v_clase, v_resuelto, v_origen, v_tipo, v_descripcion, v_etapa_b, v_id_resp_b
    FROM expediente_bloqueador
    WHERE id_bloqueador = p_id_bloqueador AND id_expediente = p_id_expediente AND eliminado_en IS NULL;

    IF v_clase IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'El bloqueo no existe en este expediente.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_resuelto = 1 THEN
        SELECT 1 AS IdTipoMensaje, IF(v_clase = 'excepcion', 'La excepción ya fue cerrada.', 'El bloqueo ya fue resuelto.') AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_origen = 'orden_compra' THEN
        SELECT 1 AS IdTipoMensaje,
               'Este bloqueo viene de una OC observada: se resuelve corrigiendo y revalidando la OC desde Órdenes de Compra.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT String1 INTO v_opcion FROM tabla_maestra
    WHERE IdEmpresa = 1 AND Num1 = p_id_opcion AND IdMaestro = IF(v_clase = 'excepcion', 99, 98);
    IF v_opcion IS NULL THEN
        SELECT 1 AS IdTipoMensaje,
               IF(v_clase = 'excepcion', 'Seleccione el resultado de cierre.', 'Seleccione el tipo de resolución.') AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_clase = 'excepcion' AND (v_sustento IS NULL OR CHAR_LENGTH(v_sustento) < 10) THEN
        SELECT 1 AS IdTipoMensaje, 'Detalle el sustento del cierre (mínimo 10 caracteres).' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_CalcularExpedientes(p_id_usuario, p_id_expediente);
    SELECT MAX(etapa), MAX(area), MAX(id_responsable), MAX(numero) INTO v_etapa, v_area, v_id_resp, v_numero FROM tmp_exp;
    DROP TEMPORARY TABLE IF EXISTS tmp_exp;

    IF v_etapa = 'cerrado' THEN
        SELECT 1 AS IdTipoMensaje, 'El expediente está cerrado.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF IFNULL(p_solo_validar, 0) = 1 THEN
        SELECT 2 AS IdTipoMensaje, 'Validado.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF NULLIF(TRIM(IFNULL(p_ruta, '')), '') IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Adjunte la evidencia (documento o imagen).' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT Num1 INTO v_id_tipo_doc FROM tabla_maestra
    WHERE IdMaestro = 96 AND IdEmpresa = 1 AND String2 = IF(v_tipo = 'ssoma', 'DOCUMENTO_SSOMA', 'OTRO') LIMIT 1;

    START TRANSACTION;

    -- Bloquea el registro y confirma que sigue abierto (doble clic, dos jefes a la vez)
    SELECT resuelto INTO v_resuelto_bd FROM expediente_bloqueador WHERE id_bloqueador = p_id_bloqueador FOR UPDATE;
    IF v_resuelto_bd = 1 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, IF(v_clase = 'excepcion', 'La excepción ya fue cerrada.', 'El bloqueo ya fue resuelto.') AS Mensaje;
        LEAVE proc;
    END IF;

    INSERT INTO documento_adjunto (entidad_tipo, id_entidad, id_tipo_documento, nombre_archivo, url_archivo, version,
                                   id_visibilidad, metadatos, subido_por, fecha_carga, creado_por)
    VALUES ('expediente', p_id_expediente, IFNULL(v_id_tipo_doc, 1), LEFT(IFNULL(p_nombre_archivo, 'evidencia'), 200), p_ruta, 1, 1,
            JSON_OBJECT('nombre_documento', LEFT(CONCAT('Evidencia: ', v_descripcion), 200),
                        'descripcion', LEFT(CONCAT(v_opcion, IFNULL(CONCAT('. ', v_sustento), '')), 1000),
                        'etapa', IFNULL(v_etapa_b, v_etapa), 'tamano_bytes', p_tamano, 'tipo_contenido', p_tipo_contenido,
                        'hash', p_hash, 'id_bloqueador', p_id_bloqueador),
            p_id_usuario, NOW(), p_id_usuario);
    SET v_id_doc = LAST_INSERT_ID();

    UPDATE expediente_bloqueador SET
        resuelto               = 1,
        fecha_resolucion       = NOW(),
        id_tipo_resolucion     = p_id_opcion,
        sustento               = v_sustento,
        id_documento_evidencia = v_id_doc,
        resuelto_por           = p_id_usuario,
        modificado_por         = p_id_usuario
    WHERE id_bloqueador = p_id_bloqueador;

    CALL SP_ActualizarEstadoExpediente(p_id_expediente, p_id_usuario);
    SELECT estado INTO v_estado FROM expediente_digital WHERE id_expediente = p_id_expediente;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario,
                                  registrado_en, metadata)
    VALUES ('expediente', p_id_expediente, IF(v_clase = 'excepcion', 'cerrar_excepcion', 'resolver_bloqueo'), NULL, v_estado,
            LEFT(CONCAT(v_descripcion, '. ', IF(v_clase = 'excepcion', 'Resultado: ', 'Resolución: '), v_opcion,
                        IFNULL(CONCAT('. Sustento: ', v_sustento), ''), '.'), 2000),
            p_id_usuario, NOW(),
            JSON_OBJECT('etapa', IFNULL(v_etapa_b, v_etapa), 'id_bloqueador', p_id_bloqueador, 'id_opcion', p_id_opcion,
                        'id_documento', v_id_doc));

    CALL SP_NotificarAreaExpediente(p_id_expediente, v_area, IFNULL(v_id_resp_b, v_id_resp),
        CONCAT(IF(v_clase = 'excepcion', 'Excepción cerrada', 'Bloqueo resuelto'), ' en ', v_numero),
        CONCAT(IF(v_clase = 'excepcion', 'Se cerró la excepción: ', 'Se resolvió el bloqueo: '), v_descripcion, ' (', v_opcion, ').',
               IF(v_estado = 'activo', ' El expediente puede continuar.', '')),
        p_id_usuario, v_notificados);

    COMMIT;

    SELECT 2 AS IdTipoMensaje, IF(v_clase = 'excepcion', 'Excepción cerrada.', 'Bloqueo resuelto.') AS Mensaje;
    SELECT p_id_bloqueador AS id_bloqueador, v_clase AS clase, v_estado AS estado_expediente,
           v_id_doc AS id_documento, CONCAT('doc-', v_id_doc) AS clave_documento, v_notificados AS notificados;
END$$

DELIMITER ;
