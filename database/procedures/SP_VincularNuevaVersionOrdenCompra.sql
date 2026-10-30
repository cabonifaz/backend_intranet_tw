-- HU-23 (Sprint 4) "Generar nueva versión de propuesta": registra en la vinculación la versión nueva que el back creó
-- (SP_CrearNuevaVersionPropuesta) para la propuesta observada. Cuando la versión nueva esté ACEPTADA, el comercial
-- presiona "Validar contra propuesta" en la ficha y la vinculación pasa a la versión nueva.
-- Resultados: 1 mensaje.
DROP PROCEDURE IF EXISTS SP_VincularNuevaVersionOrdenCompra;

DELIMITER $$

CREATE PROCEDURE SP_VincularNuevaVersionOrdenCompra(
    IN p_id_usuario        BIGINT,
    IN p_id_oc             BIGINT,
    IN p_id_propuesta      BIGINT,
    IN p_id_propuesta_nueva BIGINT
)
proc: BEGIN
    DECLARE v_numero VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    IF FN_PermisoAccion(p_id_usuario, 'oc_registrar') = 0 AND FN_PermisoAccion(p_id_usuario, 'oc_editar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para gestionar órdenes de compra.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM oc_propuesta WHERE id_oc = p_id_oc AND id_propuesta = p_id_propuesta AND eliminado_en IS NULL
                     AND estado_validacion = 'observada' AND tipo_observacion = 'nueva_version') THEN
        SELECT 1 AS IdTipoMensaje, 'La vinculación no está observada para generar una nueva versión de la propuesta.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT CONCAT(n.numero, ' v', n.version) INTO v_numero
    FROM propuesta_comercial n
    JOIN propuesta_comercial o ON o.id_propuesta = p_id_propuesta
    WHERE n.id_propuesta = p_id_propuesta_nueva AND n.numero = o.numero AND n.version > o.version;
    IF v_numero IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'La versión nueva no corresponde a la propuesta.' AS Mensaje;
        LEAVE proc;
    END IF;

    UPDATE oc_propuesta SET id_propuesta_nueva_version = p_id_propuesta_nueva, modificado_por = p_id_usuario
    WHERE id_oc = p_id_oc AND id_propuesta = p_id_propuesta AND eliminado_en IS NULL;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion,
                                  id_usuario, registrado_en, metadata)
    VALUES ('orden_compra', p_id_oc, 'nueva_version_propuesta', NULL, NULL,
            CONCAT('Se generó la versión ', v_numero, ' de la propuesta para ajustarla a la OC. Validar contra ella cuando el cliente la acepte.'),
            p_id_usuario, NOW(), JSON_OBJECT('id_propuesta', p_id_propuesta, 'id_propuesta_nueva', p_id_propuesta_nueva));

    SELECT 2 AS IdTipoMensaje, CONCAT('Versión ', v_numero, ' vinculada a la orden de compra.') AS Mensaje;
END$$

DELIMITER ;
