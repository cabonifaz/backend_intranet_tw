-- Expediente Digital (interno, HU-30/34): validaciones de la etapa actual (checklist automático).
-- Requiere tmp_exp con el expediente ya calculado (CALL SP_CalcularExpedientes(usuario, id) antes).
-- Llena tmp_exp_check (el que llama hace DROP TEMPORARY TABLE tmp_exp_check al terminar):
--   orden, codigo, descripcion, cumple (1/0), critico (1 = impide avanzar), es_documento (1 = documento crítico),
--   detalle y accion_sugerida (la próxima acción para cumplirlo).
-- Requisitos para salir de cada etapa que avanza desde el expediente:
--   programacion  OC válida, OS generada, cliente confirmado
--   ssoma         cliente confirmado, OC válida, OS generada, SCTR vigente del personal, ATS cargado
--   ejecucion     OS finalizada
--   revision      informe técnico cargado
--   conformidad   acta de conformidad cargada
--   facturacion   factura registrada
--   En todas: sin bloqueos abiertos. Las excepciones abiertas se informan, pero no impiden avanzar.
-- La etapa orden_compra muestra si la OC está validada (pasa a Programación al validarse la OC, Sprint 4).
DROP PROCEDURE IF EXISTS SP_EvaluarAvanceExpediente;

DELIMITER $$

CREATE PROCEDURE SP_EvaluarAvanceExpediente()
BEGIN
    DECLARE v_etapa        VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_bloqueos     INT DEFAULT 0;
    DECLARE v_excepciones  INT DEFAULT 0;
    DECLARE v_motivo       VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_oc_valida    TINYINT DEFAULT 0;
    DECLARE v_os           TINYINT DEFAULT 0;
    DECLARE v_confirmado   TINYINT DEFAULT 0;
    DECLARE v_personal     INT DEFAULT 0;
    DECLARE v_sin_sctr     INT DEFAULT 0;
    DECLARE v_ats          TINYINT DEFAULT 0;
    DECLARE v_os_fin       TINYINT DEFAULT 0;
    DECLARE v_informe      TINYINT DEFAULT 0;
    DECLARE v_acta         TINYINT DEFAULT 0;
    DECLARE v_factura      TINYINT DEFAULT 0;
    DECLARE v_numeros_oc   VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_numeros_os   VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    SELECT MAX(etapa), MAX(bloqueos), MAX(excepciones), MAX(motivo_bloqueo), MAX(oc_valida), MAX(os_generada),
           MAX(cliente_confirmado), MAX(personal_os), MAX(personal_sin_sctr), MAX(ats_cargado), MAX(os_finalizada),
           MAX(informe_tecnico), MAX(acta_conformidad), MAX(factura), MAX(numeros_oc), MAX(numeros_os)
      INTO v_etapa, v_bloqueos, v_excepciones, v_motivo, v_oc_valida, v_os,
           v_confirmado, v_personal, v_sin_sctr, v_ats, v_os_fin,
           v_informe, v_acta, v_factura, v_numeros_oc, v_numeros_os
    FROM tmp_exp;

    DROP TEMPORARY TABLE IF EXISTS tmp_exp_check;
    CREATE TEMPORARY TABLE tmp_exp_check (
        orden           INT,
        codigo          VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        descripcion     VARCHAR(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        cumple          TINYINT,
        critico         TINYINT,
        es_documento    TINYINT,
        detalle         VARCHAR(400) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        accion_sugerida VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
    );

    -- Requisitos por etapa
    IF v_etapa IN ('programacion', 'ssoma') THEN
        INSERT INTO tmp_exp_check VALUES
        (1, 'cliente_confirmado', 'Cliente confirmado', IFNULL(v_confirmado, 0), 1, 0,
            IF(v_confirmado = 1, 'El cliente confirmó la fecha del servicio.', 'El cliente aún no confirma la fecha del servicio en la OS.'),
            'Registrar la confirmación del cliente en la orden de servicio'),
        (2, 'oc_valida', 'OC válida', IFNULL(v_oc_valida, 0), 1, 0,
            IF(v_oc_valida = 1, CONCAT('OC ', IFNULL(v_numeros_oc, ''), ' validada y vigente.'),
               'No hay una OC validada, vigente y sin observaciones.'),
            'Revisar la orden de compra (vigencia u observación)'),
        (3, 'os_generada', 'OS generada', IFNULL(v_os, 0), 1, 0,
            IF(v_os = 1, CONCAT('Orden de servicio ', IFNULL(v_numeros_os, ''), '.'), 'Aún no se genera la orden de servicio.'),
            'Generar la orden de servicio en Programación');
    END IF;

    IF v_etapa = 'ssoma' THEN
        INSERT INTO tmp_exp_check VALUES
        (4, 'sctr_vigente', 'SCTR vigente', IF(v_personal > 0 AND v_sin_sctr = 0, 1, 0), 1, 1,
            CASE WHEN v_personal = 0 THEN 'La orden de servicio no tiene personal asignado.'
                 WHEN v_sin_sctr > 0 THEN CONCAT(v_sin_sctr, ' de ', v_personal, ' técnico(s) sin SCTR vigente.')
                 ELSE 'Todo el personal asignado tiene SCTR vigente.' END,
            IF(v_personal = 0, 'Asignar el personal de la orden de servicio', 'Cargar el SCTR vigente del personal')),
        (5, 'ats_cargado', 'ATS cargado', IFNULL(v_ats, 0), 1, 1,
            IF(v_ats = 1, 'Análisis de Trabajo Seguro cargado.', 'Falta cargar el Análisis de Trabajo Seguro (ATS).'),
            'Cargar el Análisis de Trabajo Seguro (ATS)');
    END IF;

    IF v_etapa = 'ejecucion' THEN
        INSERT INTO tmp_exp_check VALUES
        (1, 'os_finalizada', 'Servicio ejecutado', IFNULL(v_os_fin, 0), 1, 0,
            IF(v_os_fin = 1, 'Las órdenes de servicio están finalizadas.', 'Hay órdenes de servicio sin finalizar.'),
            'Finalizar la orden de servicio en campo');
    END IF;

    IF v_etapa = 'revision' THEN
        INSERT INTO tmp_exp_check VALUES
        (1, 'informe_tecnico', 'Informe técnico cargado', IFNULL(v_informe, 0), 1, 1,
            IF(v_informe = 1, 'El informe técnico está en el expediente.', 'Falta el informe técnico del servicio.'),
            'Adjuntar el informe técnico al expediente');
    END IF;

    IF v_etapa = 'conformidad' THEN
        INSERT INTO tmp_exp_check VALUES
        (1, 'acta_conformidad', 'Acta de conformidad', IFNULL(v_acta, 0), 1, 1,
            IF(v_acta = 1, 'El acta de conformidad del cliente está en el expediente.', 'Falta el acta de conformidad del cliente.'),
            'Adjuntar el acta de conformidad firmada por el cliente');
    END IF;

    IF v_etapa = 'facturacion' THEN
        INSERT INTO tmp_exp_check VALUES
        (1, 'factura', 'Factura registrada', IFNULL(v_factura, 0), 1, 1,
            IF(v_factura = 1, 'La factura está en el expediente.', 'Falta registrar la factura.'),
            'Adjuntar la factura al expediente');
    END IF;

    IF v_etapa = 'orden_compra' THEN
        INSERT INTO tmp_exp_check VALUES
        (1, 'oc_valida', 'OC validada', IFNULL(v_oc_valida, 0), 1, 0,
            IF(v_oc_valida = 1, CONCAT('OC ', IFNULL(v_numeros_oc, ''), ' validada.'),
               IF(v_numeros_oc IS NULL, 'Aún no se registra la orden de compra del cliente.',
                  CONCAT('La OC ', v_numeros_oc, ' aún no está validada.'))),
            IF(v_numeros_oc IS NULL, 'Registrar la orden de compra', 'Validar la OC desde Órdenes de Compra'));
    END IF;

    -- En todas las etapas abiertas: bloqueos (impiden avanzar) y excepciones (se informan)
    IF v_etapa <> 'cerrado' THEN
        INSERT INTO tmp_exp_check VALUES
        (90, 'sin_bloqueos', 'Sin bloqueos abiertos', IF(v_bloqueos = 0, 1, 0), 1, 0,
            IF(v_bloqueos = 0, 'El expediente no tiene bloqueos.', CONCAT(v_bloqueos, ' bloqueo(s): ', IFNULL(v_motivo, ''))),
            CONCAT('Resolver el bloqueo: ', IFNULL(v_motivo, ''))),
        (91, 'excepciones', 'Excepciones cerradas', IF(v_excepciones = 0, 1, 0), 0, 0,
            IF(v_excepciones = 0, 'No hay excepciones abiertas.',
               CONCAT(v_excepciones, ' excepción(es) abierta(s): no impiden avanzar, pero deben cerrarse.')),
            'Cerrar las excepciones abiertas');
    END IF;

    UPDATE tmp_exp_check SET accion_sugerida = NULL WHERE cumple = 1;
END$$

DELIMITER ;
