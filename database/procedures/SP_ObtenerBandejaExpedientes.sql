-- HU-29 Bandeja de Expedientes Digitales.
-- Acción expediente_bandeja. Comercial y Operaciones ven todos los expedientes.
-- Filtros (opcionales): p_estado (activo, listo_para_avanzar, bloqueado, con_excepcion, sla_vencido, cerrado,
--   o 'abiertos' = todos menos cerrados), p_etapa (código de ETAPA_EXPEDIENTE), p_id_cliente, p_area (código de área
--   responsable) y p_busqueda (N.° de expediente, RQ, propuesta, OC, OS, OM, cliente o RUC).
-- Sin p_estado se muestran los abiertos.
-- Resultados: 1 mensaje · 2 tarjetas · 3 filas (página) · 4 total · 5 estados · 6 etapas · 7 clientes · 8 áreas
DROP PROCEDURE IF EXISTS SP_ObtenerBandejaExpedientes;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerBandejaExpedientes(
    IN p_id_usuario BIGINT,
    IN p_estado     VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_etapa      VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_cliente BIGINT,
    IN p_area       VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_busqueda   VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_pagina     INT,
    IN p_por_pagina INT
)
proc: BEGIN
    DECLARE v_estado   VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_busqueda VARCHAR(102) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_pagina   INT;
    DECLARE v_por      INT;
    DECLARE v_desde    INT;

    IF FN_PermisoAccion(p_id_usuario, 'expediente_bandeja') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver los expedientes digitales.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_estado   = IFNULL(NULLIF(TRIM(p_estado), ''), 'abiertos');
    SET v_busqueda = IF(NULLIF(TRIM(IFNULL(p_busqueda, '')), '') IS NULL, NULL, CONCAT('%', TRIM(p_busqueda), '%'));
    SET v_pagina   = GREATEST(IFNULL(p_pagina, 1), 1);
    SET v_por      = IF(IFNULL(p_por_pagina, 0) BETWEEN 1 AND 100, p_por_pagina, 10);
    SET v_desde    = (v_pagina - 1) * v_por;

    CALL SP_CalcularExpedientes(p_id_usuario, NULL);

    -- Datos para mostrar y filtrar
    DROP TEMPORARY TABLE IF EXISTS tmp_exp_bandeja;
    CREATE TEMPORARY TABLE tmp_exp_bandeja AS
    SELECT x.*,
           c.razon_social, c.ruc,
           a.String1                                AS area_nombre,
           CONCAT(u.nombre, ' ', u.apellido)        AS responsable,
           pr.String1                               AS prioridad
    FROM tmp_exp x
    LEFT JOIN cliente c       ON c.id_cliente = x.id_cliente
    LEFT JOIN tabla_maestra a ON a.IdMaestro = 79 AND a.IdEmpresa = 1 AND a.String2 = x.area
    LEFT JOIN usuario u       ON u.id_usuario = x.id_responsable
    LEFT JOIN tabla_maestra pr ON pr.IdMaestro = 65 AND pr.IdEmpresa = 1 AND pr.Num1 = x.id_prioridad;

    DROP TEMPORARY TABLE IF EXISTS tmp_exp;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Tarjetas (todas las del sistema, sin filtros)
    SELECT
        IFNULL(SUM(estado <> 'cerrado'), 0)                                           AS activos,
        IFNULL(SUM(estado = 'listo_para_avanzar'), 0)                                 AS listos_para_avanzar,
        IFNULL(SUM(etapa <> 'cerrado' AND bloqueos > 0), 0)                           AS bloqueados,
        IFNULL(SUM(etapa <> 'cerrado' AND excepciones > 0), 0)                        AS con_excepcion,
        IFNULL(SUM(etapa <> 'cerrado' AND sla_vencido = 1), 0)                        AS sla_vencidos,
        IFNULL(SUM(etapa IN ('conformidad', 'facturacion')), 0)                       AS pendientes_cierre
    FROM tmp_exp_bandeja;

    -- Filas filtradas
    DROP TEMPORARY TABLE IF EXISTS tmp_exp_filtrado;
    CREATE TEMPORARY TABLE tmp_exp_filtrado AS
    SELECT * FROM tmp_exp_bandeja b
    WHERE (v_estado = 'todos'
           OR (v_estado = 'abiertos'     AND b.estado <> 'cerrado')
           OR (v_estado = 'bloqueado'    AND b.etapa <> 'cerrado' AND b.bloqueos > 0)
           OR (v_estado = 'con_excepcion' AND b.etapa <> 'cerrado' AND b.excepciones > 0)
           OR (v_estado = 'sla_vencido'  AND b.etapa <> 'cerrado' AND b.sla_vencido = 1)
           OR (v_estado = 'pendiente_cierre' AND b.etapa IN ('conformidad', 'facturacion'))
           OR (v_estado NOT IN ('bloqueado', 'con_excepcion', 'sla_vencido', 'pendiente_cierre') AND b.estado = v_estado))
      AND (NULLIF(TRIM(IFNULL(p_etapa, '')), '') IS NULL OR b.etapa = TRIM(p_etapa))
      AND (IFNULL(p_id_cliente, 0) = 0 OR b.id_cliente = p_id_cliente)
      AND (NULLIF(TRIM(IFNULL(p_area, '')), '') IS NULL OR b.area = TRIM(p_area))
      AND (v_busqueda IS NULL
           OR b.numero LIKE v_busqueda OR b.numero_rq LIKE v_busqueda OR b.numero_propuesta LIKE v_busqueda
           OR b.numeros_oc LIKE v_busqueda OR b.numeros_os LIKE v_busqueda OR b.numeros_om LIKE v_busqueda
           OR b.razon_social LIKE v_busqueda OR b.ruc LIKE v_busqueda);

    -- 3. Filas (los que requieren atención primero: bloqueados, SLA vencido, excepciones, luego el más reciente)
    SELECT
        f.id_expediente, f.numero, f.estado, f.etapa, f.etapa_nombre, f.progreso,
        f.id_cliente, f.razon_social, f.ruc,
        f.id_requerimiento, f.numero_rq,
        f.id_propuesta, IF(f.id_propuesta IS NULL, NULL, CONCAT(f.numero_propuesta, ' v', f.version_propuesta)) AS propuesta,
        f.numeros_oc, f.numeros_os, f.numeros_om,
        f.tipo_servicio,
        f.area, f.area_nombre, f.id_responsable, f.responsable, f.prioridad,
        f.bloqueos, f.excepciones, f.motivo_bloqueo,
        f.inicio_etapa, f.sla_horas, f.fecha_limite, f.sla_estado, f.sla_minutos_restantes,
        f.fecha_creacion
    FROM tmp_exp_filtrado f
    ORDER BY (f.estado = 'cerrado'), (f.bloqueos > 0) DESC, f.sla_vencido DESC, (f.excepciones > 0) DESC,
             f.id_expediente DESC
    LIMIT v_por OFFSET v_desde;

    -- 4. Total
    SELECT COUNT(*) AS total FROM tmp_exp_filtrado;

    -- 5. Estados (para el select)
    SELECT v.codigo, v.nombre FROM (
        SELECT 1 AS o, 'activo' AS codigo, 'Activo' AS nombre UNION ALL
        SELECT 2, 'listo_para_avanzar', 'Listo para avanzar' UNION ALL
        SELECT 3, 'bloqueado',          'Bloqueado'          UNION ALL
        SELECT 4, 'con_excepcion',      'Con excepción'      UNION ALL
        SELECT 5, 'sla_vencido',        'SLA vencido'        UNION ALL
        SELECT 6, 'pendiente_cierre',   'Pendiente de cierre' UNION ALL
        SELECT 7, 'cerrado',            'Cerrado'
    ) v ORDER BY v.o;

    -- 6. Etapas (ETAPA_EXPEDIENTE, tal cual)
    SELECT String2 AS codigo, String1 AS nombre
    FROM tabla_maestra WHERE IdMaestro = 97 AND IdEmpresa = 1 ORDER BY Num1;

    -- 7. Clientes con expedientes
    SELECT DISTINCT b.id_cliente, b.razon_social, b.ruc
    FROM tmp_exp_bandeja b WHERE b.id_cliente IS NOT NULL
    ORDER BY b.razon_social;

    -- 8. Áreas responsables (AREA_USUARIO, tal cual)
    SELECT String2 AS codigo, String1 AS nombre
    FROM tabla_maestra WHERE IdMaestro = 79 AND IdEmpresa = 1 ORDER BY Num1;

    DROP TEMPORARY TABLE IF EXISTS tmp_exp_filtrado;
    DROP TEMPORARY TABLE IF EXISTS tmp_exp_bandeja;
END$$

DELIMITER ;
