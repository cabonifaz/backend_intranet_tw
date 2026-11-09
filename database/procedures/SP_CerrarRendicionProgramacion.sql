-- HU-45 (Sprint 5) Cierre de la rendición: calcula el saldo final (devolución del técnico si gastó menos de lo asignado, reembolso adicional si
-- gastó más), deja la rendición de solo lectura y notifica a Contabilidad. Reglas en SP_ResumenRendicionProgramacion (puede_cerrar):
-- programación confirmada, sin gastos pendientes u observados, algo que rendir. Con depósitos pendientes se permite y se advierte.
-- Solo el Jefe. Resultados: 1 mensaje, 2 cierre.
DROP PROCEDURE IF EXISTS SP_CerrarRendicionProgramacion;

DELIMITER $$

CREATE PROCEDURE SP_CerrarRendicionProgramacion(
    IN p_id_usuario      BIGINT,
    IN p_id_programacion BIGINT
)
proc: BEGIN
    DECLARE v_id_os     BIGINT DEFAULT NULL;
    DECLARE v_numero    VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_codigo    VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado    VARCHAR(25)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_error     VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_asig      DECIMAL(12,2) DEFAULT 0;
    DECLARE v_depos     DECIMAL(12,2) DEFAULT 0;
    DECLARE v_solic     DECIMAL(12,2) DEFAULT 0;
    DECLARE v_aprob     DECIMAL(12,2) DEFAULT 0;
    DECLARE v_rech      DECIMAL(12,2) DEFAULT 0;
    DECLARE v_saldo     DECIMAL(12,2) DEFAULT 0;
    DECLARE v_tipo      VARCHAR(12)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_contab    INT DEFAULT 0;
    DECLARE v_texto     VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_mensaje   VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            @err_msg  = MESSAGE_TEXT,
            @err_code = MYSQL_ERRNO;
        ROLLBACK;
        IF @err_code IN (1213, 1205) THEN
            SELECT 1 AS IdTipoMensaje, 'Otra persona está modificando esta programación en este momento. Inténtalo de nuevo.' AS Mensaje;
        ELSE
            SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
        END IF;
    END;

    IF FN_PermisoAccion(p_id_usuario, 'prog_aprobar_reprogramacion') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Solo el Jefe de Operaciones puede cerrar la rendición.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF IFNULL(p_id_programacion, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'La programación no existe.' AS Mensaje;
        LEAVE proc;
    END IF;
    SELECT id_os INTO v_id_os FROM programacion WHERE id_programacion = p_id_programacion AND eliminado_en IS NULL;
    IF v_id_os IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'La programación no existe.' AS Mensaje;
        LEAVE proc;
    END IF;

    START TRANSACTION;

    SELECT numero INTO v_numero FROM orden_servicio WHERE id_os = v_id_os AND eliminado_en IS NULL FOR UPDATE;
    SELECT codigo, estado INTO v_codigo, v_estado FROM programacion WHERE id_programacion = p_id_programacion AND eliminado_en IS NULL FOR UPDATE;
    IF v_codigo IS NULL THEN
        SET v_error = 'La programación no existe.';
    ELSEIF v_estado <> 'confirmada' THEN
        SET v_error = CONCAT('La programación ', v_codigo, ' no está Programada: no se puede cerrar su rendición.');
    END IF;
    IF v_error IS NOT NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, v_error AS Mensaje;
        LEAVE proc;
    END IF;

    -- Con los bloqueos tomados, el resumen es consistente
    SELECT IFNULL(SUM(IF(tipo = 'viatico_asignado', monto, 0)), 0),
           IFNULL(SUM(IF(tipo = 'viatico_asignado' AND estado IN ('aprobado', 'rendido'), monto, 0)), 0),
           IFNULL(SUM(IF(tipo = 'gasto_solicitado', monto, 0)), 0),
           IFNULL(SUM(IF(tipo = 'gasto_solicitado' AND estado IN ('aprobado', 'rendido'), monto, 0)), 0),
           IFNULL(SUM(IF(tipo = 'gasto_solicitado' AND estado = 'rechazado', monto, 0)), 0),
           IFNULL(SUM(tipo = 'gasto_solicitado' AND estado IN ('pendiente', 'observado')), 0)
      INTO v_asig, v_depos, v_solic, v_aprob, v_rech, @pendientes
    FROM gasto_viatico
    WHERE eliminado_en IS NULL AND (id_programacion = p_id_programacion OR (id_programacion IS NULL AND id_os = v_id_os));

    IF EXISTS (SELECT 1 FROM programacion_rendicion WHERE id_programacion = p_id_programacion AND eliminado_en IS NULL) THEN
        SET v_error = 'La rendición ya fue cerrada.';
    ELSEIF v_asig = 0 AND v_solic = 0 THEN
        SET v_error = 'No hay viáticos ni gastos que rendir.';
    ELSEIF @pendientes > 0 THEN
        SET v_error = CONCAT('Aún hay ', @pendientes, ' gasto(s) pendientes u observados: apruébalos o recházalos antes de cerrar.');
    END IF;
    IF v_error IS NOT NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, v_error AS Mensaje;
        LEAVE proc;
    END IF;

    -- Saldo: lo aprobado menos lo asignado. >0: reembolso adicional al técnico; <0: devolución del técnico
    SET v_saldo = v_aprob - v_asig;
    SET v_tipo = IF(v_saldo > 0, 'reembolso', IF(v_saldo < 0, 'devolucion', 'cuadrado'));

    INSERT INTO programacion_rendicion (id_programacion, id_os, total_asignado, total_depositado, total_solicitado, total_aprobado, total_rechazado,
                                        saldo, tipo_saldo, cerrado_por, cerrado_en, creado_por)
    VALUES (p_id_programacion, v_id_os, v_asig, v_depos, v_solic, v_aprob, v_rech, ABS(v_saldo), v_tipo, p_id_usuario, NOW(), p_id_usuario);

    SET v_texto = CASE v_tipo WHEN 'reembolso' THEN CONCAT('Reembolso adicional al técnico: S/ ', FORMAT(ABS(v_saldo), 2))
                              WHEN 'devolucion' THEN CONCAT('Devolución del técnico: S/ ', FORMAT(ABS(v_saldo), 2))
                              ELSE 'Cuadrado: sin saldo' END;

    INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
    SELECT u.id_usuario, 5, LEFT(CONCAT('Rendición cerrada: ', v_numero), 150),
           LEFT(CONCAT('Programación ', v_codigo, ' · ', v_numero, '. Asignado S/ ', FORMAT(v_asig, 2), ', aprobado S/ ', FORMAT(v_aprob, 2),
                       ', rechazado S/ ', FORMAT(v_rech, 2), '. ', v_texto, '.'), 3000),
           'programacion', p_id_programacion, NOW(), p_id_usuario
    FROM usuario u
    WHERE u.eliminado_en IS NULL AND u.estado = 'activo' AND u.area = 'contabilidad' AND u.id_usuario <> p_id_usuario;
    SET v_contab = ROW_COUNT();

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('programacion', p_id_programacion, 'cerrar_rendicion', v_estado, v_estado,
            LEFT(CONCAT('Rendición cerrada en ', v_codigo, ': asignado S/ ', FORMAT(v_asig, 2), ', aprobado S/ ', FORMAT(v_aprob, 2), '. ', v_texto, '.'), 900),
            p_id_usuario, NOW(),
            JSON_OBJECT('asignado', v_asig, 'aprobado', v_aprob, 'rechazado', v_rech, 'saldo', v_saldo, 'tipoSaldo', v_tipo, 'notificadosContabilidad', v_contab));

    COMMIT;

    SET v_mensaje = CONCAT('Rendición cerrada. ', v_texto, '.',
                           IF(v_contab > 0, ' Se notificó a Contabilidad.', ' No hay usuarios de Contabilidad configurados para recibir el aviso.'),
                           IF(v_depos < v_asig, CONCAT(' Atención: quedaban S/ ', FORMAT(v_asig - v_depos, 2), ' sin depositar.'), ''));
    SELECT 2 AS IdTipoMensaje, v_mensaje AS Mensaje;
    SELECT p_id_programacion AS id_programacion, v_asig AS total_asignado, v_depos AS total_depositado, v_solic AS total_solicitado,
           v_aprob AS total_aprobado, v_rech AS total_rechazado, ABS(v_saldo) AS saldo, v_tipo AS tipo_saldo, v_contab AS notificados_contabilidad;
END$$

DELIMITER ;
