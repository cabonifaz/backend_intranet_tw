-- HU-23 Bandeja de Órdenes de Compra.
-- El cálculo (alcance, montos, cobertura y estado visual) vive en SP_CalcularOrdenesCompra (tmp_oc).
-- Filtros:
--   p_estado: vacío o activas (default, sin anuladas), vigentes, pendiente_validacion, validada,
--             validada_parcial, observada, bloqueada, listas_programacion, vencida, anulada, todas
--   p_cobertura: vacío, completa, con_saldo, insuficiente, moneda_diferente, pendiente
--   p_id_cliente, p_id_responsable, p_fecha_desde / p_fecha_hasta (fecha de la OC),
--   p_con_pdf (NULL todas, 1 con PDF, 0 sin PDF), p_busqueda (N° OC, cliente, RUC, RQ, propuesta)
-- HU-27: las filas traen tipo de OC (principal | complementaria), OC de origen, saldo disponible y faltante.
-- Resultados: 1 mensaje, 2 tarjetas, 3 filas, 4 total, 5 clientes (filtro), 6 responsables (filtro).
DROP PROCEDURE IF EXISTS SP_ObtenerBandejaOrdenesCompra;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerBandejaOrdenesCompra(
    IN p_id_usuario     BIGINT,
    IN p_estado         VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_cobertura      VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_cliente     BIGINT,
    IN p_id_responsable BIGINT,
    IN p_fecha_desde    DATE,
    IN p_fecha_hasta    DATE,
    IN p_con_pdf        TINYINT,
    IN p_busqueda       VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_pagina         INT,
    IN p_por_pagina     INT
)
BEGIN
    DECLARE v_por_pagina INT;
    DECLARE v_offset     INT;
    DECLARE v_estado     VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cobertura  VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_busqueda   VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    IF FN_PermisoAccion(p_id_usuario, 'oc_bandeja') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver las órdenes de compra.' AS Mensaje;
    ELSE
        SET v_por_pagina = IF(IFNULL(p_por_pagina, 0) < 1, 10, LEAST(p_por_pagina, 100));
        SET v_offset     = (GREATEST(IFNULL(p_pagina, 1), 1) - 1) * v_por_pagina;
        SET v_estado     = IF(IFNULL(p_estado, '') = '', 'activas', LOWER(p_estado));
        SET v_cobertura  = LOWER(IFNULL(p_cobertura, ''));
        SET v_busqueda   = TRIM(IFNULL(p_busqueda, ''));

        CALL SP_CalcularOrdenesCompra(p_id_usuario, NULL);

        -- Datos de presentación y filtros comunes (cliente, RQ, moneda, responsable)
        DROP TEMPORARY TABLE IF EXISTS tmp_oc_filtro;
        CREATE TEMPORARY TABLE tmp_oc_filtro AS
        SELECT t.*,
               c.razon_social, c.ruc,
               r.numero                           AS numero_rq,
               m.String3                          AS moneda, m.String2 AS moneda_simbolo,
               CONCAT(u.nombre, ' ', u.apellido)  AS responsable
        FROM tmp_oc t
        LEFT JOIN cliente c       ON c.id_cliente       = t.id_cliente
        LEFT JOIN requerimiento r ON r.id_requerimiento = t.id_requerimiento
        LEFT JOIN usuario u       ON u.id_usuario       = t.id_responsable
        LEFT JOIN tabla_maestra m ON m.IdMaestro = 1 AND m.IdEmpresa = 1 AND m.Num1 = t.id_moneda
        WHERE (IFNULL(p_id_cliente, 0) = 0     OR t.id_cliente     = p_id_cliente)
          AND (IFNULL(p_id_responsable, 0) = 0 OR t.id_responsable = p_id_responsable)
          AND (p_fecha_desde IS NULL OR t.fecha_oc >= p_fecha_desde)
          AND (p_fecha_hasta IS NULL OR t.fecha_oc <= p_fecha_hasta)
          AND (p_con_pdf IS NULL OR t.tiene_pdf = IF(p_con_pdf = 0, 0, 1))
          AND (v_busqueda = ''
               OR t.numero_oc        LIKE CONCAT('%', v_busqueda, '%')
               OR t.numero_propuesta LIKE CONCAT('%', v_busqueda, '%')
               OR r.numero           LIKE CONCAT('%', v_busqueda, '%')
               OR c.razon_social     LIKE CONCAT('%', v_busqueda, '%')
               OR c.ruc              LIKE CONCAT('%', v_busqueda, '%'));

        -- 1. Header
        SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

        -- 2. Tarjetas (sobre las OC en alcance con los filtros de cliente, responsable, fecha, archivo y búsqueda)
        SELECT
            IFNULL(SUM(estado_bd <> 'anulada' AND vencida = 0), 0)                           AS vigentes,
            IFNULL(SUM(estado_bd <> 'anulada' AND vencida = 0 AND cobertura_codigo = 'con_saldo'), 0)    AS cobertura_parcial,
            IFNULL(SUM(estado_bd <> 'anulada' AND vencida = 0 AND cobertura_codigo = 'insuficiente'), 0) AS saldo_insuficiente,
            IFNULL(SUM(estado_visual = 'pendiente_validacion'), 0)                             AS pendientes_validacion,
            IFNULL(SUM(lista_programacion = 1), 0)                                             AS listas_programacion,
            IFNULL(SUM(estado_visual = 'observada'), 0)                                        AS observadas,
            IFNULL(SUM(estado_visual = 'vencida'), 0)                                          AS vencidas,
            IFNULL(SUM(estado_visual = 'liberada'), 0)                                         AS liberadas,
            IFNULL(SUM(estado_bd <> 'anulada' AND cobertura_proyectada IN ('insuficiente', 'moneda_diferente')
                       AND estado_visual = 'pendiente_validacion'), 0)                        AS pendientes_con_alerta
        FROM tmp_oc_filtro;

        -- 3. Filas
        SELECT
            t.id_oc, t.numero_oc, t.fecha_oc, t.fecha_recepcion,
            t.id_cliente, t.razon_social, t.ruc,
            t.id_requerimiento, t.numero_rq,
            t.id_propuesta, t.numero_propuesta, t.version_propuesta,
            t.id_moneda, t.moneda, t.moneda_simbolo,
            t.monto_oc, t.monto_propuesta, t.monto_aplicado, t.saldo,
            t.cobertura_pct, t.utilizacion_pct,
            t.cobertura_codigo, t.cobertura_proyectada,
            t.estado_bd AS estado, t.estado_visual,
            t.vigencia_hasta,
            IF(t.vigencia_hasta IS NULL, NULL, DATEDIFF(t.vigencia_hasta, CURDATE())) AS dias_para_vencer,
            t.id_responsable, t.responsable,
            t.tiene_pdf,
            IF(t.tiene_pdf = 1, CONCAT('/api/crm/ordenes-compra/', t.id_oc, '/pdf'), NULL) AS url_pdf,
            t.lista_programacion,
            t.fecha_registro,
            -- HU-27
            t.tipo_oc, t.id_oc_origen,
            (SELECT o.numero_oc FROM orden_compra o WHERE o.id_oc = t.id_oc_origen) AS numero_oc_origen,
            t.saldo_disponible, t.faltante,
            t.fecha_liberacion
        FROM tmp_oc_filtro t
        WHERE (
               (v_estado = 'activas'              AND t.estado_bd <> 'anulada')
            OR (v_estado = 'vigentes'             AND t.estado_bd <> 'anulada' AND t.vencida = 0)
            OR (v_estado = 'listas_programacion'  AND t.lista_programacion = 1)
            OR (v_estado IN ('pendiente_validacion', 'validada', 'validada_parcial', 'observada',
                             'bloqueada', 'vencida', 'anulada', 'liberada') AND t.estado_visual = v_estado)
            OR  v_estado = 'todas'
          )
          AND (v_cobertura = '' OR t.cobertura_codigo = v_cobertura)
        ORDER BY CASE t.estado_visual
                     WHEN 'pendiente_validacion' THEN 1 WHEN 'observada' THEN 2 WHEN 'bloqueada' THEN 3
                     WHEN 'validada_parcial'     THEN 4 WHEN 'validada'  THEN 5 WHEN 'liberada'  THEN 6 WHEN 'vencida' THEN 7
                     ELSE 7 END,
                 t.fecha_recepcion DESC, t.id_oc DESC
        LIMIT v_por_pagina OFFSET v_offset;

        -- 4. Total
        SELECT COUNT(*) AS total
        FROM tmp_oc_filtro t
        WHERE (
               (v_estado = 'activas'              AND t.estado_bd <> 'anulada')
            OR (v_estado = 'vigentes'             AND t.estado_bd <> 'anulada' AND t.vencida = 0)
            OR (v_estado = 'listas_programacion'  AND t.lista_programacion = 1)
            OR (v_estado IN ('pendiente_validacion', 'validada', 'validada_parcial', 'observada',
                             'bloqueada', 'vencida', 'anulada', 'liberada') AND t.estado_visual = v_estado)
            OR  v_estado = 'todas'
          )
          AND (v_cobertura = '' OR t.cobertura_codigo = v_cobertura);

        DROP TEMPORARY TABLE IF EXISTS tmp_oc_filtro;

        -- 5. Clientes con OC (filtro)
        SELECT DISTINCT t.id_cliente AS id, c.razon_social AS nombre, c.ruc AS codigo
        FROM tmp_oc t
        JOIN cliente c ON c.id_cliente = t.id_cliente
        ORDER BY nombre;

        -- 6. Responsables con OC (filtro)
        SELECT DISTINCT t.id_responsable AS id, CONCAT(u.nombre, ' ', u.apellido) AS nombre, NULL AS codigo
        FROM tmp_oc t
        JOIN usuario u ON u.id_usuario = t.id_responsable
        ORDER BY nombre;

        DROP TEMPORARY TABLE IF EXISTS tmp_oc;
    END IF;
END$$

DELIMITER ;
