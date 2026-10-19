-- HU-30 Detalle extendido del expediente.
-- Acción expediente_bandeja.
-- Resultados: 1 mensaje · 2 resumen (cabecera, estado actual, control, información técnica y permisos)
--   · 3 etapas (indicador de progreso) · 4 bloqueos y excepciones abiertos · 5 validaciones de la etapa
--   (documentos críticos y próxima acción) · 6 actividad reciente (últimos 5 eventos)
DROP PROCEDURE IF EXISTS SP_ObtenerDetalleExpediente;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerDetalleExpediente(
    IN p_id_usuario    BIGINT,
    IN p_id_expediente BIGINT
)
proc: BEGIN
    DECLARE v_existe   INT DEFAULT 0;
    DECLARE v_faltan   INT DEFAULT 0;
    DECLARE v_proxima  VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

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

    CALL SP_EvaluarAvanceExpediente();
    CALL SP_CargarEtapasExpediente();
    CALL SP_CargarEventosExpediente(p_id_usuario, p_id_expediente);

    SELECT COUNT(*) INTO v_faltan FROM tmp_exp_check WHERE es_documento = 1 AND cumple = 0;
    SELECT accion_sugerida INTO v_proxima FROM tmp_exp_check WHERE cumple = 0 AND critico = 1
    ORDER BY (codigo = 'sin_bloqueos') DESC, orden LIMIT 1;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Resumen
    SELECT
        x.id_expediente, x.numero, x.estado, x.etapa, x.etapa_nombre, x.progreso,
        x.id_cliente, c.razon_social, c.ruc,
        x.id_requerimiento, x.numero_rq, x.descripcion_rq,
        x.id_propuesta, IF(x.id_propuesta IS NULL, NULL, CONCAT(x.numero_propuesta, ' v', x.version_propuesta)) AS propuesta,
        x.numeros_oc, x.numeros_os, x.numeros_om, x.tipo_servicio, x.equipos,
        sc.nombre                                   AS ubicacion,
        x.area, a.String1                           AS area_nombre,
        x.id_responsable, CONCAT(u.nombre, ' ', u.apellido) AS responsable,
        pr.String1                                  AS prioridad,
        x.bloqueos, x.excepciones, x.motivo_bloqueo,
        x.inicio_etapa, x.sla_horas, x.fecha_limite, x.sla_estado, x.sla_minutos_restantes,
        v_faltan                                    AS documentos_faltantes,
        IF(x.etapa = 'cerrado', NULL, v_proxima)    AS proxima_accion,
        x.etapa_manual,
        x.fecha_creacion, x.fecha_cierre,
        FN_PermisoAccion(p_id_usuario, 'expediente_documento_adjuntar')                        AS puede_adjuntar,
        FN_PermisoAccion(p_id_usuario, 'expediente_resolver_bloqueo')                          AS puede_resolver,
        FN_PermisoAccion(p_id_usuario, 'expediente_reasignar')                                 AS puede_reasignar,
        (FN_PermisoAccion(p_id_usuario, 'expediente_avanzar') = 1 AND x.etapa_manual = 1)      AS puede_avanzar
    FROM tmp_exp x
    LEFT JOIN cliente c        ON c.id_cliente = x.id_cliente
    LEFT JOIN sede_cliente sc  ON sc.id_sede = x.id_sede
    LEFT JOIN tabla_maestra a  ON a.IdMaestro = 79 AND a.IdEmpresa = 1 AND a.String2 = x.area
    LEFT JOIN usuario u        ON u.id_usuario = x.id_responsable
    LEFT JOIN tabla_maestra pr ON pr.IdMaestro = 65 AND pr.IdEmpresa = 1 AND pr.Num1 = x.id_prioridad;

    -- 3. Etapas
    SELECT orden, etapa, nombre, estado, inicio, fin, responsable
    FROM tmp_exp_etp ORDER BY orden;

    -- 4. Bloqueos y excepciones abiertos
    SELECT b.id_bloqueador, b.clase, b.descripcion, b.tipo, b.etapa, b.tipo_documental, b.impacto, b.critico,
           b.origen_tipo, b.id_origen,
           b.id_responsable, CONCAT(u.nombre, ' ', u.apellido) AS responsable,
           b.creado_en AS fecha_registro, TIMESTAMPDIFF(MINUTE, b.creado_en, NOW()) AS minutos_desde
    FROM expediente_bloqueador b
    LEFT JOIN usuario u ON u.id_usuario = b.id_responsable
    WHERE b.id_expediente = p_id_expediente AND b.resuelto = 0 AND b.eliminado_en IS NULL
    ORDER BY (b.clase = 'bloqueo') DESC, b.critico DESC, b.id_bloqueador;

    -- 5. Validaciones de la etapa actual
    SELECT orden, codigo, descripcion, cumple, critico, es_documento, detalle, accion_sugerida
    FROM tmp_exp_check ORDER BY orden;

    -- 6. Actividad reciente
    SELECT ev.fecha, ev.tipo_evento, ev.titulo, ev.descripcion, ev.etapa, ev.id_usuario,
           IFNULL(CONCAT(u.nombre, ' ', u.apellido), 'Sistema') AS usuario, ev.referencia, ev.urgente
    FROM tmp_exp_evt ev
    LEFT JOIN usuario u ON u.id_usuario = ev.id_usuario
    ORDER BY ev.fecha DESC
    LIMIT 5;

    DROP TEMPORARY TABLE IF EXISTS tmp_exp_evt;
    DROP TEMPORARY TABLE IF EXISTS tmp_exp_etp;
    DROP TEMPORARY TABLE IF EXISTS tmp_exp_check;
    DROP TEMPORARY TABLE IF EXISTS tmp_exp;
END$$

DELIMITER ;
