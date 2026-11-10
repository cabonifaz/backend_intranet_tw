-- ============================================================
-- SP_ObtenerMenuJefaturaMovil  (App Mobile HU-28 — Menú de Jefatura)
-- Resumen del día para quien tiene el menú de Jefatura en la app. Es UN SOLO menú para todos los jefes de área:
--   · cargo "Jefe de …" (CARGO_USUARIO jefe_*: Servicio Técnico, Metrología, Operaciones…), o
--   · rol SUPERVISOR / ADMINISTRADOR con un área definida (cualquier área, incluida Servicio Técnico).
-- Los técnicos, metrólogos y usuarios comunes reciben un mensaje y la app les muestra el menú de campo.
-- El área del jefe sale de su ficha (usuario.area) o, si no la tiene, del catálogo del cargo (CARGO_USUARIO.String3).
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

    SELECT IF(u.cargo LIKE 'jefe\_%',
              COALESCE(NULLIF(u.area, ''), NULLIF(c.String3, ''), SUBSTRING(u.cargo, 6)),
              IF(u.rol_sistema IN ('supervisor', 'administrador') AND IFNULL(u.area, '') <> '', u.area, NULL)),
           s.String1,
           COALESCE(IF(c.String2 LIKE 'jefe\_%' AND c.String3 IN ('servicio_tecnico', 'metrologia'), c.String3, NULL),
                    IF(u.rol_sistema = 'supervisor' AND u.area = 'metrologia', 'metrologia', NULL)),
           (u.cargo IN ('jefe_operaciones', 'coordinador_operaciones') OR u.rol_sistema IN ('administrador', 'admin')
            OR (u.rol_sistema = 'supervisor' AND u.area = 'operaciones'))
    INTO   v_area, v_sede, v_aut_area, v_aut_general
    FROM   usuario u
    LEFT JOIN tabla_maestra c ON c.IdMaestro = 80 AND c.IdEmpresa = 1 AND c.String2 = u.cargo
    LEFT JOIN tabla_maestra s ON s.IdMaestro = 69 AND s.IdEmpresa = 1 AND s.String2 = u.sede_operativa
    WHERE  u.id_usuario = p_id_usuario AND u.eliminado_en IS NULL AND u.estado = 'activo'
    LIMIT 1;

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

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    WITH os_area AS (
        SELECT os.id_os, os.estado
        FROM   orden_servicio os
        WHERE  os.eliminado_en IS NULL
          AND  os.estado IN ('programada', 'reprogramada', 'en_ruta', 'en_ejecucion', 'pausada', 'bloqueada')
          AND  os.fecha_ejecucion = v_hoy
          AND  (v_area NOT IN ('metrologia', 'servicio_tecnico')
                OR EXISTS (SELECT 1
                           FROM   expediente_digital ed
                           JOIN   requerimiento      rq  ON rq.id_requerimiento = ed.id_requerimiento
                           JOIN   area_servicio_rq   asr ON asr.id_area_rq      = rq.id_area
                           WHERE  ed.id_expediente = os.id_expediente AND asr.area_usuario = v_area))
    )
    SELECT v_area                                                           AS area_codigo,
           (SELECT t.String1 FROM tabla_maestra t
            WHERE  t.IdMaestro = 79 AND t.IdEmpresa = 1 AND t.String2 = v_area LIMIT 1) AS area_nombre,
           v_sede                                                           AS sede,
           COUNT(*)                                                         AS programados,
           IFNULL(SUM(estado = 'en_ruta'), 0)                               AS en_ruta,
           IFNULL(SUM(estado IN ('en_ejecucion', 'pausada')), 0)            AS en_ejecucion,
           (SELECT COUNT(DISTINCT d.id_os)
            FROM   demora_registro d
            WHERE  d.eliminado_en IS NULL AND DATE(d.fecha_registro) = v_hoy
              AND  d.id_os IN (SELECT o.id_os FROM os_area o))              AS con_demora,
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
           v_gastos                                                         AS viaticos_por_revisar
    FROM   os_area;
END$$

DELIMITER ;
