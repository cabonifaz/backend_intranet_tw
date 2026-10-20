-- Estado consolidado de la orden de compra a partir de sus vinculaciones (HU-25). Uso interno, sin resultados.
--   anulada           la OC fue anulada (no cambia)
--   recibida          OC autogenerada (OC-AUTO), provisional hasta reemplazarla por la OC del cliente
--   validada          todas las vinculaciones validadas
--   validada_parcial  al menos una vinculación validada y al menos una pendiente u observada
--   observada         ninguna vinculación validada
-- Si el estado cambia, lo registra en la auditoría (cambio_estado_oc).
DROP PROCEDURE IF EXISTS SP_RecalcularEstadoOrdenCompra;

DELIMITER $$

CREATE PROCEDURE SP_RecalcularEstadoOrdenCompra(
    IN p_id_oc      BIGINT,
    IN p_id_usuario BIGINT
)
proc: BEGIN
    DECLARE v_estado     VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_auto       TINYINT;
    DECLARE v_total      INT DEFAULT 0;
    DECLARE v_validadas  INT DEFAULT 0;
    DECLARE v_nuevo      VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    SELECT estado, es_autogenerada INTO v_estado, v_auto
    FROM orden_compra WHERE id_oc = p_id_oc AND eliminado_en IS NULL;

    IF v_estado IS NULL OR v_estado = 'anulada' THEN
        LEAVE proc;
    END IF;

    SELECT COUNT(*), IFNULL(SUM(estado_validacion = 'validada'), 0) INTO v_total, v_validadas
    FROM oc_propuesta WHERE id_oc = p_id_oc AND eliminado_en IS NULL;

    SET v_nuevo = CASE
        WHEN v_auto = 1                                THEN 'recibida'
        WHEN v_total > 0 AND v_validadas = v_total     THEN 'validada'
        WHEN v_validadas > 0                           THEN 'validada_parcial'
        ELSE                                                'observada'
    END;

    IF v_nuevo <> v_estado THEN
        UPDATE orden_compra SET estado = v_nuevo, modificado_por = p_id_usuario WHERE id_oc = p_id_oc;

        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion,
                                      id_usuario, registrado_en)
        VALUES ('orden_compra', p_id_oc, 'cambio_estado_oc', v_estado, v_nuevo,
                CONCAT('La orden de compra pasó de ', UPPER(v_estado), ' a ', UPPER(v_nuevo), '.'),
                p_id_usuario, NOW());
    END IF;
END$$

DELIMITER ;
