-- Expediente digital de una propuesta (o NULL).
-- El expediente nace con el RQ (migración 71): se busca por el RQ de la propuesta.
-- Para expedientes antiguos sin RQ se usa la propuesta vinculada directamente.
-- Si hubiera más de uno, prefiere el que no está cerrado y luego el más reciente.
DROP FUNCTION IF EXISTS FN_ExpedienteDePropuesta;

DELIMITER $$

CREATE FUNCTION FN_ExpedienteDePropuesta(
    p_id_propuesta BIGINT
) RETURNS BIGINT
READS SQL DATA
BEGIN
    DECLARE v_id_exp BIGINT DEFAULT NULL;

    SELECT e.id_expediente INTO v_id_exp
    FROM expediente_digital e
    WHERE e.eliminado_en IS NULL
      AND (e.id_requerimiento = (SELECT p.id_requerimiento FROM propuesta_comercial p WHERE p.id_propuesta = p_id_propuesta)
           OR e.id_propuesta = p_id_propuesta)
    ORDER BY (e.estado <> 'cerrado') DESC, e.id_expediente DESC
    LIMIT 1;

    RETURN v_id_exp;
END$$

DELIMITER ;
