-- HU-35 — Borra las tablas temporales que arma SP_ArmarBaseProgramacion (ayuda interna; no devuelve resultados).
DROP PROCEDURE IF EXISTS SP_LimpiarBaseProgramacion;

DELIMITER $$

CREATE PROCEDURE SP_LimpiarBaseProgramacion()
BEGIN
    DROP TEMPORARY TABLE IF EXISTS tmp_prog_lista;
    DROP TEMPORARY TABLE IF EXISTS tmp_prog_conteo;
    DROP TEMPORARY TABLE IF EXISTS tmp_prog_conf_ud;
    DROP TEMPORARY TABLE IF EXISTS tmp_prog_conf_os;
    DROP TEMPORARY TABLE IF EXISTS tmp_prog_b;
    DROP TEMPORARY TABLE IF EXISTS tmp_prog_a;
    DROP TEMPORARY TABLE IF EXISTS tmp_prog_asig;
    DROP TEMPORARY TABLE IF EXISTS tmp_prog_base;
    DROP TEMPORARY TABLE IF EXISTS tmp_prog_raw;
    DROP TEMPORARY TABLE IF EXISTS tmp_prog_tecnicos;
END$$

DELIMITER ;
