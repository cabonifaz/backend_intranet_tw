-- HU-36 — Borra las tablas temporales de SP_EvaluarSsomaProgramacion (ayuda interna; no devuelve resultados).
-- No borra tmp_ssoma_in: la crea y la borra quien llama.
DROP PROCEDURE IF EXISTS SP_LimpiarSsomaProgramacion;

DELIMITER $$

CREATE PROCEDURE SP_LimpiarSsomaProgramacion()
BEGIN
    DROP TEMPORARY TABLE IF EXISTS tmp_ssoma_res;
    DROP TEMPORARY TABLE IF EXISTS tmp_ssoma_agg;
    DROP TEMPORARY TABLE IF EXISTS tmp_ssoma_det;
    DROP TEMPORARY TABLE IF EXISTS tmp_ssoma_doc;
    DROP TEMPORARY TABLE IF EXISTS tmp_ssoma_req;
END$$

DELIMITER ;
