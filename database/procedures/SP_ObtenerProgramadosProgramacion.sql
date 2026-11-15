-- HU-35 (Sprint 5) Bandeja de Programación Operativa — tab "Programados": programaciones ya confirmadas por el cliente,
-- listas para ejecutar (insumo del Módulo 11 Control de Campo). Solo lectura. Acceso: prog_bandeja (módulo operaciones).
-- Programado = OS/OM programada o reprogramada con confirmación del cliente y sin solicitud de reprogramación pendiente
--   ni bloqueo SSOMA (esos casos aparecen en Pendientes). Los viáticos salen de gasto_viatico (tipo viatico_asignado):
--   sin_asignar · pendiente_deposito (alguno en estado pendiente) · depositado.
-- Filtros (todos opcionales): p_tipo (OS / OM) · p_id_cliente · p_id_area (área del requerimiento, catálogo 64)
--   p_id_tecnico (principal o de apoyo) · p_id_sede (sede / planta del cliente)
--   p_busqueda (N° OS/OM, N° de propuesta, cliente, RUC o técnico principal / de apoyo)
--   p_rango: vacío o todos · hoy · esta_semana · proxima_semana · personalizado (usa p_fecha_desde / p_fecha_hasta);
--            filtra por la fecha de ejecución.
--   p_exportar = 1: todas las filas hasta 5000, sin paginar (Exportar XLSX)
--   p_zona: región de la sede del cliente (texto exacto de las opciones del resultado 8)
-- Acciones por fila: las mismas reglas que en Pendientes (ver SP_ObtenerPendientesProgramacion).
-- Resultados: 1 mensaje, 2 filas, 3 total, 4 clientes, 5 áreas, 6 técnicos, 7 sedes, 8 zonas (4 a 8 son opciones de filtro).
DROP PROCEDURE IF EXISTS SP_ObtenerProgramadosProgramacion;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerProgramadosProgramacion(
    IN p_id_usuario  BIGINT,
    IN p_rango       VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_fecha_desde DATE,
    IN p_fecha_hasta DATE,
    IN p_tipo        VARCHAR(5)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_cliente  BIGINT,
    IN p_id_area     INT,
    IN p_id_tecnico  BIGINT,
    IN p_id_sede     BIGINT,
    IN p_zona        VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_busqueda    VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_pagina      INT,
    IN p_por_pagina  INT,
    IN p_exportar    TINYINT
)
proc: BEGIN
    DECLARE v_gestionar  TINYINT DEFAULT 0;
    DECLARE v_aprobar    TINYINT DEFAULT 0;
    DECLARE v_detalle    TINYINT DEFAULT 0;
    DECLARE v_anular     TINYINT DEFAULT 0;
    DECLARE v_zona       VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_por_pagina INT;
    DECLARE v_offset     INT;
    DECLARE v_inicio_sem DATE;
    DECLARE v_desde      DATE DEFAULT NULL;
    DECLARE v_hasta      DATE DEFAULT NULL;
    DECLARE v_rango      VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tipo       VARCHAR(5)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_busqueda   VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    IF FN_PermisoAccion(p_id_usuario, 'prog_bandeja') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver la programación operativa.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_gestionar  = FN_PermisoAccion(p_id_usuario, 'prog_gestionar');
    SET v_aprobar    = FN_PermisoAccion(p_id_usuario, 'prog_aprobar_reprogramacion');
    -- "Ver detalle" abre el detalle de la OS/OM: requiere poder consultar órdenes (Comercial u Operaciones)
    SET v_detalle    = IF(FN_PermisoAccion(p_id_usuario, 'os_bandeja') = 1
                          OR FN_PermisoAccion(p_id_usuario, 'os_bandeja_operaciones') = 1, 1, 0);
    -- "Cancelar" es la anulación de la OS/OM (api/crm/ordenes-servicio/{id}/anular): mismo permiso y mismos estados
    SET v_anular     = FN_PermisoAccion(p_id_usuario, 'os_anular');
    SET v_por_pagina = IF(IFNULL(p_por_pagina, 0) < 1, 10, LEAST(p_por_pagina, 100));
    SET v_offset     = (GREATEST(IFNULL(p_pagina, 1), 1) - 1) * v_por_pagina;
    IF IFNULL(p_exportar, 0) = 1 THEN
        SET v_por_pagina = 5000, v_offset = 0;
    END IF;
    SET v_tipo       = UPPER(TRIM(IFNULL(p_tipo, '')));
    SET v_busqueda   = TRIM(IFNULL(p_busqueda, ''));
    SET v_zona       = TRIM(IFNULL(p_zona, ''));
    SET v_rango      = LOWER(TRIM(IFNULL(p_rango, '')));
    SET v_inicio_sem = DATE_SUB(CURDATE(), INTERVAL WEEKDAY(CURDATE()) DAY);

    IF v_rango = 'hoy' THEN
        SET v_desde = CURDATE(), v_hasta = CURDATE();
    ELSEIF v_rango = 'esta_semana' THEN
        SET v_desde = v_inicio_sem, v_hasta = DATE_ADD(v_inicio_sem, INTERVAL 6 DAY);
    ELSEIF v_rango = 'proxima_semana' THEN
        SET v_desde = DATE_ADD(v_inicio_sem, INTERVAL 7 DAY), v_hasta = DATE_ADD(v_inicio_sem, INTERVAL 13 DAY);
    ELSEIF v_rango = 'personalizado' THEN
        SET v_desde = p_fecha_desde, v_hasta = p_fecha_hasta;
    END IF;

    CALL SP_ArmarBaseProgramacion(NULL, NULL);

    CREATE TEMPORARY TABLE tmp_prog_lista AS
    SELECT b.*
    FROM tmp_prog_base b
    WHERE b.sub_estado = 'programado'
      AND (v_desde IS NULL OR b.fecha_ejecucion >= v_desde)
      AND (v_hasta IS NULL OR b.fecha_ejecucion <= v_hasta)
      AND (v_tipo IN ('', 'TODOS') OR b.tipo = v_tipo)
      AND (IFNULL(p_id_cliente, 0) = 0 OR b.id_cliente = p_id_cliente)
      AND (IFNULL(p_id_area, 0)    = 0 OR b.id_area    = p_id_area)
      AND (IFNULL(p_id_tecnico, 0) = 0
           OR b.id_tecnico = p_id_tecnico
           OR EXISTS (SELECT 1 FROM tmp_prog_asig s WHERE s.id_os = b.id_os AND s.id_usuario = p_id_tecnico))
      AND (IFNULL(p_id_sede, 0)    = 0 OR b.id_sede    = p_id_sede)
      AND (v_zona = '' OR b.zona = v_zona)
      AND (v_busqueda = ''
           OR b.numero           LIKE CONCAT('%', v_busqueda, '%')
           OR b.numero_propuesta LIKE CONCAT('%', v_busqueda, '%')
           OR b.razon_social     LIKE CONCAT('%', v_busqueda, '%')
           OR b.ruc              LIKE CONCAT('%', v_busqueda, '%')
           OR b.tecnico          LIKE CONCAT('%', v_busqueda, '%')
           OR b.tecnicos_apoyo   LIKE CONCAT('%', v_busqueda, '%'));

    -- 1. Header
    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Filas
    SELECT
        t.id_os, t.tipo, t.numero, t.estado,
        CASE t.estado
            WHEN 'programada' THEN 'Programada' WHEN 'reprogramada' THEN 'Reprogramada'
            ELSE t.estado
        END                                                                           AS estado_label,
        t.sub_estado,
        'Programado'                                                                  AS sub_estado_label,
        t.id_expediente, t.id_cliente, t.razon_social, t.ruc, t.id_sede, t.sede, t.zona,
        t.id_propuesta, t.numero_propuesta, t.version_propuesta, t.numero_requerimiento, t.id_area, t.area,
        t.id_tecnico, t.tecnico, t.tecnicos_apoyo, t.n_tecnicos,
        t.id_tipo_servicio, t.tipo_servicio, t.ssoma_motivo, t.id_programacion, t.codigo_programacion,
        t.fecha_ejecucion,
        TIME_FORMAT(t.hora_inicio, '%H:%i')                                           AS hora_inicio,
        TIME_FORMAT(t.hora_fin, '%H:%i')                                              AS hora_fin,
        t.horas,
        t.fecha_programada_desde, t.fecha_programada_hasta,
        t.confirmacion_cliente, t.fecha_confirmacion_cliente,
        t.en_conflicto,
        t.id_reprogramacion_pendiente,
        DATEDIFF(CURDATE(), DATE(t.fecha_emision))                                    AS dias_en_espera,
        t.viatico_monto,
        t.viatico_pendiente_monto                                                     AS viatico_pendiente,
        IFNULL(t.viatico_moneda, 'S/')                                                AS viatico_moneda,
        CASE WHEN t.viatico_monto = 0        THEN 'sin_asignar'
             WHEN t.viatico_pendientes > 0   THEN 'pendiente_deposito'
             ELSE 'depositado'
        END                                                                           AS viatico_estado,
        -- Acciones según sub-estado y rol
        (v_gestionar = 1 AND t.sub_estado = 'pendiente_programar')                    AS puede_programar,
        (v_aprobar = 1 AND t.estado IN ('programada', 'reprogramada')
         AND t.id_reprogramacion_pendiente IS NULL)                                   AS puede_reprogramar,
        (v_gestionar = 1 AND v_aprobar = 0 AND t.estado IN ('programada', 'reprogramada')
         AND t.id_reprogramacion_pendiente IS NULL)                                   AS puede_solicitar_reprogramacion,
        (v_aprobar = 1 AND t.id_reprogramacion_pendiente IS NOT NULL)                 AS puede_resolver_reprogramacion,
        (v_anular = 1 AND t.estado IN ('emitida', 'programada', 'reprogramada'))      AS puede_cancelar,
        (v_detalle = 1)                                                               AS puede_ver_detalle
    FROM tmp_prog_lista t
    ORDER BY t.fecha_ejecucion, t.hora_inicio, t.id_os
    LIMIT v_por_pagina OFFSET v_offset;

    -- 3. Total
    SELECT COUNT(*) AS total FROM tmp_prog_lista;

    -- 4. Clientes con programados (filtro)
    SELECT DISTINCT b.id_cliente AS id, b.razon_social AS nombre, b.ruc AS codigo
    FROM tmp_prog_base b
    WHERE b.sub_estado = 'programado'
      AND b.id_cliente IS NOT NULL AND b.razon_social IS NOT NULL
    ORDER BY nombre;

    -- 5. Áreas del requerimiento de los servicios programados (filtro)
    SELECT DISTINCT b.id_area AS id, b.area AS nombre, NULL AS codigo
    FROM tmp_prog_base b
    WHERE b.sub_estado = 'programado'
      AND b.id_area IS NOT NULL AND b.area IS NOT NULL
    ORDER BY nombre;

    -- 6. Técnicos (filtro)
    SELECT t.id_usuario AS id, t.nombre AS nombre, t.cargo AS codigo
    FROM tmp_prog_tecnicos t
    ORDER BY nombre;

    -- 7. Sedes / plantas de los clientes con programados (filtro; el código es el cliente)
    SELECT DISTINCT b.id_sede AS id, b.sede AS nombre, b.razon_social AS codigo
    FROM tmp_prog_base b
    WHERE b.sub_estado = 'programado'
      AND b.id_sede IS NOT NULL AND b.sede IS NOT NULL
    ORDER BY nombre;

    -- 8. Zonas (región de la sede del cliente) de los servicios programados (filtro)
    SELECT DISTINCT NULL AS id, b.zona AS nombre, b.zona AS codigo
    FROM tmp_prog_base b
    WHERE b.sub_estado = 'programado'
      AND b.zona IS NOT NULL
    ORDER BY nombre;

    CALL SP_LimpiarBaseProgramacion();
END$$

DELIMITER ;
