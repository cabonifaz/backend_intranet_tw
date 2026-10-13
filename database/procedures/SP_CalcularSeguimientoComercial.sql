-- HU-17 / HU-18 — Cálculo común del seguimiento comercial (sin result sets).
-- Llena la tabla temporal tmp_seg (una fila por propuesta en seguimiento y en alcance del usuario)
-- con el estado visual, la próxima acción y el SLA. La usan SP_ObtenerBandejaSeguimiento (HU-17)
-- y SP_ObtenerDetalleSeguimiento (HU-18), así ambas pantallas calculan exactamente lo mismo.
-- p_id_propuesta NULL = todas. El que llama debe hacer DROP TEMPORARY TABLE tmp_seg al terminar.
-- Universo: versión vigente de cada propuesta enviada al cliente (estado 'enviado'),
-- más las aprobadas que ya tienen orden de compra (aceptadas) y las que pasaron a 'rechazado'
-- por un cierre de seguimiento (rechazo o sin venta, HU-21).
-- ALCANCE: propuestas cuyo responsable es de la misma área del usuario.
--   Con la acción propuesta_seguimiento_todas (admins de Gerencia y TI) todas las áreas.
-- ESTADO VISUAL (estado_seguimiento):
--   aceptada        : tiene OC (no anulada) o el último seguimiento cerró con aceptación
--   rechazada       : el último seguimiento cerró con rechazo o sin venta
--   requiere_ajuste : el último resultado registrado es SOLICITA_AJUSTE
--   sin_respuesta   : N días (SEGUIMIENTO_DIAS_SIN_RESPUESTA) sin respuesta efectiva del cliente
--   en_seguimiento  : resto de abiertas
-- PRÓXIMA ACCIÓN: la programada en el último seguimiento activo. Si no hay seguimientos,
--   "Primer seguimiento" a fecha_envio + SLA (CONFIG_SLA propuesta / seguimiento).
--   Aceptada sin OC = Generar orden de compra. OC pendiente de validación = Validar orden de compra.
-- HU-20: si la acción se reprogramó, el seguimiento vigente ya trae los nuevos datos. Si todavía no hay
--   seguimientos, se usa la última reprogramación del "Primer seguimiento" (seguimiento_reprogramacion
--   con id_seguimiento NULL).
-- SLA: en_plazo | proximo (dentro de las horas de alerta) | vencido | cumplido | cerrado.
DROP PROCEDURE IF EXISTS SP_CalcularSeguimientoComercial;

DELIMITER $$

CREATE PROCEDURE SP_CalcularSeguimientoComercial(
    IN  p_id_usuario         BIGINT,
    IN  p_id_propuesta       BIGINT,
    OUT p_dias_sin_respuesta INT,
    OUT p_meta_aceptadas_mes INT,
    OUT p_sla_horas          INT,
    OUT p_alerta_horas       INT
)
BEGIN
    DECLARE v_todas           TINYINT DEFAULT 0;
    DECLARE v_area            VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_dias_sin_resp   INT DEFAULT 7;
    DECLARE v_meta            INT DEFAULT 8;
    DECLARE v_sla_horas       INT DEFAULT 48;
    DECLARE v_alerta_horas    INT DEFAULT 24;

    SET v_todas = FN_PermisoAccion(p_id_usuario, 'propuesta_seguimiento_todas');

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
        -- fecha_envio_cliente la registra el envío al cliente (HU-10b). modificado_en es solo el último respaldo
        COALESCE(p.fecha_envio_cliente, p.fecha_envio, p.modificado_en, p.fecha_creacion) AS fecha_envio,
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
                                WHERE op.id_propuesta = p.id_propuesta AND op.eliminado_en IS NULL))) AS oc_por_validar,
        (SELECT MAX(r.id_reprogramacion) FROM seguimiento_reprogramacion r
         WHERE r.id_propuesta = p.id_propuesta AND r.id_seguimiento IS NULL
           AND r.eliminado_en IS NULL)                                               AS id_reprog_inicial,
        (SELECT COUNT(*) FROM seguimiento_reprogramacion r
         WHERE r.id_propuesta = p.id_propuesta AND r.eliminado_en IS NULL)          AS reprogramaciones
    FROM propuesta_comercial p
    JOIN usuario u ON u.id_usuario = COALESCE(p.id_responsable, p.id_creador)
    WHERE p.eliminado_en IS NULL
      AND p.estado IN ('enviado', 'aprobado', 'rechazado')
      AND p.version = (SELECT MAX(p2.version) FROM propuesta_comercial p2
                       WHERE p2.numero = p.numero AND p2.eliminado_en IS NULL)
      AND (v_todas = 1 OR u.area = v_area)
      AND (IFNULL(p_id_propuesta, 0) = 0 OR p.id_propuesta = p_id_propuesta);

    -- ── Paso 2: estado visual, próxima acción y SLA ───────────────────────
    DROP TEMPORARY TABLE IF EXISTS tmp_seg;
    CREATE TEMPORARY TABLE tmp_seg AS
    SELECT k.*,
        CASE
            WHEN k.estado_seguimiento = 'rechazada' THEN NULL
            WHEN k.estado_seguimiento = 'aceptada' AND k.fecha_primera_oc IS NULL THEN 'GENERAR_OC'
            WHEN k.estado_seguimiento = 'aceptada' AND k.oc_por_validar > 0       THEN 'VALIDAR_OC'
            WHEN k.estado_seguimiento = 'aceptada'                                THEN NULL
            WHEN k.tipo_accion_codigo IS NOT NULL                                 THEN k.tipo_accion_codigo
            WHEN k.estado_ult_seg IS NULL                                         THEN 'PRIMER_SEGUIMIENTO'
            -- HU-19: si ya hay seguimientos registrados y la última próxima acción fue consumida
            -- explícitamente (vía "Ejecutar ahora" o decider cancelar) sin programar otra, no sugerimos nada.
            ELSE NULL
        END AS proxima_accion_codigo,
        CASE
            WHEN k.estado_seguimiento = 'rechazada' THEN NULL
            WHEN k.estado_seguimiento = 'aceptada' AND k.fecha_primera_oc IS NULL THEN 'Generar orden de compra'
            WHEN k.estado_seguimiento = 'aceptada' AND k.oc_por_validar > 0       THEN 'Validar orden de compra'
            WHEN k.estado_seguimiento = 'aceptada'                                THEN NULL
            WHEN k.tipo_accion_nombre IS NOT NULL                                 THEN k.tipo_accion_nombre
            WHEN k.estado_ult_seg IS NULL                                         THEN 'Primer seguimiento'
            ELSE NULL
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
                -- Primer contacto sin seguimientos: SLA cuenta desde envío.
                WHEN j.estado_ult_seg IS NULL
                    THEN COALESCE(j.proxima_accion_fecha, j.fecha_envio + INTERVAL v_sla_horas HOUR)
                -- HU-19: si hay seguimiento activo, respetar la próxima acción explícita (NULL = sin pendiente).
                WHEN j.estado_ult_seg = 'activo'
                    THEN j.proxima_accion_fecha
                ELSE j.proxima_accion_fecha
            END AS vence_accion
        FROM (
            SELECT b.*,
                s.estado                 AS estado_ult_seg,
                s.fecha_interaccion      AS fecha_ult_interaccion,
                IF(s.id_seguimiento IS NULL, r0.fecha_nueva,        s.proxima_accion_fecha)   AS proxima_accion_fecha,
                IF(s.id_seguimiento IS NULL, r0.id_tipo_accion_nueva, s.id_tipo_proxima_accion) AS id_tipo_proxima_accion,
                IF(s.id_seguimiento IS NULL, NULL,                   s.proxima_accion_detalle) AS proxima_accion_detalle,
                IF(s.id_seguimiento IS NULL, r0.id_prioridad_nueva,  s.id_prioridad_accion)    AS id_prioridad_accion,
                CASE
                    WHEN s.id_seguimiento IS NULL THEN r0.id_responsable_nuevo
                    WHEN s.estado = 'activo'      THEN s.id_responsable
                END                                                                            AS id_responsable_accion,
                s.id_canal               AS id_canal_ult,
                s.notas                  AS notas_ult,
                rs.String2               AS resultado_ult_codigo,
                rs.String1               AS resultado_ult,
                ta.String2               AS tipo_accion_codigo,
                ta.String1               AS tipo_accion_nombre
            FROM tmp_seg_base b
            LEFT JOIN seguimiento_comercial s ON s.id_seguimiento = b.id_ult_seg
            LEFT JOIN seguimiento_reprogramacion r0 ON r0.id_reprogramacion = b.id_reprog_inicial
            LEFT JOIN tabla_maestra rs ON rs.IdMaestro = 27 AND rs.IdEmpresa = 1 AND rs.Num1 = s.id_resultado
            LEFT JOIN tabla_maestra ta ON ta.Descripcion = 'TIPO_ACCION_SEGUIMIENTO' AND ta.IdEmpresa = 1
                                      AND ta.Num1 = IF(s.id_seguimiento IS NULL, r0.id_tipo_accion_nueva, s.id_tipo_proxima_accion)
            WHERE b.estado_propuesta = 'enviado'
               OR (b.estado_propuesta = 'aprobado' AND b.fecha_primera_oc IS NOT NULL)
               OR (b.estado_propuesta = 'rechazado' AND s.estado IN ('cerrado_rechazo', 'cerrado_sin_venta'))
        ) j
    ) k;

    DROP TEMPORARY TABLE IF EXISTS tmp_seg_base;

    SET p_dias_sin_respuesta = v_dias_sin_resp;
    SET p_meta_aceptadas_mes = v_meta;
    SET p_sla_horas          = v_sla_horas;
    SET p_alerta_horas       = v_alerta_horas;
END$$

DELIMITER ;
