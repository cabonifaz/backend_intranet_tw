-- HU-59 (Sprint 5) Revisión Técnica: "Confirmar Revisión". El informe queda REVISADO, cerrado e inmutable.
-- Acceso: rt_revisar. Vuelve a validar el checklist obligatorio de SP_PrepararRevisionInforme (fotos, ensayos completos,
-- precotización si hay observaciones y procedimiento ejecutado). p_nota: nota interna del supervisor (opcional, hasta 500).
-- Efectos: estado 'revisado' con fecha y revisor, la precotización (si hay) queda enviada a Comercial, evento 'revisado' en el
-- historial y aviso al técnico y al responsable del RQ. Dos supervisores a la vez: gana el primero, el otro ve "ya fue revisado".
-- Resultados: 1 mensaje, 2 informe revisado.
DROP PROCEDURE IF EXISTS SP_RegistrarRevisionInforme;

DELIMITER $$

CREATE PROCEDURE SP_RegistrarRevisionInforme(
    IN p_id_usuario BIGINT,
    IN p_id_informe BIGINT,
    IN p_nota       VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_existe     INT DEFAULT 0;
    DECLARE v_estado     VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_falta      VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_tecnico BIGINT;
    DECLARE v_id_resp    BIGINT;
    DECLARE v_id_pc      BIGINT;
    DECLARE v_numero_pc  VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_numero_os  VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_equipo     VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_nota       VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF FN_PermisoAccion(p_id_usuario, 'rt_revisar') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para registrar la revisión de informes.' AS Mensaje;
        LEAVE proc;
    END IF;
    SET v_nota = NULLIF(TRIM(IFNULL(p_nota, '')), '');

    CALL SP_ArmarBaseInformes(p_id_usuario, IFNULL(p_id_informe, 0));
    SELECT COUNT(*),
           MAX(CASE WHEN n_fotos = 0 THEN 'Faltan las fotos del servicio.'
                    WHEN n_ensayos_sin_resultado > 0 THEN 'Hay lecturas de ensayo sin resultado.'
                    WHEN n_observaciones > 0 AND IFNULL(n_items_precot, 0) = 0
                        THEN 'Este servicio tiene observaciones registradas. Debes registrar la precotización antes de marcar el informe como revisado.'
                    WHEN n_pasos_realizados = 0 THEN 'Falta registrar el procedimiento ejecutado.'
                    ELSE NULL END),
           MAX(id_tecnico), MAX(id_responsable_rq), MAX(id_precotizacion), MAX(numero_precot), MAX(numero_os), MAX(equipo)
      INTO v_existe, v_falta, v_id_tecnico, v_id_resp, v_id_pc, v_numero_pc, v_numero_os, v_equipo
    FROM tmp_rt_base;
    DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;
    IF v_existe = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El informe no existe o no está en tu alcance.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_falta IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, v_falta AS Mensaje;
        LEAVE proc;
    END IF;

    START TRANSACTION;
    SELECT estado INTO v_estado FROM informe_tecnico WHERE id_informe = p_id_informe FOR UPDATE;
    IF v_estado IN ('revisado', 'aprobado') THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'El informe ya fue revisado.' AS Mensaje;
        LEAVE proc;
    END IF;

    UPDATE informe_tecnico
    SET estado = 'revisado', fecha_revision = NOW(), id_revisor = p_id_usuario, nota_revision = v_nota,
        fecha_inicio_revision = IFNULL(fecha_inicio_revision, NOW()), modificado_por = p_id_usuario
    WHERE id_informe = p_id_informe;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('informe_tecnico', p_id_informe, 'revisado', v_estado, 'revisado', 'Marcó el informe como revisado',
            p_id_usuario, NOW(), JSON_OBJECT('categoria', 'revision', 'nota', v_nota, 'precotizacion', v_numero_pc));

    IF v_id_pc IS NOT NULL THEN
        UPDATE precotizacion SET estado = 'enviado', fecha_envio = IFNULL(fecha_envio, NOW()), modificado_por = p_id_usuario
        WHERE id_precotizacion = v_id_pc AND estado = 'borrador';
    END IF;

    -- Avisos: técnico y responsable del RQ
    INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
    SELECT d.id_usuario, 5, CONCAT('Informe revisado: ', IFNULL(v_numero_os, '')),
           CONCAT('El informe de ', IFNULL(v_equipo, 'el equipo'), IF(v_numero_os IS NULL, '', CONCAT(' (', v_numero_os, ')')),
                  ' fue revisado', IF(v_numero_pc IS NULL, '.', CONCAT(' y generó la precotización ', v_numero_pc, '.'))),
           'informe_tecnico', p_id_informe, NOW(), p_id_usuario
    FROM (SELECT v_id_tecnico AS id_usuario UNION SELECT v_id_resp) d
    WHERE d.id_usuario IS NOT NULL AND d.id_usuario <> p_id_usuario;

    COMMIT;

    SELECT 2 AS IdTipoMensaje, 'Informe marcado como revisado.' AS Mensaje;
    SELECT p_id_informe AS id_informe, 'revisado' AS estado, NOW() AS fecha_revision, v_id_pc AS id_precotizacion, v_numero_pc AS numero_precotizacion;
END$$

DELIMITER ;
