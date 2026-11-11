-- ============================================================
-- SP_GenerarInformeEquipoMovil  (App Mobile HU-16 — "Generar informe técnico" tras la Validación completa)
-- Con las 5 etapas conformes el técnico genera el informe técnico del equipo:
--   · el equipo pasa a COMPLETADO (os_equipo.estado_ejecucion = 'ejecutado'; se cierra su tramo de tiempo),
--   · el informe recibe su N° definitivo NNNN-AAAA de la secuencia propia (informe_secuencia, atómica; se copia también a informe_tecnico.numero, que era el borrador
--     BRR-########) y queda con generado_en / generado_por. Un informe generado es el que lista y firma la HU-17 (Firma de informes).
--   El informe NO cambia de estado (sigue 'borrador'): el envío a Revisión Técnica de la intranet corresponde al cierre del servicio (constancia, HU-17).
--   Reglas (una sola vez): el contexto lo valida SP_ContextoEquipoMovil (OS del técnico del token, Hard Stop de llegada, equipo iniciado); las 5 etapas
--   SP_ArmarEtapasEquipoMovil (la misma regla de SP_ValidarCierreEquipoMovil). Equipo EN EJECUCIÓN (no pausado). Idempotente: si el informe ya estaba generado
--   responde éxito con el mismo número (repetida = 1) sin tocar nada. Orden de bloqueos fijo: os_equipo → informe técnico → secuencia del año.
--   Auditoría: auditoria_evento (os_equipo y informe_tecnico).
-- Resultados: 1 mensaje (1 regla de negocio · 2 éxito · 3 error) · 2 (solo éxito) id_informe, numero_informe, estado_equipo, repetida.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_GenerarInformeEquipoMovil;

DELIMITER $$

CREATE PROCEDURE SP_GenerarInformeEquipoMovil(
    IN p_id_usuario   BIGINT,
    IN p_id_os        BIGINT,
    IN p_id_os_equipo BIGINT
)
proc: BEGIN
    DECLARE v_msg       VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_id_eq     BIGINT DEFAULT NULL;
    DECLARE v_estado    VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_hab       TINYINT DEFAULT 0;
    DECLARE v_numero    INT DEFAULT NULL;
    DECLARE v_nombre    VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_num_os    VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_servicio  VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_oe        BIGINT DEFAULT NULL;
    DECLARE v_informe   BIGINT DEFAULT NULL;
    DECLARE v_gen       DATETIME DEFAULT NULL;
    DECLARE v_num_inf   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_conformes INT DEFAULT 0;
    DECLARE v_anio      SMALLINT;
    DECLARE v_ultimo    INT DEFAULT 0;
    DECLARE v_n         INT;
    DECLARE v_cod       VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_ahora_utc DATETIME;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_etapas_mov;
        DROP TEMPORARY TABLE IF EXISTS tmp_pend_eq;
        DROP TEMPORARY TABLE IF EXISTS tmp_cat_evid;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 OR IFNULL(p_id_os_equipo, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio o equipo no encontrado.' AS Mensaje; LEAVE proc;
    END IF;

    START TRANSACTION;

    CALL SP_ContextoEquipoMovil(p_id_usuario, p_id_os, p_id_os_equipo, v_msg, v_id_eq, v_estado, v_hab, v_numero, v_nombre, v_num_os, v_servicio);
    IF v_msg IS NOT NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje; LEAVE proc;
    END IF;

    -- Bloqueos en orden fijo: el equipo (objetivo) y luego su informe
    SELECT oe.id INTO v_oe FROM os_equipo oe WHERE oe.id = p_id_os_equipo AND oe.id_os = p_id_os AND oe.eliminado_en IS NULL FOR UPDATE;
    SELECT it.id_informe, it.generado_en, it.numero_informe INTO v_informe, v_gen, v_num_inf
    FROM   informe_tecnico it
    WHERE  it.id_os = p_id_os AND it.id_equipo = v_id_eq AND it.eliminado_en IS NULL
    ORDER BY it.id_informe DESC LIMIT 1
    FOR UPDATE;

    IF v_gen IS NOT NULL THEN
        ROLLBACK;
        SELECT 2 AS IdTipoMensaje, 'El informe técnico ya estaba generado.' AS Mensaje;
        SELECT v_informe AS id_informe, v_num_inf AS numero_informe, 'completado' AS estado_equipo, 1 AS repetida;
        LEAVE proc;
    END IF;
    IF v_estado = 'pausado' THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'El equipo está pausado: reanúdalo para generar el informe.' AS Mensaje; LEAVE proc;
    ELSEIF v_estado <> 'en_ejecucion' OR v_hab = 0 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'El equipo debe estar en ejecución para generar el informe técnico.' AS Mensaje; LEAVE proc;
    END IF;

    -- Hard Stop: las 5 etapas conformes (la misma regla que SP_ValidarCierreEquipoMovil)
    CALL SP_ArmarEtapasEquipoMovil(p_id_os, v_id_eq, v_conformes);
    DROP TEMPORARY TABLE IF EXISTS tmp_etapas_mov;
    DROP TEMPORARY TABLE IF EXISTS tmp_pend_eq;
    IF v_informe IS NULL OR v_conformes < 5 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje,
               CONCAT('No es posible finalizar el trabajo en el equipo: ', 5 - v_conformes, IF(5 - v_conformes = 1, ' etapa está incompleta o no conforme.', ' etapas están incompletas o no conformes.'),
                      ' Revisa los pendientes.') AS Mensaje;
        LEAVE proc;
    END IF;

    -- N° del informe: la secuencia propia del año (se salta cualquier número ya usado)
    SET v_anio = YEAR(UTC_TIMESTAMP() - INTERVAL 5 HOUR);
    INSERT IGNORE INTO informe_secuencia (anio, ultimo) VALUES (v_anio, 0);
    SELECT s.ultimo INTO v_ultimo FROM informe_secuencia s WHERE s.anio = v_anio FOR UPDATE;
    SET v_n = v_ultimo + 1;
    SET v_cod = CONCAT(LPAD(v_n, 4, '0'), '-', v_anio);
    WHILE v_n <= 9999 AND EXISTS (SELECT 1 FROM informe_tecnico x WHERE x.numero_informe = v_cod OR x.numero = v_cod) DO
        SET v_n = v_n + 1;
        SET v_cod = CONCAT(LPAD(v_n, 4, '0'), '-', v_anio);
    END WHILE;
    IF v_n > 9999 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Se agotaron los números de informe del año.' AS Mensaje; LEAVE proc;
    END IF;
    UPDATE informe_secuencia SET ultimo = v_n WHERE anio = v_anio;

    SET v_ahora_utc = UTC_TIMESTAMP();
    UPDATE informe_tecnico
    SET    numero_informe = v_cod, numero = v_cod, generado_en = UTC_TIMESTAMP(), generado_por = p_id_usuario, modificado_por = p_id_usuario
    WHERE  id_informe = v_informe;

    -- El equipo queda COMPLETADO y se cierra su tramo de tiempo
    UPDATE os_equipo
    SET    estado_ejecucion = 'ejecutado', fecha_ejecucion = NOW(),
           acumulado_seg = acumulado_seg + IF(reanudado_utc IS NULL, 0, GREATEST(0, TIMESTAMPDIFF(SECOND, reanudado_utc, v_ahora_utc))),
           reanudado_utc = NULL, pausado = 0, motivo_pausa = NULL, pausa_requiere_aprobacion = 0, modificado_por = p_id_usuario
    WHERE  id = p_id_os_equipo;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('os_equipo', p_id_os_equipo, 'finalizar_equipo', 'en ejecución', 'completado',
            LEFT(CONCAT('Trabajo finalizado en ', IFNULL(v_nombre, 'el equipo'), ' (', v_num_os, '). Informe técnico ', v_cod, '.'), 300),
            p_id_usuario, NOW(), JSON_OBJECT('id_os', p_id_os, 'numero_informe', v_cod));
    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('informe_tecnico', v_informe, 'generar_informe', 'borrador', v_cod,
            LEFT(CONCAT('Informe técnico ', v_cod, ' generado desde la app (HU-16) con las 5 etapas conformes.'), 300),
            p_id_usuario, NOW(), JSON_OBJECT('id_os', p_id_os, 'id_os_equipo', p_id_os_equipo, 'numero_informe', v_cod));

    COMMIT;

    SELECT 2 AS IdTipoMensaje, CONCAT('Informe técnico ', v_cod, ' generado.') AS Mensaje;
    SELECT v_informe AS id_informe, v_cod AS numero_informe, 'completado' AS estado_equipo, 0 AS repetida;
END$$

DELIMITER ;
