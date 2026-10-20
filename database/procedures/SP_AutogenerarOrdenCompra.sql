-- HU-27 (Sprint 4) OC autogenerada: "No, autogenerar OC provisional" al aceptar la propuesta.
-- Crea la OC OC-AUTO-NNNN-AAAA sin PDF, en estado RECIBIDA, por el saldo de la propuesta (100% de cobertura),
-- para que Operaciones pueda programar y ejecutar el servicio. Se reemplaza después por la OC del cliente
-- (SP_RegistrarOrdenCompra con p_id_oc_reemplaza).
-- Reglas: acción oc_registrar; propuesta aceptada, del área del usuario y sin órdenes de compra.
-- Resultados: 1 mensaje, 2 OC autogenerada.
DROP PROCEDURE IF EXISTS SP_AutogenerarOrdenCompraInterno;

DELIMITER $$

CREATE PROCEDURE SP_AutogenerarOrdenCompraInterno(
    IN p_id_usuario   BIGINT,
    IN p_id_propuesta BIGINT
)
proc: BEGIN
    DECLARE v_existe     INT DEFAULT 0;
    DECLARE v_total      DECIMAL(14,2);
    DECLARE v_saldo      DECIMAL(14,2);
    DECLARE v_id_cliente BIGINT;
    DECLARE v_id_moneda  INT;
    DECLARE v_id_resp    BIGINT;
    DECLARE v_numero_prop VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_correl     INT;
    DECLARE v_numero_oc  VARCHAR(50)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_oc      BIGINT;
    DECLARE v_usuario    VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cliente    VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_simbolo    VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_oc_disp;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF FN_PermisoAccion(p_id_usuario, 'oc_registrar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para registrar órdenes de compra.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_CalcularPropuestasDisponiblesOc(p_id_usuario, NULL, NULL);
    SELECT COUNT(*), MAX(total), MAX(saldo), MAX(id_cliente), MAX(id_moneda), MAX(id_responsable),
           MAX(CONCAT(numero, ' v', version)), MAX(moneda_simbolo), MAX(razon_social)
      INTO v_existe, v_total, v_saldo, v_id_cliente, v_id_moneda, v_id_resp, v_numero_prop, v_simbolo, v_cliente
    FROM tmp_oc_disp WHERE id_propuesta = p_id_propuesta;
    DROP TEMPORARY TABLE IF EXISTS tmp_oc_disp;

    IF v_existe = 0 THEN
        SELECT 1 AS IdTipoMensaje,
               'La propuesta no está aceptada por el cliente, no es de tu área o ya está cubierta por órdenes de compra.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF EXISTS (SELECT 1 FROM oc_propuesta op JOIN orden_compra oc ON oc.id_oc = op.id_oc
               WHERE op.id_propuesta = p_id_propuesta AND op.eliminado_en IS NULL
                 AND oc.eliminado_en IS NULL AND oc.estado <> 'anulada') THEN
        SELECT 1 AS IdTipoMensaje,
               'La propuesta ya tiene una orden de compra: registre la OC del cliente en lugar de autogenerar una.' AS Mensaje;
        LEAVE proc;
    END IF;

    START TRANSACTION;

    -- Correlativo del año: OC-AUTO-0001-2026
    SELECT IFNULL(MAX(CAST(SUBSTRING_INDEX(SUBSTRING_INDEX(numero_oc, '-', 3), '-', -1) AS UNSIGNED)), 0) + 1
      INTO v_correl
    FROM orden_compra
    WHERE es_autogenerada = 1 AND numero_oc LIKE CONCAT('OC-AUTO-%-', YEAR(CURDATE()))
    FOR UPDATE;
    SET v_numero_oc = CONCAT('OC-AUTO-', LPAD(v_correl, 4, '0'), '-', YEAR(CURDATE()));

    INSERT INTO orden_compra (
        numero_oc, es_autogenerada, id_propuesta, id_cliente, id_moneda, monto_total,
        id_condicion_pago, igv_incluido, igv_pct, factura_igual_oc,
        fecha_oc, fecha_recepcion, observaciones, estado, fecha_registro, creado_por)
    SELECT v_numero_oc, 1, p.id_propuesta, p.id_cliente, p.id_moneda, v_saldo,
           p.id_condicion_pago, p.aplica_igv, IF(p.aplica_igv = 1, p.igv_pct, NULL), 1,
           CURDATE(), CURDATE(),
           'OC provisional generada automáticamente al aceptar la propuesta. Debe reemplazarse por la OC del cliente antes de facturar.',
           'recibida', NOW(), p_id_usuario
    FROM propuesta_comercial p WHERE p.id_propuesta = p_id_propuesta;

    SET v_id_oc = LAST_INSERT_ID();

    INSERT INTO oc_propuesta (id_oc, id_propuesta, monto_asignado, estado_validacion, creado_por)
    VALUES (v_id_oc, p_id_propuesta, v_saldo, 'pendiente', p_id_usuario);

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion,
                                  id_usuario, registrado_en, metadata)
    VALUES ('orden_compra', v_id_oc, 'autogenerar_oc', NULL, 'recibida',
            CONCAT('OC provisional ', v_numero_oc, ' generada al aceptar la propuesta ', v_numero_prop,
                   ' por ', IFNULL(v_simbolo, ''), ' ', FORMAT(v_saldo, 2), ' (100% de cobertura).'),
            p_id_usuario, NOW(), JSON_OBJECT('id_propuesta', p_id_propuesta, 'monto', v_saldo));

    CALL SP_PasarExpedientesAProgramacion(v_id_oc, p_id_usuario);

    SELECT CONCAT(nombre, ' ', apellido) INTO v_usuario FROM usuario WHERE id_usuario = p_id_usuario;
    INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
    SELECT u.id_usuario, 5,
           CONCAT('OC provisional: ', v_numero_oc),
           CONCAT(v_usuario, ' generó la OC provisional ', v_numero_oc, ' de ', IFNULL(v_cliente, 'el cliente'),
                  ' (propuesta ', v_numero_prop, '). Permite ejecutar el servicio; se reemplazará por la OC del cliente.'),
           'orden_compra', v_id_oc, NOW(), p_id_usuario
    FROM usuario u
    WHERE u.eliminado_en IS NULL AND u.estado = 'activo' AND u.id_usuario <> p_id_usuario
      AND ((u.area IN ('operaciones', 'administracion') AND u.rol_sistema IN ('supervisor', 'administrador'))
           OR u.id_usuario = v_id_resp);

    COMMIT;

    SELECT 2 AS IdTipoMensaje,
           CONCAT('OC provisional ', v_numero_oc, ' generada. Reemplázala por la OC del cliente cuando llegue.') AS Mensaje;
    SELECT v_id_oc AS id_oc, v_numero_oc AS numero_oc, 'recibida' AS estado, v_saldo AS monto_total, v_id_moneda AS id_moneda;
END$$

DELIMITER ;


DROP PROCEDURE IF EXISTS SP_AutogenerarOrdenCompra;

DELIMITER $$

CREATE PROCEDURE SP_AutogenerarOrdenCompra(
    IN p_id_usuario   BIGINT,
    IN p_id_propuesta BIGINT
)
proc: BEGIN
    DECLARE v_bloqueo VARCHAR(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        DO RELEASE_LOCK(v_bloqueo);
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SET v_bloqueo = CONCAT('tw_oc_cliente_', IFNULL((SELECT id_cliente FROM propuesta_comercial WHERE id_propuesta = p_id_propuesta), 0));
    IF IFNULL(GET_LOCK(v_bloqueo, 15), 0) <> 1 THEN
        SELECT 1 AS IdTipoMensaje,
               'Hay otra operación en curso sobre las órdenes de compra de este cliente. Intente nuevamente en unos segundos.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_AutogenerarOrdenCompraInterno(p_id_usuario, p_id_propuesta);

    DO RELEASE_LOCK(v_bloqueo);
END$$

DELIMITER ;
