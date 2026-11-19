-- Perfil y alcance por ÁREA y ROL: Servicio Técnico/Metrología (Administrador/Supervisor = Jefatura, Usuario/Visor = campo; Administrador ve todo, Supervisor solo su área); las demás áreas, cualquier rol = Jefatura y ven todo. 3 SPs + verificación final. Ejecutar completo en DBeaver (Alt+X, "No" al aviso). Idempotente.

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
END$$

DELIMITER ;

-- ============================================================
-- SP_ArmarAlcanceJefaturaMovil  (App Mobile HU-28 / HU-29 / HU-30 — apoyo, NO es un endpoint)
-- Arma, UNA sola vez, los servicios (OS) que el jefe puede ver, en la tabla temporal `tmp_jf_alc` (id_os). Quien la llame debe terminar con
-- DROP TEMPORARY TABLE IF EXISTS tmp_jf_alc. Solo lectura.
--   · Servicio Técnico y Metrología: solo los servicios cuya RQ es de su área (orden_servicio → expediente_digital → requerimiento.id_area
--     → area_servicio_rq.area_usuario = área del jefe).
--     Si el jefe es ADMINISTRADOR (SP_ResolverJefaturaMovil deja @tw_jf_alcance_total = 1), ve TODOS los servicios, como las demás áreas.
--     (OM = servicios cuya RQ es de Metrología: se filtran igual por el área de la RQ.)
--   · Las demás áreas (Gerencia, Operaciones, Administración, TI, SSOMA, Calidad, Comercial) no tienen área en la RQ: ven TODOS los servicios.
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
            OR IFNULL(@tw_jf_alcance_total, 0) = 1
            OR EXISTS (SELECT 1
                       FROM   expediente_digital ed
                       JOIN   requerimiento      rq  ON rq.id_requerimiento = ed.id_requerimiento
                       JOIN   area_servicio_rq   asr ON asr.id_area_rq      = rq.id_area
                       WHERE  ed.id_expediente = os.id_expediente AND asr.area_usuario = p_area));
END$$

DELIMITER ;

-- ============================================================
-- SP_ArmarJefesMetrologiaMovil  (App Mobile HU-14 / HU-34 — apoyo, NO es un endpoint)
-- Deja en la tabla temporal `tmp_jm_jefes` (id_usuario) a quienes atienden los correlativos: los usuarios activos cuyo menú de Jefatura es del área de Metrología
-- (la MISMA regla de SP_ResolverJefaturaMovil: cargo "Jefe de …" con área Metrología, o supervisor / administrador con área Metrología). A ellos les llega
-- el aviso de una solicitud nueva. Quien la llame debe terminar con DROP TEMPORARY TABLE IF EXISTS tmp_jm_jefes. Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ArmarJefesMetrologiaMovil;

DELIMITER $$

CREATE PROCEDURE SP_ArmarJefesMetrologiaMovil()
BEGIN
    DROP TEMPORARY TABLE IF EXISTS tmp_jm_jefes;
    CREATE TEMPORARY TABLE tmp_jm_jefes (id_usuario BIGINT NOT NULL, PRIMARY KEY (id_usuario));

    INSERT INTO tmp_jm_jefes (id_usuario)
    SELECT u.id_usuario
    FROM   usuario u
    LEFT JOIN tabla_maestra c ON c.IdMaestro = 80 AND c.IdEmpresa = 1 AND c.String2 = u.cargo
    WHERE  u.eliminado_en IS NULL AND u.estado = 'activo'
      AND  IF(u.cargo LIKE 'jefe\_%',
              COALESCE(NULLIF(u.area, ''), NULLIF(c.String3, ''), SUBSTRING(u.cargo, 6)),
              IF(u.rol_sistema IN ('supervisor', 'administrador') AND IFNULL(u.area, '') <> '', u.area, NULL)) = 'metrologia'
      -- en Metrología manda el ROL: solo Administrador / Supervisor tienen Jefatura (Usuario / Visor hacen las OM), igual que SP_ResolverJefaturaMovil
      AND  u.rol_sistema IN ('supervisor', 'administrador');
END$$

DELIMITER ;

-- ============================================================
-- VERIFICACIÓN (solo lectura): ¿qué menú y qué servicios/técnicos ve cada usuario activo?
-- Llama al propio SP_ResolverJefaturaMovil (el que usa la app) para cada uno; crea y borra un procedimiento temporal, no deja nada.
--   menu_que_ve ......... JEFATURA de <área>  |  CAMPO (Servicio Técnico: OS; Metrología: OM)
--   alcance_servicios ... TODOS los servicios y técnicos  |  solo los de su área (la RQ del servicio es de su área)
--   Gerencia, Operaciones, Administración, TI, SSOMA, Calidad, Comercial ... TODOS
--   Servicio Técnico / Metrología + Administrador ......................... TODOS
--   Servicio Técnico / Metrología + Supervisor ............................ solo los de su área
-- ============================================================
DROP PROCEDURE IF EXISTS SP_TmpVerificarPerfilAreaRol;

DELIMITER $$

CREATE PROCEDURE SP_TmpVerificarPerfilAreaRol()
BEGIN
    DECLARE v_fin   INT DEFAULT 0;
    DECLARE v_id    BIGINT;
    DECLARE v_area  VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_sede  VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_aut   VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_gen   TINYINT;
    DECLARE cur CURSOR FOR
        SELECT id_usuario FROM usuario
        WHERE  eliminado_en IS NULL AND estado = 'activo' AND (IFNULL(area, '') <> '' OR cargo LIKE 'jefe\_%')
        ORDER BY area, rol_sistema, id_usuario;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_fin = 1;

    DROP TEMPORARY TABLE IF EXISTS tmp_verif_perfil;
    CREATE TEMPORARY TABLE tmp_verif_perfil (id_usuario BIGINT NOT NULL, area_jefatura VARCHAR(30) NULL, todos TINYINT NOT NULL DEFAULT 0, PRIMARY KEY (id_usuario));

    OPEN cur;
    leer: LOOP
        FETCH cur INTO v_id;
        IF v_fin = 1 THEN LEAVE leer; END IF;
        CALL SP_ResolverJefaturaMovil(v_id, v_area, v_sede, v_aut, v_gen);
        INSERT INTO tmp_verif_perfil (id_usuario, area_jefatura, todos)
        VALUES (v_id, v_area, IF(v_area IS NOT NULL AND (v_area NOT IN ('servicio_tecnico', 'metrologia') OR IFNULL(@tw_jf_alcance_total, 0) = 1), 1, 0));
    END LOOP;
    CLOSE cur;

    SELECT u.id_usuario,
           u.nombre_usuario                                         AS usuario,
           u.area,
           u.rol_sistema                                            AS rol,
           u.cargo,
           IF(t.area_jefatura IS NULL,
              CASE u.area WHEN 'metrologia' THEN 'CAMPO (hace las OM)' WHEN 'servicio_tecnico' THEN 'CAMPO (hace las OS)' ELSE 'CAMPO' END,
              CONCAT('JEFATURA de ', t.area_jefatura))              AS menu_que_ve,
           CASE WHEN t.area_jefatura IS NULL THEN '—'
                WHEN t.todos = 1             THEN 'TODOS los servicios y técnicos'
                ELSE CONCAT('solo los de ', t.area_jefatura) END    AS alcance_servicios
    FROM   tmp_verif_perfil t
    JOIN   usuario u ON u.id_usuario = t.id_usuario
    ORDER BY (t.area_jefatura IS NULL), u.area, u.rol_sistema, u.id_usuario;

    DROP TEMPORARY TABLE IF EXISTS tmp_verif_perfil;
END$$

DELIMITER ;

CALL SP_TmpVerificarPerfilAreaRol();
DROP PROCEDURE IF EXISTS SP_TmpVerificarPerfilAreaRol;
