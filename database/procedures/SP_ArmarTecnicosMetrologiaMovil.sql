-- ============================================================
-- SP_ArmarTecnicosMetrologiaMovil  (App Mobile HU-34 — apoyo, NO es un endpoint)
-- Deja en la tabla temporal `tmp_tm_tec` (id_usuario, nombre) a los técnicos de Metrología que reciben la reserva diaria de correlativos: usuarios activos del
-- área Metrología sin jefaturas ni asistentes (la MISMA regla de técnico que el contador "Mi Equipo" del menú de Jefatura, SP_ObtenerMenuJefaturaMovil).
-- Quien la llame debe terminar con DROP TEMPORARY TABLE IF EXISTS tmp_tm_tec. Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ArmarTecnicosMetrologiaMovil;

DELIMITER $$

CREATE PROCEDURE SP_ArmarTecnicosMetrologiaMovil()
BEGIN
    DROP TEMPORARY TABLE IF EXISTS tmp_tm_tec;
    CREATE TEMPORARY TABLE tmp_tm_tec (
        id_usuario BIGINT NOT NULL,
        nombre     VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        PRIMARY KEY (id_usuario));

    INSERT INTO tmp_tm_tec (id_usuario, nombre)
    SELECT u.id_usuario, TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, '')))
    FROM   usuario u
    WHERE  u.eliminado_en IS NULL AND u.estado = 'activo' AND u.area = 'metrologia'
      AND  (u.cargo IS NULL OR (u.cargo NOT LIKE 'jefe\_%' AND u.cargo NOT LIKE 'asistente\_%'));
END$$

DELIMITER ;
