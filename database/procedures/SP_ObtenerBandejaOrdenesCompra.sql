-- HU-22 (Sprint 4) Bandeja consolidada de Órdenes de Compra.
-- El cálculo (alcance, montos y estado) vive en SP_CalcularOrdenesCompra (tmp_oc).
-- Filtros:
--   p_estado: vacío o todas, autogenerada, validada, validada_parcial, observada, pendiente_reemplazo, anulada,
--             autogeneradas (alias de autogenerada), sin_asignar (con saldo de OC por asignar)
--   p_incluir_reemplazadas: 1 = incluye las OC ya reemplazadas por la OC del cliente (auditoría). Por defecto se ocultan.
--   p_id_cliente, p_id_responsable, p_id_propuesta (OC vinculadas a esa propuesta),
--   p_fecha_desde / p_fecha_hasta (fecha de emisión de la OC),
--   p_busqueda (N° OC, cliente, RUC, RQ o N° de cualquier propuesta vinculada)
-- Las tarjetas (KPIs) se calculan con todos los filtros salvo el de estado.
-- Resultados: 1 mensaje, 2 tarjetas, 3 monto validado del mes por moneda, 4 filas, 5 total,
--             6 clientes (filtro), 7 responsables (filtro).
DROP PROCEDURE IF EXISTS SP_ObtenerBandejaOrdenesCompra;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerBandejaOrdenesCompra(
    IN p_id_usuario     BIGINT,
    IN p_estado         VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_cliente     BIGINT,
    IN p_id_responsable BIGINT,
    IN p_id_propuesta   BIGINT,
    IN p_fecha_desde    DATE,
    IN p_fecha_hasta    DATE,
    IN p_busqueda       VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_pagina         INT,
    IN p_por_pagina     INT,
    IN p_incluir_reemplazadas TINYINT
)
BEGIN
    DECLARE v_por_pagina INT;
    DECLARE v_offset     INT;
    DECLARE v_estado     VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_busqueda   VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_inicio_mes DATE;

    IF FN_PermisoAccion(p_id_usuario, 'oc_bandeja') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver las órdenes de compra.' AS Mensaje;
    ELSE
        SET v_por_pagina = IF(IFNULL(p_por_pagina, 0) < 1, 10, LEAST(p_por_pagina, 100));
        SET v_offset     = (GREATEST(IFNULL(p_pagina, 1), 1) - 1) * v_por_pagina;
        SET v_estado     = IF(IFNULL(p_estado, '') = '', 'todas', LOWER(TRIM(p_estado)));
        SET v_busqueda   = TRIM(IFNULL(p_busqueda, ''));
        SET v_inicio_mes = DATE_FORMAT(CURDATE(), '%Y-%m-01');

        CALL SP_CalcularOrdenesCompra(p_id_usuario, NULL);

        DROP TEMPORARY TABLE IF EXISTS tmp_oc_filtro;
        CREATE TEMPORARY TABLE tmp_oc_filtro AS
        SELECT t.*,
               c.razon_social, c.ruc,
               r.numero                           AS numero_rq,
               m.String3                          AS moneda, m.String2 AS moneda_simbolo,
               CONCAT(u.nombre, ' ', u.apellido)  AS responsable,
               (SELECT o2.numero_oc FROM orden_compra o2 WHERE o2.id_oc = t.reemplazada_por)    AS numero_oc_reemplazo
        FROM tmp_oc t
        LEFT JOIN cliente c       ON c.id_cliente       = t.id_cliente
        LEFT JOIN requerimiento r ON r.id_requerimiento = t.id_requerimiento
        LEFT JOIN usuario u       ON u.id_usuario       = t.id_responsable
        LEFT JOIN tabla_maestra m ON m.IdMaestro = 1 AND m.IdEmpresa = 1 AND m.Num1 = t.id_moneda
        WHERE (IFNULL(p_incluir_reemplazadas, 0) = 1 OR t.reemplazada_por IS NULL)
          AND (IFNULL(p_id_cliente, 0) = 0     OR t.id_cliente     = p_id_cliente)
          AND (IFNULL(p_id_responsable, 0) = 0 OR t.id_responsable = p_id_responsable)
          AND (IFNULL(p_id_propuesta, 0) = 0
               OR EXISTS (SELECT 1 FROM oc_propuesta op WHERE op.id_oc = t.id_oc AND op.id_propuesta = p_id_propuesta
                            AND op.eliminado_en IS NULL))
          AND (p_fecha_desde IS NULL OR t.fecha_oc >= p_fecha_desde)
          AND (p_fecha_hasta IS NULL OR t.fecha_oc <= p_fecha_hasta)
          AND (v_busqueda = ''
               OR t.numero_oc    LIKE CONCAT('%', v_busqueda, '%')
               OR r.numero       LIKE CONCAT('%', v_busqueda, '%')
               OR c.razon_social LIKE CONCAT('%', v_busqueda, '%')
               OR c.ruc          LIKE CONCAT('%', v_busqueda, '%')
               OR EXISTS (SELECT 1 FROM oc_propuesta op JOIN propuesta_comercial pv ON pv.id_propuesta = op.id_propuesta
                          WHERE op.id_oc = t.id_oc AND op.eliminado_en IS NULL
                            AND pv.numero LIKE CONCAT('%', v_busqueda, '%')));

        -- 1. Header
        SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

        -- 2. Tarjetas
        SELECT
            COUNT(*)                                                                            AS total,
            IFNULL(SUM(fecha_registro >= v_inicio_mes), 0)                                      AS registradas_mes,
            IFNULL(SUM(estado_visual = 'validada'), 0)                                          AS validadas,
            IFNULL(SUM(estado_visual = 'validada_parcial'), 0)                                  AS validadas_parcial,
            IFNULL(SUM(estado_visual = 'observada'), 0)                                         AS observadas,
            IFNULL(SUM(estado_visual IN ('validada_parcial', 'observada')), 0)                  AS parcial_u_observadas,
            IFNULL(SUM(estado = 'autogenerada' AND reemplazada_por IS NULL), 0)                AS autogeneradas_pendientes,
            IFNULL(SUM(estado = 'pendiente_reemplazo' AND reemplazada_por IS NULL), 0)         AS pendientes_reemplazo,
            IFNULL(SUM(estado <> 'anulada' AND reemplazada_por IS NULL AND saldo_oc > 0), 0)   AS sin_asignar,
            IFNULL(SUM(estado_visual = 'anulada'), 0)                                           AS anuladas
        FROM tmp_oc_filtro;

        -- 3. Monto validado del mes por moneda (OC validadas o con validación parcial, emitidas este mes)
        SELECT id_moneda, moneda, moneda_simbolo, SUM(monto_oc) AS monto
        FROM tmp_oc_filtro
        WHERE estado_visual IN ('validada', 'validada_parcial') AND fecha_registro >= v_inicio_mes
        GROUP BY id_moneda, moneda, moneda_simbolo
        ORDER BY id_moneda;

        DROP TEMPORARY TABLE IF EXISTS tmp_oc_lista;
        CREATE TEMPORARY TABLE tmp_oc_lista AS
        SELECT t.* FROM tmp_oc_filtro t
        WHERE v_estado = 'todas'
           OR (v_estado = 'autogeneradas' AND t.estado = 'autogenerada')
           OR (v_estado = 'sin_asignar'   AND t.estado <> 'anulada' AND t.reemplazada_por IS NULL AND t.saldo_oc > 0)
           OR (v_estado IN ('autogenerada', 'validada', 'validada_parcial', 'observada', 'pendiente_reemplazo', 'anulada')
               AND t.estado = v_estado);

        -- 4. Filas
        SELECT
            t.id_oc, t.numero_oc, t.es_autogenerada, t.reemplazada_por, t.numero_oc_reemplazo,
            t.fecha_oc, t.fecha_recepcion, t.fecha_registro,
            t.id_cliente, t.razon_social, t.ruc,
            t.id_requerimiento, t.numero_rq,
            t.id_propuesta, t.numero_propuesta, t.version_propuesta,
            t.propuestas_vinculadas,
            GREATEST(t.propuestas_vinculadas - 1, 0)                                          AS propuestas_adicionales,
            t.id_moneda, t.moneda, t.moneda_simbolo,
            t.monto_oc, t.monto_asignado, t.saldo_oc, t.asignado_pct,
            t.estado, t.estado_visual, t.resultado_ia, t.alertas_ia,
            t.id_responsable, t.responsable,
            t.tiene_pdf,
            IF(t.tiene_pdf = 1, CONCAT('/api/crm/ordenes-compra/', t.id_oc, '/pdf'), NULL)   AS url_pdf,
            (t.estado NOT IN ('anulada', 'autogenerada') AND t.reemplazada_por IS NULL
             AND FN_PermisoAccion(p_id_usuario, 'oc_anular') = 1)                              AS puede_anular,
            (t.pendiente_reemplazo = 1 AND FN_PermisoAccion(p_id_usuario, 'oc_registrar') = 1)  AS puede_reemplazar
        FROM tmp_oc_lista t
        ORDER BY CASE t.estado_visual
                     WHEN 'pendiente_reemplazo' THEN 1 WHEN 'observada' THEN 2 WHEN 'autogenerada' THEN 3
                     WHEN 'validada_parcial' THEN 4 WHEN 'validada' THEN 5 ELSE 6 END,
                 t.fecha_registro DESC, t.id_oc DESC
        LIMIT v_por_pagina OFFSET v_offset;

        -- 5. Total
        SELECT COUNT(*) AS total FROM tmp_oc_lista;

        DROP TEMPORARY TABLE IF EXISTS tmp_oc_lista;
        DROP TEMPORARY TABLE IF EXISTS tmp_oc_filtro;

        -- 6. Clientes con OC (filtro)
        SELECT DISTINCT t.id_cliente AS id, c.razon_social AS nombre, c.ruc AS codigo
        FROM tmp_oc t
        JOIN cliente c ON c.id_cliente = t.id_cliente
        ORDER BY nombre;

        -- 7. Responsables con OC (filtro)
        SELECT DISTINCT t.id_responsable AS id, CONCAT(u.nombre, ' ', u.apellido) AS nombre, NULL AS codigo
        FROM tmp_oc t
        JOIN usuario u ON u.id_usuario = t.id_responsable
        ORDER BY nombre;

        DROP TEMPORARY TABLE IF EXISTS tmp_oc;
    END IF;
END$$

DELIMITER ;
