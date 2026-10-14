-- HU-26 Validar definitivamente la orden de compra.
-- Acción oc_validar, OC del área del usuario, pendiente de validación y sin observación abierta.
-- Las verificaciones automáticas bloqueantes deben cumplirse y el validador debe confirmar contra la OC física
-- los ítems que lo requieren (p_confirmados = códigos separados por coma: razon_social,ruc,moneda,monto,pdf_legible).
-- El monto es informativo: una OC que no cubre toda la propuesta se valida y queda en saldo_insuficiente
-- (se ve "bloqueada" y no se puede liberar) hasta que se valida su OC complementaria, que la pasa a vigente.
-- Al validar: estado vigente (cobertura_parcial si la OC deja saldo a favor, saldo_insuficiente si no alcanza),
-- monto aplicado y saldo,
-- validador, bloqueos de la OC en el expediente resueltos, auditoría validar_oc con el checklist y
-- notificación al responsable comercial y a Operaciones (OC lista para programación).
-- HU-27: el monto aplicado es el requerido neto (lo que otras OC no cubren de sus propuestas).
-- Resultados: 1 mensaje, 2 OC validada.
DROP PROCEDURE IF EXISTS SP_ValidarOrdenCompraInterno;

DELIMITER $$

CREATE PROCEDURE SP_ValidarOrdenCompraInterno(
    IN p_id_usuario  BIGINT,
    IN p_id_oc       BIGINT,
    IN p_confirmados VARCHAR(300)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_comentario  VARCHAR(1000) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_existe       INT DEFAULT 0;
    DECLARE v_estado       VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado_nuevo VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cobertura    VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_total        DECIMAL(14,2);
    DECLARE v_monto        DECIMAL(14,2);
    DECLARE v_id_resp      BIGINT;
    DECLARE v_id_exp       BIGINT;
    DECLARE v_numero       VARCHAR(50)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_obs_abierta  INT DEFAULT 0;
    DECLARE v_fallan       VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_sin_conf     VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_checklist    JSON;
    DECLARE v_confirmados  VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_usuario      VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_notificados  INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_oc;
        DROP TEMPORARY TABLE IF EXISTS tmp_oc_check;
        GET DIAGNOSTICS CONDITION 1
            @err_msg  = MESSAGE_TEXT,
            @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje,
               CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SET v_confirmados = REPLACE(LOWER(IFNULL(p_confirmados, '')), ' ', '');

    IF FN_PermisoAccion(p_id_usuario, 'oc_validar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para validar órdenes de compra.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_CalcularOrdenesCompra(p_id_usuario, p_id_oc);
    SELECT COUNT(*), MAX(estado_bd), MAX(cobertura_proyectada), MAX(monto_requerido_neto), MAX(monto_oc),
           MAX(id_responsable), MAX(id_expediente), MAX(numero_oc)
      INTO v_existe, v_estado, v_cobertura, v_total, v_monto, v_id_resp, v_id_exp, v_numero
    FROM tmp_oc;
    DROP TEMPORARY TABLE IF EXISTS tmp_oc;

    IF v_existe = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'La orden de compra no existe o no pertenece a tu área.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_estado <> 'pendiente_validacion' THEN
        SELECT 1 AS IdTipoMensaje,
               IF(v_estado = 'anulada', 'La orden de compra está anulada.', 'La orden de compra ya fue validada.') AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT COUNT(*) INTO v_obs_abierta
    FROM orden_compra_observacion WHERE id_oc = p_id_oc AND estado = 'abierta' AND eliminado_en IS NULL;
    IF v_obs_abierta > 0 THEN
        SELECT 1 AS IdTipoMensaje,
               'La OC tiene una observación abierta: debe corregirse y reenviarse a validación (Guardar y revalidar).' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_EvaluarValidacionOrdenCompra(p_id_oc);

    SELECT GROUP_CONCAT(descripcion ORDER BY orden SEPARATOR ', ') INTO v_fallan
    FROM tmp_oc_check WHERE cumple_auto = 0 AND bloqueante = 1;

    SELECT GROUP_CONCAT(descripcion ORDER BY orden SEPARATOR ', ') INTO v_sin_conf
    FROM tmp_oc_check WHERE requiere_confirmacion = 1 AND FIND_IN_SET(codigo, v_confirmados) = 0;

    SELECT JSON_ARRAYAGG(JSON_OBJECT('codigo', codigo, 'descripcion', descripcion, 'valor_sistema', valor_sistema,
                                     'cumple', cumple_auto,
                                     'confirmado', IF(requiere_confirmacion = 1, FIND_IN_SET(codigo, v_confirmados) > 0, NULL)))
      INTO v_checklist
    FROM tmp_oc_check;

    DROP TEMPORARY TABLE IF EXISTS tmp_oc_check;

    IF v_fallan IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, CONCAT('No se puede validar: no es conforme ', v_fallan, '. Observe la OC.') AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_sin_conf IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, CONCAT('Confirme contra la OC física: ', v_sin_conf, '.') AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_estado_nuevo = CASE v_cobertura WHEN 'con_saldo'    THEN 'cobertura_parcial'
                                          WHEN 'insuficiente' THEN 'saldo_insuficiente'
                                          ELSE                     'vigente' END;

    START TRANSACTION;

    UPDATE orden_compra SET
        estado                = v_estado_nuevo,
        id_validado_por       = p_id_usuario,
        id_motivo_observacion = NULL,
        monto_aplicado        = LEAST(v_total, v_monto),
        saldo                 = v_monto - LEAST(v_total, v_monto),
        modificado_por        = p_id_usuario
    WHERE id_oc = p_id_oc;

    -- HU-27: si es una OC complementaria que completa la propuesta, la OC de origen deja de estar en saldo insuficiente
    IF v_estado_nuevo <> 'saldo_insuficiente' THEN
        UPDATE orden_compra o
        JOIN orden_compra c ON c.id_oc = p_id_oc AND c.tipo_oc = 'complementaria'
        SET o.estado = 'vigente', o.modificado_por = p_id_usuario
        WHERE o.id_oc = c.id_oc_origen AND o.estado = 'saldo_insuficiente';
    END IF;

    -- Bloqueos de esta OC en los expedientes: resueltos (vinculados por id de OC)
    UPDATE expediente_bloqueador SET resuelto = 1, fecha_resolucion = NOW(), resuelto_por = p_id_usuario,
                                     sustento = 'OC validada.', modificado_por = p_id_usuario
    WHERE origen_tipo = 'orden_compra' AND id_origen = p_id_oc AND resuelto = 0 AND eliminado_en IS NULL;

    IF ROW_COUNT() > 0 THEN
            UPDATE expediente_digital e
            SET e.estado = CASE
                    WHEN EXISTS (SELECT 1 FROM expediente_bloqueador b WHERE b.id_expediente = e.id_expediente
                                 AND b.resuelto = 0 AND b.eliminado_en IS NULL AND b.clase = 'bloqueo')   THEN 'bloqueado'
                    WHEN EXISTS (SELECT 1 FROM expediente_bloqueador b WHERE b.id_expediente = e.id_expediente
                                 AND b.resuelto = 0 AND b.eliminado_en IS NULL AND b.clase = 'excepcion') THEN 'con_excepcion'
                    ELSE 'activo' END,
                e.modificado_por = p_id_usuario
            WHERE e.estado <> 'cerrado'
              AND e.id_expediente IN (SELECT b.id_expediente FROM expediente_bloqueador b
                                      WHERE b.origen_tipo = 'orden_compra' AND b.id_origen = p_id_oc);
    END IF;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo,
                                  descripcion, id_usuario, registrado_en, metadata)
    VALUES ('orden_compra', p_id_oc, 'validar_oc', v_estado, v_estado_nuevo,
            CONCAT(IF(v_estado_nuevo = 'saldo_insuficiente',
                      CONCAT('Orden de compra validada con saldo insuficiente: faltan ', FORMAT(v_total - v_monto, 2),
                             ' para cubrir la propuesta (requiere OC complementaria).'),
                      'Orden de compra validada. Checklist conforme.'),
                   IFNULL(CONCAT(' Comentario: ', NULLIF(TRIM(p_comentario), '')), '')),
            p_id_usuario, NOW(),
            JSON_OBJECT('checklist', v_checklist, 'comentario', NULLIF(TRIM(IFNULL(p_comentario, '')), ''),
                        'cobertura', v_cobertura));

    SELECT CONCAT(nombre, ' ', apellido) INTO v_usuario FROM usuario WHERE id_usuario = p_id_usuario;

    INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
    SELECT u.id_usuario, 5,
           LEFT(CONCAT('OC validada: ', v_numero), 150),
           IF(v_estado_nuevo = 'saldo_insuficiente',
              CONCAT(v_usuario, ' validó la OC ', v_numero, ' con saldo insuficiente: faltan ', FORMAT(v_total - v_monto, 2),
                     '. Registre una OC complementaria para poder liberarla.'),
              CONCAT(v_usuario, ' validó la OC ', v_numero, '. Lista para liberar a programación.')),
           'orden_compra', p_id_oc, NOW(), p_id_usuario
    FROM usuario u
    WHERE u.eliminado_en IS NULL AND u.estado = 'activo' AND u.id_usuario <> p_id_usuario
      AND ((u.area = 'operaciones' AND u.rol_sistema IN ('supervisor', 'administrador') AND v_estado_nuevo <> 'saldo_insuficiente')
           OR u.id_usuario = v_id_resp);

    SET v_notificados = ROW_COUNT();

    COMMIT;

    SELECT 2 AS IdTipoMensaje,
           IF(v_estado_nuevo = 'saldo_insuficiente',
              'Orden de compra validada con saldo insuficiente. Registre una OC complementaria para poder liberarla.',
              'Orden de compra validada.') AS Mensaje;
    SELECT p_id_oc AS id_oc, v_numero AS numero_oc, v_estado_nuevo AS estado, v_cobertura AS estado_cobertura,
           NOW() AS fecha_validacion, v_usuario AS validado_por, v_notificados AS notificados;
END$$

DELIMITER ;


-- SP_ValidarOrdenCompra: punto de entrada. Toma el mismo bloqueo por cliente (GET_LOCK) que el registro, la distribución y la
-- liberación de OC, para que no se crucen con ellas. La lógica está en SP_ValidarOrdenCompraInterno.
DROP PROCEDURE IF EXISTS SP_ValidarOrdenCompra;

DELIMITER $$

CREATE PROCEDURE SP_ValidarOrdenCompra(
    IN p_id_usuario  BIGINT,
    IN p_id_oc       BIGINT,
    IN p_confirmados VARCHAR(300)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_comentario  VARCHAR(1000) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
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

    CALL SP_ValidarOrdenCompraInterno(p_id_usuario, p_id_oc, p_confirmados, p_comentario);

    DO RELEASE_LOCK(v_bloqueo);
END$$

DELIMITER ;
