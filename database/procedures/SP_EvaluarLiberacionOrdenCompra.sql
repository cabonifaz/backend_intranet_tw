-- HU-28 (interno) Validaciones de cumplimiento para liberar el expediente a programación.
-- Llena la tabla temporal tmp_lib (el que llama hace DROP TEMPORARY TABLE tmp_lib al terminar).
-- El que llama ya validó permiso y alcance de la OC.
-- estado de cada ítem:
--   cumple     conforme
--   alerta     requisito obligatorio pendiente (SCTR, SSOMA, bloqueos de otras áreas): NO impide liberar,
--              pero se informa el impacto y se exige confirmarlo
--   bloqueante impide liberar (propuesta sin aceptar, OC sin validar u observada, otras OC de la propuesta
--              sin validar, otra OC observada, cobertura insuficiente, OC vencida, OC o expediente ya liberado,
--              u orden de servicio ya generada)
DROP PROCEDURE IF EXISTS SP_EvaluarLiberacionOrdenCompra;

DELIMITER $$

CREATE PROCEDURE SP_EvaluarLiberacionOrdenCompra(
    IN p_id_usuario BIGINT,
    IN p_id_oc      BIGINT
)
BEGIN
    DECLARE v_id_prop     BIGINT;
    DECLARE v_id_cliente  BIGINT;
    DECLARE v_id_exp      BIGINT;
    DECLARE v_validada    TINYINT DEFAULT 0;
    DECLARE v_vencida     TINYINT DEFAULT 0;
    DECLARE v_cobertura   VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_faltante    DECIMAL(14,2) DEFAULT 0;
    DECLARE v_estado      VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_fecha_lib   DATETIME;
    DECLARE v_vig_hasta   DATE;
    DECLARE v_fecha_acep  DATETIME;
    DECLARE v_fecha_val   DATETIME;
    DECLARE v_obs         INT DEFAULT 0;
    DECLARE v_sctr        TINYINT DEFAULT 0;
    DECLARE v_ssoma       VARCHAR(400) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_bloq        VARCHAR(600) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_simbolo     VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_otras_pend  VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_exp_lib     TINYINT DEFAULT 0;
    DECLARE v_n_os        INT DEFAULT 0;
    DECLARE v_etapa_exp   VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_oc_obs      VARCHAR(600) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    CALL SP_CalcularOrdenesCompra(p_id_usuario, p_id_oc);
    SELECT MAX(id_propuesta), MAX(id_cliente), MAX(id_expediente), MAX(validada), MAX(vencida),
           MAX(cobertura_proyectada), MAX(faltante), MAX(estado_bd), MAX(fecha_liberacion), MAX(vigencia_hasta),
           MAX(otras_oc_pendientes), MAX(expediente_liberado), MAX(ordenes_servicio)
      INTO v_id_prop, v_id_cliente, v_id_exp, v_validada, v_vencida,
           v_cobertura, v_faltante, v_estado, v_fecha_lib, v_vig_hasta,
           v_otras_pend, v_exp_lib, v_n_os
    FROM tmp_oc;
    SELECT MAX(etapa_actual) INTO v_etapa_exp FROM expediente_digital WHERE id_expediente = v_id_exp;
    DROP TEMPORARY TABLE IF EXISTS tmp_oc;

    SELECT MAX(s.fecha_interaccion) INTO v_fecha_acep
    FROM seguimiento_comercial s
    WHERE s.id_propuesta = v_id_prop AND s.estado = 'cerrado_aceptacion' AND s.eliminado_en IS NULL;
    IF v_fecha_acep IS NULL AND EXISTS (SELECT 1 FROM propuesta_comercial WHERE id_propuesta = v_id_prop AND estado = 'aprobado') THEN
        SELECT IFNULL(fecha_envio_cliente, modificado_en) INTO v_fecha_acep FROM propuesta_comercial WHERE id_propuesta = v_id_prop;
    END IF;

    SELECT MAX(registrado_en) INTO v_fecha_val
    FROM auditoria_evento WHERE entidad_tipo = 'orden_compra' AND id_entidad = p_id_oc AND accion = 'validar_oc';

    SELECT COUNT(*) INTO v_obs
    FROM orden_compra_observacion WHERE id_oc = p_id_oc AND estado = 'abierta' AND eliminado_en IS NULL;

    SELECT MAX(String2) INTO v_simbolo
    FROM tabla_maestra WHERE IdMaestro = 1 AND IdEmpresa = 1
      AND Num1 = (SELECT id_moneda FROM orden_compra WHERE id_oc = p_id_oc);

    -- Requisitos SSOMA del cliente (ficha del cliente + requisitos obligatorios configurados)
    SELECT IFNULL(c.ssoma_poliza_sctr, 0),
           NULLIF(CONCAT_WS(', ',
               IF(IFNULL(c.ssoma_induccion_ssoma, 0) = 1, 'inducción SSOMA', NULL),
               IF(IFNULL(c.ssoma_examen_medico, 0) = 1, 'examen médico ocupacional', NULL),
               IF(IFNULL(c.ssoma_camioneta_4x4, 0) = 1, 'camioneta 4x4', NULL),
               (SELECT GROUP_CONCAT(DISTINCT LOWER(td.String1) ORDER BY td.Num1 SEPARATOR ', ')
                FROM requisito_ssoma_cliente rq
                JOIN tabla_maestra td ON td.IdMaestro = 36 AND td.IdEmpresa = 1 AND td.Num1 = rq.id_requisito
                WHERE rq.id_cliente = c.id_cliente AND rq.es_obligatorio = 1 AND rq.eliminado_en IS NULL
                  AND rq.id_requisito <> 1)), '')
      INTO v_sctr, v_ssoma
    FROM cliente c WHERE c.id_cliente = v_id_cliente;

    IF v_sctr = 0 AND EXISTS (SELECT 1 FROM requisito_ssoma_cliente
                              WHERE id_cliente = v_id_cliente AND id_requisito = 1 AND es_obligatorio = 1 AND eliminado_en IS NULL) THEN
        SET v_sctr = 1;
    END IF;

    -- Bloqueos abiertos del expediente (OC observadas y los registrados por las áreas): impiden liberar
    SELECT GROUP_CONCAT(b.descripcion ORDER BY b.id_bloqueador SEPARATOR '; ') INTO v_oc_obs
    FROM expediente_bloqueador b
    WHERE b.id_expediente = v_id_exp AND b.resuelto = 0 AND b.eliminado_en IS NULL
      AND b.clase = 'bloqueo';

    -- Excepciones abiertas del expediente (requisitos pendientes aceptados): se informan
    SELECT GROUP_CONCAT(b.descripcion ORDER BY b.id_bloqueador SEPARATOR '; ') INTO v_bloq
    FROM expediente_bloqueador b
    WHERE b.id_expediente = v_id_exp AND b.resuelto = 0 AND b.eliminado_en IS NULL
      AND b.clase = 'excepcion';

    DROP TEMPORARY TABLE IF EXISTS tmp_lib;
    CREATE TEMPORARY TABLE tmp_lib (
        orden       INT,
        codigo      VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        descripcion VARCHAR(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        estado      VARCHAR(15)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        fecha       DATETIME,
        detalle     VARCHAR(700) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
    );

    INSERT INTO tmp_lib VALUES
    (1, 'propuesta_aceptada', 'Propuesta técnica aceptada',
        IF(v_fecha_acep IS NULL, 'bloqueante', 'cumple'), v_fecha_acep,
        IF(v_fecha_acep IS NULL, 'La propuesta no tiene registrada la aceptación del cliente.', 'Aceptada por el cliente.')),
    (2, 'oc_validada', 'Orden de Compra (OC) validada',
        IF(v_validada = 1 AND v_obs = 0, 'cumple', 'bloqueante'), v_fecha_val,
        CASE WHEN v_estado = 'anulada' THEN 'La orden de compra está anulada.'
             WHEN v_obs > 0           THEN 'La OC tiene una observación abierta.'
             WHEN v_validada = 0      THEN 'La OC está pendiente de validación.'
             ELSE 'OC validada por el jefe comercial.' END),
    (2, 'otras_oc', 'Otras OC de la propuesta validadas',
        IF(v_otras_pend IS NULL, 'cumple', 'bloqueante'), NULL,
        IF(v_otras_pend IS NULL, 'No hay otras OC pendientes de validación.',
           CONCAT('La cobertura cuenta con OC aún sin validar u observadas: ', v_otras_pend, '. Valídelas antes de liberar.'))),
    (2, 'oc_observadas', 'Sin bloqueos en el expediente',
        IF(v_oc_obs IS NULL, 'cumple', 'bloqueante'), NULL,
        IFNULL(CONCAT('Resuelva antes: ', v_oc_obs), 'El expediente no tiene bloqueos abiertos.')),
    (3, 'cobertura_oc', 'Cobertura económica de la OC',
        IF(v_cobertura IN ('completa', 'con_saldo'), 'cumple', 'bloqueante'), NULL,
        CASE WHEN v_cobertura = 'moneda_diferente' THEN 'La OC está en una moneda distinta a la propuesta.'
             WHEN v_cobertura = 'insuficiente'     THEN CONCAT('Faltan ', IFNULL(v_simbolo, ''), ' ', FORMAT(v_faltante, 2),
                                                               '. Registre una OC complementaria.')
             ELSE 'La OC cubre el monto de la propuesta.' END),
    (4, 'oc_vigente', 'Orden de compra vigente',
        IF(v_vencida = 1, 'bloqueante', 'cumple'), NULL,
        IF(v_vencida = 1, CONCAT('La OC venció el ', DATE_FORMAT(v_vig_hasta, '%d/%m/%Y'), '.'),
           IFNULL(CONCAT('Vigente hasta el ', DATE_FORMAT(v_vig_hasta, '%d/%m/%Y'), '.'), 'La OC no indica vigencia.'))),
    (5, 'sctr', 'Cobertura de seguros completa (SCTR)',
        IF(v_sctr = 1, 'alerta', 'cumple'), NULL,
        IF(v_sctr = 1, 'El cliente exige SCTR (salud y pensión): se verifica al asignar el personal de la OS.',
           'El cliente no exige SCTR específico.')),
    (6, 'ssoma', 'SSOMA pendiente de revisión final',
        IF(v_ssoma IS NULL, 'cumple', 'alerta'), NULL,
        IF(v_ssoma IS NULL, 'El cliente no tiene requisitos SSOMA adicionales.',
           CONCAT('Requisitos del cliente por completar antes de la salida a campo: ', v_ssoma, '.'))),
    (7, 'bloqueos_expediente', 'Excepciones del expediente',
        IF(v_bloq IS NULL, 'cumple', 'alerta'), NULL,
        IFNULL(CONCAT('Pendientes: ', v_bloq), 'Sin bloqueos pendientes.')),
    (8, 'no_liberada', 'Expediente aún no liberado',
        IF(v_fecha_lib IS NULL AND IFNULL(v_exp_lib, 0) = 0 AND IFNULL(v_n_os, 0) = 0, 'cumple', 'bloqueante'), v_fecha_lib,
        CASE WHEN v_fecha_lib IS NOT NULL      THEN 'Esta OC ya liberó el expediente para programación.'
             WHEN IFNULL(v_exp_lib, 0) = 1     THEN CONCAT('El expediente ya está en la etapa ',
                                                           REPLACE(IFNULL(v_etapa_exp, ''), '_', ' '), ' (se liberó con otra OC).')
             WHEN IFNULL(v_n_os, 0) > 0        THEN 'Ya existe una orden de servicio para esta OC.'
             ELSE 'Listo para liberar.' END);

    -- La descripción del ítem SSOMA solo dice "pendiente" si hay requisitos
    UPDATE tmp_lib SET descripcion = 'Requisitos SSOMA del cliente' WHERE codigo = 'ssoma' AND estado = 'cumple';
END$$

DELIMITER ;
