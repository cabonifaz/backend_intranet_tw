-- HU-60 (Sprint 5) CRM › Propuestas › pestaña "Precotizaciones Técnicas": bandeja con tarjetas.
-- Acceso: precot_ver. Alcance: ver SP_ArmarBasePrecotizaciones.
-- Filtros: p_estado (vacío o todas · pendiente · convertida), p_busqueda (RQ, cliente, RUC, supervisor, equipo, OS o N° de
--   precotización), p_id_supervisor, p_fecha_desde / p_fecha_hasta (fecha de recepción).
-- Tarjetas (con todos los filtros salvo el estado):
--   pendientes            enviadas aún sin propuesta ("Requieren tu atención")
--   convertidas_mes       convertidas en propuesta este mes
--   tiempo_promedio_horas horas promedio entre la recepción y la conversión (últimos 90 días), meta 24 h
--   supervisores          cantidad y nombres de los supervisores que generaron precotizaciones
-- Resultados: 1 mensaje, 2 tarjetas, 3 filas, 4 total, 5 supervisores (filtro).
DROP PROCEDURE IF EXISTS SP_ObtenerBandejaPrecotizaciones;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerBandejaPrecotizaciones(
    IN p_id_usuario    BIGINT,
    IN p_estado        VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_busqueda      VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_supervisor BIGINT,
    IN p_fecha_desde   DATE,
    IN p_fecha_hasta   DATE,
    IN p_pagina        INT,
    IN p_por_pagina    INT
)
proc: BEGIN
    DECLARE v_estado     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_busqueda   VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_por_pagina INT;
    DECLARE v_offset     INT;

    IF FN_PermisoAccion(p_id_usuario, 'precot_ver') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver las precotizaciones técnicas.' AS Mensaje;
        LEAVE proc;
    END IF;
    SET v_estado = LOWER(TRIM(IFNULL(p_estado, '')));
    IF v_estado IN ('', 'todas', 'todos') THEN SET v_estado = 'todas'; END IF;
    IF v_estado NOT IN ('todas', 'pendiente', 'convertida') THEN
        SELECT 1 AS IdTipoMensaje, 'Estado no válido: use pendiente, convertida o todas.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF p_fecha_desde IS NOT NULL AND p_fecha_hasta IS NOT NULL AND p_fecha_desde > p_fecha_hasta THEN
        SELECT 1 AS IdTipoMensaje, 'La fecha desde no puede ser posterior a la fecha hasta.' AS Mensaje;
        LEAVE proc;
    END IF;
    SET v_busqueda   = TRIM(IFNULL(p_busqueda, ''));
    SET v_por_pagina = IF(IFNULL(p_por_pagina, 0) < 1, 10, LEAST(p_por_pagina, 100));
    SET v_offset     = (GREATEST(IFNULL(p_pagina, 1), 1) - 1) * v_por_pagina;

    CALL SP_ArmarBasePrecotizaciones(p_id_usuario, NULL);

    DROP TEMPORARY TABLE IF EXISTS tmp_pct_opc;
    CREATE TEMPORARY TABLE tmp_pct_opc AS
    SELECT DISTINCT id_supervisor AS id, supervisor AS nombre FROM tmp_pct_base WHERE id_supervisor IS NOT NULL;

    DELETE FROM tmp_pct_base
    WHERE NOT ((p_id_supervisor IS NULL OR p_id_supervisor = 0 OR id_supervisor = p_id_supervisor)
           AND (p_fecha_desde IS NULL OR DATE(fecha) >= p_fecha_desde)
           AND (p_fecha_hasta IS NULL OR DATE(fecha) <= p_fecha_hasta)
           AND (v_busqueda = ''
                OR numero       LIKE CONCAT('%', v_busqueda, '%')
                OR numero_rq    LIKE CONCAT('%', v_busqueda, '%')
                OR razon_social LIKE CONCAT('%', v_busqueda, '%')
                OR ruc          LIKE CONCAT('%', v_busqueda, '%')
                OR supervisor   LIKE CONCAT('%', v_busqueda, '%')
                OR equipo       LIKE CONCAT('%', v_busqueda, '%')
                OR numero_os    LIKE CONCAT('%', v_busqueda, '%')));

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Tarjetas
    SELECT IFNULL(SUM(estado_grupo = 'pendiente'), 0)                                                    AS pendientes,
           IFNULL(SUM(estado_grupo = 'convertida' AND fecha_conversion >= DATE_FORMAT(CURDATE(), '%Y-%m-01')), 0) AS convertidas_mes,
           ROUND(AVG(IF(fecha_conversion >= CURDATE() - INTERVAL 90 DAY, horas_atencion, NULL)), 1)          AS tiempo_promedio_horas,
           24                                                                                            AS meta_horas,
           COUNT(DISTINCT id_supervisor)                                                                 AS supervisores,
           GROUP_CONCAT(DISTINCT SUBSTRING_INDEX(supervisor, ' ', 1) ORDER BY supervisor SEPARATOR ', ')  AS nombres_supervisores
    FROM tmp_pct_base;

    DELETE FROM tmp_pct_base WHERE NOT (v_estado = 'todas' OR estado_grupo = v_estado);

    -- 3. Filas (pendientes primero, más recientes arriba)
    SELECT id_precotizacion, numero, fecha, id_requerimiento, numero_rq, id_cliente, razon_social, ruc, sede,
           id_equipo, equipo, id_supervisor, supervisor, items, observaciones, estado, estado_grupo, estado_label,
           id_os, numero_os, id_informe, id_propuesta_generada, numero_propuesta_generada, version_propuesta_generada
    FROM tmp_pct_base
    ORDER BY (estado_grupo = 'convertida'), fecha DESC, id_precotizacion DESC
    LIMIT v_por_pagina OFFSET v_offset;

    -- 4. Total
    SELECT COUNT(*) AS total FROM tmp_pct_base;

    -- 5. Supervisores (filtro)
    SELECT id, nombre FROM tmp_pct_opc ORDER BY nombre;

    DROP TEMPORARY TABLE IF EXISTS tmp_pct_opc;
    DROP TEMPORARY TABLE IF EXISTS tmp_pct_base;
END$$

DELIMITER ;
