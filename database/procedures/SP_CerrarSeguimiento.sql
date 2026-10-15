-- HU-21 Cierre del seguimiento comercial: aceptación o rechazo.
-- p_tipo: aceptacion | rechazo. p_solo_validar = 1 valida sin guardar.
-- Observaciones 2026-10-15: el "Cierre sin venta" se eliminó (queda unificado con el Rechazo) y la
--   aceptación lleva evidencia obligatoria. Dos formas de recibirla:
--     a. p_adjuntos con el arreglo JSON de los archivos ya guardados por la API (1 a 5)
--        [{"nombre": "...", "ruta": "...", "tipo": "application/pdf", "tamano": 1234}, ...]
--        y se registran en seguimiento_adjunto en la misma transacción que el cierre.
--     b. p_adjuntos NULL: el front sube la evidencia enseguida con el endpoint de adjuntos del
--        seguimiento (HU-19), como hace hoy el modal de aceptación, que no deja guardar sin archivos.
--   Al cerrar se cancelan los recordatorios pendientes de la propuesta.
-- Reglas comunes: acción propuesta_seguimiento_cerrar, propuesta en seguimiento ABIERTO y del área
--   del usuario. Fecha del cierre (NULL = ahora) no futura ni anterior al envío de la propuesta.
-- Aceptación: tipo de aceptación (TIPO_ACEPTACION_PROPUESTA) y contacto que confirma obligatorios.
--   El seguimiento queda cerrado_aceptacion y la propuesta pasa a la etapa de Órdenes de Compra
--   (próxima acción "Generar orden de compra").
-- Rechazo: motivo (MOTIVO_RECHAZO) y comentario de al menos 20 caracteres. La propuesta pasa a 'rechazado'.
-- Notifica a los supervisores y administradores del área del comercial (y al responsable).
-- Resultados: 1 mensaje, 2 id_seguimiento y estado del seguimiento (solo al guardar).
DROP PROCEDURE IF EXISTS SP_CerrarSeguimiento;

DELIMITER $$

CREATE PROCEDURE SP_CerrarSeguimiento(
    IN p_id_usuario          BIGINT,
    IN p_id_propuesta        BIGINT,
    IN p_tipo                VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_tipo_aceptacion  INT,
    IN p_id_motivo           INT,
    IN p_id_contacto         BIGINT,
    IN p_fecha               DATETIME,
    IN p_comentario          TEXT         CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_adjuntos            LONGTEXT     CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_solo_validar        TINYINT
)
proc: BEGIN
    DECLARE v_dias_sin_resp  INT;
    DECLARE v_meta           INT;
    DECLARE v_sla_horas      INT;
    DECLARE v_alerta_horas   INT;
    DECLARE v_existe         INT DEFAULT 0;
    DECLARE v_abierta        INT DEFAULT 0;
    DECLARE v_id_cliente     BIGINT;
    DECLARE v_id_responsable BIGINT;
    DECLARE v_fecha_envio    DATETIME;
    DECLARE v_numero         VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_version        INT;
    DECLARE v_area           VARCHAR(60)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_comentario     TEXT         CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_fecha          DATETIME;
    DECLARE v_canal          INT;
    DECLARE v_estado_seg     VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_etiqueta       VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_usuario        VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cliente        VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_seguimiento BIGINT;
    DECLARE v_adjuntos       INT DEFAULT 0;
    DECLARE v_adj_invalidos  INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_seg;
        GET DIAGNOSTICS CONDITION 1
            @err_msg  = MESSAGE_TEXT,
            @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje,
               CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SET v_comentario = NULLIF(TRIM(IFNULL(p_comentario, '')), '');
    SET v_fecha      = IFNULL(p_fecha, NOW());

    IF IFNULL(p_tipo, '') NOT IN ('aceptacion', 'rechazo') THEN
        SELECT 1 AS IdTipoMensaje, 'Tipo de cierre no válido.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF FN_PermisoAccion(p_id_usuario, 'propuesta_seguimiento_cerrar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para registrar el cierre del seguimiento.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_CalcularSeguimientoComercial(p_id_usuario, p_id_propuesta,
                                         v_dias_sin_resp, v_meta, v_sla_horas, v_alerta_horas);
    SELECT COUNT(*), MAX(id_cliente), MAX(id_responsable), MAX(fecha_envio), MAX(numero), MAX(version),
           IFNULL(SUM(estado_seguimiento IN ('en_seguimiento', 'sin_respuesta', 'requiere_ajuste')), 0)
      INTO v_existe, v_id_cliente, v_id_responsable, v_fecha_envio, v_numero, v_version, v_abierta
    FROM tmp_seg;
    DROP TEMPORARY TABLE IF EXISTS tmp_seg;

    IF v_existe = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'La propuesta no está en seguimiento comercial o no pertenece a tu área.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_abierta = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El seguimiento de esta propuesta ya está cerrado (aceptada o rechazada).' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Fecha
    IF v_fecha > NOW() + INTERVAL 5 MINUTE THEN
        SELECT 1 AS IdTipoMensaje, 'La fecha del cierre no puede ser futura.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF DATE(v_fecha) < DATE(v_fecha_envio) THEN
        SELECT 1 AS IdTipoMensaje,
               CONCAT('La fecha del cierre no puede ser anterior al envío de la propuesta (',
                      DATE_FORMAT(v_fecha_envio, '%d/%m/%Y'), ').') AS Mensaje;
        LEAVE proc;
    END IF;

    -- Contacto (obligatorio en la aceptación)
    IF p_tipo = 'aceptacion' AND p_id_contacto IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Seleccione el contacto que confirma la aceptación.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF p_id_contacto IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM contacto_cliente
        WHERE id_contacto = p_id_contacto AND id_cliente = v_id_cliente AND SoftDelete = 0) THEN
        SELECT 1 AS IdTipoMensaje, 'El contacto seleccionado no pertenece al cliente de la propuesta.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF p_tipo = 'aceptacion' THEN
        SELECT MAX(t.String1), MAX(c.Num1) INTO v_etiqueta, v_canal
        FROM tabla_maestra t
        LEFT JOIN tabla_maestra c ON c.IdMaestro = 26 AND c.IdEmpresa = 1 AND c.String2 = t.String3
        WHERE t.Descripcion = 'TIPO_ACEPTACION_PROPUESTA' AND t.IdEmpresa = 1 AND t.Num1 = p_id_tipo_aceptacion
          AND t.eliminado_en IS NULL;
        IF v_etiqueta IS NULL THEN
            SELECT 1 AS IdTipoMensaje, 'Seleccione el tipo de aceptación.' AS Mensaje;
            LEAVE proc;
        END IF;
        -- Evidencia obligatoria
        IF p_adjuntos IS NOT NULL AND JSON_VALID(p_adjuntos) = 1 AND JSON_TYPE(p_adjuntos) = 'ARRAY' THEN
            SET v_adjuntos = JSON_LENGTH(p_adjuntos);
            SELECT COUNT(*) INTO v_adj_invalidos
            FROM JSON_TABLE(p_adjuntos, '$[*]' COLUMNS (
                     nombre VARCHAR(255) PATH '$.nombre',
                     ruta   VARCHAR(500) PATH '$.ruta',
                     tipo   VARCHAR(100) PATH '$.tipo',
                     tamano BIGINT       PATH '$.tamano')) a
            WHERE IFNULL(TRIM(a.nombre), '') = '' OR IFNULL(TRIM(a.ruta), '') = ''
               OR IFNULL(TRIM(a.tipo), '') = '' OR IFNULL(a.tamano, 0) <= 0;
        END IF;
        IF v_adjuntos > 5 THEN
            SELECT 1 AS IdTipoMensaje, 'Máximo 5 archivos de evidencia.' AS Mensaje;
            LEAVE proc;
        END IF;
        IF p_adjuntos IS NOT NULL AND (v_adjuntos = 0 OR v_adj_invalidos > 0) THEN
            SELECT 1 AS IdTipoMensaje, 'Los datos de la evidencia adjunta no son válidos.' AS Mensaje;
            LEAVE proc;
        END IF;
        SET v_estado_seg = 'cerrado_aceptacion';

    ELSEIF p_tipo = 'rechazo' THEN
        SELECT MAX(String1) INTO v_etiqueta FROM tabla_maestra
        WHERE IdMaestro = 10 AND IdEmpresa = 1 AND Num1 = p_id_motivo AND eliminado_en IS NULL;
        IF v_etiqueta IS NULL THEN
            SELECT 1 AS IdTipoMensaje, 'Seleccione el motivo del rechazo.' AS Mensaje;
            LEAVE proc;
        END IF;
        IF v_comentario IS NULL OR CHAR_LENGTH(v_comentario) < 20 THEN
            SELECT 1 AS IdTipoMensaje, 'Escriba la justificación del rechazo (mínimo 20 caracteres).' AS Mensaje;
            LEAVE proc;
        END IF;
        SET v_estado_seg = 'cerrado_rechazo';
    END IF;

    IF IFNULL(p_solo_validar, 0) = 1 THEN
        SELECT 2 AS IdTipoMensaje, 'Validado.' AS Mensaje;
        LEAVE proc;
    END IF;

    START TRANSACTION;

    INSERT INTO seguimiento_comercial (
        id_propuesta, id_responsable, id_contacto, id_canal, id_resultado, notas, estado,
        id_motivo_cierre, id_tipo_aceptacion, fecha_interaccion, permite_reactivacion, creado_por)
    VALUES (
        p_id_propuesta, p_id_usuario, p_id_contacto,
        IF(p_tipo = 'aceptacion', v_canal, NULL), NULL, v_comentario, v_estado_seg,
        IF(p_tipo = 'aceptacion', NULL, p_id_motivo),
        IF(p_tipo = 'aceptacion', p_id_tipo_aceptacion, NULL),
        v_fecha,
        0,
        p_id_usuario);

    SET v_id_seguimiento = LAST_INSERT_ID();

    -- Evidencia de la aceptación
    IF p_tipo = 'aceptacion' AND v_adjuntos > 0 THEN
        INSERT INTO seguimiento_adjunto (id_seguimiento, nombre_archivo, ruta, tipo_contenido, tamano_bytes, creado_por)
        SELECT v_id_seguimiento, a.nombre, a.ruta, a.tipo, a.tamano, p_id_usuario
        FROM JSON_TABLE(p_adjuntos, '$[*]' COLUMNS (
                 nombre VARCHAR(255) PATH '$.nombre',
                 ruta   VARCHAR(500) PATH '$.ruta',
                 tipo   VARCHAR(100) PATH '$.tipo',
                 tamano BIGINT       PATH '$.tamano')) a;
    END IF;

    -- El seguimiento se cerró: no quedan recordatorios pendientes
    UPDATE seguimiento_recordatorio
    SET estado = 'cancelado', fecha_procesado = NOW(), modificado_por = p_id_usuario
    WHERE id_propuesta = p_id_propuesta AND estado = 'pendiente';

    -- Rechazo: la propuesta queda rechazada (sale del pipeline y queda para auditoría)
    IF p_tipo = 'rechazo' THEN
        UPDATE propuesta_comercial
        SET estado = 'rechazado', modificado_por = p_id_usuario
        WHERE id_propuesta = p_id_propuesta;
    END IF;

    -- Notificación a supervisores y administradores del área del comercial, y al responsable
    SELECT CONCAT(nombre, ' ', apellido) INTO v_usuario FROM usuario WHERE id_usuario = p_id_usuario;
    SELECT area INTO v_area FROM usuario WHERE id_usuario = v_id_responsable;
    SELECT c.razon_social INTO v_cliente FROM cliente c WHERE c.id_cliente = v_id_cliente;

    INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
    SELECT u.id_usuario, 5,
           CASE p_tipo
               WHEN 'aceptacion' THEN CONCAT('Propuesta aceptada: ', v_numero, ' v', v_version)
               ELSE                   CONCAT('Propuesta rechazada: ', v_numero, ' v', v_version)
           END,
           CASE p_tipo
               WHEN 'aceptacion' THEN CONCAT(IFNULL(v_cliente, 'El cliente'), ' aceptó la propuesta ', v_numero,
                                             ' (', v_etiqueta, '). Registrado por ', v_usuario,
                                             '. Siguiente etapa: Órdenes de Compra.')
               ELSE                   CONCAT(IFNULL(v_cliente, 'El cliente'), ' rechazó la propuesta ', v_numero,
                                             '. Motivo: ', v_etiqueta, '. Registrado por ', v_usuario, '.')
           END,
           'propuesta', p_id_propuesta, NOW(), p_id_usuario
    FROM usuario u
    WHERE u.eliminado_en IS NULL AND u.estado = 'activo' AND u.id_usuario <> p_id_usuario
      AND ((u.area = v_area AND u.rol_sistema IN ('supervisor', 'administrador'))
           OR u.id_usuario = v_id_responsable);

    COMMIT;

    SELECT 2 AS IdTipoMensaje,
           CASE p_tipo
               WHEN 'aceptacion' THEN 'Aceptación registrada. La propuesta pasa a la etapa de Órdenes de Compra.'
               ELSE                   'Rechazo registrado. La propuesta quedó como rechazada.'
           END AS Mensaje;
    SELECT v_id_seguimiento AS id_seguimiento,
           v_adjuntos       AS adjuntos,
           CASE p_tipo WHEN 'aceptacion' THEN 'aceptada' ELSE 'rechazada' END AS estado_seguimiento,
           CASE p_tipo WHEN 'aceptacion' THEN 'ordenes_compra' ELSE NULL END AS siguiente_etapa;
END$$

DELIMITER ;
