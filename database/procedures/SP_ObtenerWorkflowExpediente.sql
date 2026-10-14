-- HU-30 Workflow del expediente: detalle de gestión por etapa.
-- Acción expediente_bandeja. También alimenta la exportación del workflow (XLSX).
-- Resultados: 1 mensaje · 2 resumen · 3 etapas (responsable, inicio, fin, horas de espera y de proceso, SLA,
--   cumplimiento y resultado) · 4 alerta de bloqueo crítico (0 o 1 fila) · 5 eventos (últimos 10)
DROP PROCEDURE IF EXISTS SP_ObtenerWorkflowExpediente;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerWorkflowExpediente(
    IN p_id_usuario    BIGINT,
    IN p_id_expediente BIGINT
)
proc: BEGIN
    DECLARE v_existe INT DEFAULT 0;

    IF FN_PermisoAccion(p_id_usuario, 'expediente_bandeja') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver los expedientes digitales.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_CalcularExpedientes(p_id_usuario, p_id_expediente);
    SELECT COUNT(*) INTO v_existe FROM tmp_exp;
    IF v_existe = 0 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_exp;
        SELECT 1 AS IdTipoMensaje, 'El expediente no existe.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_CargarEtapasExpediente();
    CALL SP_CargarEventosExpediente(p_id_usuario, p_id_expediente);

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Resumen
    SELECT x.id_expediente, x.numero, x.estado, x.etapa, x.etapa_nombre, x.progreso,
           c.razon_social, c.ruc, x.numero_rq,
           IF(x.id_propuesta IS NULL, NULL, CONCAT(x.numero_propuesta, ' v', x.version_propuesta)) AS propuesta,
           x.numeros_oc, x.numeros_os, x.numeros_om, x.tipo_servicio
    FROM tmp_exp x
    LEFT JOIN cliente c ON c.id_cliente = x.id_cliente;

    -- 3. Etapas
    SELECT orden, etapa, nombre, estado, area, area_nombre, id_responsable, responsable,
           inicio, fin, horas_espera, horas_proceso, sla_horas, cumple_sla, resultado_texto AS resultado
    FROM tmp_exp_etp ORDER BY orden;

    -- 4. Alerta de bloqueo crítico
    SELECT b.id_bloqueador, b.descripcion, b.tipo_documental, b.impacto, b.etapa, b.creado_en AS fecha_registro
    FROM expediente_bloqueador b
    WHERE b.id_expediente = p_id_expediente AND b.resuelto = 0 AND b.eliminado_en IS NULL
      AND b.clase = 'bloqueo' AND b.critico = 1
    ORDER BY b.id_bloqueador
    LIMIT 1;

    -- 5. Eventos
    SELECT ev.fecha, ev.tipo_evento, ev.titulo, ev.descripcion, ev.etapa, ev.id_usuario,
           IFNULL(CONCAT(u.nombre, ' ', u.apellido), 'Sistema') AS usuario, ev.referencia, ev.urgente
    FROM tmp_exp_evt ev
    LEFT JOIN usuario u ON u.id_usuario = ev.id_usuario
    ORDER BY ev.fecha DESC
    LIMIT 10;

    DROP TEMPORARY TABLE IF EXISTS tmp_exp_evt;
    DROP TEMPORARY TABLE IF EXISTS tmp_exp_etp;
    DROP TEMPORARY TABLE IF EXISTS tmp_exp;
END$$

DELIMITER ;
