-- HU-27 (Sprint 4) OC autogenerada: "No, autogenerar OC provisional" al aceptar la propuesta.
-- Crea la OC OC-AUTO-NNNN-AAAA sin PDF, en estado AUTOGENERADA (SP_CrearOcAutogenerada), por el saldo de la propuesta (100% de cobertura),
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
    DECLARE v_numero_oc  VARCHAR(50)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_oc      BIGINT;
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

    CALL SP_CalcularPropuestasDisponiblesOc(p_id_usuario, NULL, NULL, 0);
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

    CALL SP_CrearOcAutogenerada(p_id_propuesta, v_saldo,
                                'OC provisional generada automáticamente al aceptar la propuesta.',
                                p_id_usuario, v_id_oc, v_numero_oc);

    COMMIT;

    SELECT 2 AS IdTipoMensaje,
           CONCAT('OC provisional ', v_numero_oc, ' generada. Reemplázala por la OC del cliente cuando llegue.') AS Mensaje;
    SELECT v_id_oc AS id_oc, v_numero_oc AS numero_oc, 'autogenerada' AS estado, v_saldo AS monto_total, v_id_moneda AS id_moneda;
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
