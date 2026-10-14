-- Expediente Digital (interno, HU-30): recorrido del expediente por etapas (indicador y vista de workflow).
-- Requiere tmp_exp con el expediente ya calculado (CALL SP_CalcularExpedientes(usuario, id) antes).
-- Llena tmp_exp_etp (el que llama hace DROP TEMPORARY TABLE tmp_exp_etp), una fila por etapa de ETAPA_EXPEDIENTE:
--   estado      completado | en_curso | bloqueado | pendiente | cancelado (expediente cerrado antes de terminarla)
--               | no_aplica (expediente cerrado sin llegar a ella)
--   inicio/fin, responsable, área, horas de espera (etapa en curso: desde que empezó) y de proceso
--   (etapa terminada: de inicio a fin), SLA en horas y si se cumple, y el resultado.
-- Fechas de las etapas comerciales: RQ (registro), Propuesta (primera propuesta), VB (primera solicitud de VB),
--   OC (aprobación del VB), fin de OC = liberación. Desde Programación, el historial de expediente_etapa.
DROP PROCEDURE IF EXISTS SP_CargarEtapasExpediente;

DELIMITER $$

CREATE PROCEDURE SP_CargarEtapasExpediente()
BEGIN
    DECLARE v_id_exp      BIGINT;
    DECLARE v_id_rq       BIGINT;
    DECLARE v_etapa       VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_orden       INT;
    DECLARE v_bloqueos    INT;
    DECLARE v_fecha_rq    DATETIME;
    DECLARE v_fecha_prop  DATETIME;
    DECLARE v_fecha_vb    DATETIME;
    DECLARE v_fecha_aprob DATETIME;
    DECLARE v_fecha_lib   DATETIME;
    DECLARE v_fecha_cierre DATETIME;
    DECLARE v_resp_rq     BIGINT;
    DECLARE v_resp_prop   BIGINT;
    DECLARE v_resp_vb     BIGINT;
    DECLARE v_numeros_oc  VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_prop        VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_inicio_act  DATETIME;
    DECLARE v_resp_act    BIGINT;
    DECLARE v_orden_cierre INT;

    SELECT MAX(id_expediente), MAX(id_requerimiento), MAX(etapa), MAX(orden_etapa), MAX(bloqueos), MAX(fecha_rq),
           MAX(fecha_primera_propuesta), MAX(fecha_aprobacion_vb), MAX(fecha_liberacion_oc),
           MAX(IFNULL(fecha_cierre, IF(etapa = 'cerrado', inicio_etapa, NULL))),
           MAX(id_responsable_rq), MAX(id_responsable_propuesta), MAX(numeros_oc),
           MAX(IF(id_propuesta IS NULL, NULL, CONCAT(numero_propuesta, ' v', version_propuesta))),
           MAX(inicio_etapa), MAX(id_responsable)
      INTO v_id_exp, v_id_rq, v_etapa, v_orden, v_bloqueos, v_fecha_rq,
           v_fecha_prop, v_fecha_aprob, v_fecha_lib,
           v_fecha_cierre,
           v_resp_rq, v_resp_prop, v_numeros_oc,
           v_prop,
           v_inicio_act, v_resp_act
    FROM tmp_exp;

    -- Primera solicitud de VB y quién aprobó
    SELECT MIN(v.fecha_solicitud) INTO v_fecha_vb
    FROM visto_bueno v JOIN propuesta_comercial p ON p.id_propuesta = v.id_propuesta
    WHERE p.id_requerimiento = v_id_rq AND v.tipo = 'aprobacion' AND v.eliminado_en IS NULL;
    SELECT IFNULL(v.resuelto_por, v.id_aprobador) INTO v_resp_vb
    FROM visto_bueno v JOIN propuesta_comercial p ON p.id_propuesta = v.id_propuesta
    WHERE p.id_requerimiento = v_id_rq AND v.tipo = 'aprobacion' AND v.eliminado_en IS NULL
    ORDER BY (v.estado = 'aprobado') DESC, v.id_vb DESC LIMIT 1;

    -- Etapa en la que se cerró (la última con historial), para marcar como canceladas las que no terminó
    SET v_orden_cierre = CASE
        WHEN v_etapa <> 'cerrado' THEN NULL
        WHEN EXISTS (SELECT 1 FROM expediente_etapa x WHERE x.id_expediente = v_id_exp AND x.SoftDelete = 0)
            THEN (SELECT MAX(t.Num1) FROM expediente_etapa x
                  JOIN tabla_maestra t ON t.IdMaestro = 97 AND t.IdEmpresa = 1 AND t.String2 = x.etapa
                  WHERE x.id_expediente = v_id_exp AND x.SoftDelete = 0)
        WHEN v_fecha_lib IS NOT NULL   THEN 5
        WHEN v_fecha_aprob IS NOT NULL THEN 4
        WHEN v_fecha_vb IS NOT NULL    THEN 3
        WHEN v_fecha_prop IS NOT NULL  THEN 2
        ELSE 1 END;

    DROP TEMPORARY TABLE IF EXISTS tmp_exp_etp;
    CREATE TEMPORARY TABLE tmp_exp_etp AS
    SELECT t.Num1 AS orden, t.String2 AS etapa, t.String1 AS nombre, t.String3 AS area,
           CAST(NULL AS DATETIME) AS inicio, CAST(NULL AS DATETIME) AS fin, CAST(NULL AS SIGNED) AS id_responsable,
           CAST(NULL AS SIGNED) AS sla_horas,
           CAST(NULL AS CHAR(300)) AS resultado
    FROM tabla_maestra t
    WHERE t.IdMaestro = 97 AND t.IdEmpresa = 1
    ORDER BY t.Num1;

    -- Etapas comerciales (deducidas de sus módulos)
    UPDATE tmp_exp_etp SET inicio = v_fecha_rq,
                           fin    = IF(v_orden > 1 OR v_fecha_prop IS NOT NULL, v_fecha_prop, NULL),
                           id_responsable = v_resp_rq
    WHERE etapa = 'requerimiento';
    UPDATE tmp_exp_etp SET inicio = v_fecha_prop,
                           fin    = IF(v_orden > 2 OR v_fecha_vb IS NOT NULL, v_fecha_vb, NULL),
                           id_responsable = v_resp_prop,
                           resultado = v_prop
    WHERE etapa = 'propuesta';
    UPDATE tmp_exp_etp SET inicio = v_fecha_vb,
                           fin    = IF(v_orden > 3 OR v_fecha_aprob IS NOT NULL, v_fecha_aprob, NULL),
                           id_responsable = v_resp_vb
    WHERE etapa = 'visto_bueno';
    UPDATE tmp_exp_etp SET inicio = v_fecha_aprob,
                           fin    = v_fecha_lib,
                           id_responsable = v_resp_prop,
                           resultado = IF(v_numeros_oc IS NULL, NULL, CONCAT('OC ', v_numeros_oc))
    WHERE etapa = 'orden_compra';

    -- Etapas operativas (historial del expediente, la última vez que pasó por cada una)
    UPDATE tmp_exp_etp t
    JOIN expediente_etapa x ON x.id_expediente_etapa = (
            SELECT MAX(x2.id_expediente_etapa) FROM expediente_etapa x2
            WHERE x2.id_expediente = v_id_exp AND x2.etapa = t.etapa AND x2.SoftDelete = 0)
    SET t.inicio = x.fecha_inicio, t.fin = x.fecha_fin, t.id_responsable = x.id_responsable,
        t.sla_horas = x.sla_horas, t.area = IFNULL(x.area, t.area),
        t.resultado = NULLIF(TRIM(IFNULL(x.comentario, '')), '');

    UPDATE tmp_exp_etp SET inicio = v_fecha_cierre, fin = v_fecha_cierre WHERE etapa = 'cerrado' AND v_etapa = 'cerrado';

    -- La etapa actual: inicio y responsable calculados
    UPDATE tmp_exp_etp SET inicio = IFNULL(inicio, v_inicio_act), id_responsable = IFNULL(id_responsable, v_resp_act)
    WHERE etapa = v_etapa AND v_etapa <> 'cerrado';

    -- SLA configurado de las etapas sin SLA propio
    UPDATE tmp_exp_etp t
    SET t.sla_horas = (SELECT CAST(MAX(s.Num2) AS SIGNED) FROM tabla_maestra s
                       WHERE s.IdMaestro = 49 AND s.IdEmpresa = 1 AND s.String1 = 'expediente' AND s.String2 = t.etapa)
    WHERE t.sla_horas IS NULL;

    DROP TEMPORARY TABLE IF EXISTS tmp_exp_etp2;
    CREATE TEMPORARY TABLE tmp_exp_etp2 AS
    SELECT t.*,
        CASE
            WHEN v_etapa = 'cerrado' AND t.etapa = 'cerrado'                     THEN 'completado'
            WHEN v_etapa = 'cerrado' AND t.fin IS NOT NULL                        THEN 'completado'
            WHEN v_etapa = 'cerrado' AND t.orden <= IFNULL(v_orden_cierre, 0)      THEN 'cancelado'
            WHEN v_etapa = 'cerrado'                                              THEN 'no_aplica'
            WHEN t.orden < v_orden                                                THEN 'completado'
            WHEN t.orden = v_orden AND v_bloqueos > 0                             THEN 'bloqueado'
            WHEN t.orden = v_orden                                                THEN 'en_curso'
            ELSE 'pendiente'
        END AS estado
    FROM tmp_exp_etp t;
    DROP TEMPORARY TABLE IF EXISTS tmp_exp_etp;

    CREATE TEMPORARY TABLE tmp_exp_etp AS
    SELECT e.*,
        CONCAT(u.nombre, ' ', u.apellido)                                                  AS responsable,
        a.String1                                                                          AS area_nombre,
        IF(e.estado IN ('en_curso', 'bloqueado') AND e.inicio IS NOT NULL,
           GREATEST(ROUND(TIMESTAMPDIFF(MINUTE, e.inicio, NOW()) / 60, 1), 0), NULL)       AS horas_espera,
        IF(e.inicio IS NOT NULL AND e.fin IS NOT NULL,
           GREATEST(ROUND(TIMESTAMPDIFF(MINUTE, e.inicio, e.fin) / 60, 1), 0), NULL)       AS horas_proceso,
        CASE
            WHEN e.sla_horas IS NULL OR e.inicio IS NULL OR e.estado IN ('pendiente', 'no_aplica') OR e.etapa = 'cerrado' THEN NULL
            WHEN e.fin IS NOT NULL THEN e.fin <= e.inicio + INTERVAL e.sla_horas HOUR
            ELSE NOW() <= e.inicio + INTERVAL e.sla_horas HOUR
        END                                                                                AS cumple_sla,
        CASE e.estado
            WHEN 'completado' THEN IFNULL(e.resultado, 'Completado')
            WHEN 'en_curso'   THEN IFNULL(e.resultado, 'En curso')
            WHEN 'bloqueado'  THEN 'Bloqueado'
            WHEN 'cancelado'  THEN 'Cancelado por cierre del expediente'
            ELSE NULL
        END                                                                                AS resultado_texto
    FROM tmp_exp_etp2 e
    LEFT JOIN usuario u       ON u.id_usuario = e.id_responsable
    LEFT JOIN tabla_maestra a ON a.IdMaestro = 79 AND a.IdEmpresa = 1 AND a.String2 = e.area;

    DROP TEMPORARY TABLE IF EXISTS tmp_exp_etp2;
END$$

DELIMITER ;
