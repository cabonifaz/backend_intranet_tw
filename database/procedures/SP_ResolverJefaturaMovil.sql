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
