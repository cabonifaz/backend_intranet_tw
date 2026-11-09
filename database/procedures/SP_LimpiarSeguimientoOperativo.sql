-- HU-51 (Sprint 5) Borra las tablas temporales de la bandeja de seguimiento operativo. ESTÁ BIEN llamarla aunque no existan.
DROP PROCEDURE IF EXISTS SP_LimpiarSeguimientoOperativo;

DELIMITER $$

CREATE PROCEDURE SP_LimpiarSeguimientoOperativo()
BEGIN
    DROP TEMPORARY TABLE IF EXISTS tmp_sg_cfg;
    DROP TEMPORARY TABLE IF EXISTS tmp_sg_os;
    DROP TEMPORARY TABLE IF EXISTS tmp_sg_ev;
    DROP TEMPORARY TABLE IF EXISTS tmp_sg_ut;
    DROP TEMPORARY TABLE IF EXISTS tmp_sg_utn;
    DROP TEMPORARY TABLE IF EXISTS tmp_sg_tec;
    DROP TEMPORARY TABLE IF EXISTS tmp_sg_pos;
    DROP TEMPORARY TABLE IF EXISTS tmp_sg_alerta;
    DROP TEMPORARY TABLE IF EXISTS tmp_sg_hito;
    DROP TEMPORARY TABLE IF EXISTS tmp_sg_inc;
    DROP TEMPORARY TABLE IF EXISTS tmp_sg_f;
    DROP TEMPORARY TABLE IF EXISTS tmp_sg_tf;
END$$

DELIMITER ;
