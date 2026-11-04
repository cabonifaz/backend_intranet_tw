-- HU-39 (Sprint 5) Borra las tablas temporales de la detección de conflictos sobrevenidos. ESTÁ BIEN llamarla aunque no existan.
DROP PROCEDURE IF EXISTS SP_LimpiarConflictosProgramacion;

DELIMITER $$

CREATE PROCEDURE SP_LimpiarConflictosProgramacion()
BEGIN
    DROP TEMPORARY TABLE IF EXISTS tmp_cf_asig;
    DROP TEMPORARY TABLE IF EXISTS tmp_cf_asig2;
    DROP TEMPORARY TABLE IF EXISTS tmp_cf_par;
    DROP TEMPORARY TABLE IF EXISTS tmp_cf_serv;
    DROP TEMPORARY TABLE IF EXISTS tmp_cf;
    DROP TEMPORARY TABLE IF EXISTS tmp_cf_sv;
    DROP TEMPORARY TABLE IF EXISTS tmp_cf_op;
    DROP TEMPORARY TABLE IF EXISTS tmp_cf_pre;
    DROP TEMPORARY TABLE IF EXISTS tmp_cf_cand;
END$$

DELIMITER ;
