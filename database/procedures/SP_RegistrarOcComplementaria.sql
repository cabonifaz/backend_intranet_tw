-- HU-27 Registrar una OC complementaria que cubre el faltante de una propuesta con cobertura menor al 100 %.
-- Acción oc_registrar, propuesta del área del usuario, aceptada, con al menos una OC no anulada y faltante.
-- Mismas validaciones del registro (HU-22): N° OC único por cliente, fechas no futuras y recepción no anterior
--   a la OC, monto mayor a 0, vigencia (si no llega, la del parámetro) y PDF obligatorio al guardar.
--   La moneda es la de la propuesta.
-- La nueva OC queda 'pendiente_validacion', tipo 'complementaria', vinculada a la OC de origen, y aplica a la
--   propuesta lo que falta (si el monto es mayor, el resto queda como saldo disponible de la nueva OC).
-- p_solo_validar = 1 valida y devuelve el resultado sin guardar (antes de escribir el PDF en disco).
-- Resultados: 1 mensaje, 2 resultado.
DROP PROCEDURE IF EXISTS SP_RegistrarOcComplementaria;

DELIMITER $$

CREATE PROCEDURE SP_RegistrarOcComplementaria(
    IN p_id_usuario      BIGINT,
    IN p_id_propuesta    BIGINT,
    IN p_numero_oc       VARCHAR(50)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_fecha_oc        DATE,
    IN p_fecha_recepcion DATE,
    IN p_monto           DECIMAL(14,2),
    IN p_vigencia_dias   INT,
    IN p_observaciones   VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_referencia      VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_ruta_pdf        VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_nombre_pdf      VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_tamano_pdf      BIGINT,
    IN p_hash_pdf        CHAR(64)     CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_solo_validar    TINYINT
)
proc: BEGIN
    DECLARE v_dias_sin_resp  INT;
    DECLARE v_meta           INT;
    DECLARE v_sla_horas      INT;
    DECLARE v_alerta_horas   INT;
    DECLARE v_existe         INT DEFAULT 0;
    DECLARE v_estado         VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_cliente     BIGINT;
    DECLARE v_id_resp        BIGINT;
    DECLARE v_id_moneda      INT;
    DECLARE v_total          DECIMAL(14,2);
    DECLARE v_numero         VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cubierto       DECIMAL(14,2) DEFAULT 0;
    DECLARE v_faltante       DECIMAL(14,2);
    DECLARE v_id_origen      BIGINT;
    DECLARE v_numero_origen  VARCHAR(50)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_numero_oc      VARCHAR(50)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_vigencia       INT;
    DECLARE v_simbolo        VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_asignado       DECIMAL(14,2);
    DECLARE v_pct            DECIMAL(7,2);
    DECLARE v_estado_res     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_oc          BIGINT;
    DECLARE v_usuario        VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cliente        VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_notificados    INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_seg;
        DROP TEMPORARY TABLE IF EXISTS tmp_seg_base;
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

    CALL SP_CalcularSeguimientoComercial(p_id_usuario, p_id_propuesta, v_dias_sin_resp, v_meta, v_sla_horas, v_alerta_horas);
    SELECT COUNT(*), MAX(estado_seguimiento), MAX(id_cliente), MAX(id_responsable), MAX(id_moneda), MAX(total), MAX(numero)
      INTO v_existe, v_estado, v_id_cliente, v_id_resp, v_id_moneda, v_total, v_numero
    FROM tmp_seg;
    DROP TEMPORARY TABLE IF EXISTS tmp_seg;
    DROP TEMPORARY TABLE IF EXISTS tmp_seg_base;

    IF v_existe = 0 OR v_estado <> 'aceptada' THEN
        SELECT 1 AS IdTipoMensaje,
               IF(v_existe = 0, 'La propuesta no está en seguimiento comercial o no pertenece a tu área.',
                                'La propuesta no está aceptada por el cliente.') AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT IFNULL(SUM(op.monto_asignado), 0), MAX(op.id_oc) INTO v_cubierto, v_id_origen
    FROM oc_propuesta op
    JOIN orden_compra oc ON oc.id_oc = op.id_oc AND oc.eliminado_en IS NULL AND oc.estado <> 'anulada'
             AND oc.id_moneda = (SELECT pz.id_moneda FROM propuesta_comercial pz WHERE pz.id_propuesta = op.id_propuesta)
    WHERE op.id_propuesta = p_id_propuesta AND op.eliminado_en IS NULL;

    IF v_id_origen IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'La propuesta aún no tiene orden de compra: registre primero la OC principal.' AS Mensaje;
        LEAVE proc;
    END IF;
    SET v_faltante = v_total - v_cubierto;
    IF v_faltante < 0.005 THEN
        SELECT 1 AS IdTipoMensaje, 'La propuesta ya está cubierta al 100 % por sus órdenes de compra.' AS Mensaje;
        LEAVE proc;
    END IF;
    SELECT numero_oc INTO v_numero_origen FROM orden_compra WHERE id_oc = v_id_origen;

    -- Datos obligatorios (mismas reglas del registro)
    IF v_numero_oc IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Ingrese el número de la orden de compra.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF EXISTS (SELECT 1 FROM orden_compra
               WHERE id_cliente = v_id_cliente AND numero_oc = v_numero_oc AND estado <> 'anulada' AND eliminado_en IS NULL) THEN
        SELECT 1 AS IdTipoMensaje, CONCAT('Ya existe la orden de compra ', v_numero_oc, ' registrada para este cliente.') AS Mensaje;
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
    IF p_monto IS NULL OR p_monto <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Ingrese el monto de la orden de compra (mayor a 0).' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT CAST(IFNULL(MAX(Num2), 30) AS SIGNED) INTO v_vigencia
    FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROPUESTA' AND String2 = 'OC_VIGENCIA_DIAS_DEFECTO';
    SET v_vigencia = IFNULL(p_vigencia_dias, v_vigencia);
    IF v_vigencia < 1 OR v_vigencia > 3650 THEN
        SELECT 1 AS IdTipoMensaje, 'Indique la vigencia de la orden de compra en días (1 a 3650).' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT MAX(String2) INTO v_simbolo FROM tabla_maestra WHERE IdMaestro = 1 AND IdEmpresa = 1 AND Num1 = v_id_moneda;

    SET v_asignado   = LEAST(p_monto, v_faltante);
    SET v_pct        = LEAST(ROUND((v_cubierto + v_asignado) * 100 / v_total, 2), 100);
    SET v_estado_res = CASE WHEN ABS(p_monto - v_faltante) < 0.005 THEN 'completa'
                            WHEN p_monto > v_faltante              THEN 'con_saldo'
                            ELSE 'insuficiente' END;

    IF IFNULL(p_solo_validar, 0) = 1 THEN
        SELECT 2 AS IdTipoMensaje, 'Validado.' AS Mensaje;
        SELECT NULL AS id_oc, v_numero_oc AS numero_oc, 'pendiente_validacion' AS estado,
               v_id_origen AS id_oc_origen, v_numero_origen AS numero_oc_origen,
               v_cubierto AS monto_existente, p_monto AS monto_nueva_oc, v_cubierto + v_asignado AS cobertura_total,
               v_pct AS cobertura_total_pct, v_estado_res AS estado_resultado,
               GREATEST(p_monto - v_faltante, 0) AS saldo_nueva_oc, 0 AS notificados;
        LEAVE proc;
    END IF;

    IF NULLIF(TRIM(IFNULL(p_ruta_pdf, '')), '') IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Adjunte el PDF de la orden de compra.' AS Mensaje;
        LEAVE proc;
    END IF;

    START TRANSACTION;

    INSERT INTO orden_compra (
        numero_oc, referencia, id_propuesta, tipo_oc, id_oc_origen, id_cliente, id_moneda,
        monto_total, monto_aplicado, saldo, cobertura_pct,
        fecha_oc, fecha_recepcion, vigencia_desde, vigencia_hasta, vigencia_dias, observaciones,
        url_archivo_pdf, nombre_archivo_pdf, tamano_pdf_bytes, hash_pdf,
        estado, fecha_registro, creado_por)
    VALUES (
        v_numero_oc, NULLIF(TRIM(IFNULL(p_referencia, '')), ''), p_id_propuesta, 'complementaria', v_id_origen,
        v_id_cliente, v_id_moneda,
        p_monto, 0, p_monto, LEAST(ROUND(p_monto * 100 / v_faltante, 2), 999.99),
        p_fecha_oc, p_fecha_recepcion, p_fecha_oc, p_fecha_oc + INTERVAL v_vigencia DAY, v_vigencia,
        NULLIF(TRIM(IFNULL(p_observaciones, '')), ''),
        p_ruta_pdf, p_nombre_pdf, p_tamano_pdf, p_hash_pdf,
        'pendiente_validacion', NOW(), p_id_usuario);

    SET v_id_oc = LAST_INSERT_ID();

    INSERT INTO oc_propuesta (id_oc, id_propuesta, monto_asignado, creado_por)
    VALUES (v_id_oc, p_id_propuesta, v_asignado, p_id_usuario);

    INSERT INTO documento_adjunto (entidad_tipo, id_entidad, id_tipo_documento, nombre_archivo, url_archivo,
                                   version, id_visibilidad, metadatos, subido_por, fecha_carga, creado_por)
    VALUES ('orden_compra', v_id_oc, 1, LEFT(IFNULL(p_nombre_pdf, CONCAT('OC-', v_numero_oc, '.pdf')), 200),
            p_ruta_pdf, 1, 1,
            JSON_OBJECT('motivo', 'Versión inicial', 'tamano_bytes', p_tamano_pdf, 'hash', p_hash_pdf),
            p_id_usuario, NOW(), p_id_usuario);

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo,
                                  descripcion, id_usuario, registrado_en, metadata)
    VALUES ('orden_compra', v_id_oc, 'registrar_oc_complementaria', NULL, 'pendiente_validacion',
            CONCAT('OC complementaria de ', v_numero_origen, ' para la propuesta ', v_numero, ': ',
                   v_simbolo, ' ', FORMAT(v_cubierto, 2), ' existente + ', v_simbolo, ' ', FORMAT(p_monto, 2),
                   ' nueva = ', v_simbolo, ' ', FORMAT(v_cubierto + v_asignado, 2), ' (', v_pct, ' %).'),
            p_id_usuario, NOW(),
            JSON_OBJECT('id_oc_origen', v_id_origen, 'monto_existente', v_cubierto, 'monto_nuevo', p_monto,
                        'asignado', v_asignado, 'faltante_antes', v_faltante));

    SELECT CONCAT(nombre, ' ', apellido) INTO v_usuario FROM usuario WHERE id_usuario = p_id_usuario;
    SELECT razon_social INTO v_cliente FROM cliente WHERE id_cliente = v_id_cliente;

    INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
    SELECT u.id_usuario, 5,
           LEFT(CONCAT('Nueva OC complementaria: ', v_numero_oc), 150),
           CONCAT(v_usuario, ' registró la OC complementaria ', v_numero_oc, ' de ', IFNULL(v_cliente, 'el cliente'),
                  ' por ', v_simbolo, ' ', FORMAT(p_monto, 2), ' (complementa a ', v_numero_origen, ', propuesta ', v_numero,
                  '). Pendiente de validación.'),
           'orden_compra', v_id_oc, NOW(), p_id_usuario
    FROM usuario u
    WHERE u.eliminado_en IS NULL AND u.estado = 'activo' AND u.id_usuario <> p_id_usuario
      AND ((u.area IN ('operaciones', 'administracion') AND u.rol_sistema IN ('supervisor', 'administrador'))
           OR u.id_usuario = v_id_resp);

    SET v_notificados = ROW_COUNT();

    COMMIT;

    SELECT 2 AS IdTipoMensaje, 'OC complementaria registrada. Queda pendiente de validación.' AS Mensaje;
    SELECT v_id_oc AS id_oc, v_numero_oc AS numero_oc, 'pendiente_validacion' AS estado,
           v_id_origen AS id_oc_origen, v_numero_origen AS numero_oc_origen,
           v_cubierto AS monto_existente, p_monto AS monto_nueva_oc, v_cubierto + v_asignado AS cobertura_total,
           v_pct AS cobertura_total_pct, v_estado_res AS estado_resultado,
           GREATEST(p_monto - v_faltante, 0) AS saldo_nueva_oc, v_notificados AS notificados;
END$$

DELIMITER ;
