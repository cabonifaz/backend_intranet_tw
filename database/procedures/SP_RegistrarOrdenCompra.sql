-- HU-22 Registrar la orden de compra recibida del cliente y vincularla a la propuesta aceptada.
-- p_solo_validar = 1: valida y devuelve la COBERTURA sin guardar (previsualización del indicador
--   y validación previa a guardar el PDF en disco). En ese modo el PDF no es obligatorio.
-- Reglas:
--   Acción oc_registrar, propuesta del área del usuario, ACEPTADA por el cliente y sin OC.
--   Obligatorios: N° OC (único por cliente entre las OC no anuladas), fecha OC (no futura),
--   fecha de recepción (no futura ni anterior a la fecha OC), moneda, monto mayor a 0,
--   vigencia en días (1 a 3650) y el PDF (al guardar).
-- Cobertura (monto OC frente al total de la propuesta, en la misma moneda):
--   completa (diferencia 0), parcial (OC menor), excede (OC mayor) o moneda_diferente.
-- Al guardar: orden_compra en 'pendiente_validacion' con su vigencia, oc_propuesta con el monto
--   asignado y notificación a Operaciones y Administración (Contabilidad) y al responsable comercial.
-- HU-24: p_referencia (referencia / glosa, opcional, hasta 200 caracteres).
-- Resultados: 1 mensaje, 2 cobertura (validar) o datos de la OC registrada (guardar).
DROP PROCEDURE IF EXISTS SP_RegistrarOrdenCompra;

DELIMITER $$

CREATE PROCEDURE SP_RegistrarOrdenCompra(
    IN p_id_usuario        BIGINT,
    IN p_id_propuesta      BIGINT,
    IN p_numero_oc         VARCHAR(50)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_fecha_oc          DATE,
    IN p_fecha_recepcion   DATE,
    IN p_id_moneda         INT,
    IN p_monto             DECIMAL(14,2),
    IN p_vigencia_dias     INT,
    IN p_observaciones     VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_referencia        VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_ruta_pdf          VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_nombre_pdf        VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_tamano_pdf        BIGINT,
    IN p_hash_pdf          CHAR(64)     CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_solo_validar      TINYINT
)
proc: BEGIN
    DECLARE v_dias_sin_resp  INT;
    DECLARE v_meta           INT;
    DECLARE v_sla_horas      INT;
    DECLARE v_alerta_horas   INT;
    DECLARE v_existe         INT DEFAULT 0;
    DECLARE v_estado         VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tiene_oc       INT DEFAULT 0;
    DECLARE v_id_cliente     BIGINT;
    DECLARE v_id_responsable BIGINT;
    DECLARE v_numero         VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_total          DECIMAL(14,2);
    DECLARE v_id_moneda_prop INT;
    DECLARE v_numero_oc      VARCHAR(50)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_simbolo        VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_simbolo_prop   VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado_cob     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_pct            DECIMAL(7,2) DEFAULT 0;
    DECLARE v_diferencia     DECIMAL(14,2);
    DECLARE v_id_oc          BIGINT;
    DECLARE v_usuario        VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cliente        VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_notificados    INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_seg;
        GET DIAGNOSTICS CONDITION 1
            @err_msg  = MESSAGE_TEXT,
            @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje,
               CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SET v_numero_oc = NULLIF(TRIM(IFNULL(p_numero_oc, '')), '');

    IF FN_PermisoAccion(p_id_usuario, 'oc_registrar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para registrar órdenes de compra.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Propuesta aceptada, sin OC y en alcance
    CALL SP_CalcularSeguimientoComercial(p_id_usuario, p_id_propuesta,
                                         v_dias_sin_resp, v_meta, v_sla_horas, v_alerta_horas);
    SELECT COUNT(*), MAX(estado_seguimiento), IFNULL(MAX(fecha_primera_oc IS NOT NULL), 0),
           MAX(id_cliente), MAX(id_responsable), MAX(numero), MAX(total), MAX(id_moneda)
      INTO v_existe, v_estado, v_tiene_oc, v_id_cliente, v_id_responsable, v_numero, v_total, v_id_moneda_prop
    FROM tmp_seg;
    DROP TEMPORARY TABLE IF EXISTS tmp_seg;

    IF v_existe = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'La propuesta no está en seguimiento comercial o no pertenece a tu área.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_tiene_oc = 1 THEN
        SELECT 1 AS IdTipoMensaje, 'La propuesta ya tiene una orden de compra registrada.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_estado <> 'aceptada' THEN
        SELECT 1 AS IdTipoMensaje,
               IF(v_estado = 'rechazada', 'La propuesta fue rechazada o cerrada sin venta.',
                  'Registre primero la aceptación del cliente para poder registrar la orden de compra.') AS Mensaje;
        LEAVE proc;
    END IF;

    -- Datos obligatorios
    IF v_numero_oc IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Ingrese el número de la orden de compra.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF EXISTS (SELECT 1 FROM orden_compra
               WHERE id_cliente = v_id_cliente AND numero_oc = v_numero_oc
                 AND estado <> 'anulada' AND eliminado_en IS NULL) THEN
        SELECT 1 AS IdTipoMensaje,
               CONCAT('Ya existe la orden de compra ', v_numero_oc, ' registrada para este cliente.') AS Mensaje;
        LEAVE proc;
    END IF;
    IF p_fecha_oc IS NULL OR p_fecha_oc > CURDATE() THEN
        SELECT 1 AS IdTipoMensaje, 'Indique la fecha de la orden de compra (no puede ser futura).' AS Mensaje;
        LEAVE proc;
    END IF;
    IF p_fecha_recepcion IS NULL OR p_fecha_recepcion > CURDATE() THEN
        SELECT 1 AS IdTipoMensaje, 'Indique la fecha de recepción (no puede ser futura).' AS Mensaje;
        LEAVE proc;
    END IF;
    IF p_fecha_recepcion < p_fecha_oc THEN
        SELECT 1 AS IdTipoMensaje, 'La fecha de recepción no puede ser anterior a la fecha de la orden de compra.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT MAX(String2) INTO v_simbolo FROM tabla_maestra
    WHERE IdMaestro = 1 AND IdEmpresa = 1 AND Num1 = p_id_moneda AND eliminado_en IS NULL;
    IF v_simbolo IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Seleccione la moneda de la orden de compra.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF p_monto IS NULL OR p_monto <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Ingrese el monto de la orden de compra (mayor a 0).' AS Mensaje;
        LEAVE proc;
    END IF;
    IF p_vigencia_dias IS NULL OR p_vigencia_dias < 1 OR p_vigencia_dias > 3650 THEN
        SELECT 1 AS IdTipoMensaje, 'Indique la vigencia de la orden de compra en días (1 a 3650).' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Cobertura
    SELECT MAX(String2) INTO v_simbolo_prop FROM tabla_maestra
    WHERE IdMaestro = 1 AND IdEmpresa = 1 AND Num1 = v_id_moneda_prop;

    IF p_id_moneda <> v_id_moneda_prop THEN
        SET v_estado_cob = 'moneda_diferente';
        SET v_pct        = 0;
        SET v_diferencia = NULL;
    ELSE
        SET v_diferencia = p_monto - v_total;
        SET v_pct        = IF(v_total > 0, LEAST(ROUND(p_monto * 100 / v_total, 2), 999.99), 100);
        SET v_estado_cob = CASE
                               WHEN ABS(v_diferencia) < 0.01 THEN 'completa'
                               WHEN v_diferencia < 0         THEN 'parcial'
                               ELSE                               'excede'
                           END;
    END IF;

    IF IFNULL(p_solo_validar, 0) = 1 THEN
        SELECT 2 AS IdTipoMensaje, 'Validado.' AS Mensaje;
        SELECT v_estado_cob AS estado_cobertura, v_pct AS cobertura_pct, v_diferencia AS diferencia,
               v_total AS monto_propuesta, v_id_moneda_prop AS id_moneda_propuesta, v_simbolo_prop AS moneda_simbolo_propuesta,
               p_monto AS monto_oc, p_id_moneda AS id_moneda_oc, v_simbolo AS moneda_simbolo_oc;
        LEAVE proc;
    END IF;

    IF NULLIF(TRIM(IFNULL(p_ruta_pdf, '')), '') IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Adjunte el PDF de la orden de compra.' AS Mensaje;
        LEAVE proc;
    END IF;

    START TRANSACTION;

    INSERT INTO orden_compra (
        numero_oc, referencia, id_propuesta, id_cliente, id_moneda, monto_total, monto_aplicado, saldo, cobertura_pct,
        fecha_oc, fecha_recepcion, vigencia_desde, vigencia_hasta, vigencia_dias, observaciones,
        url_archivo_pdf, nombre_archivo_pdf, tamano_pdf_bytes, hash_pdf,
        estado, fecha_registro, creado_por)
    VALUES (
        v_numero_oc, NULLIF(TRIM(IFNULL(p_referencia, '')), ''), p_id_propuesta, v_id_cliente, p_id_moneda, p_monto, 0, p_monto, v_pct,
        p_fecha_oc, p_fecha_recepcion, p_fecha_oc, p_fecha_oc + INTERVAL p_vigencia_dias DAY, p_vigencia_dias,
        NULLIF(TRIM(IFNULL(p_observaciones, '')), ''),
        p_ruta_pdf, p_nombre_pdf, p_tamano_pdf, p_hash_pdf,
        'pendiente_validacion', NOW(), p_id_usuario);

    SET v_id_oc = LAST_INSERT_ID();

    INSERT INTO oc_propuesta (id_oc, id_propuesta, monto_asignado, creado_por)
    VALUES (v_id_oc, p_id_propuesta,
            IF(v_estado_cob = 'moneda_diferente', p_monto, LEAST(p_monto, v_total)), p_id_usuario);

    -- Notificación a Operaciones y Administración (Contabilidad) y al responsable comercial
    SELECT CONCAT(nombre, ' ', apellido) INTO v_usuario FROM usuario WHERE id_usuario = p_id_usuario;
    SELECT razon_social INTO v_cliente FROM cliente WHERE id_cliente = v_id_cliente;

    INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
    SELECT u.id_usuario, 5,
           CONCAT('Nueva orden de compra: ', v_numero_oc),
           CONCAT(v_usuario, ' registró la OC ', v_numero_oc, ' de ', IFNULL(v_cliente, 'el cliente'),
                  ' por ', v_simbolo, ' ', FORMAT(p_monto, 2), ' (propuesta ', v_numero, ').',
                  ' Pendiente de validación para iniciar la programación del servicio.'),
           'orden_compra', v_id_oc, NOW(), p_id_usuario
    FROM usuario u
    WHERE u.eliminado_en IS NULL AND u.estado = 'activo' AND u.id_usuario <> p_id_usuario
      AND ((u.area IN ('operaciones', 'administracion') AND u.rol_sistema IN ('supervisor', 'administrador'))
           OR u.id_usuario = v_id_responsable);

    SET v_notificados = ROW_COUNT();

    COMMIT;

    SELECT 2 AS IdTipoMensaje,
           'Orden de compra registrada. Se notificó a Contabilidad y Operaciones.' AS Mensaje;
    SELECT v_id_oc AS id_oc, v_numero_oc AS numero_oc, 'pendiente_validacion' AS estado,
           v_estado_cob AS estado_cobertura, v_pct AS cobertura_pct, v_diferencia AS diferencia,
           p_fecha_oc + INTERVAL p_vigencia_dias DAY AS vigencia_hasta,
           'validacion_oc' AS siguiente_etapa, v_notificados AS notificados;
END$$

DELIMITER ;
