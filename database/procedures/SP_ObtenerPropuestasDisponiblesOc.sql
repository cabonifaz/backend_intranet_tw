-- HU-22/23 (Sprint 4) Propuestas aceptadas con saldo por cubrir con órdenes de compra.
-- Alimenta el botón "+ Nueva OC" de la bandeja (p_id_cliente NULL) y "Agregar propuesta vinculada" de la ficha
-- (p_id_cliente = cliente de la OC, p_id_oc = OC que se edita para no descontar su propia asignación).
-- Resultados: 1 mensaje, 2 propuestas.
DROP PROCEDURE IF EXISTS SP_ObtenerPropuestasDisponiblesOc;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerPropuestasDisponiblesOc(
    IN p_id_usuario BIGINT,
    IN p_id_cliente BIGINT,
    IN p_id_oc      BIGINT,
    IN p_busqueda   VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
BEGIN
    DECLARE v_busqueda VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    IF FN_PermisoAccion(p_id_usuario, 'oc_registrar') = 0 AND FN_PermisoAccion(p_id_usuario, 'oc_editar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para registrar órdenes de compra.' AS Mensaje;
    ELSE
        SET v_busqueda = TRIM(IFNULL(p_busqueda, ''));
        CALL SP_CalcularPropuestasDisponiblesOc(p_id_usuario, p_id_cliente, p_id_oc);

        SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

        SELECT d.id_propuesta, d.numero, d.version, d.id_cliente, d.razon_social, d.ruc,
               d.id_requerimiento, d.numero_rq, d.id_contacto, d.contacto,
               d.total, d.saldo, d.id_moneda, d.moneda, d.moneda_simbolo,
               d.fecha_aceptacion, d.id_responsable, d.responsable, d.tipo_servicio,
               EXISTS (SELECT 1 FROM oc_propuesta op JOIN orden_compra oc ON oc.id_oc = op.id_oc
                       WHERE op.id_propuesta = d.id_propuesta AND op.eliminado_en IS NULL
                         AND oc.eliminado_en IS NULL AND oc.estado <> 'anulada')     AS tiene_oc
        FROM tmp_oc_disp d
        WHERE (IFNULL(p_id_oc, 0) = 0
               OR NOT EXISTS (SELECT 1 FROM oc_propuesta op WHERE op.id_oc = p_id_oc AND op.id_propuesta = d.id_propuesta
                                AND op.eliminado_en IS NULL))
          AND (v_busqueda = ''
               OR d.numero       LIKE CONCAT('%', v_busqueda, '%')
               OR d.numero_rq    LIKE CONCAT('%', v_busqueda, '%')
               OR d.razon_social LIKE CONCAT('%', v_busqueda, '%')
               OR d.ruc          LIKE CONCAT('%', v_busqueda, '%'))
        ORDER BY d.fecha_aceptacion DESC
        LIMIT 50;

        DROP TEMPORARY TABLE IF EXISTS tmp_oc_disp;
    END IF;
END$$

DELIMITER ;
