-- ============================================================
-- SP_ObtenerTipoOrdenServicio (Módulo 13 Órdenes de Metrología, HU-61 a HU-65)
-- Devuelve si una orden, una propuesta o una solicitud de edición corresponde a una OS o a una OM. Lo usan los controladores
-- /api/crm/ordenes-metrologia y /api/crm/ordenes-servicio para que cada bandeja solo opere sus propias órdenes. Solo lectura.
--   Prioridad: p_id_solicitud → la orden de la solicitud; p_id_os → la orden; p_id_propuesta → el tipo que tendría la orden
--   (lo define el área del RQ de la propuesta, la misma regla de SP_GuardarOrdenServicio).
-- Resultados: 1 mensaje; 2 { tipo ('OS'|'OM'), id_os (NULL si se consultó una propuesta) }.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerTipoOrdenServicio;

DELIMITER $$
CREATE PROCEDURE SP_ObtenerTipoOrdenServicio(
    IN p_id_os        BIGINT,
    IN p_id_propuesta BIGINT,
    IN p_id_solicitud BIGINT
)
proc: BEGIN
    DECLARE v_tipo  VARCHAR(5) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_id_os BIGINT DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_code = MYSQL_ERRNO, @err_msg = MESSAGE_TEXT;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_solicitud, 0) > 0 THEN
        SELECT os.tipo, os.id_os INTO v_tipo, v_id_os
        FROM os_solicitud s
        JOIN orden_servicio os ON os.id_os = s.id_os AND os.eliminado_en IS NULL
        WHERE s.id_solicitud = p_id_solicitud AND s.eliminado_en IS NULL
        LIMIT 1;
        IF v_tipo IS NULL THEN
            SELECT 1 AS IdTipoMensaje, 'La solicitud de edición no existe.' AS Mensaje;
            LEAVE proc;
        END IF;
    ELSEIF IFNULL(p_id_os, 0) > 0 THEN
        SELECT os.tipo, os.id_os INTO v_tipo, v_id_os
        FROM orden_servicio os
        WHERE os.id_os = p_id_os AND os.eliminado_en IS NULL
        LIMIT 1;
        IF v_tipo IS NULL THEN
            SELECT 1 AS IdTipoMensaje, 'La orden no existe.' AS Mensaje;
            LEAVE proc;
        END IF;
    ELSEIF IFNULL(p_id_propuesta, 0) > 0 THEN
        SELECT IF(IFNULL(a.String1, '') LIKE '%metrolog%', 'OM', 'OS') INTO v_tipo
        FROM propuesta_comercial p
        LEFT JOIN requerimiento r ON r.id_requerimiento = p.id_requerimiento
        LEFT JOIN tabla_maestra a ON a.IdMaestro = 64 AND a.IdEmpresa = 1 AND a.Num1 = r.id_area
        WHERE p.id_propuesta = p_id_propuesta
        LIMIT 1;
        IF v_tipo IS NULL THEN
            SELECT 1 AS IdTipoMensaje, 'La propuesta no existe.' AS Mensaje;
            LEAVE proc;
        END IF;
    ELSE
        SELECT 1 AS IdTipoMensaje, 'Indique la orden, la propuesta o la solicitud.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;
    SELECT v_tipo AS tipo, v_id_os AS id_os;
END$$
DELIMITER ;
