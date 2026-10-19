-- HU-27 Asignar (o corregir) el monto que una OC aplica a una propuesta.
-- Acción oc_distribuir, OC del área del usuario, no anulada ni vencida y sin observación abierta.
-- La propuesta destino debe estar ya vinculada a la OC o ser una propuesta aceptada del mismo cliente
-- y moneda, en el alcance del usuario.
-- Reglas: el monto no puede exceder el saldo disponible de la OC ni lo pendiente de la propuesta.
--   p_monto = 0 quita la aplicación (salvo la propuesta principal de la OC).
-- p_solo_validar = 1 devuelve el saldo antes y después sin guardar (cálculo en tiempo real).
-- Resultados: 1 mensaje, 2 resultado (saldo antes/después, cobertura de la propuesta).
DROP PROCEDURE IF EXISTS SP_DistribuirOrdenCompraInterno;

DELIMITER $$

CREATE PROCEDURE SP_DistribuirOrdenCompraInterno(
    IN p_id_usuario   BIGINT,
    IN p_id_oc        BIGINT,
    IN p_id_propuesta BIGINT,
    IN p_monto        DECIMAL(14,2),
    IN p_solo_validar TINYINT
)
proc: BEGIN
    DECLARE v_dias_sin_resp INT;
    DECLARE v_meta          INT;
    DECLARE v_sla_horas     INT;
    DECLARE v_alerta_horas  INT;
    DECLARE v_existe        INT DEFAULT 0;
    DECLARE v_estado        VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_vencida       TINYINT DEFAULT 0;
    DECLARE v_validada      TINYINT DEFAULT 0;
    DECLARE v_id_cliente    BIGINT;
    DECLARE v_id_moneda     INT;
    DECLARE v_id_principal  BIGINT;
    DECLARE v_numero_oc     VARCHAR(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_monto_oc      DECIMAL(14,2);
    DECLARE v_asignado_oc   DECIMAL(14,2);
    DECLARE v_vinculada     INT DEFAULT 0;
    DECLARE v_actual        DECIMAL(14,2) DEFAULT 0;
    DECLARE v_otras         DECIMAL(14,2) DEFAULT 0;
    DECLARE v_total_prop    DECIMAL(14,2);
    DECLARE v_numero_prop   VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_resp_prop  BIGINT;
    DECLARE v_candidata     INT DEFAULT 0;
    DECLARE v_saldo_antes   DECIMAL(14,2);
    DECLARE v_saldo_despues DECIMAL(14,2);
    DECLARE v_pendiente     DECIMAL(14,2);
    DECLARE v_simbolo       VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_usuario       VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_oc;
        DROP TEMPORARY TABLE IF EXISTS tmp_seg;
        DROP TEMPORARY TABLE IF EXISTS tmp_seg_base;
        GET DIAGNOSTICS CONDITION 1
            @err_msg  = MESSAGE_TEXT,
            @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje,
               CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF FN_PermisoAccion(p_id_usuario, 'oc_distribuir') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para distribuir el saldo de órdenes de compra.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_CalcularOrdenesCompra(p_id_usuario, p_id_oc);
    SELECT COUNT(*), MAX(estado_bd), MAX(vencida), MAX(validada), MAX(id_cliente), MAX(id_moneda), MAX(id_propuesta),
           MAX(numero_oc), MAX(monto_oc), MAX(monto_asignado_oc)
      INTO v_existe, v_estado, v_vencida, v_validada, v_id_cliente, v_id_moneda, v_id_principal,
           v_numero_oc, v_monto_oc, v_asignado_oc
    FROM tmp_oc;
    DROP TEMPORARY TABLE IF EXISTS tmp_oc;

    IF v_existe = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'La orden de compra no existe o no pertenece a tu área.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_estado = 'anulada' OR v_vencida = 1 THEN
        SELECT 1 AS IdTipoMensaje, 'La orden de compra está anulada o vencida: no se puede distribuir su saldo.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF EXISTS (SELECT 1 FROM orden_compra_observacion WHERE id_oc = p_id_oc AND estado = 'abierta' AND eliminado_en IS NULL) THEN
        SELECT 1 AS IdTipoMensaje, 'La orden de compra tiene una observación abierta: corríjala antes de distribuir su saldo.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF p_monto IS NULL OR p_monto < 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Ingrese el monto a aplicar.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Propuesta destino
    SELECT COUNT(*), IFNULL(SUM(monto_asignado), 0) INTO v_vinculada, v_actual
    FROM oc_propuesta WHERE id_oc = p_id_oc AND id_propuesta = p_id_propuesta AND eliminado_en IS NULL;

    IF v_vinculada = 0 THEN
        CALL SP_CalcularSeguimientoComercial(p_id_usuario, p_id_propuesta, v_dias_sin_resp, v_meta, v_sla_horas, v_alerta_horas);
        SELECT COUNT(*) INTO v_candidata
        FROM tmp_seg
        WHERE estado_seguimiento = 'aceptada' AND id_cliente = v_id_cliente AND id_moneda = v_id_moneda;
        DROP TEMPORARY TABLE IF EXISTS tmp_seg;
        DROP TEMPORARY TABLE IF EXISTS tmp_seg_base;

        IF v_candidata = 0 THEN
            SELECT 1 AS IdTipoMensaje,
                   'La propuesta destino debe estar aceptada por el cliente y ser del mismo cliente y moneda que la OC.' AS Mensaje;
            LEAVE proc;
        END IF;
        IF p_monto = 0 THEN
            SELECT 1 AS IdTipoMensaje, 'Ingrese un monto a aplicar mayor a 0.' AS Mensaje;
            LEAVE proc;
        END IF;
    END IF;

    IF p_monto = 0 AND p_id_propuesta = v_id_principal THEN
        SELECT 1 AS IdTipoMensaje, 'No se puede quitar la aplicación a la propuesta principal de la OC.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT p.total, CONCAT(p.numero, ' v', p.version), COALESCE(p.id_responsable, p.id_creador)
      INTO v_total_prop, v_numero_prop, v_id_resp_prop
    FROM propuesta_comercial p WHERE p.id_propuesta = p_id_propuesta;

    SELECT IFNULL(SUM(op.monto_asignado), 0) INTO v_otras
    FROM oc_propuesta op
    JOIN orden_compra o2 ON o2.id_oc = op.id_oc AND o2.eliminado_en IS NULL AND o2.estado <> 'anulada'
             AND o2.id_moneda = (SELECT pz.id_moneda FROM propuesta_comercial pz WHERE pz.id_propuesta = op.id_propuesta)
    WHERE op.id_propuesta = p_id_propuesta AND op.id_oc <> p_id_oc AND op.eliminado_en IS NULL;

    SET v_saldo_antes   = v_monto_oc - v_asignado_oc;
    SET v_saldo_despues = v_saldo_antes + v_actual - p_monto;
    SET v_pendiente     = GREATEST(v_total_prop - v_otras - v_actual, 0);

    IF p_monto > v_saldo_antes + v_actual THEN
        SELECT 1 AS IdTipoMensaje,
               CONCAT('El monto no puede exceder el saldo disponible de la OC (', FORMAT(v_saldo_antes + v_actual, 2), ').') AS Mensaje;
        LEAVE proc;
    END IF;
    IF p_monto > v_total_prop - v_otras THEN
        SELECT 1 AS IdTipoMensaje,
               CONCAT('El monto excede lo pendiente de la propuesta (', FORMAT(GREATEST(v_total_prop - v_otras, 0), 2), ').') AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_vinculada > 0 AND p_monto = v_actual THEN
        SELECT 1 AS IdTipoMensaje, 'No hay cambios en el monto aplicado.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT MAX(String2) INTO v_simbolo FROM tabla_maestra WHERE IdMaestro = 1 AND IdEmpresa = 1 AND Num1 = v_id_moneda;

    IF IFNULL(p_solo_validar, 0) = 1 THEN
        SELECT 2 AS IdTipoMensaje, 'Validado.' AS Mensaje;
        SELECT p_id_oc AS id_oc, p_id_propuesta AS id_propuesta, v_numero_prop AS propuesta,
               v_saldo_antes AS saldo_antes, v_saldo_despues AS saldo_despues,
               v_actual AS aplicado_antes, p_monto AS aplicado_despues,
               GREATEST(v_total_prop - v_otras - p_monto, 0) AS pendiente_propuesta,
               IF(v_total_prop - v_otras - p_monto < 0.005, 'cubierto', IF(v_otras + p_monto > 0, 'parcial', 'pendiente')) AS estado_cobertura;
        LEAVE proc;
    END IF;

    START TRANSACTION;

    IF v_vinculada = 0 THEN
        INSERT INTO oc_propuesta (id_oc, id_propuesta, monto_asignado, creado_por)
        VALUES (p_id_oc, p_id_propuesta, p_monto, p_id_usuario);
    ELSEIF p_monto = 0 THEN
        UPDATE oc_propuesta SET eliminado_en = NOW(), eliminado_por = p_id_usuario
        WHERE id_oc = p_id_oc AND id_propuesta = p_id_propuesta AND eliminado_en IS NULL;
    ELSE
        UPDATE oc_propuesta SET monto_asignado = p_monto, modificado_por = p_id_usuario
        WHERE id_oc = p_id_oc AND id_propuesta = p_id_propuesta AND eliminado_en IS NULL;
    END IF;

    -- Saldos guardados de la OC (si ya está validada, lo asignado queda aplicado)
    UPDATE orden_compra SET
        monto_aplicado = IF(v_validada = 1, v_monto_oc - v_saldo_despues, monto_aplicado),
        saldo          = IF(v_validada = 1, v_saldo_despues, saldo),
        estado         = IF(v_validada = 1 AND estado IN ('vigente', 'cobertura_parcial'),
                            IF(v_saldo_despues > 0.005, 'cobertura_parcial', 'vigente'), estado),
        modificado_por = p_id_usuario
    WHERE id_oc = p_id_oc;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo,
                                  descripcion, id_usuario, registrado_en, metadata)
    VALUES ('orden_compra', p_id_oc, 'distribuir_oc', NULL, NULL,
            CONCAT(IF(p_monto = 0, 'Se quitó la aplicación a ', 'Aplicó '), IF(p_monto = 0, '', CONCAT(v_simbolo, ' ', FORMAT(p_monto, 2), ' a ')),
                   'la propuesta ', v_numero_prop,
                   IF(v_vinculada > 0 AND p_monto > 0, CONCAT(' (antes ', v_simbolo, ' ', FORMAT(v_actual, 2), ')'), ''),
                   '. Saldo de la OC: ', v_simbolo, ' ', FORMAT(v_saldo_despues, 2), '.'),
            p_id_usuario, NOW(),
            JSON_OBJECT('id_propuesta', p_id_propuesta, 'monto_anterior', v_actual, 'monto_nuevo', p_monto,
                        'saldo_antes', v_saldo_antes, 'saldo_despues', v_saldo_despues));

    -- Aviso al responsable de la propuesta destino
    SELECT CONCAT(nombre, ' ', apellido) INTO v_usuario FROM usuario WHERE id_usuario = p_id_usuario;
    INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
    SELECT v_id_resp_prop, 5,
           LEFT(CONCAT('Saldo de OC aplicado a ', v_numero_prop), 150),
           CONCAT(v_usuario, IF(p_monto = 0, ' quitó la aplicación de la OC ', CONCAT(' aplicó ', v_simbolo, ' ', FORMAT(p_monto, 2), ' de la OC ')),
                  v_numero_oc, ' a la propuesta ', v_numero_prop, '.'),
           'orden_compra', p_id_oc, NOW(), p_id_usuario
    FROM DUAL WHERE v_id_resp_prop IS NOT NULL AND v_id_resp_prop <> p_id_usuario;

    COMMIT;

    SELECT 2 AS IdTipoMensaje, IF(p_monto = 0, 'Aplicación quitada.', 'Distribución guardada.') AS Mensaje;
    SELECT p_id_oc AS id_oc, p_id_propuesta AS id_propuesta, v_numero_prop AS propuesta,
           v_saldo_antes AS saldo_antes, v_saldo_despues AS saldo_despues,
           v_actual AS aplicado_antes, p_monto AS aplicado_despues,
           GREATEST(v_total_prop - v_otras - p_monto, 0) AS pendiente_propuesta,
           IF(v_total_prop - v_otras - p_monto < 0.005, 'cubierto', IF(v_otras + p_monto > 0, 'parcial', 'pendiente')) AS estado_cobertura;
END$$

DELIMITER ;


-- SP_DistribuirOrdenCompra: punto de entrada. Toma un bloqueo por cliente (GET_LOCK) para que dos operaciones simultáneas
-- sobre las OC del mismo cliente (registro, complementaria, distribución, liberación) no pasen las mismas
-- validaciones a la vez (OC duplicadas, saldo sobreasignado o doble liberación). La lógica está en SP_DistribuirOrdenCompraInterno.
DROP PROCEDURE IF EXISTS SP_DistribuirOrdenCompra;

DELIMITER $$

CREATE PROCEDURE SP_DistribuirOrdenCompra(
    IN p_id_usuario   BIGINT,
    IN p_id_oc        BIGINT,
    IN p_id_propuesta BIGINT,
    IN p_monto        DECIMAL(14,2),
    IN p_solo_validar TINYINT
)
proc: BEGIN
    DECLARE v_bloqueo VARCHAR(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        DO RELEASE_LOCK(v_bloqueo);
        GET DIAGNOSTICS CONDITION 1
            @err_msg  = MESSAGE_TEXT,
            @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje,
               CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SET v_bloqueo = CONCAT('tw_oc_cliente_', IFNULL((SELECT id_cliente FROM orden_compra WHERE id_oc = p_id_oc), 0));
    IF IFNULL(GET_LOCK(v_bloqueo, 15), 0) <> 1 THEN
        SELECT 1 AS IdTipoMensaje,
               'Hay otra operación en curso sobre las órdenes de compra de este cliente. Intente nuevamente en unos segundos.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_DistribuirOrdenCompraInterno(p_id_usuario, p_id_oc, p_id_propuesta, p_monto, p_solo_validar);

    DO RELEASE_LOCK(v_bloqueo);
END$$

DELIMITER ;
