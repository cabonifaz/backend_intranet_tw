-- HU-17 Bandeja de Seguimiento Comercial.
-- Universo: versión vigente de cada propuesta enviada al cliente (estado 'enviado'),
-- más las aprobadas que ya tienen orden de compra (aceptadas).
-- ALCANCE: el usuario ve las propuestas cuyo responsable pertenece a SU MISMA ÁREA.
--   Con la acción propuesta_seguimiento_todas (admins de Gerencia y TI) ve todas las áreas.
-- ESTADO VISUAL (estado_seguimiento):
--   aceptada        : tiene OC (no anulada) o el último seguimiento cerró con aceptación
--   rechazada       : el último seguimiento cerró con rechazo o sin venta
--   requiere_ajuste : el último resultado registrado es SOLICITA_AJUSTE
--   sin_respuesta   : N días (SEGUIMIENTO_DIAS_SIN_RESPUESTA) sin respuesta efectiva del cliente
--   en_seguimiento  : resto de abiertas
-- PRÓXIMA ACCIÓN: la programada en el último seguimiento activo. Si no hay seguimientos,
--   "Primer seguimiento" a fecha_envio + SLA (CONFIG_SLA propuesta / seguimiento).
--   Aceptada sin OC = Generar orden de compra. OC pendiente de validación = Validar orden de compra.
-- SLA: en_plazo | proximo (dentro de las horas de alerta) | vencido | cumplido | cerrado.
-- Filtro p_estado: vacío o abiertas (default), en_seguimiento, sin_respuesta, requiere_ajuste,
--   vencidos, aceptada, rechazada, oc_pendientes, aceptadas_mes, rechazadas_mes, todas.
-- Resultados: 1 mensaje, 2 KPIs, 3 filas, 4 total, 5 responsables (filtro), 6 parámetros.
DROP PROCEDURE IF EXISTS SP_ObtenerBandejaSeguimiento;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerBandejaSeguimiento(
    IN p_id_usuario     BIGINT,
    IN p_id_responsable BIGINT,
    IN p_estado         VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_busqueda       VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_pagina         INT,
    IN p_por_pagina     INT
)
BEGIN
    DECLARE v_todas           TINYINT DEFAULT 0;
    DECLARE v_area            VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_dias_sin_resp   INT DEFAULT 7;
    DECLARE v_meta            INT DEFAULT 8;
    DECLARE v_sla_horas       INT DEFAULT 48;
    DECLARE v_alerta_horas    INT DEFAULT 24;
    DECLARE v_por_pagina      INT;
    DECLARE v_offset          INT;
    DECLARE v_inicio_mes      DATETIME;
    DECLARE v_inicio_mes_ant  DATETIME;
    DECLARE v_env_mes         INT DEFAULT 0;
    DECLARE v_env_mes_ant     INT DEFAULT 0;
    DECLARE v_rech_mes_ant    INT DEFAULT 0;
    DECLARE v_estado          VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    SET v_todas          = FN_PermisoAccion(p_id_usuario, 'propuesta_seguimiento_todas');
    SET v_por_pagina     = IF(IFNULL(p_por_pagina, 0) < 1, 10, LEAST(p_por_pagina, 100));
    SET v_offset         = (GREATEST(IFNULL(p_pagina, 1), 1) - 1) * v_por_pagina;
    SET v_inicio_mes     = DATE_FORMAT(CURDATE(), '%Y-%m-01');
    SET v_inicio_mes_ant = DATE_FORMAT(CURDATE() - INTERVAL 1 MONTH, '%Y-%m-01');
    SET v_estado         = IF(IFNULL(p_estado, '') = '', 'abiertas', LOWER(p_estado));

    SELECT CAST(IFNULL(MAX(Num2), 7) AS SIGNED) INTO v_dias_sin_resp
    FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROPUESTA' AND String2 = 'SEGUIMIENTO_DIAS_SIN_RESPUESTA';

    SELECT CAST(IFNULL(MAX(Num2), 8) AS SIGNED) INTO v_meta
    FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROPUESTA' AND String2 = 'SEGUIMIENTO_META_ACEPTADAS_MES';

    SELECT CAST(IFNULL(MAX(Num2), 48) AS SIGNED), CAST(IFNULL(MAX(Num3), 24) AS SIGNED)
      INTO v_sla_horas, v_alerta_horas
    FROM tabla_maestra
    WHERE IdMaestro = 49 AND IdEmpresa = 1 AND String1 = 'propuesta' AND String2 = 'seguimiento';

    SELECT area INTO v_area
    FROM usuario WHERE id_usuario = p_id_usuario AND eliminado_en IS NULL AND estado = 'activo' LIMIT 1;

    -- ── Paso 1: universo en alcance con los datos crudos ──────────────────
    DROP TEMPORARY TABLE IF EXISTS tmp_seg_base;
    CREATE TEMPORARY TABLE tmp_seg_base AS
    SELECT
        p.id_propuesta, p.numero, p.version, p.id_requerimiento, p.id_cliente, p.id_contacto,
        p.total, p.id_moneda, p.estado AS estado_propuesta,
        COALESCE(p.fecha_envio, p.modificado_en, p.fecha_creacion) AS fecha_envio,
        COALESCE(p.id_responsable, p.id_creador)                   AS id_responsable,
        (SELECT s.id_seguimiento FROM seguimiento_comercial s
         WHERE s.id_propuesta = p.id_propuesta AND s.eliminado_en IS NULL
         ORDER BY s.fecha_interaccion DESC, s.id_seguimiento DESC LIMIT 1)          AS id_ult_seg,
        (SELECT COUNT(*) FROM seguimiento_comercial s
         WHERE s.id_propuesta = p.id_propuesta AND s.eliminado_en IS NULL)          AS interacciones,
        (SELECT MAX(s.fecha_interaccion) FROM seguimiento_comercial s
         JOIN tabla_maestra rs ON rs.IdMaestro = 27 AND rs.IdEmpresa = 1 AND rs.Num1 = s.id_resultado
         WHERE s.id_propuesta = p.id_propuesta AND s.eliminado_en IS NULL
           AND rs.String2 IN ('CONTACTADO', 'REUNION_AGENDADA', 'SOLICITA_AJUSTE'))  AS fecha_ult_respuesta,
        (SELECT MIN(oc.fecha_registro) FROM orden_compra oc
         WHERE oc.eliminado_en IS NULL AND oc.estado <> 'anulada'
           AND (oc.id_propuesta = p.id_propuesta
                OR oc.id_oc IN (SELECT op.id_oc FROM oc_propuesta op
                                WHERE op.id_propuesta = p.id_propuesta AND op.eliminado_en IS NULL))) AS fecha_primera_oc,
        (SELECT COUNT(*) FROM orden_compra oc
         WHERE oc.eliminado_en IS NULL AND oc.estado = 'pendiente_validacion'
           AND (oc.id_propuesta = p.id_propuesta
                OR oc.id_oc IN (SELECT op.id_oc FROM oc_propuesta op
                                WHERE op.id_propuesta = p.id_propuesta AND op.eliminado_en IS NULL))) AS oc_por_validar
    FROM propuesta_comercial p
    JOIN usuario u ON u.id_usuario = COALESCE(p.id_responsable, p.id_creador)
    WHERE p.eliminado_en IS NULL
      AND p.estado IN ('enviado', 'aprobado')
      AND p.version = (SELECT MAX(p2.version) FROM propuesta_comercial p2
                       WHERE p2.numero = p.numero AND p2.eliminado_en IS NULL)
      AND (v_todas = 1 OR u.area = v_area);

    -- ── Paso 2: estado visual, próxima acción y SLA ───────────────────────
    DROP TEMPORARY TABLE IF EXISTS tmp_seg;
    CREATE TEMPORARY TABLE tmp_seg AS
    SELECT k.*,
        CASE
            WHEN k.estado_seguimiento = 'rechazada' THEN NULL
            WHEN k.estado_seguimiento = 'aceptada' AND k.fecha_primera_oc IS NULL THEN 'GENERAR_OC'
            WHEN k.estado_seguimiento = 'aceptada' AND k.oc_por_validar > 0       THEN 'VALIDAR_OC'
            WHEN k.estado_seguimiento = 'aceptada'                                THEN NULL
            WHEN k.estado_ult_seg IS NULL                                         THEN 'PRIMER_SEGUIMIENTO'
            WHEN k.tipo_accion_codigo IS NOT NULL                                 THEN k.tipo_accion_codigo
            ELSE 'PROGRAMAR_SEGUIMIENTO'
        END AS proxima_accion_codigo,
        CASE
            WHEN k.estado_seguimiento = 'rechazada' THEN NULL
            WHEN k.estado_seguimiento = 'aceptada' AND k.fecha_primera_oc IS NULL THEN 'Generar orden de compra'
            WHEN k.estado_seguimiento = 'aceptada' AND k.oc_por_validar > 0       THEN 'Validar orden de compra'
            WHEN k.estado_seguimiento = 'aceptada'                                THEN NULL
            WHEN k.estado_ult_seg IS NULL                                         THEN 'Primer seguimiento'
            WHEN k.tipo_accion_nombre IS NOT NULL                                 THEN k.tipo_accion_nombre
            ELSE 'Programar seguimiento'
        END AS proxima_accion,
        CASE
            WHEN k.estado_seguimiento = 'rechazada' THEN 'cerrado'
            WHEN k.estado_seguimiento = 'aceptada' AND k.fecha_primera_oc IS NOT NULL
                 AND k.oc_por_validar = 0                          THEN 'cumplido'
            WHEN k.vence_accion IS NULL                            THEN 'en_plazo'
            WHEN NOW() > k.vence_accion                            THEN 'vencido'
            WHEN TIMESTAMPDIFF(HOUR, NOW(), k.vence_accion) <= v_alerta_horas THEN 'proximo'
            ELSE 'en_plazo'
        END AS sla_estado
    FROM (
        SELECT j.*,
            CASE
                WHEN j.fecha_primera_oc IS NOT NULL OR j.estado_ult_seg = 'cerrado_aceptacion' THEN 'aceptada'
                WHEN j.estado_ult_seg IN ('cerrado_rechazo', 'cerrado_sin_venta')             THEN 'rechazada'
                WHEN j.resultado_ult_codigo = 'SOLICITA_AJUSTE'                               THEN 'requiere_ajuste'
                WHEN DATEDIFF(CURDATE(), DATE(COALESCE(j.fecha_ult_respuesta, j.fecha_envio))) >= v_dias_sin_resp
                                                                                               THEN 'sin_respuesta'
                ELSE 'en_seguimiento'
            END AS estado_seguimiento,
            COALESCE(j.fecha_primera_oc,
                     IF(j.estado_ult_seg = 'cerrado_aceptacion', j.fecha_ult_interaccion, NULL)) AS fecha_aceptacion,
            IF(j.estado_ult_seg IN ('cerrado_rechazo', 'cerrado_sin_venta'), j.fecha_ult_interaccion, NULL) AS fecha_rechazo,
            DATEDIFF(CURDATE(), DATE(j.fecha_envio))                                   AS dias_transcurridos,
            DATEDIFF(CURDATE(), DATE(COALESCE(j.fecha_ult_respuesta, j.fecha_envio)))  AS dias_sin_respuesta,
            COALESCE(j.fecha_ult_interaccion, j.fecha_envio)                           AS inicio_sla,
            CASE
                WHEN j.estado_ult_seg IS NULL THEN j.fecha_envio + INTERVAL v_sla_horas HOUR
                WHEN j.estado_ult_seg = 'activo'
                    THEN COALESCE(j.proxima_accion_fecha, j.fecha_ult_interaccion + INTERVAL v_sla_horas HOUR)
                ELSE j.proxima_accion_fecha
            END AS vence_accion
        FROM (
            SELECT b.*,
                s.estado                 AS estado_ult_seg,
                s.fecha_interaccion      AS fecha_ult_interaccion,
                s.proxima_accion_fecha,
                s.id_tipo_proxima_accion,
                s.proxima_accion_detalle,
                s.id_prioridad_accion,
                s.id_canal               AS id_canal_ult,
                s.notas                  AS notas_ult,
                rs.String2               AS resultado_ult_codigo,
                rs.String1               AS resultado_ult,
                ta.String2               AS tipo_accion_codigo,
                ta.String1               AS tipo_accion_nombre
            FROM tmp_seg_base b
            LEFT JOIN seguimiento_comercial s ON s.id_seguimiento = b.id_ult_seg
            LEFT JOIN tabla_maestra rs ON rs.IdMaestro = 27 AND rs.IdEmpresa = 1 AND rs.Num1 = s.id_resultado
            LEFT JOIN tabla_maestra ta ON ta.Descripcion = 'TIPO_ACCION_SEGUIMIENTO' AND ta.IdEmpresa = 1
                                      AND ta.Num1 = s.id_tipo_proxima_accion
            WHERE b.estado_propuesta = 'enviado' OR b.fecha_primera_oc IS NOT NULL
        ) j
    ) k;

    -- Variación de enviadas (mes actual vs. mes anterior) y rechazadas del mes anterior
    SELECT
        IFNULL(SUM(fecha_envio >= v_inicio_mes), 0),
        IFNULL(SUM(fecha_envio >= v_inicio_mes_ant AND fecha_envio < v_inicio_mes), 0),
        IFNULL(SUM(fecha_rechazo >= v_inicio_mes_ant AND fecha_rechazo < v_inicio_mes), 0)
      INTO v_env_mes, v_env_mes_ant, v_rech_mes_ant
    FROM tmp_seg
    WHERE IFNULL(p_id_responsable, 0) = 0 OR id_responsable = p_id_responsable;

    -- 1. Header
    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. KPIs
    SELECT
        IFNULL(SUM(estado_seguimiento IN ('en_seguimiento', 'sin_respuesta', 'requiere_ajuste')), 0) AS en_seguimiento,
        IF(v_env_mes_ant = 0, IF(v_env_mes > 0, 100, 0),
           ROUND((v_env_mes - v_env_mes_ant) * 100 / v_env_mes_ant, 1))                           AS variacion_en_seguimiento_pct,
        IFNULL(SUM(estado_seguimiento = 'sin_respuesta'), 0)                                         AS sin_respuesta,
        IFNULL(SUM(estado_seguimiento IN ('en_seguimiento', 'sin_respuesta', 'requiere_ajuste')
                   AND sla_estado = 'vencido'), 0)                                                    AS seguimientos_vencidos,
        IFNULL(SUM(estado_seguimiento = 'aceptada' AND fecha_aceptacion >= v_inicio_mes), 0)        AS aceptadas_mes,
        v_meta                                                                                       AS meta_aceptadas_mes,
        IFNULL(SUM(estado_seguimiento = 'rechazada' AND fecha_rechazo >= v_inicio_mes), 0)          AS rechazadas_mes,
        v_rech_mes_ant                                                                               AS rechazadas_mes_anterior,
        IFNULL(SUM(estado_seguimiento = 'aceptada'
                   AND (fecha_primera_oc IS NULL OR oc_por_validar > 0)), 0)                         AS oc_pendientes
    FROM tmp_seg
    WHERE IFNULL(p_id_responsable, 0) = 0 OR id_responsable = p_id_responsable;

    -- 3. Filas
    SELECT
        t.id_propuesta, t.numero, t.version,
        t.id_requerimiento, r.numero                      AS numero_rq,
        t.id_cliente, c.razon_social, c.ruc,
        t.id_contacto, co.nombres                         AS contacto, co.cargo AS cargo_contacto,
        co.telefono_movil                                 AS telefono_contacto, co.correo AS correo_contacto,
        t.total, t.id_moneda, m.String3                   AS moneda, m.String2 AS moneda_simbolo,
        t.fecha_envio, t.dias_transcurridos, t.dias_sin_respuesta,
        t.id_responsable, CONCAT(u.nombre, ' ', u.apellido) AS responsable,
        t.interacciones, t.fecha_ult_interaccion,
        t.id_canal_ult, cn.String1                        AS canal_ult,
        t.resultado_ult_codigo, t.resultado_ult,
        t.proxima_accion_codigo, t.proxima_accion, t.proxima_accion_detalle,
        t.vence_accion                                    AS proxima_accion_fecha,
        IF(t.vence_accion IS NULL, NULL, DATEDIFF(DATE(t.vence_accion), CURDATE())) AS dias_para_accion,
        IF(t.vence_accion IS NULL, NULL, TIMESTAMPDIFF(HOUR, NOW(), t.vence_accion)) AS horas_para_accion,
        t.id_prioridad_accion, pr.String1                 AS prioridad_accion, pr.String3 AS prioridad_accion_codigo,
        t.estado_seguimiento, t.estado_propuesta,
        t.sla_estado,
        CASE
            WHEN t.sla_estado = 'cumplido' THEN 100
            WHEN t.sla_estado = 'cerrado'  THEN NULL
            WHEN t.vence_accion IS NULL    THEN 0
            WHEN t.vence_accion <= t.inicio_sla OR NOW() >= t.vence_accion THEN 100
            ELSE LEAST(100, GREATEST(0, ROUND(TIMESTAMPDIFF(MINUTE, t.inicio_sla, NOW()) * 100
                                              / TIMESTAMPDIFF(MINUTE, t.inicio_sla, t.vence_accion))))
        END                                               AS sla_pct,
        t.fecha_aceptacion, t.fecha_rechazo,
        (t.fecha_primera_oc IS NOT NULL)                  AS tiene_oc,
        t.oc_por_validar
    FROM tmp_seg t
    LEFT JOIN requerimiento r     ON r.id_requerimiento = t.id_requerimiento
    LEFT JOIN cliente c           ON c.id_cliente       = t.id_cliente
    LEFT JOIN contacto_cliente co ON co.id_contacto     = t.id_contacto
    LEFT JOIN usuario u           ON u.id_usuario       = t.id_responsable
    LEFT JOIN tabla_maestra m     ON m.IdMaestro  = 1  AND m.IdEmpresa  = 1 AND m.Num1  = t.id_moneda
    LEFT JOIN tabla_maestra cn    ON cn.IdMaestro = 26 AND cn.IdEmpresa = 1 AND cn.Num1 = t.id_canal_ult
    LEFT JOIN tabla_maestra pr    ON pr.IdMaestro = 7  AND pr.IdEmpresa = 1 AND pr.Num1 = t.id_prioridad_accion
    WHERE (IFNULL(p_id_responsable, 0) = 0 OR t.id_responsable = p_id_responsable)
      AND (
           (v_estado = 'abiertas'        AND (t.estado_seguimiento IN ('en_seguimiento', 'sin_respuesta', 'requiere_ajuste')
                                              OR (t.estado_seguimiento = 'aceptada'
                                                  AND (t.fecha_primera_oc IS NULL OR t.oc_por_validar > 0))))
        OR (v_estado = 'en_seguimiento'  AND t.estado_seguimiento = 'en_seguimiento')
        OR (v_estado = 'sin_respuesta'   AND t.estado_seguimiento = 'sin_respuesta')
        OR (v_estado = 'requiere_ajuste' AND t.estado_seguimiento = 'requiere_ajuste')
        OR (v_estado = 'vencidos'        AND t.estado_seguimiento IN ('en_seguimiento', 'sin_respuesta', 'requiere_ajuste')
                                         AND t.sla_estado = 'vencido')
        OR (v_estado = 'aceptada'        AND t.estado_seguimiento = 'aceptada')
        OR (v_estado = 'rechazada'       AND t.estado_seguimiento = 'rechazada')
        OR (v_estado = 'oc_pendientes'   AND t.estado_seguimiento = 'aceptada'
                                         AND (t.fecha_primera_oc IS NULL OR t.oc_por_validar > 0))
        OR (v_estado = 'aceptadas_mes'   AND t.estado_seguimiento = 'aceptada'  AND t.fecha_aceptacion >= v_inicio_mes)
        OR (v_estado = 'rechazadas_mes'  AND t.estado_seguimiento = 'rechazada' AND t.fecha_rechazo    >= v_inicio_mes)
        OR  v_estado = 'todas'
      )
      AND (IFNULL(p_busqueda, '') = ''
           OR t.numero        LIKE CONCAT('%', p_busqueda, '%')
           OR r.numero        LIKE CONCAT('%', p_busqueda, '%')
           OR c.razon_social  LIKE CONCAT('%', p_busqueda, '%')
           OR c.ruc           LIKE CONCAT('%', p_busqueda, '%')
           OR co.nombres      LIKE CONCAT('%', p_busqueda, '%'))
    ORDER BY (t.estado_seguimiento = 'rechazada'),
             CASE t.sla_estado WHEN 'vencido' THEN 1 WHEN 'proximo' THEN 2 WHEN 'en_plazo' THEN 3 ELSE 4 END,
             (t.vence_accion IS NULL), t.vence_accion,
             t.fecha_envio DESC
    LIMIT v_por_pagina OFFSET v_offset;

    -- 4. Total
    SELECT COUNT(*) AS total
    FROM tmp_seg t
    LEFT JOIN requerimiento r     ON r.id_requerimiento = t.id_requerimiento
    LEFT JOIN cliente c           ON c.id_cliente       = t.id_cliente
    LEFT JOIN contacto_cliente co ON co.id_contacto     = t.id_contacto
    WHERE (IFNULL(p_id_responsable, 0) = 0 OR t.id_responsable = p_id_responsable)
      AND (
           (v_estado = 'abiertas'        AND (t.estado_seguimiento IN ('en_seguimiento', 'sin_respuesta', 'requiere_ajuste')
                                              OR (t.estado_seguimiento = 'aceptada'
                                                  AND (t.fecha_primera_oc IS NULL OR t.oc_por_validar > 0))))
        OR (v_estado = 'en_seguimiento'  AND t.estado_seguimiento = 'en_seguimiento')
        OR (v_estado = 'sin_respuesta'   AND t.estado_seguimiento = 'sin_respuesta')
        OR (v_estado = 'requiere_ajuste' AND t.estado_seguimiento = 'requiere_ajuste')
        OR (v_estado = 'vencidos'        AND t.estado_seguimiento IN ('en_seguimiento', 'sin_respuesta', 'requiere_ajuste')
                                         AND t.sla_estado = 'vencido')
        OR (v_estado = 'aceptada'        AND t.estado_seguimiento = 'aceptada')
        OR (v_estado = 'rechazada'       AND t.estado_seguimiento = 'rechazada')
        OR (v_estado = 'oc_pendientes'   AND t.estado_seguimiento = 'aceptada'
                                         AND (t.fecha_primera_oc IS NULL OR t.oc_por_validar > 0))
        OR (v_estado = 'aceptadas_mes'   AND t.estado_seguimiento = 'aceptada'  AND t.fecha_aceptacion >= v_inicio_mes)
        OR (v_estado = 'rechazadas_mes'  AND t.estado_seguimiento = 'rechazada' AND t.fecha_rechazo    >= v_inicio_mes)
        OR  v_estado = 'todas'
      )
      AND (IFNULL(p_busqueda, '') = ''
           OR t.numero        LIKE CONCAT('%', p_busqueda, '%')
           OR r.numero        LIKE CONCAT('%', p_busqueda, '%')
           OR c.razon_social  LIKE CONCAT('%', p_busqueda, '%')
           OR c.ruc           LIKE CONCAT('%', p_busqueda, '%')
           OR co.nombres      LIKE CONCAT('%', p_busqueda, '%'));

    -- 5. Responsables (los que tienen propuestas en la bandeja, tal cual)
    SELECT DISTINCT
        t.id_responsable                  AS id,
        CONCAT(u.nombre, ' ', u.apellido) AS nombre,
        NULL                              AS codigo
    FROM tmp_seg t
    JOIN usuario u ON u.id_usuario = t.id_responsable
    ORDER BY nombre;

    -- 6. Parámetros
    SELECT v_dias_sin_resp AS dias_sin_respuesta,
           v_sla_horas     AS sla_horas,
           v_alerta_horas  AS alerta_horas,
           v_meta          AS meta_aceptadas_mes;

    DROP TEMPORARY TABLE IF EXISTS tmp_seg;
    DROP TEMPORARY TABLE IF EXISTS tmp_seg_base;
END$$

DELIMITER ;
