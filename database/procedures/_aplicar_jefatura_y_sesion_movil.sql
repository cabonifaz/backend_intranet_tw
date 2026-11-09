-- Aplicar en la base (solo procedimientos, sin datos). NO subir al repositorio.
-- Contiene 2 procedimientos: SP_ObtenerMenuJefaturaMovil (menú de Jefatura único, HU-28) y SP_VerificarSesionMovil (sesión única por cuenta, HU-01).
-- Después de ejecutarlo hay que REINICIAR la API (MySqlConnector guarda en caché los procedimientos).

-- ============================================================
-- 1) SP_ObtenerMenuJefaturaMovil  (App Mobile HU-28 — Menú de Jefatura único)
-- Lo reciben los jefes de área (cargo jefe_*: Servicio Técnico, Metrología, Operaciones…) y los usuarios con rol
-- SUPERVISOR / ADMINISTRADOR con un área definida. Servicio Técnico y Metrología se filtran por el área de la RQ de cada servicio;
-- las demás áreas ven todos los servicios. Solo lectura.
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
                    OR (v_aut_area IS NOT NULL AND (a.area_destino IS NULL OR a.area_destino = v_aut_area)))) AS aprobaciones_pendientes
    FROM   os_area;
END$$

DELIMITER ;

-- ============================================================
-- 2) SP_VerificarSesionMovil  (App Mobile HU-01 — sesión única por cuenta)
-- Se ejecuta en cada request con un JWT de la app. Si la sesión ya no sirve, responde IdTipoMensaje 1 con el motivo:
--   REEMPLAZADA_POR_OTRO_EQUIPO → "Tu sesión se cerró porque se inició sesión con tu usuario en otro equipo."
--   LIBERADA_POR_JEFE → "Tu jefe cerró tu sesión."; venció → "Tu sesión venció."; acceso desactivado; otro caso → "Tu sesión terminó."
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_VerificarSesionMovil;

DELIMITER //

CREATE PROCEDURE SP_VerificarSesionMovil(
    IN p_id_usuario   BIGINT,
    IN p_sesion_token VARCHAR(36) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
BEGIN
    DECLARE v_activo      TINYINT      DEFAULT NULL;
    DECLARE v_expira      DATETIME     DEFAULT NULL;
    DECLARE v_motivo      VARCHAR(60)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_usuario_ok  TINYINT      DEFAULT 0;

    IF EXISTS (
        SELECT 1
        FROM   sesion_usuario s
        JOIN   usuario u ON u.id_usuario = s.id_usuario
        WHERE  s.id_usuario       = p_id_usuario
          AND  s.token_jti        = p_sesion_token
          AND  s.id_canal_acceso  = 2
          AND  s.activo           = 1
          AND  s.eliminado_en     IS NULL
          AND  s.fecha_expiracion > NOW()
          AND  u.eliminado_en     IS NULL
          AND  u.estado           = 'activo'
          AND  u.nombre_usuario   IS NOT NULL
          AND  u.canal_acceso     IN ('movil', 'todos')
    ) THEN
        SELECT 2 AS IdTipoMensaje, 'Sesión válida.' AS Mensaje;
    ELSE
        -- Motivo por el que la sesión ya no sirve (el token pertenece a una sesión que existió)
        SELECT s.activo, s.fecha_expiracion, s.motivo_revocacion
        INTO   v_activo, v_expira, v_motivo
        FROM   sesion_usuario s
        WHERE  s.id_usuario      = p_id_usuario
          AND  s.token_jti       = p_sesion_token
          AND  s.id_canal_acceso = 2
        ORDER BY s.id_sesion DESC
        LIMIT 1;

        SELECT COUNT(*) INTO v_usuario_ok
        FROM   usuario u
        WHERE  u.id_usuario     = p_id_usuario
          AND  u.eliminado_en   IS NULL
          AND  u.estado         = 'activo'
          AND  u.nombre_usuario IS NOT NULL
          AND  u.canal_acceso   IN ('movil', 'todos');

        SELECT 1 AS IdTipoMensaje,
               CASE
                   WHEN v_usuario_ok = 0
                       THEN 'Tu acceso a la app ya no está habilitado. Consulta con tu jefe.'
                   WHEN v_activo = 0 AND v_motivo = 'REEMPLAZADA_POR_OTRO_EQUIPO'
                       THEN 'Tu sesión se cerró porque se inició sesión con tu usuario en otro equipo.'
                   WHEN v_activo = 0 AND v_motivo = 'LIBERADA_POR_JEFE'
                       THEN 'Tu jefe cerró tu sesión. Vuelve a iniciar sesión.'
                   WHEN v_activo = 1 AND v_expira <= NOW()
                       THEN 'Tu sesión venció. Vuelve a iniciar sesión.'
                   ELSE 'Tu sesión terminó. Vuelve a iniciar sesión.'
               END AS Mensaje;
    END IF;
END //

DELIMITER ;

-- ============================================================
-- COMPROBACIÓN (solo lectura, no modifica datos)
-- ============================================================

-- A) Los dos procedimientos deben aparecer con la fecha/hora de hoy
SELECT ROUTINE_NAME AS procedimiento, LAST_ALTERED AS actualizado
FROM   INFORMATION_SCHEMA.ROUTINES
WHERE  ROUTINE_SCHEMA = DATABASE()
  AND  ROUTINE_NAME IN ('SP_ObtenerMenuJefaturaMovil', 'SP_VerificarSesionMovil');

-- B) Usuarios que tendrán el menú de Jefatura (cargo "Jefe de …" o rol Supervisor/Administrador con área)
SELECT u.id_usuario, TRIM(CONCAT(u.nombre, ' ', u.apellido)) AS nombre, u.cargo, u.area, u.rol_sistema, u.nombre_usuario, u.canal_acceso, u.estado
FROM   usuario u
WHERE  u.eliminado_en IS NULL AND u.estado = 'activo'
  AND  (u.cargo LIKE 'jefe\_%' OR (u.rol_sistema IN ('supervisor', 'administrador') AND IFNULL(u.area, '') <> ''))
ORDER BY u.area, u.id_usuario;

-- C) Menú del Jefe de Servicio Técnico: debe dar area_codigo 'servicio_tecnico', la sede y los contadores de hoy
SET @jefe_st = (SELECT MIN(id_usuario) FROM usuario WHERE cargo = 'jefe_servicio_tecnico' AND eliminado_en IS NULL AND estado = 'activo');
CALL SP_ObtenerMenuJefaturaMovil(@jefe_st);

-- D) Un usuario común NO tiene menú de Jefatura: debe responder "Tu cargo no tiene el menú de Jefatura."
SET @comun = (SELECT MIN(id_usuario) FROM usuario WHERE cargo NOT LIKE 'jefe\_%' AND rol_sistema NOT IN ('supervisor', 'administrador', 'admin') AND eliminado_en IS NULL AND estado = 'activo');
CALL SP_ObtenerMenuJefaturaMovil(@comun);

-- E) Una sesión inexistente debe responder IdTipoMensaje 1 y "Tu sesión terminó. Vuelve a iniciar sesión."
CALL SP_VerificarSesionMovil(0, '00000000-0000-0000-0000-000000000000');

-- F) Últimas sesiones de la app y por qué se cerraron (REEMPLAZADA_POR_OTRO_EQUIPO = otro equipo ingresó con el mismo usuario)
SELECT id_usuario, nombre_dispositivo, activo, fecha_inicio, fecha_revocacion, motivo_revocacion
FROM   sesion_usuario
WHERE  id_canal_acceso = 2
ORDER BY id_sesion DESC
LIMIT 10;
