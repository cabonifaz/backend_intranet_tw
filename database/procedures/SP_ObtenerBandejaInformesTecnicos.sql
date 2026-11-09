-- HU-56 (Sprint 5) Revisión Técnica: bandeja de informes de servicio técnico del Supervisor / Jefe de Servicio Técnico.
-- Acceso: rt_bandeja. Alcance y estados: ver SP_ArmarBaseInformes.
-- Filtros:
--   p_grupo: vacío o todos · pendiente_revision · pendiente_precotizacion · revisado_sin_precot · revisado_con_precot
--            · pendientes (las dos primeras) · revisados (las dos últimas)
--   p_busqueda: N° OS, cliente, RUC, técnico, equipo, código TW o N° de serie
--   p_id_tecnico, p_id_cliente, p_con_observaciones (1 = con, 0 = sin, NULL = todos), p_sla_vencido (1 = solo vencidos)
--   p_fecha_desde / p_fecha_hasta: fecha de ejecución
--   p_exportar = 1: todas las filas, sin paginar
-- Las tarjetas se calculan con todos los filtros salvo el de estado. Orden: pendientes primero (los más antiguos arriba),
-- luego los revisados (los más recientes arriba).
-- Resultados: 1 mensaje, 2 tarjetas, 3 filas, 4 total, 5 técnicos (filtro), 6 clientes (filtro).
DROP PROCEDURE IF EXISTS SP_ObtenerBandejaInformesTecnicos;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerBandejaInformesTecnicos(
    IN p_id_usuario        BIGINT,
    IN p_grupo             VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_busqueda          VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_tecnico        BIGINT,
    IN p_id_cliente        BIGINT,
    IN p_con_observaciones TINYINT,
    IN p_sla_vencido       TINYINT,
    IN p_fecha_desde       DATE,
    IN p_fecha_hasta       DATE,
    IN p_pagina            INT,
    IN p_por_pagina        INT,
    IN p_exportar          TINYINT
)
proc: BEGIN
    DECLARE v_grupo      VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_busqueda   VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_por_pagina INT;
    DECLARE v_offset     INT;

    IF FN_PermisoAccion(p_id_usuario, 'rt_bandeja') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver la revisión de informes técnicos.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_grupo    = LOWER(TRIM(IFNULL(p_grupo, '')));
    IF v_grupo = '' THEN SET v_grupo = 'todos'; END IF;
    IF v_grupo NOT IN ('todos', 'pendientes', 'revisados', 'pendiente_revision', 'pendiente_precotizacion',
                       'revisado_sin_precot', 'revisado_con_precot') THEN
        SELECT 1 AS IdTipoMensaje, 'Estado no válido.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF p_fecha_desde IS NOT NULL AND p_fecha_hasta IS NOT NULL AND p_fecha_desde > p_fecha_hasta THEN
        SELECT 1 AS IdTipoMensaje, 'La fecha desde no puede ser posterior a la fecha hasta.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_busqueda   = TRIM(IFNULL(p_busqueda, ''));
    SET v_por_pagina = IF(IFNULL(p_por_pagina, 0) < 1, 10, LEAST(p_por_pagina, 100));
    SET v_offset     = (GREATEST(IFNULL(p_pagina, 1), 1) - 1) * v_por_pagina;
    IF IFNULL(p_exportar, 0) = 1 THEN SET v_por_pagina = 100000, v_offset = 0; END IF;

    CALL SP_ArmarBaseInformes(p_id_usuario, NULL);

    -- Opciones de los filtros (antes de filtrar)
    DROP TEMPORARY TABLE IF EXISTS tmp_rt_opc_tec;
    CREATE TEMPORARY TABLE tmp_rt_opc_tec AS
    SELECT DISTINCT id_tecnico AS id, tecnico AS nombre FROM tmp_rt_base WHERE id_tecnico IS NOT NULL;
    DROP TEMPORARY TABLE IF EXISTS tmp_rt_opc_cli;
    CREATE TEMPORARY TABLE tmp_rt_opc_cli AS
    SELECT DISTINCT id_cliente AS id, razon_social AS nombre FROM tmp_rt_base WHERE id_cliente IS NOT NULL;

    -- Filtros comunes (todo menos el estado)
    DELETE FROM tmp_rt_base
    WHERE NOT ((p_id_tecnico IS NULL OR p_id_tecnico = 0 OR id_tecnico = p_id_tecnico)
           AND (p_id_cliente IS NULL OR p_id_cliente = 0 OR id_cliente = p_id_cliente)
           AND (p_con_observaciones IS NULL OR (p_con_observaciones = 1 AND n_observaciones > 0)
                                            OR (p_con_observaciones = 0 AND n_observaciones = 0))
           AND (IFNULL(p_sla_vencido, 0) = 0 OR sla_vencido = 1)
           AND (p_fecha_desde IS NULL OR fecha_ejecucion >= p_fecha_desde)
           AND (p_fecha_hasta IS NULL OR fecha_ejecucion <= p_fecha_hasta)
           AND (v_busqueda = ''
                OR numero_os    LIKE CONCAT('%', v_busqueda, '%')
                OR razon_social LIKE CONCAT('%', v_busqueda, '%')
                OR ruc          LIKE CONCAT('%', v_busqueda, '%')
                OR tecnico      LIKE CONCAT('%', v_busqueda, '%')
                OR equipo       LIKE CONCAT('%', v_busqueda, '%')
                OR codigo_tw    LIKE CONCAT('%', v_busqueda, '%')
                OR numero_serie LIKE CONCAT('%', v_busqueda, '%')));

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Tarjetas
    SELECT IFNULL(SUM(grupo_estado = 'pendiente_revision'), 0)      AS pendientes_revision,
           IFNULL(SUM(grupo_estado = 'pendiente_precotizacion'), 0) AS pendientes_precotizacion,
           IFNULL(SUM(grupo_estado = 'revisado_sin_precot'), 0)     AS revisados_sin_precot,
           IFNULL(SUM(grupo_estado = 'revisado_con_precot'), 0)     AS revisados_con_precot,
           IFNULL(SUM(sla_vencido = 1), 0)                          AS sla_vencidos,
           MAX(sla_horas)                                           AS sla_horas
    FROM tmp_rt_base;

    DELETE FROM tmp_rt_base
    WHERE NOT (v_grupo = 'todos'
               OR (v_grupo = 'pendientes' AND grupo_estado IN ('pendiente_revision', 'pendiente_precotizacion'))
               OR (v_grupo = 'revisados'  AND grupo_estado IN ('revisado_sin_precot', 'revisado_con_precot'))
               OR grupo_estado = v_grupo);

    -- 3. Filas
    SELECT id_informe, numero_informe, version, id_os, numero_os, tipo_os,
           fecha_ejecucion, id_cliente, razon_social, ruc, sede,
           id_equipo, equipo, codigo_tw, numero_serie, tipo_equipo, tipo_servicio,
           id_tecnico, tecnico,
           n_observaciones, (n_observaciones > 0) AS con_observaciones,
           estado, grupo_estado,
           CASE grupo_estado
               WHEN 'pendiente_revision'      THEN IF(estado = 'en_revision', 'En revisión', 'Pendiente de revisión')
               WHEN 'pendiente_precotizacion' THEN 'Pendiente de precotización'
               WHEN 'revisado_sin_precot'     THEN 'Revisado'
               ELSE 'Revisado con precotización' END                 AS estado_label,
           id_precotizacion, numero_precot, id_propuesta_derivada, numero_propuesta_derivada,
           fecha_envio_revision, horas_espera, sla_horas, sla_vencido,
           fecha_revision, revisor
    FROM tmp_rt_base
    ORDER BY (grupo_estado IN ('revisado_sin_precot', 'revisado_con_precot')),
             IF(grupo_estado IN ('revisado_sin_precot', 'revisado_con_precot'), NULL, fecha_envio_revision),
             fecha_revision DESC, fecha_ejecucion DESC, id_informe DESC
    LIMIT v_por_pagina OFFSET v_offset;

    -- 4. Total
    SELECT COUNT(*) AS total FROM tmp_rt_base;

    DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;

    -- 5. Técnicos y 6. clientes con informes (opciones de los filtros)
    SELECT id, nombre FROM tmp_rt_opc_tec ORDER BY nombre;
    SELECT id, nombre FROM tmp_rt_opc_cli ORDER BY nombre;
    DROP TEMPORARY TABLE IF EXISTS tmp_rt_opc_tec;
    DROP TEMPORARY TABLE IF EXISTS tmp_rt_opc_cli;
END$$

DELIMITER ;
