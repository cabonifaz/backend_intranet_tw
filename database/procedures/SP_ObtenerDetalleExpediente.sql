-- HU-30 Ficha de Detalle del Expediente: sección primaria, KPIs y tab Resumen (el único que carga al abrir la ficha;
-- los demás tabs cargan con su propio SP al seleccionarlos). Solo lectura. Acción expediente_bandeja.
-- Resultados: 1 mensaje
--   2 cabecera: N.° de expediente, cliente, estado global, etapa actual, responsable principal, KPIs (días transcurridos,
--     SLA de la etapa, documentos, bloqueos activos, progreso), vista panorámica (monto, área, fechas), próximo hito,
--     contadores de los tabs y permisos (reasignar solo en etapa comercial: RQ, Propuesta, VB, Seguimiento, OC u OS)
--   3 stepper: las 10 etapas con su estado (completado, en_curso, bloqueado, pendiente, cancelado, no_aplica)
--   4 responsables actuales (comercial, operaciones, SSOMA y técnico)
--   5 árbol de entidades (RQ → propuestas → OC / OS / OM) con su responsable (consultivo)
--   6 alertas y bloqueos activos (bloqueos, excepciones y la alerta del SLA de la etapa si está en riesgo o vencido)
--   7 actividad reciente (últimos 5 eventos del timeline consolidado)
DROP PROCEDURE IF EXISTS SP_ObtenerDetalleExpediente;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerDetalleExpediente(
    IN p_id_usuario    BIGINT,
    IN p_id_expediente BIGINT
)
proc: BEGIN
    DECLARE v_existe      INT DEFAULT 0;
    DECLARE v_documentos  INT DEFAULT 0;
    DECLARE v_versiones   INT DEFAULT 0;
    DECLARE v_ocs         INT DEFAULT 0;
    DECLARE v_vbs         INT DEFAULT 0;
    DECLARE v_resp_com    BIGINT;
    DECLARE v_resp_ope    BIGINT;
    DECLARE v_resp_sso    BIGINT;
    DECLARE v_resp_tec    BIGINT;

    IF FN_PermisoAccion(p_id_usuario, 'expediente_bandeja') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver los expedientes digitales.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_CalcularExpedientes(p_id_usuario, p_id_expediente);
    SELECT COUNT(*) INTO v_existe FROM tmp_exp;
    IF v_existe = 0 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_exp;
        DROP TEMPORARY TABLE IF EXISTS tmp_exp_blq;
        SELECT 1 AS IdTipoMensaje, 'El expediente no existe.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_CargarEtapasExpediente();
    CALL SP_CargarEntidadesExpediente(p_id_expediente);
    CALL SP_CargarEventosExpediente(p_id_usuario, p_id_expediente);
    CALL SP_CargarDocumentosExpediente(p_id_usuario, p_id_expediente);
    SELECT COUNT(*) INTO v_documentos FROM tmp_exp_doc;
    DROP TEMPORARY TABLE IF EXISTS tmp_exp_doc;

    -- Contadores de los tabs: versiones de propuestas, OC (vigentes e historial) y solicitudes de VB
    SELECT COUNT(*) INTO v_versiones FROM propuesta_comercial p JOIN tmp_exp x ON p.id_requerimiento = x.id_requerimiento
    WHERE p.eliminado_en IS NULL;
    SELECT COUNT(*) INTO v_ocs FROM tmp_exp_ent WHERE entidad_tipo = 'orden_compra';
    SELECT COUNT(*) INTO v_vbs FROM visto_bueno v
    JOIN propuesta_comercial p ON p.id_propuesta = v.id_propuesta AND p.eliminado_en IS NULL
    JOIN tmp_exp x ON p.id_requerimiento = x.id_requerimiento
    WHERE v.tipo = 'aprobacion' AND v.eliminado_en IS NULL;

    SELECT MAX(id_responsable), MAX(id_responsable_actual),
           MAX(IF(etapa = 'ssoma', id_responsable_actual, NULL)), MAX(id_tecnico_principal)
      INTO v_resp_com, v_resp_ope, v_resp_sso, v_resp_tec
    FROM tmp_exp;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Cabecera, KPIs y vista panorámica
    SELECT
        x.id_expediente, x.numero, x.estado, x.etapa, x.etapa_nombre, x.etapa_comercial, x.progreso,
        x.id_cliente, c.razon_social, c.ruc,
        x.id_area_rq, ar.String1                          AS area_servicio,
        x.area, a.String1                                 AS area_nombre,
        x.id_responsable, CONCAT(u.nombre, ' ', u.apellido) AS responsable, u.cargo AS cargo_responsable,
        x.id_responsable_etapa, CONCAT(ue.nombre, ' ', ue.apellido) AS responsable_etapa,
        x.id_requerimiento, x.numero_rq,
        x.id_propuesta, x.numero_propuesta, x.version_propuesta, x.estado_propuesta, x.tipo_servicio,
        x.total_propuesta AS monto_total, x.id_moneda, mo.String1 AS moneda, mo.String2 AS simbolo_moneda,
        x.fecha_creacion, x.fecha_cierre, x.dias_transcurridos,
        x.inicio_etapa, x.sla_horas, x.fecha_limite, x.sla_estado, x.sla_minutos_restantes,
        v_documentos AS documentos_totales, x.bloqueos AS bloqueos_activos, x.excepciones AS excepciones_activas,
        x.motivo_bloqueo, x.listo AS listo_para_avanzar,
        -- Próximo hito: la etapa siguiente y lo que falta para llegar a ella
        sig.String2 AS siguiente_etapa, sig.String1 AS siguiente_etapa_nombre,
        CASE x.etapa
            WHEN 'requerimiento'  THEN 'Elaborar la propuesta'
            WHEN 'propuesta'      THEN 'Enviar la propuesta a visto bueno'
            WHEN 'visto_bueno'    THEN 'Obtener el visto bueno'
            WHEN 'seguimiento'    THEN IF(x.estado_propuesta = 'aprobado', 'Enviar la propuesta al cliente', 'Obtener la aceptación del cliente')
            WHEN 'orden_compra'   THEN IF(x.cantidad_oc > 0, 'Validar la OC', 'Registrar la OC del cliente')
            WHEN 'orden_servicio' THEN IF(x.cantidad_os > 0, 'Confirmar la programación con el cliente', 'Generar la orden de servicio')
            WHEN 'programacion'   THEN 'Asignar el personal y los recursos'
            WHEN 'ssoma'          THEN 'Habilitar al personal en SSOMA'
            WHEN 'ejecucion'      THEN 'Finalizar la ejecución en campo'
            WHEN 'cierre'         THEN 'Registrar la conformidad del cliente'
            ELSE NULL
        END AS proximo_paso,
        -- Contadores de los tabs
        v_versiones AS cantidad_propuestas, v_ocs AS cantidad_oc, v_vbs AS cantidad_vb,
        x.cantidad_os,
        -- Permisos: el expediente es de consulta; solo se reasigna en etapa comercial
        (FN_PermisoAccion(p_id_usuario, 'expediente_reasignar') = 1 AND x.etapa_comercial = 1 AND x.etapa <> 'cerrado') AS puede_reasignar,
        1 AS puede_exportar
    FROM tmp_exp x
    LEFT JOIN cliente c        ON c.id_cliente = x.id_cliente
    LEFT JOIN tabla_maestra ar ON ar.IdMaestro = 64 AND ar.IdEmpresa = 1 AND ar.Num1 = x.id_area_rq
    LEFT JOIN tabla_maestra a  ON a.IdMaestro = 79 AND a.IdEmpresa = 1 AND a.String2 = x.area
    LEFT JOIN tabla_maestra mo ON mo.IdMaestro = 1 AND mo.IdEmpresa = 1 AND mo.Num1 = x.id_moneda
    LEFT JOIN tabla_maestra sig ON sig.IdMaestro = 97 AND sig.IdEmpresa = 1 AND sig.eliminado_en IS NULL
                               AND sig.Num1 = x.orden_etapa + 1 AND x.etapa NOT IN ('cierre', 'cerrado')
    LEFT JOIN usuario u        ON u.id_usuario = x.id_responsable
    LEFT JOIN usuario ue       ON ue.id_usuario = x.id_responsable_etapa;

    -- 3. Stepper (10 etapas)
    SELECT orden, etapa, nombre, estado, area, area_nombre, inicio, fin, id_responsable, responsable,
           sla_horas, horas_reales, cumple_sla
    FROM tmp_exp_etp ORDER BY orden;

    -- 4. Responsables actuales
    SELECT r.rol, r.orden, r.id_usuario, CONCAT(u.nombre, ' ', u.apellido) AS nombre, u.cargo
    FROM (
        SELECT 'comercial' AS rol, 1 AS orden, v_resp_com AS id_usuario UNION ALL
        SELECT 'operaciones', 2, v_resp_ope UNION ALL
        SELECT 'ssoma',       3, v_resp_sso UNION ALL
        SELECT 'tecnico',     4, v_resp_tec
    ) r
    LEFT JOIN usuario u ON u.id_usuario = r.id_usuario
    ORDER BY r.orden;

    -- 5. Árbol de entidades
    SELECT e.clave, e.clave_padre, e.nivel, e.entidad_tipo, e.id_entidad, e.codigo, e.version, e.estado,
           e.monto, e.id_moneda, mo.String2 AS simbolo_moneda, e.id_responsable,
           CONCAT(u.nombre, ' ', u.apellido) AS responsable, e.fecha, e.fecha_envio, e.fecha_cierre, e.detalle,
           e.activa, e.es_activa_exp
    FROM tmp_exp_ent e
    LEFT JOIN usuario u        ON u.id_usuario = e.id_responsable
    LEFT JOIN tabla_maestra mo ON mo.IdMaestro = 1 AND mo.IdEmpresa = 1 AND mo.Num1 = e.id_moneda
    ORDER BY e.nivel, e.orden, e.id_entidad DESC;

    -- 6. Alertas y bloqueos activos
    SELECT b.clave, b.clase, b.tipo, b.tipo_nombre, b.etapa, et.String1 AS etapa_nombre, b.entidad_tipo, b.id_entidad,
           b.entidad, b.motivo, b.impacto, b.critico, b.fecha, b.origen, b.id_usuario,
           IFNULL(CONCAT(u.nombre, ' ', u.apellido), 'Sistema') AS usuario
    FROM tmp_exp_blq b
    LEFT JOIN usuario u        ON u.id_usuario = b.id_usuario
    LEFT JOIN tabla_maestra et ON et.IdMaestro = 97 AND et.IdEmpresa = 1 AND et.String2 = b.etapa
    WHERE b.activo = 1
    UNION ALL
    SELECT CONCAT('sla-', x.etapa), 'alerta', 'sla', IF(x.sla_estado = 'vencido', 'SLA de etapa vencido', 'SLA de etapa próximo a vencer'),
           x.etapa, x.etapa_nombre, 'expediente', x.id_expediente, x.numero,
           IF(x.sla_estado = 'vencido',
              CONCAT('Vencido hace ', FLOOR(ABS(x.sla_minutos_restantes) / 60), ' h ', MOD(ABS(x.sla_minutos_restantes), 60), ' min.'),
              CONCAT('Quedan ', FLOOR(x.sla_minutos_restantes / 60), ' h ', MOD(x.sla_minutos_restantes, 60), ' min.')),
           CONCAT('SLA de la etapa: ', x.sla_horas, ' h.'), (x.sla_estado = 'vencido'), x.fecha_limite, 'SLA', NULL, 'Sistema'
    FROM tmp_exp x
    WHERE x.sla_estado IN ('en_riesgo', 'vencido') AND x.etapa <> 'cerrado'
    ORDER BY (clase = 'bloqueo') DESC, (clase = 'excepcion') DESC, critico DESC, fecha;

    -- 7. Actividad reciente
    SELECT ev.fecha, ev.tipo_evento, ev.titulo, ev.descripcion, ev.etapa, et.String1 AS etapa_nombre, ev.id_usuario,
           IFNULL(CONCAT(u.nombre, ' ', u.apellido), 'Sistema') AS usuario, u.cargo AS cargo_usuario,
           ev.entidad, ev.referencia, ev.urgente, ev.origen
    FROM tmp_exp_evt ev
    LEFT JOIN usuario u        ON u.id_usuario = ev.id_usuario
    LEFT JOIN tabla_maestra et ON et.IdMaestro = 97 AND et.IdEmpresa = 1 AND et.String2 = ev.etapa
    ORDER BY ev.fecha DESC
    LIMIT 5;

    DROP TEMPORARY TABLE IF EXISTS tmp_exp_evt;
    DROP TEMPORARY TABLE IF EXISTS tmp_exp_ent;
    DROP TEMPORARY TABLE IF EXISTS tmp_exp_etp;
    DROP TEMPORARY TABLE IF EXISTS tmp_exp_blq;
    DROP TEMPORARY TABLE IF EXISTS tmp_exp;
END$$

DELIMITER ;
