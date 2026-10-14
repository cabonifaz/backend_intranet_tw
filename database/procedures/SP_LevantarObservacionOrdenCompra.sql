-- HU-26 Levantar la observación de una orden de compra sin editarla (ej. el jefe la observó por error o la
-- observación era de proceso y no de datos). La otra forma de levantarla sigue siendo "Guardar y revalidar" (HU-24).
-- Acción oc_validar (jefe comercial), OC del área del usuario, no anulada, y observación abierta de esa OC.
-- Sustento obligatorio (10 a 1000 caracteres): queda en la auditoría.
-- Al levantar: la observación queda 'levantada', la OC vuelve a "Pendiente de validación" (se puede validar),
--   se resuelven los bloqueos que la observación puso en los expedientes, se audita levantar_observacion_oc
--   y se notifica al responsable de corrección.
-- Resultados: 1 mensaje, 2 observación levantada.
DROP PROCEDURE IF EXISTS SP_LevantarObservacionOrdenCompraInterno;

DELIMITER $$

CREATE PROCEDURE SP_LevantarObservacionOrdenCompraInterno(
    IN p_id_usuario     BIGINT,
    IN p_id_oc          BIGINT,
    IN p_id_observacion BIGINT,
    IN p_sustento       VARCHAR(1000) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_existe       INT DEFAULT 0;
    DECLARE v_estado       VARCHAR(30)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_numero       VARCHAR(50)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_sustento     VARCHAR(1000) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_obs_estado   VARCHAR(20)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_resp_corr BIGINT;
    DECLARE v_usuario      VARCHAR(220)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_expedientes  INT DEFAULT 0;
    DECLARE v_notificados  INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_oc;
        DROP TEMPORARY TABLE IF EXISTS tmp_oc_exp_lev;
        GET DIAGNOSTICS CONDITION 1
            @err_msg  = MESSAGE_TEXT,
            @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje,
               CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SET v_sustento = NULLIF(TRIM(IFNULL(p_sustento, '')), '');

    IF FN_PermisoAccion(p_id_usuario, 'oc_validar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para levantar observaciones de órdenes de compra.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_CalcularOrdenesCompra(p_id_usuario, p_id_oc);
    SELECT COUNT(*), MAX(estado_bd), MAX(numero_oc) INTO v_existe, v_estado, v_numero FROM tmp_oc;
    DROP TEMPORARY TABLE IF EXISTS tmp_oc;

    IF v_existe = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'La orden de compra no existe o no pertenece a tu área.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_estado = 'anulada' THEN
        SELECT 1 AS IdTipoMensaje, 'La orden de compra está anulada.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_sustento IS NULL OR CHAR_LENGTH(v_sustento) < 10 THEN
        SELECT 1 AS IdTipoMensaje, 'Indique el sustento para levantar la observación (mínimo 10 caracteres).' AS Mensaje;
        LEAVE proc;
    END IF;

    START TRANSACTION;

    -- Se bloquea la fila para que dos usuarios no la levanten (ni la corrijan) al mismo tiempo
    SELECT estado, id_responsable_correccion INTO v_obs_estado, v_id_resp_corr
    FROM orden_compra_observacion
    WHERE id_observacion = p_id_observacion AND id_oc = p_id_oc AND eliminado_en IS NULL
    FOR UPDATE;

    IF v_obs_estado IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'La observación no existe o no pertenece a esta orden de compra.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_obs_estado <> 'abierta' THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'La observación ya fue levantada.' AS Mensaje;
        LEAVE proc;
    END IF;

    UPDATE orden_compra_observacion SET
        estado = 'levantada', fecha_levantamiento = NOW(), levantada_por = p_id_usuario, modificado_por = p_id_usuario
    WHERE id_observacion = p_id_observacion;

    -- La OC sigue pendiente de validación; solo se quita el motivo si ya no queda otra observación abierta
    UPDATE orden_compra SET id_motivo_observacion = NULL, modificado_por = p_id_usuario
    WHERE id_oc = p_id_oc
      AND NOT EXISTS (SELECT 1 FROM orden_compra_observacion o
                      WHERE o.id_oc = p_id_oc AND o.estado = 'abierta' AND o.eliminado_en IS NULL);

    -- Bloqueos que la OC puso en los expedientes (vinculados por id de OC): resueltos y estado recalculado
    DROP TEMPORARY TABLE IF EXISTS tmp_oc_exp_lev;
    CREATE TEMPORARY TABLE tmp_oc_exp_lev AS
    SELECT DISTINCT id_expediente FROM expediente_bloqueador
    WHERE origen_tipo = 'orden_compra' AND id_origen = p_id_oc AND resuelto = 0 AND eliminado_en IS NULL;

    UPDATE expediente_bloqueador SET resuelto = 1, fecha_resolucion = NOW(), resuelto_por = p_id_usuario,
                                     sustento = LEFT(CONCAT('Observación de la OC levantada: ', v_sustento), 1000),
                                     modificado_por = p_id_usuario
    WHERE origen_tipo = 'orden_compra' AND id_origen = p_id_oc AND resuelto = 0 AND eliminado_en IS NULL;

    UPDATE expediente_digital e
    JOIN tmp_oc_exp_lev x ON x.id_expediente = e.id_expediente
    SET e.estado = CASE
            WHEN EXISTS (SELECT 1 FROM expediente_bloqueador b WHERE b.id_expediente = e.id_expediente
                         AND b.resuelto = 0 AND b.eliminado_en IS NULL AND b.clase = 'bloqueo')   THEN 'bloqueado'
            WHEN EXISTS (SELECT 1 FROM expediente_bloqueador b WHERE b.id_expediente = e.id_expediente
                         AND b.resuelto = 0 AND b.eliminado_en IS NULL AND b.clase = 'excepcion') THEN 'con_excepcion'
            ELSE 'activo' END,
        e.modificado_por = p_id_usuario
    WHERE e.estado <> 'cerrado';

    SELECT COUNT(*) INTO v_expedientes FROM tmp_oc_exp_lev;
    DROP TEMPORARY TABLE IF EXISTS tmp_oc_exp_lev;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo,
                                  descripcion, id_usuario, registrado_en, metadata)
    VALUES ('orden_compra', p_id_oc, 'levantar_observacion_oc', 'observada', v_estado,
            LEFT(CONCAT('Observación levantada sin editar la OC. Sustento: ', v_sustento), 1000),
            p_id_usuario, NOW(),
            JSON_OBJECT('id_observacion', p_id_observacion, 'sustento', v_sustento,
                        'expedientes_desbloqueados', v_expedientes));

    SELECT CONCAT(nombre, ' ', apellido) INTO v_usuario FROM usuario WHERE id_usuario = p_id_usuario;

    INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
    SELECT u.id_usuario, 5,
           LEFT(CONCAT('Observación levantada: OC ', v_numero), 150),
           LEFT(CONCAT(v_usuario, ' levantó la observación de la OC ', v_numero, '. Ya no necesita corregirla. Sustento: ',
                       v_sustento), 1000),
           'orden_compra', p_id_oc, NOW(), p_id_usuario
    FROM usuario u
    WHERE u.id_usuario = v_id_resp_corr AND u.id_usuario <> p_id_usuario
      AND u.eliminado_en IS NULL AND u.estado = 'activo';

    SET v_notificados = ROW_COUNT();

    COMMIT;

    SELECT 2 AS IdTipoMensaje, 'Observación levantada. La OC queda pendiente de validación.' AS Mensaje;
    SELECT p_id_observacion AS id_observacion, p_id_oc AS id_oc, v_numero AS numero_oc,
           v_estado AS estado, 'pendiente_validacion' AS estado_visual,
           NOW() AS fecha_levantamiento, v_usuario AS levantada_por,
           v_expedientes AS expedientes_desbloqueados, v_notificados AS notificados;
END$$

DELIMITER ;


-- SP_LevantarObservacionOrdenCompra: punto de entrada. Toma el mismo bloqueo por cliente (GET_LOCK) que el resto de
-- operaciones de OC, para no cruzarse con una validación o edición. La lógica está en SP_LevantarObservacionOrdenCompraInterno.
DROP PROCEDURE IF EXISTS SP_LevantarObservacionOrdenCompra;

DELIMITER $$

CREATE PROCEDURE SP_LevantarObservacionOrdenCompra(
    IN p_id_usuario     BIGINT,
    IN p_id_oc          BIGINT,
    IN p_id_observacion BIGINT,
    IN p_sustento       VARCHAR(1000) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
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

    CALL SP_LevantarObservacionOrdenCompraInterno(p_id_usuario, p_id_oc, p_id_observacion, p_sustento);

    DO RELEASE_LOCK(v_bloqueo);
END$$

DELIMITER ;
