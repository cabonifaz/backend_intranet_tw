-- HU-17 Bandeja de Seguimiento Comercial.
-- El cálculo (universo, alcance, estado visual, próxima acción y SLA) vive en
-- SP_CalcularSeguimientoComercial, que llena la tabla temporal tmp_seg.
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

    SET v_por_pagina     = IF(IFNULL(p_por_pagina, 0) < 1, 10, LEAST(p_por_pagina, 100));
    SET v_offset         = (GREATEST(IFNULL(p_pagina, 1), 1) - 1) * v_por_pagina;
    SET v_inicio_mes     = DATE_FORMAT(CURDATE(), '%Y-%m-01');
    SET v_inicio_mes_ant = DATE_FORMAT(CURDATE() - INTERVAL 1 MONTH, '%Y-%m-01');
    SET v_estado         = IF(IFNULL(p_estado, '') = '', 'abiertas', LOWER(p_estado));

    CALL SP_CalcularSeguimientoComercial(p_id_usuario, NULL,
                                         v_dias_sin_resp, v_meta, v_sla_horas, v_alerta_horas);

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
