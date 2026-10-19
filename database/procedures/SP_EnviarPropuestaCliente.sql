-- Enviar propuesta al cliente (post VB aprobado, HU-10b).
--   Reglas:
--     * La propuesta debe estar en estado 'aprobado' (ya pasó VB).
--     * Debe ser la última versión de la cadena numero/version.
--     * El usuario necesita la acción propuesta_enviar_cliente.
--     * Solo el autor responsable (o quien tenga propuesta_vb_todas) puede enviarla.
--   Efectos:
--     * Estado pasa de 'aprobado' a 'enviado'.
--     * Se registran fecha_envio_cliente y enviado_cliente_por.
--     * Se marca la fila de orden en el seguimiento comercial para activar el pipeline.
--     * Deja auditoría y entrada en historial del requerimiento.
--     * Observaciones 2026-10-15: crea automáticamente la primera acción de seguimiento
--       (Llamada de seguimiento, prioridad Alta, plazo máximo SEGUIMIENTO_PRIMERA_ACCION_MINUTOS = 5 min)
--       a cargo del comercial responsable, con su recordatorio inmediato (seguimiento_recordatorio).
--   Respuesta: header + eco de datos (id, numero, version, estado).
DROP PROCEDURE IF EXISTS SP_EnviarPropuestaCliente;

DELIMITER $$

CREATE PROCEDURE SP_EnviarPropuestaCliente(
    IN p_id_propuesta BIGINT,
    IN p_id_usuario   BIGINT
)
proc: BEGIN
    DECLARE v_estado      VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_numero      VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_version     INT;
    DECLARE v_id_rq       BIGINT;
    DECLARE v_autor       BIGINT;
    DECLARE v_es_ultima   TINYINT DEFAULT 1;
    DECLARE v_usu_nombre  VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_todas       TINYINT DEFAULT 0;
    DECLARE v_plazo_min   INT DEFAULT 5;
    DECLARE v_tipo_accion INT;
    DECLARE v_prioridad   INT;
    DECLARE v_fecha_accion DATETIME;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SELECT estado, numero, version, id_requerimiento, COALESCE(id_responsable, id_creador)
      INTO v_estado, v_numero, v_version, v_id_rq, v_autor
    FROM propuesta_comercial
    WHERE id_propuesta = p_id_propuesta AND eliminado_en IS NULL;

    IF v_estado IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Propuesta no encontrada.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF v_estado <> 'aprobado' THEN
        SELECT 1 AS IdTipoMensaje,
               CONCAT('Solo se puede enviar al cliente una propuesta aprobada por visto bueno. Estado actual: ', v_estado, '.') AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_es_ultima = NOT EXISTS (SELECT 1 FROM propuesta_comercial
                                  WHERE numero = v_numero AND version > v_version AND eliminado_en IS NULL);
    IF v_es_ultima = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Solo se puede enviar la última versión de la propuesta.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF FN_PermisoAccion(p_id_usuario, 'propuesta_enviar_cliente') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tiene permiso para enviar propuestas al cliente.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_todas = FN_PermisoAccion(p_id_usuario, 'propuesta_vb_todas');
    IF p_id_usuario <> v_autor AND v_todas = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Solo el comercial responsable (o gerencia) puede enviar la propuesta al cliente.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT CONCAT(nombre, ' ', apellido) INTO v_usu_nombre FROM usuario WHERE id_usuario = p_id_usuario;

    -- Primera acción de seguimiento: llamada al cliente
    SELECT CAST(IFNULL(MAX(Num2), 5) AS SIGNED) INTO v_plazo_min
    FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROPUESTA' AND String2 = 'SEGUIMIENTO_PRIMERA_ACCION_MINUTOS';
    IF v_plazo_min < 1 THEN
        SET v_plazo_min = 5;
    END IF;

    SELECT MAX(Num1) INTO v_tipo_accion
    FROM tabla_maestra
    WHERE Descripcion = 'TIPO_ACCION_SEGUIMIENTO' AND IdEmpresa = 1 AND String2 = 'LLAMADA' AND eliminado_en IS NULL;

    SELECT MAX(Num1) INTO v_prioridad
    FROM tabla_maestra WHERE IdMaestro = 7 AND IdEmpresa = 1 AND String3 = 'ALTA';

    SET v_fecha_accion = NOW() + INTERVAL v_plazo_min MINUTE;

    START TRANSACTION;

    UPDATE propuesta_comercial
       SET estado              = 'enviado',
           fecha_envio_cliente = NOW(),
           enviado_cliente_por = p_id_usuario,
           primera_accion_fecha          = IF(v_tipo_accion IS NULL, NULL, v_fecha_accion),
           id_tipo_primera_accion        = v_tipo_accion,
           id_prioridad_primera_accion   = IF(v_tipo_accion IS NULL, NULL, v_prioridad),
           id_responsable_primera_accion = IF(v_tipo_accion IS NULL, NULL, v_autor),
           minutos_primera_accion        = IF(v_tipo_accion IS NULL, NULL, v_plazo_min),
           modificado_en       = NOW(),
           modificado_por      = p_id_usuario
     WHERE id_propuesta = p_id_propuesta;

    IF v_id_rq IS NOT NULL THEN
        INSERT INTO historial_requerimiento (id_requerimiento, tipo, tipo_label, icono, descripcion, usuario, fecha, creado_en, creado_por)
        VALUES (v_id_rq, 'propuesta', 'Propuesta enviada al cliente', 'send',
                CONCAT('Propuesta ', v_numero, ' v', v_version, ' enviada al cliente. Entra al pipeline de seguimiento comercial.',
                       IF(v_tipo_accion IS NULL, '',
                          CONCAT(' Primera acción: llamada al cliente antes de las ', DATE_FORMAT(v_fecha_accion, '%H:%i'), '.'))),
                v_usu_nombre, NOW(), NOW(), p_id_usuario);
    END IF;

    -- Recordatorio inmediato de la primera llamada (aviso = plazo, se notifica en la siguiente pasada del worker)
    IF v_tipo_accion IS NOT NULL THEN
        UPDATE seguimiento_recordatorio
        SET estado = 'cancelado', fecha_procesado = NOW(), modificado_por = p_id_usuario
        WHERE id_propuesta = p_id_propuesta AND estado = 'pendiente';

        INSERT INTO seguimiento_recordatorio (
            id_propuesta, origen, id_origen, id_usuario_destino, id_tipo_accion,
            fecha_accion, minutos_antes, fecha_notificar, creado_por)
        VALUES (
            p_id_propuesta, 'envio', p_id_propuesta, v_autor, v_tipo_accion,
            v_fecha_accion, v_plazo_min, NOW(), p_id_usuario);
    END IF;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('propuesta', p_id_propuesta, 'envio_cliente', 'aprobado', 'enviado',
            CONCAT('Propuesta ', v_numero, ' v', v_version, ' enviada al cliente por ', v_usu_nombre, '.'),
            p_id_usuario, NOW(),
            JSON_OBJECT('numero', v_numero, 'version', v_version, 'id_requerimiento', v_id_rq));

    COMMIT;

    SELECT 2 AS IdTipoMensaje, 'Propuesta enviada al cliente.' AS Mensaje;
    SELECT p_id_propuesta AS id_propuesta, v_numero AS numero, v_version AS version, 'enviado' AS estado,
           NOW() AS fecha_envio_cliente, p_id_usuario AS enviado_cliente_por,
           IF(v_tipo_accion IS NULL, NULL, v_fecha_accion) AS primera_accion_fecha;
END$$

DELIMITER ;
