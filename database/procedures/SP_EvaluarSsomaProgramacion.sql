-- HU-36 (Sprint 5) Validación SSOMA de los técnicos para una OS/OM en una fecha. Ayuda interna: NO devuelve resultados.
-- La usan SP_BuscarTecnicosProgramacion, SP_CrearProgramacion y SP_DerivarSsomaProgramacion, así las tres aplican la misma regla.
-- Entrada: tabla temporal tmp_ssoma_in (id_usuario) creada por quien llama, con los técnicos a evaluar.
-- Salida (tablas temporales; quien llama las borra con SP_LimpiarSsomaProgramacion):
--   tmp_ssoma_det : una fila por técnico y requisito (los que pide el cliente/zona + los demás documentos del técnico)
--                   situacion: conforme · por_vencer · bloqueado · sin_documento · sin_verificar
--   tmp_ssoma_res : una fila por técnico con su estado: conforme · por_vencer · incompleto · pendiente · bloqueado
-- Requisitos del cliente/zona: requisito_ssoma_cliente obligatorios del cliente (o generales) y de la sede (o de todas),
--   del tipo de servicio de la orden (o de todos), que aplican a personas (REQUISITO_SSOMA String3 vacío, ambos o tecnico).
--   Se comparan con el último documento del técnico del tipo equivalente (ssoma_requisito_documento, migración 87).
--   sin_verificar = el requisito no tiene documento equivalente configurado: solo se informa.
-- Situación de un documento: bloqueado si está observado o vencido, o vence antes del servicio; sin_documento si no hay
--   documento o está pendiente de carga; por_vencer si vence dentro de DIAS_POR_VENCER_SSOMA días del servicio; si no, conforme.
-- Estado del técnico:
--   bloqueado  : un requisito que bloquea el servicio está bloqueado, o el técnico figura bloqueado por SSOMA en otra orden
--                activa. Si el cliente no tiene requisitos configurados, cualquier documento bloqueado bloquea (criterio anterior).
--   pendiente  : SSOMA_EXIGIR_DOCUMENTO = 1 y le falta el documento de un requisito que bloquea el servicio (bloquea).
--   incompleto : SSOMA_EXIGIR_DOCUMENTO = 0 y le falta el documento de algún requisito del cliente (no bloquea: se avisa).
--   por_vencer : algún documento vence pronto. conforme: ninguna de las anteriores.
-- Solo lee datos. No crea funciones (exigen el privilegio SUPER) ni abre transacciones.
DROP PROCEDURE IF EXISTS SP_EvaluarSsomaProgramacion;

DELIMITER $$

CREATE PROCEDURE SP_EvaluarSsomaProgramacion(
    IN p_id_os BIGINT,
    IN p_fecha DATE
)
BEGIN
    DECLARE v_id_cliente   BIGINT;
    DECLARE v_id_sede      BIGINT;
    DECLARE v_tipo_serv    INT;
    DECLARE v_fecha        DATE;
    DECLARE v_param        DECIMAL(18,6);
    DECLARE v_por_vencer   INT;
    DECLARE v_exigir       INT;
    DECLARE v_con_req      INT DEFAULT 0;

    CALL SP_LimpiarSsomaProgramacion();

    SET v_id_cliente = (SELECT id_cliente       FROM orden_servicio WHERE id_os = p_id_os);
    SET v_id_sede    = (SELECT id_sede          FROM orden_servicio WHERE id_os = p_id_os);
    SET v_tipo_serv  = (SELECT id_tipo_servicio FROM orden_servicio WHERE id_os = p_id_os);
    SET v_fecha      = IFNULL(p_fecha, CURDATE());

    CALL SP_LeerParametroProgramacion('DIAS_POR_VENCER_SSOMA', 30, v_param);
    SET v_por_vencer = GREATEST(CAST(v_param AS SIGNED), 0);
    CALL SP_LeerParametroProgramacion('SSOMA_EXIGIR_DOCUMENTO', 0, v_param);
    SET v_exigir = IF(v_param = 1, 1, 0);

    -- Requisitos del cliente / zona que aplican a personas
    CREATE TEMPORARY TABLE tmp_ssoma_req (
        id_requisito      INT          NOT NULL,
        requisito         VARCHAR(255) NULL,
        id_tipo_documento INT          NULL,
        bloquea           TINYINT      NOT NULL DEFAULT 1,
        PRIMARY KEY (id_requisito)
    );
    INSERT INTO tmp_ssoma_req (id_requisito, requisito, id_tipo_documento, bloquea)
    SELECT rq.id_requisito,
           MAX(IFNULL(tm.String1, CONCAT('Requisito ', rq.id_requisito))),
           MAX(m.id_tipo_documento),
           MAX(rq.bloquea_servicio)
    FROM requisito_ssoma_cliente rq
    LEFT JOIN tabla_maestra tm ON tm.IdMaestro = 48 AND tm.IdEmpresa = 1 AND tm.Num1 = rq.id_requisito
    LEFT JOIN ssoma_requisito_documento m ON m.id_requisito = rq.id_requisito AND m.eliminado_en IS NULL
    WHERE rq.eliminado_en IS NULL
      AND rq.es_obligatorio = 1
      AND (rq.id_cliente IS NULL OR rq.id_cliente = v_id_cliente)
      AND (rq.id_sede IS NULL OR rq.id_sede = v_id_sede)
      AND (rq.id_tipo_servicio IS NULL OR rq.id_tipo_servicio = v_tipo_serv)
      AND (tm.String3 IS NULL OR tm.String3 IN ('', 'ambos', 'tecnico'))
    GROUP BY rq.id_requisito;

    SELECT COUNT(*) INTO v_con_req FROM tmp_ssoma_req;

    -- Último documento de cada tipo de los técnicos evaluados
    CREATE TEMPORARY TABLE tmp_ssoma_doc (
        id_usuario        BIGINT      NOT NULL,
        id_tipo_documento INT         NOT NULL,
        estado            VARCHAR(20) NOT NULL,
        fecha_vencimiento DATE        NULL,
        PRIMARY KEY (id_usuario, id_tipo_documento)
    );
    INSERT IGNORE INTO tmp_ssoma_doc (id_usuario, id_tipo_documento, estado, fecha_vencimiento)
    SELECT d.id_usuario, d.id_requisito, d.estado, d.fecha_vencimiento
    FROM ssoma_documento d
    JOIN tmp_ssoma_in i ON i.id_usuario = d.id_usuario
    WHERE d.eliminado_en IS NULL
      AND d.id_ssoma_doc = (SELECT MAX(d2.id_ssoma_doc) FROM ssoma_documento d2
                            WHERE d2.id_usuario = d.id_usuario AND d2.id_requisito = d.id_requisito
                              AND d2.eliminado_en IS NULL);

    CREATE TEMPORARY TABLE tmp_ssoma_det (
        id_usuario        BIGINT       NOT NULL,
        id_requisito      INT          NULL,
        id_tipo_documento INT          NULL,
        requisito         VARCHAR(255) NOT NULL,
        requerido         TINYINT      NOT NULL,
        bloquea           TINYINT      NOT NULL,
        estado_doc        VARCHAR(20)  NULL,
        fecha_vencimiento DATE         NULL,
        situacion         VARCHAR(20)  NOT NULL,
        KEY (id_usuario)
    );

    -- a) Lo que pide el cliente / zona
    INSERT INTO tmp_ssoma_det (id_usuario, id_requisito, id_tipo_documento, requisito, requerido, bloquea,
                               estado_doc, fecha_vencimiento, situacion)
    SELECT i.id_usuario, q.id_requisito, q.id_tipo_documento, q.requisito, 1, q.bloquea,
           d.estado, d.fecha_vencimiento,
           CASE WHEN q.id_tipo_documento IS NULL                                        THEN 'sin_verificar'
                WHEN d.id_usuario IS NULL OR d.estado = 'pendiente'                     THEN 'sin_documento'
                WHEN d.estado IN ('observado', 'vencido')
                     OR (d.fecha_vencimiento IS NOT NULL AND d.fecha_vencimiento < v_fecha) THEN 'bloqueado'
                WHEN d.fecha_vencimiento IS NOT NULL
                     AND d.fecha_vencimiento <= DATE_ADD(v_fecha, INTERVAL v_por_vencer DAY) THEN 'por_vencer'
                ELSE 'conforme'
           END
    FROM tmp_ssoma_in i
    CROSS JOIN tmp_ssoma_req q
    LEFT JOIN tmp_ssoma_doc d ON d.id_usuario = i.id_usuario AND d.id_tipo_documento = q.id_tipo_documento;

    -- b) Los demás documentos del técnico (si el cliente no tiene requisitos configurados, también bloquean)
    INSERT INTO tmp_ssoma_det (id_usuario, id_requisito, id_tipo_documento, requisito, requerido, bloquea,
                               estado_doc, fecha_vencimiento, situacion)
    SELECT d.id_usuario, NULL, d.id_tipo_documento,
           IFNULL(t36.String1, CONCAT('Documento ', d.id_tipo_documento)), 0, IF(v_con_req = 0, 1, 0),
           d.estado, d.fecha_vencimiento,
           CASE WHEN d.estado = 'pendiente'                                             THEN 'sin_documento'
                WHEN d.estado IN ('observado', 'vencido')
                     OR (d.fecha_vencimiento IS NOT NULL AND d.fecha_vencimiento < v_fecha) THEN 'bloqueado'
                WHEN d.fecha_vencimiento IS NOT NULL
                     AND d.fecha_vencimiento <= DATE_ADD(v_fecha, INTERVAL v_por_vencer DAY) THEN 'por_vencer'
                ELSE 'conforme'
           END
    FROM tmp_ssoma_doc d
    LEFT JOIN tabla_maestra t36 ON t36.IdMaestro = 36 AND t36.IdEmpresa = 1 AND t36.Num1 = d.id_tipo_documento
    WHERE NOT EXISTS (SELECT 1 FROM tmp_ssoma_req q WHERE q.id_tipo_documento = d.id_tipo_documento);

    -- Resumen por técnico (una sola lectura de tmp_ssoma_det: MySQL no reabre una temporal en la misma consulta)
    CREATE TEMPORARY TABLE tmp_ssoma_agg AS
    SELECT x.id_usuario,
           SUM(x.situacion = 'bloqueado' AND x.bloquea = 1)                      AS n_bloqueos,
           SUM(x.requerido = 1 AND x.situacion = 'sin_documento')                AS n_faltantes,
           SUM(x.requerido = 1 AND x.bloquea = 1 AND x.situacion = 'sin_documento') AS n_faltantes_bloquean,
           SUM(x.situacion = 'por_vencer')                                        AS n_por_vencer,
           SUM(x.situacion = 'sin_verificar')                                     AS n_sin_verificar,
           SUM(x.requerido = 1)                                                   AS n_requeridos,
           SUM(x.requerido = 1 AND x.situacion IN ('conforme', 'por_vencer'))     AS n_cumplidos,
           GROUP_CONCAT(CASE WHEN x.situacion = 'bloqueado' AND x.bloquea = 1
                             THEN CONCAT(x.requisito, ' ',
                                         IF(x.estado_doc IN ('observado', 'vencido'), x.estado_doc,
                                            CONCAT('vence ', DATE_FORMAT(x.fecha_vencimiento, '%d/%m/%Y'))))
                        END ORDER BY x.requisito SEPARATOR '; ')                  AS motivo_bloqueo,
           GROUP_CONCAT(CASE WHEN x.requerido = 1 AND x.situacion = 'sin_documento'
                             THEN x.requisito END ORDER BY x.requisito SEPARATOR ', ') AS faltantes
    FROM tmp_ssoma_det x
    GROUP BY x.id_usuario;

    CREATE TEMPORARY TABLE tmp_ssoma_res AS
    SELECT i.id_usuario,
           CASE WHEN IFNULL(a.n_bloqueos, 0) > 0 OR b.id_usuario IS NOT NULL         THEN 'bloqueado'
                WHEN v_exigir = 1 AND IFNULL(a.n_faltantes_bloquean, 0) > 0          THEN 'pendiente'
                WHEN IFNULL(a.n_faltantes, 0) > 0                                     THEN 'incompleto'
                WHEN IFNULL(a.n_por_vencer, 0) > 0                                    THEN 'por_vencer'
                ELSE 'conforme'
           END                                                                        AS estado,
           IFNULL(a.n_requeridos, 0)                                                  AS n_requeridos,
           IFNULL(a.n_cumplidos, 0)                                                   AS n_cumplidos,
           IFNULL(a.n_faltantes, 0)                                                   AS n_faltantes,
           IFNULL(a.n_por_vencer, 0)                                                  AS n_por_vencer,
           IFNULL(a.n_sin_verificar, 0)                                               AS n_sin_verificar,
           IF(b.id_usuario IS NULL, 0, 1)                                             AS bloqueado_en_otra_os,
           TRIM(BOTH '; ' FROM CONCAT(IFNULL(a.motivo_bloqueo, ''),
                                      IF(b.id_usuario IS NULL, '', CONCAT('; bloqueado por SSOMA en ', b.numero)))) AS motivo_bloqueo,
           a.faltantes,
           IF(v_exigir = 1, 1, 0)                                                     AS exige_documento
    FROM tmp_ssoma_in i
    LEFT JOIN tmp_ssoma_agg a ON a.id_usuario = i.id_usuario
    LEFT JOIN (SELECT p.id_usuario, MIN(o.numero) AS numero
               FROM os_personal p
               JOIN orden_servicio o ON o.id_os = p.id_os AND o.eliminado_en IS NULL AND o.id_os <> p_id_os
                    AND o.estado IN ('emitida', 'programada', 'reprogramada', 'en_ruta', 'en_ejecucion', 'pausada', 'bloqueada')
               WHERE p.eliminado_en IS NULL AND p.estado_ssoma = 'bloqueado'
               GROUP BY p.id_usuario) b ON b.id_usuario = i.id_usuario;

    DROP TEMPORARY TABLE IF EXISTS tmp_ssoma_agg;
    DROP TEMPORARY TABLE IF EXISTS tmp_ssoma_doc;
    DROP TEMPORARY TABLE IF EXISTS tmp_ssoma_req;
END$$

DELIMITER ;
