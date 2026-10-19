-- HU-23 Propuestas aceptadas por el cliente que aún no tienen orden de compra.
-- Alimenta el selector del botón "+ Nueva Orden de Compra" de la bandeja de OC
-- (luego se abre el modal de registro de la HU-22 con la propuesta elegida).
-- Resultados: 1 mensaje, 2 propuestas.
DROP PROCEDURE IF EXISTS SP_ObtenerPropuestasSinOrdenCompra;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerPropuestasSinOrdenCompra(
    IN p_id_usuario BIGINT,
    IN p_busqueda   VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
BEGIN
    DECLARE v_dias_sin_resp INT;
    DECLARE v_meta          INT;
    DECLARE v_sla_horas     INT;
    DECLARE v_alerta_horas  INT;
    DECLARE v_busqueda      VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    IF FN_PermisoAccion(p_id_usuario, 'oc_registrar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para registrar órdenes de compra.' AS Mensaje;
    ELSE
        SET v_busqueda = TRIM(IFNULL(p_busqueda, ''));

        CALL SP_CalcularSeguimientoComercial(p_id_usuario, NULL,
                                             v_dias_sin_resp, v_meta, v_sla_horas, v_alerta_horas);

        SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

        SELECT t.id_propuesta, t.numero, t.version,
               t.id_cliente, c.razon_social, c.ruc,
               t.id_requerimiento, r.numero AS numero_rq,
               t.total, t.id_moneda, m.String3 AS moneda, m.String2 AS moneda_simbolo,
               t.fecha_aceptacion,
               t.id_responsable, CONCAT(u.nombre, ' ', u.apellido) AS responsable
        FROM tmp_seg t
        LEFT JOIN cliente c       ON c.id_cliente       = t.id_cliente
        LEFT JOIN requerimiento r ON r.id_requerimiento = t.id_requerimiento
        LEFT JOIN usuario u       ON u.id_usuario       = t.id_responsable
        LEFT JOIN tabla_maestra m ON m.IdMaestro = 1 AND m.IdEmpresa = 1 AND m.Num1 = t.id_moneda
        WHERE t.estado_seguimiento = 'aceptada' AND t.fecha_primera_oc IS NULL
          AND (v_busqueda = ''
               OR t.numero       LIKE CONCAT('%', v_busqueda, '%')
               OR r.numero       LIKE CONCAT('%', v_busqueda, '%')
               OR c.razon_social LIKE CONCAT('%', v_busqueda, '%')
               OR c.ruc          LIKE CONCAT('%', v_busqueda, '%'))
        ORDER BY t.fecha_aceptacion DESC
        LIMIT 50;

        DROP TEMPORARY TABLE IF EXISTS tmp_seg;
        DROP TEMPORARY TABLE IF EXISTS tmp_seg_base;
    END IF;
END$$

DELIMITER ;
