-- ============================================================
-- SP_ObtenerCorrelativosJefaturaMovil  (App Mobile HU-34 — "Correlativos · Solicitudes de los técnicos" del Jefe de Metrología · solo lectura)
-- Solo para el área de Metrología (la misma regla del menú de Jefatura: SP_ResolverJefaturaMovil); los demás reciben un mensaje.
-- Resultados: 1 mensaje · 2 KPIs (1 fila) · 3 tickets · 4 reserva por técnico.
--   KPIs: pendientes = tickets solicitados · asignados_hoy = tickets asignados (o ya usados) HOY (hora de Lima) · reservados = correlativos de la reserva diaria
--         aún libres · siguiente_sugerido = el siguiente CC-####-AAAA de la secuencia única (SP_SiguienteCorrelativoMovil, sin consumirlo) · reserva_diaria = cuántos
--         recibe cada técnico (parámetro CORRELATIVO_RESERVA_DIARIA).
--   Tickets: primero los pendientes (los más recientes arriba) y luego los asignados hoy. Equipo = código del cliente (o COD TW) y capacidad; tipo de certificado;
--         patrón = patron_ensayo del informe técnico (HU-10 aún no lo llena: queda vacío); resultado = Conforme / No conforme de los ensayos (HU-10);
--         minutos = antigüedad de la solicitud; correlativo / asignado_en / asignado_por cuando ya se asignó (hora de Lima).
--   Reserva: por cada técnico de Metrología (SP_ArmarTecnicosMetrologiaMovil) con correlativos reservados o usados por confirmar: libres, codigos_libres
--         ("CC-1721-2026 · CC-1722-2026"), usados y usados_texto ("CC-1718-2026 usado · por confirmar").
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerCorrelativosJefaturaMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerCorrelativosJefaturaMovil(
    IN p_id_usuario BIGINT
)
proc: BEGIN
    DECLARE v_area        VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_sede        VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_aut_area    VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_aut_general TINYINT DEFAULT 0;
    DECLARE v_hoy         DATE;
    DECLARE v_num         INT;
    DECLARE v_cod         VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_anio        SMALLINT;
    DECLARE v_reserva     INT DEFAULT 2;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_tm_tec;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    CALL SP_ResolverJefaturaMovil(p_id_usuario, v_area, v_sede, v_aut_area, v_aut_general);
    IF v_area IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Tu cargo no tiene el menú de Jefatura.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_area <> 'metrologia' THEN
        SELECT 1 AS IdTipoMensaje, 'Correlativos se habilita solo para el área de Metrología.' AS Mensaje; LEAVE proc;
    END IF;

    SET v_hoy = DATE(UTC_TIMESTAMP() - INTERVAL 5 HOUR);
    CALL SP_SiguienteCorrelativoMovil(0, v_num, v_cod, v_anio);
    SELECT IFNULL(MAX(m.Num2), 2) INTO v_reserva
    FROM   tabla_maestra m WHERE m.Descripcion = 'PARAMETRO_PROGRAMACION' AND m.String2 = 'CORRELATIVO_RESERVA_DIARIA' AND m.eliminado_en IS NULL;
    IF v_reserva < 0 OR v_reserva > 10 THEN SET v_reserva = 2; END IF;
    CALL SP_ArmarTecnicosMetrologiaMovil();

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2 KPIs
    SELECT (SELECT COUNT(*) FROM ticket_metrologia t WHERE t.eliminado_en IS NULL AND t.estado = 'solicitado')                                   AS pendientes,
           (SELECT COUNT(*) FROM ticket_metrologia t
            WHERE  t.eliminado_en IS NULL AND t.estado IN ('asignado', 'despachado')
              AND  DATE(CONVERT_TZ(t.fecha_asignacion, '+00:00', '-05:00')) = v_hoy)                                                             AS asignados_hoy,
           (SELECT COUNT(*) FROM correlativo_metrologia c WHERE c.eliminado_en IS NULL AND c.estado = 'reservado')                             AS reservados,
           v_cod                                                                                                                                 AS siguiente_sugerido,
           v_reserva                                                                                                                             AS reserva_diaria;

    -- 3 Tickets: pendientes y asignados hoy
    SELECT t.id_ticket_met AS id_ticket, t.numero AS numero, t.estado AS estado,
           TRIM(CONCAT(IFNULL(ut.nombre, ''), ' ', IFNULL(ut.apellido, ''))) AS tecnico,
           os.numero AS numero_os,
           COALESCE(NULLIF(TRIM(su.descripcion), ''), ec.clasificacion) AS equipo,
           COALESCE(ec.codigo_cliente, ec.codigo_tw) AS codigo_equipo, ec.alcance_maximo AS capacidad,
           tc.String1 AS tipo_certificado, t.notas AS observacion,
           (SELECT NULLIF(TRIM(it.patron_ensayo), '') FROM informe_tecnico it
            WHERE it.id_os = t.id_os AND it.id_equipo = t.id_equipo AND it.eliminado_en IS NULL ORDER BY it.id_informe DESC LIMIT 1) AS patron,
           (SELECT IF(it.ensayos_finalizado_en IS NULL, NULL, IF(it.resultado_global = 'fuera' OR it.error_critico_motivo IS NOT NULL, 'No conforme', 'Conforme'))
            FROM informe_tecnico it
            WHERE it.id_os = t.id_os AND it.id_equipo = t.id_equipo AND it.eliminado_en IS NULL ORDER BY it.id_informe DESC LIMIT 1) AS resultado,
           CONVERT_TZ(t.fecha_solicitud, '+00:00', '-05:00') AS solicitado_en,
           GREATEST(0, TIMESTAMPDIFF(MINUTE, t.fecha_solicitud, UTC_TIMESTAMP())) AS minutos,
           t.correlativo_asignado AS correlativo,
           CONVERT_TZ(t.fecha_asignacion, '+00:00', '-05:00') AS asignado_en,
           TRIM(CONCAT(IFNULL(uj.nombre, ''), ' ', IFNULL(uj.apellido, ''))) AS asignado_por
    FROM   ticket_metrologia t
    JOIN   orden_servicio os ON os.id_os = t.id_os
    LEFT JOIN equipo_cliente ec ON ec.id_equipo = t.id_equipo
    LEFT JOIN suministros su ON su.id_suministro = ec.id_suministro
    LEFT JOIN tabla_maestra tc ON tc.Descripcion = 'TIPO_CERTIFICADO_MET' AND tc.IdEmpresa = 1 AND tc.Num1 = t.id_tipo_certificado
    LEFT JOIN usuario ut ON ut.id_usuario = t.id_tecnico_solicitante
    LEFT JOIN usuario uj ON uj.id_usuario = t.id_metrologo_asignado
    WHERE  t.eliminado_en IS NULL
      AND  (t.estado = 'solicitado'
            OR (t.estado IN ('asignado', 'despachado') AND DATE(CONVERT_TZ(t.fecha_asignacion, '+00:00', '-05:00')) = v_hoy))
    ORDER BY IF(t.estado = 'solicitado', 0, 1), t.fecha_solicitud DESC, t.id_ticket_met DESC
    LIMIT 60;

    -- 4 Reserva por técnico
    SELECT x.id_usuario AS id_usuario, x.nombre AS tecnico,
           SUM(x.estado = 'reservado') AS libres,
           IFNULL(GROUP_CONCAT(IF(x.estado = 'reservado', x.codigo, NULL) ORDER BY x.anio, x.numero SEPARATOR ' · '), '') AS codigos_libres,
           SUM(x.estado = 'usado') AS usados,
           IFNULL(GROUP_CONCAT(IF(x.estado = 'usado', CONCAT(x.codigo, ' usado · por confirmar'), NULL) ORDER BY x.anio, x.numero SEPARATOR ' · '), '') AS usados_texto
    FROM  (SELECT tt.id_usuario, tt.nombre, c.estado, c.codigo, c.anio, c.numero
           FROM   tmp_tm_tec tt
           JOIN   correlativo_metrologia c ON c.id_tecnico = tt.id_usuario AND c.estado IN ('reservado', 'usado') AND c.eliminado_en IS NULL
                                                    AND (c.estado = 'reservado' OR c.usado_en >= UTC_TIMESTAMP() - INTERVAL 7 DAY)) x
    GROUP BY x.id_usuario, x.nombre
    ORDER BY x.nombre
    LIMIT 50;

    DROP TEMPORARY TABLE IF EXISTS tmp_tm_tec;
END$$

DELIMITER ;
