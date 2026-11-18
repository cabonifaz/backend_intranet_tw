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
