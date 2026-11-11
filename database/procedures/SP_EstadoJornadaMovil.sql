-- ============================================================
-- SP_EstadoJornadaMovil  (App Mobile HU-20 — apoyo, NO es un endpoint)
-- UNA sola regla del orden de la jornada: las marcaciones del día forman siempre un prefijo de
--   inicio_labores → inicio_refrigerio → fin_refrigerio → salida_planta → fin_labores
-- así que con la cantidad de marcaciones se sabe el estado y el único paso siguiente habilitado.
--   n = 0 sin_iniciar · 1 en_labores · 2 en_refrigerio · 3 en_labores (después del refrigerio) · 4 salio_planta · 5 finalizada
-- Solo lectura. (El Seguimiento Operativo usa esta misma tabla de estados en SP_ArmarSeguimientoOperativo.)
-- ============================================================
DROP PROCEDURE IF EXISTS SP_EstadoJornadaMovil;

DELIMITER $$

CREATE PROCEDURE SP_EstadoJornadaMovil(
    IN  p_id_usuario BIGINT,
    IN  p_fecha      DATE,
    OUT p_n          INT,
    OUT p_estado     VARCHAR(20),
    OUT p_siguiente  VARCHAR(20),
    OUT p_ultima_utc DATETIME
)
BEGIN
    SELECT COUNT(*), MAX(j.marcado_utc) INTO p_n, p_ultima_utc
    FROM   jornada_marcacion j
    WHERE  j.id_usuario = p_id_usuario AND j.fecha = p_fecha;

    SET p_estado = CASE p_n WHEN 0 THEN 'sin_iniciar' WHEN 1 THEN 'en_labores' WHEN 2 THEN 'en_refrigerio'
                            WHEN 3 THEN 'en_labores' WHEN 4 THEN 'salio_planta' ELSE 'finalizada' END;
    SET p_siguiente = CASE p_n WHEN 0 THEN 'inicio_labores' WHEN 1 THEN 'inicio_refrigerio' WHEN 2 THEN 'fin_refrigerio'
                               WHEN 3 THEN 'salida_planta' WHEN 4 THEN 'fin_labores' ELSE NULL END;
END$$

DELIMITER ;
