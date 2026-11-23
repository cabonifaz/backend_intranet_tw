-- ============================================================
-- SP_CatalogoAccesoriosRecepcionOmMovil  (App Mobile HU-23 Recepción de instrumentos (OM) — apoyo, NO es un endpoint)
-- Catálogo FIJO de accesorios recibidos con un instrumento, UNA sola vez, en la tabla temporal `tmp_rom_acc` (codigo, nombre, orden). Lo usa SP_RegistrarRecepcionOmMovil para validar.
--   caja_original → «Caja original» · adaptador_corriente → «Adaptador de corriente» · protector_plato → «Protector de plato» · manual → «Manual» · otro → «Otro»
-- (La app y el PDF de la constancia muestran las mismas etiquetas: CatalogoRecepcionOm en el back y utilidades/recepcionOm en la app.)
-- Quien la llame debe terminar con DROP TEMPORARY TABLE IF EXISTS tmp_rom_acc. Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_CatalogoAccesoriosRecepcionOmMovil;

DELIMITER $$

CREATE PROCEDURE SP_CatalogoAccesoriosRecepcionOmMovil()
BEGIN
    DROP TEMPORARY TABLE IF EXISTS tmp_rom_acc;
    CREATE TEMPORARY TABLE tmp_rom_acc (
        codigo VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL,
        nombre VARCHAR(60) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL,
        orden INT NOT NULL,
        PRIMARY KEY (codigo));
    INSERT INTO tmp_rom_acc (codigo, nombre, orden) VALUES
        ('caja_original',       'Caja original',          1),
        ('adaptador_corriente', 'Adaptador de corriente', 2),
        ('protector_plato',     'Protector de plato',     3),
        ('manual',              'Manual',                 4),
        ('otro',                'Otro',                   5);
END$$

DELIMITER ;
