-- HU-30 Tab ✓ Cierre de la ficha del expediente (carga perezosa, solo lectura). Acción expediente_bandeja.
-- Datos del cierre del servicio: conformidad del cliente, informe final, fecha de cierre y observaciones.
-- Resultados: 1 mensaje · 2 resumen (estado del cierre: pendiente, en_revision, conforme u observado; fecha de cierre;
--   informes aprobados y conformidades registradas) · 3 informes técnicos (clave inf-<id> si tiene PDF)
--   · 4 conformidades del cliente · 5 certificados de metrología (clave om-<id>)
DROP PROCEDURE IF EXISTS SP_ObtenerCierreExpediente;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerCierreExpediente(
    IN p_id_usuario    BIGINT,
    IN p_id_expediente BIGINT
)
proc: BEGIN
    IF FN_PermisoAccion(p_id_usuario, 'expediente_bandeja') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver los expedientes digitales.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM expediente_digital WHERE id_expediente = p_id_expediente AND eliminado_en IS NULL) THEN
        SELECT 1 AS IdTipoMensaje, 'El expediente no existe.' AS Mensaje;
        LEAVE proc;
    END IF;

    DROP TEMPORARY TABLE IF EXISTS tmp_exp_inf;
    CREATE TEMPORARY TABLE tmp_exp_inf AS
    SELECT it.*, os.numero AS os
    FROM informe_tecnico it
    JOIN orden_servicio os ON os.id_os = it.id_os AND os.id_expediente = p_id_expediente AND os.eliminado_en IS NULL
                          AND os.estado <> 'anulada'
    WHERE it.eliminado_en IS NULL;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Resumen del cierre
    SELECT CASE WHEN k.conformes > 0 AND k.observadas = 0 THEN 'conforme'
                WHEN k.observadas > 0 THEN 'observado'
                WHEN k.informes > 0 THEN 'en_revision'
                ELSE 'pendiente' END AS estado_cierre,
           k.fecha_cierre, k.informes, k.informes_aprobados, k.conformes, k.observadas
    FROM (SELECT (SELECT COUNT(*) FROM tmp_exp_inf) AS informes,
                 (SELECT COUNT(*) FROM informe_tecnico it2
                  JOIN orden_servicio o2 ON o2.id_os = it2.id_os AND o2.id_expediente = p_id_expediente AND o2.eliminado_en IS NULL
                  WHERE it2.eliminado_en IS NULL AND it2.estado = 'aprobado') AS informes_aprobados,
                 IFNULL(SUM(cd.estado = 'conforme'), 0) AS conformes, IFNULL(SUM(cd.estado = 'observado'), 0) AS observadas,
                 MAX(IF(cd.estado = 'conforme', cd.registrado_en, NULL)) AS fecha_cierre
          FROM conformidad_digital cd
          JOIN informe_tecnico it ON it.id_informe = cd.id_informe AND it.eliminado_en IS NULL
          JOIN orden_servicio os ON os.id_os = it.id_os AND os.id_expediente = p_id_expediente AND os.eliminado_en IS NULL
          WHERE cd.eliminado_en IS NULL) k;

    -- 3. Informes técnicos
    SELECT t.id_informe, t.numero, t.os, t.version, t.estado, t.diagnostico_principal, t.hallazgos,
           t.fecha_creacion, t.fecha_envio_cliente, IF(t.url_pdf IS NULL, NULL, CONCAT('inf-', t.id_informe)) AS clave_pdf,
           CONCAT(ut.nombre, ' ', ut.apellido) AS tecnico, CONCAT(ur.nombre, ' ', ur.apellido) AS revisor
    FROM tmp_exp_inf t
    LEFT JOIN usuario ut ON ut.id_usuario = t.id_tecnico
    LEFT JOIN usuario ur ON ur.id_usuario = t.id_revisor
    ORDER BY t.fecha_creacion DESC;

    DROP TEMPORARY TABLE IF EXISTS tmp_exp_inf;

    -- 4. Conformidades del cliente
    SELECT cd.id_conformidad, it.numero AS informe, os.numero AS os, cd.tipo, cd.estado, cd.observaciones, cd.registrado_en,
           ct.nombres AS contacto, ct.cargo AS cargo_contacto
    FROM conformidad_digital cd
    JOIN informe_tecnico it ON it.id_informe = cd.id_informe AND it.eliminado_en IS NULL
    JOIN orden_servicio os ON os.id_os = it.id_os AND os.id_expediente = p_id_expediente AND os.eliminado_en IS NULL
    LEFT JOIN contacto_cliente ct ON ct.id_contacto = cd.id_contacto_cliente
    WHERE cd.eliminado_en IS NULL
    ORDER BY cd.registrado_en DESC;

    -- 5. Certificados de metrología
    SELECT IF(om.url_certificado_pdf IS NULL, NULL, CONCAT('om-', om.id_om)) AS clave, om.numero, om.numero_certificado,
           om.fecha_emision_certificado, om.estado
    FROM orden_metrologia om
    WHERE om.id_expediente = p_id_expediente AND om.eliminado_en IS NULL
    ORDER BY om.id_om;
END$$

DELIMITER ;
