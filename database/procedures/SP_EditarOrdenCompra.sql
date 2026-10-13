-- HU-24 Editar los datos de una orden de compra registrada.
-- Acción oc_editar, OC del área del usuario y no anulada. Propuesta, RQ y cliente no se modifican.
-- Mismas validaciones del registro (HU-22): N° OC único por cliente, fechas no futuras y recepción
--   no anterior a la OC, moneda, monto mayor a 0 y vigencia de 1 a 3650 días. El PDF nuevo es opcional
--   (si llega, reemplaza al anterior, que queda registrado en el historial).
-- Revalidación:
--   Cambiar monto o moneda de una OC validada recalcula cobertura y saldos y la regresa a
--   'pendiente_validacion' (lo aplicado vuelve a 0 hasta que se revalide).
--   p_revalidar = 1 ("Guardar y revalidar") la regresa siempre a 'pendiente_validacion' y levanta la
--   observación. En ambos casos se notifica a Operaciones, Administración y al responsable comercial.
--   Si la OC ya tiene órdenes de servicio no se puede cambiar el monto ni la moneda.
-- HU-26: "Guardar y revalidar" levanta la observación abierta, resuelve el bloqueo del expediente
--   y avisa también a quien observó la OC.
-- HU-25: el PDF nuevo se registra como nueva versión en documento_adjunto.
-- p_solo_validar = 1 valida y devuelve el impacto sin guardar (antes de escribir el PDF en disco).
-- Resultados: 1 mensaje, 2 resultado de la edición.
DROP PROCEDURE IF EXISTS SP_EditarOrdenCompra;

DELIMITER $$

CREATE PROCEDURE SP_EditarOrdenCompra(
    IN p_id_usuario      BIGINT,
    IN p_id_oc           BIGINT,
    IN p_numero_oc       VARCHAR(50)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_referencia      VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_fecha_oc        DATE,
    IN p_fecha_recepcion DATE,
    IN p_id_moneda       INT,
    IN p_monto           DECIMAL(14,2),
    IN p_vigencia_dias   INT,
    IN p_observaciones   VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_revalidar       TINYINT,
    IN p_ruta_pdf        VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_nombre_pdf      VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_tamano_pdf      BIGINT,
    IN p_hash_pdf        CHAR(64)     CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_solo_validar    TINYINT
)
proc: BEGIN
    DECLARE v_existe        INT DEFAULT 0;
    DECLARE v_id_cliente    BIGINT;
    DECLARE v_id_prop       BIGINT;
    DECLARE v_id_resp       BIGINT;
    DECLARE v_total         DECIMAL(14,2) DEFAULT 0;
    DECLARE v_validada      TINYINT DEFAULT 0;
    DECLARE v_n_os          INT DEFAULT 0;
    DECLARE v_estado        VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado_nuevo  VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_moneda_prop INT;
    -- valores actuales
    DECLARE a_numero        VARCHAR(50)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE a_referencia    VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE a_fecha_oc      DATE;
    DECLARE a_fecha_rec     DATE;
    DECLARE a_moneda        INT;
    DECLARE a_monto         DECIMAL(14,2);
    DECLARE a_vigencia      INT;
    DECLARE a_observ        VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE a_ruta_pdf      VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE a_motivo_obs    INT;
    -- valores nuevos
    DECLARE v_numero        VARCHAR(50)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_referencia    VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_observ        VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_ruta_pdf      VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_simbolo       VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cambia_monto  TINYINT DEFAULT 0;
    DECLARE v_vuelve        TINYINT DEFAULT 0;
    DECLARE v_cambios       VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado_cob    VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_pct           DECIMAL(7,2) DEFAULT 0;
    DECLARE v_diferencia    DECIMAL(14,2);
    DECLARE v_usuario       VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cliente       VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_notificados   INT DEFAULT 0;
    DECLARE v_obs_abierta   BIGINT;
    DECLARE v_observador    BIGINT;
    DECLARE v_id_exp        BIGINT;

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

    SET v_numero     = NULLIF(TRIM(IFNULL(p_numero_oc, '')), '');
    SET v_referencia = NULLIF(TRIM(IFNULL(p_referencia, '')), '');
    SET v_observ     = NULLIF(TRIM(IFNULL(p_observaciones, '')), '');
    SET v_ruta_pdf   = NULLIF(TRIM(IFNULL(p_ruta_pdf, '')), '');

    IF FN_PermisoAccion(p_id_usuario, 'oc_editar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para editar órdenes de compra.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- OC en alcance
    CALL SP_CalcularOrdenesCompra(p_id_usuario, p_id_oc);
    SELECT COUNT(*), MAX(id_cliente), MAX(id_propuesta), MAX(id_responsable), MAX(monto_propuesta),
           MAX(validada), MAX(ordenes_servicio), MAX(estado_bd)
      INTO v_existe, v_id_cliente, v_id_prop, v_id_resp, v_total, v_validada, v_n_os, v_estado
    FROM tmp_oc;
    DROP TEMPORARY TABLE IF EXISTS tmp_oc;

    IF v_existe = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'La orden de compra no existe o no pertenece a tu área.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_estado = 'anulada' THEN
        SELECT 1 AS IdTipoMensaje, 'La orden de compra está anulada y no se puede editar.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT numero_oc, referencia, fecha_oc, fecha_recepcion, id_moneda, monto_total, vigencia_dias,
           observaciones, url_archivo_pdf, id_motivo_observacion
      INTO a_numero, a_referencia, a_fecha_oc, a_fecha_rec, a_moneda, a_monto, a_vigencia,
           a_observ, a_ruta_pdf, a_motivo_obs
    FROM orden_compra WHERE id_oc = p_id_oc;

    SELECT id_moneda INTO v_id_moneda_prop FROM propuesta_comercial WHERE id_propuesta = v_id_prop;

    -- Datos obligatorios
    IF v_numero IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Ingrese el número de la orden de compra.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF EXISTS (SELECT 1 FROM orden_compra
               WHERE id_cliente = v_id_cliente AND numero_oc = v_numero AND id_oc <> p_id_oc
                 AND estado <> 'anulada' AND eliminado_en IS NULL) THEN
        SELECT 1 AS IdTipoMensaje,
               CONCAT('Ya existe la orden de compra ', v_numero, ' registrada para este cliente.') AS Mensaje;
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

    SET v_cambia_monto = IF(p_monto <> a_monto OR p_id_moneda <> a_moneda, 1, 0);

    IF v_cambia_monto = 1 AND v_n_os > 0 THEN
        SELECT 1 AS IdTipoMensaje,
               'La orden de compra ya tiene órdenes de servicio: no se puede cambiar el monto ni la moneda.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_cambios = CONCAT_WS(', ',
        IF(v_numero <> a_numero, 'N.° OC', NULL),
        IF(NOT (v_referencia <=> a_referencia), 'referencia', NULL),
        IF(p_fecha_oc <> a_fecha_oc, 'fecha OC', NULL),
        IF(p_fecha_recepcion <> a_fecha_rec, 'fecha de recepción', NULL),
        IF(p_id_moneda <> a_moneda, 'moneda', NULL),
        IF(p_monto <> a_monto, 'monto', NULL),
        IF(NOT (p_vigencia_dias <=> a_vigencia), 'vigencia', NULL),
        IF(NOT (v_observ <=> a_observ), 'observaciones', NULL),
        IF(v_ruta_pdf IS NOT NULL, 'PDF', NULL));
    SET v_cambios = NULLIF(v_cambios, '');

    IF v_cambios IS NULL AND IFNULL(p_revalidar, 0) = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No hay cambios para guardar.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Regresa a validación: "Guardar y revalidar" o cambio de monto o moneda en una OC validada
    SET v_vuelve       = IF(IFNULL(p_revalidar, 0) = 1 OR (v_cambia_monto = 1 AND v_validada = 1), 1, 0);
    SET v_estado_nuevo = IF(v_vuelve = 1, 'pendiente_validacion', v_estado);

    -- Cobertura con los datos nuevos
    IF p_id_moneda <> v_id_moneda_prop THEN
        SET v_estado_cob = 'moneda_diferente';
        SET v_pct        = 0;
        SET v_diferencia = NULL;
    ELSE
        SET v_diferencia = p_monto - v_total;
        SET v_pct        = IF(v_total > 0, LEAST(ROUND(p_monto * 100 / v_total, 2), 999.99), 100);
        SET v_estado_cob = CASE WHEN ABS(v_diferencia) < 0.01 THEN 'completa'
                                WHEN v_diferencia > 0         THEN 'con_saldo'
                                ELSE                               'insuficiente' END;
    END IF;

    IF IFNULL(p_solo_validar, 0) = 1 THEN
        SELECT 2 AS IdTipoMensaje, 'Validado.' AS Mensaje;
        SELECT p_id_oc AS id_oc, v_numero AS numero_oc, v_estado_nuevo AS estado,
               v_estado_cob AS estado_cobertura, v_pct AS cobertura_pct, v_diferencia AS diferencia,
               v_vuelve AS requiere_revalidacion, v_cambios AS cambios, 0 AS notificados;
        LEAVE proc;
    END IF;

    START TRANSACTION;

    -- HU-25: el PDF nuevo queda como una versión más (la anterior se conserva). Va antes del UPDATE
    IF v_ruta_pdf IS NOT NULL THEN
        CALL SP_AgregarVersionDocumentoOc(p_id_oc, p_id_usuario, v_ruta_pdf, p_nombre_pdf, p_tamano_pdf, p_hash_pdf,
                                          'Reemplazado al editar la orden de compra');
    END IF;

    UPDATE orden_compra SET
        numero_oc             = v_numero,
        referencia            = v_referencia,
        fecha_oc              = p_fecha_oc,
        fecha_recepcion       = p_fecha_recepcion,
        vigencia_desde        = p_fecha_oc,
        vigencia_hasta        = p_fecha_oc + INTERVAL p_vigencia_dias DAY,
        vigencia_dias         = p_vigencia_dias,
        id_moneda             = p_id_moneda,
        monto_total           = p_monto,
        cobertura_pct         = v_pct,
        monto_aplicado        = IF(v_vuelve = 1 OR v_estado = 'pendiente_validacion', 0, monto_aplicado),
        saldo                 = p_monto - IF(v_vuelve = 1 OR v_estado = 'pendiente_validacion', 0, monto_aplicado),
        observaciones         = v_observ,
        url_archivo_pdf       = IFNULL(v_ruta_pdf, url_archivo_pdf),
        nombre_archivo_pdf    = IF(v_ruta_pdf IS NULL, nombre_archivo_pdf, p_nombre_pdf),
        tamano_pdf_bytes      = IF(v_ruta_pdf IS NULL, tamano_pdf_bytes, p_tamano_pdf),
        hash_pdf              = IF(v_ruta_pdf IS NULL, hash_pdf, p_hash_pdf),
        estado                = v_estado_nuevo,
        id_validado_por       = IF(v_vuelve = 1, NULL, id_validado_por),
        id_motivo_observacion = IF(IFNULL(p_revalidar, 0) = 1, NULL, id_motivo_observacion),
        modificado_por        = p_id_usuario
    WHERE id_oc = p_id_oc;

    UPDATE oc_propuesta SET
        monto_asignado = IF(v_estado_cob = 'moneda_diferente', p_monto, LEAST(p_monto, v_total)),
        modificado_por = p_id_usuario
    WHERE id_oc = p_id_oc AND id_propuesta = v_id_prop AND eliminado_en IS NULL;

    -- HU-26: "Guardar y revalidar" levanta la observación abierta y el bloqueo del expediente
    SELECT MAX(id_observacion) INTO v_obs_abierta
    FROM orden_compra_observacion WHERE id_oc = p_id_oc AND estado = 'abierta' AND eliminado_en IS NULL;

    IF IFNULL(p_revalidar, 0) = 1 AND v_obs_abierta IS NOT NULL THEN
        SELECT creado_por INTO v_observador FROM orden_compra_observacion WHERE id_observacion = v_obs_abierta;

        UPDATE orden_compra_observacion SET
            estado = 'levantada', fecha_levantamiento = NOW(), levantada_por = p_id_usuario, modificado_por = p_id_usuario
        WHERE id_oc = p_id_oc AND estado = 'abierta' AND eliminado_en IS NULL;

        SELECT MAX(e.id_expediente) INTO v_id_exp
        FROM expediente_digital e
        WHERE e.eliminado_en IS NULL AND (e.id_orden_compra = p_id_oc OR e.id_propuesta = v_id_prop);

        IF v_id_exp IS NOT NULL THEN
            UPDATE expediente_bloqueador SET resuelto = 1, fecha_resolucion = NOW(), modificado_por = p_id_usuario
            WHERE id_expediente = v_id_exp AND resuelto = 0 AND eliminado_en IS NULL
              AND descripcion LIKE CONCAT('OC ', a_numero, '%');

            UPDATE expediente_digital SET estado = 'activo', modificado_por = p_id_usuario
            WHERE id_expediente = v_id_exp AND estado = 'bloqueado'
              AND NOT EXISTS (SELECT 1 FROM expediente_bloqueador b
                              WHERE b.id_expediente = v_id_exp AND b.resuelto = 0 AND b.eliminado_en IS NULL);
        END IF;
    END IF;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo,
                                  descripcion, id_usuario, registrado_en, metadata)
    VALUES ('orden_compra', p_id_oc,
            IF(v_vuelve = 1, 'editar_oc_revalidacion', 'editar_oc'),
            v_estado, v_estado_nuevo,
            CONCAT(IF(v_cambios IS NULL, 'Sin cambios en los datos', CONCAT('Cambios: ', v_cambios)),
                   IF(v_vuelve = 1, '. Enviada a revalidación.', '.'),
                   IF(IFNULL(p_revalidar, 0) = 1 AND a_motivo_obs IS NOT NULL, ' Se levantó la observación.', '')),
            p_id_usuario, NOW(),
            JSON_OBJECT('numero_anterior', a_numero, 'numero_nuevo', v_numero,
                        'moneda_anterior', a_moneda, 'moneda_nueva', p_id_moneda,
                        'monto_anterior', a_monto, 'monto_nuevo', p_monto,
                        'fecha_oc_anterior', a_fecha_oc, 'fecha_oc_nueva', p_fecha_oc,
                        'vigencia_anterior', a_vigencia, 'vigencia_nueva', p_vigencia_dias,
                        'pdf_anterior', IF(v_ruta_pdf IS NULL, NULL, a_ruta_pdf)));

    IF v_vuelve = 1 THEN
        SELECT CONCAT(nombre, ' ', apellido) INTO v_usuario FROM usuario WHERE id_usuario = p_id_usuario;
        SELECT razon_social INTO v_cliente FROM cliente WHERE id_cliente = v_id_cliente;

        INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
        SELECT u.id_usuario, 5,
               LEFT(CONCAT('OC modificada, requiere revalidación: ', v_numero), 150),
               CONCAT(v_usuario, ' modificó la OC ', v_numero, ' de ', IFNULL(v_cliente, 'el cliente'),
                      IF(v_cambios IS NULL, '', CONCAT(' (', v_cambios, ')')),
                      '. Monto: ', v_simbolo, ' ', FORMAT(p_monto, 2), '. Requiere revalidación.'),
               'orden_compra', p_id_oc, NOW(), p_id_usuario
        FROM usuario u
        WHERE u.eliminado_en IS NULL AND u.estado = 'activo' AND u.id_usuario <> p_id_usuario
          AND ((u.area IN ('operaciones', 'administracion') AND u.rol_sistema IN ('supervisor', 'administrador'))
               OR u.id_usuario = v_id_resp
               OR u.id_usuario = v_observador);

        SET v_notificados = ROW_COUNT();
    END IF;

    COMMIT;

    SELECT 2 AS IdTipoMensaje,
           IF(v_vuelve = 1,
              'Orden de compra actualizada y enviada a revalidación. Se notificó a Contabilidad y Operaciones.',
              'Orden de compra actualizada.') AS Mensaje;
    SELECT p_id_oc AS id_oc, v_numero AS numero_oc, v_estado_nuevo AS estado,
           v_estado_cob AS estado_cobertura, v_pct AS cobertura_pct, v_diferencia AS diferencia,
           v_vuelve AS requiere_revalidacion, v_cambios AS cambios, v_notificados AS notificados;
END$$

DELIMITER ;
