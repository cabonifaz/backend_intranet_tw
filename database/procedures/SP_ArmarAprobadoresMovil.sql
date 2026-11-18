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
