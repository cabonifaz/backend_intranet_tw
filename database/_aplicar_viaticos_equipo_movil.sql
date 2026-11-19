-- HU-35 Viáticos y gastos del equipo (Jefe de Área, app móvil). Ejecutar con Alt+X (No al aviso) y reiniciar la API.
-- Requiere antes: _aplicar_aprobaciones_area_rol_movil.sql (SP_ResolverAprobadorMovil y SP_ArmarAprobadoresOsMovil) y la migración 114 (gastos con reparto y fotos). No crea tablas ni datos.
-- Incluye la EXCEPCIÓN pedida por el usuario: el jefe puede marcar «Ya depositado» desde la app (ver SP_GuardarViaticosProgramacion y SP_AsignarViaticoEquipoMovil).

-- ============================================================
-- SP_ArmarAlcanceViaticosMovil  (App Mobile HU-35 — apoyo, NO es un endpoint)
-- Arma, UNA sola vez, los servicios (OS) cuyos viáticos y gastos puede ver y operar el jefe, en la tabla temporal `tmp_vi_alc` (id_os). Quien la llame debe terminar con
-- DROP TEMPORARY TABLE IF EXISTS tmp_vi_alc. Solo lectura.
--   Regla Área + Rol (la misma de SP_ResolverAprobadorMovil y de las aprobaciones de la HU-31):
--     · Gerencia, Operaciones, Administración, TI, SSOMA, Calidad, Comercial (cualquier rol) y Administradores → TODOS los servicios.
--     · Supervisor de Servicio Técnico / Metrología → solo los servicios cuya RQ es de su área (area_servicio_rq.area_usuario); un servicio cuya RQ no indica área lo ven
--       todos los jefes (igual que en Aprobaciones).
--     · Usuario / Visor de Servicio Técnico o Metrología (o sin área) → p_sin_jefatura = 1 y ningún servicio.
--   Solo entran servicios con una programación no cancelada (los viáticos cuelgan de la programación).
--   p_id_os NULL → todos los del alcance;  p_id_os dado → solo ese (si está en el alcance), de cualquier fecha.
-- Lo usan: la lista y el detalle de "Viáticos y gastos del equipo", la asignación de viáticos, la revisión de un gasto (SP_RevisarGastoMovil) y el contador del menú de Jefatura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ArmarAlcanceViaticosMovil;

DELIMITER $$

CREATE PROCEDURE SP_ArmarAlcanceViaticosMovil(
    IN  p_id_usuario   BIGINT,
    IN  p_id_os        BIGINT,
    OUT p_sin_jefatura TINYINT
)
BEGIN
    DECLARE v_area_jefe VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_general   TINYINT DEFAULT 0;

    SET p_sin_jefatura = 0;

    DROP TEMPORARY TABLE IF EXISTS tmp_vi_alc;
    CREATE TEMPORARY TABLE tmp_vi_alc (id_os BIGINT NOT NULL, PRIMARY KEY (id_os));

    CALL SP_ResolverAprobadorMovil(p_id_usuario, v_area_jefe, v_general);

    IF IFNULL(v_general, 0) = 0 AND v_area_jefe IS NULL THEN
        SET p_sin_jefatura = 1;
    ELSE
        INSERT INTO tmp_vi_alc (id_os)
        SELECT os.id_os
        FROM   orden_servicio os
        WHERE  os.eliminado_en IS NULL
          AND  (p_id_os IS NULL OR os.id_os = p_id_os)
          AND  EXISTS (SELECT 1 FROM programacion pr
                       WHERE pr.id_os = os.id_os AND pr.estado <> 'cancelada' AND pr.eliminado_en IS NULL)
          AND  (v_general = 1
                OR NOT EXISTS (SELECT 1
                               FROM   expediente_digital ed
                               JOIN   requerimiento      rq  ON rq.id_requerimiento = ed.id_requerimiento
                               JOIN   area_servicio_rq   asr ON asr.id_area_rq      = rq.id_area
                               WHERE  ed.id_expediente = os.id_expediente AND asr.area_usuario IS NOT NULL)
                OR EXISTS (SELECT 1
                           FROM   expediente_digital ed
                           JOIN   requerimiento      rq  ON rq.id_requerimiento = ed.id_requerimiento
                           JOIN   area_servicio_rq   asr ON asr.id_area_rq      = rq.id_area
                           WHERE  ed.id_expediente = os.id_expediente AND asr.area_usuario = v_area_jefe));
    END IF;
END$$

DELIMITER ;

-- ============================================================
-- SP_ObtenerViaticosEquipoMovil  (App Mobile HU-35 — "Viáticos y gastos del equipo" del Jefe de Área · lectura)
-- Resumen por servicio de lo que el jefe asignó a sus técnicos (viáticos) y de lo que ellos rindieron (gastos), con el alcance de la app (SP_ArmarAlcanceViaticosMovil:
-- Gerencia, Operaciones, Administración, TI, SSOMA, Calidad, Comercial y Administradores ven todo; el Supervisor de Servicio Técnico / Metrología, solo su área).
-- Acceso: prog_bandeja (ver). Asignar y revisar gastos exige prog_aprobar_reprogramacion: puede_asignar lo dice por servicio.
-- Mismas definiciones que HU-45 (SP_ArmarViaticosOs) y HU-25 (SP_ObtenerViaticosUsuarioMovil), por programación:
--   asignado   = viáticos asignados (gasto_viatico.tipo = 'viatico_asignado') · depositado = los de estado 'aprobado' o 'rendido' (Contabilidad o el jefe desde la app)
--   rendido    = gastos rendidos (tipo = 'gasto_solicitado') que no fueron rechazados
--   por_revisar = gastos en estado 'pendiente' (los que esperan la decisión del jefe; los 'observado' esperan al técnico). Es el mismo cálculo del contador del menú.
-- Ventana: servicios del alcance con programación NO cancelada y (rendición abierta o servicio de los últimos 7 días), los más recientes primero (máx. 50).
-- Estado del servicio: cerrado (rendición cerrada) · por_revisar (hay gastos pendientes) · por_depositar (hay viáticos pendientes de depósito) · al_dia.
-- avance = rendido / asignado en % (0 si no hay asignado; tope 100).
-- Resultados: 1 mensaje · 2 KPIs (sobre los servicios listados) · 3 servicios.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerViaticosEquipoMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerViaticosEquipoMovil(
    IN p_id_usuario BIGINT
)
proc: BEGIN
    DECLARE v_sin   TINYINT DEFAULT 0;
    DECLARE v_hoy   DATE;
    DECLARE v_puede TINYINT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_vi_alc;
        DROP TEMPORARY TABLE IF EXISTS tmp_vi_srv;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF FN_PermisoAccion(p_id_usuario, 'prog_bandeja') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver los viáticos del equipo.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_hoy   = DATE(UTC_TIMESTAMP() - INTERVAL 5 HOUR);
    SET v_puede = FN_PermisoAccion(p_id_usuario, 'prog_aprobar_reprogramacion');

    CALL SP_ArmarAlcanceViaticosMovil(p_id_usuario, NULL, v_sin);
    IF v_sin = 1 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_vi_alc;
        SELECT 1 AS IdTipoMensaje, 'Tu cargo no tiene el menú de Jefatura.' AS Mensaje;
        LEAVE proc;
    END IF;

    DROP TEMPORARY TABLE IF EXISTS tmp_vi_srv;
    CREATE TEMPORARY TABLE tmp_vi_srv (
        id_os           BIGINT        NOT NULL,
        id_programacion BIGINT        NOT NULL,
        numero_os       VARCHAR(20)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        cliente         VARCHAR(300)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        estado_os       VARCHAR(25)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        estado_prog     VARCHAR(25)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        cerrada         TINYINT       NOT NULL DEFAULT 0,
        fecha_ejecucion DATE          NULL,
        asignado        DECIMAL(12,2) NOT NULL DEFAULT 0,
        depositado      DECIMAL(12,2) NOT NULL DEFAULT 0,
        rendido         DECIMAL(12,2) NOT NULL DEFAULT 0,
        por_revisar     DECIMAL(12,2) NOT NULL DEFAULT 0,
        n_por_revisar   INT           NOT NULL DEFAULT 0,
        tecnicos        VARCHAR(600)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        n_tecnicos      INT           NOT NULL DEFAULT 0,
        PRIMARY KEY (id_os)
    );

    -- La programación vigente de cada servicio (la última no cancelada) y la ventana de la lista
    INSERT INTO tmp_vi_srv (id_os, id_programacion, numero_os, cliente, estado_os, estado_prog, cerrada, fecha_ejecucion)
    SELECT os.id_os, pr.id_programacion, os.numero, COALESCE(NULLIF(cl.nombre_comercial, ''), cl.razon_social), os.estado, pr.estado,
           IF(EXISTS (SELECT 1 FROM programacion_rendicion pre WHERE pre.id_programacion = pr.id_programacion AND pre.eliminado_en IS NULL), 1, 0),
           os.fecha_ejecucion
    FROM   tmp_vi_alc a
    JOIN   orden_servicio os ON os.id_os = a.id_os
    JOIN   programacion pr   ON pr.id_programacion = (SELECT MAX(p2.id_programacion) FROM programacion p2
                                                      WHERE p2.id_os = os.id_os AND p2.estado <> 'cancelada' AND p2.eliminado_en IS NULL)
    LEFT JOIN cliente cl     ON cl.id_cliente = os.id_cliente
    WHERE  NOT EXISTS (SELECT 1 FROM programacion_rendicion pre WHERE pre.id_programacion = pr.id_programacion AND pre.eliminado_en IS NULL)
        OR os.fecha_ejecucion >= v_hoy - INTERVAL 7 DAY
    ORDER BY os.fecha_ejecucion DESC, os.id_os DESC
    LIMIT 50;

    DROP TEMPORARY TABLE IF EXISTS tmp_vi_alc;

    -- Montos por programación (mismas definiciones que SP_ArmarViaticosOs)
    UPDATE tmp_vi_srv s
    SET s.asignado   = IFNULL((SELECT SUM(g.monto) FROM gasto_viatico g
                               WHERE g.tipo = 'viatico_asignado' AND g.eliminado_en IS NULL
                                 AND (g.id_programacion = s.id_programacion OR (g.id_programacion IS NULL AND g.id_os = s.id_os))), 0),
        s.depositado = IFNULL((SELECT SUM(g.monto) FROM gasto_viatico g
                               WHERE g.tipo = 'viatico_asignado' AND g.eliminado_en IS NULL AND g.estado IN ('aprobado', 'rendido')
                                 AND (g.id_programacion = s.id_programacion OR (g.id_programacion IS NULL AND g.id_os = s.id_os))), 0),
        s.rendido    = IFNULL((SELECT SUM(g.monto) FROM gasto_viatico g
                               WHERE g.tipo = 'gasto_solicitado' AND g.eliminado_en IS NULL AND g.estado <> 'rechazado'
                                 AND (g.id_programacion = s.id_programacion OR (g.id_programacion IS NULL AND g.id_os = s.id_os))), 0),
        s.por_revisar = IFNULL((SELECT SUM(g.monto) FROM gasto_viatico g
                                WHERE g.tipo = 'gasto_solicitado' AND g.eliminado_en IS NULL AND g.estado = 'pendiente'
                                  AND (g.id_programacion = s.id_programacion OR (g.id_programacion IS NULL AND g.id_os = s.id_os))), 0),
        s.n_por_revisar = (SELECT COUNT(*) FROM gasto_viatico g
                           WHERE g.tipo = 'gasto_solicitado' AND g.eliminado_en IS NULL AND g.estado = 'pendiente'
                             AND (g.id_programacion = s.id_programacion OR (g.id_programacion IS NULL AND g.id_os = s.id_os))),
        s.tecnicos   = (SELECT GROUP_CONCAT(TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, '')))
                                            ORDER BY IF(pt.rol = 'principal', 0, 1), u.nombre SEPARATOR ', ')
                        FROM programacion_tecnico pt JOIN usuario u ON u.id_usuario = pt.id_usuario
                        WHERE pt.id_programacion = s.id_programacion AND pt.eliminado_en IS NULL),
        s.n_tecnicos = (SELECT COUNT(*) FROM programacion_tecnico pt
                        WHERE pt.id_programacion = s.id_programacion AND pt.eliminado_en IS NULL);

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2 KPIs (sobre los servicios de la lista)
    SELECT IFNULL(SUM(s.asignado), 0)    AS asignado,
           IFNULL(SUM(s.rendido), 0)     AS rendido,
           IFNULL(SUM(s.por_revisar), 0) AS por_revisar,
           DATE_FORMAT(UTC_TIMESTAMP() - INTERVAL 5 HOUR, '%H:%i') AS actualizado,
           30 AS refresco_segundos
    FROM   tmp_vi_srv s;

    -- 3 Servicios
    SELECT s.id_os, s.numero_os, s.cliente, s.id_programacion,
           IFNULL(s.tecnicos, '') AS tecnicos, s.n_tecnicos,
           s.asignado, s.depositado, s.rendido, s.por_revisar, s.n_por_revisar AS gastos_por_revisar,
           IF(s.asignado <= 0, 0, LEAST(100, ROUND(s.rendido * 100 / s.asignado))) AS avance,
           CASE WHEN s.cerrada = 1                  THEN 'cerrado'
                WHEN s.n_por_revisar > 0            THEN 'por_revisar'
                WHEN s.asignado - s.depositado > 0  THEN 'por_depositar'
                ELSE 'al_dia' END AS estado,
           IF(v_puede = 1 AND s.estado_prog = 'confirmada' AND s.cerrada = 0
              AND IFNULL(s.estado_os, '') NOT IN ('en_ruta', 'en_ejecucion', 'pausada', 'finalizada'), 1, 0) AS puede_asignar
    FROM   tmp_vi_srv s
    ORDER BY s.fecha_ejecucion DESC, s.id_os DESC;

    DROP TEMPORARY TABLE IF EXISTS tmp_vi_srv;
END$$

DELIMITER ;

-- ============================================================
-- SP_ObtenerViaticoServicioEquipoMovil  (App Mobile HU-35 — detalle de los viáticos y gastos de UN servicio del equipo · lectura)
-- Por técnico: lo asignado por concepto (con su estado de depósito), lo rendido y lo que espera su decisión; y los gastos rendidos con su estado y la lectura de la IA del comprobante.
-- Acceso: prog_bandeja y el servicio dentro del alcance de la app (SP_ArmarAlcanceViaticosMovil). Un servicio fuera del alcance se responde como si no existiera.
-- Mismas definiciones que HU-45 (SP_ArmarViaticosOs). por_revisar = gastos en estado 'pendiente' (los que espera el jefe).
-- puede_asignar / motivo_no_asignar: las mismas condiciones con las que SP_GuardarViaticosProgramacion acepta o rechaza (prog_aprobar_reprogramacion, programación confirmada,
--   rendición abierta y servicio sin salir a campo); allí se vuelven a validar al guardar. version = huella de la asignación (SP_VersionViaticosProgramacion) que debe enviarse al asignar.
-- clave del concepto: movilidad | alimentacion | alojamiento (los conceptos fijos del catálogo CONCEPTO_GASTO) u otros (cualquier otro concepto).
-- Resultados: 1 mensaje · 2 cabecera · 3 técnicos · 4 líneas asignadas · 5 gastos rendidos.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerViaticoServicioEquipoMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerViaticoServicioEquipoMovil(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT
)
proc: BEGIN
    DECLARE v_sin       TINYINT DEFAULT 0;
    DECLARE v_prog      BIGINT DEFAULT NULL;
    DECLARE v_numero    VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cliente   VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado_os VARCHAR(25)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado_pr VARCHAR(25)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cerrada   TINYINT DEFAULT 0;
    DECLARE v_jefe      TINYINT DEFAULT 0;
    DECLARE v_puede     TINYINT DEFAULT 0;
    DECLARE v_motivo    VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_version   VARCHAR(80);
    DECLARE v_asignado  DECIMAL(12,2) DEFAULT 0;
    DECLARE v_deposit   DECIMAL(12,2) DEFAULT 0;
    DECLARE v_rendido   DECIMAL(12,2) DEFAULT 0;
    DECLARE v_revisar   DECIMAL(12,2) DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_vi_alc;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF FN_PermisoAccion(p_id_usuario, 'prog_bandeja') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver los viáticos del equipo.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF IFNULL(p_id_os, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El servicio indicado no es válido.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_ArmarAlcanceViaticosMovil(p_id_usuario, p_id_os, v_sin);
    IF v_sin = 1 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_vi_alc;
        SELECT 1 AS IdTipoMensaje, 'Tu cargo no tiene el menú de Jefatura.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM tmp_vi_alc WHERE id_os = p_id_os) THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_vi_alc;
        SELECT 1 AS IdTipoMensaje, 'El servicio no existe, no tiene programación o no pertenece a tu alcance.' AS Mensaje;
        LEAVE proc;
    END IF;
    DROP TEMPORARY TABLE IF EXISTS tmp_vi_alc;

    SELECT MAX(p2.id_programacion) INTO v_prog
    FROM programacion p2 WHERE p2.id_os = p_id_os AND p2.estado <> 'cancelada' AND p2.eliminado_en IS NULL;

    SELECT os.numero, COALESCE(NULLIF(cl.nombre_comercial, ''), cl.razon_social), os.estado
      INTO v_numero, v_cliente, v_estado_os
    FROM orden_servicio os LEFT JOIN cliente cl ON cl.id_cliente = os.id_cliente
    WHERE os.id_os = p_id_os;
    SELECT pr.estado INTO v_estado_pr FROM programacion pr WHERE pr.id_programacion = v_prog;
    SET v_cerrada = IF(EXISTS (SELECT 1 FROM programacion_rendicion WHERE id_programacion = v_prog AND eliminado_en IS NULL), 1, 0);
    SET v_jefe    = FN_PermisoAccion(p_id_usuario, 'prog_aprobar_reprogramacion');

    IF v_jefe = 0 THEN
        SET v_motivo = 'Solo el Jefe de Operaciones puede asignar viáticos y revisar gastos.';
    ELSEIF IFNULL(v_estado_os, '') IN ('en_ruta', 'en_ejecucion', 'pausada', 'finalizada') THEN
        SET v_motivo = 'La asignación ya no se puede editar: el servicio salió a campo.';
    ELSEIF IFNULL(v_estado_pr, '') <> 'confirmada' THEN
        SET v_motivo = 'La programación aún no está confirmada por el cliente: los viáticos se asignan cuando está Programado.';
    ELSEIF v_cerrada = 1 THEN
        SET v_motivo = 'La rendición ya fue cerrada: los viáticos quedan solo de lectura.';
    END IF;
    SET v_puede = IF(v_motivo IS NULL, 1, 0);

    CALL SP_VersionViaticosProgramacion(v_prog, p_id_os, 1, v_version);

    SELECT IFNULL(SUM(g.monto), 0), IFNULL(SUM(IF(g.estado IN ('aprobado', 'rendido'), g.monto, 0)), 0)
      INTO v_asignado, v_deposit
    FROM gasto_viatico g
    WHERE g.tipo = 'viatico_asignado' AND g.eliminado_en IS NULL AND (g.id_programacion = v_prog OR (g.id_programacion IS NULL AND g.id_os = p_id_os));
    SELECT IFNULL(SUM(IF(g.estado <> 'rechazado', g.monto, 0)), 0), IFNULL(SUM(IF(g.estado = 'pendiente', g.monto, 0)), 0)
      INTO v_rendido, v_revisar
    FROM gasto_viatico g
    WHERE g.tipo = 'gasto_solicitado' AND g.eliminado_en IS NULL AND (g.id_programacion = v_prog OR (g.id_programacion IS NULL AND g.id_os = p_id_os));

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2 Cabecera
    SELECT p_id_os AS id_os, v_numero AS numero_os, v_cliente AS cliente, v_prog AS id_programacion, v_cerrada AS cerrada,
           v_puede AS puede_asignar, v_motivo AS motivo_no_asignar, v_version AS version,
           v_asignado AS asignado, v_deposit AS depositado, v_rendido AS rendido, v_revisar AS por_revisar;

    -- 3 Técnicos del servicio (el principal primero) con sus montos
    SELECT pt.id_usuario AS id_tecnico, TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))) AS nombre,
           IF(pt.rol = 'principal', 1, 0) AS principal,
           IFNULL((SELECT SUM(g.monto) FROM gasto_viatico g
                   WHERE g.tipo = 'viatico_asignado' AND g.eliminado_en IS NULL AND g.id_usuario = pt.id_usuario
                     AND (g.id_programacion = v_prog OR (g.id_programacion IS NULL AND g.id_os = p_id_os))), 0) AS asignado,
           IFNULL((SELECT SUM(g.monto) FROM gasto_viatico g
                   WHERE g.tipo = 'viatico_asignado' AND g.eliminado_en IS NULL AND g.id_usuario = pt.id_usuario AND g.estado IN ('aprobado', 'rendido')
                     AND (g.id_programacion = v_prog OR (g.id_programacion IS NULL AND g.id_os = p_id_os))), 0) AS depositado,
           IFNULL((SELECT SUM(g.monto) FROM gasto_viatico g
                   WHERE g.tipo = 'gasto_solicitado' AND g.eliminado_en IS NULL AND g.id_usuario = pt.id_usuario AND g.estado <> 'rechazado'
                     AND (g.id_programacion = v_prog OR (g.id_programacion IS NULL AND g.id_os = p_id_os))), 0) AS rendido,
           IFNULL((SELECT SUM(g.monto) FROM gasto_viatico g
                   WHERE g.tipo = 'gasto_solicitado' AND g.eliminado_en IS NULL AND g.id_usuario = pt.id_usuario AND g.estado = 'pendiente'
                     AND (g.id_programacion = v_prog OR (g.id_programacion IS NULL AND g.id_os = p_id_os))), 0) AS por_revisar
    FROM   programacion_tecnico pt
    JOIN   usuario u ON u.id_usuario = pt.id_usuario
    WHERE  pt.id_programacion = v_prog AND pt.eliminado_en IS NULL
    ORDER BY IF(pt.rol = 'principal', 0, 1), u.nombre, pt.id_usuario;

    -- 4 Líneas asignadas por técnico y concepto
    SELECT g.id_gasto, g.id_usuario AS id_tecnico, IFNULL(cg.String1, 'Concepto') AS concepto,
           CASE UPPER(IFNULL(cg.String3, '')) WHEN 'MOVILIDAD' THEN 'movilidad' WHEN 'ALIMENTACION' THEN 'alimentacion'
                                              WHEN 'ALOJAMIENTO' THEN 'alojamiento' ELSE 'otros' END AS clave,
           g.monto, IF(g.estado IN ('aprobado', 'rendido'), 1, 0) AS depositado
    FROM   gasto_viatico g
    LEFT JOIN tabla_maestra cg ON cg.IdMaestro = 25 AND cg.IdEmpresa = 1 AND cg.Num1 = g.id_concepto
    WHERE  g.tipo = 'viatico_asignado' AND g.eliminado_en IS NULL AND (g.id_programacion = v_prog OR (g.id_programacion IS NULL AND g.id_os = p_id_os))
    ORDER BY g.id_usuario, g.id_gasto;

    -- 5 Gastos rendidos (con el comprobante y la lectura de la IA)
    SELECT g.id_gasto, g.id_usuario AS id_tecnico, TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))) AS tecnico,
           IF(cg.String3 = 'OTRO' AND g.concepto_texto IS NOT NULL, CONCAT('Otro: ', g.concepto_texto), IFNULL(cg.String1, 'Concepto')) AS concepto,
           g.monto, g.estado, DATE_FORMAT(COALESCE(g.fecha_gasto, g.fecha_solicitud), '%Y-%m-%d') AS fecha,
           IF(GREATEST((SELECT COUNT(*) FROM gasto_viatico_foto f WHERE f.id_gasto = g.id_gasto AND f.eliminado_en IS NULL),
                       IF(NULLIF(TRIM(IFNULL(g.url_comprobante, '')), '') IS NULL, 0, 1)) > 0, 1, 0) AS tiene_comprobante,
           g.monto_ia, g.coincide_ia
    FROM   gasto_viatico g
    JOIN   usuario u ON u.id_usuario = g.id_usuario
    LEFT JOIN tabla_maestra cg ON cg.IdMaestro = 25 AND cg.IdEmpresa = 1 AND cg.Num1 = g.id_concepto
    WHERE  g.tipo = 'gasto_solicitado' AND g.eliminado_en IS NULL AND (g.id_programacion = v_prog OR (g.id_programacion IS NULL AND g.id_os = p_id_os))
    ORDER BY COALESCE(g.fecha_gasto, g.fecha_solicitud), g.id_gasto;
END$$

DELIMITER ;

-- HU-45 (Sprint 5) "Guardar asignación" de la pestaña Asignación de Viáticos. Solo el Jefe (prog_aprobar_reprogramacion) y con la programación
-- CONFIRMADA (Programado), su rendición abierta y el servicio todavía sin salir a campo (OS no en_ruta/en_ejecucion/pausada/finalizada). Modelo B: el Jefe asigna un monto por técnico y concepto como ADELANTO.
--   p_version: la huella que devolvió SP_ObtenerViaticosProgramacion. Si otra persona (o Contabilidad al depositar) cambió la asignación
--     mientras se editaba, se rechaza y hay que recargar (control de concurrencia optimista).
--   p_lineas (JSON): la asignación COMPLETA que debe quedar: [{"idGasto":n|null,"idTecnico":n,"idConcepto":n|null,"nuevoConcepto":"texto"|null,"monto":0.00}]
--     · idGasto null = línea nueva · idGasto = línea existente (se actualiza si cambió) · línea existente que no viene = se quita.
--     · Un concepto es del catálogo (idConcepto) O nuevo (nuevoConcepto: se crea una vez; si ya existe con el mismo nombre se reutiliza).
--     · Solo técnicos de esta programación; un concepto por técnico; monto > 0 y hasta VIATICOS_MONTO_MAXIMO (5 000 por defecto).
--     · Las líneas DEPOSITADAS (estado 'aprobado', las marca Contabilidad) son inmutables: deben venir tal cual y no se pueden quitar.
-- Al guardar con cambios (o con líneas nunca avisadas) se NOTIFICA a Contabilidad (área contabilidad) con la lista consolidada de lo pendiente
--   de depósito. Este módulo NUNCA marca "Depositado". Auditoría en el historial de la programación.
-- EXCEPCIÓN (App Mobile HU-35, decisión del usuario): el jefe también puede marcar «Ya depositado» desde la app (hasta ahora solo Contabilidad lo marcaba, fuera de este módulo).
--   SP_AsignarViaticoEquipoMovil lo pide con TRES variables de sesión que fija justo antes de llamar a este SP y limpia al terminar:
--     @tw_vi_deposita_jefe (= quien guarda) · @tw_vi_deposita_prog (= esta programación) · @tw_vi_deposita_tecnico (técnico cuyos viáticos pendientes quedan depositados).
--   Solo si las tres coinciden con esta llamada, al final de los cambios (misma transacción) las líneas pendientes de ese técnico pasan a 'aprobado' (depositado) con fecha_deposito
--   de hoy (Lima). Es lo que Contabilidad hace por su lado, así que no se les avisa de lo ya depositado (la lista y el aviso solo cuentan lo pendiente). Queda auditado aparte
--   («marcado como depositado por el jefe desde la app»). Sin esas variables este SP se comporta como siempre (la intranet no cambia).
--   @tw_vi_ok = 1 al terminar con éxito (también «sin cambios»): lo lee SP_AsignarViaticoEquipoMovil para avisar al técnico solo si guardó.
-- Concurrencia: OS → programación → catálogo (mismo orden que el resto). Resultados: 1 mensaje, 2 resultado.
DROP PROCEDURE IF EXISTS SP_GuardarViaticosProgramacion;

DELIMITER $$

CREATE PROCEDURE SP_GuardarViaticosProgramacion(
    IN p_id_usuario      BIGINT,
    IN p_id_programacion BIGINT,
    IN p_version         VARCHAR(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_lineas          JSON
)
proc: BEGIN
    DECLARE v_id_os      BIGINT DEFAULT NULL;
    DECLARE v_numero     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tipo       VARCHAR(5)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_cliente BIGINT DEFAULT NULL;
    DECLARE v_cliente    VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_codigo     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado     VARCHAR(25)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado_os  VARCHAR(25)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_version    VARCHAR(80);
    DECLARE v_cap        DECIMAL(18,6) DEFAULT 5000;
    DECLARE v_error      VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_n          INT DEFAULT 0;
    DECLARE v_i          INT DEFAULT 1;
    DECLARE v_nombre     VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_conc    INT DEFAULT NULL;
    DECLARE v_next       INT DEFAULT 0;
    DECLARE v_nuevos     INT DEFAULT 0;
    DECLARE v_custom     INT DEFAULT 0;
    DECLARE v_creadas    INT DEFAULT 0;
    DECLARE v_modif      INT DEFAULT 0;
    DECLARE v_retiradas  INT DEFAULT 0;
    DECLARE v_retirados  TEXT;
    DECLARE v_sin_avisar INT DEFAULT 0;
    DECLARE v_lista      TEXT;
    DECLARE v_total      DECIMAL(12,2) DEFAULT 0;
    DECLARE v_depos      DECIMAL(12,2) DEFAULT 0;
    DECLARE v_pend       DECIMAL(12,2) DEFAULT 0;
    DECLARE v_contab     INT DEFAULT 0;
    DECLARE v_dep_app    INT DEFAULT 0;
    DECLARE v_dep_nombre VARCHAR(210) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_mensaje    VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            @err_msg  = MESSAGE_TEXT,
            @err_code = MYSQL_ERRNO;
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_vi_in;
        DROP TEMPORARY TABLE IF EXISTS tmp_vi_nc;
        IF @err_code IN (1213, 1205) THEN
            SELECT 1 AS IdTipoMensaje, 'Otra persona está modificando esta programación en este momento. Inténtalo de nuevo.' AS Mensaje;
        ELSE
            SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
        END IF;
    END;

    SET SESSION group_concat_max_len = 32768;

    IF FN_PermisoAccion(p_id_usuario, 'prog_aprobar_reprogramacion') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Solo el Jefe de Operaciones puede asignar viáticos.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF IFNULL(p_id_programacion, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'La programación no existe.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF NULLIF(TRIM(IFNULL(p_version, '')), '') IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Falta la versión de la asignación: vuelve a abrir la gestión de viáticos.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF p_lineas IS NULL OR NOT JSON_VALID(p_lineas) OR JSON_TYPE(p_lineas) <> 'ARRAY' THEN
        SELECT 1 AS IdTipoMensaje, 'La asignación debe enviarse como una lista de líneas.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF JSON_LENGTH(p_lineas) > 60 THEN
        SELECT 1 AS IdTipoMensaje, 'Una programación admite hasta 60 líneas de viáticos.' AS Mensaje;
        LEAVE proc;
    END IF;
    CALL SP_LeerParametroProgramacion('VIATICOS_MONTO_MAXIMO', 5000, v_cap);

    SELECT id_os INTO v_id_os FROM programacion WHERE id_programacion = p_id_programacion AND eliminado_en IS NULL;
    IF v_id_os IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'La programación no existe.' AS Mensaje;
        LEAVE proc;
    END IF;

    START TRANSACTION;

    SELECT numero, tipo, id_cliente, estado INTO v_numero, v_tipo, v_id_cliente, v_estado_os
    FROM orden_servicio WHERE id_os = v_id_os AND eliminado_en IS NULL FOR UPDATE;
    SELECT codigo, estado INTO v_codigo, v_estado FROM programacion WHERE id_programacion = p_id_programacion AND eliminado_en IS NULL FOR UPDATE;

    IF v_codigo IS NULL THEN
        SET v_error = 'La programación no existe.';
    ELSEIF v_estado_os IN ('en_ruta', 'en_ejecucion', 'pausada', 'finalizada') THEN
        -- La app pasa la OS a en_ruta al iniciar el traslado (SP_IniciarTrasladoMovil)
        SET v_error = 'La asignación ya no se puede editar: el servicio salió a campo.';
    ELSEIF v_estado = 'cancelada' THEN
        SET v_error = CONCAT('La programación ', v_codigo, ' está cancelada: ya no admite viáticos.');
    ELSEIF v_estado <> 'confirmada' THEN
        SET v_error = CONCAT('La programación ', v_codigo, ' aún no está confirmada por el cliente: los viáticos se asignan cuando está Programado.');
    ELSEIF EXISTS (SELECT 1 FROM programacion_rendicion WHERE id_programacion = p_id_programacion AND eliminado_en IS NULL) THEN
        SET v_error = 'La rendición ya fue cerrada: los viáticos quedan solo de lectura.';
    END IF;
    IF v_error IS NOT NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, v_error AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_VersionViaticosProgramacion(p_id_programacion, v_id_os, 1, v_version);
    IF v_version <> TRIM(p_version) THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'La asignación cambió mientras la editabas (por ejemplo, Contabilidad registró un depósito). Recarga e inténtalo de nuevo.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- ── Entrada ───────────────────────────────────────────────────────────────────────────
    DROP TEMPORARY TABLE IF EXISTS tmp_vi_in;
    CREATE TEMPORARY TABLE tmp_vi_in (
        n        INT NOT NULL, id_gasto BIGINT NULL, id_usuario BIGINT NULL, id_concepto INT NULL,
        nuevo    VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL, monto DECIMAL(12,2) NULL, cf INT NULL,
        PRIMARY KEY (n)
    );
    INSERT INTO tmp_vi_in (n, id_gasto, id_usuario, id_concepto, nuevo, monto)
    SELECT j.n, j.id_gasto, j.id_usuario, j.id_concepto, NULLIF(TRIM(j.nuevo), ''), j.monto
    FROM JSON_TABLE(p_lineas, '$[*]' COLUMNS (
            n FOR ORDINALITY,
            id_gasto    BIGINT         PATH '$.idGasto'       NULL ON EMPTY NULL ON ERROR,
            id_usuario  BIGINT         PATH '$.idTecnico'     NULL ON EMPTY NULL ON ERROR,
            id_concepto INT            PATH '$.idConcepto'    NULL ON EMPTY NULL ON ERROR,
            nuevo       VARCHAR(100)   PATH '$.nuevoConcepto' NULL ON EMPTY NULL ON ERROR,
            monto       DECIMAL(12,2)  PATH '$.monto'         NULL ON EMPTY NULL ON ERROR)) j;
    SELECT COUNT(*) INTO v_n FROM tmp_vi_in;

    -- Formas
    IF v_n <> JSON_LENGTH(p_lineas) THEN
        SET v_error = 'La asignación tiene líneas con un formato no válido.';
    ELSEIF EXISTS (SELECT 1 FROM tmp_vi_in WHERE monto IS NULL OR monto <= 0 OR monto > v_cap) THEN
        SET v_error = CONCAT('Cada monto debe ser mayor a 0 y de hasta S/ ', FORMAT(v_cap, 2), '.');
    ELSEIF EXISTS (SELECT 1 FROM tmp_vi_in WHERE id_usuario IS NULL OR id_usuario <= 0) THEN
        SET v_error = 'Cada línea debe indicar el técnico.';
    ELSEIF EXISTS (SELECT 1 FROM tmp_vi_in WHERE (id_concepto IS NULL AND nuevo IS NULL) OR (id_concepto IS NOT NULL AND nuevo IS NOT NULL)) THEN
        SET v_error = 'Cada línea debe tener un concepto: elige uno del catálogo o crea uno nuevo (no ambos).';
    ELSEIF EXISTS (SELECT 1 FROM tmp_vi_in WHERE nuevo IS NOT NULL AND (CHAR_LENGTH(nuevo) NOT BETWEEN 2 AND 60 OR nuevo REGEXP '[[:cntrl:]]')) THEN
        SET v_error = 'El nombre del concepto nuevo debe tener entre 2 y 60 caracteres, sin caracteres de control.';
    ELSEIF EXISTS (SELECT 1 FROM tmp_vi_in WHERE id_gasto IS NOT NULL AND id_gasto <= 0) THEN
        SET v_error = 'Hay una línea con un identificador no válido.';
    ELSEIF EXISTS (SELECT 1 FROM tmp_vi_in WHERE id_gasto IS NOT NULL GROUP BY id_gasto HAVING COUNT(*) > 1) THEN
        SET v_error = 'Una línea viene repetida en la asignación.';
    ELSEIF EXISTS (SELECT 1 FROM tmp_vi_in t WHERE t.id_concepto IS NOT NULL
                   AND NOT EXISTS (SELECT 1 FROM tabla_maestra c WHERE c.IdMaestro = 25 AND c.IdEmpresa = 1 AND c.Num1 = t.id_concepto AND c.eliminado_en IS NULL)) THEN
        SET v_error = 'Hay un concepto que no existe en el catálogo.';
    ELSEIF (SELECT COUNT(DISTINCT id_usuario) FROM tmp_vi_in) > 10 THEN
        SET v_error = 'Una programación admite viáticos para hasta 10 técnicos.';
    END IF;

    -- Líneas existentes
    IF v_error IS NULL AND EXISTS (SELECT 1 FROM tmp_vi_in t WHERE t.id_gasto IS NOT NULL
        AND NOT EXISTS (SELECT 1 FROM gasto_viatico g WHERE g.id_gasto = t.id_gasto AND g.tipo = 'viatico_asignado' AND g.eliminado_en IS NULL
                          AND (g.id_programacion = p_id_programacion OR (g.id_programacion IS NULL AND g.id_os = v_id_os)))) THEN
        SET v_error = 'Una de las líneas ya no existe: recarga la gestión de viáticos.';
    END IF;

    -- Líneas depositadas: inmutables (deben venir iguales) y no se pueden quitar
    IF v_error IS NULL AND EXISTS (SELECT 1 FROM gasto_viatico g
        WHERE g.tipo = 'viatico_asignado' AND g.eliminado_en IS NULL AND g.estado IN ('aprobado', 'rendido')
          AND (g.id_programacion = p_id_programacion OR (g.id_programacion IS NULL AND g.id_os = v_id_os))
          AND NOT EXISTS (SELECT 1 FROM tmp_vi_in t WHERE t.id_gasto = g.id_gasto)) THEN
        SET v_error = 'Los viáticos ya depositados no se pueden quitar: inclúyelos tal como están.';
    END IF;
    IF v_error IS NULL AND EXISTS (SELECT 1 FROM tmp_vi_in t JOIN gasto_viatico g ON g.id_gasto = t.id_gasto
        WHERE g.estado IN ('aprobado', 'rendido') AND (g.monto <> t.monto OR g.id_usuario <> t.id_usuario OR (t.id_concepto IS NOT NULL AND g.id_concepto <> t.id_concepto) OR t.nuevo IS NOT NULL)) THEN
        SET v_error = 'Los viáticos ya depositados no se pueden modificar.';
    END IF;

    -- Técnicos: solo el personal de la programación (una línea nueva o modificada no puede ir a otra persona)
    IF v_error IS NULL AND EXISTS (SELECT 1 FROM tmp_vi_in t
        LEFT JOIN gasto_viatico g ON g.id_gasto = t.id_gasto
        WHERE NOT EXISTS (SELECT 1 FROM programacion_tecnico pt WHERE pt.id_programacion = p_id_programacion AND pt.id_usuario = t.id_usuario AND pt.eliminado_en IS NULL)
          AND (g.id_gasto IS NULL OR g.id_usuario <> t.id_usuario OR g.monto <> t.monto OR t.nuevo IS NOT NULL OR (t.id_concepto IS NOT NULL AND g.id_concepto <> t.id_concepto))) THEN
        SET v_error = 'Los viáticos solo se asignan al personal de esta programación.';
    END IF;
    IF v_error IS NOT NULL THEN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_vi_in;
        SELECT 1 AS IdTipoMensaje, v_error AS Mensaje;
        LEAVE proc;
    END IF;

    -- ── Conceptos nuevos: se reutiliza el existente con el mismo nombre; si no existe, se crea en el catálogo ─────────
    DROP TEMPORARY TABLE IF EXISTS tmp_vi_nc;
    CREATE TEMPORARY TABLE tmp_vi_nc (i INT NOT NULL AUTO_INCREMENT, nombre VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL, PRIMARY KEY (i));
    INSERT INTO tmp_vi_nc (nombre) SELECT DISTINCT nuevo FROM tmp_vi_in WHERE nuevo IS NOT NULL;
    SELECT COUNT(*) INTO v_nuevos FROM tmp_vi_nc;
    SET v_i = 1;
    WHILE v_i <= v_nuevos DO
        SELECT nombre INTO v_nombre FROM tmp_vi_nc WHERE i = v_i;
        SET v_id_conc = NULL;
        SELECT Num1 INTO v_id_conc FROM tabla_maestra
        WHERE IdMaestro = 25 AND IdEmpresa = 1 AND eliminado_en IS NULL AND String1 = v_nombre ORDER BY Num1 LIMIT 1;
        IF v_id_conc IS NULL THEN
            SELECT COUNT(*) INTO v_custom FROM tabla_maestra WHERE IdMaestro = 25 AND IdEmpresa = 1 AND eliminado_en IS NULL AND String3 LIKE 'PERS\_%';
            IF v_custom >= 50 THEN
                SET v_error = 'Se alcanzó el máximo de conceptos personalizados (50): usa uno existente.';
            ELSE
                SELECT IFNULL(MAX(Num1), 0) + 1 INTO v_next FROM tabla_maestra WHERE IdMaestro = 25 AND IdEmpresa = 1 FOR UPDATE;
                INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2, String3, creado_por)
                VALUES (1, 25, 'CONCEPTO_GASTO', v_next, v_nombre, 'viatico', CONCAT('PERS_', v_next), p_id_usuario);
                SET v_id_conc = v_next;
            END IF;
        END IF;
        IF v_error IS NOT NULL THEN
            SET v_i = v_nuevos + 1;
        ELSE
            UPDATE tmp_vi_in SET cf = v_id_conc WHERE nuevo = v_nombre;
            SET v_i = v_i + 1;
        END IF;
    END WHILE;
    IF v_error IS NOT NULL THEN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_vi_in;
        DROP TEMPORARY TABLE IF EXISTS tmp_vi_nc;
        SELECT 1 AS IdTipoMensaje, v_error AS Mensaje;
        LEAVE proc;
    END IF;
    UPDATE tmp_vi_in SET cf = id_concepto WHERE id_concepto IS NOT NULL;

    IF EXISTS (SELECT 1 FROM tmp_vi_in GROUP BY id_usuario, cf HAVING COUNT(*) > 1) THEN
        SET v_error = 'Un técnico no puede tener dos líneas con el mismo concepto: edita el monto de la existente.';
    ELSEIF EXISTS (SELECT 1 FROM tmp_vi_in GROUP BY id_usuario HAVING COUNT(*) > 12) THEN
        SET v_error = 'Un técnico admite hasta 12 conceptos de viáticos.';
    END IF;
    IF v_error IS NOT NULL THEN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_vi_in;
        DROP TEMPORARY TABLE IF EXISTS tmp_vi_nc;
        SELECT 1 AS IdTipoMensaje, v_error AS Mensaje;
        LEAVE proc;
    END IF;

    -- ── Cambios ───────────────────────────────────────────────────────────────────────────
    -- Quitadas (solo pendientes de depósito): se guarda qué se retiró si ya se le había avisado a Contabilidad
    SELECT GROUP_CONCAT(CONCAT(TRIM(CONCAT(u.nombre, ' ', u.apellido)), ' · ', IFNULL(c.String1, 'Concepto'), ' S/ ', FORMAT(g.monto, 2)) ORDER BY g.id_gasto SEPARATOR '; ')
      INTO v_retirados
    FROM gasto_viatico g
    JOIN usuario u ON u.id_usuario = g.id_usuario
    LEFT JOIN tabla_maestra c ON c.IdMaestro = 25 AND c.IdEmpresa = 1 AND c.Num1 = g.id_concepto
    WHERE g.tipo = 'viatico_asignado' AND g.eliminado_en IS NULL AND g.estado NOT IN ('aprobado', 'rendido') AND g.notificado_en IS NOT NULL
      AND (g.id_programacion = p_id_programacion OR (g.id_programacion IS NULL AND g.id_os = v_id_os))
      AND NOT EXISTS (SELECT 1 FROM tmp_vi_in t WHERE t.id_gasto = g.id_gasto);

    UPDATE gasto_viatico g
    SET g.eliminado_en = NOW(), g.eliminado_por = p_id_usuario
    WHERE g.tipo = 'viatico_asignado' AND g.eliminado_en IS NULL AND g.estado NOT IN ('aprobado', 'rendido')
      AND (g.id_programacion = p_id_programacion OR (g.id_programacion IS NULL AND g.id_os = v_id_os))
      AND NOT EXISTS (SELECT 1 FROM tmp_vi_in t WHERE t.id_gasto = g.id_gasto);
    SET v_retiradas = ROW_COUNT();

    UPDATE gasto_viatico g
    JOIN tmp_vi_in t ON t.id_gasto = g.id_gasto
    SET g.id_usuario = t.id_usuario, g.id_concepto = t.cf, g.monto = t.monto, g.notificado_en = NULL, g.modificado_por = p_id_usuario
    WHERE g.estado NOT IN ('aprobado', 'rendido') AND (g.monto <> t.monto OR g.id_concepto <> t.cf OR g.id_usuario <> t.id_usuario);
    SET v_modif = ROW_COUNT();

    UPDATE gasto_viatico g
    JOIN tmp_vi_in t ON t.id_gasto = g.id_gasto
    SET g.id_programacion = p_id_programacion
    WHERE g.id_programacion IS NULL;

    INSERT INTO gasto_viatico (id_os, id_programacion, id_usuario, id_concepto, id_moneda, monto, tipo, estado, fecha_solicitud, creado_por)
    SELECT v_id_os, p_id_programacion, t.id_usuario, t.cf, 1, t.monto, 'viatico_asignado', 'pendiente', CURDATE(), p_id_usuario
    FROM tmp_vi_in t WHERE t.id_gasto IS NULL;
    SET v_creadas = ROW_COUNT();

    -- Depósito marcado por el jefe desde la app (HU-35): ver la excepción en la cabecera
    IF IFNULL(@tw_vi_deposita_jefe, 0) = p_id_usuario AND IFNULL(@tw_vi_deposita_prog, 0) = p_id_programacion AND IFNULL(@tw_vi_deposita_tecnico, 0) > 0 THEN
        UPDATE gasto_viatico g
        SET g.estado = 'aprobado', g.fecha_deposito = DATE(UTC_TIMESTAMP() - INTERVAL 5 HOUR), g.modificado_por = p_id_usuario
        WHERE g.tipo = 'viatico_asignado' AND g.eliminado_en IS NULL AND g.estado NOT IN ('aprobado', 'rendido')
          AND g.id_usuario = @tw_vi_deposita_tecnico
          AND (g.id_programacion = p_id_programacion OR (g.id_programacion IS NULL AND g.id_os = v_id_os));
        SET v_dep_app = ROW_COUNT();
        SELECT TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))) INTO v_dep_nombre FROM usuario u WHERE u.id_usuario = @tw_vi_deposita_tecnico;
    END IF;

    DROP TEMPORARY TABLE IF EXISTS tmp_vi_in;
    DROP TEMPORARY TABLE IF EXISTS tmp_vi_nc;

    SELECT IFNULL(SUM(g.monto), 0), IFNULL(SUM(IF(g.estado IN ('aprobado', 'rendido'), g.monto, 0)), 0),
           IFNULL(SUM(IF(g.estado IN ('aprobado', 'rendido'), 0, g.monto)), 0), IFNULL(SUM(g.estado NOT IN ('aprobado', 'rendido') AND g.notificado_en IS NULL), 0)
      INTO v_total, v_depos, v_pend, v_sin_avisar
    FROM gasto_viatico g
    WHERE g.tipo = 'viatico_asignado' AND g.eliminado_en IS NULL AND (g.id_programacion = p_id_programacion OR (g.id_programacion IS NULL AND g.id_os = v_id_os));

    IF v_creadas + v_modif + v_retiradas + v_dep_app = 0 AND v_sin_avisar = 0 THEN
        COMMIT;
        SET @tw_vi_ok = 1;
        SELECT 2 AS IdTipoMensaje, 'No hay cambios en la asignación de viáticos.' AS Mensaje;
        SELECT p_id_programacion AS id_programacion, 0 AS creadas, 0 AS modificadas, 0 AS retiradas, v_total AS total_asignado, v_depos AS total_depositado,
               v_pend AS total_pendiente, 0 AS notificados_contabilidad, 1 AS sin_cambios, v_nuevos AS conceptos_nuevos, v_version AS version;
        LEAVE proc;
    END IF;

    -- ── Notificación a Contabilidad: lista consolidada de lo pendiente de depósito ─────────────────
    SELECT razon_social INTO v_cliente FROM cliente WHERE id_cliente = v_id_cliente;
    SELECT GROUP_CONCAT(CONCAT(x.tecnico, ': ', x.conceptos) ORDER BY x.orden, x.tecnico SEPARATOR ' · ') INTO v_lista
    FROM (SELECT TRIM(CONCAT(u.nombre, ' ', u.apellido)) AS tecnico, MIN(g.id_gasto) AS orden,
                 GROUP_CONCAT(CONCAT(IFNULL(c.String1, 'Concepto'), ' S/ ', FORMAT(g.monto, 2)) ORDER BY g.id_gasto SEPARATOR ', ') AS conceptos
          FROM gasto_viatico g
          JOIN usuario u ON u.id_usuario = g.id_usuario
          LEFT JOIN tabla_maestra c ON c.IdMaestro = 25 AND c.IdEmpresa = 1 AND c.Num1 = g.id_concepto
          WHERE g.tipo = 'viatico_asignado' AND g.eliminado_en IS NULL AND g.estado NOT IN ('aprobado', 'rendido')
            AND (g.id_programacion = p_id_programacion OR (g.id_programacion IS NULL AND g.id_os = v_id_os))
          GROUP BY g.id_usuario) x;

    -- Si lo único que pasó es que el jefe dejó todo depositado, no hay nada que pedirle a Contabilidad
    IF v_dep_app > 0 AND v_pend = 0 AND v_retirados IS NULL THEN
        SET v_contab = 0;
    ELSE
    INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
    SELECT u.id_usuario, 5, LEFT(CONCAT('Viáticos por depositar: ', v_numero), 150),
           LEFT(CONCAT('Programación ', v_codigo, ' · ', v_tipo, ' ', v_numero, IF(v_cliente IS NULL, '', CONCAT(' · ', v_cliente)), '. ',
                       IF(v_pend > 0, CONCAT('Pendiente de depósito: S/ ', FORMAT(v_pend, 2), ' (', IFNULL(v_lista, ''), ').'), 'No quedan viáticos pendientes de depósito.'),
                       IF(v_retirados IS NULL, '', CONCAT(' Se retiró lo anunciado antes: ', v_retirados, '.'))), 3000),
           'programacion', p_id_programacion, NOW(), p_id_usuario
    FROM usuario u
    WHERE u.eliminado_en IS NULL AND u.estado = 'activo' AND u.area = 'contabilidad' AND u.id_usuario <> p_id_usuario;
    SET v_contab = ROW_COUNT();
    END IF;

    UPDATE gasto_viatico g SET g.notificado_en = NOW()
    WHERE g.tipo = 'viatico_asignado' AND g.eliminado_en IS NULL AND g.estado NOT IN ('aprobado', 'rendido') AND g.notificado_en IS NULL
      AND (g.id_programacion = p_id_programacion OR (g.id_programacion IS NULL AND g.id_os = v_id_os));

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('programacion', p_id_programacion, 'asignar_viaticos', v_estado, v_estado,
            LEFT(CONCAT('Viáticos asignados en ', v_codigo, ': total S/ ', FORMAT(v_total, 2), ', pendiente de depósito S/ ', FORMAT(v_pend, 2),
                        ' (', v_creadas, ' nuevas, ', v_modif, ' modificadas, ', v_retiradas, ' retiradas).'), 900),
            p_id_usuario, NOW(),
            JSON_OBJECT('creadas', v_creadas, 'modificadas', v_modif, 'retiradas', v_retiradas, 'totalAsignado', v_total,
                        'totalDepositado', v_depos, 'totalPendiente', v_pend, 'conceptosNuevos', v_nuevos, 'notificadosContabilidad', v_contab));

    IF v_dep_app > 0 THEN
        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
        VALUES ('programacion', p_id_programacion, 'depositar_viaticos_app', v_estado, v_estado,
                LEFT(CONCAT('Viáticos de ', IFNULL(v_dep_nombre, 'un técnico'), ' en ', v_codigo, ' marcados como depositados por el jefe desde la app (', v_dep_app, ' líneas).'), 900),
                p_id_usuario, NOW(), JSON_OBJECT('idTecnico', @tw_vi_deposita_tecnico, 'lineas', v_dep_app, 'origen', 'app_movil'));
    END IF;

    COMMIT;
    SET @tw_vi_ok = 1;

    CALL SP_VersionViaticosProgramacion(p_id_programacion, v_id_os, 1, v_version);
    SET v_mensaje = CONCAT('Asignación de viáticos guardada.',
                           IF(v_contab > 0, CONCAT(' Se notificó a Contabilidad: S/ ', FORMAT(v_pend, 2), ' pendientes de depósito.'),
                              IF(v_dep_app > 0 AND v_pend = 0, ' Los viáticos quedaron depositados: no hay nada que avisar a Contabilidad.',
                                 ' No hay usuarios de Contabilidad configurados para recibir el aviso.')));
    SELECT 2 AS IdTipoMensaje, v_mensaje AS Mensaje;
    SELECT p_id_programacion AS id_programacion, v_creadas AS creadas, v_modif AS modificadas, v_retiradas AS retiradas, v_total AS total_asignado,
           v_depos AS total_depositado, v_pend AS total_pendiente, v_contab AS notificados_contabilidad, 0 AS sin_cambios, v_nuevos AS conceptos_nuevos,
           v_version AS version;
END$$

DELIMITER ;

-- ============================================================
-- SP_AsignarViaticoEquipoMovil  (App Mobile HU-35 — "Asignar viático" a un técnico del servicio, por concepto · escritura)
-- El jefe asigna a UN técnico del servicio los montos de Movilidad, Alimentación, Alojamiento y Otros, y puede dejarlo marcado como «Ya depositado». El técnico lo ve al instante en
-- «Viáticos y Gastos» de su app (HU-25) y recibe la notificación «Viático asignado».
-- NO duplica las reglas de la intranet (HU-45): arma la asignación COMPLETA de la programación (las líneas de los demás técnicos y los demás conceptos del técnico quedan tal cual;
-- los 4 conceptos del técnico se ponen con los montos recibidos) y la guarda con SP_GuardarViaticosProgramacion, que valida: prog_aprobar_reprogramacion, programación confirmada,
-- rendición abierta, servicio sin salir a campo, tope VIATICOS_MONTO_MAXIMO, concurrencia por versión, líneas depositadas inmutables, auditoría y aviso a Contabilidad.
--   p_version : la huella (SP_ObtenerViaticoServicioEquipoMovil.version) con la que el jefe abrió el servicio; si cambió mientras tanto, se rechaza y hay que recargar.
--   Un monto 0 (o vacío) quita esa línea si todavía no está depositada; una línea depositada no se puede cambiar ni quitar (mensaje de negocio).
--   p_depositado = 1 : los viáticos PENDIENTES de ese técnico quedan depositados (estado 'aprobado' + fecha de depósito) en la misma transacción.
--     EXCEPCIÓN pedida por el usuario a la regla de HU-45 «el módulo nunca marca Depositado» (lo hacía solo Contabilidad): ver la cabecera de SP_GuardarViaticosProgramacion.
--     Un depósito no se puede revertir: si todo lo del técnico ya está depositado y llega p_depositado = 0, se responde con un mensaje de negocio.
--     Contabilidad: lo pendiente se les sigue avisando; lo que el jefe deja depositado no.
--   Alcance (Área + Rol): SP_ArmarAlcanceViaticosMovil. El técnico debe ser del personal de la programación.
-- Resultados: los de SP_GuardarViaticosProgramacion (1 mensaje · 2 resultado: total_asignado, total_depositado, total_pendiente, notificados_contabilidad, sin_cambios, version…)
--   y, solo si guardó, 3: total_tecnico (lo asignado a ese técnico), depositado (1 si todo lo del técnico está depositado), tecnico_notificado (1 si se le avisó), version.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_AsignarViaticoEquipoMovil;

DELIMITER $$

CREATE PROCEDURE SP_AsignarViaticoEquipoMovil(
    IN p_id_usuario  BIGINT,
    IN p_id_os       BIGINT,
    IN p_id_tecnico  BIGINT,
    IN p_movilidad   DECIMAL(12,2),
    IN p_alimentacion DECIMAL(12,2),
    IN p_alojamiento DECIMAL(12,2),
    IN p_otros       DECIMAL(12,2),
    IN p_depositado  TINYINT,
    IN p_version     VARCHAR(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_sin       TINYINT DEFAULT 0;
    DECLARE v_prog      BIGINT DEFAULT NULL;
    DECLARE v_numero    VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cliente   VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_json      JSON DEFAULT NULL;
    DECLARE v_cap       DECIMAL(18,6) DEFAULT 5000;
    DECLARE v_mov       INT DEFAULT NULL;
    DECLARE v_ali       INT DEFAULT NULL;
    DECLARE v_alo       INT DEFAULT NULL;
    DECLARE v_otr       INT DEFAULT NULL;
    DECLARE v_error     VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_concepto  VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_v0        VARCHAR(80);
    DECLARE v_v1        VARCHAR(80);
    DECLARE v_total_tec DECIMAL(12,2) DEFAULT 0;
    DECLARE v_n_tec     INT DEFAULT 0;
    DECLARE v_pend_tec  INT DEFAULT 0;
    DECLARE v_depos_tec INT DEFAULT 0;
    DECLARE v_notif     TINYINT DEFAULT 0;
    DECLARE v_lista     TEXT;
    DECLARE v_dep_prev  INT DEFAULT 0;
    DECLARE v_pend_nuevo INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SET @tw_vi_deposita_jefe = NULL, @tw_vi_deposita_prog = NULL, @tw_vi_deposita_tecnico = NULL;
        DROP TEMPORARY TABLE IF EXISTS tmp_vi_alc;
        DROP TEMPORARY TABLE IF EXISTS tmp_vi_lin;
        DROP TEMPORARY TABLE IF EXISTS tmp_vi_pedido;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SET SESSION group_concat_max_len = 32768;
    SET @tw_vi_deposita_jefe = NULL, @tw_vi_deposita_prog = NULL, @tw_vi_deposita_tecnico = NULL, @tw_vi_ok = 0;

    IF FN_PermisoAccion(p_id_usuario, 'prog_aprobar_reprogramacion') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Solo el Jefe de Operaciones puede asignar viáticos.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF IFNULL(p_id_os, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El servicio indicado no es válido.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF IFNULL(p_id_tecnico, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Elige el técnico al que se asigna el viático.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF NULLIF(TRIM(IFNULL(p_version, '')), '') IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Falta la versión de la asignación: vuelve a abrir los viáticos del servicio.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET p_movilidad    = IFNULL(p_movilidad, 0);
    SET p_alimentacion = IFNULL(p_alimentacion, 0);
    SET p_alojamiento  = IFNULL(p_alojamiento, 0);
    SET p_otros        = IFNULL(p_otros, 0);
    IF p_movilidad < 0 OR p_alimentacion < 0 OR p_alojamiento < 0 OR p_otros < 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Los montos no pueden ser negativos.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF p_movilidad + p_alimentacion + p_alojamiento + p_otros <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Indica al menos un monto mayor a 0.' AS Mensaje;
        LEAVE proc;
    END IF;
    CALL SP_LeerParametroProgramacion('VIATICOS_MONTO_MAXIMO', 5000, v_cap);
    IF p_movilidad > v_cap OR p_alimentacion > v_cap OR p_alojamiento > v_cap OR p_otros > v_cap THEN
        SELECT 1 AS IdTipoMensaje, CONCAT('Cada monto debe ser de hasta S/ ', FORMAT(v_cap, 2), '.') AS Mensaje;
        LEAVE proc;
    END IF;

    -- Alcance: el servicio debe ser de los que el jefe ve y operar
    CALL SP_ArmarAlcanceViaticosMovil(p_id_usuario, p_id_os, v_sin);
    IF v_sin = 1 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_vi_alc;
        SELECT 1 AS IdTipoMensaje, 'Tu cargo no tiene el menú de Jefatura.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM tmp_vi_alc WHERE id_os = p_id_os) THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_vi_alc;
        SELECT 1 AS IdTipoMensaje, 'El servicio no existe, no tiene programación o no pertenece a tu alcance.' AS Mensaje;
        LEAVE proc;
    END IF;
    DROP TEMPORARY TABLE IF EXISTS tmp_vi_alc;

    SELECT MAX(p2.id_programacion) INTO v_prog
    FROM programacion p2 WHERE p2.id_os = p_id_os AND p2.estado <> 'cancelada' AND p2.eliminado_en IS NULL;
    SELECT os.numero, COALESCE(NULLIF(cl.nombre_comercial, ''), cl.razon_social) INTO v_numero, v_cliente
    FROM orden_servicio os LEFT JOIN cliente cl ON cl.id_cliente = os.id_cliente WHERE os.id_os = p_id_os;

    IF NOT EXISTS (SELECT 1 FROM programacion_tecnico pt
                   WHERE pt.id_programacion = v_prog AND pt.id_usuario = p_id_tecnico AND pt.eliminado_en IS NULL) THEN
        SELECT 1 AS IdTipoMensaje, 'Los viáticos solo se asignan al personal de este servicio.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Los 4 conceptos fijos del catálogo CONCEPTO_GASTO (el catálogo de la intranet)
    SELECT MIN(Num1) INTO v_mov FROM tabla_maestra WHERE IdMaestro = 25 AND IdEmpresa = 1 AND eliminado_en IS NULL AND String3 = 'MOVILIDAD';
    SELECT MIN(Num1) INTO v_ali FROM tabla_maestra WHERE IdMaestro = 25 AND IdEmpresa = 1 AND eliminado_en IS NULL AND String3 = 'ALIMENTACION';
    SELECT MIN(Num1) INTO v_alo FROM tabla_maestra WHERE IdMaestro = 25 AND IdEmpresa = 1 AND eliminado_en IS NULL AND String3 = 'ALOJAMIENTO';
    SELECT MIN(Num1) INTO v_otr FROM tabla_maestra WHERE IdMaestro = 25 AND IdEmpresa = 1 AND eliminado_en IS NULL AND String3 = 'OTRO';
    IF v_mov IS NULL OR v_ali IS NULL OR v_alo IS NULL OR v_otr IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'El catálogo de conceptos de gasto no tiene Movilidad, Alimentación, Alojamiento u Otro: pídele a TI que lo complete.' AS Mensaje;
        LEAVE proc;
    END IF;

    DROP TEMPORARY TABLE IF EXISTS tmp_vi_pedido;
    CREATE TEMPORARY TABLE tmp_vi_pedido (id_concepto INT NOT NULL, monto DECIMAL(12,2) NOT NULL, PRIMARY KEY (id_concepto));
    INSERT INTO tmp_vi_pedido (id_concepto, monto)
    VALUES (v_mov, p_movilidad), (v_ali, p_alimentacion), (v_alo, p_alojamiento), (v_otr, p_otros);

    -- Un viático ya depositado no se modifica ni se quita
    SELECT MIN(IFNULL(cg.String1, 'Concepto')) INTO v_concepto
    FROM gasto_viatico g
    JOIN tmp_vi_pedido d ON d.id_concepto = g.id_concepto
    LEFT JOIN tabla_maestra cg ON cg.IdMaestro = 25 AND cg.IdEmpresa = 1 AND cg.Num1 = g.id_concepto
    WHERE g.tipo = 'viatico_asignado' AND g.eliminado_en IS NULL AND g.id_usuario = p_id_tecnico AND g.estado IN ('aprobado', 'rendido')
      AND (g.id_programacion = v_prog OR (g.id_programacion IS NULL AND g.id_os = p_id_os))
      AND g.monto <> d.monto;
    IF v_concepto IS NOT NULL THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_vi_pedido;
        SELECT 1 AS IdTipoMensaje, CONCAT('El viático de ', v_concepto, ' ya está depositado: no se puede modificar ni quitar.') AS Mensaje;
        LEAVE proc;
    END IF;

    -- Asignación completa: lo ajeno y lo que no se toca queda igual; los 4 conceptos del técnico salen del formulario
    DROP TEMPORARY TABLE IF EXISTS tmp_vi_lin;
    CREATE TEMPORARY TABLE tmp_vi_lin (id_gasto BIGINT NULL, id_usuario BIGINT NOT NULL, id_concepto INT NOT NULL, monto DECIMAL(12,2) NOT NULL);

    INSERT INTO tmp_vi_lin (id_gasto, id_usuario, id_concepto, monto)
    SELECT g.id_gasto, g.id_usuario, g.id_concepto, g.monto
    FROM gasto_viatico g
    WHERE g.tipo = 'viatico_asignado' AND g.eliminado_en IS NULL
      AND (g.id_programacion = v_prog OR (g.id_programacion IS NULL AND g.id_os = p_id_os))
      AND NOT (g.id_usuario = p_id_tecnico AND g.id_concepto IN (v_mov, v_ali, v_alo, v_otr));

    INSERT INTO tmp_vi_lin (id_gasto, id_usuario, id_concepto, monto)
    SELECT g.id_gasto, p_id_tecnico, d.id_concepto, d.monto
    FROM tmp_vi_pedido d
    LEFT JOIN gasto_viatico g ON g.tipo = 'viatico_asignado' AND g.eliminado_en IS NULL AND g.id_usuario = p_id_tecnico AND g.id_concepto = d.id_concepto
                              AND (g.id_programacion = v_prog OR (g.id_programacion IS NULL AND g.id_os = p_id_os))
    WHERE d.monto > 0;

    DROP TEMPORARY TABLE IF EXISTS tmp_vi_pedido;

    -- Un depósito no se revierte: si todo lo del técnico ya está depositado y se pide «Pendiente», no hay nada que hacer
    SELECT IFNULL(SUM(g.estado IN ('aprobado', 'rendido')), 0) INTO v_dep_prev
    FROM gasto_viatico g
    WHERE g.tipo = 'viatico_asignado' AND g.eliminado_en IS NULL AND g.id_usuario = p_id_tecnico
      AND (g.id_programacion = v_prog OR (g.id_programacion IS NULL AND g.id_os = p_id_os));
    SELECT COUNT(*) INTO v_pend_nuevo
    FROM tmp_vi_lin l
    LEFT JOIN gasto_viatico g ON g.id_gasto = l.id_gasto
    WHERE l.id_usuario = p_id_tecnico AND (l.id_gasto IS NULL OR g.estado NOT IN ('aprobado', 'rendido'));
    IF IFNULL(p_depositado, 0) = 0 AND v_dep_prev > 0 AND v_pend_nuevo = 0 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_vi_lin;
        SELECT 1 AS IdTipoMensaje, 'Los viáticos de este técnico ya están depositados: no se puede volver a Pendiente.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT JSON_ARRAYAGG(JSON_OBJECT('idGasto', l.id_gasto, 'idTecnico', l.id_usuario, 'idConcepto', l.id_concepto, 'monto', l.monto))
      INTO v_json
    FROM tmp_vi_lin l;
    DROP TEMPORARY TABLE IF EXISTS tmp_vi_lin;
    IF v_json IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'No hay nada que asignar.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_VersionViaticosProgramacion(v_prog, p_id_os, 1, v_v0);

    -- Guardar con las reglas de HU-45 (y, si el jefe lo pidió, dejar el depósito marcado en la misma transacción)
    IF IFNULL(p_depositado, 0) = 1 THEN
        SET @tw_vi_deposita_jefe = p_id_usuario, @tw_vi_deposita_prog = v_prog, @tw_vi_deposita_tecnico = p_id_tecnico;
    END IF;
    SET @tw_vi_ok = 0;
    CALL SP_GuardarViaticosProgramacion(p_id_usuario, v_prog, TRIM(p_version), v_json);
    SET @tw_vi_deposita_jefe = NULL, @tw_vi_deposita_prog = NULL, @tw_vi_deposita_tecnico = NULL;

    -- Solo si guardó: aviso al técnico y totales de su asignación
    IF @tw_vi_ok = 1 THEN
        SET @tw_vi_ok = 0;
        CALL SP_VersionViaticosProgramacion(v_prog, p_id_os, 1, v_v1);

        SELECT IFNULL(SUM(g.monto), 0), COUNT(*), IFNULL(SUM(g.estado NOT IN ('aprobado', 'rendido')), 0),
               GROUP_CONCAT(CONCAT(IFNULL(cg.String1, 'Concepto'), ' S/ ', FORMAT(g.monto, 2)) ORDER BY g.id_gasto SEPARATOR ', ')
          INTO v_total_tec, v_n_tec, v_pend_tec, v_lista
        FROM gasto_viatico g
        LEFT JOIN tabla_maestra cg ON cg.IdMaestro = 25 AND cg.IdEmpresa = 1 AND cg.Num1 = g.id_concepto
        WHERE g.tipo = 'viatico_asignado' AND g.eliminado_en IS NULL AND g.id_usuario = p_id_tecnico
          AND (g.id_programacion = v_prog OR (g.id_programacion IS NULL AND g.id_os = p_id_os));
        SET v_depos_tec = IF(v_n_tec > 0 AND v_pend_tec = 0, 1, 0);

        IF v_v1 <> v_v0 AND p_id_tecnico <> p_id_usuario AND v_n_tec > 0 THEN
            INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por, prioridad_origen)
            VALUES (p_id_tecnico, 5, LEFT(CONCAT('Viático asignado: S/ ', FORMAT(v_total_tec, 2)), 150),
                    LEFT(CONCAT(v_numero, IF(v_cliente IS NULL, '', CONCAT(' · ', v_cliente)), '. ', IFNULL(v_lista, ''), '. ',
                                IF(v_depos_tec = 1, 'Ya está depositado.', 'Pendiente de depósito.'), ' Míralo en Viáticos y Gastos.'), 3000),
                    'programacion', v_prog, NOW(), p_id_usuario, 'alta');
            SET v_notif = 1;
        END IF;

        SELECT v_total_tec AS total_tecnico, v_depos_tec AS depositado, v_notif AS tecnico_notificado, v_v1 AS version;
    END IF;
END$$

DELIMITER ;

-- ============================================================
-- SP_RevisarGastoMovil  (App Mobile HU-31 — el Jefe de Operaciones aprueba, observa o rechaza un gasto desde la bandeja de aprobaciones · escritura)
--   HU-35: además el gasto debe ser de un servicio del alcance del jefe (Área + Rol, SP_ArmarAlcanceViaticosMovil); fuera del alcance responde como si no existiera.
--   Resuelve la programación del gasto y llama a SP_RevisarGastoProgramacion (HU-45), que valida: solo prog_aprobar_reprogramacion, programación confirmada,
--   rendición abierta, acción aprobar | observar | rechazar con su comentario (obligatorio al observar o rechazar) y que un gasto ya aprobado o rechazado
--   no se vuelve a resolver (si otro jefe ya lo resolvió responde con un mensaje de negocio). Notifica al técnico y deja auditoría.
-- Resultados: los de SP_RevisarGastoProgramacion (1 mensaje, 2 gasto resultante, 3 tarjetas de la rendición).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_RevisarGastoMovil;

DELIMITER $$

CREATE PROCEDURE SP_RevisarGastoMovil(
    IN p_id_usuario BIGINT,
    IN p_id_gasto   BIGINT,
    IN p_accion     VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_comentario VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_n    INT DEFAULT 0;
    DECLARE v_id_os BIGINT;
    DECLARE v_prog BIGINT;
    DECLARE v_sin  TINYINT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_vi_alc;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF FN_PermisoAccion(p_id_usuario, 'prog_aprobar_reprogramacion') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Solo el Jefe de Operaciones puede revisar los gastos rendidos.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF IFNULL(p_id_gasto, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El gasto no existe.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT COUNT(*), MAX(id_os), MAX(id_programacion) INTO v_n, v_id_os, v_prog
    FROM gasto_viatico WHERE id_gasto = p_id_gasto AND tipo = 'gasto_solicitado' AND eliminado_en IS NULL;
    IF v_n = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El gasto no existe.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_prog IS NULL THEN
        SELECT MAX(id_programacion) INTO v_prog FROM programacion WHERE id_os = v_id_os AND estado <> 'cancelada' AND eliminado_en IS NULL;
    END IF;
    IF v_prog IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'El servicio del gasto no tiene una programación activa.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Alcance Área + Rol (HU-35, SP_ArmarAlcanceViaticosMovil): solo gastos de servicios que el jefe ve (Supervisor de ST / Metrología: los de su área)
    CALL SP_ArmarAlcanceViaticosMovil(p_id_usuario, v_id_os, v_sin);
    IF v_sin = 1 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_vi_alc;
        SELECT 1 AS IdTipoMensaje, 'Tu cargo no tiene el menú de Jefatura.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM tmp_vi_alc WHERE id_os = v_id_os) THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_vi_alc;
        SELECT 1 AS IdTipoMensaje, 'El gasto no existe o no pertenece a tu alcance.' AS Mensaje;
        LEAVE proc;
    END IF;
    DROP TEMPORARY TABLE IF EXISTS tmp_vi_alc;

    CALL SP_RevisarGastoProgramacion(p_id_usuario, v_prog, p_id_gasto, p_accion, p_comentario);
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
        -- HU-35: además del permiso, el servicio del gasto debe estar en el alcance Área + Rol del jefe (la misma regla de las demás aprobaciones y de SP_ArmarAlcanceViaticosMovil)
        SET v_ve = IF(FN_PermisoAccion(p_id_usuario, 'prog_aprobar_reprogramacion') = 1
                      AND (v_general = 1 OR (v_area_jefe IS NOT NULL AND (v_area_os IS NULL OR v_area_os = v_area_jefe))), 1, 0);
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
--                               Solo con prog_aprobar_reprogramacion (el Jefe de Operaciones, quien revisa los gastos: SP_RevisarGastoProgramacion) y solo los de servicios de su
--                               alcance Área + Rol (HU-35, SP_ArmarAlcanceViaticosMovil: el mismo número que los "por revisar" de Viáticos y gastos del equipo).
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
        DECLARE v_tiene_inf TINYINT DEFAULT 0;
        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            SET @tw_inf_usuario = NULL, @tw_inf_ver_todo = NULL, @tw_inf_area = NULL;
            DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;
            SET v_informes = NULL;
        END;
        IF FN_PermisoAccion(p_id_usuario, 'rt_bandeja') = 1 THEN
            -- Con el alcance de la app (regla ÁREA + ROL) y sin los observados (esos esperan la corrección del técnico): los mismos de la pestaña "Por revisar" (HU-33)
            CALL SP_FijarAlcanceInformesMovil(p_id_usuario, v_tiene_inf);
            IF v_tiene_inf = 1 THEN
                CALL SP_ArmarBaseInformes(p_id_usuario, NULL);
                SELECT COUNT(*) INTO v_informes FROM tmp_rt_base
                WHERE grupo_estado IN ('pendiente_revision', 'pendiente_precotizacion') AND estado <> 'observado';
                DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;
            END IF;
            SET @tw_inf_usuario = NULL, @tw_inf_ver_todo = NULL, @tw_inf_area = NULL;
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

    -- Viáticos y Gastos: gastos rendidos por revisar (solo quien los revisa y solo los de su alcance Área + Rol: SP_ArmarAlcanceViaticosMovil, el mismo de "Viáticos y gastos del
    -- equipo" y de la revisión de un gasto; el mismo número que los "por revisar" de esa pantalla)
    BEGIN
        DECLARE v_sin_vi TINYINT DEFAULT 0;
        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            SET v_gastos = NULL;
            DROP TEMPORARY TABLE IF EXISTS tmp_vi_alc;
        END;
        IF FN_PermisoAccion(p_id_usuario, 'prog_aprobar_reprogramacion') = 1 THEN
            CALL SP_ArmarAlcanceViaticosMovil(p_id_usuario, NULL, v_sin_vi);
            IF v_sin_vi = 0 THEN
                SELECT COUNT(*) INTO v_gastos
                FROM   gasto_viatico g
                JOIN   tmp_vi_alc a ON a.id_os = g.id_os
                WHERE  g.eliminado_en IS NULL AND g.tipo = 'gasto_solicitado' AND g.estado = 'pendiente';
            END IF;
            DROP TEMPORARY TABLE IF EXISTS tmp_vi_alc;
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
                    OR (v_aut_area IS NOT NULL AND (a.area_destino IS NULL OR a.area_destino = v_aut_area))))
           + (SELECT COUNT(*)
              FROM   llegada_forzada_os lf
              WHERE  lf.eliminado_en IS NULL AND lf.estado = 'pendiente'
                AND  (v_aut_general = 1
                      OR (v_aut_area IS NOT NULL AND (lf.area_destino IS NULL OR lf.area_destino = v_aut_area))))
           -- Evidencias forzadas y ensayos con error sin revisar (migración 113), por el área de la RQ
           + (SELECT COUNT(*)
              FROM   evidencia_fotografica f
              JOIN   orden_servicio os ON os.id_os = f.id_os AND os.eliminado_en IS NULL AND os.estado <> 'anulada'
              LEFT JOIN expediente_digital ed ON ed.id_expediente = os.id_expediente
              LEFT JOIN requerimiento rq      ON rq.id_requerimiento = ed.id_requerimiento
              LEFT JOIN area_servicio_rq asr  ON asr.id_area_rq = rq.id_area
              WHERE  f.eliminado_en IS NULL AND f.override_aprobado = 1 AND f.vigente = 1 AND f.revision_jefe IS NULL
                AND  (v_aut_general = 1 OR (v_aut_area IS NOT NULL AND (asr.area_usuario IS NULL OR asr.area_usuario = v_aut_area))))
           + (SELECT COUNT(*)
              FROM   informe_tecnico it
              JOIN   orden_servicio os ON os.id_os = it.id_os AND os.eliminado_en IS NULL AND os.estado <> 'anulada'
              LEFT JOIN expediente_digital ed ON ed.id_expediente = os.id_expediente
              LEFT JOIN requerimiento rq      ON rq.id_requerimiento = ed.id_requerimiento
              LEFT JOIN area_servicio_rq asr  ON asr.id_area_rq = rq.id_area
              WHERE  it.eliminado_en IS NULL AND it.error_critico_motivo IS NOT NULL AND it.error_critico_revision IS NULL
                AND  (v_aut_general = 1 OR (v_aut_area IS NOT NULL AND (asr.area_usuario IS NULL OR asr.area_usuario = v_aut_area))))
           -- Gastos pendientes: solo para quien los revisa (el mismo contador de la tarjeta Viáticos y Gastos)
           + IFNULL(v_gastos, 0)                                            AS aprobaciones_pendientes,
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

-- ============================================================
-- SP_ObtenerNotificacionesMovil  (App Mobile HU-02 / HU-04 — pestaña Notificaciones)
-- Avisos del usuario que inició sesión (el id sale del token): las 60 más recientes, no eliminadas.
-- Son las mismas de la campana de la intranet (tabla notificacion), con el tipo ya clasificado para el ícono y la acción de la app.
--   tipo (según el título que dejan los demás SP):
--     autorizacion_aprobada   "Autorización de salida aprobada" (y el texto anterior "Visto bueno de salida: …")
--     autorizacion_rechazada  "Autorización de salida rechazada" (y "Salida no autorizada: …")
--     autorizacion_solicitud  "Autorización de salida · …" (le llega al jefe cuando un técnico pide su visto bueno)
--     solicitud_enviada       "Solicitud de autorización enviada" (confirmación para el técnico)
--     gasto_aprobado | gasto_observado | gasto_rechazado   gastos revisados por el Jefe de Operaciones
--     viatico_asignado        "Viático asignado: S/ …" (HU-35: el jefe le asignó viáticos; abre Viáticos y Gastos)
--     servicio                "Nueva programación: …" (se asignó un servicio)
--     demora                  "Demora en ruta" (le llega a Operaciones)
--     ensayo_critico          "Ensayo con error crítico" (HU-10: le llega al encargado del área; el técnico pidió apoyo o aceptó guardar con una lectura fuera del EMP)
--     evidencia_forzada       "Evidencia forzada" (HU-12: una foto rechazada por la IA que el técnico aceptó con un motivo)
--     correlativo_solicitado  "Solicitud de correlativo enviada" (HU-14: confirmación al técnico) · correlativo_solicitud "Solicitud de correlativo" (HU-34: le llega al Jefe de
--                             Metrología) · correlativo_asignado "Correlativo asignado" (HU-14: Metrología asignó el correlativo; abre "Mis tickets"). entidad_tipo = ticket_metrologia.
--     equipo_nuevo            "Equipo nuevo por aprobar" (HU-07: equipo NEW registrado en campo)
--     servicio_detenido       "Servicio detenido: …" (Control de Campo)
--     informe_observado       "Informe observado: …" (HU-33: el jefe pidió una corrección; le llega al técnico, entidad_tipo = informe_tecnico) · informe_revisado "Informe revisado: …" (HU-59)
--     alerta_campo            otra alerta operativa del Control de Campo (tipo_notificacion = alerta_operativa)
--     general                 cualquier otro
--   critica / prioridad: la prioridad que ya clasifica el Centro de Notificaciones (HU-90, migración 102_centro_notificaciones: columna
--     notificacion.prioridad = critica | alta | normal). Es lo que filtra "Críticas" en la pestaña Notificaciones del jefe. No se repite la regla aquí.
--   Las archivadas en la intranet no se muestran.
--   pendientes_aprobados: solo en autorizacion_aprobada, los pendientes con los que el jefe autorizó la salida.
--   entidad_tipo / id_entidad: a qué abre la app ('orden_servicio' = el detalle del servicio).
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerNotificacionesMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerNotificacionesMovil(
    IN p_id_usuario BIGINT
)
proc: BEGIN
    IF NOT EXISTS (SELECT 1 FROM usuario WHERE id_usuario = p_id_usuario AND eliminado_en IS NULL) THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no encontrado.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT x.id_notificacion, x.tipo, x.titulo, x.cuerpo, x.entidad_tipo, x.id_entidad, x.leida, x.fecha_creacion,
           x.prioridad, IF(x.prioridad = 'critica', 1, 0) AS critica,
           CASE WHEN x.tipo = 'autorizacion_aprobada' AND x.entidad_tipo = 'orden_servicio'
                THEN (SELECT a.pendientes FROM autorizacion_salida_os a
                      WHERE  a.id_os = x.id_entidad AND a.eliminado_en IS NULL
                      ORDER BY a.id_autorizacion DESC LIMIT 1)
           END AS pendientes_aprobados
    FROM (
        SELECT n.id_notificacion,
               CASE WHEN n.titulo LIKE 'Autorización de salida aprobada%' OR n.titulo LIKE 'Visto bueno de salida%'     THEN 'autorizacion_aprobada'
                    WHEN n.titulo LIKE 'Autorización de salida rechazada%' OR n.titulo LIKE 'Salida no autorizada%'     THEN 'autorizacion_rechazada'
                    WHEN n.titulo LIKE 'Solicitud de autorización enviada%'                                             THEN 'solicitud_enviada'
                    WHEN n.titulo LIKE 'Solicitud de llegada forzada enviada%'                                          THEN 'solicitud_enviada'
                    WHEN n.titulo LIKE 'Llegada forzada aprobada%'                                                      THEN 'llegada_forzada_aprobada'
                    WHEN n.titulo LIKE 'Llegada forzada rechazada%'                                                     THEN 'llegada_forzada_rechazada'
                    WHEN n.titulo LIKE 'Llegada forzada%'                                                               THEN 'llegada_forzada_solicitud'
                    WHEN n.titulo LIKE 'Solicitud de correlativo enviada%'                                              THEN 'correlativo_solicitado'
                    WHEN n.titulo LIKE 'Solicitud de correlativo%'                                                      THEN 'correlativo_solicitud'
                    WHEN n.titulo LIKE 'Correlativo asignado%'                                                          THEN 'correlativo_asignado'
                    WHEN n.titulo LIKE 'Autorización de salida%'                                                        THEN 'autorizacion_solicitud'
                    WHEN n.titulo LIKE 'Gasto aprobado%'                                                                THEN 'gasto_aprobado'
                    WHEN n.titulo LIKE 'Gasto observado%'                                                               THEN 'gasto_observado'
                    WHEN n.titulo LIKE 'Gasto rechazado%'                                                               THEN 'gasto_rechazado'
                    WHEN n.titulo LIKE 'Viático asignado%'                                                              THEN 'viatico_asignado'
                    WHEN n.titulo LIKE 'Nueva programación%' OR n.titulo LIKE 'Nuevo servicio%'                         THEN 'servicio'
                    WHEN n.titulo LIKE 'Demora en ruta%'                                                                THEN 'demora'
                    WHEN n.titulo LIKE 'Ensayo con error cr%'                                                           THEN 'ensayo_critico'
                    WHEN n.titulo LIKE 'Evidencia forzada%'                                                             THEN 'evidencia_forzada'
                    WHEN n.titulo LIKE 'Equipo nuevo por aprobar%'                                                      THEN 'equipo_nuevo'
                    WHEN n.titulo LIKE 'Servicio detenido:%'                                                            THEN 'servicio_detenido'
                    WHEN n.titulo LIKE 'Informe observado%'                                                             THEN 'informe_observado'
                    WHEN n.titulo LIKE 'Informe revisado%'                                                              THEN 'informe_revisado'
                    WHEN n.tipo_notificacion = 'alerta_operativa'                                                       THEN 'alerta_campo'
                    ELSE 'general' END AS tipo,
               n.titulo,
               n.cuerpo,
               n.entidad_tipo,
               n.id_entidad,
               n.leido                AS leida,
               n.fecha_creacion,
               n.prioridad
        FROM   notificacion n
        WHERE  n.id_usuario_destino = p_id_usuario AND n.eliminado_en IS NULL AND n.archivado = 0
        ORDER BY n.fecha_creacion DESC, n.id_notificacion DESC
        LIMIT 60
    ) x
    ORDER BY x.fecha_creacion DESC, x.id_notificacion DESC;
END$$

DELIMITER ;

-- ============================================================
-- SP_RendirGastoMovil  (App Mobile HU-27 — rendir un gasto o corregir uno observado · escritura)
-- Una sola ruta para los dos orígenes del dinero (los dos van a gasto_viatico tipo 'gasto_solicitado', los revisa el Jefe de Operaciones y entran al
-- cierre de la rendición):
--   origen 'viatico'   sale del adelanto: trae p_reparto [{ "idViaticoLinea": n, "monto": 0.00 }] (líneas viatico_asignado del MISMO técnico y de ESA OS,
--                      sin repetirse, y la suma exacta = p_monto). El concepto del gasto es el de la línea con más monto. Si una línea se pasa de lo que le
--                      queda NO se rechaza: se guarda y se devuelve una advertencia (lo aprobado de más se le paga al técnico al cerrar la rendición).
--   origen 'reembolso' lo pagó el técnico: trae p_id_concepto (CONCEPTO_GASTO) y, si es "Otro" (String3 = 'OTRO'), p_concepto_texto (2 a 100 caracteres).
--   p_id_gasto = 0: gasto nuevo. p_id_cliente_app (GUID de la app): si ya existe un gasto del técnico con ese GUID, se devuelve ese (reintento de la
--     sincronización) sin crear otro: duplicado = 1 (la API borra las fotos que acaba de guardar).
--   p_id_gasto > 0: corregir un gasto OBSERVADO del técnico (vuelve a 'pendiente'). p_fotos_conservar = [orden…] de las fotos que se quedan; las demás se
--     retiran. Las nuevas se agregan al final.
--   p_fotos_nuevas: ["ruta", …] ya guardadas por la API (JPEG validados por contenido, máx. 5 MB, nombre generado por el servidor). Total ≤ 5 fotos.
--   Sin ninguna foto, p_motivo_sin_foto es obligatorio (3 a 300 caracteres).
--   p_monto_ia / p_coincide_ia: lo que leyó la IA en la primera foto nueva (NULL = sin lectura). Al corregir sin fotos nuevas se conserva la lectura anterior.
-- Reglas: monto > 0 y hasta GASTO_MONTO_MAXIMO (5 000 por defecto); fecha del gasto no futura; el técnico está en la programación activa de la OS, que debe
--   estar confirmada y con la rendición abierta. Notifica a quienes revisan gastos (prog_aprobar_reprogramacion) y deja auditoría. Requiere la migración 114.
-- Resultados: 1 mensaje · 2 gasto (id_gasto, codigo, estado, duplicado) · 3 advertencias (0 o más filas).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_RendirGastoMovil;

DELIMITER $$

CREATE PROCEDURE SP_RendirGastoMovil(
    IN p_id_usuario       BIGINT,
    IN p_id_gasto         BIGINT,
    IN p_id_cliente_app   VARCHAR(36)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_origen           VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_os            BIGINT,
    IN p_id_concepto      INT,
    IN p_concepto_texto   VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_monto            DECIMAL(12,2),
    IN p_fecha_gasto      DATE,
    IN p_descripcion      VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_reparto          JSON,
    IN p_motivo_sin_foto  VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_fotos_nuevas     JSON,
    IN p_fotos_conservar  JSON,
    IN p_monto_ia         DECIMAL(12,2),
    IN p_coincide_ia      TINYINT
)
proc: BEGIN
    DECLARE v_hoy        DATE;
    DECLARE v_cap        DECIMAL(18,6) DEFAULT 5000;
    DECLARE v_origen     VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_os      BIGINT;
    DECLARE v_numero     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado_os  VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_principal  BIGINT;
    DECLARE v_prog       BIGINT;
    DECLARE v_codigo     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado_pg  VARCHAR(25)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_g_id       BIGINT;
    DECLARE v_g_estado   VARCHAR(15)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_g_usuario  BIGINT;
    DECLARE v_id_conc    INT;
    DECLARE v_conc_cod   VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_conc_nom   VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_texto      VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_desc       VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_motivo     VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_n_rep      INT DEFAULT 0;
    DECLARE v_suma       DECIMAL(14,2) DEFAULT 0;
    DECLARE v_n_nuevas   INT DEFAULT 0;
    DECLARE v_n_cons     INT DEFAULT 0;
    DECLARE v_n_cons_ok  INT DEFAULT 0;
    DECLARE v_max_orden  INT DEFAULT 0;
    DECLARE v_error      VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_es_nuevo   TINYINT DEFAULT 1;
    DECLARE v_url1       VARCHAR(500);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_rg_rep;
        DROP TEMPORARY TABLE IF EXISTS tmp_rg_fn;
        DROP TEMPORARY TABLE IF EXISTS tmp_rg_fc;
        DROP TEMPORARY TABLE IF EXISTS tmp_rg_adv;
        IF @err_code IN (1213, 1205) THEN
            SELECT 1 AS IdTipoMensaje, 'Otra persona está modificando este gasto en este momento. Inténtalo de nuevo.' AS Mensaje;
        ELSE
            SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
        END IF;
    END;

    SET v_hoy      = DATE(UTC_TIMESTAMP() - INTERVAL 5 HOUR);
    SET v_origen   = LOWER(TRIM(IFNULL(p_origen, '')));
    SET v_es_nuevo = IF(IFNULL(p_id_gasto, 0) > 0, 0, 1);
    SET v_desc     = NULLIF(TRIM(IFNULL(p_descripcion, '')), '');
    SET v_motivo   = NULLIF(TRIM(IFNULL(p_motivo_sin_foto, '')), '');
    SET v_texto    = NULLIF(TRIM(IFNULL(p_concepto_texto, '')), '');
    CALL SP_LeerParametroProgramacion('GASTO_MONTO_MAXIMO', 5000, v_cap);

    IF NOT EXISTS (SELECT 1 FROM usuario WHERE id_usuario = p_id_usuario AND eliminado_en IS NULL AND estado = 'activo') THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no encontrado.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- ── Reintento de la sincronización: el mismo GUID devuelve el gasto ya creado ─────────────
    IF v_es_nuevo = 1 AND NULLIF(TRIM(IFNULL(p_id_cliente_app, '')), '') IS NOT NULL THEN
        SELECT MAX(id_gasto) INTO v_g_id
        FROM gasto_viatico
        WHERE id_usuario = p_id_usuario AND id_cliente_app = TRIM(p_id_cliente_app) AND tipo = 'gasto_solicitado' AND eliminado_en IS NULL;
        IF v_g_id IS NOT NULL THEN
            SELECT 2 AS IdTipoMensaje, 'El gasto ya estaba registrado.' AS Mensaje;
            SELECT id_gasto, CONCAT('GS-', LPAD(id_gasto, 6, '0')) AS codigo, estado, 1 AS duplicado FROM gasto_viatico WHERE id_gasto = v_g_id;
            SELECT CAST(NULL AS CHAR(300)) AS advertencia FROM DUAL WHERE 1 = 0;
            LEAVE proc;
        END IF;
    END IF;

    -- ── Formas ────────────────────────────────────────────────────────────────────────────
    IF v_origen NOT IN ('viatico', 'reembolso') THEN
        SET v_error = 'El origen del gasto debe ser viatico o reembolso.';
    ELSEIF p_monto IS NULL OR p_monto <= 0 OR p_monto > v_cap THEN
        SET v_error = CONCAT('El monto debe ser mayor a 0 y de hasta S/ ', FORMAT(v_cap, 2), '.');
    ELSEIF p_fecha_gasto IS NULL OR p_fecha_gasto > v_hoy OR p_fecha_gasto < v_hoy - INTERVAL 90 DAY THEN
        SET v_error = 'Indica la fecha del gasto (no futura y de los últimos 90 días).';
    ELSEIF v_desc IS NOT NULL AND v_desc REGEXP '[[:cntrl:]]' THEN
        SET v_error = 'La descripción tiene caracteres no permitidos.';
    ELSEIF p_reparto IS NOT NULL AND (NOT JSON_VALID(p_reparto) OR JSON_TYPE(p_reparto) <> 'ARRAY') THEN
        SET v_error = 'El reparto debe enviarse como una lista.';
    ELSEIF p_fotos_nuevas IS NOT NULL AND (NOT JSON_VALID(p_fotos_nuevas) OR JSON_TYPE(p_fotos_nuevas) <> 'ARRAY') THEN
        SET v_error = 'Las fotos no tienen un formato válido.';
    ELSEIF p_fotos_conservar IS NOT NULL AND (NOT JSON_VALID(p_fotos_conservar) OR JSON_TYPE(p_fotos_conservar) <> 'ARRAY') THEN
        SET v_error = 'Las fotos a conservar deben enviarse como una lista.';
    END IF;
    IF v_error IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, v_error AS Mensaje;
        LEAVE proc;
    END IF;

    -- ── Gasto a corregir (solo uno observado del propio técnico) ───────────────────────────
    IF v_es_nuevo = 0 THEN
        SELECT id_gasto, estado, id_usuario, id_os INTO v_g_id, v_g_estado, v_g_usuario, v_id_os
        FROM gasto_viatico WHERE id_gasto = p_id_gasto AND tipo = 'gasto_solicitado' AND eliminado_en IS NULL;
        IF v_g_id IS NULL OR v_g_usuario <> p_id_usuario THEN
            SELECT 1 AS IdTipoMensaje, 'El gasto no existe.' AS Mensaje;
            LEAVE proc;
        END IF;
        IF v_g_estado <> 'observado' THEN
            SELECT 1 AS IdTipoMensaje, 'Solo se puede corregir un gasto observado por el Jefe de Operaciones.' AS Mensaje;
            LEAVE proc;
        END IF;
        IF IFNULL(p_id_os, 0) > 0 AND p_id_os <> v_id_os THEN
            SELECT 1 AS IdTipoMensaje, 'El gasto no pertenece a ese servicio.' AS Mensaje;
            LEAVE proc;
        END IF;
    ELSE
        SET v_id_os = p_id_os;
    END IF;
    IF IFNULL(v_id_os, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Indica el servicio del gasto.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- ── Entradas a tablas temporales ──────────────────────────────────────────────────────
    DROP TEMPORARY TABLE IF EXISTS tmp_rg_rep;
    DROP TEMPORARY TABLE IF EXISTS tmp_rg_fn;
    DROP TEMPORARY TABLE IF EXISTS tmp_rg_fc;
    DROP TEMPORARY TABLE IF EXISTS tmp_rg_adv;
    CREATE TEMPORARY TABLE tmp_rg_rep (n INT NOT NULL, id_linea BIGINT NULL, monto DECIMAL(14,2) NULL, PRIMARY KEY (n));
    CREATE TEMPORARY TABLE tmp_rg_fn (n INT NOT NULL, ruta VARCHAR(500) NULL, PRIMARY KEY (n));
    CREATE TEMPORARY TABLE tmp_rg_fc (orden INT NOT NULL, PRIMARY KEY (orden));
    CREATE TEMPORARY TABLE tmp_rg_adv (n INT NOT NULL AUTO_INCREMENT, advertencia VARCHAR(300) NOT NULL, PRIMARY KEY (n))
        DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;

    IF v_origen = 'viatico' AND p_reparto IS NOT NULL THEN
        INSERT INTO tmp_rg_rep (n, id_linea, monto)
        SELECT j.n, j.id_linea, j.monto
        FROM JSON_TABLE(p_reparto, '$[*]' COLUMNS (
                n FOR ORDINALITY,
                id_linea BIGINT        PATH '$.idViaticoLinea' NULL ON EMPTY NULL ON ERROR,
                monto    DECIMAL(14,2) PATH '$.monto'          NULL ON EMPTY NULL ON ERROR)) j;
    END IF;
    IF p_fotos_nuevas IS NOT NULL THEN
        INSERT INTO tmp_rg_fn (n, ruta)
        SELECT j.n, NULLIF(TRIM(j.ruta), '')
        FROM JSON_TABLE(p_fotos_nuevas, '$[*]' COLUMNS (n FOR ORDINALITY, ruta VARCHAR(500) PATH '$' NULL ON EMPTY NULL ON ERROR)) j;
    END IF;
    IF v_es_nuevo = 0 AND p_fotos_conservar IS NOT NULL THEN
        INSERT IGNORE INTO tmp_rg_fc (orden)
        SELECT j.orden FROM JSON_TABLE(p_fotos_conservar, '$[*]' COLUMNS (orden INT PATH '$' NULL ON EMPTY NULL ON ERROR)) j
        WHERE j.orden IS NOT NULL;
    END IF;
    SELECT COUNT(*) INTO v_n_rep FROM tmp_rg_rep;
    SELECT IFNULL(SUM(monto), 0) INTO v_suma FROM tmp_rg_rep;
    SELECT COUNT(*) INTO v_n_nuevas FROM tmp_rg_fn;
    SELECT COUNT(*) INTO v_n_cons FROM tmp_rg_fc;
    IF v_es_nuevo = 0 THEN
        SELECT COUNT(*) INTO v_n_cons_ok FROM gasto_viatico_foto f
        WHERE f.id_gasto = v_g_id AND f.eliminado_en IS NULL AND f.orden IN (SELECT orden FROM tmp_rg_fc);
    END IF;

    -- ── Fotos y motivo ────────────────────────────────────────────────────────────────────
    IF EXISTS (SELECT 1 FROM tmp_rg_fn WHERE ruta IS NULL OR ruta LIKE '%..%') THEN
        SET v_error = 'Una de las fotos no es válida.';
    ELSEIF v_n_cons_ok <> v_n_cons THEN
        SET v_error = 'Una de las fotos a conservar no existe en el gasto.';
    ELSEIF v_n_nuevas + v_n_cons > 5 THEN
        SET v_error = 'Un gasto admite hasta 5 fotos.';
    ELSEIF v_n_nuevas + v_n_cons = 0 AND (v_motivo IS NULL OR CHAR_LENGTH(v_motivo) < 3) THEN
        SET v_error = 'Sin foto del comprobante, indica el motivo (mínimo 3 caracteres).';
    ELSEIF v_motivo IS NOT NULL AND v_motivo REGEXP '[[:cntrl:]]' THEN
        SET v_error = 'El motivo tiene caracteres no permitidos.';
    END IF;

    -- ── Según el origen ───────────────────────────────────────────────────────────────────
    IF v_error IS NULL AND v_origen = 'reembolso' THEN
        SELECT MAX(Num1), MAX(String3), MAX(String1) INTO v_id_conc, v_conc_cod, v_conc_nom
        FROM tabla_maestra WHERE IdMaestro = 25 AND IdEmpresa = 1 AND Num1 = p_id_concepto AND eliminado_en IS NULL;
        IF v_id_conc IS NULL THEN
            SET v_error = 'Elige un concepto del catálogo.';
        ELSEIF v_conc_cod = 'OTRO' AND (v_texto IS NULL OR CHAR_LENGTH(v_texto) < 2 OR v_texto REGEXP '[[:cntrl:]]') THEN
            SET v_error = 'Escribe el concepto del gasto (2 a 100 caracteres).';
        ELSEIF v_n_rep > 0 THEN
            SET v_error = 'Un reembolso no lleva reparto entre viáticos.';
        END IF;
        IF IFNULL(v_conc_cod, '') <> 'OTRO' THEN SET v_texto = NULL; END IF;
    ELSEIF v_error IS NULL THEN
        SET v_texto = NULL;
        IF v_n_rep = 0 THEN
            SET v_error = 'Indica de qué viáticos sale el gasto.';
        ELSEIF v_n_rep > 12 THEN
            SET v_error = 'El reparto admite hasta 12 líneas.';
        ELSEIF EXISTS (SELECT 1 FROM tmp_rg_rep WHERE id_linea IS NULL OR id_linea <= 0 OR monto IS NULL OR monto <= 0) THEN
            SET v_error = 'Cada línea del reparto debe tener el viático y un monto mayor a 0.';
        ELSEIF EXISTS (SELECT 1 FROM tmp_rg_rep GROUP BY id_linea HAVING COUNT(*) > 1) THEN
            SET v_error = 'Un viático aparece dos veces en el reparto.';
        ELSEIF v_suma <> p_monto THEN
            SET v_error = CONCAT('La suma del reparto (S/ ', FORMAT(v_suma, 2), ') debe ser igual al monto del gasto (S/ ', FORMAT(p_monto, 2), ').');
        END IF;
    END IF;
    IF v_error IS NOT NULL THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_rg_rep;
        DROP TEMPORARY TABLE IF EXISTS tmp_rg_fn;
        DROP TEMPORARY TABLE IF EXISTS tmp_rg_fc;
        DROP TEMPORARY TABLE IF EXISTS tmp_rg_adv;
        SELECT 1 AS IdTipoMensaje, v_error AS Mensaje;
        LEAVE proc;
    END IF;

    START TRANSACTION;

    -- ── OS, programación y técnico ────────────────────────────────────────────────────────
    SELECT numero, estado, id_tecnico_principal INTO v_numero, v_estado_os, v_principal
    FROM orden_servicio WHERE id_os = v_id_os AND eliminado_en IS NULL FOR UPDATE;
    SELECT MAX(id_programacion) INTO v_prog FROM programacion WHERE id_os = v_id_os AND estado <> 'cancelada' AND eliminado_en IS NULL;
    IF v_prog IS NOT NULL THEN
        SELECT codigo, estado INTO v_codigo, v_estado_pg FROM programacion WHERE id_programacion = v_prog FOR UPDATE;
    END IF;

    IF v_numero IS NULL OR v_estado_os = 'anulada' THEN
        SET v_error = 'El servicio no existe o fue anulado.';
    ELSEIF v_prog IS NULL OR v_estado_pg <> 'confirmada' THEN
        SET v_error = 'El servicio no tiene una programación confirmada: aún no admite gastos.';
    ELSEIF EXISTS (SELECT 1 FROM programacion_rendicion WHERE id_programacion = v_prog AND eliminado_en IS NULL) THEN
        SET v_error = 'La rendición de este servicio ya se cerró: no admite más gastos.';
    ELSEIF NOT (IFNULL(v_principal, 0) = p_id_usuario
                OR EXISTS (SELECT 1 FROM programacion_tecnico pt WHERE pt.id_programacion = v_prog AND pt.id_usuario = p_id_usuario AND pt.eliminado_en IS NULL)
                OR EXISTS (SELECT 1 FROM os_personal op WHERE op.id_os = v_id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL)) THEN
        SET v_error = 'No estás asignado a este servicio.';
    END IF;

    -- Reparto: líneas del adelanto del MISMO técnico y de ESTA OS
    IF v_error IS NULL AND v_origen = 'viatico' AND EXISTS (
        SELECT 1 FROM tmp_rg_rep t
        WHERE NOT EXISTS (SELECT 1 FROM gasto_viatico l
                          WHERE l.id_gasto = t.id_linea AND l.tipo = 'viatico_asignado' AND l.eliminado_en IS NULL AND l.id_usuario = p_id_usuario
                            AND (l.id_programacion = v_prog OR (l.id_programacion IS NULL AND l.id_os = v_id_os)))) THEN
        SET v_error = 'Una línea del reparto no es un viático tuyo de este servicio.';
    END IF;
    IF v_error IS NOT NULL THEN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_rg_rep;
        DROP TEMPORARY TABLE IF EXISTS tmp_rg_fn;
        DROP TEMPORARY TABLE IF EXISTS tmp_rg_fc;
        DROP TEMPORARY TABLE IF EXISTS tmp_rg_adv;
        SELECT 1 AS IdTipoMensaje, v_error AS Mensaje;
        LEAVE proc;
    END IF;

    IF v_origen = 'viatico' THEN
        -- Concepto del gasto: el de la línea con más monto
        SELECT l.id_concepto INTO v_id_conc
        FROM tmp_rg_rep t JOIN gasto_viatico l ON l.id_gasto = t.id_linea
        ORDER BY t.monto DESC, t.id_linea LIMIT 1;
        SELECT MAX(String1) INTO v_conc_nom FROM tabla_maestra WHERE IdMaestro = 25 AND IdEmpresa = 1 AND Num1 = v_id_conc;

        -- Advertencias: la línea se pasa de lo que le queda (otros gastos no rechazados ya repartidos en ella + los antiguos sin reparto del mismo concepto)
        INSERT INTO tmp_rg_adv (advertencia)
        SELECT LEFT(CONCAT(IFNULL(c.String1, 'Viático'), ': el reparto (S/ ', FORMAT(t.monto, 2), ') supera lo que queda (S/ ',
                           FORMAT(GREATEST(l.monto - IFNULL(r.usado, 0) - IFNULL(a.usado, 0), 0), 2),
                           '). Lo aprobado de más se paga al cerrar la rendición.'), 300)
        FROM tmp_rg_rep t
        JOIN gasto_viatico l ON l.id_gasto = t.id_linea
        LEFT JOIN tabla_maestra c ON c.IdMaestro = 25 AND c.IdEmpresa = 1 AND c.Num1 = l.id_concepto
        LEFT JOIN (SELECT rp.id_viatico_linea, SUM(rp.monto) AS usado
                   FROM gasto_viatico_reparto rp
                   JOIN gasto_viatico g ON g.id_gasto = rp.id_gasto AND g.eliminado_en IS NULL AND g.estado <> 'rechazado'
                   WHERE rp.eliminado_en IS NULL AND rp.id_gasto <> IFNULL(v_g_id, 0)
                   GROUP BY rp.id_viatico_linea) r ON r.id_viatico_linea = t.id_linea
        LEFT JOIN (SELECT g.id_usuario, g.id_concepto, SUM(g.monto) AS usado
                   FROM gasto_viatico g
                   WHERE g.tipo = 'gasto_solicitado' AND g.origen IS NULL AND g.estado <> 'rechazado' AND g.eliminado_en IS NULL
                     AND (g.id_programacion = v_prog OR (g.id_programacion IS NULL AND g.id_os = v_id_os))
                   GROUP BY g.id_usuario, g.id_concepto) a ON a.id_usuario = l.id_usuario AND a.id_concepto = l.id_concepto
        WHERE t.monto > l.monto - IFNULL(r.usado, 0) - IFNULL(a.usado, 0)
        ORDER BY t.n;
    END IF;

    SET v_motivo = IF(v_n_nuevas + v_n_cons > 0, NULL, v_motivo);

    -- ── Guardar ───────────────────────────────────────────────────────────────────────────
    IF v_es_nuevo = 1 THEN
        INSERT INTO gasto_viatico (id_os, id_programacion, id_usuario, id_concepto, id_moneda, monto, descripcion, tipo, estado,
                                   fecha_solicitud, fecha_gasto, origen, id_cliente_app, concepto_texto, motivo_sin_foto, monto_ia, coincide_ia, creado_por)
        VALUES (v_id_os, v_prog, p_id_usuario, v_id_conc, 1, p_monto, v_desc, 'gasto_solicitado', 'pendiente',
                v_hoy, p_fecha_gasto, v_origen, NULLIF(TRIM(IFNULL(p_id_cliente_app, '')), ''), v_texto, v_motivo,
                p_monto_ia, IF(p_coincide_ia IS NULL, NULL, IF(p_coincide_ia = 1, 1, 0)), p_id_usuario);
        SET v_g_id = LAST_INSERT_ID();
    ELSE
        UPDATE gasto_viatico
        SET id_programacion = IFNULL(id_programacion, v_prog), id_concepto = v_id_conc, monto = p_monto, descripcion = v_desc,
            estado = 'pendiente', fecha_gasto = p_fecha_gasto, origen = v_origen, concepto_texto = v_texto, motivo_sin_foto = v_motivo,
            monto_ia    = IF(v_n_nuevas > 0, p_monto_ia, monto_ia),
            coincide_ia = IF(v_n_nuevas > 0, IF(p_coincide_ia IS NULL, NULL, IF(p_coincide_ia = 1, 1, 0)), coincide_ia),
            modificado_por = p_id_usuario
        WHERE id_gasto = v_g_id;

        UPDATE gasto_viatico_reparto SET eliminado_en = NOW(), eliminado_por = p_id_usuario WHERE id_gasto = v_g_id AND eliminado_en IS NULL;
        UPDATE gasto_viatico_foto SET eliminado_en = NOW(), eliminado_por = p_id_usuario
        WHERE id_gasto = v_g_id AND eliminado_en IS NULL AND orden NOT IN (SELECT orden FROM tmp_rg_fc);
    END IF;

    INSERT INTO gasto_viatico_reparto (id_gasto, id_viatico_linea, monto, creado_por)
    SELECT v_g_id, t.id_linea, t.monto, p_id_usuario FROM tmp_rg_rep t WHERE v_origen = 'viatico' ORDER BY t.n;

    SELECT IFNULL(MAX(orden), 0) INTO v_max_orden FROM gasto_viatico_foto WHERE id_gasto = v_g_id AND eliminado_en IS NULL;
    INSERT INTO gasto_viatico_foto (id_gasto, url, orden, creado_por)
    SELECT v_g_id, f.ruta, v_max_orden + f.n, p_id_usuario FROM tmp_rg_fn f ORDER BY f.n;

    -- Compatibilidad: url_comprobante = la primera foto (la intranet de HU-45 y los SPs anteriores la leen)
    SELECT url INTO v_url1 FROM gasto_viatico_foto WHERE id_gasto = v_g_id AND eliminado_en IS NULL ORDER BY orden LIMIT 1;
    UPDATE gasto_viatico SET url_comprobante = v_url1 WHERE id_gasto = v_g_id;

    -- Aviso a quienes revisan gastos (Jefe de Operaciones). HU-35: solo a los que además ven este servicio (Área + Rol, SP_ArmarAprobadoresOsMovil): los demás no podrían revisarlo
    CALL SP_ArmarAprobadoresOsMovil(v_id_os);
    INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
    SELECT u.id_usuario, 5, LEFT(CONCAT(IF(v_es_nuevo = 1, 'Gasto por revisar: ', 'Gasto corregido: '), v_numero), 150),
           LEFT(CONCAT(v_codigo, ' · ', v_numero, ' · ', IFNULL(v_texto, IFNULL(v_conc_nom, 'Gasto')), ' S/ ', FORMAT(p_monto, 2),
                       IF(v_origen = 'reembolso', ' (reembolso)', ''), IF(v_n_nuevas + v_n_cons = 0, ' · sin foto', ''), '.'), 3000),
           'programacion', v_prog, NOW(), p_id_usuario
    FROM usuario u
    JOIN tmp_aprobadores ap ON ap.id_usuario = u.id_usuario
    WHERE u.eliminado_en IS NULL AND u.estado = 'activo' AND u.id_usuario <> p_id_usuario
      AND FN_PermisoAccion(u.id_usuario, 'prog_aprobar_reprogramacion') = 1;
    DROP TEMPORARY TABLE IF EXISTS tmp_aprobadores;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('programacion', v_prog, IF(v_es_nuevo = 1, 'rendir_gasto', 'corregir_gasto'), IF(v_es_nuevo = 1, NULL, 'observado'), 'pendiente',
            LEFT(CONCAT('Gasto ', CONCAT('GS-', LPAD(v_g_id, 6, '0')), IF(v_es_nuevo = 1, ' rendido', ' corregido'), ' desde la app: ',
                        IFNULL(v_texto, IFNULL(v_conc_nom, 'Gasto')), ' S/ ', FORMAT(p_monto, 2), ' (', v_origen, ').'), 900),
            p_id_usuario, NOW(),
            JSON_OBJECT('idGasto', v_g_id, 'origen', v_origen, 'monto', p_monto, 'fotos', v_n_nuevas + v_n_cons, 'reparto', v_n_rep,
                        'montoIa', p_monto_ia, 'advertencias', (SELECT COUNT(*) FROM tmp_rg_adv)));

    COMMIT;

    SELECT 2 AS IdTipoMensaje,
           IF(v_es_nuevo = 1, 'Gasto registrado: queda pendiente de la revisión del Jefe de Operaciones.',
                              'Gasto corregido: vuelve a la revisión del Jefe de Operaciones.') AS Mensaje;
    SELECT v_g_id AS id_gasto, CONCAT('GS-', LPAD(v_g_id, 6, '0')) AS codigo, 'pendiente' AS estado, 0 AS duplicado;
    SELECT advertencia FROM tmp_rg_adv ORDER BY n;

    DROP TEMPORARY TABLE IF EXISTS tmp_rg_rep;
    DROP TEMPORARY TABLE IF EXISTS tmp_rg_fn;
    DROP TEMPORARY TABLE IF EXISTS tmp_rg_fc;
    DROP TEMPORARY TABLE IF EXISTS tmp_rg_adv;
END$$

DELIMITER ;

SELECT 'Procedimientos HU-35 (deben ser 10)' AS verificacion, COUNT(*) AS valor FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = DATABASE() AND ROUTINE_NAME IN ('SP_ArmarAlcanceViaticosMovil','SP_ObtenerViaticosEquipoMovil','SP_ObtenerViaticoServicioEquipoMovil','SP_GuardarViaticosProgramacion','SP_AsignarViaticoEquipoMovil','SP_RevisarGastoMovil','SP_ObtenerAprobacionDetalleMovil','SP_ObtenerMenuJefaturaMovil','SP_ObtenerNotificacionesMovil','SP_RendirGastoMovil')
UNION ALL
SELECT 'Depósito desde la app en SP_GuardarViaticosProgramacion (debe ser 1)', COUNT(*) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = DATABASE() AND ROUTINE_NAME = 'SP_GuardarViaticosProgramacion' AND ROUTINE_DEFINITION LIKE '%tw_vi_deposita_jefe%'
UNION ALL
SELECT 'Apoyos de áreas y roles (deben ser 2)', COUNT(*) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = DATABASE() AND ROUTINE_NAME IN ('SP_ResolverAprobadorMovil','SP_ArmarAprobadoresOsMovil');
