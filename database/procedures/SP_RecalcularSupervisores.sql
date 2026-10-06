-- Supervisor automático (reunión 02-oct)
-- El supervisor directo de cada usuario activo es el usuario activo de su misma área
-- con el nivel superior más cercano entre los roles que pueden supervisar (Num3 = 1,
-- es decir supervisor y administrador): usuario y visor reportan al supervisor, o al
-- administrador si no hay supervisor, y el supervisor reporta al administrador.
-- Ante varios candidatos del mismo nivel se toma el más antiguo.
-- No devuelve resultados. Lo llaman SP_GuardarUsuario y SP_CambiarEstadoUsuario.
DROP PROCEDURE IF EXISTS SP_RecalcularSupervisores;

DELIMITER $$

CREATE PROCEDURE SP_RecalcularSupervisores()
BEGIN
    UPDATE usuario u
    LEFT JOIN (
        SELECT DISTINCT
               a.id_usuario,
               (SELECT c.id_usuario
                FROM (SELECT u2.id_usuario, u2.area, IFNULL(t2.Num1, 99) AS nivel
                      FROM usuario u2
                      JOIN tabla_maestra t2
                        ON t2.IdMaestro = 68 AND t2.IdEmpresa = 1 AND t2.String2 = u2.rol_sistema
                       AND t2.Num3 = 1
                      WHERE u2.eliminado_en IS NULL AND u2.estado = 'activo'
                        AND u2.area IS NOT NULL AND u2.area <> '') c
                WHERE c.area = a.area AND c.nivel < a.nivel AND c.id_usuario <> a.id_usuario
                ORDER BY c.nivel DESC, c.id_usuario ASC
                LIMIT 1) AS id_supervisor
        FROM (SELECT u1.id_usuario, u1.area, IFNULL(t1.Num1, 99) AS nivel
              FROM usuario u1
              LEFT JOIN tabla_maestra t1
                     ON t1.IdMaestro = 68 AND t1.IdEmpresa = 1 AND t1.String2 = u1.rol_sistema
              WHERE u1.eliminado_en IS NULL AND u1.estado = 'activo'
                AND u1.area IS NOT NULL AND u1.area <> '') a
    ) s ON s.id_usuario = u.id_usuario
    SET u.id_supervisor = s.id_supervisor,
        u.modificado_en = u.modificado_en
    WHERE u.eliminado_en IS NULL
      AND NOT (u.id_supervisor <=> s.id_supervisor);
END$$

DELIMITER ;
