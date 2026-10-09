-- Datos de dos versiones de una misma propuesta para compararlas (HU-14).
-- Las diferencias (agregado / modificado / eliminado) y el riesgo se calculan en el back (C#).
-- Resultados: 1 mensaje, 2 cabeceras (base y destino), 3 ítems, 4 formas de pago,
--             5 equipos, 6 textos, 7 versiones disponibles del mismo número.
DROP PROCEDURE IF EXISTS SP_CompararVersionesPropuesta;

DELIMITER $$

CREATE PROCEDURE SP_CompararVersionesPropuesta(
    IN p_id_base    BIGINT,
    IN p_id_destino BIGINT
)
proc: BEGIN
    DECLARE v_num_base    VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_num_destino VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    SELECT numero INTO v_num_base    FROM propuesta_comercial WHERE id_propuesta = p_id_base    AND eliminado_en IS NULL;
    SELECT numero INTO v_num_destino FROM propuesta_comercial WHERE id_propuesta = p_id_destino AND eliminado_en IS NULL;

    IF v_num_base IS NULL OR v_num_destino IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Una de las versiones no existe.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF v_num_base <> v_num_destino THEN
        SELECT 1 AS IdTipoMensaje, 'Solo se pueden comparar versiones de la misma propuesta.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Cabeceras
    SELECT IF(p.id_propuesta = p_id_base, 'base', 'destino') AS rol,
           p.id_propuesta, p.numero, p.version, p.estado, p.fecha_creacion,
           p.referencia, p.tipo_servicio,
           c.razon_social,
           p.id_moneda, m.String3 AS moneda, m.String2 AS moneda_simbolo,
           p.subtotal, IFNULL(p.descuento_monto, 0) AS descuento_monto, IFNULL(p.descuento_pct, 0) AS descuento_pct,
           IFNULL(p.igv_pct, 0) AS igv_pct, IFNULL(p.igv_monto, 0) AS igv_monto, p.total,
           p.aplica_igv, p.plazo_entrega_dias, p.vigencia_dias,
           (SELECT cp.String1 FROM tabla_maestra cp
            WHERE cp.IdMaestro = 39 AND cp.IdEmpresa = 1 AND cp.Num1 = p.id_condicion_pago LIMIT 1) AS condicion_pago,
           p.descripcion_cambios,
           (SELECT mv.String1 FROM tabla_maestra mv
            WHERE mv.IdEmpresa = 1 AND mv.Descripcion = 'MOTIVO_NUEVA_VERSION' AND mv.Num1 = p.id_motivo_nueva_version
            ORDER BY mv.IdMaestro DESC LIMIT 1) AS motivo_nueva_version
    FROM propuesta_comercial p
    JOIN cliente c ON c.id_cliente = p.id_cliente
    LEFT JOIN tabla_maestra m  ON m.IdMaestro = 1  AND m.IdEmpresa = 1  AND m.Num1 = p.id_moneda
    WHERE p.id_propuesta IN (p_id_base, p_id_destino);

    -- 3. Ítems
    SELECT IF(i.id_propuesta = p_id_base, 'base', 'destino') AS rol,
           i.id_catalogo_item, IFNULL(i.seccion, 'principal') AS seccion, i.descripcion,
           i.cantidad, i.precio_unitario, IFNULL(i.descuento, 0) AS descuento, i.subtotal,
           i.alcance, i.puntos_calibracion, i.frecuencia, i.orden
    FROM propuesta_item i
    WHERE i.id_propuesta IN (p_id_base, p_id_destino) AND i.eliminado_en IS NULL AND IFNULL(i.es_espaciado, 0) = 0
    ORDER BY rol, i.orden;

    -- 4. Formas de pago
    SELECT IF(f.id_propuesta = p_id_base, 'base', 'destino') AS rol, f.porcentaje, f.condicion, f.orden
    FROM propuesta_forma_pago f
    WHERE f.id_propuesta IN (p_id_base, p_id_destino)
    ORDER BY rol, f.orden;

    -- 5. Equipos
    SELECT IF(e.id_propuesta = p_id_base, 'base', 'destino') AS rol,
           e.id_equipo, e.num_serie, e.codigo_tw, e.tipo, e.marca, e.modelo, e.local_sede
    FROM propuesta_equipo e
    WHERE e.id_propuesta IN (p_id_base, p_id_destino)
    ORDER BY rol, e.orden;

    -- 6. Textos
    SELECT IF(t.id_propuesta = p_id_base, 'base', 'destino') AS rol, t.seccion, t.tipo, t.texto, t.orden
    FROM propuesta_texto t
    WHERE t.id_propuesta IN (p_id_base, p_id_destino)
    ORDER BY rol, t.seccion, t.orden;

    -- 7. Versiones disponibles (para los selectores)
    SELECT p.id_propuesta, p.version, p.estado, p.fecha_creacion
    FROM propuesta_comercial p
    WHERE p.numero = v_num_base AND p.eliminado_en IS NULL
    ORDER BY p.version;
END$$

DELIMITER ;
