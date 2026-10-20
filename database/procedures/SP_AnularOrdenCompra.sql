-- HU-28 (Sprint 4) Anular una orden de compra registrada por error, duplicada o dejada sin efecto por el cliente.
-- Reglas: acción oc_anular; OC del área del usuario, no anulada (ni autogenerada ya reemplazada); motivo tipificado
--   (MOTIVO_ANULACION_OC, 102) y justificación obligatoria (mínimo 20 caracteres). Si hay órdenes de servicio en
--   ejecución vinculadas (impacto crítico) se exige p_confirma_impacto = 1.
-- Efectos: la OC pasa a ANULADA en solo lectura (no se edita, no se reactiva ni se le vinculan propuestas); su aporte
--   deja de contar en la cobertura de todas las propuestas vinculadas (FN_SaldoPropuestaOc recalcula los saldos), así una
--   propuesta que quedaba cerrada solo por esta OC vuelve a ACEPTADA con saldo por cubrir. Los expedientes que pasaron a
--   Programación por esta OC y aún no tienen OS ni otra OC válida vuelven a la etapa Orden de Compra.
--   Timeline con usuario, motivo y justificación; notificación a Operaciones, Contabilidad y responsables comerciales.
-- Resultados: 1 mensaje, 2 OC anulada, 3 propuestas afectadas con su saldo.
DROP PROCEDURE IF EXISTS SP_AnularOrdenCompraInterno;

DELIMITER $$

CREATE PROCEDURE SP_AnularOrdenCompraInterno(
    IN p_id_usuario        BIGINT,
    IN p_id_oc             BIGINT,
    IN p_id_motivo         INT,
    IN p_justificacion     VARCHAR(1000) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_confirma_impacto  TINYINT
)
proc: BEGIN
    DECLARE v_existe   INT DEFAULT 0;
    DECLARE v_estado   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_reemp    BIGINT;
    DECLARE v_numero   VARCHAR(50)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_motivo   VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_just     VARCHAR(1000) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_os       INT DEFAULT 0;
    DECLARE v_usuario  VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_revert   INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_oc;
        DROP TEMPORARY TABLE IF EXISTS tmp_oc_anu_exp;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF FN_PermisoAccion(p_id_usuario, 'oc_anular') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para anular órdenes de compra.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_CalcularOrdenesCompra(p_id_usuario, p_id_oc);
    SELECT COUNT(*), MAX(estado), MAX(reemplazada_por), MAX(numero_oc) INTO v_existe, v_estado, v_reemp, v_numero FROM tmp_oc;
    DROP TEMPORARY TABLE IF EXISTS tmp_oc;

    IF v_existe = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'La orden de compra no existe o no pertenece a tu área.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_estado = 'anulada' THEN
        SELECT 1 AS IdTipoMensaje, 'La orden de compra ya está anulada.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_reemp IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, 'La OC autogenerada ya fue reemplazada por la OC del cliente.' AS Mensaje; LEAVE proc;
    END IF;

    SELECT MAX(String1) INTO v_motivo FROM tabla_maestra
    WHERE IdMaestro = 102 AND IdEmpresa = 1 AND Num1 = p_id_motivo AND eliminado_en IS NULL;
    IF v_motivo IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Seleccione el motivo de la anulación.' AS Mensaje; LEAVE proc;
    END IF;
    SET v_just = TRIM(IFNULL(p_justificacion, ''));
    IF CHAR_LENGTH(v_just) < 20 THEN
        SELECT 1 AS IdTipoMensaje, 'La justificación es obligatoria (mínimo 20 caracteres).' AS Mensaje; LEAVE proc;
    END IF;

    SELECT COUNT(DISTINCT os.id_os) INTO v_os
    FROM oc_propuesta op
    JOIN orden_servicio os ON os.id_expediente = FN_ExpedienteDePropuesta(op.id_propuesta) AND os.eliminado_en IS NULL
                          AND os.estado IN ('en_ruta', 'en_ejecucion', 'pausada')
    WHERE op.id_oc = p_id_oc AND op.eliminado_en IS NULL;
    IF v_os > 0 AND IFNULL(p_confirma_impacto, 0) <> 1 THEN
        SELECT 1 AS IdTipoMensaje,
               CONCAT('Impacto crítico: hay ', v_os, ' orden(es) de servicio en ejecución vinculadas. Confirme el impacto para anular.') AS Mensaje;
        LEAVE proc;
    END IF;

    START TRANSACTION;

    SELECT estado INTO v_estado FROM orden_compra WHERE id_oc = p_id_oc FOR UPDATE;
    IF v_estado = 'anulada' THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'La orden de compra ya está anulada.' AS Mensaje; LEAVE proc;
    END IF;

    UPDATE orden_compra
    SET estado = 'anulada', id_motivo_anulacion = p_id_motivo, justificacion_anulacion = v_just,
        fecha_anulacion = NOW(), anulado_por = p_id_usuario, modificado_por = p_id_usuario
    WHERE id_oc = p_id_oc;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion,
                                  id_usuario, registrado_en, metadata)
    VALUES ('orden_compra', p_id_oc, 'anular_oc', v_estado, 'anulada',
            CONCAT('Orden de compra anulada. Motivo: ', v_motivo, '. Justificación: ', v_just,
                   IF(v_os > 0, CONCAT(' (con ', v_os, ' OS en ejecución, impacto confirmado)'), '')),
            p_id_usuario, NOW(),
            JSON_OBJECT('id_motivo', p_id_motivo, 'motivo', v_motivo, 'justificacion', v_just, 'os_en_ejecucion', v_os));

    -- Expedientes que pasaron a Programación por esta OC, sin OS y sin otra OC válida: vuelven a la etapa de OC
    DROP TEMPORARY TABLE IF EXISTS tmp_oc_anu_exp;
    CREATE TEMPORARY TABLE tmp_oc_anu_exp AS
    SELECT DISTINCT e.id_expediente, op.id_propuesta
    FROM oc_propuesta op
    JOIN expediente_digital e ON e.id_expediente = FN_ExpedienteDePropuesta(op.id_propuesta)
    WHERE op.id_oc = p_id_oc AND op.eliminado_en IS NULL
      AND e.eliminado_en IS NULL AND e.etapa_actual = 'programacion'
      AND NOT EXISTS (SELECT 1 FROM orden_servicio os WHERE os.id_expediente = e.id_expediente
                        AND os.eliminado_en IS NULL AND os.estado <> 'anulada')
      AND NOT EXISTS (SELECT 1 FROM oc_propuesta o2
                      JOIN orden_compra c2 ON c2.id_oc = o2.id_oc
                      WHERE o2.id_propuesta = op.id_propuesta AND o2.eliminado_en IS NULL AND o2.id_oc <> p_id_oc
                        AND c2.eliminado_en IS NULL AND c2.estado <> 'anulada'
                        AND (o2.estado_validacion = 'validada' OR (c2.es_autogenerada = 1 AND c2.reemplazada_por IS NULL)));
    SELECT COUNT(*) INTO v_revert FROM tmp_oc_anu_exp;

    IF v_revert > 0 THEN
        UPDATE expediente_etapa x
        JOIN tmp_oc_anu_exp t ON t.id_expediente = x.id_expediente
        SET x.fecha_fin = NOW(), x.resultado = 'cancelado',
            x.comentario = LEFT(CONCAT('Cancelada por la anulación de la OC ', v_numero, '.'), 1000),
            x.UsuMod = CAST(p_id_usuario AS CHAR), x.FchMod = NOW()
        WHERE x.fecha_fin IS NULL AND x.SoftDelete = 0;

        UPDATE expediente_digital e
        JOIN tmp_oc_anu_exp t ON t.id_expediente = e.id_expediente
        SET e.etapa_actual = 'orden_compra', e.area_responsable = 'comercial', e.id_responsable_actual = NULL,
            e.id_orden_compra = IF(e.id_orden_compra = p_id_oc, NULL, e.id_orden_compra),
            e.fecha_etapa = NOW(), e.sla_horas = NULL, e.fecha_limite_sla = NULL, e.modificado_por = p_id_usuario;

        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion,
                                      id_usuario, registrado_en, metadata)
        SELECT 'expediente', t.id_expediente, 'volver_orden_compra', 'programacion', 'orden_compra',
               CONCAT('El expediente vuelve a la etapa Orden de Compra por la anulación de la OC ', v_numero, '.'),
               p_id_usuario, NOW(), JSON_OBJECT('id_oc', p_id_oc)
        FROM tmp_oc_anu_exp t;
    END IF;
    DROP TEMPORARY TABLE IF EXISTS tmp_oc_anu_exp;

    SELECT CONCAT(nombre, ' ', apellido) INTO v_usuario FROM usuario WHERE id_usuario = p_id_usuario;
    INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
    SELECT DISTINCT u.id_usuario, 5,
           CONCAT('OC anulada: ', v_numero),
           CONCAT(v_usuario, ' anuló la OC ', v_numero, ' (', v_motivo, '). ', v_just,
                  IF(v_os > 0, CONCAT(' Hay ', v_os, ' OS en ejecución vinculadas.'), '')),
           'orden_compra', p_id_oc, NOW(), p_id_usuario
    FROM usuario u
    WHERE u.eliminado_en IS NULL AND u.estado = 'activo' AND u.id_usuario <> p_id_usuario
      AND ((u.area IN ('operaciones', 'administracion') AND u.rol_sistema IN ('supervisor', 'administrador'))
           OR u.id_usuario IN (SELECT COALESCE(p.id_responsable, p.id_creador)
                               FROM oc_propuesta op JOIN propuesta_comercial p ON p.id_propuesta = op.id_propuesta
                               WHERE op.id_oc = p_id_oc AND op.eliminado_en IS NULL));

    COMMIT;

    SELECT 2 AS IdTipoMensaje,
           CONCAT('Orden de compra ', v_numero, ' anulada. Se recalcularon los saldos de las propuestas vinculadas',
                  IF(v_revert > 0, CONCAT(' y ', v_revert, ' expediente(s) volvieron a la etapa Orden de Compra'), ''), '.') AS Mensaje;

    SELECT oc.id_oc, oc.numero_oc, oc.estado, oc.fecha_anulacion, v_motivo AS motivo, oc.justificacion_anulacion
    FROM orden_compra oc WHERE oc.id_oc = p_id_oc;

    SELECT op.id_propuesta, p.numero, p.version, op.monto_asignado, FN_SaldoPropuestaOc(op.id_propuesta, NULL) AS saldo
    FROM oc_propuesta op JOIN propuesta_comercial p ON p.id_propuesta = op.id_propuesta
    WHERE op.id_oc = p_id_oc AND op.eliminado_en IS NULL
    ORDER BY op.id;
END$$

DELIMITER ;


DROP PROCEDURE IF EXISTS SP_AnularOrdenCompra;

DELIMITER $$

CREATE PROCEDURE SP_AnularOrdenCompra(
    IN p_id_usuario        BIGINT,
    IN p_id_oc             BIGINT,
    IN p_id_motivo         INT,
    IN p_justificacion     VARCHAR(1000) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_confirma_impacto  TINYINT
)
proc: BEGIN
    DECLARE v_bloqueo VARCHAR(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        DO RELEASE_LOCK(v_bloqueo);
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SET v_bloqueo = CONCAT('tw_oc_cliente_', IFNULL((SELECT id_cliente FROM orden_compra WHERE id_oc = p_id_oc), 0));
    IF IFNULL(GET_LOCK(v_bloqueo, 15), 0) <> 1 THEN
        SELECT 1 AS IdTipoMensaje,
               'Hay otra operación en curso sobre las órdenes de compra de este cliente. Intente nuevamente en unos segundos.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_AnularOrdenCompraInterno(p_id_usuario, p_id_oc, p_id_motivo, p_justificacion, p_confirma_impacto);

    DO RELEASE_LOCK(v_bloqueo);
END$$

DELIMITER ;
