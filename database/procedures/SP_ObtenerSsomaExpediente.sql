-- HU-30 Tab 🛡️ SSOMA de la ficha del expediente (carga perezosa, solo lectura). Acción expediente_bandeja.
-- Checklist de habilitación por técnico de cada OS, documentos SSOMA cargados y estado de validación.
-- Resultados: 1 mensaje · 2 resumen (personal, habilitados, pendientes, bloqueados, documentos observados o vencidos,
--   estado global: sin_personal, habilitado, pendiente o bloqueado) · 3 checklist por técnico · 4 documentos SSOMA
--   (clave ssoma-<id> para ver/descargar) · 5 requisitos SSOMA del cliente
DROP PROCEDURE IF EXISTS SP_ObtenerSsomaExpediente;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerSsomaExpediente(
    IN p_id_usuario    BIGINT,
    IN p_id_expediente BIGINT
)
proc: BEGIN
    DECLARE v_id_cliente BIGINT;

    IF FN_PermisoAccion(p_id_usuario, 'expediente_bandeja') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver los expedientes digitales.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM expediente_digital WHERE id_expediente = p_id_expediente AND eliminado_en IS NULL) THEN
        SELECT 1 AS IdTipoMensaje, 'El expediente no existe.' AS Mensaje;
        LEAVE proc;
    END IF;
    SELECT COALESCE(e.id_cliente, r.id_cliente) INTO v_id_cliente
    FROM expediente_digital e LEFT JOIN requerimiento r ON r.id_requerimiento = e.id_requerimiento
    WHERE e.id_expediente = p_id_expediente;

    DROP TEMPORARY TABLE IF EXISTS tmp_exp_ssp;
    CREATE TEMPORARY TABLE tmp_exp_ssp AS
    SELECT p.id, p.id_os, os.numero AS os, p.id_usuario, p.rol_en_servicio, p.estado_ssoma
    FROM os_personal p
    JOIN orden_servicio os ON os.id_os = p.id_os AND os.id_expediente = p_id_expediente AND os.eliminado_en IS NULL
                          AND os.estado <> 'anulada'
    WHERE p.eliminado_en IS NULL;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Resumen
    SELECT k.personal, k.habilitados, k.pendientes, k.bloqueados, d.observados, d.vencidos,
           CASE WHEN k.personal = 0 THEN 'sin_personal' WHEN k.bloqueados > 0 THEN 'bloqueado'
                WHEN k.pendientes > 0 OR d.observados > 0 OR d.vencidos > 0 THEN 'pendiente' ELSE 'habilitado' END AS estado_global
    FROM (SELECT COUNT(*) AS personal, IFNULL(SUM(estado_ssoma = 'habilitado'), 0) AS habilitados,
                 IFNULL(SUM(estado_ssoma = 'pendiente'), 0) AS pendientes, IFNULL(SUM(estado_ssoma = 'bloqueado'), 0) AS bloqueados
          FROM tmp_exp_ssp) k
    CROSS JOIN (SELECT IFNULL(SUM(sd.estado = 'observado'), 0) AS observados,
                       IFNULL(SUM(sd.estado = 'vencido' OR (sd.fecha_vencimiento IS NOT NULL AND sd.fecha_vencimiento < CURDATE())), 0) AS vencidos
                FROM ssoma_documento sd
                JOIN orden_servicio os ON os.id_os = sd.id_os AND os.id_expediente = p_id_expediente AND os.eliminado_en IS NULL
                WHERE sd.eliminado_en IS NULL) d;

    -- 3. Checklist por técnico (un renglón por requisito que tiene documento)
    SELECT t.os, t.id_usuario, CONCAT(u.nombre, ' ', u.apellido) AS tecnico, t.rol_en_servicio, t.estado_ssoma,
           sd.id_requisito, r36.String1 AS requisito,
           CASE WHEN sd.id_ssoma_doc IS NULL THEN 'sin_documento'
                WHEN sd.estado = 'vencido' OR (sd.fecha_vencimiento IS NOT NULL AND sd.fecha_vencimiento < CURDATE()) THEN 'vencido'
                ELSE sd.estado END AS estado_documento,
           sd.fecha_vencimiento
    FROM tmp_exp_ssp t
    LEFT JOIN usuario u ON u.id_usuario = t.id_usuario
    LEFT JOIN ssoma_documento sd ON sd.id_os = t.id_os AND sd.id_usuario = t.id_usuario AND sd.eliminado_en IS NULL
    LEFT JOIN tabla_maestra r36 ON r36.IdMaestro = 36 AND r36.IdEmpresa = 1 AND r36.Num1 = sd.id_requisito
    ORDER BY t.os, tecnico, sd.id_requisito;

    -- 4. Documentos SSOMA
    SELECT CONCAT('ssoma-', sd.id_ssoma_doc) AS clave, os.numero AS os, CONCAT(u.nombre, ' ', u.apellido) AS tecnico,
           r36.String1 AS tipo, SUBSTRING_INDEX(sd.url_archivo, '/', -1) AS nombre_archivo, sd.estado, sd.version,
           sd.fecha_carga, sd.fecha_vencimiento, sd.motivo_observacion,
           CONCAT(ua.nombre, ' ', ua.apellido) AS aprobado_por
    FROM ssoma_documento sd
    JOIN orden_servicio os ON os.id_os = sd.id_os AND os.id_expediente = p_id_expediente AND os.eliminado_en IS NULL
    LEFT JOIN usuario u  ON u.id_usuario = sd.id_usuario
    LEFT JOIN usuario ua ON ua.id_usuario = sd.aprobado_por
    LEFT JOIN tabla_maestra r36 ON r36.IdMaestro = 36 AND r36.IdEmpresa = 1 AND r36.Num1 = sd.id_requisito
    WHERE sd.eliminado_en IS NULL
    ORDER BY sd.fecha_carga DESC;

    -- 5. Requisitos SSOMA del cliente
    SELECT rq.id_requisito, r48.String1 AS requisito, rq.es_obligatorio, rq.bloquea_servicio, s.nombre AS sede
    FROM requisito_ssoma_cliente rq
    LEFT JOIN tabla_maestra r48 ON r48.IdMaestro = 48 AND r48.IdEmpresa = 1 AND r48.Num1 = rq.id_requisito
    LEFT JOIN sede_cliente s ON s.id_sede = rq.id_sede
    WHERE rq.id_cliente = v_id_cliente AND rq.eliminado_en IS NULL
    ORDER BY rq.id_requisito;

    DROP TEMPORARY TABLE IF EXISTS tmp_exp_ssp;
END$$

DELIMITER ;
