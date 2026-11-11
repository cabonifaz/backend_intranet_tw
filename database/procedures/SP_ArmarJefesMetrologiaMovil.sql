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
              IF(u.rol_sistema IN ('supervisor', 'administrador') AND IFNULL(u.area, '') <> '', u.area, NULL)) = 'metrologia';
END$$

DELIMITER ;
