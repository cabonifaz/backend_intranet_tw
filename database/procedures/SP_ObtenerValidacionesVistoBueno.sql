-- Validaciones previas al visto bueno (HU-14).
--   credito   : línea del cliente (según moneda) vs. propuestas aceptadas (con OC) aún sin facturar.
--   margen    : venta neta vs. precio de costo de los suministros (MARGEN_MINIMO_PCT / MARGEN_ALERTA_PCT).
--               Sin la acción suministro_costo_ver se informa el nivel pero no las cifras.
--   descuento : descuento global vs. DESCUENTO_APROBACION_ESPECIAL.
--   stock     : no disponible hasta integrar inventario.
-- nivel: ok | alerta | error | no_disponible
-- Resultados: 1 mensaje, 2 validaciones, 3 resumen económico (cifras de margen solo con permiso).
DROP PROCEDURE IF EXISTS SP_ObtenerValidacionesVistoBueno;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerValidacionesVistoBueno(
    IN p_id_propuesta BIGINT,
    IN p_id_usuario   BIGINT
)
proc: BEGIN
    DECLARE v_cliente      BIGINT;
    DECLARE v_moneda       INT;
    DECLARE v_simbolo      VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_total        DECIMAL(14,2);
    DECLARE v_desc_global  DECIMAL(14,2);
    DECLARE v_desc_pct     DECIMAL(7,2);
    DECLARE v_linea        DECIMAL(15,2);
    DECLARE v_consumido    DECIMAL(15,2);
    DECLARE v_disponible   DECIMAL(15,2);
    DECLARE v_alerta_cred  DECIMAL(10,2);
    DECLARE v_venta_items  DECIMAL(14,2);
    DECLARE v_venta_costo  DECIMAL(14,2);
    DECLARE v_costo        DECIMAL(14,2);
    DECLARE v_items        INT;
    DECLARE v_sin_costo    INT;
    DECLARE v_venta_neta   DECIMAL(14,2);
    DECLARE v_margen       DECIMAL(7,2);
    DECLARE v_min          DECIMAL(10,2);
    DECLARE v_alerta_mg    DECIMAL(10,2);
    DECLARE v_umbral_desc  DECIMAL(10,2);
    DECLARE v_ver_costo    TINYINT;
    DECLARE v_nivel        VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_detalle      VARCHAR(400) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_nivel_cred   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_det_cred     VARCHAR(400) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    SELECT p.id_cliente, p.id_moneda, p.total, IFNULL(p.descuento_monto, 0), IFNULL(p.descuento_pct, 0)
      INTO v_cliente, v_moneda, v_total, v_desc_global, v_desc_pct
    FROM propuesta_comercial p
    WHERE p.id_propuesta = p_id_propuesta AND p.eliminado_en IS NULL;

    IF v_cliente IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Propuesta no encontrada.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_ver_costo = FN_PermisoAccion(p_id_usuario, 'suministro_costo_ver');
    SELECT IFNULL(String2, '') INTO v_simbolo FROM tabla_maestra WHERE IdMaestro = 1 AND IdEmpresa = 1 AND Num1 = v_moneda LIMIT 1;
    SELECT IFNULL(MAX(CASE WHEN String2 = 'MARGEN_MINIMO_PCT'              THEN Num2 END), 10),
           IFNULL(MAX(CASE WHEN String2 = 'MARGEN_ALERTA_PCT'              THEN Num2 END), 15),
           IFNULL(MAX(CASE WHEN String2 = 'DESCUENTO_APROBACION_ESPECIAL'  THEN Num2 END), 10),
           IFNULL(MAX(CASE WHEN String2 = 'CREDITO_ALERTA_PCT'             THEN Num2 END), 80)
      INTO v_min, v_alerta_mg, v_umbral_desc, v_alerta_cred
    FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROPUESTA';

    -- ── Crédito ─────────────────────────────────────────────────────────
    SELECT CASE v_moneda WHEN 1 THEN linea_credito WHEN 2 THEN linea_credito_usd END
      INTO v_linea FROM cliente WHERE id_cliente = v_cliente;

    SELECT IFNULL(SUM(p.total), 0) INTO v_consumido
    FROM propuesta_comercial p
    WHERE p.id_cliente = v_cliente AND p.id_moneda = v_moneda AND p.eliminado_en IS NULL
      AND p.id_propuesta <> p_id_propuesta
      AND EXISTS (SELECT 1 FROM orden_compra oc
                  WHERE oc.eliminado_en IS NULL AND oc.estado <> 'anulada'
                    AND (oc.id_propuesta = p.id_propuesta
                         OR oc.id_oc IN (SELECT op.id_oc FROM oc_propuesta op
                                         WHERE op.id_propuesta = p.id_propuesta AND op.eliminado_en IS NULL)));

    IF IFNULL(v_linea, 0) <= 0 THEN
        SET v_nivel = 'no_disponible', v_detalle = 'El cliente no tiene línea de crédito registrada en esta moneda.';
    ELSE
        SET v_disponible = v_linea - v_consumido;
        SET v_nivel = CASE WHEN v_total > v_disponible THEN 'error'
                           WHEN v_consumido + v_total > v_linea * v_alerta_cred / 100 THEN 'alerta'
                           ELSE 'ok' END;
        SET v_detalle = CONCAT('Línea disponible: ', v_simbolo, ' ', FORMAT(GREATEST(v_disponible, 0), 2),
                               ' de ', v_simbolo, ' ', FORMAT(v_linea, 2),
                               IF(v_nivel = 'error', '. La propuesta supera la línea disponible.', ''),
                               IF(v_nivel = 'alerta', CONCAT('. Con esta propuesta se usaría más del ', FORMAT(v_alerta_cred, 0), ' % de la línea.'), ''));
    END IF;
    SET v_nivel_cred = v_nivel, v_det_cred = v_detalle;

    -- ── Margen de utilidad ──────────────────────────────────────────────
    -- Unidades facturadas = subtotal / precio unitario (incluye cantidad y frecuencia).
    SELECT COUNT(*),
           IFNULL(SUM(i.subtotal - IFNULL(i.descuento, 0)), 0),
           IFNULL(SUM(CASE WHEN s.precio_costo IS NOT NULL AND s.id_moneda = v_moneda AND i.precio_unitario > 0
                           THEN i.subtotal - IFNULL(i.descuento, 0) END), 0),
           IFNULL(SUM(CASE WHEN s.precio_costo IS NOT NULL AND s.id_moneda = v_moneda AND i.precio_unitario > 0
                           THEN s.precio_costo * i.subtotal / i.precio_unitario END), 0),
           SUM(NOT (s.precio_costo IS NOT NULL AND s.id_moneda = v_moneda AND i.precio_unitario > 0))
      INTO v_items, v_venta_items, v_venta_costo, v_costo, v_sin_costo
    FROM propuesta_item i
    LEFT JOIN suministros s ON s.id_suministro = i.id_catalogo_item
    WHERE i.id_propuesta = p_id_propuesta AND i.eliminado_en IS NULL
      AND IFNULL(i.seccion, 'principal') = 'principal' AND IFNULL(i.es_espaciado, 0) = 0;

    -- El descuento global se reparte en proporción a la venta de cada ítem
    SET v_venta_neta = IF(v_venta_items > 0, v_venta_costo * (1 - v_desc_global / v_venta_items), 0);
    SET v_margen     = IF(v_venta_neta > 0, ROUND((v_venta_neta - v_costo) * 100 / v_venta_neta, 2), NULL);

    IF IFNULL(v_items, 0) = 0 OR v_sin_costo = v_items THEN
        SET v_nivel = 'no_disponible',
            v_detalle = 'Los ítems no tienen precio de costo registrado: no se puede calcular el margen.';
    ELSE
        SET v_nivel = CASE WHEN v_margen < v_min THEN 'error'
                           WHEN v_margen < v_alerta_mg OR v_sin_costo > 0 THEN 'alerta'
                           ELSE 'ok' END;
        SET v_detalle = CONCAT(
            IF(v_ver_costo = 1, CONCAT('Margen (', FORMAT(v_margen, 1), ' %)'), 'Margen'),
            CASE WHEN v_margen < v_min      THEN CONCAT(' por debajo del mínimo aceptable (', FORMAT(v_min, 0), ' %).')
                 WHEN v_margen < v_alerta_mg THEN CONCAT(' cercano al mínimo aceptable (', FORMAT(v_min, 0), ' %). Revise los costos operativos.')
                 ELSE ' dentro de lo esperado.' END,
            IF(v_sin_costo > 0, CONCAT(' ', v_sin_costo, ' de ', v_items, ' ítems sin precio de costo: margen incompleto.'), ''));
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;
    SELECT 1 AS orden, 'credito' AS codigo, 'Crédito cliente' AS etiqueta, v_nivel_cred AS nivel, v_det_cred AS detalle
    UNION ALL
    SELECT 2, 'margen', 'Margen de utilidad', v_nivel, v_detalle
    UNION ALL
    SELECT 3, 'descuento', 'Descuento comercial',
           IF(v_desc_pct > v_umbral_desc, 'alerta', 'ok'),
           IF(v_desc_pct > 0,
              CONCAT('Descuento global de ', FORMAT(v_desc_pct, 1), ' %',
                     IF(v_desc_pct > v_umbral_desc, CONCAT(': supera el ', FORMAT(v_umbral_desc, 0), ' % y requiere aprobación especial.'), '.')),
              'Sin descuento global.')
    UNION ALL
    SELECT 4, 'stock', 'Stock de repuestos', 'no_disponible',
           'Inventario no integrado: verifique la disponibilidad con almacén.';
    SELECT v_moneda AS id_moneda, v_simbolo AS moneda_simbolo, v_total AS total,
           v_linea AS linea_credito, v_consumido AS credito_consumido,
           IF(v_ver_costo = 1, v_venta_neta, NULL) AS venta_con_costo,
           IF(v_ver_costo = 1, v_costo,      NULL) AS costo,
           IF(v_ver_costo = 1, v_margen,     NULL) AS margen_pct,
           v_min AS margen_minimo_pct, v_items AS items, v_sin_costo AS items_sin_costo,
           v_desc_pct AS descuento_pct, v_ver_costo = 1 AS ve_costos;

END$$

DELIMITER ;
