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
