-- HU-29 Bandeja de Expedientes Digitales (refinamiento Sprint 4). Acción expediente_bandeja.
-- Los expedientes nacen solos con el RQ (no se crean a mano). Una fila por expediente (RQ) con la trazabilidad
-- RQ → Propuesta → OC → OS/OM.
-- Filtros (opcionales):
--   p_estado        tarjeta o estado global: abiertos (tarjeta "Expedientes Activos": todo menos cerrados),
--                   listo_para_avanzar, bloqueado, con_excepcion, sla_vencido, activo (sin bloqueos ni excepciones),
--                   cerrado o todos. Sin estado = abiertos.
--   p_etapa         código de ETAPA_EXPEDIENTE        p_id_cliente     cliente
--   p_area          área responsable de la etapa      p_tipo_propuesta tipo de servicio de la propuesta (tal cual)
--   p_desde/p_hasta fecha de creación del expediente  p_sla            en_plazo, en_riesgo o vencido
--   p_busqueda      N.° RQ, N.° propuesta, cliente o RUC (también N.° de expediente, OC y OS/OM)
-- p_exportar = 1: todas las filas filtradas sin paginar (Exportar XLSX, máx. 5000).
-- Resultados: 1 mensaje · 2 tarjetas · 3 filas · 4 total · 5 estados · 6 etapas · 7 clientes · 8 áreas
--   · 9 tipos de propuesta · 10 estados de SLA
DROP PROCEDURE IF EXISTS SP_ObtenerBandejaExpedientes;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerBandejaExpedientes(
    IN p_id_usuario     BIGINT,
    IN p_estado         VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_etapa          VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_cliente     BIGINT,
    IN p_area           VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_tipo_propuesta VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_desde          DATE,
    IN p_hasta          DATE,
    IN p_sla            VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_busqueda       VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_pagina         INT,
    IN p_por_pagina     INT,
    IN p_exportar       TINYINT
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
    IF p_desde IS NOT NULL AND p_hasta IS NOT NULL AND p_desde > p_hasta THEN
        SELECT 1 AS IdTipoMensaje, 'La fecha desde no puede ser posterior a la fecha hasta.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_estado   = IFNULL(NULLIF(TRIM(p_estado), ''), 'abiertos');
    SET v_busqueda = IF(NULLIF(TRIM(IFNULL(p_busqueda, '')), '') IS NULL, NULL, CONCAT('%', TRIM(p_busqueda), '%'));
    SET v_pagina   = GREATEST(IFNULL(p_pagina, 1), 1);
    SET v_por      = IF(IFNULL(p_exportar, 0) = 1, 5000, IF(IFNULL(p_por_pagina, 0) BETWEEN 1 AND 100, p_por_pagina, 10));
    SET v_desde    = IF(IFNULL(p_exportar, 0) = 1, 0, (v_pagina - 1) * v_por);

    CALL SP_CalcularExpedientes(p_id_usuario, NULL);
    DROP TEMPORARY TABLE IF EXISTS tmp_exp_blq;

    DROP TEMPORARY TABLE IF EXISTS tmp_exp_bandeja;
    CREATE TEMPORARY TABLE tmp_exp_bandeja AS
    SELECT x.*, c.razon_social, c.ruc, a.String1 AS area_nombre,
           CONCAT(u.nombre, ' ', u.apellido) AS responsable,
           CONCAT(ue.nombre, ' ', ue.apellido) AS responsable_etapa,
           (SELECT GROUP_CONCAT(DISTINCT oc.numero_oc ORDER BY oc.id_oc SEPARATOR ', ') FROM orden_compra oc
            JOIN oc_propuesta op ON op.id_oc = oc.id_oc AND op.eliminado_en IS NULL
            JOIN propuesta_comercial po ON po.id_propuesta = op.id_propuesta AND po.id_requerimiento = x.id_requerimiento
            WHERE oc.eliminado_en IS NULL AND oc.estado <> 'anulada' AND oc.reemplazada_por IS NULL) AS numeros_oc
    FROM tmp_exp x
    LEFT JOIN cliente c       ON c.id_cliente = x.id_cliente
    LEFT JOIN tabla_maestra a ON a.IdMaestro = 79 AND a.IdEmpresa = 1 AND a.String2 = x.area
    LEFT JOIN usuario u       ON u.id_usuario = x.id_responsable
    LEFT JOIN usuario ue      ON ue.id_usuario = x.id_responsable_etapa;

    DROP TEMPORARY TABLE IF EXISTS tmp_exp;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Tarjetas (todo el sistema, sin filtros; cada una es un filtro rápido por p_estado)
    SELECT
        IFNULL(SUM(estado <> 'cerrado'), 0)                         AS activos,
        IFNULL(SUM(listo = 1), 0)                                   AS listos_para_avanzar,
        IFNULL(SUM(estado = 'bloqueado'), 0)                        AS bloqueados,
        IFNULL(SUM(estado <> 'cerrado' AND excepciones > 0), 0)     AS con_excepcion,
        IFNULL(SUM(estado <> 'cerrado' AND sla_vencido = 1), 0)     AS sla_vencidos
    FROM tmp_exp_bandeja;

    DROP TEMPORARY TABLE IF EXISTS tmp_exp_filtrado;
    CREATE TEMPORARY TABLE tmp_exp_filtrado AS
    SELECT * FROM tmp_exp_bandeja b
    WHERE (v_estado = 'todos'
           OR (v_estado = 'abiertos'           AND b.estado <> 'cerrado')
           OR (v_estado = 'listo_para_avanzar' AND b.listo = 1)
           OR (v_estado = 'con_excepcion'      AND b.estado <> 'cerrado' AND b.excepciones > 0)
           OR (v_estado = 'sla_vencido'        AND b.estado <> 'cerrado' AND b.sla_vencido = 1)
           OR (v_estado IN ('activo', 'bloqueado', 'cerrado') AND b.estado = v_estado))
      AND (NULLIF(TRIM(IFNULL(p_etapa, '')), '') IS NULL OR b.etapa = TRIM(p_etapa))
      AND (IFNULL(p_id_cliente, 0) = 0 OR b.id_cliente = p_id_cliente)
      AND (NULLIF(TRIM(IFNULL(p_area, '')), '') IS NULL OR b.area = TRIM(p_area))
      AND (NULLIF(TRIM(IFNULL(p_tipo_propuesta, '')), '') IS NULL OR b.tipo_servicio = TRIM(p_tipo_propuesta))
      AND (p_desde IS NULL OR b.fecha_creacion >= p_desde)
      AND (p_hasta IS NULL OR b.fecha_creacion < p_hasta + INTERVAL 1 DAY)
      AND (NULLIF(TRIM(IFNULL(p_sla, '')), '') IS NULL OR b.sla_estado = TRIM(p_sla))
      AND (v_busqueda IS NULL
           OR b.numero_rq LIKE v_busqueda OR b.numero_propuesta LIKE v_busqueda
           OR b.razon_social LIKE v_busqueda OR b.ruc LIKE v_busqueda
           OR b.numero LIKE v_busqueda OR b.numeros_oc LIKE v_busqueda
           OR b.numeros_os LIKE v_busqueda OR b.numeros_om LIKE v_busqueda
           OR EXISTS (SELECT 1 FROM propuesta_comercial po
                      WHERE po.id_requerimiento = b.id_requerimiento AND po.eliminado_en IS NULL AND po.numero LIKE v_busqueda));

    -- 3. Filas: primero lo que requiere atención (bloqueados, SLA vencido, con excepción), luego el más reciente
    SELECT
        f.id_expediente, f.numero, f.id_requerimiento, f.numero_rq,
        f.id_propuesta, f.numero_propuesta, f.version_propuesta, f.estado_propuesta, f.propuestas_otras,
        f.id_cliente, f.razon_social, f.ruc,
        f.cantidad_oc, f.numeros_oc, f.numero_os_om, f.numeros_os, f.numeros_om,
        f.tipo_servicio,
        f.etapa, f.etapa_nombre, f.estado, f.listo, f.progreso,
        f.area, f.area_nombre, f.id_responsable, f.responsable, f.id_responsable_etapa, f.responsable_etapa,
        f.bloqueos, f.excepciones, f.motivo_bloqueo,
        f.inicio_etapa, f.sla_horas, f.fecha_limite, f.sla_estado, f.sla_minutos_restantes,
        f.fecha_creacion, f.dias_transcurridos
    FROM tmp_exp_filtrado f
    ORDER BY (f.estado = 'cerrado'), (f.estado = 'bloqueado') DESC, f.sla_vencido DESC, (f.excepciones > 0) DESC,
             f.id_expediente DESC
    LIMIT v_por OFFSET v_desde;

    -- 4. Total
    SELECT COUNT(*) AS total FROM tmp_exp_filtrado;

    -- 5. Estados globales (select del panel de filtros)
    SELECT v.codigo, v.nombre FROM (
        SELECT 1 AS o, 'activo' AS codigo, 'Activo' AS nombre UNION ALL
        SELECT 2, 'bloqueado',     'Bloqueado'     UNION ALL
        SELECT 3, 'con_excepcion', 'Con excepción' UNION ALL
        SELECT 4, 'cerrado',       'Cerrado'
    ) v ORDER BY v.o;

    -- 6. Etapas (ETAPA_EXPEDIENTE, tal cual)
    SELECT String2 AS codigo, String1 AS nombre
    FROM tabla_maestra WHERE IdMaestro = 97 AND IdEmpresa = 1 AND eliminado_en IS NULL ORDER BY Num1;

    -- 7. Clientes con expedientes
    SELECT DISTINCT b.id_cliente, b.razon_social, b.ruc
    FROM tmp_exp_bandeja b WHERE b.id_cliente IS NOT NULL
    ORDER BY b.razon_social;

    -- 8. Áreas responsables de las etapas (AREA_USUARIO, tal cual)
    SELECT a.String2 AS codigo, a.String1 AS nombre
    FROM tabla_maestra a
    WHERE a.IdMaestro = 79 AND a.IdEmpresa = 1 AND a.eliminado_en IS NULL
      AND a.String2 IN (SELECT et.String3 FROM tabla_maestra et
                        WHERE et.IdMaestro = 97 AND et.IdEmpresa = 1 AND et.eliminado_en IS NULL AND et.String3 IS NOT NULL)
    ORDER BY a.Num1;

    -- 9. Tipos de propuesta (tipo de servicio de las propuestas, tal cual)
    SELECT DISTINCT b.tipo_servicio AS codigo, b.tipo_servicio AS nombre
    FROM tmp_exp_bandeja b WHERE NULLIF(TRIM(IFNULL(b.tipo_servicio, '')), '') IS NOT NULL
    ORDER BY b.tipo_servicio;

    -- 10. Estados de SLA
    SELECT v.codigo, v.nombre FROM (
        SELECT 1 AS o, 'en_plazo' AS codigo, 'En plazo' AS nombre UNION ALL
        SELECT 2, 'en_riesgo', 'En riesgo' UNION ALL
        SELECT 3, 'vencido',   'Vencido'
    ) v ORDER BY v.o;

    DROP TEMPORARY TABLE IF EXISTS tmp_exp_filtrado;
    DROP TEMPORARY TABLE IF EXISTS tmp_exp_bandeja;
END$$

DELIMITER ;
