-- ============================================================
-- SP_ObtenerAprobacionesExtraMovil  (App Mobile HU-31 — bandeja del jefe: evidencias forzadas, ensayos con error y gastos · lectura)
-- Se suma a las salidas y llegadas forzadas que ya arma ObtenerAprobacionesMovilCasoDeUso, con el MISMO formato de ítem:
--   tipo, id, titulo, numero_os, tecnico, cliente, detalle, fecha_ejecucion, hora_inicio, urgente, solicitada_en
--   evidencia: id = id_evidencia. Forzada (HU-12), vigente y sin revisar (migración 113). Ve: encargado del área de la RQ, supervisión general, administrador.
--   ensayo   : id = id_informe. Guardado con error crítico y sin revisar. Mismas personas que la evidencia. Urgente (el técnico espera para cerrar).
--   gasto    : id = id_gasto. Gasto rendido 'pendiente' de una programación confirmada con la rendición abierta. Solo quien revisa gastos
--              (prog_aprobar_reprogramacion: el Jefe de Operaciones).
-- Urgente = el servicio es de hoy (o, en el ensayo, siempre). Solo OS no anuladas. Máximo 200 filas. Requiere las migraciones 113 y 114.
-- Resultados: 1 mensaje · 2 ítems.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerAprobacionesExtraMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerAprobacionesExtraMovil(
    IN p_id_usuario BIGINT
)
proc: BEGIN
    DECLARE v_area_jefe VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_general   TINYINT DEFAULT 0;
    DECLARE v_existe    TINYINT DEFAULT 0;
    DECLARE v_gastos    TINYINT DEFAULT 0;
    DECLARE v_hoy       DATE;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_apx;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SET v_hoy = DATE(UTC_TIMESTAMP() - INTERVAL 5 HOUR);

    SELECT 1,
           COALESCE(IF(c.String2 LIKE 'jefe\_%' AND c.String3 IN ('servicio_tecnico', 'metrologia'), c.String3, NULL),
                    IF(u.rol_sistema = 'supervisor' AND u.area = 'metrologia', 'metrologia', NULL)),
           (u.cargo IN ('jefe_operaciones', 'coordinador_operaciones') OR u.rol_sistema IN ('administrador', 'admin')
            OR (u.rol_sistema = 'supervisor' AND u.area = 'operaciones'))
    INTO   v_existe, v_area_jefe, v_general
    FROM   usuario u
    LEFT JOIN tabla_maestra c ON c.IdMaestro = 80 AND c.IdEmpresa = 1 AND c.String2 = u.cargo
    WHERE  u.id_usuario = p_id_usuario AND u.eliminado_en IS NULL AND u.estado = 'activo'
    LIMIT 1;

    IF v_existe = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no encontrado.' AS Mensaje;
        LEAVE proc;
    END IF;
    SET v_general = IFNULL(v_general, 0);
    SET v_gastos  = FN_PermisoAccion(p_id_usuario, 'prog_aprobar_reprogramacion');

    DROP TEMPORARY TABLE IF EXISTS tmp_apx;
    CREATE TEMPORARY TABLE tmp_apx (
        tipo            VARCHAR(12)  NOT NULL,
        id              BIGINT       NOT NULL,
        titulo          VARCHAR(200) NOT NULL,
        numero_os       VARCHAR(20)  NULL,
        tecnico         VARCHAR(210) NULL,
        cliente         VARCHAR(300) NULL,
        detalle         VARCHAR(500) NULL,
        fecha_ejecucion DATE         NULL,
        hora_inicio     VARCHAR(5)   NULL,
        urgente         TINYINT      NOT NULL DEFAULT 0,
        solicitada_en   DATETIME     NULL
    ) DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;

    -- Evidencias forzadas y ensayos con error: encargado del área de la RQ o supervisión general
    IF v_area_jefe IS NOT NULL OR v_general = 1 THEN
        INSERT INTO tmp_apx
        SELECT 'evidencia', f.id_evidencia,
               LEFT(CONCAT('Evidencia forzada: ', IFNULL(f.codigo, 'foto'), IF(IFNULL(f.pagina, 1) > 1, CONCAT(' (hoja ', f.pagina, ')'), '')), 200),
               os.numero,
               NULLIF(TRIM(CONCAT(IFNULL(t.nombre, ''), ' ', IFNULL(t.apellido, ''))), ''),
               COALESCE(NULLIF(cl.nombre_comercial, ''), cl.razon_social),
               LEFT(CONCAT_WS(' · ', IF(ec.codigo_tw IS NULL, NULL, CONCAT('Equipo ', ec.codigo_tw)),
                              IF(f.motivo_forzado IS NULL, NULL, CONCAT('motivo: ', f.motivo_forzado))), 500),
               os.fecha_ejecucion, TIME_FORMAT(os.hora_inicio, '%H:%i'),
               IF(os.fecha_ejecucion = v_hoy, 1, 0),
               COALESCE(f.forzada_en, f.timestamp_captura)
        FROM evidencia_fotografica f
        JOIN orden_servicio os ON os.id_os = f.id_os AND os.eliminado_en IS NULL AND os.estado <> 'anulada'
        LEFT JOIN cliente cl            ON cl.id_cliente = os.id_cliente
        LEFT JOIN equipo_cliente ec     ON ec.id_equipo = f.id_equipo
        LEFT JOIN usuario t             ON t.id_usuario = COALESCE(f.id_usuario_override, f.id_usuario)
        LEFT JOIN expediente_digital ed ON ed.id_expediente = os.id_expediente
        LEFT JOIN requerimiento rq      ON rq.id_requerimiento = ed.id_requerimiento
        LEFT JOIN area_servicio_rq asr  ON asr.id_area_rq = rq.id_area
        WHERE f.eliminado_en IS NULL AND f.override_aprobado = 1 AND f.vigente = 1 AND f.revision_jefe IS NULL
          AND (v_general = 1 OR asr.area_usuario IS NULL OR asr.area_usuario = v_area_jefe);

        INSERT INTO tmp_apx
        SELECT 'ensayo', it.id_informe,
               'Ensayo con error crítico',
               os.numero,
               NULLIF(TRIM(CONCAT(IFNULL(t.nombre, ''), ' ', IFNULL(t.apellido, ''))), ''),
               COALESCE(NULLIF(cl.nombre_comercial, ''), cl.razon_social),
               LEFT(CONCAT_WS(' · ', IF(ec.codigo_tw IS NULL, NULL, CONCAT('Equipo ', ec.codigo_tw)),
                              CONCAT((SELECT COUNT(*) FROM informe_ensayo ie WHERE ie.id_informe = it.id_informe AND ie.critico = 1 AND ie.eliminado_en IS NULL),
                                     ' lectura(s) fuera del EMP'),
                              CONCAT('motivo: ', it.error_critico_motivo)), 500),
               os.fecha_ejecucion, TIME_FORMAT(os.hora_inicio, '%H:%i'),
               1,
               COALESCE(it.error_critico_notificado_en, it.ensayos_finalizado_en, it.modificado_en, it.creado_en)
        FROM informe_tecnico it
        JOIN orden_servicio os ON os.id_os = it.id_os AND os.eliminado_en IS NULL AND os.estado <> 'anulada'
        LEFT JOIN cliente cl            ON cl.id_cliente = os.id_cliente
        LEFT JOIN equipo_cliente ec     ON ec.id_equipo = it.id_equipo
        LEFT JOIN usuario t             ON t.id_usuario = it.id_tecnico
        LEFT JOIN expediente_digital ed ON ed.id_expediente = os.id_expediente
        LEFT JOIN requerimiento rq      ON rq.id_requerimiento = ed.id_requerimiento
        LEFT JOIN area_servicio_rq asr  ON asr.id_area_rq = rq.id_area
        WHERE it.eliminado_en IS NULL AND it.error_critico_motivo IS NOT NULL AND it.error_critico_revision IS NULL
          AND (v_general = 1 OR asr.area_usuario IS NULL OR asr.area_usuario = v_area_jefe);
    END IF;

    -- Gastos pendientes: solo quien revisa gastos
    IF v_gastos = 1 THEN
        INSERT INTO tmp_apx
        SELECT 'gasto', g.id_gasto,
               LEFT(CONCAT('Gasto: ', IF(cg.String3 = 'OTRO' AND g.concepto_texto IS NOT NULL, g.concepto_texto, IFNULL(cg.String1, 'Concepto')),
                           ' S/ ', FORMAT(g.monto, 2)), 200),
               os.numero,
               NULLIF(TRIM(CONCAT(IFNULL(t.nombre, ''), ' ', IFNULL(t.apellido, ''))), ''),
               COALESCE(NULLIF(cl.nombre_comercial, ''), cl.razon_social),
               LEFT(CONCAT_WS(' · ', CONCAT('GS-', LPAD(g.id_gasto, 6, '0')), IF(g.origen = 'reembolso', 'reembolso', NULL),
                              IF(NULLIF(TRIM(IFNULL(g.url_comprobante, '')), '') IS NULL, 'sin foto', NULL),
                              IF(g.coincide_ia = 0, CONCAT('la IA leyó S/ ', FORMAT(g.monto_ia, 2)), NULL)), 500),
               os.fecha_ejecucion, TIME_FORMAT(os.hora_inicio, '%H:%i'),
               IF(os.fecha_ejecucion = v_hoy, 1, 0),
               COALESCE(g.modificado_en, g.creado_en)
        FROM gasto_viatico g
        JOIN orden_servicio os ON os.id_os = g.id_os AND os.eliminado_en IS NULL AND os.estado <> 'anulada'
        JOIN programacion pr   ON pr.id_programacion = COALESCE(g.id_programacion,
                                     (SELECT MAX(p2.id_programacion) FROM programacion p2
                                      WHERE p2.id_os = g.id_os AND p2.estado <> 'cancelada' AND p2.eliminado_en IS NULL))
                              AND pr.estado = 'confirmada' AND pr.eliminado_en IS NULL
        LEFT JOIN cliente cl       ON cl.id_cliente = os.id_cliente
        LEFT JOIN usuario t        ON t.id_usuario = g.id_usuario
        LEFT JOIN tabla_maestra cg ON cg.IdMaestro = 25 AND cg.IdEmpresa = 1 AND cg.Num1 = g.id_concepto
        WHERE g.tipo = 'gasto_solicitado' AND g.estado = 'pendiente' AND g.eliminado_en IS NULL
          AND NOT EXISTS (SELECT 1 FROM programacion_rendicion r WHERE r.id_programacion = pr.id_programacion AND r.eliminado_en IS NULL);
    END IF;

    SELECT 2 AS IdTipoMensaje, 'OK' AS Mensaje;
    SELECT tipo, id, titulo, numero_os, tecnico, cliente, detalle, fecha_ejecucion, hora_inicio, urgente, solicitada_en
    FROM tmp_apx
    ORDER BY urgente DESC, solicitada_en DESC
    LIMIT 200;
    DROP TEMPORARY TABLE IF EXISTS tmp_apx;
END$$

DELIMITER ;
