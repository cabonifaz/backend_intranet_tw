-- ============================================================
-- SP_GenerarAlertasOperativas  (HU-90 Centro de Notificaciones — alertas del Módulo 11 Control de Campo)
-- Lo ejecuta el worker de la API (AlertasOperativasWorker) cada minuto. Proceso del sistema: no valida permisos de quien llama.
-- Las alertas automáticas del Módulo 11 solo se calculaban al abrir la bandeja de seguimiento; este SP las guarda como notificación
-- para que lleguen a la campana. Usa EXACTAMENTE el mismo cálculo y los mismos umbrales (SP_ArmarSeguimientoOperativo, migración 90):
--   perdida_contacto (crítica) · gps_parado (advertencia) · sin_movimiento (CRÍTICA, HU-20: avisa a los 10 min y se repite cada 5 min hasta que el técnico se mueve o inicia el trabajo) · sin_ingreso_post_llegada (advertencia) · sin_iniciar_servicio (advertencia)
--   · proximidad (info) · incidente crítico (crítica)
-- Destinatarios: usuarios activos con el permiso seg_bandeja (los que ven la bandeja de seguimiento).
-- Sin duplicados: clave_alerta = clave de la alerta + fecha de Lima → una sola notificación por alerta, técnico, servicio y día.
-- Excepción «sin_movimiento»: la clave lleva además el tramo de 5 minutos (minutos / 5) → una notificación nueva cada 5 min mientras siga parado.
-- Varias instancias de la API: GET_LOCK evita que dos corran a la vez (la otra sale sin hacer nada).
-- Se guarda con modulo_origen = control_campo, tipo_origen = alerta_operativa y la prioridad según la severidad.
-- Resultados: 1 mensaje · 2 generadas (notificaciones insertadas) y alertas (alertas activas en este momento).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_GenerarAlertasOperativas;

DELIMITER $$

CREATE PROCEDURE SP_GenerarAlertasOperativas()
proc: BEGIN
    DECLARE v_lock       INT DEFAULT 0;
    DECLARE v_hoy        DATE;
    DECLARE v_prox       INT DEFAULT 300;
    DECLARE v_generadas  INT DEFAULT 0;
    DECLARE v_alertas    INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_alerta_dest;
        CALL SP_LimpiarSeguimientoOperativo();
        DO RELEASE_LOCK('tw_alertas_operativas');
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SET v_lock = GET_LOCK('tw_alertas_operativas', 0);
    IF IFNULL(v_lock, 0) <> 1 THEN
        SELECT 2 AS IdTipoMensaje, 'Otra instancia está generando las alertas operativas.' AS Mensaje;
        SELECT 0 AS generadas, 0 AS alertas;
        LEAVE proc;
    END IF;

    CALL SP_ArmarSeguimientoOperativo();

    SELECT hoy, prox INTO v_hoy, v_prox FROM tmp_sg_cfg LIMIT 1;
    SELECT COUNT(*) INTO v_alertas FROM tmp_sg_alerta;

    IF v_alertas > 0 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_alerta_dest;
        -- area_limite NULL = ve las alertas de TODAS las áreas; 'servicio_tecnico' | 'metrologia' = solo las de su área.
        -- Regla Área + Rol (2026-11-18, la misma de SP_ResolverJefaturaMovil): Gerencia, Operaciones, Administración, TI, SSOMA, Calidad, Comercial (cualquier rol) y
        -- Administradores ven todo; Supervisor de Servicio Técnico / Metrología, solo su área; Usuario / Visor de ST / Metrología no reciben alertas de jefatura.
        CREATE TEMPORARY TABLE tmp_alerta_dest (id_usuario BIGINT NOT NULL, area_limite VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL, PRIMARY KEY (id_usuario));

        INSERT INTO tmp_alerta_dest (id_usuario, area_limite)
        SELECT x.id_usuario,
               IF(x.rol_sistema IN ('administrador', 'admin') OR x.area_efectiva NOT IN ('servicio_tecnico', 'metrologia'), NULL, x.area_efectiva)
        FROM (
            SELECT u.id_usuario, u.rol_sistema,
                   IF(u.cargo LIKE 'jefe\_%',
                      COALESCE(NULLIF(u.area, ''), NULLIF(c.String3, ''), SUBSTRING(u.cargo, 6)),
                      NULLIF(u.area, '')) AS area_efectiva
            FROM   usuario u
            LEFT JOIN tabla_maestra c ON c.IdMaestro = 80 AND c.IdEmpresa = 1 AND c.String2 = u.cargo
            WHERE  u.eliminado_en IS NULL AND u.estado = 'activo'
        ) x
        WHERE  x.rol_sistema IN ('administrador', 'admin')
           OR (x.area_efectiva IS NOT NULL AND x.area_efectiva NOT IN ('servicio_tecnico', 'metrologia'))
           OR (x.area_efectiva IN ('servicio_tecnico', 'metrologia') AND x.rol_sistema = 'supervisor');

        INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por,
                                  modulo_origen, tipo_origen, prioridad_origen, clave_alerta)
        SELECT d.id_usuario, 5,
               IF(a.tipo = 'sin_movimiento', LEFT(CONCAT('Técnico sin movimiento — ', IFNULL(a.tecnico, '')), 150), LEFT(CONCAT('Técnico ', IFNULL(a.tecnico, ''), ' — ', a.titulo), 150)),
               LEFT(CONCAT(
                   CASE a.tipo
                       WHEN 'gps_parado'               THEN CONCAT('Sin movimiento registrado en los últimos ', IFNULL(a.minutos, 0), ' min')
                       WHEN 'sin_movimiento'           THEN CONCAT('Sin movimiento desde hace ', IFNULL(a.minutos, 0), ' min con la jornada en curso. Comunícate con el técnico para saber qué sucede')
                       WHEN 'perdida_contacto'         THEN CONCAT('Sin señal GPS desde hace ', IFNULL(a.minutos, 0), ' min')
                       WHEN 'sin_ingreso_post_llegada' THEN CONCAT('Llegó a planta hace ', IFNULL(a.minutos, 0), ' min y aún no inicia el trabajo')
                       WHEN 'sin_iniciar_servicio'     THEN CONCAT('Pasaron ', IFNULL(a.minutos, 0), ' min de la hora de salida programada y no marcó "Salida"')
                       WHEN 'proximidad'               THEN CONCAT('Está a menos de ', v_prox, ' m del cliente')
                       WHEN 'incidente'                THEN CONCAT('Incidente crítico abierto hace ', IFNULL(a.minutos, 0), ' min')
                       ELSE a.titulo END,
                   ' — ', COALESCE(NULLIF(o.sede_nombre, ''), NULLIF(o.razon_social, ''), 'cliente'),
                   IF(NULLIF(o.sede_nombre, '') IS NOT NULL AND NULLIF(o.razon_social, '') IS NOT NULL, CONCAT(' (', o.razon_social, ')'), ''),
                   ' · ', IFNULL(a.numero, ''), '.'), 1000),
               'orden_servicio', a.id_os, NOW(), NULL,
               'control_campo', 'alerta_operativa',
               CASE a.severidad WHEN 'critica' THEN 'critica' WHEN 'advertencia' THEN 'alta' ELSE 'normal' END,
               CONCAT(a.clave, IF(a.tipo = 'sin_movimiento', CONCAT(':r', FLOOR(IFNULL(a.minutos, 0) / 5)), ''), ':', DATE_FORMAT(v_hoy, '%Y%m%d'))
        FROM   tmp_sg_alerta a
        JOIN   tmp_sg_os o ON o.id_os = a.id_os
        CROSS JOIN tmp_alerta_dest d
        WHERE  a.tipo NOT IN ('autorizacion_salida', 'ensayo_critico')   -- sus notificaciones (críticas) ya las crean SP_SolicitarAutorizacionSalidaMovil y SP_GuardarEnsayosMovil
          -- Supervisor de ST / Metrología: solo las alertas de servicios de SU área (si la RQ no indica área, las ve)
          AND  (d.area_limite IS NULL
                OR NOT EXISTS (SELECT 1 FROM orden_servicio os2
                               JOIN expediente_digital ed2 ON ed2.id_expediente    = os2.id_expediente
                               JOIN requerimiento      rq2 ON rq2.id_requerimiento = ed2.id_requerimiento
                               JOIN area_servicio_rq  asr2 ON asr2.id_area_rq      = rq2.id_area
                               WHERE os2.id_os = a.id_os AND asr2.area_usuario IS NOT NULL)
                OR EXISTS (SELECT 1 FROM orden_servicio os3
                           JOIN expediente_digital ed3 ON ed3.id_expediente    = os3.id_expediente
                           JOIN requerimiento      rq3 ON rq3.id_requerimiento = ed3.id_requerimiento
                           JOIN area_servicio_rq  asr3 ON asr3.id_area_rq      = rq3.id_area
                           WHERE os3.id_os = a.id_os AND asr3.area_usuario = d.area_limite))
          AND  NOT EXISTS (SELECT 1 FROM notificacion n
                           WHERE  n.clave_alerta = CONCAT(a.clave, IF(a.tipo = 'sin_movimiento', CONCAT(':r', FLOOR(IFNULL(a.minutos, 0) / 5)), ''), ':', DATE_FORMAT(v_hoy, '%Y%m%d'))
                             AND  n.id_usuario_destino = d.id_usuario);
        SET v_generadas = ROW_COUNT();

        DROP TEMPORARY TABLE IF EXISTS tmp_alerta_dest;
    END IF;

    CALL SP_LimpiarSeguimientoOperativo();
    DO RELEASE_LOCK('tw_alertas_operativas');

    SELECT 2 AS IdTipoMensaje, 'Alertas operativas procesadas.' AS Mensaje;
    SELECT v_generadas AS generadas, v_alertas AS alertas;
END$$

DELIMITER ;
