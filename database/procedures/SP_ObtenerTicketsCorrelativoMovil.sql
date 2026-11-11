-- ============================================================
-- SP_ObtenerTicketsCorrelativoMovil  (App Mobile HU-14 — "Mis tickets" · solo lectura)
-- Los tickets de correlativo que pidió el técnico que inició sesión (el id sale del token), del más reciente al más antiguo (máx. 50).
--   p_filtro: todos (por defecto) · pendientes (solicitados) · asignados (asignados y ya usados).   p_id_os: solo los de esa OS (NULL / 0 = todos).
--   estado del ticket: solicitado → "Pendiente" · asignado → "Asignado" · despachado → asignado y ya usado en el certificado (usado = 1).
--   Línea de tiempo: solicitado_en (hora de Lima) y asignado_en / asignado_por cuando Metrología lo asignó.
--   id_os_equipo = el objetivo (os_equipo) de ese equipo en la OS, para abrir "Correlativo y certificado".  puede_usar = asignado, sin usar y el informe del equipo aún
--   sin certificado.
-- Resultados: 1 mensaje · 2 tickets.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerTicketsCorrelativoMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerTicketsCorrelativoMovil(
    IN p_id_usuario BIGINT,
    IN p_filtro     VARCHAR(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_os      BIGINT
)
proc: BEGIN
    DECLARE v_filtro VARCHAR(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    SET v_filtro = IFNULL(NULLIF(TRIM(p_filtro), ''), 'todos');
    IF IFNULL(p_id_usuario, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no encontrado.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_filtro NOT IN ('todos', 'pendientes', 'asignados') THEN
        SELECT 1 AS IdTipoMensaje, 'El filtro de tickets no es válido.' AS Mensaje; LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT t.id_ticket_met AS id_ticket, t.numero AS numero, t.estado AS estado, IF(t.estado = 'despachado', 1, 0) AS usado,
           t.id_os AS id_os, os.numero AS numero_os, oe.id AS id_os_equipo,
           COALESCE(NULLIF(TRIM(su.descripcion), ''), ec.clasificacion) AS equipo, COALESCE(ec.codigo_cliente, ec.codigo_tw) AS codigo_equipo, ec.num_serie AS num_serie,
           t.id_tipo_certificado AS id_tipo, tc.String1 AS tipo_certificado, t.notas AS observacion,
           CONVERT_TZ(t.fecha_solicitud, '+00:00', '-05:00') AS solicitado_en,
           TRIM(CONCAT(IFNULL(ut.nombre, ''), ' ', IFNULL(ut.apellido, ''))) AS solicitante,
           t.correlativo_asignado AS correlativo,
           CONVERT_TZ(t.fecha_asignacion, '+00:00', '-05:00') AS asignado_en,
           TRIM(CONCAT(IFNULL(uj.nombre, ''), ' ', IFNULL(uj.apellido, ''))) AS asignado_por,
           IF(t.estado = 'asignado'
              AND (SELECT it.numero_certificado FROM informe_tecnico it
                   WHERE it.id_os = t.id_os AND it.id_equipo = t.id_equipo AND it.eliminado_en IS NULL ORDER BY it.id_informe DESC LIMIT 1) IS NULL, 1, 0) AS puede_usar
    FROM   ticket_metrologia t
    JOIN   orden_servicio os ON os.id_os = t.id_os
    LEFT JOIN os_equipo oe ON oe.id_os = t.id_os AND oe.id_equipo = t.id_equipo AND oe.eliminado_en IS NULL
    LEFT JOIN equipo_cliente ec ON ec.id_equipo = t.id_equipo
    LEFT JOIN suministros su ON su.id_suministro = ec.id_suministro
    LEFT JOIN tabla_maestra tc ON tc.Descripcion = 'TIPO_CERTIFICADO_MET' AND tc.IdEmpresa = 1 AND tc.Num1 = t.id_tipo_certificado
    LEFT JOIN usuario ut ON ut.id_usuario = t.id_tecnico_solicitante
    LEFT JOIN usuario uj ON uj.id_usuario = t.id_metrologo_asignado
    WHERE  t.id_tecnico_solicitante = p_id_usuario AND t.eliminado_en IS NULL AND t.estado <> 'cancelado'
      AND  (IFNULL(p_id_os, 0) <= 0 OR t.id_os = p_id_os)
      AND  (v_filtro = 'todos'
            OR (v_filtro = 'pendientes' AND t.estado = 'solicitado')
            OR (v_filtro = 'asignados'  AND t.estado IN ('asignado', 'despachado')))
    ORDER BY t.fecha_solicitud DESC, t.id_ticket_met DESC
    LIMIT 50;
END$$

DELIMITER ;
