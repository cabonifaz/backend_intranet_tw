-- HU-54 (Sprint 5) Vista de Cierre del Servicio (OBSERVACIONAL): resumen del cierre automático. Solo si el servicio está FINALIZADO. SOLO LECTURA.
-- El cierre lo hace el sistema (técnico marca "Finalicé" en la app, o el Asistente con el cambio manual crítico de la HU-53); aquí no se decide nada.
-- Resultados: 1 mensaje · 2 cabecera del cierre (1 fila) · 3 equipos del servicio · 4 acta de conformidad (0 o 1 fila) · 5 pie (expediente, documentos, auditoría)
--             · 6 órdenes de metrología / certificados del servicio.
-- Resultado del cierre (por la ejecución de los equipos): completado = todos ejecutados · parcial = algunos · cancelado = ninguno (servicio abortado).
-- Estado del equipo AL CIERRE (refleja el estado actual, también las decisiones posteriores del Jefe de Operaciones):
--   finalizado (ejecutado) · reprogramado (tiene otra programación/OS del mismo expediente) · anulado (el Jefe lo retiró del servicio tras el cierre)
--   · parcial (en proceso, observado o con etapa iniciada) · pendiente (sin ejecutar: espera decisión del Jefe de Operaciones).
-- Modo auditoría post-cierre: la cabecera trae ModoAuditoria, RegistrarHabilitado=0 y el tooltip del tab Registrar (HU-53 rechaza registros en servicios finalizados).
-- Requiere las migraciones 90 a 92.
DROP PROCEDURE IF EXISTS SP_ObtenerCierreServicioRuta;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerCierreServicioRuta(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT
)
proc: BEGIN
    DECLARE v_msg      VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_ini_utc  DATETIME;
    DECLARE v_hoy      DATE;
    DECLARE v_ahora    DATETIME;
    DECLARE v_prox     INT;
    DECLARE v_fin      DATETIME;
    DECLARE v_ini      DATETIME;
    DECLARE v_est_min  INT;
    DECLARE v_dur      INT;
    DECLARE v_tec      BIGINT;
    DECLARE v_tec_nom  VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tec_ini  VARCHAR(4) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_lat_s    DECIMAL(10,7);
    DECLARE v_lon_s    DECIMAL(10,7);
    DECLARE v_sede     VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_exp      BIGINT;
    DECLARE v_total    INT DEFAULT 0;
    DECLARE v_ejec     INT DEFAULT 0;
    DECLARE v_inc      INT DEFAULT 0;
    DECLARE v_asist_id BIGINT;
    DECLARE v_asist_nom VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cierre_usr BIGINT;
    DECLARE v_resultado VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_subtitulo VARCHAR(400) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_parc     INT DEFAULT 0;
    DECLARE v_pend     INT DEFAULT 0;
    DECLARE v_repro    INT DEFAULT 0;
    DECLARE v_anul     INT DEFAULT 0;
    DECLARE v_hora_fin VARCHAR(5) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_ci_eq;
        CALL SP_LimpiarSeguimientoOperativo();
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    CALL SP_PrepararDetalleServicioRuta(p_id_usuario, p_id_os, v_msg);
    IF v_msg IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje;
        LEAVE proc;
    END IF;
    SELECT hoy, ahora, ini_utc, prox INTO v_hoy, v_ahora, v_ini_utc, v_prox FROM tmp_sg_cfg LIMIT 1;
    SELECT estado_seg, fin_dt,
           COALESCE(CONVERT_TZ(salida_utc, '+00:00', '-05:00'), inicio_dt, llegada_dt, IF(hora_inicio IS NULL, NULL, TIMESTAMP(v_hoy, hora_inicio))),
           IF(hora_inicio IS NOT NULL AND hora_fin_est IS NOT NULL AND hora_fin_est > hora_inicio, TIMESTAMPDIFF(MINUTE, TIMESTAMP(v_hoy, hora_inicio), TIMESTAMP(v_hoy, hora_fin_est)), NULL),
           id_tecnico, tecnico, UPPER(CONCAT(LEFT(nombre_pila, 1), LEFT(SUBSTRING_INDEX(tecnico, ' ', -1), 1))), lat_sede, lon_sede, sede_nombre
      INTO v_estado, v_fin, v_ini, v_est_min, v_tec, v_tec_nom, v_tec_ini, v_lat_s, v_lon_s, v_sede
      FROM tmp_sg_os WHERE id_os = p_id_os;
    SELECT COUNT(*) INTO v_inc FROM tmp_sg_inc WHERE id_os = p_id_os;
    CALL SP_LimpiarSeguimientoOperativo();
    IF v_estado <> 'finalizado' THEN
        SELECT 1 AS IdTipoMensaje, 'El cierre del servicio solo está disponible cuando el servicio finalizó.' AS Mensaje;
        LEAVE proc;
    END IF;
    SELECT id_expediente INTO v_exp FROM orden_servicio WHERE id_os = p_id_os;

    -- ── Equipos al cierre ────────────────────────────────────────────────────────────────
    DROP TEMPORARY TABLE IF EXISTS tmp_ci_eq;
    CREATE TEMPORARY TABLE tmp_ci_eq (
        id_equipo BIGINT NOT NULL, orden INT, nombre VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, serie VARCHAR(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        tipo VARCHAR(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, ejecutado TINYINT, estado VARCHAR(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        hora VARCHAR(5) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, informe VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        url_informe VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, con_obs TINYINT, vinculo VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        PRIMARY KEY (id_equipo)
    );
    INSERT INTO tmp_ci_eq (id_equipo, orden, nombre, serie, tipo, ejecutado, estado, hora, informe, url_informe, con_obs, vinculo)
    SELECT oe.id_equipo, oe.orden, TRIM(CONCAT(e.codigo_tw, IF(e.modelo IS NULL, '', CONCAT(' ', e.modelo)))), e.numero_serie,
           COALESCE(ti.String1, ts.String1),
           IF(oe.estado_ejecucion = 'ejecutado', 1, 0),
           CASE WHEN oe.estado_ejecucion = 'ejecutado' THEN 'finalizado'
                WHEN nv.numero IS NOT NULL THEN 'reprogramado'
                WHEN oe.eliminado_en IS NOT NULL THEN 'anulado'
                WHEN oe.estado_ejecucion IN ('en_proceso', 'observado')
                     OR EXISTS (SELECT 1 FROM os_equipo_etapa et WHERE et.id_os = oe.id_os AND et.id_equipo = oe.id_equipo AND et.inicio_utc IS NOT NULL AND et.eliminado_en IS NULL) THEN 'parcial'
                ELSE 'pendiente' END,
           IF(oe.estado_ejecucion = 'ejecutado' AND oe.fecha_ejecucion IS NOT NULL, DATE_FORMAT(CONVERT_TZ(oe.fecha_ejecucion, '+00:00', '-05:00'), '%H:%i'), NULL),
           inf.numero,
           IF(inf.url_pdf REGEXP '^(https://[^[:space:][:cntrl:]<>"\\\\]+|/[^/[:space:][:cntrl:]<>"\\\\][^[:space:][:cntrl:]<>"\\\\]*)$', inf.url_pdf, NULL),
           IF(oe.estado_ejecucion = 'observado' OR IFNULL(oe.observacion_ejecucion, '') <> ''
              OR EXISTS (SELECT 1 FROM os_equipo_observacion ob WHERE ob.id_os = oe.id_os AND ob.id_equipo = oe.id_equipo AND ob.eliminado_en IS NULL)
              OR IFNULL(inf.estado, '') = 'observado', 1, 0),
           nv.numero
    FROM os_equipo oe
    JOIN equipo e ON e.id_equipo = oe.id_equipo
    JOIN orden_servicio osr ON osr.id_os = oe.id_os
    LEFT JOIN tabla_maestra ti ON ti.IdMaestro = 31 AND ti.IdEmpresa = 1 AND ti.Num1 = oe.id_tipo_intervencion
    LEFT JOIN tabla_maestra ts ON ts.IdEmpresa = 1 AND ts.Descripcion = 'TIPO_SERVICIO' AND ts.Num1 = osr.id_tipo_servicio
    LEFT JOIN informe_tecnico inf ON inf.id_informe = (SELECT i2.id_informe FROM informe_tecnico i2 WHERE i2.id_os = oe.id_os AND i2.id_equipo = oe.id_equipo
                                                       AND i2.eliminado_en IS NULL ORDER BY i2.version DESC, i2.id_informe DESC LIMIT 1)
    LEFT JOIN (SELECT pe.id_equipo, MIN(os2.numero) AS numero
               FROM programacion_equipo pe
               JOIN programacion p2 ON p2.id_programacion = pe.id_programacion AND p2.estado <> 'cancelada' AND p2.id_os <> p_id_os AND p2.fecha_ejecucion >= v_hoy
               JOIN orden_servicio os2 ON os2.id_os = p2.id_os AND os2.estado <> 'anulada' AND v_exp IS NOT NULL AND os2.id_expediente = v_exp
               WHERE pe.eliminado_en IS NULL GROUP BY pe.id_equipo) nv ON nv.id_equipo = oe.id_equipo
    WHERE oe.id_os = p_id_os AND (oe.eliminado_en IS NULL OR (oe.estado_ejecucion <> 'ejecutado' AND oe.eliminado_en >= v_ini_utc));

    SELECT COUNT(*), IFNULL(SUM(ejecutado), 0), IFNULL(SUM(estado = 'parcial'), 0), IFNULL(SUM(estado = 'pendiente'), 0), IFNULL(SUM(estado = 'reprogramado'), 0), IFNULL(SUM(estado = 'anulado'), 0)
      INTO v_total, v_ejec, v_parc, v_pend, v_repro, v_anul FROM tmp_ci_eq;
    SET v_resultado = CASE WHEN v_total = 0 OR v_ejec = v_total THEN 'completado' WHEN v_ejec = 0 THEN 'cancelado' ELSE 'parcial' END;
    SET v_dur = IF(v_ini IS NULL OR v_fin IS NULL, NULL, GREATEST(0, TIMESTAMPDIFF(MINUTE, v_ini, v_fin)));
    SET v_hora_fin = DATE_FORMAT(v_fin, '%H:%i');

    -- Quién cerró: el Asistente (cambio manual crítico de la HU-53) o el técnico desde su app
    SELECT r.id_usuario INTO v_asist_id FROM registro_asistente r WHERE r.id_os = p_id_os AND r.modo = 'cambio_estado' AND r.estado_nuevo = 'finalizado'
     ORDER BY r.id_registro DESC LIMIT 1;
    IF v_asist_id IS NOT NULL THEN
        SELECT TRIM(CONCAT(nombre, ' ', apellido)) INTO v_asist_nom FROM usuario WHERE id_usuario = v_asist_id;
        SET v_subtitulo = CONCAT('El Asistente ', IFNULL(v_asist_nom, ''), ' marcó el servicio como finalizado a las ', IFNULL(v_hora_fin, '--:--'),
                                 ' desde la intranet (cambio manual crítico). El sistema cerró automáticamente el seguimiento operativo.');
    ELSE
        SELECT e.id_usuario INTO v_cierre_usr FROM evento_campo e JOIN tabla_maestra m ON m.Descripcion = 'TIPO_EVENTO_CAMPO' AND m.IdEmpresa = 1 AND m.Num1 = e.id_tipo_evento
         WHERE e.id_os = p_id_os AND e.eliminado_en IS NULL AND m.String2 = 'CIERRE' ORDER BY e.timestamp_utc DESC, e.id_evento DESC LIMIT 1;
        IF v_cierre_usr IS NOT NULL AND v_cierre_usr <> IFNULL(v_tec, 0) THEN
            SELECT TRIM(CONCAT(nombre, ' ', apellido)), UPPER(CONCAT(LEFT(nombre, 1), LEFT(apellido, 1))), id_usuario INTO v_tec_nom, v_tec_ini, v_tec FROM usuario WHERE id_usuario = v_cierre_usr;
        END IF;
        SET v_subtitulo = CONCAT('El técnico marcó "Finalicé el servicio" a las ', IFNULL(v_hora_fin, '--:--'),
                                 ' desde su app móvil. El sistema cerró automáticamente el seguimiento operativo.');
    END IF;

    SELECT 2 AS IdTipoMensaje, 'OK' AS Mensaje;
    -- 2 · cabecera del cierre
    SELECT v_resultado AS Resultado,
           CASE v_resultado WHEN 'completado' THEN 'COMPLETADO' WHEN 'parcial' THEN 'COMPLETADO PARCIAL' ELSE 'CANCELADO' END AS ResultadoTexto,
           v_hora_fin AS FinalizadoHora, v_dur AS DuracionMin, v_est_min AS MinutosEstimados,
           IF(v_dur IS NULL OR v_est_min IS NULL, NULL, v_dur - v_est_min) AS DiferenciaMin,
           v_tec AS IdTecnico, v_tec_nom AS Tecnico, v_tec_ini AS Iniciales, IF(v_asist_id IS NULL, 'Líder', 'Asistente') AS Rol,
           IF(v_asist_id IS NULL, 'tecnico', 'asistente') AS CerradoPor, v_subtitulo AS Subtitulo,
           v_ejec AS EquiposFinalizados, v_total AS EquiposTotal,
           (SELECT COUNT(*) FROM informe_tecnico i WHERE i.id_os = p_id_os AND i.eliminado_en IS NULL) AS Informes,
           v_inc AS DemorasIncidencias,
           (SELECT COUNT(*) FROM registro_asistente r WHERE r.id_os = p_id_os) AS RegistrosAsistente,
           v_parc AS EquiposParciales,
           v_pend AS EquiposPendientes,
           v_repro AS EquiposReprogramados,
           v_anul AS EquiposAnulados,
           'FINALIZADO' AS EstadoCabecera, 1 AS ModoAuditoria, 0 AS RegistrarHabilitado,
           'Servicio finalizado — Para registrar observaciones post-cierre, pedir reapertura al Jefe de Operaciones.' AS TooltipRegistrar,
           'Modo auditoría post-servicio · Solo lectura' AS ChipModo,
           CONCAT('Última actualización ', DATE_FORMAT(v_ahora, '%H:%i'), ' · Servicio cerrado automáticamente por el sistema') AS TextoActualizacion;
    -- 3 · equipos
    SELECT id_equipo AS IdEquipo, nombre AS Nombre, serie AS Serie, tipo AS TipoServicio, estado AS Estado,
           CASE estado WHEN 'finalizado' THEN 'Finalizado' WHEN 'parcial' THEN 'Parcial' WHEN 'pendiente' THEN 'Pendiente'
                       WHEN 'reprogramado' THEN 'Reprogramado' ELSE 'Anulado' END AS EstadoTexto,
           hora AS Hora, informe AS Informe, url_informe AS UrlInforme, con_obs AS ConObservaciones,
           CASE estado WHEN 'pendiente' THEN 'Esperando decisión J.Ops' WHEN 'parcial' THEN 'Avance sin informe final · Esperando decisión J.Ops'
                       WHEN 'reprogramado' THEN CONCAT('Reprogramado en ', vinculo) WHEN 'anulado' THEN 'Anulado por el Jefe de Operaciones' ELSE NULL END AS Info,
           vinculo AS Vinculo, IF(estado IN ('pendiente', 'parcial'), 1, 0) AS Destacado
    FROM tmp_ci_eq ORDER BY orden, id_equipo;
    -- 4 · acta de conformidad del cliente
    SELECT DATE_FORMAT(CONVERT_TZ(cd.registrado_en, '+00:00', '-05:00'), '%H:%i') AS Hora, cd.estado AS Estado,
           IF(cd.estado = 'pendiente', 'Pendiente de firma', CONCAT('Firmada ', DATE_FORMAT(CONVERT_TZ(cd.registrado_en, '+00:00', '-05:00'), '%H:%i'))) AS Chip,
           cc.nombres AS Firmante, cc.cargo AS Cargo,
           CASE cd.tipo WHEN 'presencial' THEN 'Firma digital en app del técnico' WHEN 'digital_extranet' THEN 'Firma digital en la extranet del cliente' ELSE 'Aceptación táctica' END AS Metodo,
           cd.tipo AS Tipo,
           IF(cd.latitud IS NULL OR cd.longitud IS NULL OR v_lat_s IS NULL OR v_lon_s IS NULL, 0,
              IF(6371000 * 2 * ASIN(SQRT(POW(SIN(RADIANS(v_lat_s - cd.latitud) / 2), 2) + COS(RADIANS(cd.latitud)) * COS(RADIANS(v_lat_s)) * POW(SIN(RADIANS(v_lon_s - cd.longitud) / 2), 2))) <= v_prox, 1, 0)) AS GpsVerificado,
           IF(cd.latitud IS NULL OR cd.longitud IS NULL, 'Sin ubicación registrada',
              CONCAT(IFNULL(v_sede, 'Planta'), IF(v_lat_s IS NULL OR v_lon_s IS NULL, '', IF(6371000 * 2 * ASIN(SQRT(POW(SIN(RADIANS(v_lat_s - cd.latitud) / 2), 2) + COS(RADIANS(cd.latitud)) * COS(RADIANS(v_lat_s)) * POW(SIN(RADIANS(v_lon_s - cd.longitud) / 2), 2))) <= v_prox, ' - verificado', ' - fuera del radio del cliente')))) AS Gps,
           IF(cd.url_firma_imagen REGEXP '^(https://[^[:space:][:cntrl:]<>"\\\\]+|/[^/[:space:][:cntrl:]<>"\\\\][^[:space:][:cntrl:]<>"\\\\]*)$', cd.url_firma_imagen, NULL) AS UrlFirma,
           cd.observaciones AS Observaciones,
           'Flujo de captura por definir con el cliente: por ahora se asume firma digital en la app del técnico.' AS Nota
    FROM conformidad_digital cd
    JOIN informe_tecnico it ON it.id_informe = cd.id_informe AND it.id_os = p_id_os AND it.eliminado_en IS NULL
    LEFT JOIN contacto_cliente cc ON cc.id_contacto = cd.id_contacto_cliente
    WHERE cd.eliminado_en IS NULL
    ORDER BY cd.registrado_en DESC, cd.id_conformidad DESC LIMIT 1;
    -- 5 · pie: accesos a Documentos del Expediente y Auditoría del servicio
    SELECT v_exp AS IdExpediente, (SELECT numero FROM expediente_digital WHERE id_expediente = v_exp) AS Expediente,
           IF(v_exp IS NULL, 0, (SELECT COUNT(*) FROM documento_adjunto d WHERE d.eliminado_en IS NULL AND d.entidad_tipo = 'expediente' AND d.id_entidad = v_exp)) AS Documentos,
           (SELECT COUNT(*) FROM auditoria_evento a WHERE a.entidad_tipo = 'orden_servicio' AND a.id_entidad = p_id_os) AS EventosAuditoria;
    -- 6 · órdenes de metrología / certificados
    SELECT om.numero AS Numero, om.estado AS Estado, om.numero_certificado AS Certificado, DATE_FORMAT(om.fecha_emision_certificado, '%Y-%m-%d') AS FechaEmision
    FROM orden_metrologia om WHERE om.id_os = p_id_os AND om.eliminado_en IS NULL ORDER BY om.id_om;

    DROP TEMPORARY TABLE IF EXISTS tmp_ci_eq;
END$$

DELIMITER ;
