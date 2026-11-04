-- HU-35 — Lee un parámetro de PARAMETRO_PROGRAMACION (migración 85). Ayuda interna: NO devuelve resultados.
-- Si el parámetro no existe o está dado de baja, devuelve el valor por defecto que recibe (los SPs siguen funcionando
-- aunque la migración 85 no se haya ejecutado). No es una función: crearlas exige el privilegio SUPER.
DROP PROCEDURE IF EXISTS SP_LeerParametroProgramacion;

DELIMITER $$

CREATE PROCEDURE SP_LeerParametroProgramacion(
    IN  p_codigo  VARCHAR(60) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN  p_defecto DECIMAL(18,6),
    OUT p_valor   DECIMAL(18,6)
)
BEGIN
    -- Subconsulta escalar: siempre devuelve una fila (no dispara NOT FOUND en el SP que llama)
    SET p_valor = IFNULL((SELECT t.Num2
                          FROM tabla_maestra t
                          WHERE t.Descripcion = 'PARAMETRO_PROGRAMACION' AND t.IdEmpresa = 1
                            AND t.String2 = p_codigo AND t.eliminado_en IS NULL
                          ORDER BY t.IdTablaMaestra DESC
                          LIMIT 1), p_defecto);
END$$

DELIMITER ;
