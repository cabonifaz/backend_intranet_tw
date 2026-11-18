-- Perfil por ÁREA y ROL (Servicio Técnico y Metrología): Administrador/Supervisor = Jefatura; Usuario/Visor = campo. 2 SPs + verificación final. Ejecutar completo en DBeaver (Alt+X, "No" al aviso). Idempotente.

-- ============================================================
-- SP_ResolverJefaturaMovil  (App Mobile HU-28 / HU-29 / HU-30 — apoyo, NO es un endpoint)
-- Resuelve UNA sola vez quién es el jefe y de qué área, para el menú de Jefatura y las pantallas del Panel de Campo / Seguimiento del servicio.
--   · cargo "Jefe de …" (CARGO_USUARIO jefe_*): su área sale de su ficha (usuario.area) o, si no la tiene, del catálogo del cargo (String3).
--   · rol SUPERVISOR / ADMINISTRADOR con un área definida: esa área.  Cualquier otro usuario → p_area = NULL (no tiene menú de Jefatura).
--   · EXCEPCIÓN (2026-11-18) — área Servicio Técnico o Metrología: manda el ROL. Administrador / Supervisor = Jefatura de esa área; Usuario / Visor =
--     p_area NULL (menú de campo: OS, u OM en Metrología), aunque el cargo sea "Jefe de …".
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

    SET p_area = NULL;
    SET p_sede = NULL;
    SET p_aut_area = NULL;
    SET p_aut_general = 0;
    SET v_rol = NULL;

    SELECT IF(u.cargo LIKE 'jefe\_%',
              COALESCE(NULLIF(u.area, ''), NULLIF(c.String3, ''), SUBSTRING(u.cargo, 6)),
              IF(u.rol_sistema IN ('supervisor', 'administrador') AND IFNULL(u.area, '') <> '', u.area, NULL)),
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
-- VERIFICACIÓN (solo lectura): ¿qué menú ve cada usuario activo de Servicio Técnico y Metrología?
-- Llama al propio SP_ResolverJefaturaMovil (el que usa la app) para cada uno; crea y borra un procedimiento temporal, no deja nada.
--   Administrador / Supervisor  → JEFATURA de su área
--   Usuario / Visor             → CAMPO (Servicio Técnico: hacen las OS; Metrología: hacen las OM), aunque el cargo diga "Jefe de …"
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
        WHERE  eliminado_en IS NULL AND estado = 'activo' AND area IN ('servicio_tecnico', 'metrologia')
        ORDER BY area, rol_sistema, id_usuario;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_fin = 1;

    DROP TEMPORARY TABLE IF EXISTS tmp_verif_perfil;
    CREATE TEMPORARY TABLE tmp_verif_perfil (id_usuario BIGINT NOT NULL, area_jefatura VARCHAR(30) NULL, PRIMARY KEY (id_usuario));

    OPEN cur;
    leer: LOOP
        FETCH cur INTO v_id;
        IF v_fin = 1 THEN LEAVE leer; END IF;
        CALL SP_ResolverJefaturaMovil(v_id, v_area, v_sede, v_aut, v_gen);
        INSERT INTO tmp_verif_perfil (id_usuario, area_jefatura) VALUES (v_id, v_area);
    END LOOP;
    CLOSE cur;

    SELECT u.id_usuario,
           u.nombre_usuario                                         AS usuario,
           u.area,
           u.rol_sistema                                            AS rol,
           u.cargo,
           IF(t.area_jefatura IS NULL,
              IF(u.area = 'metrologia', 'CAMPO (hace las OM)', 'CAMPO (hace las OS)'),
              CONCAT('JEFATURA de ', t.area_jefatura))              AS menu_que_ve
    FROM   tmp_verif_perfil t
    JOIN   usuario u ON u.id_usuario = t.id_usuario
    ORDER BY u.area, u.rol_sistema, u.id_usuario;

    DROP TEMPORARY TABLE IF EXISTS tmp_verif_perfil;
END$$

DELIMITER ;

CALL SP_TmpVerificarPerfilAreaRol();
DROP PROCEDURE IF EXISTS SP_TmpVerificarPerfilAreaRol;
