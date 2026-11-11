-- Aplicar en la base (Panel de Campo HU-29 + Seguimiento del servicio HU-30 de la app móvil del Jefe de Área). Sin migración propia y sin datos de prueba.
-- Ejecutar completo con Alt+X. NO subir al repositorio. Después REINICIAR la API.
-- ORDEN: aplica primero _aplicar_jefatura_menu_movil.sql (HU-28: notificaciones del jefe y sus contadores) y DESPUÉS este script, que vuelve a crear
-- SP_ObtenerMenuJefaturaMovil usando los dos procedimientos de apoyo nuevos (SP_ResolverJefaturaMovil y SP_ArmarAlcanceJefaturaMovil). No vuelvas a ejecutar
-- el script anterior después de este: dejaría el menú con su versión previa (sigue funcionando, pero sin compartir la regla de alcance).
-- Requiere (ya existentes): Seguimiento Operativo HU-51/52/53 (migraciones 90 a 92: SP_ArmarSeguimientoOperativo, SP_FiltrarSeguimientoOperativo,
-- SP_LimpiarSeguimientoOperativo y SP_RegistrarAsistenteServicioRuta), la llegada validada por GPS (migración 97), los ensayos (migración 100) y FN_PermisoAccion.


-- ############################################################
-- SP_ResolverJefaturaMovil
-- ############################################################
-- ============================================================
-- SP_ResolverJefaturaMovil  (App Mobile HU-28 / HU-29 / HU-30 — apoyo, NO es un endpoint)
-- Resuelve UNA sola vez quién es el jefe y de qué área, para el menú de Jefatura y las pantallas del Panel de Campo / Seguimiento del servicio.
--   · cargo "Jefe de …" (CARGO_USUARIO jefe_*): su área sale de su ficha (usuario.area) o, si no la tiene, del catálogo del cargo (String3).
--   · rol SUPERVISOR / ADMINISTRADOR con un área definida: esa área.  Cualquier otro usuario → p_area = NULL (no tiene menú de Jefatura).
--   p_sede           sede operativa del usuario (nombre). p_aut_area / p_aut_general: misma regla de SP_ObtenerAutorizacionesSalida (aprobaciones).
-- Solo lectura. El alcance de los SERVICIOS (área de la RQ) lo arma SP_ArmarAlcanceJefaturaMovil.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ResolverJefaturaMovil;

DELIMITER $$

CREATE PROCEDURE SP_ResolverJefaturaMovil(
    IN  p_id_usuario  BIGINT,
    OUT p_area        VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    OUT p_sede        VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    OUT p_aut_area    VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    OUT p_aut_general TINYINT
)
BEGIN
    SET p_area = NULL;
    SET p_sede = NULL;
    SET p_aut_area = NULL;
    SET p_aut_general = 0;

    SELECT IF(u.cargo LIKE 'jefe\_%',
              COALESCE(NULLIF(u.area, ''), NULLIF(c.String3, ''), SUBSTRING(u.cargo, 6)),
              IF(u.rol_sistema IN ('supervisor', 'administrador') AND IFNULL(u.area, '') <> '', u.area, NULL)),
           s.String1,
           COALESCE(IF(c.String2 LIKE 'jefe\_%' AND c.String3 IN ('servicio_tecnico', 'metrologia'), c.String3, NULL),
                    IF(u.rol_sistema = 'supervisor' AND u.area = 'metrologia', 'metrologia', NULL)),
           IFNULL(u.cargo IN ('jefe_operaciones', 'coordinador_operaciones') OR u.rol_sistema IN ('administrador', 'admin')
                  OR (u.rol_sistema = 'supervisor' AND u.area = 'operaciones'), 0)
    INTO   p_area, p_sede, p_aut_area, p_aut_general
    FROM   usuario u
    LEFT JOIN tabla_maestra c ON c.IdMaestro = 80 AND c.IdEmpresa = 1 AND c.String2 = u.cargo
    LEFT JOIN tabla_maestra s ON s.IdMaestro = 69 AND s.IdEmpresa = 1 AND s.String2 = u.sede_operativa
    WHERE  u.id_usuario = p_id_usuario AND u.eliminado_en IS NULL AND u.estado = 'activo'
    LIMIT 1;
END$$

DELIMITER ;

-- ############################################################
-- SP_ArmarAlcanceJefaturaMovil
-- ############################################################
-- ============================================================
-- SP_ArmarAlcanceJefaturaMovil  (App Mobile HU-28 / HU-29 / HU-30 — apoyo, NO es un endpoint)
-- Arma, UNA sola vez, los servicios (OS) que el jefe puede ver, en la tabla temporal `tmp_jf_alc` (id_os). Quien la llame debe terminar con
-- DROP TEMPORARY TABLE IF EXISTS tmp_jf_alc. Solo lectura.
--   · Servicio Técnico y Metrología: solo los servicios cuya RQ es de su área (orden_servicio → expediente_digital → requerimiento.id_area
--     → area_servicio_rq.area_usuario = área del jefe).
--   · Las demás áreas (Operaciones, TI, Gerencia, Comercial…) no tienen área en la RQ: ven TODOS los servicios.
--   · p_area NULL (no es jefe) → ningún servicio.
--   p_id_os NULL → los servicios de HOY (fecha de Lima, UTC-5);  p_id_os dado → solo ese servicio (si está en el alcance), de cualquier fecha.
-- Lo usan el menú de Jefatura (contadores), el Panel de Campo, la lista de servicios, el detalle, la ruta y el registro del cambio de estado.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ArmarAlcanceJefaturaMovil;

DELIMITER $$

CREATE PROCEDURE SP_ArmarAlcanceJefaturaMovil(
    IN p_area  VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_os BIGINT
)
BEGIN
    DECLARE v_hoy DATE;
    SET v_hoy = DATE(UTC_TIMESTAMP() - INTERVAL 5 HOUR);

    DROP TEMPORARY TABLE IF EXISTS tmp_jf_alc;
    CREATE TEMPORARY TABLE tmp_jf_alc (id_os BIGINT NOT NULL, PRIMARY KEY (id_os));

    INSERT INTO tmp_jf_alc (id_os)
    SELECT os.id_os
    FROM   orden_servicio os
    WHERE  p_area IS NOT NULL
      AND  os.eliminado_en IS NULL
      AND  ((p_id_os IS NULL AND os.fecha_ejecucion = v_hoy) OR os.id_os = p_id_os)
      AND  (p_area NOT IN ('metrologia', 'servicio_tecnico')
            OR EXISTS (SELECT 1
                       FROM   expediente_digital ed
                       JOIN   requerimiento      rq  ON rq.id_requerimiento = ed.id_requerimiento
                       JOIN   area_servicio_rq   asr ON asr.id_area_rq      = rq.id_area
                       WHERE  ed.id_expediente = os.id_expediente AND asr.area_usuario = p_area));
END$$

DELIMITER ;

-- ############################################################
-- SP_FiltrarServiciosJefaturaMovil
-- ############################################################
-- ============================================================
-- SP_FiltrarServiciosJefaturaMovil  (App Mobile HU-29 — apoyo, NO es un endpoint)
-- Deja en `tmp_sg_f` los servicios del día (id_os) que el jefe puede ver (alcance por área) y que cumplen la búsqueda y el filtro.
-- Requiere SP_ArmarSeguimientoOperativo (tmp_sg_*) y SP_ArmarAlcanceJefaturaMovil (tmp_jf_alc). Los parámetros ya vienen validados por quien llama.
--   p_busqueda : N° de OS/OM, cliente, RUC o técnico (la misma búsqueda de la bandeja de seguimiento, SP_FiltrarSeguimientoOperativo).
--   p_filtro   : NULL / '' = todos · activos (no finalizados) · demora (con demora o pausados) · incidencias (incidente crítico o que detiene) · finalizados.
-- Los filtros usan las banderas del servicio (no el estado único de la bandeja) para coincidir con los contadores del menú de Jefatura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_FiltrarServiciosJefaturaMovil;

DELIMITER $$

CREATE PROCEDURE SP_FiltrarServiciosJefaturaMovil(
    IN p_busqueda VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_filtro   VARCHAR(12)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
BEGIN
    CALL SP_FiltrarSeguimientoOperativo(NULL, NULL, NULL, NULL, NULLIF(TRIM(IFNULL(p_busqueda, '')), ''));

    -- Solo los servicios del alcance del jefe
    DELETE f FROM tmp_sg_f f LEFT JOIN tmp_jf_alc a ON a.id_os = f.id_os WHERE a.id_os IS NULL;

    IF NULLIF(p_filtro, '') IS NOT NULL THEN
        DELETE f FROM tmp_sg_f f JOIN tmp_sg_os o ON o.id_os = f.id_os
        WHERE NOT CASE p_filtro
                      WHEN 'activos'      THEN o.fase <> 'finalizado'
                      WHEN 'demora'       THEN o.fase <> 'finalizado' AND (o.n_demoras > 0 OR o.os_estado = 'pausada')
                      WHEN 'incidencias'  THEN o.fase <> 'finalizado' AND o.crit = 1
                      WHEN 'finalizados'  THEN o.fase = 'finalizado'
                      ELSE 1 END;
    END IF;
END$$

DELIMITER ;

-- ############################################################
-- SP_ObtenerMenuJefaturaMovil
-- ############################################################
-- ============================================================
-- SP_ObtenerMenuJefaturaMovil  (App Mobile HU-28 — Menú de Jefatura)
-- Resumen del día para quien tiene el menú de Jefatura en la app. Es UN SOLO menú para todos los jefes de área:
--   · cargo "Jefe de …" (CARGO_USUARIO jefe_*: Servicio Técnico, Metrología, Operaciones…), o
--   · rol SUPERVISOR / ADMINISTRADOR con un área definida (cualquier área, incluida Servicio Técnico).
-- Los técnicos, metrólogos y usuarios comunes reciben un mensaje y la app les muestra el menú de campo.
-- El área del jefe sale de su ficha (usuario.area) o, si no la tiene, del catálogo del cargo (CARGO_USUARIO.String3): SP_ResolverJefaturaMovil.
-- El alcance de los servicios (área de la RQ) lo arma SP_ArmarAlcanceJefaturaMovil; el Panel de Campo y el Seguimiento del servicio (HU-29 / HU-30)
-- usan los mismos dos procedimientos de apoyo.
--   - Servicio Técnico y Metrología: se filtra por el área de la RQ de cada servicio (orden_servicio → expediente_digital →
--     requerimiento.id_area → area_servicio_rq.area_usuario = área del jefe).
--   - Otras áreas (Operaciones, TI, Gerencia, Comercial…): no tienen área en la RQ, así que ven el resumen de TODOS los servicios.
-- Resultados:
--   1. Mensaje
--   2. Una fila: area_codigo (el área del usuario), area_nombre, sede, y los contadores de HOY (fecha de Lima, UTC-5):
--        programados      : servicios programados para hoy (en cualquier estado activo)
--        en_ruta          : de esos, en ruta
--        en_ejecucion     : de esos, en ejecución o pausados (ya están en planta)
--        con_demora       : de esos, con una demora registrada hoy
--        aprobaciones_pendientes : solicitudes de salida que ESTE usuario puede resolver. Misma regla que
--                           SP_ObtenerAutorizacionesSalida / SP_ResolverAutorizacionSalida: encargado del área (Jefe de Servicio
--                           Técnico o Jefe de Metrología, o supervisor de Metrología) → las de su área y las que la RQ no ubica en
--                           un área; supervisión general (Jefe/Coordinador de Operaciones, supervisor de Operaciones, administrador)
--                           → todas; el resto → 0.
--      Contadores de las tarjetas (HU-28, actualización). NULL = sin dato para este usuario (no tiene el permiso, el área no aplica o
--      la fuente no está disponible): la app no pinta contador. Cada uno se calcula en su propio bloque: si una fuente falla (p. ej. falta
--      una migración) solo ese contador queda NULL y el menú sigue funcionando.
--        alertas_criticas     : notificaciones CRÍTICAS sin leer ni archivar de este usuario (notificacion.prioridad = 'critica', la
--                               clasificación del Centro de Notificaciones HU-90, migración 102_centro_notificaciones: error crítico de ensayo,
--                               servicio detenido, alertas críticas de Control de Campo). Es lo mismo que filtra "Críticas" en Notificaciones.
--        informes_por_revisar : informes de servicio técnico enviados por los técnicos y pendientes de revisión (grupos pendiente_revision y
--                               pendiente_precotizacion de SP_ArmarBaseInformes, el MISMO cálculo de la bandeja de Revisión Técnica). Solo con rt_bandeja.
--        certificados_pendientes : órdenes de metrología en estado pendiente_certificado. Solo área Metrología.
--        tickets_correlativo  : tickets de metrología solicitados (ticket_metrologia.estado = 'solicitado'), pendientes de asignar correlativo.
--                               Solo área Metrología.
--        mi_equipo_total / mi_equipo_en_labores : técnicos activos del área (misma regla de técnico que la bandeja de Programación: sin
--                               jefaturas ni asistentes) y, de ellos, los que HOY tienen una orden en ruta, en ejecución o pausada (como técnico
--                               principal o personal de apoyo). Solo Servicio Técnico y Metrología.
--        agenda_conflictos    : conflictos sobrevenidos de la Programación (HU-39, SP_ArmarConflictosProgramacion: el MISMO cálculo de la lista de
--                               conflictos). Solo con prog_bandeja; en Servicio Técnico y Metrología, los de técnicos de su área.
--        viaticos_por_revisar : gastos rendidos por los técnicos pendientes de revisión (gasto_viatico tipo gasto_solicitado, estado pendiente).
--                               Solo con prog_aprobar_reprogramacion (el Jefe de Operaciones, quien revisa los gastos: SP_RevisarGastoProgramacion).
--      Sin fuente todavía (no hay contador): Recepción en Taller (no existe el módulo ni tabla) y Panel de Campo usa en_ruta.
-- Solo lectura. No usa funciones almacenadas propias (solo el FN_PermisoAccion que ya existe).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerMenuJefaturaMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerMenuJefaturaMovil(
    IN p_id_usuario BIGINT
)
proc: BEGIN
    DECLARE v_area VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_sede VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_hoy  DATE;
    DECLARE v_aut_area    VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_aut_general TINYINT DEFAULT 0;
    DECLARE v_alertas      INT DEFAULT NULL;
    DECLARE v_informes     INT DEFAULT NULL;
    DECLARE v_certificados INT DEFAULT NULL;
    DECLARE v_tickets      INT DEFAULT NULL;
    DECLARE v_eq_total     INT DEFAULT NULL;
    DECLARE v_eq_labores   INT DEFAULT NULL;
    DECLARE v_conflictos   INT DEFAULT NULL;
    DECLARE v_gastos       INT DEFAULT NULL;
    DECLARE v_prog         INT DEFAULT 0;
    DECLARE v_ruta         INT DEFAULT 0;
    DECLARE v_ejec         INT DEFAULT 0;
    DECLARE v_dem          INT DEFAULT 0;

    -- Quién es el jefe y de qué área: la regla vive en SP_ResolverJefaturaMovil (la comparten el Panel de Campo y el Seguimiento del servicio)
    CALL SP_ResolverJefaturaMovil(p_id_usuario, v_area, v_sede, v_aut_area, v_aut_general);

    IF v_area IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Tu cargo no tiene el menú de Jefatura.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_hoy = DATE(UTC_TIMESTAMP() - INTERVAL 5 HOUR);

    -- ── Contadores de las tarjetas: cada uno en su bloque; si la fuente falla queda NULL ─────────────────────────────────
    -- Alertas de Campo: críticas sin leer (la misma clasificación que el filtro "Críticas" de Notificaciones)
    BEGIN
        DECLARE EXIT HANDLER FOR SQLEXCEPTION SET v_alertas = NULL;
        SELECT COUNT(*) INTO v_alertas
        FROM   notificacion n
        WHERE  n.id_usuario_destino = p_id_usuario AND n.eliminado_en IS NULL
          AND  n.archivado = 0 AND n.leido = 0 AND n.prioridad = 'critica';
    END;

    -- Informes pendientes de revisión: el cálculo compartido de la bandeja de Revisión Técnica
    BEGIN
        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;
            SET v_informes = NULL;
        END;
        IF FN_PermisoAccion(p_id_usuario, 'rt_bandeja') = 1 THEN
            CALL SP_ArmarBaseInformes(p_id_usuario, NULL);
            SELECT COUNT(*) INTO v_informes FROM tmp_rt_base WHERE grupo_estado IN ('pendiente_revision', 'pendiente_precotizacion');
            DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;
        END IF;
    END;

    -- Metrología: certificados pendientes y tickets de correlativo solicitados
    IF v_area = 'metrologia' THEN
        BEGIN
            DECLARE EXIT HANDLER FOR SQLEXCEPTION SET v_certificados = NULL;
            SELECT COUNT(*) INTO v_certificados FROM orden_metrologia om WHERE om.eliminado_en IS NULL AND om.estado = 'pendiente_certificado';
        END;
        BEGIN
            DECLARE EXIT HANDLER FOR SQLEXCEPTION SET v_tickets = NULL;
            SELECT COUNT(*) INTO v_tickets FROM ticket_metrologia t WHERE t.eliminado_en IS NULL AND t.estado = 'solicitado';
        END;
    END IF;

    -- Mi Equipo: técnicos del área y los que hoy están en labores (solo Servicio Técnico y Metrología)
    IF v_area IN ('servicio_tecnico', 'metrologia') THEN
        BEGIN
            DECLARE EXIT HANDLER FOR SQLEXCEPTION
            BEGIN
                SET v_eq_total = NULL;
                SET v_eq_labores = NULL;
            END;
            SELECT COUNT(*),
                   IFNULL(SUM(EXISTS (SELECT 1
                                      FROM   orden_servicio os
                                      WHERE  os.eliminado_en IS NULL AND os.fecha_ejecucion = v_hoy
                                        AND  os.estado IN ('en_ruta', 'en_ejecucion', 'pausada')
                                        AND  (os.id_tecnico_principal = u.id_usuario
                                              OR EXISTS (SELECT 1 FROM os_personal op
                                                         WHERE op.id_os = os.id_os AND op.id_usuario = u.id_usuario AND op.eliminado_en IS NULL)))), 0)
            INTO   v_eq_total, v_eq_labores
            FROM   usuario u
            WHERE  u.eliminado_en IS NULL AND u.estado = 'activo' AND u.area = v_area
              AND  (u.cargo IS NULL OR (u.cargo NOT LIKE 'jefe\_%' AND u.cargo NOT LIKE 'asistente\_%'));
        END;
    END IF;

    -- Agenda del Área: conflictos sobrevenidos de la Programación (HU-39)
    BEGIN
        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            CALL SP_LimpiarConflictosProgramacion();
            SET v_conflictos = NULL;
        END;
        IF FN_PermisoAccion(p_id_usuario, 'prog_bandeja') = 1 THEN
            CALL SP_ArmarConflictosProgramacion();
            SELECT COUNT(*) INTO v_conflictos
            FROM   tmp_cf c
            WHERE  v_area NOT IN ('servicio_tecnico', 'metrologia')
                   OR EXISTS (SELECT 1 FROM usuario t WHERE t.id_usuario = c.id_usuario AND t.area = v_area);
            CALL SP_LimpiarConflictosProgramacion();
        END IF;
    END;

    -- Viáticos y Gastos: gastos rendidos por revisar (solo quien los revisa)
    BEGIN
        DECLARE EXIT HANDLER FOR SQLEXCEPTION SET v_gastos = NULL;
        IF FN_PermisoAccion(p_id_usuario, 'prog_aprobar_reprogramacion') = 1 THEN
            SELECT COUNT(*) INTO v_gastos
            FROM   gasto_viatico g
            WHERE  g.eliminado_en IS NULL AND g.tipo = 'gasto_solicitado' AND g.estado = 'pendiente';
        END IF;
    END;

    -- Resumen del día: los servicios del alcance del jefe (SP_ArmarAlcanceJefaturaMovil: área de la RQ para ST/Metrología; las demás áreas ven todo)
    CALL SP_ArmarAlcanceJefaturaMovil(v_area, NULL);
    SELECT COUNT(*),
           IFNULL(SUM(os.estado = 'en_ruta'), 0),
           IFNULL(SUM(os.estado IN ('en_ejecucion', 'pausada')), 0)
    INTO   v_prog, v_ruta, v_ejec
    FROM   orden_servicio os
    JOIN   tmp_jf_alc a ON a.id_os = os.id_os
    WHERE  os.estado IN ('programada', 'reprogramada', 'en_ruta', 'en_ejecucion', 'pausada', 'bloqueada');
    SELECT COUNT(DISTINCT d.id_os) INTO v_dem
    FROM   demora_registro d
    JOIN   tmp_jf_alc a ON a.id_os = d.id_os
    JOIN   orden_servicio os ON os.id_os = d.id_os
    WHERE  d.eliminado_en IS NULL AND DATE(d.fecha_registro) = v_hoy
      AND  os.estado IN ('programada', 'reprogramada', 'en_ruta', 'en_ejecucion', 'pausada', 'bloqueada');
    DROP TEMPORARY TABLE IF EXISTS tmp_jf_alc;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT v_area                                                           AS area_codigo,
           (SELECT t.String1 FROM tabla_maestra t
            WHERE  t.IdMaestro = 79 AND t.IdEmpresa = 1 AND t.String2 = v_area LIMIT 1) AS area_nombre,
           v_sede                                                           AS sede,
           v_prog                                                           AS programados,
           v_ruta                                                           AS en_ruta,
           v_ejec                                                           AS en_ejecucion,
           v_dem                                                            AS con_demora,
           (SELECT COUNT(*)
            FROM   autorizacion_salida_os a
            WHERE  a.eliminado_en IS NULL AND a.estado = 'pendiente'
              AND  (v_aut_general = 1
                    OR (v_aut_area IS NOT NULL AND (a.area_destino IS NULL OR a.area_destino = v_aut_area)))) AS aprobaciones_pendientes,
           v_alertas                                                        AS alertas_criticas,
           v_informes                                                       AS informes_por_revisar,
           v_certificados                                                   AS certificados_pendientes,
           v_tickets                                                        AS tickets_correlativo,
           v_eq_total                                                       AS mi_equipo_total,
           v_eq_labores                                                     AS mi_equipo_en_labores,
           v_conflictos                                                     AS agenda_conflictos,
           v_gastos                                                         AS viaticos_por_revisar;
END$$

DELIMITER ;

-- ############################################################
-- SP_ObtenerPanelCampoMovil
-- ############################################################
-- ============================================================
-- SP_ObtenerPanelCampoMovil  (App Mobile HU-29 — Panel de campo en tiempo real · solo lectura)
-- El jefe de área ve dónde están sus técnicos y en qué estado va cada servicio de HOY (fecha de Lima, UTC-5).
-- Reutiliza el motor de la bandeja de Seguimiento Operativo (HU-51, SP_ArmarSeguimientoOperativo: servicios confirmados del día, estado, GPS y alertas)
-- y el alcance del menú de Jefatura (SP_ResolverJefaturaMovil + SP_ArmarAlcanceJefaturaMovil: área de la RQ para ST/Metrología; las demás áreas ven todo).
-- Quien lo ve no necesita seg_bandeja: el permiso es ser jefe (menú de Jefatura) y el alcance por área. No escribe nada.
-- Resultados: 1 mensaje · 2 KPIs (1 fila) · 3 pines del mapa (un técnico por fila) · 4 alertas críticas (primero las críticas; máx. 10).
--   KPIs (banderas de la OS, mismas que el menú de Jefatura; no son excluyentes entre sí):
--     en_ruta        OS en ruta (con o sin llegada)          ejecucion   OS en ejecución o pausada
--     demora         con demora/incidencia no crítica o pausada (no finalizada)      incidencia  incidente crítico o que detiene (no finalizada)
--     finalizados    OS finalizadas hoy                       programados total del alcance
--   Pin: estado del técnico = el de su servicio más urgente (HU-51). lat/lon NULL = el técnico aún no envía posición hoy (el mapa no lo dibuja).
--   Alertas (tipo): error_critico (ensayo con error crítico aceptado, HU-10: informe_tecnico.error_critico_motivo) · incidente (demora/incidencia que
--     detiene) · demora (demoras e incidencias del día) · perdida_contacto · gps_parado · sin_ingreso_post_llegada · sin_iniciar_servicio (alertas automáticas HU-51).
-- Requiere las migraciones 90 a 92, 97 y 100.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerPanelCampoMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerPanelCampoMovil(
    IN p_id_usuario BIGINT
)
proc: BEGIN
    DECLARE v_area        VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_sede        VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_aut_area    VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_aut_general TINYINT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_jf_alc;
        DROP TEMPORARY TABLE IF EXISTS tmp_pc_al;
        CALL SP_LimpiarSeguimientoOperativo();
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    CALL SP_ResolverJefaturaMovil(p_id_usuario, v_area, v_sede, v_aut_area, v_aut_general);
    IF v_area IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Tu cargo no tiene el menú de Jefatura.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_ArmarSeguimientoOperativo();
    CALL SP_ArmarAlcanceJefaturaMovil(v_area, NULL);
    CALL SP_FiltrarServiciosJefaturaMovil(NULL, NULL);   -- tmp_sg_f = servicios del día dentro del alcance del jefe

    -- Alertas: error crítico de ensayo + demoras/incidencias del día + alertas automáticas de la bandeja (sin la proximidad ni el incidente, que ya sale como demora/incidencia)
    DROP TEMPORARY TABLE IF EXISTS tmp_pc_al;
    CREATE TEMPORARY TABLE tmp_pc_al (
        id        INT NOT NULL AUTO_INCREMENT,
        clave     VARCHAR(60)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        tipo      VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        severidad VARCHAR(12)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        titulo    VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        detalle   VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        id_os     BIGINT,
        numero    VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        cliente   VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        tecnico   VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        equipo    VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        minutos   INT,
        PRIMARY KEY (id)
    );
    INSERT INTO tmp_pc_al (clave, tipo, severidad, titulo, detalle, id_os, numero, cliente, tecnico, equipo, minutos)
    SELECT CONCAT('ensayo:', it.id_informe), 'error_critico', 'critica', 'Error crítico', LEFT(it.error_critico_motivo, 300), o.id_os, o.numero, o.razon_social,
           TRIM(CONCAT(ut.nombre, ' ', ut.apellido)), COALESCE(ec.codigo_cliente, ec.codigo_tw),
           GREATEST(0, TIMESTAMPDIFF(MINUTE, COALESCE(it.modificado_en, it.creado_en), NOW()))
    FROM   informe_tecnico it
    JOIN   tmp_sg_f f  ON f.id_os = it.id_os
    JOIN   tmp_sg_os o ON o.id_os = it.id_os
    LEFT JOIN usuario ut ON ut.id_usuario = it.id_tecnico
    LEFT JOIN equipo_cliente ec ON ec.id_equipo = it.id_equipo
    WHERE  it.eliminado_en IS NULL AND NULLIF(TRIM(it.error_critico_motivo), '') IS NOT NULL AND o.fase <> 'finalizado';

    INSERT INTO tmp_pc_al (clave, tipo, severidad, titulo, detalle, id_os, numero, cliente, tecnico, equipo, minutos)
    SELECT i.clave, IF(i.impacto = 'detiene', 'incidente', 'demora'), IF(i.impacto = 'detiene', 'critica', 'advertencia'),
           IF(i.impacto = 'detiene', 'Incidente', 'Demora'),
           LEFT(CONCAT(i.tipo, IF(i.duracion_min IS NULL, '', CONCAT(' +', i.duracion_min, ' min')),
                       IF(IFNULL(i.descripcion, '') = '', '', CONCAT(' · ', i.descripcion))), 300),
           o.id_os, o.numero, o.razon_social, i.tecnico, NULL, GREATEST(0, TIMESTAMPDIFF(MINUTE, i.fecha, c.ahora))
    FROM   tmp_sg_inc i
    JOIN   tmp_sg_f f  ON f.id_os = i.id_os
    JOIN   tmp_sg_os o ON o.id_os = i.id_os
    JOIN   tmp_sg_cfg c
    WHERE  o.fase <> 'finalizado';

    INSERT INTO tmp_pc_al (clave, tipo, severidad, titulo, detalle, id_os, numero, cliente, tecnico, equipo, minutos)
    SELECT a.clave, a.tipo, a.severidad, a.titulo, a.detalle, o.id_os, o.numero, o.razon_social, a.tecnico, NULL, a.minutos
    FROM   tmp_sg_alerta a
    JOIN   tmp_sg_f f  ON f.id_os = a.id_os
    JOIN   tmp_sg_os o ON o.id_os = a.id_os
    WHERE  a.severidad IN ('critica', 'advertencia') AND a.tipo NOT IN ('incidente', 'proximidad');

    -- Pines: un técnico por fila (los de los servicios del alcance)
    DROP TEMPORARY TABLE IF EXISTS tmp_sg_tf;
    CREATE TEMPORARY TABLE tmp_sg_tf (id_usuario BIGINT NOT NULL, PRIMARY KEY (id_usuario));
    INSERT INTO tmp_sg_tf SELECT DISTINCT ut.id_usuario FROM tmp_sg_ut ut JOIN tmp_sg_f f ON f.id_os = ut.id_os;

    SELECT 2 AS IdTipoMensaje, 'OK' AS Mensaje;

    -- 2 KPIs
    SELECT COUNT(*)                                                                                                AS programados,
           IFNULL(SUM(o.fase IN ('en_ruta', 'en_planta')), 0)                                                       AS en_ruta,
           IFNULL(SUM(o.fase = 'en_ejecucion'), 0)                                                                  AS ejecucion,
           IFNULL(SUM(o.fase <> 'finalizado' AND (o.n_demoras > 0 OR o.os_estado = 'pausada')), 0)                  AS demora,
           IFNULL(SUM(o.fase <> 'finalizado' AND o.crit = 1), 0)                                                    AS incidencia,
           IFNULL(SUM(o.fase = 'finalizado'), 0)                                                                    AS finalizados,
           DATE_FORMAT(MAX(c.ahora), '%H:%i')                                                                       AS actualizado,
           IFNULL(MAX(c.refresco), 30)                                                                              AS refresco_segundos
    FROM   tmp_sg_f f
    JOIN   tmp_sg_os o ON o.id_os = f.id_os
    JOIN   tmp_sg_cfg c;

    -- 3 Pines del mapa
    SELECT t.id_usuario AS id_usuario, t.nombre AS tecnico, t.iniciales AS iniciales, t.estado_seg AS estado,
           p.lat AS latitud, p.lon AS longitud,
           IF(p.ts_utc IS NULL, NULL, GREATEST(0, TIMESTAMPDIFF(MINUTE, p.ts_utc, c.ahora_utc))) AS minutos_ubicacion,
           t.id_os_actual AS id_os, o.numero AS numero_os, o.razon_social AS cliente
    FROM   tmp_sg_tec t
    JOIN   tmp_sg_tf tf ON tf.id_usuario = t.id_usuario
    LEFT JOIN tmp_sg_pos p ON p.id_usuario = t.id_usuario
    LEFT JOIN tmp_sg_os  o ON o.id_os = t.id_os_actual
    JOIN   tmp_sg_cfg c
    ORDER BY t.nombre;

    -- 4 Alertas críticas primero (luego advertencias), las más recientes antes
    SELECT al.clave AS clave, al.tipo AS tipo, al.severidad AS severidad, al.titulo AS titulo, al.detalle AS detalle, al.id_os AS id_os,
           al.numero AS numero_os, al.cliente AS cliente, al.tecnico AS tecnico, al.equipo AS equipo, al.minutos AS minutos
    FROM   tmp_pc_al al
    ORDER BY FIELD(al.severidad, 'critica', 'advertencia'), al.minutos, al.id
    LIMIT 10;

    DROP TEMPORARY TABLE IF EXISTS tmp_pc_al;
    DROP TEMPORARY TABLE IF EXISTS tmp_jf_alc;
    CALL SP_LimpiarSeguimientoOperativo();
END$$

DELIMITER ;

-- ############################################################
-- SP_ObtenerServiciosJefaturaMovil
-- ############################################################
-- ============================================================
-- SP_ObtenerServiciosJefaturaMovil  (App Mobile HU-29 — "Servicios activos" · vista lista del Panel de Campo · solo lectura)
-- Servicios de HOY dentro del alcance del jefe (SP_ResolverJefaturaMovil + SP_ArmarAlcanceJefaturaMovil), con el estado y el avance del motor de la bandeja
-- de Seguimiento Operativo (HU-51). Búsqueda por N° de OS/OM, cliente, RUC o técnico (hasta 100 caracteres).
--   p_filtro: activos (por defecto; no finalizados) · demora · incidencias · finalizados.
-- Resultados: 1 mensaje · 2 contadores de los chips (siempre sobre todo el alcance, sin búsqueda ni filtro) · 3 servicios (máx. 100).
--   estado (de la bandeja HU-51): sin_salir · en_ruta · en_planta · en_ejecucion · con_demora · con_incidente · finalizado.
--   llegada (HH:MM) = llegada validada por GPS (HU-06).  eta (HH:MM) = solo en ruta: la hora esperada de llegada de la bandeja (hora programada + demoras en ruta).
--   lugar = sede/planta del cliente (o su dirección).
--   avance_pct = ESTIMACIÓN POR HITOS, no un dato medido: sin salir 0 · en ruta 15 · en planta 30 · en ejecución 30 + 60 × (equipos ejecutados / equipos) · finalizado 100.
-- Requiere las migraciones 90 a 92 y 97.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerServiciosJefaturaMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerServiciosJefaturaMovil(
    IN p_id_usuario BIGINT,
    IN p_filtro     VARCHAR(12)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_busqueda   VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_area        VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_sede        VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_aut_area    VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_aut_general TINYINT DEFAULT 0;
    DECLARE v_filtro      VARCHAR(12)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_jf_alc;
        CALL SP_LimpiarSeguimientoOperativo();
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SET v_filtro = IFNULL(NULLIF(TRIM(p_filtro), ''), 'activos');
    IF v_filtro NOT IN ('activos', 'demora', 'incidencias', 'finalizados') THEN
        SELECT 1 AS IdTipoMensaje, 'El filtro de servicios no es válido.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF CHAR_LENGTH(IFNULL(p_busqueda, '')) > 100 THEN
        SELECT 1 AS IdTipoMensaje, 'La búsqueda no puede superar los 100 caracteres.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_ResolverJefaturaMovil(p_id_usuario, v_area, v_sede, v_aut_area, v_aut_general);
    IF v_area IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Tu cargo no tiene el menú de Jefatura.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_ArmarSeguimientoOperativo();
    CALL SP_ArmarAlcanceJefaturaMovil(v_area, NULL);

    SELECT 2 AS IdTipoMensaje, 'OK' AS Mensaje;

    -- 2 Chips: sobre todo el alcance del jefe
    SELECT IFNULL(SUM(o.fase <> 'finalizado'), 0)                                                       AS activos,
           IFNULL(SUM(o.fase <> 'finalizado' AND (o.n_demoras > 0 OR o.os_estado = 'pausada')), 0)       AS con_demora,
           IFNULL(SUM(o.fase <> 'finalizado' AND o.crit = 1), 0)                                         AS incidencias,
           IFNULL(SUM(o.fase = 'finalizado'), 0)                                                         AS finalizados,
           DATE_FORMAT(MAX(c.ahora), '%H:%i')                                                            AS actualizado,
           IFNULL(MAX(c.refresco), 30)                                                                   AS refresco_segundos
    FROM   tmp_sg_os o
    JOIN   tmp_jf_alc a ON a.id_os = o.id_os
    JOIN   tmp_sg_cfg c;

    CALL SP_FiltrarServiciosJefaturaMovil(p_busqueda, v_filtro);

    -- 3 Servicios
    SELECT o.id_os AS id_os, o.numero AS numero, o.razon_social AS cliente, o.estado_seg AS estado,
           o.id_tecnico AS id_tecnico, o.tecnico AS tecnico,
           UPPER(CONCAT(LEFT(IFNULL(o.nombre_pila, ''), 1), LEFT(IFNULL(SUBSTRING_INDEX(o.tecnico, ' ', -1), ''), 1))) AS iniciales,
           COALESCE(NULLIF(o.sede_nombre, ''), NULLIF(o.sede_direccion, '')) AS lugar,
           TIME_FORMAT(o.hora_inicio, '%H:%i') AS hora_programada,
           DATE_FORMAT(o.llegada_dt, '%H:%i') AS llegada,
           IF(o.fase = 'en_ruta', DATE_FORMAT(h.esperado, '%H:%i'), NULL) AS eta,
           CASE o.fase WHEN 'finalizado'   THEN 100
                       WHEN 'en_ejecucion' THEN 30 + ROUND(60 * IF(o.n_equipos = 0, 0, o.n_ejecutados / o.n_equipos))
                       WHEN 'en_planta'    THEN 30
                       WHEN 'en_ruta'      THEN 15
                       ELSE 0 END AS avance_pct,
           IF(p.ts_utc IS NULL, NULL, GREATEST(0, TIMESTAMPDIFF(MINUTE, p.ts_utc, c.ahora_utc))) AS minutos_ubicacion
    FROM   tmp_sg_f f
    JOIN   tmp_sg_os o ON o.id_os = f.id_os
    LEFT JOIN tmp_sg_pos  p ON p.id_usuario = o.id_tecnico
    LEFT JOIN tmp_sg_hito h ON h.id_os = o.id_os
    JOIN   tmp_sg_cfg c
    ORDER BY o.prio, o.hora_inicio, o.id_os
    LIMIT 100;

    DROP TEMPORARY TABLE IF EXISTS tmp_jf_alc;
    CALL SP_LimpiarSeguimientoOperativo();
END$$

DELIMITER ;

-- ############################################################
-- SP_ObtenerServicioJefaturaMovil
-- ############################################################
-- ============================================================
-- SP_ObtenerServicioJefaturaMovil  (App Mobile HU-30 — Seguimiento del servicio: detalle de una OS · solo lectura)
-- El jefe ve el detalle de un servicio de HOY de su alcance (SP_ResolverJefaturaMovil + SP_ArmarAlcanceJefaturaMovil): técnico (para llamarlo), estado,
-- hora programada, llegada, SLA, los hitos que marca la app del técnico y lo necesario para el modal "Cambiar estado operativo".
-- Reutiliza el motor de Seguimiento Operativo (HU-51/52). Quien lo ve no necesita seg_bandeja; sí lo exigen los cambios (ver puede_cambiar_estado).
-- Resultados: 1 mensaje · 2 cabecera (1 fila) · 3 hitos · 4 estados a los que se puede avanzar · 5 motivos del cambio manual.
--   Cabecera: estado (el de la bandeja HU-51) y estado_os (el de la OS). telefono_tecnico = ficha del usuario. contacto_* = contacto en planta de la OS.
--   sla_pct = PUNTUALIDAD DE LLEGADA (estimación, no hay un SLA de ejecución definido por servicio): 100 si llegó a la hora programada o antes; si llegó tarde baja
--     proporcionalmente al atraso sobre la duración estimada del servicio (mínimo 60 min); NULL mientras no haya llegada.
--   avance_pct = estimación por hitos (igual que SP_ObtenerServiciosJefaturaMovil).
--   Hitos (estado: hecho · actual · pendiente; tono: verde · azul · naranja · rojo · gris): asignado y autorizado (visto bueno de la autorización de salida) · en ruta · demoras
--     registradas (app o Asistente, HU-05/HU-53) · llegada a planta (GPS válido a N m, HU-06) · trabajo en el equipo (equipos ejecutados) · informe y firmas (informe_tecnico).
--   Estados permitidos: SOLO avanzar (regla de SP_RegistrarAsistenteServicioRuta, HU-53): salida · en_ruta · llegada · ingreso · inicio · finalizado, por encima del nivel actual.
--   puede_cambiar_estado = 1 si el usuario tiene seg_registrar y seg_bandeja (los exige SP_RegistrarAsistenteServicioRuta) y el servicio no está finalizado.
-- Requiere las migraciones 90 a 92 y 97.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerServicioJefaturaMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerServicioJefaturaMovil(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT
)
proc: BEGIN
    DECLARE v_area        VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_sede        VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_aut_area    VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_aut_general TINYINT DEFAULT 0;
    DECLARE v_existe      INT DEFAULT 0;
    DECLARE v_ini_utc     DATETIME;
    DECLARE v_estado_os   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_nivel       INT DEFAULT 0;
    DECLARE v_puede       TINYINT DEFAULT 0;
    DECLARE v_informe     VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_jf_alc;
        DROP TEMPORARY TABLE IF EXISTS tmp_jf_hito;
        CALL SP_LimpiarSeguimientoOperativo();
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_os, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El servicio indicado no es válido.' AS Mensaje;
        LEAVE proc;
    END IF;
    CALL SP_ResolverJefaturaMovil(p_id_usuario, v_area, v_sede, v_aut_area, v_aut_general);
    IF v_area IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Tu cargo no tiene el menú de Jefatura.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_ArmarSeguimientoOperativo();
    CALL SP_ArmarAlcanceJefaturaMovil(v_area, p_id_os);
    SELECT COUNT(*) INTO v_existe FROM tmp_sg_os o JOIN tmp_jf_alc a ON a.id_os = o.id_os WHERE o.id_os = p_id_os;
    IF v_existe = 0 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_jf_alc;
        CALL SP_LimpiarSeguimientoOperativo();
        SELECT 1 AS IdTipoMensaje, 'El servicio no existe, no es de hoy o no pertenece a tu área.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT ini_utc INTO v_ini_utc FROM tmp_sg_cfg LIMIT 1;
    SELECT os_estado INTO v_estado_os FROM tmp_sg_os WHERE id_os = p_id_os;

    -- Nivel del servicio (0 programado · 1 salida · 2 en ruta · 3 llegada · 4 ingreso a planta · 5 inicio · 6 finalizado): mismos niveles que HU-53
    SET v_nivel = CASE v_estado_os
        WHEN 'en_ejecucion' THEN 5 WHEN 'pausada' THEN 5 WHEN 'finalizada' THEN 6
        WHEN 'en_ruta' THEN
            CASE WHEN EXISTS (SELECT 1 FROM evento_campo e JOIN tabla_maestra m ON m.Descripcion = 'TIPO_EVENTO_CAMPO' AND m.IdEmpresa = 1 AND m.Num1 = e.id_tipo_evento
                              WHERE e.id_os = p_id_os AND e.eliminado_en IS NULL AND e.timestamp_utc >= v_ini_utc AND m.String2 = 'INGRESO_PLANTA') THEN 4
                 WHEN (SELECT x.hora_llegada_real FROM orden_servicio x WHERE x.id_os = p_id_os) IS NOT NULL THEN 3
                 WHEN EXISTS (SELECT 1 FROM evento_campo e JOIN tabla_maestra m ON m.Descripcion = 'TIPO_EVENTO_CAMPO' AND m.IdEmpresa = 1 AND m.Num1 = e.id_tipo_evento
                              WHERE e.id_os = p_id_os AND e.eliminado_en IS NULL AND e.timestamp_utc >= v_ini_utc AND m.String2 = 'EN_RUTA') THEN 2
                 ELSE 1 END
        ELSE 0 END;
    SET v_puede = IF(v_estado_os <> 'finalizada' AND FN_PermisoAccion(p_id_usuario, 'seg_registrar') = 1 AND FN_PermisoAccion(p_id_usuario, 'seg_bandeja') = 1, 1, 0);
    SELECT it.estado INTO v_informe FROM informe_tecnico it WHERE it.id_os = p_id_os AND it.eliminado_en IS NULL ORDER BY it.id_informe DESC LIMIT 1;

    -- ── Hitos del servicio ────────────────────────────────────────────────────────────────
    DROP TEMPORARY TABLE IF EXISTS tmp_jf_hito;
    CREATE TEMPORARY TABLE tmp_jf_hito (
        id      INT NOT NULL AUTO_INCREMENT,
        ord     INT NOT NULL,
        hora    VARCHAR(5)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        codigo  VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL,
        titulo  VARCHAR(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL,
        detalle VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        estado  VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL,
        tono    VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL,
        PRIMARY KEY (id)
    );

    -- 1 Asignado y autorizado (la programación confirmada; con la autorización de salida aprobada, quién dio el visto bueno)
    INSERT INTO tmp_jf_hito (ord, hora, codigo, titulo, detalle, estado, tono)
    SELECT 1, DATE_FORMAT(x.resuelto_en, '%H:%i'), 'asignado', 'Asignado y autorizado',
           IF(x.jefe IS NULL, 'Programación confirmada', CONCAT('visto bueno de ', x.jefe)), 'hecho', 'verde'
    FROM (SELECT 1 AS uno) d
    LEFT JOIN (SELECT a.resuelto_en, NULLIF(TRIM(CONCAT(IFNULL(j.nombre, ''), ' ', IFNULL(j.apellido, ''))), '') AS jefe
               FROM autorizacion_salida_os a LEFT JOIN usuario j ON j.id_usuario = a.id_jefe
               WHERE a.id_os = p_id_os AND a.eliminado_en IS NULL AND a.estado = 'aprobada'
               ORDER BY a.resuelto_en DESC LIMIT 1) x ON 1 = 1;

    -- 2 En ruta
    INSERT INTO tmp_jf_hito (ord, hora, codigo, titulo, detalle, estado, tono)
    SELECT 2, DATE_FORMAT(CONVERT_TZ(o.salida_utc, '+00:00', '-05:00'), '%H:%i'), 'en_ruta', 'En ruta',
           IF(o.fase = 'sin_salir', 'Aún no sale de la sede', 'salida de la sede'),
           IF(o.fase = 'sin_salir', 'actual', 'hecho'), IF(o.fase = 'sin_salir', 'azul', 'verde')
    FROM tmp_sg_os o WHERE o.id_os = p_id_os;

    -- 3 / 5 Demoras e incidencias de hoy (antes de la llegada si fueron en ruta; después si fueron en planta o incidencias)
    INSERT INTO tmp_jf_hito (ord, hora, codigo, titulo, detalle, estado, tono)
    SELECT IF(i.fase = 'llegada', 3, 5), DATE_FORMAT(i.fecha, '%H:%i'), 'demora',
           LEFT(CASE i.fase WHEN 'llegada' THEN 'Demora · En ruta' WHEN 'ingreso' THEN 'Demora · Ingreso a planta'
                            ELSE CONCAT(IF(i.impacto = 'detiene', 'Incidencia · ', 'Demora · '), i.tipo) END, 120),
           LEFT(CONCAT(IF(i.duracion_min IS NULL, '', CONCAT('+', i.duracion_min, ' min · ')),
                       IF(i.origen = 'asistente', 'registrada por el asistente', 'registrada por el técnico')), 300),
           'hecho', IF(i.impacto = 'detiene', 'rojo', 'naranja')
    FROM tmp_sg_inc i WHERE i.id_os = p_id_os ORDER BY i.fecha;

    -- 4 Llegada a planta (GPS válido a N m, HU-06)
    INSERT INTO tmp_jf_hito (ord, hora, codigo, titulo, detalle, estado, tono)
    SELECT 4, DATE_FORMAT(o.llegada_dt, '%H:%i'), 'llegada', 'Llegada a planta',
           IF(o.llegada_dt IS NULL, 'Aún no llega', IF(ev.distancia_metros IS NULL, 'llegada confirmada', CONCAT('GPS válido a ', ev.distancia_metros, ' m'))),
           IF(o.llegada_dt IS NOT NULL, 'hecho', IF(o.fase = 'en_ruta', 'actual', 'pendiente')),
           IF(o.llegada_dt IS NOT NULL, 'verde', IF(o.fase = 'en_ruta', 'azul', 'gris'))
    FROM tmp_sg_os o
    LEFT JOIN (SELECT e.distancia_metros
               FROM evento_campo e JOIN tabla_maestra m ON m.Descripcion = 'TIPO_EVENTO_CAMPO' AND m.IdEmpresa = 1 AND m.Num1 = e.id_tipo_evento AND m.String2 = 'LLEGADA'
               WHERE e.id_os = p_id_os AND e.eliminado_en IS NULL AND e.timestamp_utc >= v_ini_utc
               ORDER BY e.id_evento DESC LIMIT 1) ev ON 1 = 1
    WHERE o.id_os = p_id_os;

    -- 6 Trabajo en el equipo
    INSERT INTO tmp_jf_hito (ord, hora, codigo, titulo, detalle, estado, tono)
    SELECT 6, DATE_FORMAT(o.inicio_dt, '%H:%i'), 'trabajo', 'Trabajo en el equipo',
           IF(o.n_equipos = 0, NULL, CONCAT(o.n_ejecutados, ' de ', o.n_equipos, IF(o.n_equipos = 1, ' equipo ejecutado', ' equipos ejecutados'))),
           CASE o.fase WHEN 'finalizado' THEN 'hecho' WHEN 'en_ejecucion' THEN 'actual' ELSE 'pendiente' END,
           CASE o.fase WHEN 'finalizado' THEN 'verde' WHEN 'en_ejecucion' THEN 'azul' ELSE 'gris' END
    FROM tmp_sg_os o WHERE o.id_os = p_id_os;

    -- 7 Informe y firmas
    INSERT INTO tmp_jf_hito (ord, hora, codigo, titulo, detalle, estado, tono)
    SELECT 7, NULL, 'informe', 'Informe y firmas',
           CASE WHEN v_informe = 'aprobado' THEN 'Informe aprobado'
                WHEN v_informe IN ('pendiente_revision', 'en_revision') THEN 'En revisión'
                WHEN v_informe = 'observado' THEN 'Observado: requiere correcciones'
                WHEN v_informe = 'borrador' THEN 'Borrador del técnico'
                ELSE 'Pendiente' END,
           CASE WHEN v_informe = 'aprobado' THEN 'hecho' WHEN v_informe IN ('pendiente_revision', 'en_revision', 'observado') THEN 'actual' ELSE 'pendiente' END,
           CASE WHEN v_informe = 'aprobado' THEN 'verde' WHEN v_informe = 'observado' THEN 'naranja' WHEN v_informe IN ('pendiente_revision', 'en_revision') THEN 'azul' ELSE 'gris' END;

    SELECT 2 AS IdTipoMensaje, 'OK' AS Mensaje;

    -- 2 Cabecera
    SELECT o.id_os AS id_os, o.numero AS numero, o.tipo AS tipo, o.razon_social AS cliente,
           COALESCE(NULLIF(o.sede_nombre, ''), NULLIF(o.sede_direccion, '')) AS lugar,
           o.estado_seg AS estado, o.os_estado AS estado_os,
           o.id_tecnico AS id_tecnico, o.tecnico AS tecnico, t.cargo AS cargo_tecnico, NULLIF(TRIM(ut.telefono), '') AS telefono_tecnico,
           TIME_FORMAT(o.hora_inicio, '%H:%i') AS hora_programada, DATE_FORMAT(o.llegada_dt, '%H:%i') AS llegada,
           IF(o.llegada_dt IS NULL OR o.hora_inicio IS NULL, NULL,
              GREATEST(0, 100 - ROUND(100 * GREATEST(0, TIMESTAMPDIFF(MINUTE, TIMESTAMP(c.hoy, o.hora_inicio), o.llegada_dt))
                                      / GREATEST(60, IFNULL(TIME_TO_SEC(TIMEDIFF(o.hora_fin_est, o.hora_inicio)) DIV 60, 60))))) AS sla_pct,
           CASE o.fase WHEN 'finalizado' THEN 100
                       WHEN 'en_ejecucion' THEN 30 + ROUND(60 * IF(o.n_equipos = 0, 0, o.n_ejecutados / o.n_equipos))
                       WHEN 'en_planta' THEN 30 WHEN 'en_ruta' THEN 15 ELSE 0 END AS avance_pct,
           o.n_equipos AS equipos, o.n_ejecutados AS ejecutados,
           cc.nombres AS contacto_nombre, NULLIF(TRIM(cc.telefono_movil), '') AS contacto_telefono,
           v_puede AS puede_cambiar_estado, DATE_FORMAT(c.ahora, '%H:%i') AS actualizado
    FROM   tmp_sg_os o
    JOIN   tmp_sg_cfg c
    JOIN   orden_servicio osr ON osr.id_os = o.id_os
    LEFT JOIN tmp_sg_tec t ON t.id_usuario = o.id_tecnico
    LEFT JOIN usuario ut ON ut.id_usuario = o.id_tecnico
    LEFT JOIN contacto_cliente cc ON cc.id_contacto = osr.id_contacto AND cc.SoftDelete = 0
    WHERE  o.id_os = p_id_os;

    -- 3 Hitos
    SELECT h.codigo AS codigo, h.titulo AS titulo, h.detalle AS detalle, h.hora AS hora, h.estado AS estado, h.tono AS tono
    FROM   tmp_jf_hito h ORDER BY h.ord, h.id;

    -- 4 Estados a los que se puede avanzar (solo hacia adelante)
    SELECT x.codigo AS codigo, x.nombre AS nombre
    FROM (SELECT 1 AS n, 'salida' AS codigo, 'Salida de base' AS nombre UNION ALL
          SELECT 2, 'en_ruta', 'En ruta' UNION ALL SELECT 3, 'llegada', 'Llegada a planta' UNION ALL
          SELECT 4, 'ingreso', 'Ingreso a planta' UNION ALL SELECT 5, 'inicio', 'Inicio de servicio' UNION ALL
          SELECT 6, 'finalizado', 'Finalizado') x
    WHERE x.n > v_nivel AND v_estado_os <> 'finalizada'
    ORDER BY x.n;

    -- 5 Motivos del cambio manual
    SELECT m.Num1 AS id_motivo, m.String1 AS nombre
    FROM   tabla_maestra m
    WHERE  m.Descripcion = 'MOTIVO_CAMBIO_MANUAL' AND m.IdEmpresa = 1 AND m.eliminado_en IS NULL
    ORDER BY m.Num1;

    DROP TEMPORARY TABLE IF EXISTS tmp_jf_hito;
    DROP TEMPORARY TABLE IF EXISTS tmp_jf_alc;
    CALL SP_LimpiarSeguimientoOperativo();
END$$

DELIMITER ;

-- ############################################################
-- SP_ObtenerRutaServicioJefaturaMovil
-- ############################################################
-- ============================================================
-- SP_ObtenerRutaServicioJefaturaMovil  (App Mobile HU-30 — "Ubicación y ruta" de un servicio · solo lectura)
-- Posición y recorrido GPS del técnico en un servicio de HOY dentro del alcance del jefe (SP_ResolverJefaturaMovil + SP_ArmarAlcanceJefaturaMovil), con la
-- demora registrada por el técnico y los eventos en ruta. Datos del motor de Seguimiento Operativo (HU-51): ubicacion_tecnico, evento_campo, demora_registro.
-- Resultados: 1 mensaje · 2 resumen (1 fila) · 3 recorrido GPS (máx. 120 puntos, en orden) · 4 eventos en ruta (cronológicos).
--   Resumen: lat/lon = última posición; minutos_ubicacion = antigüedad de esa posición; destino_* = planta del cliente (sede); origen_* = coordenada del evento de
--     salida (si la app la envió). distancia_m = distancia EN LÍNEA RECTA de la última posición a la planta (no es la distancia por calle).
--     velocidad_kmh = entre las dos últimas posiciones de hoy (solo si distan entre 20 s y 10 min; NULL si no hay datos suficientes).
--     eta (HH:MM) = solo en ruta: la hora de llegada recalculada por la última demora de la app (demora_registro.eta_recalculada) o, si no hay, la hora esperada de
--     la bandeja de seguimiento (hora programada + demoras en ruta). eta_programada = hora programada del servicio.
--     demora_* = la última demora/incidencia de hoy (texto armado para la tarjeta amarilla). contacto_* = contacto en planta del cliente (para avisarle).
--   Eventos: tono (verde · naranja · amarillo): hito del técnico (OK) · demora (+N MIN) · alerta automática de la bandeja (ALERTA).
-- Requiere las migraciones 90 a 92 y 97.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerRutaServicioJefaturaMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerRutaServicioJefaturaMovil(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT
)
proc: BEGIN
    DECLARE v_area        VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_sede        VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_aut_area    VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_aut_general TINYINT DEFAULT 0;
    DECLARE v_existe      INT DEFAULT 0;
    DECLARE v_ini_utc     DATETIME;
    DECLARE v_ahora_utc   DATETIME;
    DECLARE v_tec         BIGINT;
    DECLARE v_la1 DECIMAL(10,7) DEFAULT NULL;
    DECLARE v_lo1 DECIMAL(10,7) DEFAULT NULL;
    DECLARE v_t1  DATETIME      DEFAULT NULL;
    DECLARE v_la2 DECIMAL(10,7) DEFAULT NULL;
    DECLARE v_lo2 DECIMAL(10,7) DEFAULT NULL;
    DECLARE v_t2  DATETIME      DEFAULT NULL;
    DECLARE v_dt_seg  INT DEFAULT NULL;
    DECLARE v_dist_m  DOUBLE DEFAULT NULL;
    DECLARE v_kmh     DECIMAL(6,1) DEFAULT NULL;
    DECLARE v_dem_txt VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_dem_org VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_jf_alc;
        DROP TEMPORARY TABLE IF EXISTS tmp_jf_ev;
        CALL SP_LimpiarSeguimientoOperativo();
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_os, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El servicio indicado no es válido.' AS Mensaje;
        LEAVE proc;
    END IF;
    CALL SP_ResolverJefaturaMovil(p_id_usuario, v_area, v_sede, v_aut_area, v_aut_general);
    IF v_area IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Tu cargo no tiene el menú de Jefatura.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_ArmarSeguimientoOperativo();
    CALL SP_ArmarAlcanceJefaturaMovil(v_area, p_id_os);
    SELECT COUNT(*) INTO v_existe FROM tmp_sg_os o JOIN tmp_jf_alc a ON a.id_os = o.id_os WHERE o.id_os = p_id_os;
    IF v_existe = 0 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_jf_alc;
        CALL SP_LimpiarSeguimientoOperativo();
        SELECT 1 AS IdTipoMensaje, 'El servicio no existe, no es de hoy o no pertenece a tu área.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT ini_utc, ahora_utc INTO v_ini_utc, v_ahora_utc FROM tmp_sg_cfg LIMIT 1;
    SELECT id_tecnico INTO v_tec FROM tmp_sg_os WHERE id_os = p_id_os;

    -- Velocidad: entre las dos últimas posiciones del técnico en este servicio (hoy)
    SELECT x.latitud, x.longitud, x.timestamp_utc INTO v_la1, v_lo1, v_t1
    FROM   ubicacion_tecnico x
    WHERE  x.id_usuario = v_tec AND x.timestamp_utc >= v_ini_utc AND x.timestamp_utc <= v_ahora_utc AND (x.id_os IS NULL OR x.id_os = p_id_os)
    ORDER BY x.timestamp_utc DESC, x.id_ubicacion DESC LIMIT 1;
    SELECT x.latitud, x.longitud, x.timestamp_utc INTO v_la2, v_lo2, v_t2
    FROM   ubicacion_tecnico x
    WHERE  x.id_usuario = v_tec AND x.timestamp_utc >= v_ini_utc AND x.timestamp_utc <= v_ahora_utc AND (x.id_os IS NULL OR x.id_os = p_id_os)
    ORDER BY x.timestamp_utc DESC, x.id_ubicacion DESC LIMIT 1 OFFSET 1;
    IF v_t1 IS NOT NULL AND v_t2 IS NOT NULL THEN
        SET v_dt_seg = TIMESTAMPDIFF(SECOND, v_t2, v_t1);
        IF v_dt_seg BETWEEN 20 AND 600 THEN
            SET v_dist_m = 6371000 * 2 * ASIN(SQRT(POW(SIN(RADIANS(v_la1 - v_la2) / 2), 2)
                                                 + COS(RADIANS(v_la2)) * COS(RADIANS(v_la1)) * POW(SIN(RADIANS(v_lo1 - v_lo2) / 2), 2)));
            SET v_kmh = ROUND(v_dist_m / v_dt_seg * 3.6, 1);
        END IF;
    END IF;

    -- Eventos en ruta: hitos del técnico, demoras/incidencias y alertas automáticas de este servicio
    DROP TEMPORARY TABLE IF EXISTS tmp_jf_ev;
    CREATE TEMPORARY TABLE tmp_jf_ev (
        id      INT NOT NULL AUTO_INCREMENT,
        hora    DATETIME,
        titulo  VARCHAR(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        detalle VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        badge   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        tono    VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        PRIMARY KEY (id)
    );
    INSERT INTO tmp_jf_ev (hora, titulo, detalle, badge, tono)
    SELECT CONVERT_TZ(e.timestamp_utc, '+00:00', '-05:00'), m.String1,
           IF(e.latitud IS NULL, NULL, CONCAT('GPS ', ROUND(e.latitud, 2), ', ', ROUND(e.longitud, 2))), 'OK', 'verde'
    FROM   evento_campo e
    JOIN   tabla_maestra m ON m.Descripcion = 'TIPO_EVENTO_CAMPO' AND m.IdEmpresa = 1 AND m.Num1 = e.id_tipo_evento
    WHERE  e.id_os = p_id_os AND e.eliminado_en IS NULL AND e.timestamp_utc >= v_ini_utc AND m.String2 IN ('SALIDA_BASE', 'EN_RUTA', 'LLEGADA', 'INGRESO_PLANTA');
    INSERT INTO tmp_jf_ev (hora, titulo, detalle, badge, tono)
    SELECT i.fecha, LEFT(CONCAT(CASE i.fase WHEN 'llegada' THEN 'Demora registrada' WHEN 'ingreso' THEN 'Demora en ingreso a planta' ELSE i.tipo END), 120),
           LEFT(IFNULL(NULLIF(i.descripcion, ''), i.tipo), 300),
           IF(i.duracion_min IS NULL, 'DEMORA', CONCAT('+', i.duracion_min, ' MIN')), IF(i.impacto = 'detiene', 'rojo', 'naranja')
    FROM   tmp_sg_inc i WHERE i.id_os = p_id_os;
    INSERT INTO tmp_jf_ev (hora, titulo, detalle, badge, tono)
    SELECT DATE_SUB(c.ahora, INTERVAL IFNULL(a.minutos, 0) MINUTE), a.titulo, a.detalle, 'ALERTA', 'amarillo'
    FROM   tmp_sg_alerta a JOIN tmp_sg_cfg c
    WHERE  a.id_os = p_id_os AND a.tipo <> 'proximidad';

    -- Última demora/incidencia de hoy (se precalcula: una tabla temporal no puede abrirse dos veces en la misma consulta)
    SELECT LEFT(CONCAT(CASE i.fase WHEN 'llegada' THEN 'Llegada a planta' WHEN 'ingreso' THEN 'Ingreso a planta' ELSE i.tipo END,
                       IF(i.duracion_min IS NULL, '', CONCAT(' · +', i.duracion_min, ' min')),
                       IF(IFNULL(i.descripcion, '') = '', '', CONCAT(' · "', i.descripcion, '"')),
                       ' · Impacto: ', IF(i.impacto = 'detiene', 'detiene el servicio', 'retrasa el servicio')), 300),
           IF(i.origen = 'asistente', 'asistente', 'tecnico')
    INTO   v_dem_txt, v_dem_org
    FROM   tmp_sg_inc i WHERE i.id_os = p_id_os ORDER BY i.fecha DESC LIMIT 1;

    SELECT 2 AS IdTipoMensaje, 'OK' AS Mensaje;

    -- 2 Resumen
    SELECT o.id_os AS id_os, o.numero AS numero, o.razon_social AS cliente, o.estado_seg AS estado,
           o.id_tecnico AS id_tecnico, o.tecnico AS tecnico, NULLIF(TRIM(ut.telefono), '') AS telefono_tecnico,
           p.lat AS latitud, p.lon AS longitud,
           IF(p.ts_utc IS NULL, NULL, GREATEST(0, TIMESTAMPDIFF(MINUTE, p.ts_utc, c.ahora_utc))) AS minutos_ubicacion,
           v_kmh AS velocidad_kmh, o.dist_m AS distancia_m,
           o.lat_sede AS destino_latitud, o.lon_sede AS destino_longitud,
           COALESCE(NULLIF(o.sede_nombre, ''), NULLIF(o.sede_direccion, '')) AS destino_nombre,
           (SELECT e.latitud FROM evento_campo e JOIN tabla_maestra m ON m.Descripcion = 'TIPO_EVENTO_CAMPO' AND m.IdEmpresa = 1 AND m.Num1 = e.id_tipo_evento AND m.String2 = 'SALIDA_BASE'
             WHERE e.id_os = o.id_os AND e.eliminado_en IS NULL AND e.latitud IS NOT NULL AND e.timestamp_utc >= c.ini_utc ORDER BY e.id_evento LIMIT 1) AS origen_latitud,
           (SELECT e.longitud FROM evento_campo e JOIN tabla_maestra m ON m.Descripcion = 'TIPO_EVENTO_CAMPO' AND m.IdEmpresa = 1 AND m.Num1 = e.id_tipo_evento AND m.String2 = 'SALIDA_BASE'
             WHERE e.id_os = o.id_os AND e.eliminado_en IS NULL AND e.latitud IS NOT NULL AND e.timestamp_utc >= c.ini_utc ORDER BY e.id_evento LIMIT 1) AS origen_longitud,
           IF(o.fase = 'en_ruta', DATE_FORMAT(COALESCE((SELECT MAX(d.eta_recalculada) FROM demora_registro d
                                                          WHERE d.id_os = o.id_os AND d.tipo = 'llegada' AND d.eliminado_en IS NULL AND d.fecha_registro >= c.hoy), h.esperado), '%H:%i'), NULL) AS eta,
           TIME_FORMAT(o.hora_inicio, '%H:%i') AS eta_programada,
           v_dem_txt AS demora_texto, v_dem_org AS demora_origen,
           cc.nombres AS contacto_nombre, NULLIF(TRIM(cc.telefono_movil), '') AS contacto_telefono,
           DATE_FORMAT(c.ahora, '%H:%i') AS actualizado
    FROM   tmp_sg_os o
    JOIN   tmp_sg_cfg c
    JOIN   orden_servicio osr ON osr.id_os = o.id_os
    LEFT JOIN tmp_sg_pos  p ON p.id_usuario = o.id_tecnico
    LEFT JOIN tmp_sg_hito h ON h.id_os = o.id_os
    LEFT JOIN usuario ut ON ut.id_usuario = o.id_tecnico
    LEFT JOIN contacto_cliente cc ON cc.id_contacto = osr.id_contacto AND cc.SoftDelete = 0
    WHERE  o.id_os = p_id_os;

    -- 3 Recorrido GPS (hasta 120 puntos repartidos en todo el trayecto)
    SELECT t.latitud AS latitud, t.longitud AS longitud, DATE_FORMAT(CONVERT_TZ(t.timestamp_utc, '+00:00', '-05:00'), '%H:%i') AS hora
    FROM (SELECT x.latitud, x.longitud, x.timestamp_utc,
                 ROW_NUMBER() OVER (ORDER BY x.timestamp_utc, x.id_ubicacion) AS rn,
                 COUNT(*) OVER () AS n
          FROM   ubicacion_tecnico x
          WHERE  x.id_usuario = v_tec AND x.timestamp_utc >= v_ini_utc AND x.timestamp_utc <= v_ahora_utc AND (x.id_os IS NULL OR x.id_os = p_id_os)) t
    WHERE  t.n <= 120 OR MOD(t.rn, CEIL(t.n / 120)) = 0 OR t.rn = t.n
    ORDER BY t.rn;

    -- 4 Eventos en ruta
    SELECT DATE_FORMAT(ev.hora, '%H:%i') AS hora, ev.titulo AS titulo, ev.detalle AS detalle, ev.badge AS badge, ev.tono AS tono
    FROM   tmp_jf_ev ev ORDER BY ev.hora, ev.id;

    DROP TEMPORARY TABLE IF EXISTS tmp_jf_ev;
    DROP TEMPORARY TABLE IF EXISTS tmp_jf_alc;
    CALL SP_LimpiarSeguimientoOperativo();
END$$

DELIMITER ;

-- ############################################################
-- SP_RegistrarSeguimientoJefaturaMovil
-- ############################################################
-- ============================================================
-- SP_RegistrarSeguimientoJefaturaMovil  (App Mobile HU-30 — escritura: "Cambiar estado operativo" y "Avisar al cliente")
-- El jefe registra, desde la app, un cambio manual de estado del servicio o el aviso que dio al cliente. NO duplica reglas: valida que el servicio sea de su alcance
-- (SP_ResolverJefaturaMovil + SP_ArmarAlcanceJefaturaMovil) y delega la escritura en SP_RegistrarAsistenteServicioRuta (HU-53), que ya hace TODO lo demás:
-- permiso seg_registrar (y seg_bandeja), servicio de hoy y no finalizado, solo avanzar de estado, motivo del catálogo MOTIVO_CAMBIO_MANUAL, comentario obligatorio
-- (10 a 1000 caracteres), evento de campo del técnico, auditoría en la OS y el expediente (con el usuario y la hora), aviso a Jefatura, antiduplicado (15 s) y
-- límite de frecuencia, todo en una transacción con candado por usuario.
--   p_modo = cambio_estado : p_nuevo_estado (salida | en_ruta | llegada | ingreso | inicio | finalizado), p_id_motivo, p_texto = comentario (10 a 1000).
--   p_modo = aviso_cliente : p_texto = lo que se le avisó al cliente (5 a 450). Queda como NOTA del seguimiento ("Aviso al cliente (app de Jefatura): …") en el historial
--                            del servicio. NO envía correos ni mensajes: el aviso al cliente lo hace el jefe por llamada o mensaje y aquí solo se deja constancia.
-- Resultados: 1 mensaje (1 regla de negocio · 2 éxito · 3 error) · 2 (solo éxito) IdRegistro, Modo, Notificados, EstadoNuevo — los de SP_RegistrarAsistenteServicioRuta.
-- Requiere las migraciones 90 a 92.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_RegistrarSeguimientoJefaturaMovil;

DELIMITER $$

CREATE PROCEDURE SP_RegistrarSeguimientoJefaturaMovil(
    IN p_id_usuario   BIGINT,
    IN p_id_os        BIGINT,
    IN p_modo         VARCHAR(20)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_nuevo_estado VARCHAR(20)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_motivo    INT,
    IN p_texto        VARCHAR(1000) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_area        VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_sede        VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_aut_area    VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_aut_general TINYINT DEFAULT 0;
    DECLARE v_en_alcance  INT DEFAULT 0;
    DECLARE v_texto       VARCHAR(1000) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_jf_alc;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SET v_texto = TRIM(IFNULL(p_texto, ''));
    IF IFNULL(p_id_os, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El servicio indicado no es válido.' AS Mensaje;
        LEAVE proc;
    ELSEIF IFNULL(p_modo, '') NOT IN ('cambio_estado', 'aviso_cliente') THEN
        SELECT 1 AS IdTipoMensaje, 'El tipo de registro no es válido.' AS Mensaje;
        LEAVE proc;
    ELSEIF p_modo = 'cambio_estado' AND IFNULL(p_nuevo_estado, '') NOT IN ('salida', 'en_ruta', 'llegada', 'ingreso', 'inicio', 'finalizado') THEN
        SELECT 1 AS IdTipoMensaje, 'El nuevo estado no es válido.' AS Mensaje;
        LEAVE proc;
    ELSEIF p_modo = 'cambio_estado' AND IFNULL(p_id_motivo, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Elige el motivo del cambio.' AS Mensaje;
        LEAVE proc;
    ELSEIF p_modo = 'cambio_estado' AND CHAR_LENGTH(v_texto) < 10 THEN
        SELECT 1 AS IdTipoMensaje, 'El comentario es obligatorio (mínimo 10 caracteres).' AS Mensaje;
        LEAVE proc;
    ELSEIF p_modo = 'cambio_estado' AND CHAR_LENGTH(v_texto) > 1000 THEN
        SELECT 1 AS IdTipoMensaje, 'El comentario no puede superar los 1000 caracteres.' AS Mensaje;
        LEAVE proc;
    ELSEIF p_modo = 'aviso_cliente' AND CHAR_LENGTH(v_texto) < 5 THEN
        SELECT 1 AS IdTipoMensaje, 'Escribe lo que se le avisó al cliente (mínimo 5 caracteres).' AS Mensaje;
        LEAVE proc;
    ELSEIF p_modo = 'aviso_cliente' AND CHAR_LENGTH(v_texto) > 450 THEN
        SELECT 1 AS IdTipoMensaje, 'El aviso no puede superar los 450 caracteres.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_ResolverJefaturaMovil(p_id_usuario, v_area, v_sede, v_aut_area, v_aut_general);
    IF v_area IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Tu cargo no tiene el menú de Jefatura.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- El servicio debe ser de su alcance (misma regla del menú y del Panel de Campo)
    CALL SP_ArmarAlcanceJefaturaMovil(v_area, p_id_os);
    SELECT COUNT(*) INTO v_en_alcance FROM tmp_jf_alc WHERE id_os = p_id_os;
    DROP TEMPORARY TABLE IF EXISTS tmp_jf_alc;
    IF v_en_alcance = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El servicio no existe o no pertenece a tu área.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF p_modo = 'cambio_estado' THEN
        CALL SP_RegistrarAsistenteServicioRuta(p_id_usuario, p_id_os, 'cambio_estado', NULL, NULL, NULL, NULL, NULL, NULL, NULL, p_nuevo_estado, p_id_motivo, v_texto);
    ELSE
        CALL SP_RegistrarAsistenteServicioRuta(p_id_usuario, p_id_os, 'observacion', CONCAT('Aviso al cliente (app de Jefatura): ', v_texto), NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL);
    END IF;
END$$

DELIMITER ;

-- ============================================================
-- COMPROBACIÓN (solo lectura, no modifica datos)
-- ============================================================
-- A) Procedimientos con la fecha/hora de hoy (deben ser 9)
SELECT ROUTINE_NAME AS procedimiento, LAST_ALTERED AS actualizado FROM INFORMATION_SCHEMA.ROUTINES
WHERE ROUTINE_SCHEMA = DATABASE() AND ROUTINE_NAME IN ('SP_ResolverJefaturaMovil', 'SP_ArmarAlcanceJefaturaMovil', 'SP_FiltrarServiciosJefaturaMovil', 'SP_ObtenerMenuJefaturaMovil',
      'SP_ObtenerPanelCampoMovil', 'SP_ObtenerServiciosJefaturaMovil', 'SP_ObtenerServicioJefaturaMovil', 'SP_ObtenerRutaServicioJefaturaMovil', 'SP_RegistrarSeguimientoJefaturaMovil')
ORDER BY ROUTINE_NAME;

-- B) Un usuario sin menú de Jefatura: "Tu cargo no tiene el menú de Jefatura." (menú y panel)
CALL SP_ObtenerMenuJefaturaMovil(0);
CALL SP_ObtenerPanelCampoMovil(0);

-- C) El primer jefe activo (o supervisor / administrador con área) y un servicio de HOY
SET @jefe = (SELECT id_usuario FROM usuario
             WHERE estado = 'activo' AND eliminado_en IS NULL
               AND (cargo LIKE 'jefe_%' OR (rol_sistema IN ('supervisor', 'administrador') AND IFNULL(area, '') <> ''))
             ORDER BY id_usuario LIMIT 1);
SET @os = (SELECT id_os FROM orden_servicio WHERE eliminado_en IS NULL AND fecha_ejecucion = DATE(UTC_TIMESTAMP() - INTERVAL 5 HOUR) ORDER BY id_os LIMIT 1);
SELECT @jefe AS jefe, @os AS servicio_de_hoy;

-- D) Menú (los contadores de programados, en ruta, en ejecución y con demora no deben haber cambiado respecto a antes de este script)
CALL SP_ObtenerMenuJefaturaMovil(@jefe);

-- E) Panel de Campo: 1 mensaje · 2 KPIs · 3 pines · 4 alertas
CALL SP_ObtenerPanelCampoMovil(@jefe);

-- F) Servicios activos: 1 mensaje · 2 chips · 3 servicios. Luego con filtro y búsqueda
CALL SP_ObtenerServiciosJefaturaMovil(@jefe, 'activos', NULL);
CALL SP_ObtenerServiciosJefaturaMovil(@jefe, 'demora', '');
CALL SP_ObtenerServiciosJefaturaMovil(@jefe, 'otro', NULL);   -- "El filtro de servicios no es válido."

-- G) Detalle y ruta de un servicio de hoy (si @os es NULL, no hay servicios hoy: "El servicio indicado no es válido.")
CALL SP_ObtenerServicioJefaturaMovil(@jefe, @os);
CALL SP_ObtenerRutaServicioJefaturaMovil(@jefe, @os);

-- H) Registro con datos inválidos: solo valida, NO escribe nada (comentario de menos de 10 caracteres / aviso corto)
CALL SP_RegistrarSeguimientoJefaturaMovil(@jefe, @os, 'cambio_estado', 'salida', 1, 'corto');
CALL SP_RegistrarSeguimientoJefaturaMovil(@jefe, @os, 'aviso_cliente', NULL, NULL, 'ok');
