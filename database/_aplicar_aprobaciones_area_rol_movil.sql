-- Regla ÁREA + ROL en Aprobaciones, Alertas críticas y Notificaciones (quién las VE y quién las RECIBE, incluido el push). Orden: ver el resumen al final.
-- Gerencia, Operaciones, Administración, TI, SSOMA, Calidad, Comercial (cualquier rol) y Administradores = todo · Supervisor de Servicio Técnico / Metrología = solo su área · Usuario / Visor de ST / Metrología = nada.

-- ============================================================
-- SP_ResolverJefaturaMovil  (App Mobile HU-28 / HU-29 / HU-30 — apoyo, NO es un endpoint)
-- Resuelve UNA sola vez quién es el jefe y de qué área, para el menú de Jefatura y las pantallas del Panel de Campo / Seguimiento del servicio.
--   · cargo "Jefe de …" (CARGO_USUARIO jefe_*): su área sale de su ficha (usuario.area) o, si no la tiene, del catálogo del cargo (String3).
--   · cualquier usuario con un ÁREA definida que NO sea Servicio Técnico ni Metrología (Gerencia, Operaciones, Administración, TI, SSOMA, Calidad,
--     Comercial…): esa área, con CUALQUIER rol (Administrador, Supervisor, Usuario o Visor) — por descarte van a Jefatura (2026-11-18).
--     Un usuario sin área y sin cargo "Jefe de …" → p_area = NULL (menú de campo).
--   · EXCEPCIÓN (2026-11-18) — área Servicio Técnico o Metrología: manda el ROL. Administrador / Supervisor = Jefatura de esa área; Usuario / Visor =
--     p_area NULL (menú de campo: OS, u OM en Metrología), aunque el cargo sea "Jefe de …".
--   · Deja en la variable de sesión @tw_jf_alcance_total (1/0) si el jefe ve TODOS los servicios aunque su área sea Servicio Técnico o Metrología
--     (rol Administrador). La lee SP_ArmarAlcanceJefaturaMovil; siempre se llama a este SP antes que a ese.
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
    DECLARE v_rol VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;

    SET @tw_jf_alcance_total = 0;
    SET p_area = NULL;
    SET p_sede = NULL;
    SET p_aut_area = NULL;
    SET p_aut_general = 0;
    SET v_rol = NULL;

    SELECT IF(u.cargo LIKE 'jefe\_%',
              COALESCE(NULLIF(u.area, ''), NULLIF(c.String3, ''), SUBSTRING(u.cargo, 6)),
              NULLIF(u.area, '')),
           s.String1,
           COALESCE(IF(c.String2 LIKE 'jefe\_%' AND c.String3 IN ('servicio_tecnico', 'metrologia'), c.String3, NULL),
                    IF(u.rol_sistema = 'supervisor' AND u.area = 'metrologia', 'metrologia', NULL)),
           IFNULL(u.cargo IN ('jefe_operaciones', 'coordinador_operaciones') OR u.rol_sistema IN ('administrador', 'admin')
                  OR (u.rol_sistema = 'supervisor' AND u.area = 'operaciones'), 0),
           u.rol_sistema
    INTO   p_area, p_sede, p_aut_area, p_aut_general, v_rol
    FROM   usuario u
    LEFT JOIN tabla_maestra c ON c.IdMaestro = 80 AND c.IdEmpresa = 1 AND c.String2 = u.cargo
    LEFT JOIN tabla_maestra s ON s.IdMaestro = 69 AND s.IdEmpresa = 1 AND s.String2 = u.sede_operativa
    WHERE  u.id_usuario = p_id_usuario AND u.eliminado_en IS NULL AND u.estado = 'activo'
    LIMIT 1;

    -- Servicio Técnico y Metrología: manda el ROL principal de la plataforma. Administrador / Supervisor = Jefatura de esa área;
    -- Usuario / Visor = NO tiene Jefatura (va al menú de campo: hace las OS, o las OM en Metrología), aunque su cargo diga "Jefe de …".
    IF p_area IN ('servicio_tecnico', 'metrologia') AND IFNULL(v_rol, '') NOT IN ('supervisor', 'administrador') THEN
        SET p_area     = NULL;
        SET p_aut_area = NULL;
    END IF;

    -- Alcance de los servicios (lo lee SP_ArmarAlcanceJefaturaMovil, que se llama justo después con este mismo p_area):
    --   · Servicio Técnico / Metrología con rol SUPERVISOR → solo los servicios de su área (OS en ST, OM en Metrología).
    --   · Servicio Técnico / Metrología con rol ADMINISTRADOR → TODOS los servicios, como las demás áreas.
    --   · Las demás áreas (Gerencia, Operaciones, Administración, TI, SSOMA, Calidad, Comercial) ya ven todo.
    SET @tw_jf_alcance_total = IF(p_area IN ('servicio_tecnico', 'metrologia') AND IFNULL(v_rol, '') IN ('administrador', 'admin'), 1, 0);

    -- Aprobaciones (p_aut_area / p_aut_general): la MISMA regla Área + Rol. General = ve las de todas las áreas; p_aut_area = Supervisor de ST / Metrología (solo la suya).
    SET p_aut_area    = IF(p_area IN ('servicio_tecnico', 'metrologia') AND @tw_jf_alcance_total = 0, p_area, NULL);
    SET p_aut_general = IF((p_area IS NOT NULL AND (p_area NOT IN ('servicio_tecnico', 'metrologia') OR @tw_jf_alcance_total = 1))
                           OR IFNULL(v_rol, '') IN ('administrador', 'admin'), 1, 0);
END$$

DELIMITER ;

-- ============================================================
-- SP_ResolverAprobadorMovil  (App Mobile — apoyo, NO es un endpoint)
-- Qué aprobaciones ve un usuario, con la regla Área + Rol de SP_ResolverJefaturaMovil (2026-11-18):
--   p_general   = 1 → ve las de TODAS las áreas (cualquier rol en Gerencia, Operaciones, Administración, TI, SSOMA, Calidad, Comercial…; o Administrador).
--   p_area_jefe     → 'servicio_tecnico' | 'metrologia' si es Supervisor de esa área: solo las de su área.
--   Ambos vacíos    → no ve aprobaciones (Usuario / Visor de Servicio Técnico o Metrología, o sin área).
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ResolverAprobadorMovil;

DELIMITER $$

CREATE PROCEDURE SP_ResolverAprobadorMovil(
    IN  p_id_usuario BIGINT,
    OUT p_area_jefe  VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    OUT p_general    TINYINT
)
BEGIN
    DECLARE v_area     VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_sede     VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_aut_area VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_aut_gen  TINYINT DEFAULT 0;

    SET p_area_jefe = NULL;
    SET p_general   = 0;

    CALL SP_ResolverJefaturaMovil(p_id_usuario, v_area, v_sede, v_aut_area, v_aut_gen);

    IF v_area IS NOT NULL THEN
        IF v_area IN ('servicio_tecnico', 'metrologia') AND IFNULL(@tw_jf_alcance_total, 0) = 0 THEN
            SET p_area_jefe = v_area;      -- Supervisor de ST / Metrología: solo su área
        ELSE
            SET p_general = 1;             -- otras áreas (cualquier rol) o Administrador de ST / Metrología
        END IF;
    END IF;

    -- Un Administrador sin área sigue viendo todo (como antes)
    IF EXISTS (SELECT 1 FROM usuario u WHERE u.id_usuario = p_id_usuario AND u.eliminado_en IS NULL AND u.estado = 'activo'
                 AND u.rol_sistema IN ('administrador', 'admin')) THEN
        SET p_general   = 1;
        SET p_area_jefe = NULL;
    END IF;
END$$

DELIMITER ;

-- ============================================================
-- SP_ArmarAprobadoresMovil  (App Mobile — apoyo, NO es un endpoint)
-- Deja en la tabla temporal `tmp_aprobadores` (id_usuario) a quienes deben VER y recibir aviso (aprobaciones, alertas críticas, notificaciones de
-- Jefatura) de un servicio de la área p_area (servicio_tecnico | metrologia | NULL = la RQ no indica área). MISMA regla de SP_ResolverJefaturaMovil (2026-11-18):
--   · Área distinta de Servicio Técnico / Metrología (Gerencia, Operaciones, Administración, TI, SSOMA, Calidad, Comercial…), CUALQUIER rol → ven TODO.
--   · Servicio Técnico / Metrología con rol Administrador → ven TODO.
--   · Servicio Técnico / Metrología con rol Supervisor → solo los servicios de SU área (con p_area NULL, de cualquiera de las dos).
--   · Servicio Técnico / Metrología con rol Usuario o Visor → nada (van al menú de campo).
--   · Un Administrador sin área sigue viéndolo todo (como antes).
-- Quien la llame debe terminar con DROP TEMPORARY TABLE IF EXISTS tmp_aprobadores. Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ArmarAprobadoresMovil;

DELIMITER $$

CREATE PROCEDURE SP_ArmarAprobadoresMovil(
    IN p_area VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
BEGIN
    DROP TEMPORARY TABLE IF EXISTS tmp_aprobadores;
    CREATE TEMPORARY TABLE tmp_aprobadores (id_usuario BIGINT NOT NULL, PRIMARY KEY (id_usuario));

    INSERT IGNORE INTO tmp_aprobadores (id_usuario)
    SELECT x.id_usuario
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
       OR (x.area_efectiva IN ('servicio_tecnico', 'metrologia') AND x.rol_sistema = 'supervisor'
           AND (p_area IS NULL OR x.area_efectiva = p_area));
END$$

DELIMITER ;

-- ============================================================
-- SP_ArmarAprobadoresOsMovil  (App Mobile — apoyo, NO es un endpoint)
-- Igual que SP_ArmarAprobadoresMovil pero a partir de la OS: toma el área de su RQ (area_servicio_rq.area_usuario) y deja en `tmp_aprobadores` a quienes
-- deben ver y recibir los avisos de ESE servicio. Quien la llame debe terminar con DROP TEMPORARY TABLE IF EXISTS tmp_aprobadores. Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ArmarAprobadoresOsMovil;

DELIMITER $$

CREATE PROCEDURE SP_ArmarAprobadoresOsMovil(
    IN p_id_os BIGINT
)
BEGIN
    DECLARE v_area VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;

    SELECT asr.area_usuario INTO v_area
    FROM   orden_servicio os
    JOIN   expediente_digital ed ON ed.id_expediente    = os.id_expediente
    JOIN   requerimiento      rq ON rq.id_requerimiento = ed.id_requerimiento
    JOIN   area_servicio_rq  asr ON asr.id_area_rq      = rq.id_area
    WHERE  os.id_os = p_id_os
    LIMIT 1;

    CALL SP_ArmarAprobadoresMovil(v_area);
END$$

DELIMITER ;

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

    SELECT COUNT(*) INTO v_existe FROM usuario u
    WHERE  u.id_usuario = p_id_usuario AND u.eliminado_en IS NULL AND u.estado = 'activo';
    -- Regla Área + Rol (SP_ResolverAprobadorMovil): otras áreas con cualquier rol y Administradores ven todo; Supervisor de ST / Metrología, solo su área
    CALL SP_ResolverAprobadorMovil(p_id_usuario, v_area_jefe, v_general);

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
               CONVERT_TZ(COALESCE(f.forzada_en, f.timestamp_captura), '+00:00', '-05:00')
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

-- ============================================================
-- SP_ObtenerAprobacionDetalleMovil  (App Mobile HU-31 — detalle de una evidencia forzada, un ensayo con error o un gasto para el jefe · lectura)
--   p_tipo: evidencia (id = id_evidencia) | ensayo (id = id_informe) | gasto (id = id_gasto).
--   Ver y resolver evidencia/ensayo: encargado del área de la RQ, supervisión general (Jefe/Coordinador de Operaciones, supervisor de Operaciones) o
--   administrador. Gasto: solo quien revisa gastos (prog_aprobar_reprogramacion). A quien no corresponde se le responde como si no existiera.
--   puede_resolver: sigue pendiente (gasto: pendiente u observado, programación confirmada y rendición abierta).
-- Resultados: 1 mensaje · 2 cabecera (1 fila; columnas que no aplican al tipo van en NULL) ·
--   3 líneas: gasto = reparto (id_viatico_linea, concepto, monto, asignado); ensayo = lecturas fuera del EMP (tipo, punto, carga, lectura, error, tolerancia);
--     evidencia = sin filas ·
--   4 fotos: orden, es_video, tiene_cuadro (gasto: sus fotos; evidencia: la toma; ensayo: sin filas). El archivo se pide por
--     GET api/movil/aprobaciones/evidencias/{id}/archivo[?cuadro=true] o GET api/movil/aprobaciones/gastos/{id}/fotos/{orden}.
--   Requiere las migraciones 113 y 114.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerAprobacionDetalleMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerAprobacionDetalleMovil(
    IN p_id_usuario BIGINT,
    IN p_tipo       VARCHAR(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id         BIGINT
)
proc: BEGIN
    DECLARE v_tipo      VARCHAR(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_area_jefe VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_general   TINYINT DEFAULT 0;
    DECLARE v_id_os     BIGINT;
    DECLARE v_area_os   VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_ve        TINYINT DEFAULT 0;
    DECLARE v_prog      BIGINT;
    DECLARE v_abierta   TINYINT DEFAULT 0;
    DECLARE v_noexiste  VARCHAR(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
                        DEFAULT 'No se encontró la aprobación o no corresponde a tu área.';

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SET v_tipo = LOWER(TRIM(IFNULL(p_tipo, '')));
    IF v_tipo NOT IN ('evidencia', 'ensayo', 'gasto') OR IFNULL(p_id, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, v_noexiste AS Mensaje;
        LEAVE proc;
    END IF;

    -- Regla Área + Rol (SP_ResolverAprobadorMovil)
    CALL SP_ResolverAprobadorMovil(p_id_usuario, v_area_jefe, v_general);
    SET v_general = IFNULL(v_general, 0);

    IF v_tipo = 'evidencia' THEN
        SELECT MAX(id_os) INTO v_id_os FROM evidencia_fotografica WHERE id_evidencia = p_id AND override_aprobado = 1 AND eliminado_en IS NULL;
    ELSEIF v_tipo = 'ensayo' THEN
        SELECT MAX(id_os) INTO v_id_os FROM informe_tecnico WHERE id_informe = p_id AND error_critico_motivo IS NOT NULL AND eliminado_en IS NULL;
    ELSE
        SELECT MAX(id_os) INTO v_id_os FROM gasto_viatico WHERE id_gasto = p_id AND tipo = 'gasto_solicitado' AND eliminado_en IS NULL;
    END IF;
    IF v_id_os IS NULL THEN
        SELECT 1 AS IdTipoMensaje, v_noexiste AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT asr.area_usuario INTO v_area_os
    FROM orden_servicio os
    LEFT JOIN expediente_digital ed ON ed.id_expediente = os.id_expediente
    LEFT JOIN requerimiento rq      ON rq.id_requerimiento = ed.id_requerimiento
    LEFT JOIN area_servicio_rq asr  ON asr.id_area_rq = rq.id_area
    WHERE os.id_os = v_id_os;

    IF v_tipo = 'gasto' THEN
        SET v_ve = FN_PermisoAccion(p_id_usuario, 'prog_aprobar_reprogramacion');
        SELECT COALESCE(g.id_programacion, (SELECT MAX(p2.id_programacion) FROM programacion p2
                                            WHERE p2.id_os = g.id_os AND p2.estado <> 'cancelada' AND p2.eliminado_en IS NULL))
          INTO v_prog FROM gasto_viatico g WHERE g.id_gasto = p_id;
        SET v_abierta = IF(EXISTS (SELECT 1 FROM programacion WHERE id_programacion = v_prog AND estado = 'confirmada' AND eliminado_en IS NULL)
                           AND NOT EXISTS (SELECT 1 FROM programacion_rendicion WHERE id_programacion = v_prog AND eliminado_en IS NULL), 1, 0);
    ELSE
        SET v_ve = IF(v_general = 1 OR (v_area_jefe IS NOT NULL AND (v_area_os IS NULL OR v_area_os = v_area_jefe)), 1, 0);
    END IF;
    IF v_ve = 0 THEN
        SELECT 1 AS IdTipoMensaje, v_noexiste AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'OK' AS Mensaje;

    -- 2. Cabecera
    IF v_tipo = 'evidencia' THEN
        SELECT 'evidencia' AS tipo, f.id_evidencia AS id,
               CONCAT('Evidencia forzada: ', IFNULL(f.codigo, 'foto')) AS titulo,
               IFNULL(f.revision_jefe, 'pendiente') AS estado,
               os.id_os, os.numero AS numero_os, COALESCE(NULLIF(cl.nombre_comercial, ''), cl.razon_social) AS cliente, sc.nombre AS sede,
               NULLIF(TRIM(CONCAT(IFNULL(t.nombre, ''), ' ', IFNULL(t.apellido, ''))), '') AS tecnico,
               os.fecha_ejecucion, TIME_FORMAT(os.hora_inicio, '%H:%i') AS hora_inicio,
               CONVERT_TZ(COALESCE(f.forzada_en, f.timestamp_captura), '+00:00', '-05:00') AS solicitada_en,
               f.motivo_forzado AS motivo,
               CONCAT_WS(' · ', IF(ec.codigo_tw IS NULL, NULL, CONCAT('Equipo ', ec.codigo_tw)), IF(IFNULL(f.pagina, 1) > 1, CONCAT('hoja ', f.pagina), NULL)) AS detalle,
               f.comentario_jefe AS comentario,
               NULLIF(TRIM(CONCAT(IFNULL(j.nombre, ''), ' ', IFNULL(j.apellido, ''))), '') AS resuelto_por, f.revisado_jefe_en AS resuelto_en,
               IF(f.revision_jefe IS NULL, 1, 0) AS puede_resolver,
               f.codigo AS codigo_evidencia, f.motivo_rechazo_ia, f.es_video, ec.codigo_tw AS equipo,
               CAST(NULL AS SIGNED) AS n_criticas,
               CAST(NULL AS CHAR(20)) AS codigo, CAST(NULL AS CHAR(10)) AS origen, CAST(NULL AS CHAR(100)) AS concepto,
               CAST(NULL AS DECIMAL(12,2)) AS monto, CAST(NULL AS DATE) AS fecha_gasto, CAST(NULL AS CHAR(300)) AS descripcion,
               CAST(NULL AS CHAR(300)) AS motivo_sin_foto, CAST(NULL AS DECIMAL(12,2)) AS monto_ia, CAST(NULL AS SIGNED) AS coincide_ia,
               CAST(NULL AS CHAR(20)) AS codigo_programacion
        FROM evidencia_fotografica f
        JOIN orden_servicio os      ON os.id_os = f.id_os
        LEFT JOIN cliente cl        ON cl.id_cliente = os.id_cliente
        LEFT JOIN sede_cliente sc   ON sc.id_sede = os.id_sede
        LEFT JOIN equipo_cliente ec ON ec.id_equipo = f.id_equipo
        LEFT JOIN usuario t         ON t.id_usuario = COALESCE(f.id_usuario_override, f.id_usuario)
        LEFT JOIN usuario j         ON j.id_usuario = f.revisado_jefe_por
        WHERE f.id_evidencia = p_id;

        SELECT CAST(NULL AS SIGNED) AS id_viatico_linea FROM DUAL WHERE 1 = 0;

        SELECT 1 AS orden, f.es_video, IF(NULLIF(TRIM(IFNULL(f.ruta_cuadro, '')), '') IS NULL, 0, 1) AS tiene_cuadro
        FROM evidencia_fotografica f
        WHERE f.id_evidencia = p_id AND NULLIF(TRIM(IFNULL(f.url_archivo, '')), '') IS NOT NULL;

    ELSEIF v_tipo = 'ensayo' THEN
        SELECT 'ensayo' AS tipo, it.id_informe AS id,
               'Ensayo con error crítico' AS titulo,
               IFNULL(it.error_critico_revision, 'pendiente') AS estado,
               os.id_os, os.numero AS numero_os, COALESCE(NULLIF(cl.nombre_comercial, ''), cl.razon_social) AS cliente, sc.nombre AS sede,
               NULLIF(TRIM(CONCAT(IFNULL(t.nombre, ''), ' ', IFNULL(t.apellido, ''))), '') AS tecnico,
               os.fecha_ejecucion, TIME_FORMAT(os.hora_inicio, '%H:%i') AS hora_inicio,
               COALESCE(it.error_critico_notificado_en, it.ensayos_finalizado_en, it.modificado_en, it.creado_en) AS solicitada_en,
               it.error_critico_motivo AS motivo,
               IF(ec.codigo_tw IS NULL, NULL, CONCAT('Equipo ', ec.codigo_tw)) AS detalle,
               it.error_critico_comentario AS comentario,
               NULLIF(TRIM(CONCAT(IFNULL(j.nombre, ''), ' ', IFNULL(j.apellido, ''))), '') AS resuelto_por, it.error_critico_revisado_en AS resuelto_en,
               IF(it.error_critico_revision IS NULL, 1, 0) AS puede_resolver,
               CAST(NULL AS CHAR(20)) AS codigo_evidencia, CAST(NULL AS CHAR(300)) AS motivo_rechazo_ia, CAST(NULL AS SIGNED) AS es_video,
               ec.codigo_tw AS equipo,
               (SELECT COUNT(*) FROM informe_ensayo ie WHERE ie.id_informe = it.id_informe AND ie.critico = 1 AND ie.eliminado_en IS NULL) AS n_criticas,
               CAST(NULL AS CHAR(20)) AS codigo, CAST(NULL AS CHAR(10)) AS origen, CAST(NULL AS CHAR(100)) AS concepto,
               CAST(NULL AS DECIMAL(12,2)) AS monto, CAST(NULL AS DATE) AS fecha_gasto, CAST(NULL AS CHAR(300)) AS descripcion,
               CAST(NULL AS CHAR(300)) AS motivo_sin_foto, CAST(NULL AS DECIMAL(12,2)) AS monto_ia, CAST(NULL AS SIGNED) AS coincide_ia,
               CAST(NULL AS CHAR(20)) AS codigo_programacion
        FROM informe_tecnico it
        JOIN orden_servicio os      ON os.id_os = it.id_os
        LEFT JOIN cliente cl        ON cl.id_cliente = os.id_cliente
        LEFT JOIN sede_cliente sc   ON sc.id_sede = os.id_sede
        LEFT JOIN equipo_cliente ec ON ec.id_equipo = it.id_equipo
        LEFT JOIN usuario t         ON t.id_usuario = it.id_tecnico
        LEFT JOIN usuario j         ON j.id_usuario = it.error_critico_revisado_por
        WHERE it.id_informe = p_id;

        SELECT ie.tipo, ie.punto, ie.carga, ie.lectura, ie.error, ie.tolerancia
        FROM informe_ensayo ie
        WHERE ie.id_informe = p_id AND ie.critico = 1 AND ie.eliminado_en IS NULL
        ORDER BY ie.tipo, ie.orden, ie.id_ensayo;

        SELECT CAST(NULL AS SIGNED) AS orden FROM DUAL WHERE 1 = 0;

    ELSE
        SELECT 'gasto' AS tipo, g.id_gasto AS id,
               CONCAT('Gasto: ', IF(cg.String3 = 'OTRO' AND g.concepto_texto IS NOT NULL, g.concepto_texto, IFNULL(cg.String1, 'Concepto'))) AS titulo,
               g.estado,
               os.id_os, os.numero AS numero_os, COALESCE(NULLIF(cl.nombre_comercial, ''), cl.razon_social) AS cliente, sc.nombre AS sede,
               NULLIF(TRIM(CONCAT(IFNULL(t.nombre, ''), ' ', IFNULL(t.apellido, ''))), '') AS tecnico,
               os.fecha_ejecucion, TIME_FORMAT(os.hora_inicio, '%H:%i') AS hora_inicio,
               COALESCE(g.modificado_en, g.creado_en) AS solicitada_en,
               g.motivo_sin_foto AS motivo,
               IF(g.coincide_ia = 0, CONCAT('La IA leyó S/ ', FORMAT(g.monto_ia, 2), ' en la boleta.'), NULL) AS detalle,
               g.comentario_revision AS comentario,
               NULLIF(TRIM(CONCAT(IFNULL(j.nombre, ''), ' ', IFNULL(j.apellido, ''))), '') AS resuelto_por, g.revisado_en AS resuelto_en,
               IF(v_abierta = 1 AND g.estado IN ('pendiente', 'observado'), 1, 0) AS puede_resolver,
               CAST(NULL AS CHAR(20)) AS codigo_evidencia, CAST(NULL AS CHAR(300)) AS motivo_rechazo_ia, CAST(NULL AS SIGNED) AS es_video,
               CAST(NULL AS CHAR(30)) AS equipo, CAST(NULL AS SIGNED) AS n_criticas,
               CONCAT('GS-', LPAD(g.id_gasto, 6, '0')) AS codigo, g.origen,
               IF(cg.String3 = 'OTRO' AND g.concepto_texto IS NOT NULL, CONCAT('Otro: ', g.concepto_texto), IFNULL(cg.String1, 'Concepto')) AS concepto,
               g.monto, COALESCE(g.fecha_gasto, g.fecha_solicitud) AS fecha_gasto, g.descripcion, g.motivo_sin_foto, g.monto_ia, g.coincide_ia,
               pr.codigo AS codigo_programacion
        FROM gasto_viatico g
        JOIN orden_servicio os     ON os.id_os = g.id_os
        LEFT JOIN cliente cl       ON cl.id_cliente = os.id_cliente
        LEFT JOIN sede_cliente sc  ON sc.id_sede = os.id_sede
        LEFT JOIN usuario t        ON t.id_usuario = g.id_usuario
        LEFT JOIN usuario j        ON j.id_usuario = g.revisado_por
        LEFT JOIN tabla_maestra cg ON cg.IdMaestro = 25 AND cg.IdEmpresa = 1 AND cg.Num1 = g.id_concepto
        LEFT JOIN programacion pr  ON pr.id_programacion = v_prog
        WHERE g.id_gasto = p_id;

        SELECT rp.id_viatico_linea, IFNULL(cg.String1, 'Viático') AS concepto, rp.monto, l.monto AS asignado
        FROM gasto_viatico_reparto rp
        LEFT JOIN gasto_viatico l   ON l.id_gasto = rp.id_viatico_linea
        LEFT JOIN tabla_maestra cg  ON cg.IdMaestro = 25 AND cg.IdEmpresa = 1 AND cg.Num1 = l.id_concepto
        WHERE rp.id_gasto = p_id AND rp.eliminado_en IS NULL
        ORDER BY rp.id_reparto;

        SELECT x.orden, 0 AS es_video, 0 AS tiene_cuadro
        FROM (SELECT f.orden FROM gasto_viatico_foto f WHERE f.id_gasto = p_id AND f.eliminado_en IS NULL
              UNION
              SELECT 1 FROM gasto_viatico g2
              WHERE g2.id_gasto = p_id AND NULLIF(TRIM(IFNULL(g2.url_comprobante, '')), '') IS NOT NULL
                AND NOT EXISTS (SELECT 1 FROM gasto_viatico_foto f2 WHERE f2.id_gasto = p_id AND f2.eliminado_en IS NULL)) x
        ORDER BY x.orden;
    END IF;
END$$

DELIMITER ;

-- HU-52 (Sprint 5) Pestaña Aprobaciones del Detalle del Servicio en Ruta: una sola lista con todo lo que el encargado aprueba en esa OS. SOLO LECTURA.
--   salida    autorizacion_salida_os (App Mobile HU-04)
--   llegada   llegada_forzada_os (migración 111, HU-06)
--   (las evidencias fotográficas forzadas ya NO se listan aquí: se ven en Avance por equipos > Fotos)
--   ensayo    informe_tecnico guardado con error crítico (error_critico_motivo, migraciones 100 y 107); revisión en error_critico_revision (113)
-- Acceso: seg_bandeja y el servicio en la jornada de hoy (SP_PrepararDetalleServicioRuta), igual que las demás pestañas.
-- puede_resolver: misma regla de área que SP_ObtenerAutorizacionesSalida / SP_ResolverLlegadaForzada: el encargado del área de la solicitud (o de la RQ
--   si la solicitud no la tiene), Jefe o Coordinador de Operaciones, supervisor de Operaciones o administrador. Salida y llegada: solo la última
--   solicitud pendiente de la OS (los SP de resolver actúan sobre esa); la salida, además, mientras la OS siga programada.
-- Resultados: 1 mensaje · 2 aprobaciones · 3 totales (total, pendientes, aprobadas, rechazadas).
DROP PROCEDURE IF EXISTS SP_ObtenerAprobacionesServicioRuta;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerAprobacionesServicioRuta(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT
)
proc: BEGIN
    DECLARE v_msg         VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_area_jefe   VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_general     TINYINT DEFAULT 0;
    DECLARE v_area_os     VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado_os   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_ult_salida  BIGINT;
    DECLARE v_ult_llegada BIGINT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_apr;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    CALL SP_PrepararDetalleServicioRuta(p_id_usuario, p_id_os, v_msg);
    IF v_msg IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje;
        LEAVE proc;
    END IF;
    CALL SP_LimpiarSeguimientoOperativo();

    -- Quién consulta: encargado de un área (v_area_jefe) o supervisión general (v_general)
    -- Regla Área + Rol (SP_ResolverAprobadorMovil)
    CALL SP_ResolverAprobadorMovil(p_id_usuario, v_area_jefe, v_general);
    SET v_general = IFNULL(v_general, 0);

    -- Área de la OS (la de la RQ) y estado
    SELECT os.estado, asr.area_usuario INTO v_estado_os, v_area_os
    FROM   orden_servicio os
    LEFT JOIN expediente_digital ed  ON ed.id_expediente    = os.id_expediente
    LEFT JOIN requerimiento      rq  ON rq.id_requerimiento = ed.id_requerimiento
    LEFT JOIN area_servicio_rq   asr ON asr.id_area_rq      = rq.id_area
    WHERE  os.id_os = p_id_os;

    SELECT MAX(id_autorizacion) INTO v_ult_salida  FROM autorizacion_salida_os WHERE id_os = p_id_os AND eliminado_en IS NULL;
    SELECT MAX(id_solicitud)    INTO v_ult_llegada FROM llegada_forzada_os     WHERE id_os = p_id_os AND eliminado_en IS NULL;

    DROP TEMPORARY TABLE IF EXISTS tmp_apr;
    CREATE TEMPORARY TABLE tmp_apr (
        tipo           VARCHAR(12)  NOT NULL,
        id             BIGINT       NOT NULL,
        titulo         VARCHAR(200) NULL,
        solicitante    VARCHAR(210) NULL,
        solicitado_en  DATETIME     NULL,
        motivo         VARCHAR(500) NULL,
        detalle        VARCHAR(500) NULL,
        estado         VARCHAR(12)  NOT NULL,
        resuelto_por   VARCHAR(210) NULL,
        cargo          VARCHAR(150) NULL,
        resuelto_en    DATETIME     NULL,
        comentario     VARCHAR(500) NULL,
        urgente        TINYINT      NOT NULL DEFAULT 0,
        puede_resolver TINYINT      NOT NULL DEFAULT 0
    ) DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;

    -- Salida
    INSERT INTO tmp_apr
    SELECT 'salida', a.id_autorizacion, 'Autorización de salida',
           NULLIF(TRIM(CONCAT(IFNULL(t.nombre, ''), ' ', IFNULL(t.apellido, ''))), ''),
           a.solicitado_en, a.motivo, a.pendientes, a.estado,
           NULLIF(TRIM(CONCAT(IFNULL(j.nombre, ''), ' ', IFNULL(j.apellido, ''))), ''), IFNULL(cj.String1, NULLIF(j.cargo, '')),
           a.resuelto_en, a.comentario,
           IF(a.estado = 'pendiente', 1, 0),
           IF(a.estado = 'pendiente' AND a.id_autorizacion = v_ult_salida AND v_estado_os IN ('programada', 'reprogramada')
              AND (v_general = 1 OR (v_area_jefe IS NOT NULL
                                     AND (COALESCE(a.area_destino, v_area_os) IS NULL OR COALESCE(a.area_destino, v_area_os) = v_area_jefe))), 1, 0)
    FROM   autorizacion_salida_os a
    LEFT JOIN usuario t        ON t.id_usuario = a.id_tecnico
    LEFT JOIN usuario j        ON j.id_usuario = a.id_jefe
    LEFT JOIN tabla_maestra cj ON cj.IdMaestro = 80 AND cj.IdEmpresa = 1 AND cj.String2 = j.cargo
    WHERE  a.id_os = p_id_os AND a.eliminado_en IS NULL;

    -- Llegada forzada
    INSERT INTO tmp_apr
    SELECT 'llegada', s.id_solicitud, 'Llegada forzada',
           NULLIF(TRIM(CONCAT(IFNULL(t.nombre, ''), ' ', IFNULL(t.apellido, ''))), ''),
           s.solicitado_en, s.motivo,
           NULLIF(CONCAT_WS(' · ', IF(s.distancia_metros IS NULL, NULL, CONCAT('A ', s.distancia_metros, ' m de la planta')),
                                   IF(IFNULL(s.intentos, 0) = 0, NULL, CONCAT(s.intentos, ' capturas fuera de rango'))), ''),
           s.estado,
           NULLIF(TRIM(CONCAT(IFNULL(j.nombre, ''), ' ', IFNULL(j.apellido, ''))), ''), IFNULL(cj.String1, NULLIF(j.cargo, '')),
           s.resuelto_en, s.comentario,
           IF(s.estado = 'pendiente', 1, 0),
           IF(s.estado = 'pendiente' AND s.id_solicitud = v_ult_llegada
              AND (v_general = 1 OR (v_area_jefe IS NOT NULL AND (s.area_destino IS NULL OR s.area_destino = v_area_jefe))), 1, 0)
    FROM   llegada_forzada_os s
    LEFT JOIN usuario t        ON t.id_usuario = s.id_tecnico
    LEFT JOIN usuario j        ON j.id_usuario = s.id_jefe
    LEFT JOIN tabla_maestra cj ON cj.IdMaestro = 80 AND cj.IdEmpresa = 1 AND cj.String2 = j.cargo
    WHERE  s.id_os = p_id_os AND s.eliminado_en IS NULL;

    -- Las evidencias fotográficas forzadas NO se aprueban aquí: se ven en Avance por equipos > Fotos (marcadas como «Forzada por el técnico»).

    -- Ensayos guardados con error crítico
    INSERT INTO tmp_apr
    SELECT 'ensayo', it.id_informe,
           LEFT(CONCAT('Ensayo con error crítico', IF(ec.codigo_tw IS NULL, '', CONCAT(' · ', ec.codigo_tw))), 200),
           NULLIF(TRIM(CONCAT(IFNULL(t.nombre, ''), ' ', IFNULL(t.apellido, ''))), ''),
           COALESCE(it.error_critico_notificado_en, it.ensayos_finalizado_en, it.modificado_en, it.creado_en),
           it.error_critico_motivo,
           CONCAT((SELECT COUNT(*) FROM informe_ensayo ie WHERE ie.id_informe = it.id_informe AND ie.critico = 1 AND ie.eliminado_en IS NULL),
                  ' lectura(s) fuera del EMP'),
           IFNULL(it.error_critico_revision, 'pendiente'),
           NULLIF(TRIM(CONCAT(IFNULL(j.nombre, ''), ' ', IFNULL(j.apellido, ''))), ''), IFNULL(cj.String1, NULLIF(j.cargo, '')),
           it.error_critico_revisado_en, it.error_critico_comentario,
           IF(it.error_critico_revision IS NULL, 1, 0),
           IF(it.error_critico_revision IS NULL
              AND (v_general = 1 OR (v_area_jefe IS NOT NULL AND (v_area_os IS NULL OR v_area_os = v_area_jefe))), 1, 0)
    FROM   informe_tecnico it
    LEFT JOIN equipo_cliente ec ON ec.id_equipo = it.id_equipo
    LEFT JOIN usuario t         ON t.id_usuario = it.id_tecnico
    LEFT JOIN usuario j         ON j.id_usuario = it.error_critico_revisado_por
    LEFT JOIN tabla_maestra cj  ON cj.IdMaestro = 80 AND cj.IdEmpresa = 1 AND cj.String2 = j.cargo
    WHERE  it.id_os = p_id_os AND it.eliminado_en IS NULL AND it.error_critico_motivo IS NOT NULL;

    SELECT 2 AS IdTipoMensaje, 'OK' AS Mensaje;

    SELECT tipo, id, titulo, solicitante, solicitado_en, motivo, detalle, estado, resuelto_por, cargo, resuelto_en, comentario,
           urgente, puede_resolver
    FROM   tmp_apr
    ORDER BY (estado = 'pendiente') DESC, urgente DESC, solicitado_en DESC, id DESC;

    SELECT COUNT(*) AS total,
           IFNULL(SUM(estado = 'pendiente'), 0) AS pendientes,
           IFNULL(SUM(estado = 'aprobada'), 0)  AS aprobadas,
           IFNULL(SUM(estado = 'rechazada'), 0) AS rechazadas
    FROM   tmp_apr;

    DROP TEMPORARY TABLE IF EXISTS tmp_apr;
END$$

DELIMITER ;

-- ============================================================
-- SP_ObtenerAutorizacionesSalida  (Intranet · App Mobile HU-04)
-- Bandeja de solicitudes de visto bueno de salida de los técnicos.
--   p_estado: pendiente | aprobada | rechazada | (vacío = todas)
--   Encargado de área (Jefe de Servicio Técnico / Jefe de Metrología, o el supervisor del área Metrología): solo las de SU área
--   (y las que no tienen área en la RQ). Jefe/Coordinador de Operaciones, supervisor del área Operaciones y administradores: todas.
-- id_tecnico (última columna): quién la pidió; la app móvil del Jefe lo usa para mostrar el checklist de ese técnico.
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerAutorizacionesSalida;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerAutorizacionesSalida(
    IN p_id_usuario BIGINT,
    IN p_estado     VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_estado    VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_area_jefe VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_general   TINYINT DEFAULT 0;
    DECLARE v_existe    TINYINT DEFAULT 0;

    SELECT COUNT(*) INTO v_existe FROM usuario u
    WHERE  u.id_usuario = p_id_usuario AND u.eliminado_en IS NULL AND u.estado = 'activo';
    -- Regla Área + Rol (SP_ResolverAprobadorMovil): otras áreas con cualquier rol y Administradores ven todo; Supervisor de ST / Metrología, solo su área
    CALL SP_ResolverAprobadorMovil(p_id_usuario, v_area_jefe, v_general);

    IF v_existe = 0 OR (v_area_jefe IS NULL AND v_general = 0) THEN
        SELECT 1 AS IdTipoMensaje, 'Solo los encargados de Servicio Técnico y Metrología pueden ver las autorizaciones de salida.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_estado = LOWER(TRIM(IFNULL(p_estado, '')));
    IF v_estado NOT IN ('', 'pendiente', 'aprobada', 'rechazada') THEN
        SELECT 1 AS IdTipoMensaje, 'Estado no válido. Use pendiente, aprobada o rechazada.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT a.id_autorizacion,
           a.id_os,
           os.numero                                                        AS numero_os,
           COALESCE(NULLIF(cl.nombre_comercial, ''), cl.razon_social)       AS cliente,
           os.fecha_ejecucion,
           TIME_FORMAT(os.hora_inicio, '%H:%i')                             AS hora_inicio,
           os.estado                                                        AS estado_os,
           NULLIF(TRIM(CONCAT(IFNULL(tc.nombre, ''), ' ', IFNULL(tc.apellido, ''))), '') AS tecnico,
           a.motivo,
           a.pendientes,
           a.estado,
           a.area_destino,
           ar.String1                                                       AS area,
           a.solicitado_en,
           NULLIF(TRIM(CONCAT(IFNULL(jf.nombre, ''), ' ', IFNULL(jf.apellido, ''))), '') AS jefe,
           a.resuelto_en,
           a.comentario,
           a.id_tecnico
    FROM   autorizacion_salida_os a
    JOIN   orden_servicio os ON os.id_os = a.id_os AND os.eliminado_en IS NULL
    LEFT JOIN cliente cl ON cl.id_cliente = os.id_cliente
    LEFT JOIN usuario tc ON tc.id_usuario = a.id_tecnico
    LEFT JOIN usuario jf ON jf.id_usuario = a.id_jefe
    LEFT JOIN tabla_maestra ar ON ar.IdMaestro = 79 AND ar.IdEmpresa = 1 AND ar.String2 = a.area_destino
    WHERE  a.eliminado_en IS NULL
      AND  (v_estado = '' OR a.estado = v_estado)
      AND  (v_general = 1 OR a.area_destino IS NULL OR a.area_destino = v_area_jefe)
    ORDER BY (a.estado = 'pendiente') DESC, IFNULL(a.solicitado_en, a.creado_en) DESC
    LIMIT 200;
END$$

DELIMITER ;

-- ============================================================
-- SP_ObtenerLlegadasForzadas  (App Mobile HU-06 / HU-31 — bandeja de Aprobaciones del encargado · lectura)
-- Solicitudes de llegada forzada que puede ver el usuario (misma regla de áreas que las autorizaciones de salida):
--   encargado de área (Jefe de Servicio Técnico / Jefe de Metrología o supervisor de Metrología): las de SU área y las sin área en la RQ;
--   Jefe/Coordinador de Operaciones, supervisor de Operaciones y administradores: todas.
--   p_id_os = 0/NULL → las PENDIENTES (la bandeja). p_id_os > 0 → la más reciente de esa OS, en cualquier estado (el detalle).
-- Resultado: 1 mensaje · 2 filas (id_solicitud, id_os, numero_os, cliente, sede, fecha_ejecucion, hora_inicio, tecnico, estado, motivo, intentos,
--   latitud, longitud, precision_metros, distancia_m, lat_planta, lon_planta, radio_m, area_destino, area, solicitado_en, jefe, resuelto_en, comentario, usada_en).
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerLlegadasForzadas;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerLlegadasForzadas(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT
)
proc: BEGIN
    DECLARE v_area_jefe VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_general   TINYINT DEFAULT 0;
    DECLARE v_existe    TINYINT DEFAULT 0;
    DECLARE v_radio     DECIMAL(18,6);

    SELECT COUNT(*) INTO v_existe FROM usuario u
    WHERE  u.id_usuario = p_id_usuario AND u.eliminado_en IS NULL AND u.estado = 'activo';
    -- Regla Área + Rol (SP_ResolverAprobadorMovil): otras áreas con cualquier rol y Administradores ven todo; Supervisor de ST / Metrología, solo su área
    CALL SP_ResolverAprobadorMovil(p_id_usuario, v_area_jefe, v_general);

    IF v_existe = 0 OR (v_area_jefe IS NULL AND v_general = 0) THEN
        SELECT 1 AS IdTipoMensaje, 'Solo los encargados de Servicio Técnico y Metrología pueden ver las llegadas forzadas.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_LeerParametroProgramacion('LLEGADA_RADIO_METROS', 200, v_radio);

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT s.id_solicitud,
           s.id_os,
           os.numero                                                        AS numero_os,
           COALESCE(NULLIF(cl.nombre_comercial, ''), cl.razon_social)       AS cliente,
           COALESCE(NULLIF(sc.nombre, ''), sc2.nombre)                      AS sede,
           os.fecha_ejecucion,
           TIME_FORMAT(os.hora_inicio, '%H:%i')                             AS hora_inicio,
           NULLIF(TRIM(CONCAT(IFNULL(tc.nombre, ''), ' ', IFNULL(tc.apellido, ''))), '') AS tecnico,
           s.estado,
           s.motivo,
           s.intentos,
           s.latitud,
           s.longitud,
           s.precision_metros,
           s.distancia_metros                                               AS distancia_m,
           COALESCE(sc.latitud, sc2.latitud, os.latitud_llegada)            AS lat_planta,
           COALESCE(sc.longitud, sc2.longitud, os.longitud_llegada)         AS lon_planta,
           ROUND(v_radio)                                                   AS radio_m,
           s.area_destino,
           ar.String1                                                       AS area,
           s.solicitado_en,
           NULLIF(TRIM(CONCAT(IFNULL(jf.nombre, ''), ' ', IFNULL(jf.apellido, ''))), '') AS jefe,
           s.resuelto_en,
           s.comentario,
           s.usada_en
    FROM   llegada_forzada_os s
    JOIN   orden_servicio os ON os.id_os = s.id_os AND os.eliminado_en IS NULL
    LEFT JOIN cliente        cl  ON cl.id_cliente = os.id_cliente
    LEFT JOIN sede_cliente   sc  ON sc.id_sede = os.id_sede AND sc.SoftDelete = 0
    LEFT JOIN requerimiento  rq  ON rq.id_requerimiento = os.id_requerimiento
    LEFT JOIN sede_cliente   sc2 ON sc2.id_sede = rq.id_sede AND sc2.SoftDelete = 0
    LEFT JOIN usuario        tc  ON tc.id_usuario = s.id_tecnico
    LEFT JOIN usuario        jf  ON jf.id_usuario = s.id_jefe
    LEFT JOIN tabla_maestra  ar  ON ar.IdMaestro = 79 AND ar.IdEmpresa = 1 AND ar.String2 = s.area_destino
    WHERE  s.eliminado_en IS NULL
      AND  (v_general = 1 OR s.area_destino IS NULL OR s.area_destino = v_area_jefe)
      AND  ((IFNULL(p_id_os, 0) = 0 AND s.estado = 'pendiente')
            OR (IFNULL(p_id_os, 0) > 0 AND s.id_os = p_id_os
                AND s.id_solicitud = (SELECT MAX(x.id_solicitud) FROM llegada_forzada_os x WHERE x.id_os = p_id_os AND x.eliminado_en IS NULL)))
    ORDER BY s.solicitado_en DESC, s.id_solicitud DESC
    LIMIT 200;
END$$

DELIMITER ;

-- ============================================================
-- SP_ObtenerArchivoAprobacionMovil  (App Mobile HU-31 — foto de una evidencia forzada o de un gasto para el jefe · lectura)
--   p_tipo: evidencia (id = id_evidencia; n se ignora) | gasto (id = id_gasto; n = orden de la foto, 1 a 5).
--   Mismas reglas de acceso que SP_ObtenerAprobacionDetalleMovil: evidencia → encargado del área de la RQ, supervisión general o administrador;
--   gasto → prog_aprobar_reprogramacion. Solo devuelve rutas; la API abre el archivo con autenticación.
-- Resultados: 1 mensaje · 2 (ruta, ruta_cuadro, es_video).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerArchivoAprobacionMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerArchivoAprobacionMovil(
    IN p_id_usuario BIGINT,
    IN p_tipo       VARCHAR(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id         BIGINT,
    IN p_n          INT
)
proc: BEGIN
    DECLARE v_tipo      VARCHAR(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_area_jefe VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_general   TINYINT DEFAULT 0;
    DECLARE v_id_os     BIGINT;
    DECLARE v_area_os   VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_ruta      VARCHAR(500);
    DECLARE v_cuadro    VARCHAR(500);
    DECLARE v_video     TINYINT DEFAULT 0;
    DECLARE v_url       VARCHAR(500);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SET v_tipo = LOWER(TRIM(IFNULL(p_tipo, '')));
    IF v_tipo NOT IN ('evidencia', 'gasto') OR IFNULL(p_id, 0) <= 0 OR (v_tipo = 'gasto' AND IFNULL(p_n, 0) NOT BETWEEN 1 AND 5) THEN
        SELECT 1 AS IdTipoMensaje, 'Archivo no encontrado.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF v_tipo = 'evidencia' THEN
        SELECT f.id_os, NULLIF(TRIM(IFNULL(f.url_archivo, '')), ''), NULLIF(TRIM(IFNULL(f.ruta_cuadro, '')), ''), IFNULL(f.es_video, 0)
          INTO v_id_os, v_ruta, v_cuadro, v_video
        FROM evidencia_fotografica f WHERE f.id_evidencia = p_id AND f.override_aprobado = 1 AND f.eliminado_en IS NULL;

        -- Regla Área + Rol (SP_ResolverAprobadorMovil): otras áreas con cualquier rol y Administradores ven todo; Supervisor de ST / Metrología, solo su área
        CALL SP_ResolverAprobadorMovil(p_id_usuario, v_area_jefe, v_general);

        SELECT asr.area_usuario INTO v_area_os
        FROM orden_servicio os
        LEFT JOIN expediente_digital ed ON ed.id_expediente = os.id_expediente
        LEFT JOIN requerimiento rq      ON rq.id_requerimiento = ed.id_requerimiento
        LEFT JOIN area_servicio_rq asr  ON asr.id_area_rq = rq.id_area
        WHERE os.id_os = v_id_os;

        IF v_id_os IS NULL OR v_ruta IS NULL
           OR NOT (IFNULL(v_general, 0) = 1 OR (v_area_jefe IS NOT NULL AND (v_area_os IS NULL OR v_area_os = v_area_jefe))) THEN
            SELECT 1 AS IdTipoMensaje, 'Archivo no encontrado.' AS Mensaje;
            LEAVE proc;
        END IF;
    ELSE
        IF FN_PermisoAccion(p_id_usuario, 'prog_aprobar_reprogramacion') = 0 THEN
            SELECT 1 AS IdTipoMensaje, 'Archivo no encontrado.' AS Mensaje;
            LEAVE proc;
        END IF;
        SELECT MAX(url_comprobante), MAX(id_os) INTO v_url, v_id_os
        FROM gasto_viatico WHERE id_gasto = p_id AND tipo = 'gasto_solicitado' AND eliminado_en IS NULL;
        SELECT url INTO v_ruta FROM gasto_viatico_foto WHERE id_gasto = p_id AND orden = p_n AND eliminado_en IS NULL ORDER BY id_foto DESC LIMIT 1;
        IF v_ruta IS NULL AND p_n = 1 AND NOT EXISTS (SELECT 1 FROM gasto_viatico_foto WHERE id_gasto = p_id AND eliminado_en IS NULL) THEN
            SET v_ruta = NULLIF(TRIM(IFNULL(v_url, '')), '');
        END IF;
        IF v_id_os IS NULL OR v_ruta IS NULL THEN
            SELECT 1 AS IdTipoMensaje, 'Archivo no encontrado.' AS Mensaje;
            LEAVE proc;
        END IF;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'OK' AS Mensaje;
    SELECT v_ruta AS ruta, v_cuadro AS ruta_cuadro, v_video AS es_video;
END$$

DELIMITER ;

-- ============================================================
-- SP_ResolverAutorizacionSalida  (Intranet · App Mobile HU-04)
-- El encargado del área da (o niega) el visto bueno de salida de una OS desde la intranet.
--   - Área de la OS: la de la solicitud (area_destino) o, si no hay solicitud, la de la RQ
--     (requerimiento.id_area → area_servicio_rq).
--   - Pueden resolver: el encargado de ESA área (cargo jefe_* del área: Jefe de Servicio Técnico
--     o Jefe de Metrología; y también el SUPERVISOR del área Metrología, que es su jefe en la app móvil;
--     si la RQ no tiene área, cualquiera de los dos), el Jefe/Coordinador
--     de Operaciones o el supervisor del área Operaciones (supervisión general) o un administrador. El encargado de la otra área NO.
--   - Si hay una solicitud pendiente del técnico, la resuelve; si no, registra el visto bueno igual.
--   - Solo mientras la OS siga programada/reprogramada.
--   - Notifica al técnico principal y al personal de la OS ("Autorización de salida aprobada/rechazada" con el jefe, su cargo y la
--     condición o el motivo). Deja registro en auditoria_evento.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ResolverAutorizacionSalida;

DELIMITER $$

CREATE PROCEDURE SP_ResolverAutorizacionSalida(
    IN p_id_jefe    BIGINT,
    IN p_id_os      BIGINT,
    IN p_aprobar    TINYINT,
    IN p_comentario VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_estado     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_numero     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_jefe       VARCHAR(210) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_principal  BIGINT;
    DECLARE v_id_aut     BIGINT;
    DECLARE v_aut_estado VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_nuevo      VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_area       VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_area_jefe  VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_general    TINYINT DEFAULT 0;
    DECLARE v_area_sol   VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cargo_jefe VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cliente    VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    -- Quién es: encargado de un área (v_area_jefe) o supervisión general (v_general)
    SELECT TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))),
           IFNULL(c.String1, NULLIF(u.cargo, '')),
           COALESCE(IF(c.String2 LIKE 'jefe\_%' AND c.String3 IN ('servicio_tecnico', 'metrologia'), c.String3, NULL),
                    IF(u.rol_sistema = 'supervisor' AND u.area = 'metrologia', 'metrologia', NULL)),
           (u.cargo IN ('jefe_operaciones', 'coordinador_operaciones') OR u.rol_sistema IN ('administrador', 'admin')
            OR (u.rol_sistema = 'supervisor' AND u.area = 'operaciones'))
    INTO   v_jefe, v_cargo_jefe, v_area_jefe, v_general
    FROM   usuario u
    LEFT JOIN tabla_maestra c ON c.IdMaestro = 80 AND c.IdEmpresa = 1 AND c.String2 = u.cargo
    WHERE  u.id_usuario = p_id_jefe AND u.eliminado_en IS NULL AND u.estado = 'activo'
    LIMIT 1;

    -- Regla Área + Rol (SP_ResolverAprobadorMovil): reemplaza el área / alcance general calculado por el cargo
    IF v_jefe IS NOT NULL THEN
        CALL SP_ResolverAprobadorMovil(p_id_jefe, v_area_jefe, v_general);
    END IF;
    IF v_jefe IS NULL OR (v_area_jefe IS NULL AND v_general = 0) THEN
        SELECT 1 AS IdTipoMensaje, 'Solo el encargado del área (Servicio Técnico o Metrología) puede dar el visto bueno de salida.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_nuevo = IF(p_aprobar = 1, 'aprobada', 'rechazada');

    START TRANSACTION;

    SELECT os.estado, os.numero, os.id_tecnico_principal, asr.area_usuario, COALESCE(NULLIF(cl.nombre_comercial, ''), cl.razon_social)
    INTO   v_estado, v_numero, v_principal, v_area, v_cliente
    FROM   orden_servicio os
    LEFT JOIN cliente            cl  ON cl.id_cliente       = os.id_cliente
    LEFT JOIN expediente_digital ed  ON ed.id_expediente    = os.id_expediente
    LEFT JOIN requerimiento      rq  ON rq.id_requerimiento = ed.id_requerimiento
    LEFT JOIN area_servicio_rq   asr ON asr.id_area_rq      = rq.id_area
    WHERE  os.id_os = p_id_os AND os.eliminado_en IS NULL
    FOR UPDATE;

    IF v_estado IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Orden de servicio no encontrada.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF v_estado NOT IN ('programada', 'reprogramada') THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, CONCAT('La OS ya no está programada (', REPLACE(v_estado, '_', ' '), '): no requiere visto bueno.') AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT a.id_autorizacion, a.estado, IF(a.estado = 'pendiente', a.area_destino, NULL)
    INTO   v_id_aut, v_aut_estado, v_area_sol
    FROM   autorizacion_salida_os a
    WHERE  a.id_os = p_id_os AND a.eliminado_en IS NULL
    ORDER BY a.id_autorizacion DESC LIMIT 1;

    -- La solicitud pendiente manda: es el área a la que se notificó
    IF v_aut_estado = 'pendiente' AND v_area_sol IS NOT NULL THEN
        SET v_area = v_area_sol;
    END IF;

    -- El encargado de la otra área no puede resolver (sí la supervisión general)
    IF v_general = 0 AND v_area IS NOT NULL AND v_area <> v_area_jefe THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Este servicio no es de tu área: lo autoriza el encargado del área indicada en la RQ.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF v_aut_estado = 'pendiente' THEN
        UPDATE autorizacion_salida_os
        SET    estado = v_nuevo, id_jefe = p_id_jefe, resuelto_en = NOW(),
               comentario = NULLIF(TRIM(p_comentario), ''), modificado_por = p_id_jefe
        WHERE  id_autorizacion = v_id_aut;
    ELSE
        INSERT INTO autorizacion_salida_os (id_os, id_tecnico, estado, area_destino, id_jefe, resuelto_en, comentario, creado_por)
        VALUES (p_id_os, v_principal, v_nuevo, v_area, p_id_jefe, NOW(), NULLIF(TRIM(p_comentario), ''), p_id_jefe);
        SET v_id_aut = LAST_INSERT_ID();
    END IF;

    -- Aviso al técnico principal y al personal de la OS
    INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
    SELECT d.id_usuario, 5,
           IF(p_aprobar = 1, 'Autorización de salida aprobada', 'Autorización de salida rechazada'),
           LEFT(CONCAT(v_numero, IF(v_cliente IS NULL, '', CONCAT(' · ', v_cliente)), ' · ', v_jefe,
                       IF(v_cargo_jefe IS NULL, '', CONCAT(' (', v_cargo_jefe, ')')),
                       IF(p_aprobar = 1, ' dio el visto bueno.', ' no autorizó tu salida.'),
                       IF(NULLIF(TRIM(p_comentario), '') IS NULL, '', CONCAT(IF(p_aprobar = 1, ' Condición: ', ' Motivo: '), TRIM(p_comentario)))), 3000),
           'orden_servicio', p_id_os, NOW(), p_id_jefe
    FROM (
        SELECT v_principal AS id_usuario FROM DUAL WHERE v_principal IS NOT NULL
        UNION
        SELECT op.id_usuario FROM os_personal op WHERE op.id_os = p_id_os AND op.eliminado_en IS NULL
    ) d;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('orden_servicio', p_id_os, 'visto_bueno_salida', IFNULL(v_aut_estado, 'sin_solicitud'), v_nuevo,
            CONCAT(v_jefe, IF(p_aprobar = 1, ' dio el visto bueno de salida.', ' no autorizó la salida.'),
                   IF(NULLIF(TRIM(p_comentario), '') IS NULL, '', CONCAT(' ', TRIM(p_comentario)))),
            p_id_jefe, NOW(), JSON_OBJECT('id_autorizacion', v_id_aut, 'area', v_area));

    COMMIT;

    SELECT 2 AS IdTipoMensaje, IF(p_aprobar = 1, 'Visto bueno de salida registrado.', 'Salida no autorizada.') AS Mensaje;
END$$

DELIMITER ;

-- ============================================================
-- SP_ResolverLlegadaForzada  (App Mobile HU-06 / HU-31 — el encargado aprueba o rechaza la llegada forzada · escritura)
--   - Pueden resolver las mismas personas que ven la solicitud (SP_ObtenerLlegadasForzadas): el encargado del ÁREA de la solicitud, la supervisión
--     general (Jefe/Coordinador de Operaciones, supervisor de Operaciones) y los administradores. El de la otra área NO.
--   - Solo una solicitud PENDIENTE de la OS; el comentario es obligatorio (condición al aprobar, motivo al rechazar; 3 a 500 caracteres).
--   - Aprobar deja a la OS lista para que el técnico registre su llegada UNA vez (SP_EvaluarLlegadaMovil → 'autorizada'); rechazar le pide volver a
--     acercarse (puede intentarlo otra vez tras 5 capturas más).
--   - Notifica al técnico principal y al personal de la OS («Llegada forzada aprobada/rechazada») y deja el registro en auditoria_evento.
-- Resultado: 1 fila (IdTipoMensaje, Mensaje).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ResolverLlegadaForzada;

DELIMITER $$

CREATE PROCEDURE SP_ResolverLlegadaForzada(
    IN p_id_jefe    BIGINT,
    IN p_id_os      BIGINT,
    IN p_aprobar    TINYINT,
    IN p_comentario VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_numero     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado_os  VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cliente    VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_jefe       VARCHAR(210) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cargo_jefe VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_area_jefe  VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_general    TINYINT DEFAULT 0;
    DECLARE v_principal  BIGINT;
    DECLARE v_id_sol     BIGINT;
    DECLARE v_sol_estado VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_sol_area   VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_nuevo      VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SELECT TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))),
           IFNULL(c.String1, NULLIF(u.cargo, '')),
           COALESCE(IF(c.String2 LIKE 'jefe\_%' AND c.String3 IN ('servicio_tecnico', 'metrologia'), c.String3, NULL),
                    IF(u.rol_sistema = 'supervisor' AND u.area = 'metrologia', 'metrologia', NULL)),
           (u.cargo IN ('jefe_operaciones', 'coordinador_operaciones') OR u.rol_sistema IN ('administrador', 'admin')
            OR (u.rol_sistema = 'supervisor' AND u.area = 'operaciones'))
    INTO   v_jefe, v_cargo_jefe, v_area_jefe, v_general
    FROM   usuario u
    LEFT JOIN tabla_maestra c ON c.IdMaestro = 80 AND c.IdEmpresa = 1 AND c.String2 = u.cargo
    WHERE  u.id_usuario = p_id_jefe AND u.eliminado_en IS NULL AND u.estado = 'activo'
    LIMIT 1;

    -- Regla Área + Rol (SP_ResolverAprobadorMovil): reemplaza el área / alcance general calculado por el cargo
    IF v_jefe IS NOT NULL THEN
        CALL SP_ResolverAprobadorMovil(p_id_jefe, v_area_jefe, v_general);
    END IF;
    IF v_jefe IS NULL OR (v_area_jefe IS NULL AND v_general = 0) THEN
        SELECT 1 AS IdTipoMensaje, 'Solo el encargado del área (Servicio Técnico o Metrología) puede resolver la llegada forzada.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF NULLIF(TRIM(p_comentario), '') IS NULL OR CHAR_LENGTH(TRIM(p_comentario)) < 3 THEN
        SELECT 1 AS IdTipoMensaje, IF(p_aprobar = 1, 'Indica la condición con la que autorizas la llegada.', 'Indica el motivo por el que no autorizas la llegada.') AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_nuevo = IF(p_aprobar = 1, 'aprobada', 'rechazada');

    START TRANSACTION;

    SELECT os.numero, os.estado, os.id_tecnico_principal, COALESCE(NULLIF(cl.nombre_comercial, ''), cl.razon_social)
    INTO   v_numero, v_estado_os, v_principal, v_cliente
    FROM   orden_servicio os
    LEFT JOIN cliente cl ON cl.id_cliente = os.id_cliente
    WHERE  os.id_os = p_id_os AND os.eliminado_en IS NULL
    FOR UPDATE;

    IF v_numero IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Orden de servicio no encontrada.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT s.id_solicitud, s.estado, s.area_destino INTO v_id_sol, v_sol_estado, v_sol_area
    FROM   llegada_forzada_os s
    WHERE  s.id_os = p_id_os AND s.eliminado_en IS NULL
    ORDER BY s.id_solicitud DESC LIMIT 1;

    IF v_id_sol IS NULL OR v_sol_estado <> 'pendiente' THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'No hay una solicitud de llegada forzada pendiente para este servicio (quizá ya la resolvió otra persona).' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_general = 0 AND v_sol_area IS NOT NULL AND v_sol_area <> v_area_jefe THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Este servicio no es de tu área: lo autoriza el encargado del área indicada en la RQ.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF p_aprobar = 1 AND v_estado_os <> 'en_ruta' THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'El servicio ya no está en ruta: no hace falta autorizar la llegada.' AS Mensaje;
        LEAVE proc;
    END IF;

    UPDATE llegada_forzada_os
    SET    estado = v_nuevo, id_jefe = p_id_jefe, resuelto_en = NOW(), comentario = TRIM(p_comentario), modificado_por = p_id_jefe
    WHERE  id_solicitud = v_id_sol;

    INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
    SELECT d.id_usuario, 5,
           IF(p_aprobar = 1, 'Llegada forzada aprobada', 'Llegada forzada rechazada'),
           LEFT(CONCAT(v_numero, IF(v_cliente IS NULL, '', CONCAT(' · ', v_cliente)), ' · ', v_jefe,
                       IF(v_cargo_jefe IS NULL, '', CONCAT(' (', v_cargo_jefe, ')')),
                       IF(p_aprobar = 1, ' autorizó tu llegada: ya puedes registrarla.', ' no autorizó tu llegada: acércate a la planta.'),
                       IF(p_aprobar = 1, ' Condición: ', ' Motivo: '), TRIM(p_comentario)), 3000),
           'orden_servicio', p_id_os, NOW(), p_id_jefe
    FROM (
        SELECT v_principal AS id_usuario FROM DUAL WHERE v_principal IS NOT NULL
        UNION
        SELECT op.id_usuario FROM os_personal op WHERE op.id_os = p_id_os AND op.eliminado_en IS NULL
    ) d;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('orden_servicio', p_id_os, 'resolver_llegada_forzada', 'pendiente', v_nuevo,
            LEFT(CONCAT(v_jefe, IF(p_aprobar = 1, ' autorizó la llegada forzada.', ' no autorizó la llegada forzada.'), ' ', TRIM(p_comentario)), 900),
            p_id_jefe, NOW(), JSON_OBJECT('id_solicitud', v_id_sol, 'area', v_sol_area));

    COMMIT;

    SELECT 2 AS IdTipoMensaje, IF(p_aprobar = 1, 'Llegada autorizada: el técnico ya puede registrarla.', 'Llegada no autorizada.') AS Mensaje;
END$$

DELIMITER ;

-- HU-52 (Sprint 5) El encargado aprueba o rechaza un ensayo guardado con error crítico (HU-10: "Guardar de todas formas", migraciones 100 y 107).
--   Pueden resolver: el encargado del área de la RQ de la OS (Jefe de Servicio Técnico / Jefe de Metrología o el supervisor de Metrología), la supervisión
--   general (Jefe o Coordinador de Operaciones, supervisor de Operaciones) y los administradores. El de la otra área NO.
--   El informe debe ser de ESA OS (p_id_os NULL/0 = la del informe, desde la app), tener el error crítico registrado y estar sin revisar.
--   Comentario hasta 500 caracteres, obligatorio al rechazar (la intranet lo exige siempre en su caso de uso).
--   Rechazar no borra las lecturas: queda registrada la decisión y se avisa al técnico para que repita o corrija el ensayo.
--   Notifica al técnico y deja el registro en auditoria_evento. Requiere la migración 113.
-- Resultado: 1 fila (IdTipoMensaje, Mensaje).
DROP PROCEDURE IF EXISTS SP_ResolverEnsayoConError;

DELIMITER $$

CREATE PROCEDURE SP_ResolverEnsayoConError(
    IN p_id_jefe    BIGINT,
    IN p_id_os      BIGINT,
    IN p_id_informe BIGINT,
    IN p_aprobar    TINYINT,
    IN p_comentario VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_jefe       VARCHAR(210) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cargo_jefe VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_area_jefe  VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_general    TINYINT DEFAULT 0;
    DECLARE v_numero     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cliente    VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_area       VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id         BIGINT;
    DECLARE v_revision   VARCHAR(12)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_motivo     VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tecnico    BIGINT;
    DECLARE v_equipo     VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_com        VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_aprobar    TINYINT DEFAULT 0;
    DECLARE v_nuevo      VARCHAR(12)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        ROLLBACK;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SELECT TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))),
           IFNULL(c.String1, NULLIF(u.cargo, '')),
           COALESCE(IF(c.String2 LIKE 'jefe\_%' AND c.String3 IN ('servicio_tecnico', 'metrologia'), c.String3, NULL),
                    IF(u.rol_sistema = 'supervisor' AND u.area = 'metrologia', 'metrologia', NULL)),
           (u.cargo IN ('jefe_operaciones', 'coordinador_operaciones') OR u.rol_sistema IN ('administrador', 'admin')
            OR (u.rol_sistema = 'supervisor' AND u.area = 'operaciones'))
    INTO   v_jefe, v_cargo_jefe, v_area_jefe, v_general
    FROM   usuario u
    LEFT JOIN tabla_maestra c ON c.IdMaestro = 80 AND c.IdEmpresa = 1 AND c.String2 = u.cargo
    WHERE  u.id_usuario = p_id_jefe AND u.eliminado_en IS NULL AND u.estado = 'activo'
    LIMIT 1;

    -- Regla Área + Rol (SP_ResolverAprobadorMovil): reemplaza el área / alcance general calculado por el cargo
    IF v_jefe IS NOT NULL THEN
        CALL SP_ResolverAprobadorMovil(p_id_jefe, v_area_jefe, v_general);
    END IF;
    IF v_jefe IS NULL OR (v_area_jefe IS NULL AND IFNULL(v_general, 0) = 0) THEN
        SELECT 1 AS IdTipoMensaje, 'Solo el encargado del área (Servicio Técnico o Metrología) puede resolver el ensayo con error.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_com = NULLIF(TRIM(IFNULL(p_comentario, '')), '');
    SET v_aprobar = IF(IFNULL(p_aprobar, 0) = 1, 1, 0);
    SET v_nuevo   = IF(v_aprobar = 1, 'aprobada', 'rechazada');
    IF (v_aprobar = 0 AND v_com IS NULL) OR CHAR_LENGTH(IFNULL(v_com, '')) > 500 THEN
        SELECT 1 AS IdTipoMensaje, IF(v_com IS NULL, 'Indica el motivo del rechazo.', 'El comentario admite hasta 500 caracteres.') AS Mensaje;
        LEAVE proc;
    END IF;

    -- Desde la app llega solo el id del informe: la OS se toma del informe
    IF IFNULL(p_id_os, 0) <= 0 THEN
        SELECT MAX(id_os) INTO p_id_os FROM informe_tecnico WHERE id_informe = p_id_informe AND eliminado_en IS NULL;
    END IF;

    START TRANSACTION;

    SELECT os.numero, COALESCE(NULLIF(cl.nombre_comercial, ''), cl.razon_social), asr.area_usuario
    INTO   v_numero, v_cliente, v_area
    FROM   orden_servicio os
    LEFT JOIN cliente            cl  ON cl.id_cliente       = os.id_cliente
    LEFT JOIN expediente_digital ed  ON ed.id_expediente    = os.id_expediente
    LEFT JOIN requerimiento      rq  ON rq.id_requerimiento = ed.id_requerimiento
    LEFT JOIN area_servicio_rq   asr ON asr.id_area_rq      = rq.id_area
    WHERE  os.id_os = p_id_os AND os.eliminado_en IS NULL
    FOR UPDATE;

    IF v_numero IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Orden de servicio no encontrada.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT it.id_informe, it.error_critico_revision, it.error_critico_motivo, it.id_tecnico, ec.codigo_tw
    INTO   v_id, v_revision, v_motivo, v_tecnico, v_equipo
    FROM   informe_tecnico it
    LEFT JOIN equipo_cliente ec ON ec.id_equipo = it.id_equipo
    WHERE  it.id_informe = p_id_informe AND it.id_os = p_id_os AND it.eliminado_en IS NULL
    FOR UPDATE;

    IF v_id IS NULL OR v_motivo IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'El ensayo con error no existe en este servicio.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_revision IS NOT NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Este ensayo ya fue revisado (quizá por otra persona).' AS Mensaje;
        LEAVE proc;
    END IF;
    IF IFNULL(v_general, 0) = 0 AND v_area IS NOT NULL AND v_area <> v_area_jefe THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Este servicio no es de tu área: lo revisa el encargado del área indicada en la RQ.' AS Mensaje;
        LEAVE proc;
    END IF;

    UPDATE informe_tecnico
    SET    error_critico_revision = v_nuevo, error_critico_revisado_por = p_id_jefe, error_critico_revisado_en = NOW(),
           error_critico_comentario = v_com, modificado_por = p_id_jefe
    WHERE  id_informe = v_id;

    INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
    SELECT v_tecnico, 5,
           IF(v_aprobar = 1, 'Ensayo con error aprobado', 'Ensayo con error rechazado'),
           LEFT(CONCAT(v_numero, IF(v_cliente IS NULL, '', CONCAT(' · ', v_cliente)), IF(v_equipo IS NULL, '', CONCAT(' · ', v_equipo)),
                       ' · ', v_jefe, IF(v_cargo_jefe IS NULL, '', CONCAT(' (', v_cargo_jefe, ')')),
                       IF(v_aprobar = 1, CONCAT(' aprobó el ensayo guardado con error crítico.', IF(v_com IS NULL, '', CONCAT(' Comentario: ', v_com))),
                                         CONCAT(' rechazó el ensayo guardado con error crítico: repítelo o corrige las lecturas. Motivo: ', v_com))), 3000),
           'orden_servicio', p_id_os, NOW(), p_id_jefe
    FROM   DUAL
    WHERE  v_tecnico IS NOT NULL AND v_tecnico <> p_id_jefe;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('orden_servicio', p_id_os, 'resolver_ensayo_error', 'pendiente', v_nuevo,
            LEFT(CONCAT(v_jefe, IF(v_aprobar = 1, ' aprobó', ' rechazó'), ' el ensayo con error crítico',
                        IF(v_equipo IS NULL, '', CONCAT(' del equipo ', v_equipo)), '.', IF(v_com IS NULL, '', CONCAT(' ', v_com))), 900),
            p_id_jefe, NOW(), JSON_OBJECT('id_informe', v_id, 'area', v_area));

    COMMIT;

    SELECT 2 AS IdTipoMensaje, IF(v_aprobar = 1, 'Ensayo con error aprobado.', 'Ensayo con error rechazado: se avisó al técnico.') AS Mensaje;
END$$

DELIMITER ;

-- HU-52 (Sprint 5) El encargado aprueba o rechaza una evidencia FORZADA (HU-12: la IA la rechazó y el técnico la aceptó con un motivo).
--   Pueden resolver: el encargado del área de la RQ de la OS (Jefe de Servicio Técnico / Jefe de Metrología o el supervisor de Metrología), la supervisión
--   general (Jefe o Coordinador de Operaciones, supervisor de Operaciones) y los administradores. El de la otra área NO.
--   La evidencia debe ser de ESA OS (p_id_os NULL/0 = la de la evidencia, desde la app), estar forzada y sin revisar.
--   Comentario hasta 500 caracteres, obligatorio al rechazar (la intranet lo exige siempre en su caso de uso).
--   Rechazar no borra la foto: queda registrada la decisión y se avisa al técnico para que vuelva a tomarla.
--   Notifica al técnico y deja el registro en auditoria_evento. Requiere la migración 113.
-- Resultado: 1 fila (IdTipoMensaje, Mensaje).
DROP PROCEDURE IF EXISTS SP_ResolverEvidenciaForzada;

DELIMITER $$

CREATE PROCEDURE SP_ResolverEvidenciaForzada(
    IN p_id_jefe      BIGINT,
    IN p_id_os        BIGINT,
    IN p_id_evidencia BIGINT,
    IN p_aprobar      TINYINT,
    IN p_comentario   VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_jefe       VARCHAR(210) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cargo_jefe VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_area_jefe  VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_general    TINYINT DEFAULT 0;
    DECLARE v_numero     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cliente    VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_area       VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id         BIGINT;
    DECLARE v_revision   VARCHAR(12)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tecnico    BIGINT;
    DECLARE v_codigo     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_com        VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_aprobar    TINYINT DEFAULT 0;
    DECLARE v_nuevo      VARCHAR(12)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        ROLLBACK;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SELECT TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))),
           IFNULL(c.String1, NULLIF(u.cargo, '')),
           COALESCE(IF(c.String2 LIKE 'jefe\_%' AND c.String3 IN ('servicio_tecnico', 'metrologia'), c.String3, NULL),
                    IF(u.rol_sistema = 'supervisor' AND u.area = 'metrologia', 'metrologia', NULL)),
           (u.cargo IN ('jefe_operaciones', 'coordinador_operaciones') OR u.rol_sistema IN ('administrador', 'admin')
            OR (u.rol_sistema = 'supervisor' AND u.area = 'operaciones'))
    INTO   v_jefe, v_cargo_jefe, v_area_jefe, v_general
    FROM   usuario u
    LEFT JOIN tabla_maestra c ON c.IdMaestro = 80 AND c.IdEmpresa = 1 AND c.String2 = u.cargo
    WHERE  u.id_usuario = p_id_jefe AND u.eliminado_en IS NULL AND u.estado = 'activo'
    LIMIT 1;

    -- Regla Área + Rol (SP_ResolverAprobadorMovil): reemplaza el área / alcance general calculado por el cargo
    IF v_jefe IS NOT NULL THEN
        CALL SP_ResolverAprobadorMovil(p_id_jefe, v_area_jefe, v_general);
    END IF;
    IF v_jefe IS NULL OR (v_area_jefe IS NULL AND IFNULL(v_general, 0) = 0) THEN
        SELECT 1 AS IdTipoMensaje, 'Solo el encargado del área (Servicio Técnico o Metrología) puede resolver la evidencia forzada.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_com = NULLIF(TRIM(IFNULL(p_comentario, '')), '');
    SET v_aprobar = IF(IFNULL(p_aprobar, 0) = 1, 1, 0);
    SET v_nuevo   = IF(v_aprobar = 1, 'aprobada', 'rechazada');
    IF (v_aprobar = 0 AND v_com IS NULL) OR CHAR_LENGTH(IFNULL(v_com, '')) > 500 THEN
        SELECT 1 AS IdTipoMensaje, IF(v_com IS NULL, 'Indica el motivo del rechazo.', 'El comentario admite hasta 500 caracteres.') AS Mensaje;
        LEAVE proc;
    END IF;

    -- Desde la app llega solo el id de la evidencia: la OS se toma de la evidencia
    IF IFNULL(p_id_os, 0) <= 0 THEN
        SELECT MAX(id_os) INTO p_id_os FROM evidencia_fotografica WHERE id_evidencia = p_id_evidencia AND eliminado_en IS NULL;
    END IF;

    START TRANSACTION;

    SELECT os.numero, COALESCE(NULLIF(cl.nombre_comercial, ''), cl.razon_social), asr.area_usuario
    INTO   v_numero, v_cliente, v_area
    FROM   orden_servicio os
    LEFT JOIN cliente            cl  ON cl.id_cliente       = os.id_cliente
    LEFT JOIN expediente_digital ed  ON ed.id_expediente    = os.id_expediente
    LEFT JOIN requerimiento      rq  ON rq.id_requerimiento = ed.id_requerimiento
    LEFT JOIN area_servicio_rq   asr ON asr.id_area_rq      = rq.id_area
    WHERE  os.id_os = p_id_os AND os.eliminado_en IS NULL
    FOR UPDATE;

    IF v_numero IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Orden de servicio no encontrada.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT f.id_evidencia, f.revision_jefe, COALESCE(f.id_usuario_override, f.id_usuario), f.codigo
    INTO   v_id, v_revision, v_tecnico, v_codigo
    FROM   evidencia_fotografica f
    WHERE  f.id_evidencia = p_id_evidencia AND f.id_os = p_id_os AND f.eliminado_en IS NULL AND f.override_aprobado = 1
    FOR UPDATE;

    IF v_id IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'La evidencia forzada no existe en este servicio.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_revision IS NOT NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Esta evidencia ya fue revisada (quizá por otra persona).' AS Mensaje;
        LEAVE proc;
    END IF;
    IF IFNULL(v_general, 0) = 0 AND v_area IS NOT NULL AND v_area <> v_area_jefe THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Este servicio no es de tu área: lo revisa el encargado del área indicada en la RQ.' AS Mensaje;
        LEAVE proc;
    END IF;

    UPDATE evidencia_fotografica
    SET    revision_jefe = v_nuevo, revisado_jefe_por = p_id_jefe, revisado_jefe_en = NOW(), comentario_jefe = v_com, modificado_por = p_id_jefe
    WHERE  id_evidencia = v_id;

    INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
    SELECT v_tecnico, 5,
           IF(v_aprobar = 1, 'Evidencia forzada aprobada', 'Evidencia forzada rechazada'),
           LEFT(CONCAT(v_numero, IF(v_cliente IS NULL, '', CONCAT(' · ', v_cliente)), ' · ', v_jefe,
                       IF(v_cargo_jefe IS NULL, '', CONCAT(' (', v_cargo_jefe, ')')),
                       IF(v_aprobar = 1, ' aprobó la evidencia "', ' rechazó la evidencia "'), IFNULL(v_codigo, 'foto'), '".',
                       IF(v_aprobar = 1, IF(v_com IS NULL, '', CONCAT(' Comentario: ', v_com)), CONCAT(' Vuelve a tomarla. Motivo: ', v_com))), 3000),
           'orden_servicio', p_id_os, NOW(), p_id_jefe
    FROM   DUAL
    WHERE  v_tecnico IS NOT NULL AND v_tecnico <> p_id_jefe;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('orden_servicio', p_id_os, 'resolver_evidencia_forzada', 'pendiente', v_nuevo,
            LEFT(CONCAT(v_jefe, IF(v_aprobar = 1, ' aprobó', ' rechazó'), ' la evidencia forzada "', IFNULL(v_codigo, 'foto'), '".',
                        IF(v_com IS NULL, '', CONCAT(' ', v_com))), 900),
            p_id_jefe, NOW(), JSON_OBJECT('id_evidencia', v_id, 'codigo', v_codigo, 'area', v_area));

    COMMIT;

    SELECT 2 AS IdTipoMensaje, IF(v_aprobar = 1, 'Evidencia forzada aprobada.', 'Evidencia forzada rechazada: se avisó al técnico.') AS Mensaje;
END$$

DELIMITER ;

-- ============================================================
-- SP_SolicitarAutorizacionSalidaMovil  (App Mobile HU-04)
-- El técnico pide el visto bueno para salir con pendientes al ENCARGADO DEL ÁREA del servicio.
--   - El área sale de la RQ de la OS: orden_servicio → expediente_digital → requerimiento.id_area
--     (catálogo AREA_REQUERIMIENTO 64) → area_servicio_rq → servicio_tecnico | metrologia.
--   - Encargado = usuario activo cuyo cargo es el "jefe_*" de esa área en CARGO_USUARIO (80):
--     Jefe de Servicio Técnico o Jefe de Metrología.
--   - Si la RQ no tiene área (o no está mapeada) se notifica a ambos encargados.
--   - Respaldo si el área no tiene encargado activo: supervisores/administradores del área;
--     si tampoco, Jefe/Coordinador de Operaciones; si tampoco, administradores.
--   - Una sola solicitud pendiente por OS (evita duplicados y spam de notificaciones).
--   - Solo desde el día programado de la OS (SP_ObtenerSalidaHabilitadaMovil).
--   - La notificación al encargado es CRÍTICA (prioridad_origen = critica, control_campo / autorizacion_salida): sale como alerta crítica; el Seguimiento Operativo
--     también la muestra en «Alertas críticas» mientras la solicitud siga pendiente (SP_ArmarSeguimientoOperativo).
--   - Deja también una notificación al propio técnico ("Solicitud de autorización enviada") para que la vea en la app.
--   - Deja registro en autorizacion_salida_os (con area_destino) y auditoria_evento.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_SolicitarAutorizacionSalidaMovil;

DELIMITER $$

CREATE PROCEDURE SP_SolicitarAutorizacionSalidaMovil(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT,
    IN p_motivo     VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_pendientes VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_estado      VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_numero      VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cliente     VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tecnico     VARCHAR(210) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_aut_estado  VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_aut      BIGINT;
    DECLARE v_destinos    INT DEFAULT 0;
    DECLARE v_area        VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_area_nombre VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_notificados VARCHAR(600) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_salida_ok   TINYINT DEFAULT 1;
    DECLARE v_salida_msg  VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    START TRANSACTION;

    SELECT os.estado, os.numero, COALESCE(NULLIF(cl.nombre_comercial, ''), cl.razon_social), asr.area_usuario
    INTO   v_estado, v_numero, v_cliente, v_area
    FROM   orden_servicio os
    LEFT JOIN cliente            cl  ON cl.id_cliente        = os.id_cliente
    LEFT JOIN expediente_digital ed  ON ed.id_expediente     = os.id_expediente
    LEFT JOIN requerimiento      rq  ON rq.id_requerimiento  = ed.id_requerimiento
    LEFT JOIN area_servicio_rq   asr ON asr.id_area_rq       = rq.id_area
    WHERE  os.id_os = p_id_os AND os.eliminado_en IS NULL
      AND  (os.id_tecnico_principal = p_id_usuario
            OR EXISTS (SELECT 1 FROM os_personal op
                       WHERE op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL))
    FOR UPDATE;

    IF v_estado IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Servicio no encontrado o no asignado a tu usuario.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF v_estado NOT IN ('programada', 'reprogramada') THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'El servicio ya no está programado: no hace falta autorización de salida.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- La salida (y su autorización) solo se gestiona desde el día programado
    CALL SP_ObtenerSalidaHabilitadaMovil(p_id_os, v_salida_ok, v_salida_msg);
    IF v_salida_ok = 0 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, v_salida_msg AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT a.estado INTO v_aut_estado
    FROM   autorizacion_salida_os a
    WHERE  a.id_os = p_id_os AND a.eliminado_en IS NULL
    ORDER BY a.id_autorizacion DESC LIMIT 1;

    IF v_aut_estado = 'pendiente' THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Ya enviaste una solicitud: espera la respuesta del encargado del área.' AS Mensaje;
        LEAVE proc;
    END IF;

    IF v_aut_estado = 'aprobada' THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Ya tienes el visto bueno: puedes iniciar el traslado.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT TRIM(CONCAT(IFNULL(nombre, ''), ' ', IFNULL(apellido, ''))) INTO v_tecnico
    FROM usuario WHERE id_usuario = p_id_usuario;

    SET v_area_nombre = (SELECT t.String1 FROM tabla_maestra t
                         WHERE t.IdMaestro = 79 AND t.IdEmpresa = 1 AND t.String2 = v_area LIMIT 1);

    INSERT INTO autorizacion_salida_os (id_os, id_tecnico, motivo, pendientes, estado, area_destino, solicitado_en, creado_por)
    VALUES (p_id_os, p_id_usuario, NULLIF(TRIM(p_motivo), ''), NULLIF(TRIM(p_pendientes), ''), 'pendiente', v_area, NOW(), p_id_usuario);
    SET v_id_aut = LAST_INSERT_ID();

    -- Destinatarios (en una tabla temporal para notificar y responder con los nombres)
    DROP TEMPORARY TABLE IF EXISTS tmp_aut_destino;
    CREATE TEMPORARY TABLE tmp_aut_destino (
        id_usuario BIGINT PRIMARY KEY,
        nombre     VARCHAR(210) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        cargo      VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
    );

    -- 1) Regla Área + Rol (SP_ArmarAprobadoresMovil): Gerencia, Operaciones, Administración, TI, SSOMA, Calidad, Comercial (cualquier rol) y Administradores
    --    ven todo; Supervisor de Servicio Técnico / Metrología, solo su área (si la RQ no tiene área: de ambas); Usuario / Visor de ST / Metrología, nunca.
    CALL SP_ArmarAprobadoresMovil(v_area);
    INSERT IGNORE INTO tmp_aut_destino
    SELECT u.id_usuario, TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))), c.String1
    FROM   tmp_aprobadores a
    JOIN   usuario u ON u.id_usuario = a.id_usuario
    LEFT JOIN tabla_maestra c ON c.IdMaestro = 80 AND c.IdEmpresa = 1 AND c.String2 = u.cargo
    WHERE  u.id_usuario <> p_id_usuario;
    DROP TEMPORARY TABLE IF EXISTS tmp_aprobadores;

    -- 2) Respaldo: supervisores / administradores del área
    IF (SELECT COUNT(*) FROM tmp_aut_destino) = 0 THEN
        INSERT IGNORE INTO tmp_aut_destino
        SELECT u.id_usuario, TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))), NULL
        FROM   usuario u
        WHERE  u.eliminado_en IS NULL AND u.estado = 'activo'
          AND  u.rol_sistema IN ('supervisor', 'administrador')
          AND  ((v_area IS NOT NULL AND u.area = v_area)
                OR (v_area IS NULL AND u.area IN ('servicio_tecnico', 'metrologia')));
    END IF;

    -- 3) Respaldo: Jefe / Coordinador de Operaciones
    IF (SELECT COUNT(*) FROM tmp_aut_destino) = 0 THEN
        INSERT IGNORE INTO tmp_aut_destino
        SELECT u.id_usuario, TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))), c.String1
        FROM   usuario u
        LEFT JOIN tabla_maestra c ON c.IdMaestro = 80 AND c.IdEmpresa = 1 AND c.String2 = u.cargo
        WHERE  u.eliminado_en IS NULL AND u.estado = 'activo'
          AND  u.cargo IN ('jefe_operaciones', 'coordinador_operaciones');
    END IF;

    -- 4) Respaldo final: administradores
    IF (SELECT COUNT(*) FROM tmp_aut_destino) = 0 THEN
        INSERT IGNORE INTO tmp_aut_destino
        SELECT u.id_usuario, TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))), NULL
        FROM   usuario u
        WHERE  u.eliminado_en IS NULL AND u.estado = 'activo' AND u.rol_sistema IN ('administrador', 'admin');
    END IF;

    INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por,
                              modulo_origen, tipo_origen, prioridad_origen)
    SELECT d.id_usuario, 5,
           CONCAT('Autorización de salida', IF(v_area_nombre IS NULL, '', CONCAT(' · ', v_area_nombre)), ': ', v_numero),
           CONCAT(v_tecnico, ' solicita tu visto bueno para salir a ', IFNULL(v_cliente, 'el cliente'), ' (', v_numero, ').',
                  IF(v_area_nombre IS NULL, ' La RQ no indica el área del servicio.', CONCAT(' Área del servicio según la RQ: ', v_area_nombre, '.')),
                  IF(NULLIF(TRIM(p_pendientes), '') IS NULL, '', CONCAT(' Pendientes: ', TRIM(p_pendientes), '.')),
                  IF(NULLIF(TRIM(p_motivo), '') IS NULL, '', CONCAT(' Motivo: ', TRIM(p_motivo)))),
           'orden_servicio', p_id_os, NOW(), p_id_usuario,
           'control_campo', 'autorizacion_salida', 'critica'
    FROM   tmp_aut_destino d;
    SET v_destinos = ROW_COUNT();

    SELECT GROUP_CONCAT(CONCAT(d.nombre, IFNULL(CONCAT(' (', d.cargo, ')'), '')) ORDER BY d.nombre SEPARATOR ', ')
    INTO   v_notificados
    FROM   tmp_aut_destino d;
    DROP TEMPORARY TABLE IF EXISTS tmp_aut_destino;

    -- Confirmación para el propio técnico (HU-04: "Solicitud de autorización enviada · avisado al Jefe …")
    INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
    VALUES (p_id_usuario, 5, 'Solicitud de autorización enviada',
            LEFT(CONCAT(v_numero, ' · ', IF(v_notificados IS NULL, 'sin un encargado activo para avisar', CONCAT('avisado a ', v_notificados))), 3000),
            'orden_servicio', p_id_os, NOW(), p_id_usuario);

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('orden_servicio', p_id_os, 'solicitar_autorizacion_salida', IFNULL(v_aut_estado, 'sin_solicitud'), 'pendiente',
            CONCAT('El técnico solicita visto bueno para salir.',
                   IF(NULLIF(TRIM(p_pendientes), '') IS NULL, '', CONCAT(' Pendientes: ', TRIM(p_pendientes), '.'))),
            p_id_usuario, NOW(), JSON_OBJECT('id_autorizacion', v_id_aut, 'area_destino', v_area, 'notificados', v_destinos));

    COMMIT;

    SELECT 2 AS IdTipoMensaje,
           IF(v_destinos > 0,
              CONCAT('Solicitud enviada a ', v_notificados, '.'),
              'Solicitud registrada, pero no hay un encargado activo para notificar: avisa a tu jefe.') AS Mensaje;
END$$

DELIMITER ;

-- ============================================================
-- SP_SolicitarLlegadaForzadaMovil  (App Mobile HU-06 — llegada forzada · escritura)
-- El técnico, que sigue fuera del radio permitido tras volver a capturar su ubicación (mínimo 5 veces), pide a Jefatura que le autorice registrar la llegada.
--   - El técnico sale del token; la OS debe ser suya y estar EN RUTA, sin llegada registrada en este viaje.
--   - La ubicación se evalúa AQUÍ (SP_EvaluarLlegadaMovil): solo se puede pedir si de verdad está fuera del rango (con señal GPS aceptable).
--     Dentro del rango o sin coordenada de la planta no hace falta autorización.
--   - Mínimo de intentos (p_intentos, lo cuenta la app) = 5: LLEGADA_FORZADA_INTENTOS (PARAMETRO_PROGRAMACION, por defecto 5).
--   - Una sola solicitud pendiente por OS; si ya hay una aprobada sin usar se avisa que ya puede registrar.
--   - Destinatarios: el encargado del área de la RQ (cargo jefe_*); respaldos: supervisores del área, Jefe/Coordinador de Operaciones, administradores
--     (misma regla que la autorización de salida, SP_SolicitarAutorizacionSalidaMovil). Les llega una notificación «Llegada forzada · OS».
--   - Deja una notificación de confirmación al técnico y el registro en auditoria_evento.
-- Resultado: 1 fila (IdTipoMensaje, Mensaje).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_SolicitarLlegadaForzadaMovil;

DELIMITER $$

CREATE PROCEDURE SP_SolicitarLlegadaForzadaMovil(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT,
    IN p_latitud    DECIMAL(10,7),
    IN p_longitud   DECIMAL(10,7),
    IN p_precision  DECIMAL(8,1),
    IN p_intentos   INT,
    IN p_motivo     VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_estado      VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_numero      VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cliente     VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tecnico     VARCHAR(210) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_area        VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_area_nombre VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_notificados VARCHAR(600) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_ult_estado  VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_ult_usada   DATETIME;
    DECLARE v_salida_utc  DATETIME;
    DECLARE v_ya_llego    TINYINT DEFAULT 0;
    DECLARE v_min_int     DECIMAL(18,6);
    DECLARE v_id_sol      BIGINT;
    DECLARE v_destinos    INT DEFAULT 0;
    DECLARE v_resultado   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_registrable TINYINT;
    DECLARE v_distancia   INT;
    DECLARE v_radio       INT;
    DECLARE v_pmax        INT;
    DECLARE v_lat_ref     DECIMAL(10,7);
    DECLARE v_lon_ref     DECIMAL(10,7);
    DECLARE v_mensaje     VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio no encontrado o no asignado a tu usuario.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF p_latitud IS NULL OR p_longitud IS NULL OR p_latitud NOT BETWEEN -90 AND 90 OR p_longitud NOT BETWEEN -180 AND 180
       OR (p_latitud = 0 AND p_longitud = 0) THEN
        SELECT 1 AS IdTipoMensaje, 'La ubicación GPS no es válida: activa el GPS e inténtalo de nuevo.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF p_precision IS NULL OR p_precision < 0 OR p_precision > 5000 THEN
        SELECT 1 AS IdTipoMensaje, 'La precisión del GPS no es válida.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_LeerParametroProgramacion('LLEGADA_FORZADA_INTENTOS', 5, v_min_int);
    IF IFNULL(p_intentos, 0) < v_min_int THEN
        SELECT 1 AS IdTipoMensaje, CONCAT('Vuelve a capturar tu ubicación al menos ', ROUND(v_min_int), ' veces antes de pedir la llegada forzada.') AS Mensaje;
        LEAVE proc;
    END IF;

    START TRANSACTION;

    SELECT os.estado, os.numero, COALESCE(NULLIF(cl.nombre_comercial, ''), cl.razon_social), asr.area_usuario
    INTO   v_estado, v_numero, v_cliente, v_area
    FROM   orden_servicio os
    LEFT JOIN cliente            cl  ON cl.id_cliente        = os.id_cliente
    LEFT JOIN expediente_digital ed  ON ed.id_expediente     = os.id_expediente
    LEFT JOIN requerimiento      rq  ON rq.id_requerimiento  = ed.id_requerimiento
    LEFT JOIN area_servicio_rq   asr ON asr.id_area_rq       = rq.id_area
    WHERE  os.id_os = p_id_os AND os.eliminado_en IS NULL
      AND  (os.id_tecnico_principal = p_id_usuario
            OR EXISTS (SELECT 1 FROM os_personal op
                       WHERE op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL))
    FOR UPDATE;

    IF v_estado IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Servicio no encontrado o no asignado a tu usuario.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_estado <> 'en_ruta' THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'La llegada solo se registra con el servicio en ruta.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- ¿Ya llegó en este viaje? (evento LLEGADA posterior a la última salida)
    SELECT MAX(e.timestamp_utc) INTO v_salida_utc
    FROM   evento_campo e
    JOIN   tabla_maestra m ON m.IdMaestro = 29 AND m.IdEmpresa = 1 AND m.Num1 = e.id_tipo_evento AND m.String2 = 'SALIDA_BASE'
    WHERE  e.id_os = p_id_os AND e.eliminado_en IS NULL;
    SELECT IF(COUNT(*) > 0, 1, 0) INTO v_ya_llego
    FROM   evento_campo e
    JOIN   tabla_maestra m ON m.IdMaestro = 29 AND m.IdEmpresa = 1 AND m.Num1 = e.id_tipo_evento AND m.String2 = 'LLEGADA'
    WHERE  e.id_os = p_id_os AND e.eliminado_en IS NULL AND e.timestamp_utc >= IFNULL(v_salida_utc, '1000-01-01');
    IF v_ya_llego = 1 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Ya registraste tu llegada.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT s.estado, s.usada_en INTO v_ult_estado, v_ult_usada
    FROM   llegada_forzada_os s
    WHERE  s.id_os = p_id_os AND s.eliminado_en IS NULL
    ORDER BY s.id_solicitud DESC LIMIT 1;

    IF v_ult_estado = 'pendiente' THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Ya enviaste la solicitud: espera la respuesta de Jefatura.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_ult_estado = 'aprobada' AND v_ult_usada IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Jefatura ya autorizó tu llegada: confírmala.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Solo se pide estando de verdad fuera del rango
    CALL SP_EvaluarLlegadaMovil(p_id_os, p_latitud, p_longitud, p_precision, v_resultado, v_registrable, v_distancia, v_radio, v_pmax,
                                v_lat_ref, v_lon_ref, v_mensaje);
    IF v_resultado <> 'fuera_rango' THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje,
               CASE v_resultado
                   WHEN 'precision_baja' THEN v_mensaje
                   ELSE 'No hace falta autorización: tu ubicación ya permite registrar la llegada.' END AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT TRIM(CONCAT(IFNULL(nombre, ''), ' ', IFNULL(apellido, ''))) INTO v_tecnico FROM usuario WHERE id_usuario = p_id_usuario;
    SET v_area_nombre = (SELECT t.String1 FROM tabla_maestra t WHERE t.IdMaestro = 79 AND t.IdEmpresa = 1 AND t.String2 = v_area LIMIT 1);

    INSERT INTO llegada_forzada_os (id_os, id_tecnico, estado, motivo, intentos, latitud, longitud, precision_metros, distancia_metros,
                                    area_destino, solicitado_en, creado_por)
    VALUES (p_id_os, p_id_usuario, 'pendiente', NULLIF(TRIM(p_motivo), ''), p_intentos, p_latitud, p_longitud, p_precision, v_distancia,
            v_area, NOW(), p_id_usuario);
    SET v_id_sol = LAST_INSERT_ID();

    -- Destinatarios (misma regla que la autorización de salida)
    DROP TEMPORARY TABLE IF EXISTS tmp_llf_destino;
    CREATE TEMPORARY TABLE tmp_llf_destino (
        id_usuario BIGINT PRIMARY KEY,
        nombre     VARCHAR(210) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        cargo      VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
    );

    -- Regla Área + Rol (SP_ArmarAprobadoresMovil)
    CALL SP_ArmarAprobadoresMovil(v_area);
    INSERT IGNORE INTO tmp_llf_destino
    SELECT u.id_usuario, TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))), c.String1
    FROM   tmp_aprobadores a
    JOIN   usuario u ON u.id_usuario = a.id_usuario
    LEFT JOIN tabla_maestra c ON c.IdMaestro = 80 AND c.IdEmpresa = 1 AND c.String2 = u.cargo
    WHERE  u.id_usuario <> p_id_usuario;
    DROP TEMPORARY TABLE IF EXISTS tmp_aprobadores;

    IF (SELECT COUNT(*) FROM tmp_llf_destino) = 0 THEN
        INSERT IGNORE INTO tmp_llf_destino
        SELECT u.id_usuario, TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))), NULL
        FROM   usuario u
        WHERE  u.eliminado_en IS NULL AND u.estado = 'activo' AND u.rol_sistema IN ('supervisor', 'administrador')
          AND  ((v_area IS NOT NULL AND u.area = v_area) OR (v_area IS NULL AND u.area IN ('servicio_tecnico', 'metrologia')));
    END IF;
    IF (SELECT COUNT(*) FROM tmp_llf_destino) = 0 THEN
        INSERT IGNORE INTO tmp_llf_destino
        SELECT u.id_usuario, TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))), NULL
        FROM   usuario u
        WHERE  u.eliminado_en IS NULL AND u.estado = 'activo' AND u.cargo IN ('jefe_operaciones', 'coordinador_operaciones');
    END IF;
    IF (SELECT COUNT(*) FROM tmp_llf_destino) = 0 THEN
        INSERT IGNORE INTO tmp_llf_destino
        SELECT u.id_usuario, TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))), NULL
        FROM   usuario u
        WHERE  u.eliminado_en IS NULL AND u.estado = 'activo' AND u.rol_sistema IN ('administrador', 'admin');
    END IF;

    INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
    SELECT d.id_usuario, 5,
           CONCAT('Llegada forzada', IF(v_area_nombre IS NULL, '', CONCAT(' · ', v_area_nombre)), ': ', v_numero),
           LEFT(CONCAT(v_tecnico, ' está a ', FORMAT(v_distancia, 0), ' m de la planta de ', IFNULL(v_cliente, 'el cliente'), ' (', v_numero, ') y pide autorización para registrar su llegada.',
                       ' Capturó su ubicación ', p_intentos, ' veces (permitido hasta ', v_radio, ' m).',
                       IF(NULLIF(TRIM(p_motivo), '') IS NULL, '', CONCAT(' Motivo: ', TRIM(p_motivo)))), 3000),
           'orden_servicio', p_id_os, NOW(), p_id_usuario
    FROM   tmp_llf_destino d;
    SET v_destinos = ROW_COUNT();

    SELECT GROUP_CONCAT(CONCAT(d.nombre, IFNULL(CONCAT(' (', d.cargo, ')'), '')) ORDER BY d.nombre SEPARATOR ', ') INTO v_notificados FROM tmp_llf_destino d;
    DROP TEMPORARY TABLE IF EXISTS tmp_llf_destino;

    INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
    VALUES (p_id_usuario, 5, 'Solicitud de llegada forzada enviada',
            LEFT(CONCAT(v_numero, ' · ', IF(v_notificados IS NULL, 'sin un encargado activo para avisar', CONCAT('avisado a ', v_notificados))), 3000),
            'orden_servicio', p_id_os, NOW(), p_id_usuario);

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('orden_servicio', p_id_os, 'solicitar_llegada_forzada', IFNULL(v_ult_estado, 'sin_solicitud'), 'pendiente',
            LEFT(CONCAT('El técnico pide autorización para registrar la llegada a ', v_distancia, ' m de la planta tras ', p_intentos, ' capturas.',
                        IF(NULLIF(TRIM(p_motivo), '') IS NULL, '', CONCAT(' Motivo: ', TRIM(p_motivo)))), 900),
            p_id_usuario, NOW(),
            JSON_OBJECT('id_solicitud', v_id_sol, 'distancia_m', v_distancia, 'intentos', p_intentos, 'area_destino', v_area, 'notificados', v_destinos));

    COMMIT;

    SELECT 2 AS IdTipoMensaje,
           IF(v_destinos > 0, CONCAT('Solicitud enviada a ', v_notificados, '. Espera su aprobación para registrar tu llegada.'),
              'Solicitud registrada, pero no hay un encargado activo para notificar: avisa a tu jefe.') AS Mensaje;
END$$

DELIMITER ;

-- ============================================================
-- SP_GuardarEnsayosMovil  (App Mobile HU-10 — Ensayos y Calibración · escritura)
-- Guarda las lecturas de pesaje y excentricidad del equipo. La app envía SOLO la carga (L) y la indicación (I); aquí se calcula el error (E = I − L),
-- el EMP (SP_EmpEnsayoMovil) y la conformidad (|E| ≤ EMP): nunca se confía en lo que la app mostró.
--   - Acceso (SP_ContextoEnsayoMovil): OS del técnico, llegada registrada (Hard Stop), equipo EN EJECUCIÓN y variables ambientales guardadas (HU-09).
--   - p_json = {"pesaje":[{"carga":10000,"indicacion":10005}], "excentricidad":[{"carga":26000,"lecturas":[26000,26004,null,…]}]}. Se puede guardar
--     incompleto (borrador); cada guardado REEMPLAZA las lecturas del técnico de ese informe.
--   - Excentricidad: posiciones por forma del plato (rectangular y circular 5, triangular 4); la lectura 1 es el centro.
--   - Error crítico = una lectura fuera del EMP. Se puede guardar igual (borrador); para FINALIZAR hay que corregirlo o aceptarlo con un motivo (3 a 300
--     caracteres, "Guardar de todas formas"): el motivo se guarda, el ensayo queda marcado con error en el informe y se avisa al encargado del área.
--   - p_finalizar = 1 exige pesaje y excentricidad completos (todas las posiciones de cada carga) y marca la etapa como finalizada; guardar de nuevo
--     sin finalizar la reabre ("Editar lecturas").
--   - Crea el informe técnico en borrador (informe_tecnico, número provisional BRR-…) si todavía no existe; lo definitivo lo asigna la generación del informe.
--   - Deja el registro en auditoria_evento.
-- Resultados: 1 mensaje; 2 (id_informe, criticos, finalizado, notificados).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_GuardarEnsayosMovil;

DELIMITER $$

CREATE PROCEDURE SP_GuardarEnsayosMovil(
    IN p_id_usuario   BIGINT,
    IN p_id_os        BIGINT,
    IN p_id_os_equipo BIGINT,
    IN p_forma        VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_json         LONGTEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_motivo       VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_finalizar    TINYINT
)
proc: BEGIN
    DECLARE v_msg      VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_eq    BIGINT;
    DECLARE v_est_eq   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_hab      TINYINT;
    DECLARE v_numero   INT;
    DECLARE v_nombre   VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_num_os   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_clase    VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_unidad   VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cap      DECIMAL(14,4);
    DECLARE v_d        DECIMAL(14,4);
    DECLARE v_e        DECIMAL(14,4);
    DECLARE v_forma    VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_motivo   VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_motivo_ant VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_pos_req  INT;
    DECLARE v_n        INT DEFAULT 0;
    DECLARE v_i        INT DEFAULT 0;
    DECLARE v_fila     BIGINT;
    DECLARE v_carga    DECIMAL(14,4);
    DECLARE v_emp      DECIMAL(14,4);
    DECLARE v_n_pes    INT DEFAULT 0;
    DECLARE v_n_ecc    INT DEFAULT 0;
    DECLARE v_incompl  INT DEFAULT 0;
    DECLARE v_invalid  INT DEFAULT 0;
    DECLARE v_criticos INT DEFAULT 0;
    DECLARE v_err_max  DECIMAL(14,4) DEFAULT NULL;
    DECLARE v_informe  BIGINT DEFAULT NULL;
    DECLARE v_final    TINYINT DEFAULT 0;
    DECLARE v_area     VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_enc   BIGINT;
    DECLARE v_nom_enc  VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_car_enc  VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tel_enc  VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_nombre_tec VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_texto    VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_notif    INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_ens_filas;
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 OR IFNULL(p_id_os_equipo, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio o equipo no encontrado.' AS Mensaje; LEAVE proc;
    END IF;
    SET v_forma = LOWER(TRIM(IFNULL(p_forma, 'rectangular')));
    IF v_forma NOT IN ('rectangular', 'circular', 'triangular') THEN
        SELECT 1 AS IdTipoMensaje, 'La forma del plato no es válida.' AS Mensaje; LEAVE proc;
    END IF;
    SET v_pos_req = IF(v_forma = 'triangular', 4, 5);
    IF p_json IS NULL OR NOT JSON_VALID(p_json) OR CHAR_LENGTH(p_json) > 30000 THEN
        SELECT 1 AS IdTipoMensaje, 'Las lecturas enviadas no son válidas.' AS Mensaje; LEAVE proc;
    END IF;
    SET v_motivo = NULLIF(TRIM(IFNULL(p_motivo, '')), '');
    IF v_motivo IS NOT NULL AND (CHAR_LENGTH(v_motivo) < 3 OR CHAR_LENGTH(v_motivo) > 300) THEN
        SELECT 1 AS IdTipoMensaje, 'El motivo debe tener entre 3 y 300 caracteres.' AS Mensaje; LEAVE proc;
    END IF;

    START TRANSACTION;

    CALL SP_ContextoEnsayoMovil(p_id_usuario, p_id_os, p_id_os_equipo, v_msg, v_id_eq, v_est_eq, v_hab, v_numero, v_nombre, v_num_os, v_clase, v_unidad, v_cap, v_d, v_e);
    IF v_msg IS NULL AND (v_hab = 0 OR v_est_eq <> 'en_ejecucion') THEN
        SET v_msg = IF(v_est_eq = 'pausado', 'El equipo está pausado: reanúdalo para registrar los ensayos.',
                       IF(v_est_eq = 'completado', 'Este equipo ya está completado.', 'El servicio ya no está en curso: no se pueden registrar ensayos.'));
    END IF;
    IF v_msg IS NULL AND (v_clase IS NULL OR v_e IS NULL OR v_e <= 0) THEN
        SET v_msg = 'El equipo no tiene clase de exactitud o división e registradas: complétalas en la ficha del equipo para evaluar el ensayo.';
    END IF;
    IF v_msg IS NOT NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje; LEAVE proc;
    END IF;

    -- ── Lecturas que llegan ─────────────────────────────────────────────────────────────────────
    DROP TEMPORARY TABLE IF EXISTS tmp_ens_filas;
    CREATE TEMPORARY TABLE tmp_ens_filas (
        id INT NOT NULL AUTO_INCREMENT, tipo VARCHAR(15) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, grupo INT NULL, pos INT NULL,
        carga DECIMAL(14,4) NULL, ind DECIMAL(14,4) NULL, emp DECIMAL(14,4) NULL, err DECIMAL(14,4) NULL, res VARCHAR(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        PRIMARY KEY (id));

    INSERT INTO tmp_ens_filas (tipo, grupo, pos, carga, ind)
    SELECT 'pesaje', NULL, jt.n, jt.carga, jt.ind
    FROM   JSON_TABLE(p_json, '$.pesaje[*]' COLUMNS (
               n FOR ORDINALITY,
               carga DECIMAL(14,4) PATH '$.carga'      NULL ON EMPTY NULL ON ERROR,
               ind   DECIMAL(14,4) PATH '$.indicacion' NULL ON EMPTY NULL ON ERROR)) jt;

    INSERT INTO tmp_ens_filas (tipo, grupo, pos, carga, ind)
    SELECT 'excentricidad', jt.g, jt.pos, jt.carga, jt.ind
    FROM   JSON_TABLE(p_json, '$.excentricidad[*]' COLUMNS (
               g FOR ORDINALITY,
               carga DECIMAL(14,4) PATH '$.carga' NULL ON EMPTY NULL ON ERROR,
               NESTED PATH '$.lecturas[*]' COLUMNS (
                   pos FOR ORDINALITY,
                   ind DECIMAL(14,4) PATH '$' NULL ON EMPTY NULL ON ERROR))) jt
    WHERE  jt.pos IS NOT NULL;

    SELECT COUNT(*) INTO v_n FROM tmp_ens_filas;
    SELECT COUNT(*) INTO v_n_pes FROM tmp_ens_filas WHERE tipo = 'pesaje';
    SELECT COUNT(DISTINCT grupo) INTO v_n_ecc FROM tmp_ens_filas WHERE tipo = 'excentricidad';

    -- Límites: cantidad de filas, cargas e indicaciones razonables y posiciones según la forma del plato
    SELECT COUNT(*) INTO v_invalid
    FROM   tmp_ens_filas
    WHERE  carga IS NULL OR carga <= 0 OR carga > 100000000 OR (ind IS NOT NULL AND (ind < 0 OR ind > 100000000))
        OR (tipo = 'pesaje' AND pos > 12) OR (tipo = 'excentricidad' AND (grupo > 10 OR pos > v_pos_req));
    IF v_n = 0 OR v_n_pes > 12 OR v_n_ecc > 10 OR v_invalid > 0 THEN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_ens_filas;
        SELECT 1 AS IdTipoMensaje,
               IF(v_n = 0, 'No hay lecturas para guardar.',
                  'Revisa las lecturas: cada carga debe ser mayor que 0, las indicaciones no pueden ser negativas y no se aceptan más de 12 cargas de pesaje, 10 de excentricidad ni posiciones fuera del plato.') AS Mensaje;
        LEAVE proc;
    END IF;

    -- ── EMP, error y conformidad: aquí, una sola vez ───────────────────────────────────────────
    WHILE v_i < v_n DO
        SELECT id, carga INTO v_fila, v_carga FROM tmp_ens_filas ORDER BY id LIMIT 1 OFFSET v_i;
        CALL SP_EmpEnsayoMovil(v_clase, v_e, v_carga, v_emp);
        UPDATE tmp_ens_filas SET emp = v_emp WHERE id = v_fila;
        SET v_i = v_i + 1;
    END WHILE;
    UPDATE tmp_ens_filas
    SET    err = IF(ind IS NULL, NULL, ind - carga),
           res = IF(ind IS NULL OR emp IS NULL, NULL, IF(ABS(ind - carga) <= emp, 'conforme', 'no_conforme'));

    SELECT COUNT(*) INTO v_criticos FROM tmp_ens_filas WHERE res = 'no_conforme';
    SELECT MAX(ABS(err)) INTO v_err_max FROM tmp_ens_filas WHERE tipo = 'pesaje';

    -- Completitud (para finalizar): todo con indicación y cada carga de excentricidad con todas sus posiciones
    SELECT COUNT(*) INTO v_incompl FROM tmp_ens_filas WHERE ind IS NULL;
    IF v_n_pes = 0 OR v_n_ecc = 0 THEN SET v_incompl = v_incompl + 1; END IF;
    SELECT COUNT(*) INTO v_invalid
    FROM  (SELECT grupo, COUNT(*) AS c FROM tmp_ens_filas WHERE tipo = 'excentricidad' GROUP BY grupo HAVING COUNT(*) <> v_pos_req) x;
    SET v_incompl = v_incompl + v_invalid;

    IF p_finalizar = 1 THEN
        IF v_incompl > 0 THEN
            ROLLBACK;
            DROP TEMPORARY TABLE IF EXISTS tmp_ens_filas;
            SELECT 1 AS IdTipoMensaje, 'Completa todas las lecturas de pesaje y de excentricidad (todas las posiciones de cada carga) antes de finalizar el ensayo.' AS Mensaje;
            LEAVE proc;
        END IF;
        IF v_criticos > 0 AND v_motivo IS NULL THEN
            ROLLBACK;
            DROP TEMPORARY TABLE IF EXISTS tmp_ens_filas;
            SELECT 1 AS IdTipoMensaje, 'Hay un error crítico: corrige la lectura, repite el ensayo o usa "Guardar de todas formas" con un motivo.' AS Mensaje;
            LEAVE proc;
        END IF;
        SET v_final = 1;
    END IF;

    -- ── Informe técnico (borrador) ───────────────────────────────────────────────────────────
    SELECT it.id_informe, it.error_critico_motivo INTO v_informe, v_motivo_ant
    FROM   informe_tecnico it
    WHERE  it.id_os = p_id_os AND it.id_equipo = v_id_eq AND it.eliminado_en IS NULL
    ORDER BY it.id_informe DESC LIMIT 1
    FOR UPDATE;
    IF v_informe IS NULL THEN
        INSERT INTO informe_tecnico (numero, id_os, id_equipo, id_tecnico, estado, version, fecha_creacion, creado_por)
        VALUES (CONCAT('BRR-', FLOOR(RAND() * 1000000000)), p_id_os, v_id_eq, p_id_usuario, 'borrador', 1, NOW(), p_id_usuario);
        SET v_informe = LAST_INSERT_ID();
        UPDATE informe_tecnico SET numero = CONCAT('BRR-', LPAD(v_informe, 8, '0')) WHERE id_informe = v_informe;
    END IF;

    UPDATE informe_ensayo
    SET    eliminado_en = NOW(), eliminado_por = p_id_usuario
    WHERE  id_informe = v_informe AND tipo IN ('pesaje', 'excentricidad') AND origen = 'tecnico' AND eliminado_en IS NULL;

    INSERT INTO informe_ensayo (id_informe, tipo, orden, punto, carga, lectura, error, tolerancia, resultado, origen, creado_por, grupo, critico)
    SELECT v_informe, t.tipo, t.pos, IF(t.tipo = 'pesaje', CONCAT('Carga ', t.pos), CONCAT('Pos. ', t.pos)), t.carga, t.ind, t.err, t.emp, t.res,
           'tecnico', p_id_usuario, t.grupo, IF(t.res = 'no_conforme', 1, 0)
    FROM   tmp_ens_filas t
    ORDER BY t.id;

    UPDATE informe_tecnico
    SET    forma_plato = v_forma,
           error_critico_motivo = IF(v_criticos > 0, v_motivo, NULL),
           error_critico_notificado_en = IF(v_criticos > 0, error_critico_notificado_en, NULL),
           ensayos_finalizado_en = IF(v_final = 1, UTC_TIMESTAMP(), NULL),
           resultado_global = IF(v_criticos > 0, 'fuera', 'dentro'),
           error_maximo = v_err_max,
           modificado_por = p_id_usuario
    WHERE  id_informe = v_informe;

    -- ── Error crítico aceptado: aviso al encargado del área (y, si no hay, a los administradores) ──────────
    IF v_criticos > 0 AND v_motivo IS NOT NULL AND (v_motivo_ant IS NULL OR v_motivo_ant <> v_motivo) THEN
        CALL SP_ContactoEncargadoEnsayoMovil(p_id_os, v_area, v_id_enc, v_nom_enc, v_car_enc, v_tel_enc);
        SELECT TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))) INTO v_nombre_tec FROM usuario u WHERE u.id_usuario = p_id_usuario LIMIT 1;
        SET v_texto = LEFT(CONCAT(v_nombre_tec, ' guardó el ensayo de ', v_nombre, ' (', v_num_os, ') con ', v_criticos,
                                  IF(v_criticos = 1, ' lectura fuera', ' lecturas fuera'), ' del EMP. Motivo: ', v_motivo), 500);
        -- Regla Área + Rol (SP_ArmarAprobadoresOsMovil): ven y reciben el aviso las áreas que ven todo y el Supervisor del área de la OS
        CALL SP_ArmarAprobadoresOsMovil(p_id_os);
        INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
        SELECT a.id_usuario, 5, 'Ensayo con error crítico', v_texto, 'orden_servicio', p_id_os, NOW(), p_id_usuario
        FROM   tmp_aprobadores a
        WHERE  a.id_usuario <> p_id_usuario;
        SET v_notif = ROW_COUNT();
        DROP TEMPORARY TABLE IF EXISTS tmp_aprobadores;
        IF v_notif > 0 THEN
            SET v_notif = v_notif;
        ELSEIF v_id_enc IS NOT NULL AND v_id_enc <> p_id_usuario THEN
            INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
            VALUES (v_id_enc, 5, 'Ensayo con error crítico', v_texto, 'orden_servicio', p_id_os, NOW(), p_id_usuario);
            SET v_notif = 1;
        ELSE
            INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
            SELECT u.id_usuario, 5, 'Ensayo con error crítico', v_texto, 'orden_servicio', p_id_os, NOW(), p_id_usuario
            FROM   usuario u
            WHERE  u.eliminado_en IS NULL AND u.estado = 'activo' AND u.id_usuario <> p_id_usuario AND u.rol_sistema IN ('administrador', 'admin');
            SET v_notif = ROW_COUNT();
        END IF;
        -- Quedó constancia de que se avisó (o de que no había a quién avisar): con el aviso hecho, el ensayo ya no bloquea el cierre del equipo (HU-16)
        UPDATE informe_tecnico SET error_critico_notificado_en = IF(v_notif > 0, NOW(), NULL) WHERE id_informe = v_informe;
    END IF;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('os_equipo', p_id_os_equipo, IF(v_final = 1, 'finalizar_ensayos', 'guardar_ensayos'), NULL, IF(v_final = 1, 'finalizado', 'borrador'),
            LEFT(CONCAT(IF(v_final = 1, 'Ensayos finalizados', 'Ensayos guardados'), ' en ', v_num_os, ': ', v_n_pes, ' cargas de pesaje, ', v_n_ecc, ' de excentricidad, ',
                        v_criticos, ' fuera del EMP', IF(v_criticos > 0 AND v_motivo IS NOT NULL, CONCAT('. Motivo: ', v_motivo), '')), 900),
            p_id_usuario, NOW(),
            JSON_OBJECT('id_informe', v_informe, 'criticos', v_criticos, 'clase', v_clase, 'e', v_e));

    COMMIT;
    DROP TEMPORARY TABLE IF EXISTS tmp_ens_filas;

    SELECT 2 AS IdTipoMensaje,
           IF(v_final = 1, 'Ensayo finalizado.', IF(v_criticos > 0 AND v_motivo IS NOT NULL, 'Ensayo guardado con error crítico: se avisó al encargado.', 'Ensayo guardado.')) AS Mensaje;
    SELECT v_informe AS id_informe, v_criticos AS criticos, v_final AS finalizado, v_notif AS notificados;
END$$

DELIMITER ;

-- ============================================================
-- SP_ForzarEvidenciaMovil  (App Mobile HU-12 — Override de evidencia fotográfica · escritura)
-- El técnico acepta a la fuerza una toma que la IA rechazó, en una situación excepcional donde no puede conseguir una mejor.
--   - Solo con un MOTIVO ESCRITO (3 a 300 caracteres). Solo se fuerza la última captura de la evidencia (vigente) y solo si está rechazada.
--   - Acceso: OS del técnico, Hard Stop y equipo EN EJECUCIÓN (SP_ContextoEquipoMovil).
--   - Marca la evidencia FORZADA (override_aprobado = 1) con el motivo, quién y cuándo (la validación de la IA y su motivo de rechazo se conservan).
--     Cuenta como completa en el panel.
--   - Consecuencias que la app muestra ANTES de confirmar y que se cumplen aquí: queda registrada como excepción en el expediente (auditoria_evento),
--     suma al contador de evidencias forzadas del scorecard del técnico del mes (tecnico_scorecard.foto_override_count) y queda visible para Jefatura
--     (notificación al encargado del área según la RQ; si no hay, a los administradores).
--   - Repetir la petición sobre una evidencia ya forzada responde éxito sin duplicar nada.
-- Resultados: 1 mensaje; 2 (id_evidencia, forzada_en en Lima, intentos_previos, notificados).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ForzarEvidenciaMovil;

DELIMITER $$

CREATE PROCEDURE SP_ForzarEvidenciaMovil(
    IN p_id_usuario    BIGINT,
    IN p_id_os         BIGINT,
    IN p_id_os_equipo  BIGINT,
    IN p_id_evidencia  BIGINT,
    IN p_motivo        VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_msg      VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_eq    BIGINT;
    DECLARE v_est_eq   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_hab      TINYINT;
    DECLARE v_numero   INT;
    DECLARE v_nombre   VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_num_os   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_servicio VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_motivo   VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_codigo   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_valida   VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_ya       TINYINT DEFAULT 0;
    DECLARE v_vigente  TINYINT DEFAULT 0;
    DECLARE v_intento  INT DEFAULT 1;
    DECLARE v_motivo_ia VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_forzada  DATETIME DEFAULT NULL;
    DECLARE v_mes      DATE;
    DECLARE v_area     VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_enc   BIGINT;
    DECLARE v_nom_enc  VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_car_enc  VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tel_enc  VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_nombre_tec VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_texto    VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_notif    INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 OR IFNULL(p_id_os_equipo, 0) <= 0 OR IFNULL(p_id_evidencia, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Evidencia no encontrada.' AS Mensaje; LEAVE proc;
    END IF;
    SET v_motivo = NULLIF(TRIM(IFNULL(p_motivo, '')), '');
    IF v_motivo IS NULL OR CHAR_LENGTH(v_motivo) < 3 THEN
        SELECT 1 AS IdTipoMensaje, 'Escribe el motivo por el que aceptas la foto (mínimo 3 caracteres).' AS Mensaje; LEAVE proc;
    END IF;
    IF CHAR_LENGTH(v_motivo) > 300 THEN
        SELECT 1 AS IdTipoMensaje, 'El motivo puede tener hasta 300 caracteres.' AS Mensaje; LEAVE proc;
    END IF;

    START TRANSACTION;

    CALL SP_ContextoEquipoMovil(p_id_usuario, p_id_os, p_id_os_equipo, v_msg, v_id_eq, v_est_eq, v_hab, v_numero, v_nombre, v_num_os, v_servicio);
    IF v_msg IS NULL AND (v_hab = 0 OR v_est_eq <> 'en_ejecucion') THEN
        SET v_msg = IF(v_est_eq = 'pausado', 'El equipo está pausado: reanúdalo para registrar evidencias.',
                       IF(v_est_eq = 'completado', 'Este equipo ya está completado.', 'El servicio ya no está en curso: no se pueden registrar evidencias.'));
    END IF;
    IF v_msg IS NOT NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje; LEAVE proc;
    END IF;

    SELECT f.codigo, f.validacion_ia, f.override_aprobado, f.vigente, f.intento, f.motivo_rechazo_ia, f.forzada_en
    INTO   v_codigo, v_valida, v_ya, v_vigente, v_intento, v_motivo_ia, v_forzada
    FROM   evidencia_fotografica f
    WHERE  f.id_evidencia = p_id_evidencia AND f.id_os = p_id_os AND f.id_equipo = v_id_eq AND f.eliminado_en IS NULL
    FOR UPDATE;

    IF v_codigo IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Evidencia no encontrada.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_ya = 1 THEN
        COMMIT;
        SELECT 2 AS IdTipoMensaje, 'Esta evidencia ya estaba aceptada como forzada.' AS Mensaje;
        SELECT p_id_evidencia AS id_evidencia, CONVERT_TZ(v_forzada, '+00:00', '-05:00') AS forzada_en, v_intento - 1 AS intentos_previos, 0 AS notificados;
        LEAVE proc;
    END IF;
    IF v_valida <> 'rechazada' THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Solo se puede forzar una foto que la IA rechazó.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_vigente = 0 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Esa toma ya fue reemplazada por una más reciente.' AS Mensaje; LEAVE proc;
    END IF;

    SET v_forzada = UTC_TIMESTAMP();
    UPDATE evidencia_fotografica
    SET    override_aprobado = 1, id_usuario_override = p_id_usuario, motivo_forzado = v_motivo, forzada_en = v_forzada, modificado_por = p_id_usuario
    WHERE  id_evidencia = p_id_evidencia;

    -- Scorecard del técnico (mes en curso, hora de Lima)
    SET v_mes = DATE_FORMAT(UTC_TIMESTAMP() - INTERVAL 5 HOUR, '%Y-%m-01');
    UPDATE tecnico_scorecard SET foto_override_count = foto_override_count + 1, modificado_por = p_id_usuario
    WHERE  id_usuario = p_id_usuario AND periodo_mes = v_mes AND eliminado_en IS NULL;
    IF ROW_COUNT() = 0 THEN
        INSERT INTO tecnico_scorecard (id_usuario, periodo_mes, foto_override_count, creado_por) VALUES (p_id_usuario, v_mes, 1, p_id_usuario);
    END IF;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('os_equipo', p_id_os_equipo, 'forzar_evidencia', 'rechazada', 'forzada',
            LEFT(CONCAT('Evidencia ', v_codigo, ' de ', v_num_os, ' aceptada a la fuerza tras ', v_intento, IF(v_intento = 1, ' intento', ' intentos'),
                        '. Rechazo de la IA: ', IFNULL(v_motivo_ia, '—'), '. Motivo del técnico: ', v_motivo), 900),
            p_id_usuario, NOW(),
            JSON_OBJECT('id_evidencia', p_id_evidencia, 'codigo', v_codigo, 'intentos', v_intento, 'motivo', v_motivo, 'motivo_ia', v_motivo_ia));

    -- Visible para Jefatura: aviso al encargado del área (si no hay, a los administradores)
    CALL SP_ContactoEncargadoEnsayoMovil(p_id_os, v_area, v_id_enc, v_nom_enc, v_car_enc, v_tel_enc);
    SELECT TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))) INTO v_nombre_tec FROM usuario u WHERE u.id_usuario = p_id_usuario LIMIT 1;
    SET v_texto = LEFT(CONCAT(v_nombre_tec, ' aceptó a la fuerza la evidencia «', v_codigo, '» de ', v_nombre, ' (', v_num_os, '), rechazada por la IA. Motivo: ', v_motivo), 500);
    -- Regla Área + Rol (SP_ArmarAprobadoresOsMovil): ven y reciben el aviso las áreas que ven todo y el Supervisor del área de la OS
    CALL SP_ArmarAprobadoresOsMovil(p_id_os);
    INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
    SELECT a.id_usuario, 5, 'Evidencia forzada', v_texto, 'orden_servicio', p_id_os, NOW(), p_id_usuario
    FROM   tmp_aprobadores a
    WHERE  a.id_usuario <> p_id_usuario;
    SET v_notif = ROW_COUNT();
    DROP TEMPORARY TABLE IF EXISTS tmp_aprobadores;
    IF v_notif > 0 THEN
        SET v_notif = v_notif;
    ELSEIF v_id_enc IS NOT NULL AND v_id_enc <> p_id_usuario THEN
        INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
        VALUES (v_id_enc, 5, 'Evidencia forzada', v_texto, 'orden_servicio', p_id_os, NOW(), p_id_usuario);
        SET v_notif = 1;
    ELSE
        INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
        SELECT u.id_usuario, 5, 'Evidencia forzada', v_texto, 'orden_servicio', p_id_os, NOW(), p_id_usuario
        FROM   usuario u
        WHERE  u.eliminado_en IS NULL AND u.estado = 'activo' AND u.id_usuario <> p_id_usuario AND u.rol_sistema IN ('administrador', 'admin');
        SET v_notif = ROW_COUNT();
    END IF;

    COMMIT;

    SELECT 2 AS IdTipoMensaje, 'Foto aceptada como evidencia forzada: quedó registrada y visible para Jefatura.' AS Mensaje;
    SELECT p_id_evidencia AS id_evidencia, CONVERT_TZ(v_forzada, '+00:00', '-05:00') AS forzada_en, v_intento - 1 AS intentos_previos, v_notif AS notificados;
END$$

DELIMITER ;

-- ============================================================
-- SP_RegistrarEquipoNuevoMovil  (App Mobile HU-07 — "Equipo nuevo (NEW)" · escritura)
-- El técnico registra en campo un equipo que no está en la lista de la O/S ("Registrar y seleccionar").
--   - El técnico sale del token; la OS debe ser suya. Hard Stop (HU-06): solo con la llegada registrada y la OS en curso (SP_EvaluarCampoMovil).
--   - Obligatorios: N/S, código del cliente, marca (del catálogo MARCA_SUMINISTRO), modelo, tipo de equipo (suministro activo de clase
--     equipo / instrumento / pesa), ubicación y la foto de la placa (solo cámara; la valida y guarda el back antes de llamar a este SP).
--   - El cliente y la sede salen de la OS. La clasificación sale de la clase del suministro.
--   - Si el equipo YA existe en el maestro del cliente (mismo N/S + marca + modelo) NO se duplica: se agrega a esta O/S como objetivo
--     (ya_existia = 1, la foto no se usa). Si ya está en la lista de esta O/S: no se agrega otra vez (responde cuál es), salvo que lo haya
--     registrado el mismo técnico en esta O/S (reintento de la app): responde éxito con el ya registrado (ya_registrado = 1).
--   - Equipo creado: equipo_cliente en estado 'borrador' (pendiente de aprobación de la intranet) con COD TW PROVISIONAL "NEW-000123";
--     la intranet asigna el COD TW definitivo (EQ-TW-AAAA-NNNN) al aprobar el registro. Queda marcado registrado_en_campo, con la O/S y la
--     foto de la placa. El objetivo (os_equipo) queda con ingresado_en_campo = 1 y el mismo tipo de intervención que los demás de la O/S.
--   - Avisa por notificación a los supervisores/administradores del área del técnico y a su jefe (jefe_<área>); si no hay, a los administradores.
--   - Deja el registro en auditoria_evento (equipo_cliente y os_equipo).
-- Resultados: 1 mensaje; 2 (id_os_equipo, id_equipo, codigo_tw, ya_existia, ya_registrado, foto_guardada, notificados).
--   foto_guardada = 1 solo si el equipo se creó con esa foto (si no, el back borra el archivo).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_RegistrarEquipoNuevoMovil;

DELIMITER $$

CREATE PROCEDURE SP_RegistrarEquipoNuevoMovil(
    IN p_id_usuario     BIGINT,
    IN p_id_os          BIGINT,
    IN p_num_serie      VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_codigo_cliente VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_marca          VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_modelo         VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_suministro  BIGINT,
    IN p_ubicacion      VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_foto_placa     VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_serie       VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_codigo_cli  VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_marca       VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_modelo      VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_marca_cat   VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_ubicacion   VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado_os   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_numero_os   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_cliente  BIGINT;
    DECLARE v_id_sede     BIGINT;
    DECLARE v_salida_utc  DATETIME;
    DECLARE v_llegada_utc DATETIME;
    DECLARE v_habilitado  TINYINT;
    DECLARE v_motivo_no   VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_clase       VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_id_equipo   BIGINT DEFAULT NULL;
    DECLARE v_codigo_tw   VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_oe       BIGINT DEFAULT NULL;
    DECLARE v_oe_campo    TINYINT DEFAULT 0;
    DECLARE v_oe_orden    INT DEFAULT NULL;
    DECLARE v_oe_usuario  BIGINT DEFAULT NULL;
    DECLARE v_ya_existia  TINYINT DEFAULT 0;
    DECLARE v_ya_reg      TINYINT DEFAULT 0;
    DECLARE v_foto_ok     TINYINT DEFAULT 0;
    DECLARE v_tipo_interv INT DEFAULT NULL;
    DECLARE v_orden       INT DEFAULT 1;
    DECLARE v_area        VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_login       VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_nombre_tec  VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_texto       VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_notif       INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio no encontrado o no asignado a tu usuario.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_serie      = TRIM(IFNULL(p_num_serie, ''));
    SET v_codigo_cli = TRIM(IFNULL(p_codigo_cliente, ''));
    SET v_marca      = TRIM(IFNULL(p_marca, ''));
    SET v_modelo     = TRIM(IFNULL(p_modelo, ''));
    SET v_ubicacion  = TRIM(IFNULL(p_ubicacion, ''));

    IF v_serie = '' THEN
        SELECT 1 AS IdTipoMensaje, 'Ingresa el N/S del equipo.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_codigo_cli = '' THEN
        SELECT 1 AS IdTipoMensaje, 'Ingresa el código del equipo.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_marca = '' THEN
        SELECT 1 AS IdTipoMensaje, 'Selecciona la marca.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_modelo = '' THEN
        SELECT 1 AS IdTipoMensaje, 'Ingresa el modelo.' AS Mensaje; LEAVE proc;
    END IF;
    IF IFNULL(p_id_suministro, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Selecciona el tipo de equipo.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_ubicacion = '' THEN
        SELECT 1 AS IdTipoMensaje, 'Ingresa la ubicación del equipo.' AS Mensaje; LEAVE proc;
    END IF;
    IF CHAR_LENGTH(IFNULL(p_num_serie, '')) > 80 OR CHAR_LENGTH(IFNULL(p_codigo_cliente, '')) > 80
       OR CHAR_LENGTH(IFNULL(p_modelo, '')) > 80 OR CHAR_LENGTH(IFNULL(p_ubicacion, '')) > 200 THEN
        SELECT 1 AS IdTipoMensaje, 'Algún dato supera el largo permitido (N/S, código y modelo: 80; ubicación: 200).' AS Mensaje; LEAVE proc;
    END IF;
    IF NULLIF(TRIM(IFNULL(p_foto_placa, '')), '') IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Toma la foto de la placa del equipo (solo cámara).' AS Mensaje; LEAVE proc;
    END IF;

    -- La marca debe ser una del catálogo (se guarda con el nombre del catálogo)
    SELECT t.String1 INTO v_marca_cat
    FROM   tabla_maestra t
    WHERE  t.Descripcion = 'MARCA_SUMINISTRO' AND t.IdEmpresa = 1 AND t.eliminado_en IS NULL AND t.String1 = v_marca
    LIMIT 1;
    IF v_marca_cat IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'La marca no está en el catálogo: elige una de la lista.' AS Mensaje; LEAVE proc;
    END IF;
    SET v_marca = v_marca_cat;

    -- El tipo de equipo es un suministro activo de clase equipo / instrumento / pesa
    SELECT su.clase INTO v_clase
    FROM   suministros su
    WHERE  su.id_suministro = p_id_suministro AND su.eliminado_en IS NULL AND su.estado = 'activo' AND su.clase IN ('equipo', 'instrumento', 'pesa');
    IF v_clase IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'El tipo de equipo elegido no existe o no está activo.' AS Mensaje; LEAVE proc;
    END IF;

    START TRANSACTION;

    -- La OS debe ser del técnico del token (se bloquea la fila: dos envíos seguidos no se pisan)
    SELECT os.estado, os.numero, os.id_cliente, os.id_sede INTO v_estado_os, v_numero_os, v_id_cliente, v_id_sede
    FROM   orden_servicio os
    WHERE  os.id_os = p_id_os AND os.eliminado_en IS NULL
      AND  (os.id_tecnico_principal = p_id_usuario
            OR EXISTS (SELECT 1 FROM os_personal op
                       WHERE op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL))
    FOR UPDATE;
    IF v_estado_os IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Servicio no encontrado o no asignado a tu usuario.' AS Mensaje; LEAVE proc;
    END IF;

    -- Hard Stop (HU-06): una sola vez, en SP_EvaluarCampoMovil
    CALL SP_EvaluarCampoMovil(p_id_os, v_estado_os, v_salida_utc, v_llegada_utc, v_habilitado, v_motivo_no);
    IF v_habilitado = 0 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, v_motivo_no AS Mensaje; LEAVE proc;
    END IF;

    SELECT u.correo, u.area, TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))) INTO v_login, v_area, v_nombre_tec
    FROM   usuario u WHERE u.id_usuario = p_id_usuario LIMIT 1;

    -- ¿El equipo ya existe en el maestro del cliente? (misma regla que SP_GuardarEquipoCliente: serie + marca + modelo)
    SELECT ec.id_equipo, ec.codigo_tw INTO v_id_equipo, v_codigo_tw
    FROM   equipo_cliente ec
    WHERE  ec.id_cliente = v_id_cliente AND ec.SoftDelete = 0
      AND  ec.num_serie = v_serie AND ec.marca = v_marca AND ec.modelo = v_modelo
    ORDER BY ec.id_equipo LIMIT 1;

    IF v_id_equipo IS NOT NULL THEN
        SET v_ya_existia = 1;
        SELECT oe.id, oe.ingresado_en_campo, oe.orden, oe.creado_por INTO v_id_oe, v_oe_campo, v_oe_orden, v_oe_usuario
        FROM   os_equipo oe
        WHERE  oe.id_os = p_id_os AND oe.id_equipo = v_id_equipo AND oe.eliminado_en IS NULL
        LIMIT 1;

        IF v_id_oe IS NOT NULL THEN
            IF v_oe_campo = 1 AND v_oe_usuario = p_id_usuario THEN
                -- Reintento de la app: ya lo registró este técnico en esta O/S
                SET v_ya_reg = 1;
            ELSE
                ROLLBACK;
                SELECT 1 AS IdTipoMensaje,
                       CONCAT('Este equipo ya está en la lista de la O/S (', v_codigo_tw, '): búscalo y selecciónalo.') AS Mensaje;
                LEAVE proc;
            END IF;
        END IF;
    END IF;

    IF v_ya_reg = 0 THEN
        -- Mismo tipo de intervención que los demás objetivos de la O/S (la intranet lo puede cambiar); el orden va al final
        SELECT oe.id_tipo_intervencion INTO v_tipo_interv
        FROM   os_equipo oe
        WHERE  oe.id_os = p_id_os AND oe.eliminado_en IS NULL AND oe.id_tipo_intervencion IS NOT NULL
        ORDER BY oe.id LIMIT 1;
        SELECT IFNULL(MAX(IFNULL(oe.orden, oe.id)), 0) + 1 INTO v_orden
        FROM   os_equipo oe WHERE oe.id_os = p_id_os AND oe.eliminado_en IS NULL;

        IF v_id_equipo IS NULL THEN
            -- COD TW provisional (único): la intranet asigna el definitivo al aprobar el registro
            INSERT INTO equipo_cliente (
                codigo_tw, num_serie, id_cliente, id_sede, codigo_cliente, clasificacion, marca, modelo, ubicacion_especifica,
                es_pre_revisado, bloqueado_para_servicios, id_suministro, estado_operativo, es_activo, estado,
                usuario_registro, SoftDelete, UsuCre, FchCre, registrado_en_campo, id_os_registro, foto_placa_url)
            VALUES (
                CONCAT('NEW-', UUID_SHORT()), v_serie, v_id_cliente, v_id_sede, v_codigo_cli, v_clase, v_marca, v_modelo, v_ubicacion,
                0, 0, p_id_suministro, NULL, 1, 'borrador',
                v_login, 0, v_login, NOW(), 1, p_id_os, TRIM(p_foto_placa));
            SET v_id_equipo = LAST_INSERT_ID();
            SET v_codigo_tw = CONCAT('NEW-', LPAD(v_id_equipo, 6, '0'));
            UPDATE equipo_cliente SET codigo_tw = v_codigo_tw WHERE id_equipo = v_id_equipo;
            SET v_foto_ok = 1;
        END IF;

        INSERT INTO os_equipo (id_os, id_equipo, id_tipo_intervencion, orden, ingresado_en_campo, estado_ejecucion, creado_por)
        VALUES (p_id_os, v_id_equipo, v_tipo_interv, v_orden, 1, 'pendiente', p_id_usuario);
        SET v_id_oe = LAST_INSERT_ID();

        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
        VALUES ('os_equipo', v_id_oe, 'registrar_equipo_campo', NULL, 'por iniciar',
                LEFT(CONCAT(IF(v_ya_existia = 1, 'Equipo ya registrado agregado desde campo a ', 'Equipo nuevo registrado desde campo en '), v_numero_os,
                            ': N/S ', v_serie, ' · ', v_marca, ' ', v_modelo, ' · ', v_ubicacion), 900),
                p_id_usuario, NOW(),
                JSON_OBJECT('id_os', p_id_os, 'id_equipo', v_id_equipo, 'codigo_tw', v_codigo_tw, 'ya_existia', v_ya_existia = 1));

        IF v_ya_existia = 0 THEN
            INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
            VALUES ('equipo_cliente', v_id_equipo, 'registrar_equipo_campo', NULL, 'borrador',
                    LEFT(CONCAT('Registrado desde la app móvil en ', v_numero_os, ' por ', v_nombre_tec, ': pendiente de aprobación (COD TW provisional ', v_codigo_tw, ').'), 900),
                    p_id_usuario, NOW(),
                    JSON_OBJECT('id_os', p_id_os, 'num_serie', v_serie, 'marca', v_marca, 'modelo', v_modelo, 'id_suministro', p_id_suministro));

            -- Aviso para aprobar el registro: supervisores/administradores del área del técnico y su jefe; si no hay, administradores
            SET v_texto = LEFT(CONCAT(v_nombre_tec, ' registró un equipo nuevo en la O/S ', v_numero_os, ' (N/S ', v_serie, ' · ', v_marca, ' ', v_modelo,
                                      '). Falta aprobar el registro y asignar su COD TW.'), 500);
            -- Regla Área + Rol (SP_ArmarAprobadoresOsMovil)
            CALL SP_ArmarAprobadoresOsMovil(p_id_os);
            INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
            SELECT a.id_usuario, 5, 'Equipo nuevo por aprobar', v_texto, 'equipo_cliente', v_id_equipo, NOW(), p_id_usuario
            FROM   tmp_aprobadores a
            WHERE  a.id_usuario <> p_id_usuario;
            SET v_notif = ROW_COUNT();
            DROP TEMPORARY TABLE IF EXISTS tmp_aprobadores;
            IF v_notif = 0 THEN
                INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
                SELECT u.id_usuario, 5, 'Equipo nuevo por aprobar', v_texto, 'equipo_cliente', v_id_equipo, NOW(), p_id_usuario
                FROM   usuario u
                WHERE  u.eliminado_en IS NULL AND u.estado = 'activo' AND u.id_usuario <> p_id_usuario
                  AND  u.rol_sistema IN ('administrador', 'admin');
                SET v_notif = ROW_COUNT();
            END IF;
        END IF;
    END IF;

    COMMIT;

    SELECT 2 AS IdTipoMensaje,
           CASE WHEN v_ya_reg = 1 THEN 'Ya registraste este equipo.'
                WHEN v_ya_existia = 1 THEN 'El equipo ya estaba registrado en el sistema: se agregó a esta O/S.'
                ELSE 'Equipo registrado. El COD TW lo asigna la intranet al aprobar el registro.' END AS Mensaje;
    SELECT v_id_oe AS id_os_equipo, v_id_equipo AS id_equipo, v_codigo_tw AS codigo_tw, v_ya_existia AS ya_existia, v_ya_reg AS ya_registrado,
           v_foto_ok AS foto_guardada, v_notif AS notificados;
END$$

DELIMITER ;

-- ============================================================
-- SP_RegistrarDemoraMovil  (App Mobile HU-05 — Registro de demoras en ruta · escritura)
-- El técnico reporta una demora durante el traslado ("llegar a planta") o al ingresar a la planta ("ingreso a planta").
--   - El técnico sale del token; la OS debe ser suya (principal o personal) y estar en el estado que permite ese tipo:
--       llegada : OS EN RUTA y sin llegada registrada. Recalcula la ETA de llegada.
--       ingreso : OS en ruta o en ejecución, con la llegada registrada y sin inicio del trabajo. Recalcula el inicio del trabajo.
--   - Solo se captura el GPS y la hora (en Lima, UTC-5): la pone el servidor, salvo una demora guardada sin conexión (ver más abajo).
--     Foto opcional (la ruta ya guardada en el almacenamiento de archivos; la valida y guarda el back antes de llamar a este SP).
--   - El tipo de demora (motivo) debe existir en MOTIVO_DEMORA_RUTA y corresponder al ámbito (traslado | ingreso | ambos).
--   - Duración de 1 a 480 minutos. Las horas se recalculan con las reglas de SP_ObtenerEtaDemorasMovil.
--   - Antirrebote: la misma demora (mismo tipo, motivo y duración) del mismo técnico en los últimos 20 s no se duplica: se responde
--     con la ya registrada y sin avisar de nuevo.
--   - Sin conexión: la app guarda la demora en el teléfono y la envía al recuperar la señal, con la hora en que se registró
--     (p_capturado_utc, hora UTC del teléfono). Esa hora solo se respeta si no es futura (tolerancia 5 min) ni tiene más de 24 h; si no,
--     vale la hora del servidor. Una demora "diferida" (llegó más de 2 min después) queda con la hora en que ocurrió y, si el envío se
--     repite (la respuesta se perdió), se reconoce como la misma y no se duplica ni se avisa de nuevo.
--   - Avisa a Operaciones (supervisor o administrador del área Operaciones, o Jefe/Coordinador de Operaciones; si no hay, a los
--     administradores) y deja el registro en auditoria_evento. El impacto queda en 'retrasa' (lo lee el Seguimiento Operativo).
-- Resultados: 1 mensaje; 2 la demora (id_demora, tipo, eta_original, eta_anterior, eta_recalculada, notificados, repetida, diferida).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_RegistrarDemoraMovil;

DELIMITER $$

CREATE PROCEDURE SP_RegistrarDemoraMovil(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT,
    IN p_tipo       VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_motivo  INT,
    IN p_duracion   INT,
    IN p_descripcion VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_latitud    DECIMAL(10,7),
    IN p_longitud   DECIMAL(10,7),
    IN p_precision  DECIMAL(8,1),
    IN p_foto       VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_capturado_utc DATETIME
)
proc: BEGIN
    DECLARE v_tipo       VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_numero     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_motivo     VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_ambito     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tecnico    VARCHAR(210) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_texto      VARCHAR(400) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_eta_orig   DATETIME;
    DECLARE v_min_lleg   INT DEFAULT 0;
    DECLARE v_llegada    DATETIME;
    DECLARE v_inicio_vig DATETIME;
    DECLARE v_ahora      DATETIME;
    DECLARE v_capt       DATETIME;
    DECLARE v_registro   DATETIME;
    DECLARE v_diferida   TINYINT DEFAULT 0;
    DECLARE v_eta_ant    DATETIME DEFAULT NULL;
    DECLARE v_eta_nueva  DATETIME DEFAULT NULL;
    DECLARE v_inicio_trab TINYINT DEFAULT 0;
    DECLARE v_id_dem     BIGINT DEFAULT NULL;
    DECLARE v_notif      INT DEFAULT 0;
    DECLARE v_repetida   TINYINT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    -- ── Datos que llegan ─────────────────────────────────────────────────────────────────────────
    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio no encontrado o no asignado a tu usuario.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_tipo = LOWER(TRIM(IFNULL(p_tipo, '')));
    IF v_tipo NOT IN ('llegada', 'ingreso') THEN
        SELECT 1 AS IdTipoMensaje, 'Elige dónde se presenta la demora: llegar a planta o ingreso a planta.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF IFNULL(p_id_motivo, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Selecciona el tipo de demora.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF p_duracion IS NULL OR p_duracion < 1 OR p_duracion > 480 THEN
        SELECT 1 AS IdTipoMensaje, 'La duración estimada debe estar entre 1 y 480 minutos.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF CHAR_LENGTH(IFNULL(p_descripcion, '')) > 500 THEN
        SELECT 1 AS IdTipoMensaje, 'La descripción puede tener hasta 500 caracteres.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF p_latitud IS NULL OR p_longitud IS NULL OR p_latitud NOT BETWEEN -90 AND 90 OR p_longitud NOT BETWEEN -180 AND 180
       OR (p_latitud = 0 AND p_longitud = 0) THEN
        SELECT 1 AS IdTipoMensaje, 'La ubicación GPS no es válida: activa el GPS e inténtalo de nuevo.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF p_precision IS NOT NULL AND (p_precision < 0 OR p_precision > 5000) THEN
        SELECT 1 AS IdTipoMensaje, 'La precisión del GPS no es válida.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_ahora = UTC_TIMESTAMP() - INTERVAL 5 HOUR;

    -- Hora en que el técnico registró la demora (la marca el teléfono, en UTC). Se respeta solo si no es futura ni muy antigua
    SET v_capt = v_ahora;
    IF p_capturado_utc IS NOT NULL THEN
        SET v_capt = p_capturado_utc - INTERVAL 5 HOUR;
        IF v_capt > v_ahora + INTERVAL 5 MINUTE OR v_capt < v_ahora - INTERVAL 24 HOUR THEN
            SET v_capt = v_ahora;
        ELSEIF v_capt > v_ahora THEN
            SET v_capt = v_ahora;
        END IF;
    END IF;
    -- Diferida = llegó más de 2 min después de ocurrir (se guardó sin conexión): vale la hora del teléfono; si no, la del servidor
    SET v_diferida = IF(v_capt < v_ahora - INTERVAL 2 MINUTE, 1, 0);
    SET v_registro = IF(v_diferida = 1, v_capt, v_ahora);

    START TRANSACTION;

    -- La OS debe ser del técnico del token
    SELECT os.estado, os.numero INTO v_estado, v_numero
    FROM   orden_servicio os
    WHERE  os.id_os = p_id_os AND os.eliminado_en IS NULL
      AND  (os.id_tecnico_principal = p_id_usuario
            OR EXISTS (SELECT 1 FROM os_personal op
                       WHERE op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL))
    FOR UPDATE;

    IF v_estado IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Servicio no encontrado o no asignado a tu usuario.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- El motivo debe existir y corresponder al tipo de demora
    SELECT t.String1, IFNULL(NULLIF(t.String3, ''), 'ambos') INTO v_motivo, v_ambito
    FROM   tabla_maestra t
    WHERE  t.IdMaestro = 15 AND t.IdEmpresa = 1 AND t.Num1 = p_id_motivo AND t.eliminado_en IS NULL;

    IF v_motivo IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'El tipo de demora seleccionado no es válido.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_ambito <> 'ambos' AND v_ambito <> IF(v_tipo = 'llegada', 'traslado', 'ingreso') THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje,
               IF(v_tipo = 'llegada', 'Ese tipo de demora es de ingreso a planta: no aplica al traslado.',
                                      'Ese tipo de demora es del traslado: no aplica al ingreso a planta.') AS Mensaje;
        LEAVE proc;
    END IF;

    -- Estado de la OS y de la llegada
    CALL SP_ObtenerEtaDemorasMovil(p_id_os, v_eta_orig, v_min_lleg, v_llegada, v_inicio_vig);

    SELECT IF(COUNT(*) > 0, 1, 0) INTO v_inicio_trab
    FROM   evento_campo e
    JOIN   tabla_maestra m ON m.IdMaestro = 29 AND m.IdEmpresa = 1 AND m.Num1 = e.id_tipo_evento AND m.String2 = 'INICIO_TRABAJO'
    WHERE  e.id_os = p_id_os AND e.eliminado_en IS NULL;

    IF v_tipo = 'llegada' THEN
        IF v_estado IN ('programada', 'reprogramada') THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, 'Las demoras se registran durante el traslado: primero inicia el traslado.' AS Mensaje;
            LEAVE proc;
        END IF;
        IF v_estado <> 'en_ruta' THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, 'Las demoras de llegada solo se registran con el servicio en ruta.' AS Mensaje;
            LEAVE proc;
        END IF;
        IF v_llegada IS NOT NULL THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, 'Ya registraste tu llegada: reporta la demora como ingreso a planta.' AS Mensaje;
            LEAVE proc;
        END IF;
    ELSE
        IF v_estado NOT IN ('en_ruta', 'en_ejecucion') THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, 'Las demoras de ingreso solo se registran al llegar a la planta, antes de iniciar el trabajo.' AS Mensaje;
            LEAVE proc;
        END IF;
        IF v_llegada IS NULL THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, 'Registra primero tu llegada a la planta para reportar una demora de ingreso.' AS Mensaje;
            LEAVE proc;
        END IF;
        IF v_inicio_trab = 1 THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, 'El trabajo ya inició: no se registran demoras de ingreso.' AS Mensaje;
            LEAVE proc;
        END IF;
    END IF;

    -- Antirrebote: la misma demora hace menos de 20 s ya está registrada. Si llegó diferida (sin conexión), también cuenta la que
    -- quedó registrada alrededor de la hora en que ocurrió (el envío se repitió porque la respuesta no llegó al teléfono).
    SELECT d.id_demora, d.eta_anterior, d.eta_recalculada INTO v_id_dem, v_eta_ant, v_eta_nueva
    FROM   demora_registro d
    WHERE  d.id_os = p_id_os AND d.id_usuario = p_id_usuario AND d.tipo = v_tipo AND d.id_motivo = p_id_motivo
      AND  d.duracion_minutos = p_duracion AND d.eliminado_en IS NULL
      AND  (d.fecha_registro >= v_ahora - INTERVAL 20 SECOND
            OR (v_diferida = 1 AND d.fecha_registro BETWEEN v_capt - INTERVAL 2 MINUTE AND v_capt + INTERVAL 2 MINUTE))
    ORDER BY d.id_demora DESC LIMIT 1;

    IF v_id_dem IS NOT NULL THEN
        SET v_repetida = 1;
    ELSE
        -- Horas: llegada → ETA de llegada; ingreso → inicio del trabajo previsto (nunca antes de "ahora")
        IF v_tipo = 'llegada' THEN
            SET v_eta_ant   = IF(v_eta_orig IS NULL, NULL, v_eta_orig + INTERVAL v_min_lleg MINUTE);
            SET v_eta_nueva = IF(v_eta_ant IS NULL, NULL, v_eta_ant + INTERVAL p_duracion MINUTE);
        ELSE
            SET v_eta_ant   = GREATEST(IFNULL(v_inicio_vig, v_registro), v_registro);
            SET v_eta_nueva = v_eta_ant + INTERVAL p_duracion MINUTE;
        END IF;

        INSERT INTO demora_registro
            (id_os, id_usuario, id_motivo, tipo, descripcion, duracion_minutos, impacto, fotografia_url,
             latitud, longitud, precision_metros, eta_anterior, eta_recalculada, fecha_registro, creado_por)
        VALUES
            (p_id_os, p_id_usuario, p_id_motivo, v_tipo, NULLIF(TRIM(IFNULL(p_descripcion, '')), ''), p_duracion, 'retrasa',
             NULLIF(TRIM(IFNULL(p_foto, '')), ''), p_latitud, p_longitud, p_precision, v_eta_ant, v_eta_nueva, v_registro, p_id_usuario);
        SET v_id_dem = LAST_INSERT_ID();

        -- Aviso a Operaciones
        SELECT TRIM(CONCAT(IFNULL(nombre, ''), ' ', IFNULL(apellido, ''))) INTO v_tecnico FROM usuario WHERE id_usuario = p_id_usuario;
        SET v_texto = LEFT(CONCAT(v_numero, ' · ', IF(v_tipo = 'llegada', 'Llegar a planta', 'Ingreso a planta'), ' +', p_duracion, ' min · ',
                                  v_motivo, ' · ', IFNULL(v_tecnico, ''),
                                  IF(v_diferida = 1, CONCAT(' · sin conexión, reportada ', TIME_FORMAT(v_registro, '%H:%i')), '')), 400);

        -- Regla Área + Rol (SP_ArmarAprobadoresOsMovil): Operaciones y las demás áreas (cualquier rol), Administradores y el Supervisor del área de la OS
        CALL SP_ArmarAprobadoresOsMovil(p_id_os);
        INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
        SELECT a.id_usuario, 5, 'Demora en ruta', v_texto, 'orden_servicio', p_id_os, NOW(), p_id_usuario
        FROM   tmp_aprobadores a
        WHERE  a.id_usuario <> p_id_usuario;
        SET v_notif = ROW_COUNT();
        DROP TEMPORARY TABLE IF EXISTS tmp_aprobadores;

        -- Respaldo: si no hay nadie en Operaciones, los administradores
        IF v_notif = 0 THEN
            INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
            SELECT u.id_usuario, 5, 'Demora en ruta', v_texto, 'orden_servicio', p_id_os, NOW(), p_id_usuario
            FROM   usuario u
            WHERE  u.eliminado_en IS NULL AND u.estado = 'activo' AND u.id_usuario <> p_id_usuario
              AND  u.rol_sistema IN ('administrador', 'admin');
            SET v_notif = ROW_COUNT();
        END IF;

        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
        VALUES ('orden_servicio', p_id_os, 'registrar_demora', v_estado, v_estado,
                LEFT(CONCAT('Demora ', IF(v_tipo = 'llegada', 'al llegar a planta', 'en el ingreso a planta'), ': ', v_motivo, ', ', p_duracion, ' min.'), 900),
                p_id_usuario, NOW(),
                JSON_OBJECT('id_demora', v_id_dem, 'tipo', v_tipo, 'minutos', p_duracion, 'notificados', v_notif, 'diferida', v_diferida = 1));
    END IF;

    COMMIT;

    SELECT 2 AS IdTipoMensaje,
           CONCAT('Demora registrada. ',
                  IF(v_tipo = 'llegada', 'ETA recalculada: ', 'Inicio de trabajo recalculado: '),
                  IFNULL(TIME_FORMAT(v_eta_nueva, '%H:%i'), '—'), '. ',
                  IF(v_repetida = 1, 'Ya estaba registrada.',
                     IF(v_notif > 0, 'Se avisó a Operaciones.', 'No hay un responsable de Operaciones activo para avisar: informa a tu jefe.'))) AS Mensaje;

    SELECT v_id_dem AS id_demora, v_tipo AS tipo, v_eta_orig AS eta_original, v_eta_ant AS eta_anterior, v_eta_nueva AS eta_recalculada, v_notif AS notificados,
           v_repetida AS repetida, v_diferida AS diferida;
END$$

DELIMITER ;

-- ============================================================
-- SP_RegistrarIncidenciaCampoMovil  (App Mobile HU-32 — "Registrar incidencia" y "Escalar" · escritura)
-- El jefe registra una incidencia de un servicio de su área (imprevisto en ruta o en planta): tipo, severidad, impacto, descripción y foto (solo cámara).
--   - Se guarda en incidencia_operativa, la misma tabla que lee la bandeja de Seguimiento Operativo: una incidencia con impacto "detiene" o de nivel crítico
--     deja el servicio "con incidente" y genera la alerta crítica. Queda a nombre del técnico de la OS (id_usuario) y del jefe (creado_por).
--   - Tipo: catálogo TIPO_INCIDENCIA_OPERATIVA (1 a 6). Severidad: NIVEL_ALERTA (1 Bajo · 2 Medio · 3 Alto · 4 Crítico). Impacto: retrasa | detiene.
--   - p_escalar = 1: la incidencia queda "escalada" (escalada_en) y se avisa a los administradores y al Jefe de Operaciones.
--   - La OS debe estar en el alcance del jefe (SP_ResolverJefaturaMovil + SP_ArmarAlcanceJefaturaMovil). p_evidencia = ruta de la foto ya guardada por el back.
-- Resultados: 1 mensaje; 2 (id_incidencia, estado, notificados).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_RegistrarIncidenciaCampoMovil;

DELIMITER $$

CREATE PROCEDURE SP_RegistrarIncidenciaCampoMovil(
    IN p_id_usuario  BIGINT,
    IN p_id_os       BIGINT,
    IN p_id_tipo     INT,
    IN p_id_nivel    INT,
    IN p_impacto     VARCHAR(10)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_descripcion VARCHAR(1100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_evidencia   VARCHAR(500)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_escalar     TINYINT
)
proc: BEGIN
    DECLARE v_area      VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_sede      VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_aut_area  VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_aut_gen   TINYINT;
    DECLARE v_impacto   VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_desc      VARCHAR(1100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_existe    INT DEFAULT 0;
    DECLARE v_num_os    VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tec       BIGINT DEFAULT NULL;
    DECLARE v_tipo_txt  VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_nivel_txt VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_estado    VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id        BIGINT;
    DECLARE v_nom_jefe  VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_texto     VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_notif     INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_jf_alc;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SET v_impacto = LOWER(TRIM(IFNULL(p_impacto, '')));
    SET v_desc    = NULLIF(TRIM(IFNULL(p_descripcion, '')), '');
    IF IFNULL(p_id_os, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El servicio indicado no es válido.' AS Mensaje; LEAVE proc;
    END IF;
    SELECT t.String1 INTO v_tipo_txt FROM tabla_maestra t
    WHERE  t.Descripcion = 'TIPO_INCIDENCIA_OPERATIVA' AND t.IdEmpresa = 1 AND t.Num1 = p_id_tipo AND t.eliminado_en IS NULL LIMIT 1;
    IF v_tipo_txt IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Selecciona el tipo de incidencia.' AS Mensaje; LEAVE proc;
    END IF;
    SELECT t.String1 INTO v_nivel_txt FROM tabla_maestra t
    WHERE  t.Descripcion = 'NIVEL_ALERTA' AND t.IdEmpresa = 1 AND t.Num1 = p_id_nivel AND t.eliminado_en IS NULL LIMIT 1;
    IF v_nivel_txt IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Selecciona la severidad.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_impacto NOT IN ('retrasa', 'detiene') THEN
        SELECT 1 AS IdTipoMensaje, 'Selecciona el impacto en el servicio.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_desc IS NULL OR CHAR_LENGTH(v_desc) < 3 THEN
        SELECT 1 AS IdTipoMensaje, 'Escribe la descripción de la incidencia (mínimo 3 caracteres).' AS Mensaje; LEAVE proc;
    END IF;
    IF CHAR_LENGTH(v_desc) > 1000 THEN
        SELECT 1 AS IdTipoMensaje, 'La descripción puede tener hasta 1000 caracteres.' AS Mensaje; LEAVE proc;
    END IF;

    CALL SP_ResolverJefaturaMovil(p_id_usuario, v_area, v_sede, v_aut_area, v_aut_gen);
    IF v_area IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Tu cargo no tiene el menú de Jefatura.' AS Mensaje; LEAVE proc;
    END IF;
    CALL SP_ArmarAlcanceJefaturaMovil(v_area, p_id_os);
    SELECT COUNT(*) INTO v_existe FROM tmp_jf_alc WHERE id_os = p_id_os;
    DROP TEMPORARY TABLE IF EXISTS tmp_jf_alc;
    IF v_existe = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El servicio no existe o no pertenece a tu área.' AS Mensaje; LEAVE proc;
    END IF;

    SELECT os.numero, os.id_tecnico_principal INTO v_num_os, v_tec FROM orden_servicio os WHERE os.id_os = p_id_os AND os.eliminado_en IS NULL;
    SET v_estado = IF(IFNULL(p_escalar, 0) = 1, 'escalada', 'abierta');

    START TRANSACTION;

    INSERT INTO incidencia_operativa (id_os, id_usuario, id_tipo, descripcion, id_nivel_alerta, estado, impacto, fecha_registro, creado_por, evidencia_url, escalada_en)
    VALUES (p_id_os, IFNULL(v_tec, p_id_usuario), p_id_tipo, v_desc, p_id_nivel, v_estado, v_impacto, NOW(), p_id_usuario,
            NULLIF(TRIM(IFNULL(p_evidencia, '')), ''), IF(v_estado = 'escalada', NOW(), NULL));
    SET v_id = LAST_INSERT_ID();

    SELECT TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))) INTO v_nom_jefe FROM usuario u WHERE u.id_usuario = p_id_usuario;

    IF v_estado = 'escalada' THEN
        SET v_texto = LEFT(CONCAT(v_nom_jefe, ' escaló una incidencia en ', v_num_os, ': ', v_tipo_txt, ' · severidad ', v_nivel_txt, ' · ',
                                  IF(v_impacto = 'detiene', 'detiene el servicio', 'retrasa el servicio'), '. ', v_desc), 500);
        -- Regla Área + Rol (SP_ArmarAprobadoresOsMovil)
        CALL SP_ArmarAprobadoresOsMovil(p_id_os);
        INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
        SELECT a.id_usuario, 5, CONCAT('Incidencia escalada: ', LEFT(v_tipo_txt, 60)), v_texto, 'orden_servicio', p_id_os, NOW(), p_id_usuario
        FROM   tmp_aprobadores a
        WHERE  a.id_usuario <> p_id_usuario;
        SET v_notif = ROW_COUNT();
        DROP TEMPORARY TABLE IF EXISTS tmp_aprobadores;
    END IF;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('orden_servicio', p_id_os, IF(v_estado = 'escalada', 'incidencia_escalada', 'incidencia_registrada'), NULL, v_estado,
            LEFT(CONCAT(v_nom_jefe, ' registró una incidencia en ', v_num_os, ': ', v_tipo_txt, ' · ', v_nivel_txt, ' · ', v_impacto, ' · ', v_desc), 900),
            p_id_usuario, NOW(), JSON_OBJECT('id_incidencia', v_id, 'id_tipo', p_id_tipo, 'id_nivel', p_id_nivel, 'impacto', v_impacto));

    COMMIT;

    SELECT 2 AS IdTipoMensaje, IF(v_estado = 'escalada', 'Incidencia registrada y escalada.', 'Incidencia registrada.') AS Mensaje;
    SELECT v_id AS id_incidencia, v_estado AS estado, v_notif AS notificados;
END$$

DELIMITER ;

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

-- ============================================================
-- VERIFICACIÓN (SP temporal): qué aprobaciones / alertas ve y recibe cada usuario activo. Se borra al terminar.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_TmpVerificarAprobadores;

DELIMITER $$

CREATE PROCEDURE SP_TmpVerificarAprobadores()
BEGIN
    DECLARE v_id BIGINT;
    DECLARE v_fin INT DEFAULT 0;
    DECLARE v_area VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_gen TINYINT DEFAULT 0;
    DECLARE cur CURSOR FOR SELECT id_usuario FROM usuario WHERE eliminado_en IS NULL AND estado = 'activo' ORDER BY id_usuario;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_fin = 1;

    DROP TEMPORARY TABLE IF EXISTS tmp_verif_apr;
    CREATE TEMPORARY TABLE tmp_verif_apr (id_usuario BIGINT, ve VARCHAR(60));

    OPEN cur;
    leer: LOOP
        FETCH cur INTO v_id;
        IF v_fin = 1 THEN LEAVE leer; END IF;
        CALL SP_ResolverAprobadorMovil(v_id, v_area, v_gen);
        INSERT INTO tmp_verif_apr VALUES (v_id, IF(v_gen = 1, 'TODAS las áreas', IF(v_area IS NOT NULL, CONCAT('solo ', v_area), 'NADA (menú de campo)')));
    END LOOP;
    CLOSE cur;

    SELECT u.id_usuario, u.nombre_usuario AS usuario, u.area, u.rol_sistema AS rol, u.cargo, t.ve AS aprobaciones_alertas_y_avisos
    FROM   tmp_verif_apr t JOIN usuario u ON u.id_usuario = t.id_usuario
    ORDER BY u.area, u.rol_sistema, u.id_usuario;

    DROP TEMPORARY TABLE IF EXISTS tmp_verif_apr;
END$$

DELIMITER ;

CALL SP_TmpVerificarAprobadores();
DROP PROCEDURE IF EXISTS SP_TmpVerificarAprobadores;
