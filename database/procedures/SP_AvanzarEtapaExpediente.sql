-- HU-34 Avanzar el expediente a la siguiente etapa del flujo.
-- Mismas reglas que SP_PrepararAvanceExpediente (puede_avanzar): acción expediente_avanzar, etapa desde Programación,
-- requisitos críticos cumplidos y sin bloqueos, usuario del área responsable de la etapa (o Gerencia / TI).
-- Efectos: cierra la etapa actual en expediente_etapa (completado) y abre la siguiente con su área, SLA y vencimiento,
--   el responsable pasa a ser el área (sin persona asignada). Desde Facturación pasa a Cerrado (fecha de cierre).
--   Queda auditado (avanzar_etapa) y se notifica a los jefes del área siguiente.
-- Resultados: 1 mensaje · 2 resultado
DROP PROCEDURE IF EXISTS SP_AvanzarEtapaExpediente;

DELIMITER $$

CREATE PROCEDURE SP_AvanzarEtapaExpediente(
    IN p_id_usuario    BIGINT,
    IN p_id_expediente BIGINT,
    IN p_comentario    VARCHAR(1000) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_existe     INT DEFAULT 0;
    DECLARE v_etapa      VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_etapa_nom  VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_orden      INT;
    DECLARE v_manual     TINYINT;
    DECLARE v_area       VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_area_usr   VARCHAR(60)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_numero     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_inicio     DATETIME;
    DECLARE v_id_resp    BIGINT;
    DECLARE v_sla_act    INT;
    DECLARE v_limite_act DATETIME;
    DECLARE v_fallan     VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_validaciones JSON;
    DECLARE v_sig        VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_sig_nom    VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_sig_area   VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_sla        INT;
    DECLARE v_comentario VARCHAR(1000) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_usuario    VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_notificados INT DEFAULT 0;
    DECLARE v_etapa_bd   VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_exp_check;
        DROP TEMPORARY TABLE IF EXISTS tmp_exp;
        GET DIAGNOSTICS CONDITION 1
            @err_msg  = MESSAGE_TEXT,
            @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje,
               CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SET v_comentario = NULLIF(TRIM(IFNULL(p_comentario, '')), '');

    IF FN_PermisoAccion(p_id_usuario, 'expediente_avanzar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para avanzar expedientes.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_CalcularExpedientes(p_id_usuario, p_id_expediente);
    SELECT COUNT(*), MAX(etapa), MAX(etapa_nombre), MAX(orden_etapa), MAX(etapa_manual), MAX(area), MAX(numero),
           MAX(inicio_etapa), MAX(id_responsable), MAX(sla_horas), MAX(fecha_limite)
      INTO v_existe, v_etapa, v_etapa_nom, v_orden, v_manual, v_area, v_numero,
           v_inicio, v_id_resp, v_sla_act, v_limite_act
    FROM tmp_exp;

    IF v_existe = 0 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_exp;
        SELECT 1 AS IdTipoMensaje, 'El expediente no existe.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_etapa = 'cerrado' THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_exp;
        SELECT 1 AS IdTipoMensaje, 'El expediente está cerrado.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_manual = 0 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_exp;
        SELECT 1 AS IdTipoMensaje,
               IF(v_etapa = 'orden_compra', 'El expediente pasa a Programación al liberar la orden de compra.',
                  'Esta etapa avanza sola con la gestión comercial.') AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT area, CONCAT(nombre, ' ', apellido) INTO v_area_usr, v_usuario FROM usuario WHERE id_usuario = p_id_usuario;
    IF IFNULL(v_area_usr, '') <> IFNULL(v_area, '') AND IFNULL(v_area_usr, '') NOT IN ('gerencia', 'ti') THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_exp;
        SELECT 1 AS IdTipoMensaje, 'Solo el área responsable de la etapa puede avanzar el expediente.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_EvaluarAvanceExpediente();
    SELECT GROUP_CONCAT(descripcion ORDER BY orden SEPARATOR ', ') INTO v_fallan
    FROM tmp_exp_check WHERE critico = 1 AND cumple = 0;
    SELECT JSON_ARRAYAGG(JSON_OBJECT('codigo', codigo, 'cumple', cumple)) INTO v_validaciones FROM tmp_exp_check;
    DROP TEMPORARY TABLE IF EXISTS tmp_exp_check;
    DROP TEMPORARY TABLE IF EXISTS tmp_exp;

    IF v_fallan IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, CONCAT('No es posible avanzar. Requisitos pendientes: ', v_fallan, '.') AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT String2, String1, String3 INTO v_sig, v_sig_nom, v_sig_area
    FROM tabla_maestra WHERE IdMaestro = 97 AND IdEmpresa = 1 AND Num1 = v_orden + 1;
    IF v_sig IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'No hay una etapa siguiente configurada.' AS Mensaje;
        LEAVE proc;
    END IF;
    SELECT CAST(MAX(Num2) AS SIGNED) INTO v_sla
    FROM tabla_maestra WHERE IdMaestro = 49 AND IdEmpresa = 1 AND String1 = 'expediente' AND String2 = v_sig;

    START TRANSACTION;

    -- Bloquea el expediente y confirma que nadie lo avanzó mientras tanto (doble clic, dos usuarios)
    SELECT etapa_actual INTO v_etapa_bd FROM expediente_digital WHERE id_expediente = p_id_expediente FOR UPDATE;
    IF v_etapa_bd <> v_etapa THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'El expediente cambió de etapa mientras se procesaba. Actualice la página.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Cierra la etapa actual (si no tenía historial, la registra ya cerrada)
    UPDATE expediente_etapa SET fecha_fin = NOW(), resultado = 'completado',
                                comentario = IFNULL(v_comentario, comentario),
                                UsuMod = CAST(p_id_usuario AS CHAR), FchMod = NOW()
    WHERE id_expediente = p_id_expediente AND etapa = v_etapa AND fecha_fin IS NULL AND SoftDelete = 0;
    IF ROW_COUNT() = 0 THEN
        INSERT INTO expediente_etapa (id_expediente, etapa, area, id_responsable, fecha_inicio, fecha_fin, sla_horas,
                                      fecha_limite, resultado, comentario, UsuCre, FchCre)
        VALUES (p_id_expediente, v_etapa, v_area, v_id_resp, IFNULL(v_inicio, NOW()), NOW(), v_sla_act, v_limite_act,
                'completado', v_comentario, CAST(p_id_usuario AS CHAR), NOW());
    END IF;

    IF v_sig = 'cerrado' THEN
        UPDATE expediente_digital SET etapa_actual = 'cerrado', estado = 'cerrado', fecha_cierre = NOW(),
                                      area_responsable = NULL, id_responsable_actual = NULL,
                                      fecha_etapa = NOW(), sla_horas = NULL, fecha_limite_sla = NULL,
                                      modificado_por = p_id_usuario
        WHERE id_expediente = p_id_expediente;
    ELSE
        INSERT INTO expediente_etapa (id_expediente, etapa, area, id_responsable, fecha_inicio, sla_horas, fecha_limite,
                                      resultado, UsuCre, FchCre)
        VALUES (p_id_expediente, v_sig, v_sig_area, NULL, NOW(), v_sla,
                IF(v_sla IS NULL, NULL, NOW() + INTERVAL v_sla HOUR), 'en_curso', CAST(p_id_usuario AS CHAR), NOW());

        UPDATE expediente_digital SET etapa_actual = v_sig, area_responsable = v_sig_area, id_responsable_actual = NULL,
                                      fecha_etapa = NOW(), sla_horas = v_sla,
                                      fecha_limite_sla = IF(v_sla IS NULL, NULL, NOW() + INTERVAL v_sla HOUR),
                                      modificado_por = p_id_usuario
        WHERE id_expediente = p_id_expediente;
        CALL SP_ActualizarEstadoExpediente(p_id_expediente, p_id_usuario);
    END IF;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario,
                                  registrado_en, metadata)
    VALUES ('expediente', p_id_expediente, 'avanzar_etapa', v_etapa, v_sig,
            CONCAT(v_etapa_nom, ' completada. Pasa a ', v_sig_nom, '.', IFNULL(CONCAT(' Comentario: ', v_comentario), '')),
            p_id_usuario, NOW(), JSON_OBJECT('etapa', v_etapa, 'siguiente', v_sig, 'validaciones', v_validaciones));

    IF v_sig <> 'cerrado' THEN
        CALL SP_NotificarAreaExpediente(p_id_expediente, v_sig_area, NULL,
            CONCAT('Expediente ', v_numero, ' en ', v_sig_nom),
            CONCAT(v_usuario, ' completó la etapa ', v_etapa_nom, ' del expediente ', v_numero,
                   '. Ahora está en ', v_sig_nom, ' y es responsabilidad de tu área.',
                   IFNULL(CONCAT(' SLA: ', v_sla, ' horas.'), '')),
            p_id_usuario, v_notificados);
    END IF;

    COMMIT;

    SELECT 2 AS IdTipoMensaje,
           IF(v_sig = 'cerrado', CONCAT('Expediente ', v_numero, ' cerrado.'), CONCAT('Expediente ', v_numero, ' avanzó a ', v_sig_nom, '.')) AS Mensaje;
    SELECT p_id_expediente AS id_expediente, v_numero AS numero, v_etapa AS etapa_anterior, v_sig AS etapa_actual,
           v_sig_nom AS etapa_nombre, v_sig_area AS area_responsable, v_sla AS sla_horas,
           IF(v_sla IS NULL, NULL, NOW() + INTERVAL v_sla HOUR) AS fecha_limite, v_notificados AS notificados;
END$$

DELIMITER ;
