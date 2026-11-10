-- ============================================================
-- SP_ObtenerSolicitudCorrelativoMovil  (App Mobile HU-14 — "Solicitud de correlativo" y modal "Correlativo y certificado" · solo lectura)
-- Todo lo que necesita el técnico para pedir o usar el correlativo de UN equipo de su OS. El contexto (OS suya, Hard Stop, equipo iniciado) lo valida
-- SP_ContextoCorrelativoMovil, una sola vez. No escribe nada (la reserva diaria se genera con SP_GenerarReservaCorrelativosMovil).
-- Resultados: 1 mensaje · 2 cabecera (1 fila) · 3 tipos de certificado · 4 correlativo asignado listo para usar (0 o 1 fila) · 5 reserva libre del técnico.
--   Cabecera: orden, equipo, serie, código, COD TW, clase y capacidad (equipo_cliente), tipo_orden (OS · Servicio técnico / OM · Metrología según la RQ),
--     puede_solicitar (en ejecución, ensayos finalizados, sin ticket abierto y sin certificado) y motivo_bloqueo con el texto cuando no se puede,
--     ticket_abierto_* (el ticket solicitado o asignado de este equipo), numero_certificado (el ya guardado en el informe), tecnico_metrologia (recibe reserva).
--   Correlativo asignado: el ticket de este equipo en estado asignado que aún no se usó (asignado por quién y cuándo, hora de Lima).
--   Reserva libre: los correlativos reservados al técnico que todavía no usó.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerSolicitudCorrelativoMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerSolicitudCorrelativoMovil(
    IN p_id_usuario   BIGINT,
    IN p_id_os        BIGINT,
    IN p_id_os_equipo BIGINT
)
proc: BEGIN
    DECLARE v_msg       VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_id_eq     BIGINT DEFAULT NULL;
    DECLARE v_estado    VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_hab       TINYINT DEFAULT 0;
    DECLARE v_final     DATETIME DEFAULT NULL;
    DECLARE v_cert      VARCHAR(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_tk_id     BIGINT DEFAULT NULL;
    DECLARE v_tk_num    VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_tk_estado VARCHAR(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_puede     TINYINT DEFAULT 0;
    DECLARE v_motivo    VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_cc_ctx;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 OR IFNULL(p_id_os_equipo, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio o equipo no válido.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_ContextoCorrelativoMovil(p_id_usuario, p_id_os, p_id_os_equipo);
    SELECT c.mensaje, c.id_equipo, c.estado_equipo, c.habilitado, c.ens_final, c.numero_certificado
    INTO   v_msg, v_id_eq, v_estado, v_hab, v_final, v_cert
    FROM   tmp_cc_ctx c LIMIT 1;
    IF v_msg IS NOT NULL THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_cc_ctx;
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT t.id_ticket_met, t.numero, t.estado INTO v_tk_id, v_tk_num, v_tk_estado
    FROM   ticket_metrologia t
    WHERE  t.id_os = p_id_os AND t.id_equipo = v_id_eq AND t.estado IN ('solicitado', 'asignado') AND t.eliminado_en IS NULL
    ORDER BY t.id_ticket_met DESC LIMIT 1;

    IF v_cert IS NOT NULL THEN
        SET v_motivo = CONCAT('Este equipo ya tiene el certificado ', v_cert, '.');
    ELSEIF v_hab = 0 OR v_estado <> 'en_ejecucion' THEN
        SET v_motivo = IF(v_estado = 'pausado', 'El equipo está pausado: reanúdalo para solicitar el correlativo.',
                          IF(v_estado = 'completado', 'Este equipo ya está completado.', 'El servicio ya no está en curso.'));
    ELSEIF v_final IS NULL THEN
        SET v_motivo = 'Primero finaliza los ensayos y la calibración del equipo.';
    ELSEIF v_tk_id IS NOT NULL THEN
        SET v_motivo = CONCAT('Ya hay un ticket abierto para este equipo (', v_tk_num, ').');
    END IF;
    SET v_puede = IF(v_motivo IS NULL, 1, 0);

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2 Cabecera
    SELECT c.id_os, c.numero_os, c.id_os_equipo, c.nombre_equipo AS equipo, c.numero, c.num_serie, c.codigo_cliente, c.codigo_tw, c.clase, c.capacidad,
           c.tipo_orden, c.numero_rq, c.resultado,
           v_puede AS puede_solicitar, v_motivo AS motivo_bloqueo,
           v_tk_id AS ticket_abierto_id, v_tk_num AS ticket_abierto_numero, v_tk_estado AS ticket_abierto_estado,
           c.numero_certificado, c.tecnico_metrologia
    FROM   tmp_cc_ctx c;

    -- 3 Tipos de certificado
    SELECT m.Num1 AS id_tipo, m.String1 AS nombre
    FROM   tabla_maestra m
    WHERE  m.Descripcion = 'TIPO_CERTIFICADO_MET' AND m.IdEmpresa = 1 AND m.eliminado_en IS NULL
    ORDER BY m.Num1;

    -- 4 Correlativo asignado y todavía sin usar
    SELECT t.id_ticket_met AS id_ticket, t.numero AS ticket, t.correlativo_asignado AS correlativo,
           CONVERT_TZ(t.fecha_asignacion, '+00:00', '-05:00') AS asignado_en,
           TRIM(CONCAT(IFNULL(j.nombre, ''), ' ', IFNULL(j.apellido, ''))) AS asignado_por
    FROM   ticket_metrologia t
    LEFT JOIN usuario j ON j.id_usuario = t.id_metrologo_asignado
    WHERE  t.id_os = p_id_os AND t.id_equipo = v_id_eq AND t.estado = 'asignado' AND t.eliminado_en IS NULL
      AND  t.id_tecnico_solicitante = p_id_usuario
    ORDER BY t.id_ticket_met DESC LIMIT 1;

    -- 5 Reserva libre del técnico
    SELECT c.codigo AS correlativo
    FROM   correlativo_metrologia c
    WHERE  c.id_tecnico = p_id_usuario AND c.estado = 'reservado' AND c.eliminado_en IS NULL
    ORDER BY c.anio, c.numero;

    DROP TEMPORARY TABLE IF EXISTS tmp_cc_ctx;
END$$

DELIMITER ;
