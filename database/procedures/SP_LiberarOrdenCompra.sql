-- HU-28 Liberar el expediente para programación.
-- Acción oc_liberar y OC del área del usuario. No debe haber puntos bloqueantes.
-- Si hay requisitos pendientes (alertas: SCTR, SSOMA, bloqueos de otras áreas) se exige p_confirma_impacto = 1:
--   la liberación traslada la responsabilidad de completarlos a Operaciones.
-- Efectos:
--   Expediente: se crea si no existe (EXP-AAAA-NNNN) o se actualiza: etapa programacion, estado activo
--     (con_excepcion si se liberó con alertas), vinculado a la OC. Las alertas quedan como bloqueos del expediente.
--   OC: fecha_liberacion y liberado_por. Auditoría liberar_oc (OC) y liberar_programacion (expediente).
--   Notificación a Operaciones (supervisores y administradores) con el SLA, y al responsable comercial.
-- Resultados: 1 mensaje, 2 resultado.
DROP PROCEDURE IF EXISTS SP_LiberarOrdenCompra;

DELIMITER $$

CREATE PROCEDURE SP_LiberarOrdenCompra(
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
    DECLARE v_correlativo INT DEFAULT 0;
    DECLARE v_sla         INT DEFAULT 4;
    DECLARE v_usuario     VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_notificados INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_oc;
        DROP TEMPORARY TABLE IF EXISTS tmp_lib;
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

    -- Expediente: crear o actualizar
    IF v_id_exp IS NULL THEN
        SELECT IFNULL(MAX(CAST(SUBSTRING_INDEX(numero, '-', -1) AS UNSIGNED)), 0) INTO v_correlativo
        FROM expediente_digital WHERE numero LIKE CONCAT('EXP-', YEAR(CURDATE()), '-%');
        SET v_numero_exp = CONCAT('EXP-', YEAR(CURDATE()), '-', LPAD(v_correlativo + 1, 4, '0'));

        INSERT INTO expediente_digital (numero, id_requerimiento, id_propuesta, id_orden_compra, etapa_actual, estado,
                                        id_responsable_actual, fecha_creacion, creado_por)
        VALUES (v_numero_exp, v_id_rq, v_id_prop, p_id_oc, 'programacion',
                IF(v_alertas > 0, 'con_excepcion', 'activo'), NULL, NOW(), p_id_usuario);
        SET v_id_exp = LAST_INSERT_ID();
        SET v_creado = 1;
        SET v_etapa_ant = NULL;
    ELSE
        SELECT numero, etapa_actual INTO v_numero_exp, v_etapa_ant FROM expediente_digital WHERE id_expediente = v_id_exp;
        UPDATE expediente_digital SET
            id_orden_compra = IFNULL(id_orden_compra, p_id_oc),
            etapa_actual    = 'programacion',
            estado          = IF(v_alertas > 0, 'con_excepcion', 'activo'),
            modificado_por  = p_id_usuario
        WHERE id_expediente = v_id_exp;
    END IF;

    -- Las alertas quedan registradas como bloqueos del expediente (Operaciones las resuelve)
    INSERT INTO expediente_bloqueador (id_expediente, descripcion, tipo, resuelto, creado_por)
    SELECT v_id_exp, LEFT(CONCAT(descripcion, ': ', detalle), 300),
           IF(codigo IN ('sctr', 'ssoma'), 'ssoma', 'otro'), 0, p_id_usuario
    FROM tmp_lib
    WHERE estado = 'alerta' AND codigo IN ('sctr', 'ssoma');

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
    VALUES ('expediente', v_id_exp, IF(v_creado = 1, 'crear_y_liberar_programacion', 'liberar_programacion'),
            v_etapa_ant, 'programacion',
            CONCAT('Liberado para programación con la OC ', v_numero_oc, '. Responsable: Operaciones. SLA: ', v_sla, ' horas.'),
            p_id_usuario, NOW());

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
