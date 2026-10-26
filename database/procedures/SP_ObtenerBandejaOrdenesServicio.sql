-- HU-41 (Sprint 4) Bandeja consolidada de Órdenes de Servicio y de Metrología (OS / OM).
-- Acceso: os_bandeja (Comercial) u os_bandeja_operaciones (Operaciones, consulta). Los borradores solo los ve Comercial.
-- Estado (grupo de la tarjeta):
--   borrador · emitida · programada (programada, reprogramada) · en_ejecucion (en_ruta, en_ejecucion, pausada,
--   bloqueada) · finalizada · anulada
-- Filtros:
--   p_estado: vacío o todas, o uno de los grupos anteriores (la tarjeta pulsada)
--   p_tipo: vacío o todos, OS u OM
--   p_id_cliente, p_id_responsable (responsable comercial de la orden)
--   p_fecha_desde / p_fecha_hasta (fecha de emisión; los borradores usan su fecha de creación)
--   p_busqueda: N° OS/OM, N° de propuesta, cliente o RUC
--   p_exportar = 1: todas las filas, sin paginar (Exportar XLSX)
-- Las tarjetas se calculan con todos los filtros salvo el de estado.
-- Resultados: 1 mensaje, 2 tarjetas, 3 filas, 4 total, 5 clientes (filtro), 6 responsables (filtro).
DROP PROCEDURE IF EXISTS SP_ObtenerBandejaOrdenesServicio;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerBandejaOrdenesServicio(
    IN p_id_usuario     BIGINT,
    IN p_estado         VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_tipo           VARCHAR(5)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_cliente     BIGINT,
    IN p_id_responsable BIGINT,
    IN p_fecha_desde    DATE,
    IN p_fecha_hasta    DATE,
    IN p_busqueda       VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_pagina         INT,
    IN p_por_pagina     INT,
    IN p_exportar       TINYINT
)
BEGIN
    DECLARE v_comercial   TINYINT DEFAULT 0;
    DECLARE v_operaciones TINYINT DEFAULT 0;
    DECLARE v_guardar     TINYINT DEFAULT 0;
    DECLARE v_anular      TINYINT DEFAULT 0;
    DECLARE v_jefe        TINYINT DEFAULT 0;
    DECLARE v_por_pagina  INT;
    DECLARE v_offset      INT;
    DECLARE v_estado      VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tipo        VARCHAR(5)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_busqueda    VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_inicio_sem  DATE;
    DECLARE v_inicio_mes  DATE;

    SET v_comercial   = FN_PermisoAccion(p_id_usuario, 'os_bandeja');
    SET v_operaciones = FN_PermisoAccion(p_id_usuario, 'os_bandeja_operaciones');

    IF v_comercial = 0 AND v_operaciones = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver las órdenes de servicio.' AS Mensaje;
    ELSE
        SET v_guardar    = FN_PermisoAccion(p_id_usuario, 'os_guardar');
        SET v_anular     = FN_PermisoAccion(p_id_usuario, 'os_anular');
        SET v_jefe       = FN_PermisoAccion(p_id_usuario, 'os_aprobar_edicion');
        SET v_por_pagina = IF(IFNULL(p_por_pagina, 0) < 1, 10, LEAST(p_por_pagina, 100));
        SET v_offset     = (GREATEST(IFNULL(p_pagina, 1), 1) - 1) * v_por_pagina;
        IF IFNULL(p_exportar, 0) = 1 THEN
            SET v_por_pagina = 100000, v_offset = 0;
        END IF;
        SET v_estado     = IF(IFNULL(p_estado, '') = '', 'todas', LOWER(TRIM(p_estado)));
        SET v_tipo       = UPPER(TRIM(IFNULL(p_tipo, '')));
        SET v_busqueda   = TRIM(IFNULL(p_busqueda, ''));
        SET v_inicio_sem = DATE_SUB(CURDATE(), INTERVAL WEEKDAY(CURDATE()) DAY);
        SET v_inicio_mes = DATE_FORMAT(CURDATE(), '%Y-%m-01');

        DROP TEMPORARY TABLE IF EXISTS tmp_os_bandeja;
        CREATE TEMPORARY TABLE tmp_os_bandeja AS
        SELECT os.id_os,
               os.tipo,
               os.numero,
               os.estado,
               CASE os.estado
                   WHEN 'borrador'     THEN 'borrador'
                   WHEN 'emitida'      THEN 'emitida'
                   WHEN 'programada'   THEN 'programada'
                   WHEN 'reprogramada' THEN 'programada'
                   WHEN 'finalizada'   THEN 'finalizada'
                   WHEN 'anulada'      THEN 'anulada'
                   ELSE 'en_ejecucion'
               END                                                               AS estado_grupo,
               COALESCE(os.fecha_emision, os.fecha_creacion, os.creado_en)       AS fecha_emision,
               os.fecha_emision IS NOT NULL                                      AS emitida_registrada,
               os.fecha_ejecucion,
               os.id_cliente,
               c.razon_social,
               c.ruc,
               COALESCE(os.id_propuesta, e.id_propuesta)                         AS id_propuesta,
               os.id_expediente,
               os.id_responsable_comercial                                       AS id_responsable,
               os.creado_en
        FROM orden_servicio os
        LEFT JOIN cliente c            ON c.id_cliente = os.id_cliente
        LEFT JOIN expediente_digital e ON e.id_expediente = os.id_expediente
        WHERE os.eliminado_en IS NULL
          AND (v_comercial = 1 OR os.estado <> 'borrador');

        DROP TEMPORARY TABLE IF EXISTS tmp_os_filtro;
        CREATE TEMPORARY TABLE tmp_os_filtro AS
        SELECT t.*,
               p.numero                                                           AS numero_propuesta,
               p.version                                                          AS version_propuesta,
               NULLIF(TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))), '') AS responsable
        FROM tmp_os_bandeja t
        LEFT JOIN propuesta_comercial p ON p.id_propuesta = t.id_propuesta
        LEFT JOIN usuario u             ON u.id_usuario   = t.id_responsable
        WHERE (v_tipo IN ('', 'TODOS') OR t.tipo = v_tipo)
          AND (IFNULL(p_id_cliente, 0) = 0     OR t.id_cliente     = p_id_cliente)
          AND (IFNULL(p_id_responsable, 0) = 0 OR t.id_responsable = p_id_responsable)
          AND (p_fecha_desde IS NULL OR DATE(t.fecha_emision) >= p_fecha_desde)
          AND (p_fecha_hasta IS NULL OR DATE(t.fecha_emision) <= p_fecha_hasta)
          AND (v_busqueda = ''
               OR t.numero       LIKE CONCAT('%', v_busqueda, '%')
               OR p.numero       LIKE CONCAT('%', v_busqueda, '%')
               OR t.razon_social LIKE CONCAT('%', v_busqueda, '%')
               OR t.ruc          LIKE CONCAT('%', v_busqueda, '%'));

        -- 1. Header
        SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

        -- 2. Tarjetas (con todos los filtros salvo el estado)
        SELECT
            COUNT(*)                                                                         AS total,
            IFNULL(SUM(estado_grupo = 'borrador'), 0)                                        AS borradores,
            IFNULL(SUM(estado_grupo = 'emitida'), 0)                                         AS emitidas,
            IFNULL(SUM(emitida_registrada = 1 AND fecha_emision >= v_inicio_sem), 0)         AS emitidas_semana,
            IFNULL(SUM(estado_grupo = 'programada'), 0)                                      AS programadas,
            IFNULL(SUM(estado_grupo = 'en_ejecucion'), 0)                                    AS en_ejecucion,
            IFNULL(SUM(estado_grupo = 'finalizada'), 0)                                      AS finalizadas,
            IFNULL(SUM(estado_grupo = 'finalizada'
                       AND IFNULL(fecha_ejecucion, DATE(fecha_emision)) >= v_inicio_mes), 0) AS finalizadas_mes,
            IFNULL(SUM(estado_grupo = 'anulada'), 0)                                         AS anuladas
        FROM tmp_os_filtro;

        DROP TEMPORARY TABLE IF EXISTS tmp_os_lista;
        CREATE TEMPORARY TABLE tmp_os_lista AS
        SELECT t.* FROM tmp_os_filtro t
        WHERE v_estado IN ('todas', 'todos') OR t.estado_grupo = v_estado;

        -- 3. Filas
        SELECT
            t.id_os, t.tipo, t.numero, t.estado, t.estado_grupo,
            CASE t.estado
                WHEN 'borrador'     THEN 'Borrador'      WHEN 'emitida'      THEN 'Emitida'
                WHEN 'programada'   THEN 'Programada'    WHEN 'reprogramada' THEN 'Reprogramada'
                WHEN 'en_ruta'      THEN 'En ruta'       WHEN 'en_ejecucion' THEN 'En ejecución'
                WHEN 'pausada'      THEN 'Pausada'       WHEN 'bloqueada'    THEN 'Bloqueada'
                WHEN 'finalizada'   THEN 'Finalizada'    WHEN 'anulada'      THEN 'Anulada'
                ELSE t.estado
            END                                                                          AS estado_label,
            t.fecha_emision, t.emitida_registrada,
            t.id_cliente, t.razon_social, t.ruc,
            t.id_propuesta, t.numero_propuesta, t.version_propuesta,
            t.id_expediente,
            t.id_responsable, t.responsable,
            (SELECT COUNT(*) FROM os_equipo oe
             WHERE oe.id_os = t.id_os AND oe.eliminado_en IS NULL)                       AS n_equipos,
            (SELECT COUNT(*) FROM os_concepto oc
             WHERE oc.id_os = t.id_os AND oc.eliminado_en IS NULL)                       AS n_conceptos,
            sp.id_solicitud                                                               AS id_solicitud_pendiente,
            (sp.id_solicitud IS NOT NULL)                                                 AS solicitud_pendiente,
            (sa.id_solicitud IS NOT NULL)                                                 AS edicion_aprobada,
            -- Acciones según estado y rol
            (v_guardar = 1
             AND ((t.estado = 'borrador' AND (t.id_responsable = p_id_usuario OR t.id_responsable IS NULL OR v_jefe = 1))
                  OR sa.id_solicitud IS NOT NULL))                                        AS puede_editar,
            (v_guardar = 1 AND (t.id_responsable <=> p_id_usuario)
             AND t.estado IN ('emitida', 'programada', 'reprogramada')
             AND sp.id_solicitud IS NULL AND sa.id_solicitud IS NULL)                     AS puede_solicitar_edicion,
            (v_jefe = 1 AND sp.id_solicitud IS NOT NULL
             AND (sp.id_aprobador IS NULL OR sp.id_aprobador = p_id_usuario
                  OR FN_PermisoAccion(p_id_usuario, 'propuesta_seguimiento_todas') = 1)) AS puede_resolver_solicitud,
            (v_anular = 1 AND t.estado IN ('borrador', 'emitida', 'programada', 'reprogramada')) AS puede_anular
        FROM tmp_os_lista t
        LEFT JOIN os_solicitud sp ON sp.id_solicitud = (
                  SELECT MAX(s1.id_solicitud) FROM os_solicitud s1
                  WHERE s1.id_os = t.id_os AND s1.tipo = 'edicion' AND s1.estado = 'pendiente' AND s1.eliminado_en IS NULL)
        LEFT JOIN os_solicitud sa ON sa.id_solicitud = (
                  SELECT MAX(s2.id_solicitud) FROM os_solicitud s2
                  WHERE s2.id_os = t.id_os AND s2.tipo = 'edicion' AND s2.estado = 'aprobada'
                    AND s2.id_solicitante = p_id_usuario AND s2.eliminado_en IS NULL)
        ORDER BY t.fecha_emision DESC, t.id_os DESC
        LIMIT v_por_pagina OFFSET v_offset;

        -- 4. Total
        SELECT COUNT(*) AS total FROM tmp_os_lista;

        DROP TEMPORARY TABLE IF EXISTS tmp_os_lista;
        DROP TEMPORARY TABLE IF EXISTS tmp_os_filtro;

        -- 5. Clientes con OS/OM (filtro)
        SELECT DISTINCT t.id_cliente AS id, t.razon_social AS nombre, t.ruc AS codigo
        FROM tmp_os_bandeja t
        WHERE t.id_cliente IS NOT NULL AND t.razon_social IS NOT NULL
        ORDER BY nombre;

        -- 6. Responsables de OS/OM (filtro)
        SELECT DISTINCT t.id_responsable AS id, CONCAT(u.nombre, ' ', u.apellido) AS nombre, NULL AS codigo
        FROM tmp_os_bandeja t
        JOIN usuario u ON u.id_usuario = t.id_responsable
        ORDER BY nombre;

        DROP TEMPORARY TABLE IF EXISTS tmp_os_bandeja;
    END IF;
END$$

DELIMITER ;
