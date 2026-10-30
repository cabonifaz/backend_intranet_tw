-- HU-23/24 (Sprint 4) Datos de apoyo para la IA (Gemini) de órdenes de compra. Lo usa el back, no la pantalla.
-- p_ids_propuesta: [idPropuesta, ...] (JSON) de las propuestas cuyos conceptos se comparan con la OC (puede ser NULL).
-- Resultados: 1 mensaje, 2 monedas (para traducir la moneda leída del PDF), 3 condiciones de pago, 4 ítems de las
--             propuestas, 5 motivo de nueva versión para "Generar nueva versión de propuesta" (SOLICITUD_CLIENTE).
DROP PROCEDURE IF EXISTS SP_ObtenerDatosIaOrdenCompra;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerDatosIaOrdenCompra(
    IN p_id_usuario     BIGINT,
    IN p_ids_propuesta  JSON
)
BEGIN
    IF FN_PermisoAccion(p_id_usuario, 'oc_bandeja') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver las órdenes de compra.' AS Mensaje;
    ELSE
        SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

        SELECT Num1 AS id, MAX(String1) AS nombre, MAX(String2) AS simbolo, MAX(String3) AS codigo
        FROM tabla_maestra WHERE IdMaestro = 1 AND IdEmpresa = 1 AND eliminado_en IS NULL GROUP BY Num1 ORDER BY Num1;

        SELECT Num1 AS id, MAX(String1) AS nombre, MAX(String2) AS codigo
        FROM tabla_maestra WHERE IdMaestro = 39 AND IdEmpresa = 1 AND eliminado_en IS NULL GROUP BY Num1 ORDER BY Num1;

        SELECT i.id_propuesta, p.numero, p.version, i.descripcion, i.cantidad, i.precio_unitario, i.subtotal,
               NULLIF(TRIM(i.alcance), '') AS alcance, p.id_moneda, (i.seccion = 'opcional') AS opcional
        FROM propuesta_item i
        JOIN propuesta_comercial p ON p.id_propuesta = i.id_propuesta
        WHERE p_ids_propuesta IS NOT NULL AND JSON_TYPE(p_ids_propuesta) = 'ARRAY'
          AND i.id_propuesta IN (SELECT j.id FROM JSON_TABLE(p_ids_propuesta, '$[*]' COLUMNS (id BIGINT PATH '$')) j)
          -- Principales y opcionales (opcional = 1): el cliente puede comprar un opcional; si no lo compra no es error
          AND i.seccion IN ('principal', 'opcional') AND IFNULL(i.es_espaciado, 0) = 0 AND i.eliminado_en IS NULL
        ORDER BY i.id_propuesta, (i.seccion = 'opcional'), i.orden;

        SELECT MAX(Num1) AS id_motivo_nueva_version
        FROM tabla_maestra WHERE IdMaestro = 11 AND IdEmpresa = 1 AND String2 = 'SOLICITUD_CLIENTE' AND eliminado_en IS NULL;
    END IF;
END$$

DELIMITER ;
