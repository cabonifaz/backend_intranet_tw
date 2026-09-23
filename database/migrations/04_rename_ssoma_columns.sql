-- ============================================================
-- 04_rename_ssoma_columns.sql
-- Renombra las columnas SSOMA de la tabla cliente para alinear
-- con el Figma HU-79.
-- ============================================================

ALTER TABLE cliente
    CHANGE COLUMN ssoma_pase_ingreso      ssoma_poliza_sctr      TINYINT(1) NOT NULL DEFAULT 0,
    CHANGE COLUMN ssoma_trabajo_altura    ssoma_camioneta_4x4    TINYINT(1) NOT NULL DEFAULT 0,
    CHANGE COLUMN ssoma_espacio_confinado ssoma_induccion_ssoma  TINYINT(1) NOT NULL DEFAULT 0,
    CHANGE COLUMN ssoma_induccion_previa  ssoma_examen_medico    TINYINT(1) NOT NULL DEFAULT 0;
