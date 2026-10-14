-- HU-26 Observar la orden de compra.
-- Acción oc_validar, OC del área del usuario, pendiente de validación y sin observación abierta.
-- Obligatorio: al menos un motivo tipificado (MOTIVO_OBSERVACION_OC, IdMaestro 14, ids separados por coma),
--   el detalle (10 a 1000 caracteres) y el responsable de corrección (usuario activo del área que puede
--   editar la OC).
-- Al observar: la OC queda OBSERVADA (pendiente de validación con motivo), se bloquea la liberación del
--   expediente (expediente_bloqueador) y se notifica al responsable de corrección.
-- La observación se levanta cuando el responsable corrige la OC con "Guardar y revalidar" (HU-24).
-- Resultados: 1 mensaje, 2 observación registrada.
DROP PROCEDURE IF EXISTS SP_ObservarOrdenCompraInterno;

DELIMITER $$

CREATE PROCEDURE SP_ObservarOrdenCompraInterno(
    IN p_id_usuario     BIGINT,
    IN p_id_oc          BIGINT,
    IN p_motivos        VARCHAR(200)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_detalle        VARCHAR(1000) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_responsable BIGINT
)
proc: BEGIN
    DECLARE v_existe      INT DEFAULT 0;
    DECLARE v_estado      VARCHAR(30)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_resp     BIGINT;
    DECLARE v_id_exp      BIGINT;
    DECLARE v_numero      VARCHAR(50)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_area_resp   VARCHAR(40)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_detalle     VARCHAR(1000) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_motivos     VARCHAR(200)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_n_ids       INT DEFAULT 0;
    DECLARE v_n_validos   INT DEFAULT 0;
    DECLARE v_primer      INT;
    DECLARE v_nombres     VARCHAR(600)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_obs      BIGINT;
    DECLARE v_usuario     VARCHAR(220)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_responsable VARCHAR(220)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_notificados INT DEFAULT 0;
    DECLARE v_bloqueado   TINYINT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_oc;
        GET DIAGNOSTICS CONDITION 1
            @err_msg  = MESSAGE_TEXT,
            @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje,
               CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SET v_detalle = NULLIF(TRIM(IFNULL(p_detalle, '')), '');
    SET v_motivos = REPLACE(IFNULL(p_motivos, ''), ' ', '');

    IF FN_PermisoAccion(p_id_usuario, 'oc_validar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para observar órdenes de compra.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_CalcularOrdenesCompra(p_id_usuario, p_id_oc);
    SELECT COUNT(*), MAX(estado_bd), MAX(id_responsable), MAX(id_expediente), MAX(numero_oc)
      INTO v_existe, v_estado, v_id_resp, v_id_exp, v_numero
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
    IF EXISTS (SELECT 1 FROM orden_compra_observacion WHERE id_oc = p_id_oc AND estado = 'abierta' AND eliminado_en IS NULL) THEN
        SELECT 1 AS IdTipoMensaje, 'La orden de compra ya tiene una observación abierta.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Motivos tipificados: todos deben existir en el catálogo
    IF v_motivos = '' THEN
        SELECT 1 AS IdTipoMensaje, 'Seleccione al menos un motivo de observación.' AS Mensaje;
        LEAVE proc;
    END IF;
    SET v_n_ids = CHAR_LENGTH(v_motivos) - CHAR_LENGTH(REPLACE(v_motivos, ',', '')) + 1;
    SELECT COUNT(*), MIN(Num1), GROUP_CONCAT(String1 ORDER BY Num1 SEPARATOR ', ')
      INTO v_n_validos, v_primer, v_nombres
    FROM tabla_maestra
    WHERE IdMaestro = 14 AND IdEmpresa = 1 AND eliminado_en IS NULL AND FIND_IN_SET(Num1, v_motivos) > 0;
    IF v_n_validos = 0 OR v_n_validos <> v_n_ids THEN
        SELECT 1 AS IdTipoMensaje, 'Uno o más motivos de observación no son válidos.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF v_detalle IS NULL OR CHAR_LENGTH(v_detalle) < 10 THEN
        SELECT 1 AS IdTipoMensaje, 'Describa el problema encontrado en la orden de compra (mínimo 10 caracteres).' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Responsable de corrección: activo, del área de la propuesta y con permiso para editar la OC
    SELECT area INTO v_area_resp FROM usuario WHERE id_usuario = v_id_resp;
    IF p_id_responsable IS NULL OR NOT EXISTS (
           SELECT 1 FROM usuario u
           WHERE u.id_usuario = p_id_responsable AND u.eliminado_en IS NULL AND u.estado = 'activo'
             AND u.area = v_area_resp AND FN_PermisoAccion(u.id_usuario, 'oc_editar') = 1) THEN
        SELECT 1 AS IdTipoMensaje, 'Seleccione un responsable de corrección válido.' AS Mensaje;
        LEAVE proc;
    END IF;

    START TRANSACTION;

    INSERT INTO orden_compra_observacion (id_oc, detalle, id_responsable_correccion, estado, estado_oc_anterior,
                                          fecha_observacion, creado_por)
    VALUES (p_id_oc, v_detalle, p_id_responsable, 'abierta', v_estado, NOW(), p_id_usuario);
    SET v_id_obs = LAST_INSERT_ID();

    INSERT INTO orden_compra_observacion_motivo (id_observacion, id_motivo, creado_por)
    SELECT v_id_obs, Num1, p_id_usuario
    FROM tabla_maestra
    WHERE IdMaestro = 14 AND IdEmpresa = 1 AND eliminado_en IS NULL AND FIND_IN_SET(Num1, v_motivos) > 0;

    UPDATE orden_compra SET
        id_motivo_observacion = v_primer,
        id_validado_por       = NULL,
        monto_aplicado        = 0,
        saldo                 = monto_total,
        modificado_por        = p_id_usuario
    WHERE id_oc = p_id_oc;

    -- Bloquear los expedientes que cubre la OC (propuesta principal y distribuidas). El bloqueo queda
    -- vinculado a la OC por su id: se resuelve al revalidarla o validarla.
    INSERT INTO expediente_bloqueador (id_expediente, clase, descripcion, tipo, etapa, tipo_documental, impacto, critico,
                                       origen_tipo, id_origen, id_responsable, resuelto, creado_por)
    SELECT e.id_expediente, 'bloqueo', LEFT(CONCAT('OC ', v_numero, ' observada: ', v_nombres), 300), 'documento_faltante',
           'orden_compra', 'Orden de compra',
           'No se puede liberar el expediente a programación hasta corregir y revalidar la OC.', 1,
           'orden_compra', p_id_oc, p_id_responsable, 0, p_id_usuario
    FROM expediente_digital e
    WHERE e.eliminado_en IS NULL AND e.estado <> 'cerrado'
      AND e.id_expediente IN (SELECT FN_ExpedienteDePropuesta(x.id_propuesta)
                              FROM (SELECT oc.id_propuesta FROM orden_compra oc WHERE oc.id_oc = p_id_oc
                                    UNION
                                    SELECT op.id_propuesta FROM oc_propuesta op
                                    WHERE op.id_oc = p_id_oc AND op.eliminado_en IS NULL) x);
    SET v_bloqueado = IF(ROW_COUNT() > 0, 1, 0);

    UPDATE expediente_digital e
    SET e.estado = 'bloqueado', e.modificado_por = p_id_usuario
    WHERE e.estado <> 'cerrado'
      AND e.id_expediente IN (SELECT b.id_expediente FROM expediente_bloqueador b
                              WHERE b.origen_tipo = 'orden_compra' AND b.id_origen = p_id_oc
                                AND b.resuelto = 0 AND b.eliminado_en IS NULL);

    SELECT CONCAT(nombre, ' ', apellido) INTO v_usuario FROM usuario WHERE id_usuario = p_id_usuario;
    SELECT CONCAT(nombre, ' ', apellido) INTO v_responsable FROM usuario WHERE id_usuario = p_id_responsable;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo,
                                  descripcion, id_usuario, registrado_en, metadata)
    VALUES ('orden_compra', p_id_oc, 'observar_oc', v_estado, 'observada',
            LEFT(CONCAT('Motivos: ', v_nombres, '. Detalle: ', v_detalle, '. Responsable de corrección: ', v_responsable, '.'), 2000),
            p_id_usuario, NOW(),
            JSON_OBJECT('id_observacion', v_id_obs, 'motivos', v_motivos, 'id_responsable', p_id_responsable,
                        'expediente_bloqueado', v_bloqueado));

    INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
    SELECT p_id_responsable, 5,
           LEFT(CONCAT('OC observada: ', v_numero, ' - corrección asignada'), 150),
           CONCAT(v_usuario, ' observó la OC ', v_numero, ' y te asignó la corrección. Motivos: ', v_nombres,
                  '. Detalle: ', v_detalle, '. Corrige la OC y usa "Guardar y revalidar".'),
           'orden_compra', p_id_oc, NOW(), p_id_usuario
    FROM DUAL WHERE p_id_responsable <> p_id_usuario;

    SET v_notificados = ROW_COUNT();

    COMMIT;

    SELECT 2 AS IdTipoMensaje,
           CONCAT('Observación registrada. Se notificó a ', v_responsable, '.') AS Mensaje;
    SELECT v_id_obs AS id_observacion, p_id_oc AS id_oc, v_numero AS numero_oc, 'observada' AS estado,
           v_nombres AS motivos, p_id_responsable AS id_responsable, v_responsable AS responsable,
           v_bloqueado AS expediente_bloqueado, v_notificados AS notificados;
END$$

DELIMITER ;


-- SP_ObservarOrdenCompra: punto de entrada. Toma el mismo bloqueo por cliente (GET_LOCK) que el registro, la distribución y la
-- liberación de OC, para que no se crucen con ellas. La lógica está en SP_ObservarOrdenCompraInterno.
DROP PROCEDURE IF EXISTS SP_ObservarOrdenCompra;

DELIMITER $$

CREATE PROCEDURE SP_ObservarOrdenCompra(
    IN p_id_usuario     BIGINT,
    IN p_id_oc          BIGINT,
    IN p_motivos        VARCHAR(200)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_detalle        VARCHAR(1000) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_responsable BIGINT
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

    CALL SP_ObservarOrdenCompraInterno(p_id_usuario, p_id_oc, p_motivos, p_detalle, p_id_responsable);

    DO RELEASE_LOCK(v_bloqueo);
END$$

DELIMITER ;
