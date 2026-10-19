-- HU-28 Liberar el expediente para programación.
-- Acción oc_liberar y OC del área del usuario. No debe haber puntos bloqueantes.
-- Si hay requisitos pendientes (alertas: SCTR, SSOMA, bloqueos de otras áreas) se exige p_confirma_impacto = 1:
--   la liberación traslada la responsabilidad de completarlos a Operaciones.
-- Efectos:
--   Expediente (nace con el RQ, solo se crea aquí si no existe): pasa a programacion con área Operaciones,
--     inicio de etapa y SLA, vinculado a la OC. También pasan los expedientes de las propuestas a las que
--     la OC distribuyó saldo. Las alertas quedan como excepciones del expediente (estado con_excepcion).
--   OC: fecha_liberacion y liberado_por. Auditoría liberar_oc (OC) y liberar_programacion (expediente).
--   Notificación a Operaciones (supervisores y administradores) con el SLA, y al responsable comercial.
-- Resultados: 1 mensaje, 2 resultado.
DROP PROCEDURE IF EXISTS SP_LiberarOrdenCompraInterno;

DELIMITER $$

CREATE PROCEDURE SP_LiberarOrdenCompraInterno(
    IN p_id_usuario        BIGINT,
    IN p_id_oc             BIGINT,
    IN p_confirma_impacto  TINYINT,
    IN p_comentario        VARCHAR(1000) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_existe      INT DEFAULT 0;
    DECLARE v_bloqueantes INT DEFAULT 0;
    DECLARE v_alertas     INT DEFAULT 0;
    DECLARE v_texto_bloq  VARCHAR(600) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_texto_alert VARCHAR(600) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_detalles    JSON;
    DECLARE v_id_prop     BIGINT;
    DECLARE v_id_rq       BIGINT;
    DECLARE v_id_resp     BIGINT;
    DECLARE v_numero_oc   VARCHAR(50)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cliente     VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_exp      BIGINT;
    DECLARE v_numero_exp  VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_creado      TINYINT DEFAULT 0;
    DECLARE v_etapa_ant   VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_sla         INT DEFAULT 4;
    DECLARE v_usuario     VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_notificados INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_oc;
        DROP TEMPORARY TABLE IF EXISTS tmp_lib;
        DROP TEMPORARY TABLE IF EXISTS tmp_lib_exp;
        GET DIAGNOSTICS CONDITION 1
            @err_msg  = MESSAGE_TEXT,
            @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje,
               CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF FN_PermisoAccion(p_id_usuario, 'oc_liberar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para liberar expedientes a programación.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_CalcularOrdenesCompra(p_id_usuario, p_id_oc);
    SELECT COUNT(*), MAX(id_propuesta), MAX(id_requerimiento), MAX(id_responsable), MAX(numero_oc), MAX(id_expediente)
      INTO v_existe, v_id_prop, v_id_rq, v_id_resp, v_numero_oc, v_id_exp
    FROM tmp_oc;
    DROP TEMPORARY TABLE IF EXISTS tmp_oc;
    IF v_existe = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'La orden de compra no existe o no pertenece a tu área.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_EvaluarLiberacionOrdenCompra(p_id_usuario, p_id_oc);
    SELECT IFNULL(SUM(estado = 'bloqueante'), 0), IFNULL(SUM(estado = 'alerta'), 0),
           GROUP_CONCAT(IF(estado = 'bloqueante', detalle, NULL) ORDER BY orden SEPARATOR ' '),
           GROUP_CONCAT(IF(estado = 'alerta', descripcion, NULL) ORDER BY orden SEPARATOR ', '),
           JSON_ARRAYAGG(JSON_OBJECT('codigo', codigo, 'estado', estado, 'detalle', detalle))
      INTO v_bloqueantes, v_alertas, v_texto_bloq, v_texto_alert, v_detalles
    FROM tmp_lib;

    IF v_bloqueantes > 0 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_lib;
        SELECT 1 AS IdTipoMensaje, CONCAT('No se puede liberar: ', v_texto_bloq) AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_alertas > 0 AND IFNULL(p_confirma_impacto, 0) <> 1 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_lib;
        SELECT 1 AS IdTipoMensaje,
               CONCAT('Hay requisitos pendientes (', v_texto_alert,
                      '). Confirme que entiende el impacto: la responsabilidad pasa a Operaciones.') AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT CAST(IFNULL(MAX(Num2), 4) AS SIGNED) INTO v_sla
    FROM tabla_maestra WHERE IdMaestro = 49 AND IdEmpresa = 1 AND String1 = 'expediente' AND String2 = 'programacion';
    SELECT razon_social INTO v_cliente FROM cliente WHERE id_cliente = (SELECT id_cliente FROM orden_compra WHERE id_oc = p_id_oc);
    SELECT CONCAT(nombre, ' ', apellido) INTO v_usuario FROM usuario WHERE id_usuario = p_id_usuario;

    START TRANSACTION;

    -- Expediente: nace con el RQ (migración 71). Solo se crea aquí si la propuesta no tiene RQ con expediente.
    IF v_id_exp IS NULL THEN
        INSERT INTO expediente_digital (numero, id_requerimiento, id_propuesta, id_orden_compra, id_cliente, etapa_actual, estado,
                                        id_responsable_actual, fecha_creacion, creado_por)
        SELECT CONCAT('EXP-TMP-', p_id_oc), v_id_rq, v_id_prop, p_id_oc, oc.id_cliente, 'orden_compra', 'activo', NULL, NOW(), p_id_usuario
        FROM orden_compra oc WHERE oc.id_oc = p_id_oc;
        SET v_id_exp = LAST_INSERT_ID();
        UPDATE expediente_digital SET numero = CONCAT('EXP-', YEAR(fecha_creacion), '-', LPAD(id_expediente, 4, '0'))
        WHERE id_expediente = v_id_exp;
        SET v_creado = 1;
    END IF;
    SELECT numero, etapa_actual INTO v_numero_exp, v_etapa_ant FROM expediente_digital WHERE id_expediente = v_id_exp;

    -- Expedientes que pasan a Programación: el de la propuesta principal y los de las propuestas a las que esta OC
    -- distribuyó saldo (HU-27), siempre que esas propuestas estén aceptadas por el cliente, no tengan otras OC sin
    -- validar ni bloqueos abiertos, y sigan en la etapa comercial.
    DROP TEMPORARY TABLE IF EXISTS tmp_lib_exp;
    CREATE TEMPORARY TABLE tmp_lib_exp (id_expediente BIGINT PRIMARY KEY, etapa_anterior VARCHAR(30));
    INSERT IGNORE INTO tmp_lib_exp (id_expediente, etapa_anterior)
    SELECT e.id_expediente, e.etapa_actual
    FROM expediente_digital e
    WHERE e.id_expediente = v_id_exp AND e.eliminado_en IS NULL AND e.estado <> 'cerrado'
      AND e.etapa_actual IN ('requerimiento', 'propuesta', 'visto_bueno', 'orden_compra');

    INSERT IGNORE INTO tmp_lib_exp (id_expediente, etapa_anterior)
    SELECT e.id_expediente, e.etapa_actual
    FROM oc_propuesta op
    JOIN propuesta_comercial p ON p.id_propuesta = op.id_propuesta
    JOIN expediente_digital e  ON e.id_expediente = FN_ExpedienteDePropuesta(op.id_propuesta)
    WHERE op.id_oc = p_id_oc AND op.eliminado_en IS NULL AND op.id_propuesta <> IFNULL(v_id_prop, 0)
      AND e.eliminado_en IS NULL AND e.estado <> 'cerrado'
      AND e.etapa_actual IN ('requerimiento', 'propuesta', 'visto_bueno', 'orden_compra')
      AND (p.estado = 'aprobado'
           OR EXISTS (SELECT 1 FROM seguimiento_comercial s
                      WHERE s.id_propuesta = p.id_propuesta AND s.estado = 'cerrado_aceptacion' AND s.eliminado_en IS NULL))
      AND NOT EXISTS (SELECT 1 FROM orden_compra o2
                      JOIN oc_propuesta op2 ON op2.id_oc = o2.id_oc AND op2.eliminado_en IS NULL AND op2.id_propuesta = p.id_propuesta
                      WHERE o2.id_oc <> p_id_oc AND o2.eliminado_en IS NULL AND o2.estado <> 'anulada'
                        AND (o2.estado = 'pendiente_validacion'
                             OR EXISTS (SELECT 1 FROM orden_compra_observacion ob
                                        WHERE ob.id_oc = o2.id_oc AND ob.estado = 'abierta' AND ob.eliminado_en IS NULL)))
      AND NOT EXISTS (SELECT 1 FROM expediente_bloqueador b
                      WHERE b.id_expediente = e.id_expediente AND b.resuelto = 0 AND b.eliminado_en IS NULL AND b.clase = 'bloqueo');

    UPDATE expediente_digital e
    JOIN tmp_lib_exp t ON t.id_expediente = e.id_expediente
    SET e.id_orden_compra       = IFNULL(e.id_orden_compra, p_id_oc),
        e.id_propuesta          = IF(e.id_expediente = v_id_exp, IFNULL(e.id_propuesta, v_id_prop), e.id_propuesta),
        e.etapa_actual          = 'programacion',
        e.area_responsable      = 'operaciones',
        e.id_responsable_actual = NULL,
        e.fecha_etapa           = NOW(),
        e.sla_horas             = v_sla,
        e.fecha_limite_sla      = NOW() + INTERVAL v_sla HOUR,
        e.modificado_por        = p_id_usuario;

    INSERT INTO expediente_etapa (id_expediente, etapa, area, id_responsable, fecha_inicio, sla_horas, fecha_limite,
                                  resultado, comentario, UsuCre, FchCre)
    SELECT t.id_expediente, 'programacion', 'operaciones', NULL, NOW(), v_sla, NOW() + INTERVAL v_sla HOUR, 'en_curso',
           LEFT(CONCAT('Liberado para programación con la OC ', v_numero_oc, '.',
                       IFNULL(CONCAT(' Comentario: ', NULLIF(TRIM(p_comentario), '')), '')), 1000),
           CAST(p_id_usuario AS CHAR), NOW()
    FROM tmp_lib_exp t;

    -- Los requisitos pendientes con los que se libera quedan como excepciones del expediente (Operaciones
    -- las cierra antes de la salida a campo). No impiden avanzar, pero se informan.
    -- (mismo cliente: los requisitos SSOMA aplican a todos los expedientes que se liberan)
    INSERT INTO expediente_bloqueador (id_expediente, clase, descripcion, tipo, etapa, tipo_documental, impacto, critico,
                                       origen_tipo, id_origen, resuelto, creado_por)
    SELECT t.id_expediente, 'excepcion', LEFT(CONCAT(l.descripcion, ': ', l.detalle), 300),
           IF(l.codigo IN ('sctr', 'ssoma'), 'ssoma', 'otro'), 'programacion', 'Seguridad y Salud (SSOMA)',
           'Debe completarse antes de la salida a campo.', 0, 'liberacion', p_id_oc, 0, p_id_usuario
    FROM tmp_lib l
    CROSS JOIN tmp_lib_exp t
    WHERE l.estado = 'alerta' AND l.codigo IN ('sctr', 'ssoma');

    UPDATE expediente_digital e
    JOIN tmp_lib_exp t ON t.id_expediente = e.id_expediente
    SET e.estado = CASE
            WHEN EXISTS (SELECT 1 FROM expediente_bloqueador b WHERE b.id_expediente = e.id_expediente
                         AND b.resuelto = 0 AND b.eliminado_en IS NULL AND b.clase = 'bloqueo')   THEN 'bloqueado'
            WHEN EXISTS (SELECT 1 FROM expediente_bloqueador b WHERE b.id_expediente = e.id_expediente
                         AND b.resuelto = 0 AND b.eliminado_en IS NULL AND b.clase = 'excepcion') THEN 'con_excepcion'
            ELSE 'activo' END;

    DROP TEMPORARY TABLE IF EXISTS tmp_lib;

    UPDATE orden_compra SET fecha_liberacion = NOW(), liberado_por = p_id_usuario, modificado_por = p_id_usuario
    WHERE id_oc = p_id_oc;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('orden_compra', p_id_oc, 'liberar_oc', NULL, 'liberada',
            CONCAT('Expediente ', v_numero_exp, ' liberado para programación',
                   IF(v_alertas > 0, CONCAT(' con requisitos pendientes (', v_texto_alert, '). Responsabilidad trasladada a Operaciones.'), '.'),
                   IFNULL(CONCAT(' Comentario: ', NULLIF(TRIM(p_comentario), '')), '')),
            p_id_usuario, NOW(),
            JSON_OBJECT('id_expediente', v_id_exp, 'expediente_creado', v_creado, 'validaciones', v_detalles,
                        'confirma_impacto', IFNULL(p_confirma_impacto, 0)));

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en)
    SELECT 'expediente', t.id_expediente,
           IF(v_creado = 1 AND t.id_expediente = v_id_exp, 'crear_y_liberar_programacion', 'liberar_programacion'),
           t.etapa_anterior, 'programacion',
           CONCAT('Liberado para programación con la OC ', v_numero_oc, '. Responsable: Operaciones. SLA: ', v_sla, ' horas.'),
           p_id_usuario, NOW()
    FROM tmp_lib_exp t;

    DROP TEMPORARY TABLE IF EXISTS tmp_lib_exp;

    INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
    SELECT u.id_usuario, 5,
           LEFT(CONCAT('Expediente ', v_numero_exp, ' liberado para programación'), 150),
           CONCAT(v_usuario, ' liberó el expediente ', v_numero_exp, ' (OC ', v_numero_oc, ', ', IFNULL(v_cliente, 'cliente'),
                  ') para programación. SLA: ', v_sla, ' horas.',
                  IF(v_alertas > 0, CONCAT(' Pendiente antes de la salida a campo: ', v_texto_alert, '.'), '')),
           'orden_compra', p_id_oc, NOW(), p_id_usuario
    FROM usuario u
    WHERE u.eliminado_en IS NULL AND u.estado = 'activo' AND u.id_usuario <> p_id_usuario
      AND ((u.area = 'operaciones' AND u.rol_sistema IN ('supervisor', 'administrador')) OR u.id_usuario = v_id_resp);

    SET v_notificados = ROW_COUNT();

    COMMIT;

    SELECT 2 AS IdTipoMensaje, CONCAT('Expediente ', v_numero_exp, ' liberado para programación.') AS Mensaje;
    SELECT p_id_oc AS id_oc, v_numero_oc AS numero_oc, v_id_exp AS id_expediente, v_numero_exp AS numero_expediente,
           v_creado AS expediente_creado, 'programacion' AS etapa, IF(v_alertas > 0, 'con_excepcion', 'activo') AS estado_expediente,
           v_alertas AS alertas_pendientes, v_sla AS sla_horas, NOW() + INTERVAL v_sla HOUR AS fecha_limite_programacion,
           v_notificados AS notificados;
END$$

DELIMITER ;


-- SP_LiberarOrdenCompra: punto de entrada. Toma un bloqueo por cliente (GET_LOCK) para que dos operaciones simultáneas
-- sobre las OC del mismo cliente (registro, complementaria, distribución, liberación) no pasen las mismas
-- validaciones a la vez (OC duplicadas, saldo sobreasignado o doble liberación). La lógica está en SP_LiberarOrdenCompraInterno.
DROP PROCEDURE IF EXISTS SP_LiberarOrdenCompra;

DELIMITER $$

CREATE PROCEDURE SP_LiberarOrdenCompra(
    IN p_id_usuario        BIGINT,
    IN p_id_oc             BIGINT,
    IN p_confirma_impacto  TINYINT,
    IN p_comentario        VARCHAR(1000) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
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

    CALL SP_LiberarOrdenCompraInterno(p_id_usuario, p_id_oc, p_confirma_impacto, p_comentario);

    DO RELEASE_LOCK(v_bloqueo);
END$$

DELIMITER ;
