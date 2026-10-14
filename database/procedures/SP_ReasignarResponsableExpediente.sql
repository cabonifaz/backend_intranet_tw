-- HU-33 Reasignar el responsable actual del expediente.
-- Acción expediente_reasignar (Jefe de Operaciones / Jefe Comercial). Etapa desde Programación y no cerrada.
-- Quien reasigna debe ser del área responsable de la etapa (o de Gerencia / TI).
-- Nuevo responsable: usuario activo del área responsable de la etapa (o de Gerencia / TI) que puede trabajar el
--   expediente (expediente_avanzar), distinto del actual. El área de la etapa no cambia.
-- Motivo obligatorio (MOTIVO_REASIGNACION_EXPEDIENTE 100), comentario hasta 1000 (obligatorio si el motivo es "Otro").
-- Gestión del SLA: 'mantener' (sigue el vencimiento actual) o 'reiniciar' (nuevo plazo completo desde ahora).
-- Queda auditado (reasignar_responsable) y se notifica al
-- nuevo responsable (intranet, el correo lo envía la aplicación con los datos del resultado 2).
-- Resultados: 1 mensaje · 2 resultado (con nombre y correo del nuevo responsable)
DROP PROCEDURE IF EXISTS SP_ReasignarResponsableExpediente;

DELIMITER $$

CREATE PROCEDURE SP_ReasignarResponsableExpediente(
    IN p_id_usuario    BIGINT,
    IN p_id_expediente BIGINT,
    IN p_id_nuevo      BIGINT,
    IN p_id_motivo     INT,
    IN p_comentario    VARCHAR(1000) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_gestion_sla   VARCHAR(20)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_existe     INT DEFAULT 0;
    DECLARE v_etapa      VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_etapa_nom  VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_manual     TINYINT DEFAULT 0;
    DECLARE v_numero     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_actual     BIGINT;
    DECLARE v_sla        INT;
    DECLARE v_limite     DATETIME;
    DECLARE v_motivo     VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cod_motivo VARCHAR(60)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_comentario VARCHAR(1000) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_gestion    VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_nuevo      VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_correo     VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_area_nueva VARCHAR(60)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_area_etapa VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_area_usr   VARCHAR(60)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_anterior   VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_ejecutor   VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cliente    VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_notificados INT DEFAULT 0;
    DECLARE v_actual_bd  BIGINT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_exp;
        GET DIAGNOSTICS CONDITION 1
            @err_msg  = MESSAGE_TEXT,
            @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje,
               CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SET v_comentario = NULLIF(TRIM(IFNULL(p_comentario, '')), '');
    SET v_gestion    = LOWER(TRIM(IFNULL(p_gestion_sla, 'mantener')));

    IF FN_PermisoAccion(p_id_usuario, 'expediente_reasignar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para reasignar el responsable del expediente.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_CalcularExpedientes(p_id_usuario, p_id_expediente);
    SELECT COUNT(*), MAX(etapa), MAX(etapa_nombre), MAX(etapa_manual), MAX(numero), MAX(id_responsable), MAX(sla_horas),
           MAX(fecha_limite), MAX(area)
      INTO v_existe, v_etapa, v_etapa_nom, v_manual, v_numero, v_actual, v_sla, v_limite, v_area_etapa
    FROM tmp_exp;
    SELECT c.razon_social INTO v_cliente FROM tmp_exp x JOIN cliente c ON c.id_cliente = x.id_cliente;
    DROP TEMPORARY TABLE IF EXISTS tmp_exp;

    IF v_existe = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El expediente no existe.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_etapa = 'cerrado' THEN
        SELECT 1 AS IdTipoMensaje, 'El expediente está cerrado.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_manual = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'La reasignación aplica desde la etapa de Programación.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT area INTO v_area_usr FROM usuario WHERE id_usuario = p_id_usuario;
    IF IFNULL(v_area_usr, '') <> IFNULL(v_area_etapa, '') AND IFNULL(v_area_usr, '') NOT IN ('gerencia', 'ti') THEN
        SELECT 1 AS IdTipoMensaje, 'Solo los jefes del área responsable de la etapa (o Gerencia / TI) pueden reasignar el expediente.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT CONCAT(nombre, ' ', apellido), correo, area INTO v_nuevo, v_correo, v_area_nueva
    FROM usuario WHERE id_usuario = p_id_nuevo AND estado = 'activo' AND eliminado_en IS NULL;
    IF v_nuevo IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Seleccione un nuevo responsable activo.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF p_id_nuevo = IFNULL(v_actual, 0) THEN
        SELECT 1 AS IdTipoMensaje, 'El usuario seleccionado ya es el responsable actual.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF IFNULL(v_area_nueva, '') <> IFNULL(v_area_etapa, '') AND IFNULL(v_area_nueva, '') NOT IN ('gerencia', 'ti') THEN
        SELECT 1 AS IdTipoMensaje, 'El nuevo responsable debe ser del área responsable de la etapa.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF FN_PermisoAccion(p_id_nuevo, 'expediente_avanzar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El usuario seleccionado no tiene permiso para trabajar expedientes.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT String1, String2 INTO v_motivo, v_cod_motivo
    FROM tabla_maestra WHERE IdMaestro = 100 AND IdEmpresa = 1 AND Num1 = p_id_motivo;
    IF v_motivo IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Seleccione el motivo de la reasignación.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_cod_motivo = 'OTRO' AND (v_comentario IS NULL OR CHAR_LENGTH(v_comentario) < 10) THEN
        SELECT 1 AS IdTipoMensaje, 'Con el motivo "Otro" detalle el comentario (mínimo 10 caracteres).' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_gestion NOT IN ('mantener', 'reiniciar') THEN
        SELECT 1 AS IdTipoMensaje, 'Indique la gestión del SLA: mantener o reiniciar.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT CONCAT(nombre, ' ', apellido) INTO v_anterior FROM usuario WHERE id_usuario = v_actual;
    SELECT CONCAT(nombre, ' ', apellido) INTO v_ejecutor FROM usuario WHERE id_usuario = p_id_usuario;
    IF v_gestion = 'reiniciar' THEN
        SET v_limite = NOW() + INTERVAL IFNULL(v_sla, 0) HOUR;
    END IF;

    START TRANSACTION;

    -- Bloquea el expediente y confirma que el responsable no cambió mientras tanto
    SELECT id_responsable_actual INTO v_actual_bd FROM expediente_digital WHERE id_expediente = p_id_expediente FOR UPDATE;
    IF NOT (v_actual_bd <=> v_actual) THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'El responsable del expediente cambió mientras se procesaba. Actualice la página.' AS Mensaje;
        LEAVE proc;
    END IF;

    UPDATE expediente_digital SET
        id_responsable_actual = p_id_nuevo,
        fecha_limite_sla      = v_limite,
        modificado_por        = p_id_usuario
    WHERE id_expediente = p_id_expediente;

    UPDATE expediente_etapa SET
        id_responsable = p_id_nuevo,
        fecha_limite   = v_limite,
        UsuMod         = CAST(p_id_usuario AS CHAR),
        FchMod         = NOW()
    WHERE id_expediente = p_id_expediente AND etapa = v_etapa AND fecha_fin IS NULL AND SoftDelete = 0;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario,
                                  registrado_en, metadata)
    VALUES ('expediente', p_id_expediente, 'reasignar_responsable', LEFT(IFNULL(v_anterior, 'Área'), 80), LEFT(v_nuevo, 80),
            LEFT(CONCAT('Responsable: ', IFNULL(v_anterior, 'sin asignar'), ' → ', v_nuevo, '. Motivo: ', v_motivo,
                        IFNULL(CONCAT('. ', v_comentario), ''),
                        IF(v_gestion = 'reiniciar', '. SLA reiniciado.', '. SLA se mantiene.')), 2000),
            p_id_usuario, NOW(),
            JSON_OBJECT('etapa', v_etapa, 'id_anterior', v_actual, 'id_nuevo', p_id_nuevo, 'id_motivo', p_id_motivo,
                        'gestion_sla', v_gestion, 'fecha_limite', v_limite));

    CALL SP_NotificarAreaExpediente(p_id_expediente, NULL, p_id_nuevo,
        CONCAT('Te asignaron el expediente ', v_numero),
        CONCAT(v_ejecutor, ' te asignó el expediente ', v_numero, IFNULL(CONCAT(' (', v_cliente, ')'), ''),
               ' en la etapa ', v_etapa_nom, '. Motivo: ', v_motivo, '.',
               IFNULL(CONCAT(' Vence: ', DATE_FORMAT(v_limite, '%d/%m/%Y %H:%i'), '.'), '')),
        p_id_usuario, v_notificados);

    COMMIT;

    SELECT 2 AS IdTipoMensaje, CONCAT('Responsable reasignado a ', v_nuevo, '.') AS Mensaje;
    SELECT p_id_expediente AS id_expediente, v_numero AS numero, v_cliente AS cliente, v_etapa AS etapa,
           v_etapa_nom AS etapa_nombre, p_id_nuevo AS id_responsable, v_nuevo AS responsable, v_correo AS correo_responsable,
           v_area_nueva AS area, v_motivo AS motivo, v_comentario AS comentario, v_gestion AS gestion_sla,
           v_limite AS fecha_limite, v_ejecutor AS reasignado_por, v_notificados AS notificados;
END$$

DELIMITER ;
