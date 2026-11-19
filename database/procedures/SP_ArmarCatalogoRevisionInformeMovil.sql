-- ============================================================
-- SP_ArmarCatalogoRevisionInformeMovil  (App Mobile HU-33 — apoyo, NO es un endpoint)
-- Catálogo FIJO del modal "Observar informe", una sola vez: lo devuelve el detalle del informe (SP_ObtenerInformeRevisionMovil) y lo usa SP_ObservarInformeMovil para validar.
-- Deja la tabla temporal tmp_cat_rev (tipo, codigo, nombre, orden, horas); quien la llame debe terminar con DROP TEMPORARY TABLE IF EXISTS tmp_cat_rev.
--   tipo 'motivo'  : evidencia_insuficiente · datos_incorrectos · ensayos_inconsistentes · firma_faltante · otro
--   tipo 'seccion' : registro_fotografico · cabecera · ensayos · firmas
--   tipo 'plazo'   : codigo h4 / h24 / h48 / h72, horas = 4 / 24 / 48 / 72
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ArmarCatalogoRevisionInformeMovil;

DELIMITER $$

CREATE PROCEDURE SP_ArmarCatalogoRevisionInformeMovil()
BEGIN
    DROP TEMPORARY TABLE IF EXISTS tmp_cat_rev;
    CREATE TEMPORARY TABLE tmp_cat_rev (
        tipo   VARCHAR(10) NOT NULL,
        codigo VARCHAR(30) NOT NULL,
        nombre VARCHAR(60) NOT NULL,
        orden  INT         NOT NULL,
        horas  INT         NULL
    ) DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;

    INSERT INTO tmp_cat_rev (tipo, codigo, nombre, orden, horas) VALUES
        ('motivo',  'evidencia_insuficiente', 'Evidencia insuficiente',     1, NULL),
        ('motivo',  'datos_incorrectos',      'Datos incorrectos',          2, NULL),
        ('motivo',  'ensayos_inconsistentes', 'Ensayos inconsistentes',     3, NULL),
        ('motivo',  'firma_faltante',         'Firma faltante',             4, NULL),
        ('motivo',  'otro',                   'Otro (explicar abajo)',      5, NULL),
        ('seccion', 'registro_fotografico',   'Registro fotográfico',       1, NULL),
        ('seccion', 'cabecera',               'Cabecera',                   2, NULL),
        ('seccion', 'ensayos',                'Ensayos',                    3, NULL),
        ('seccion', 'firmas',                 'Firmas',                     4, NULL),
        ('plazo',   'h4',                     '4 horas',                    1, 4),
        ('plazo',   'h24',                    '24 horas',                   2, 24),
        ('plazo',   'h48',                    '48 horas (2 días)',          3, 48),
        ('plazo',   'h72',                    '72 horas (3 días)',          4, 72);
END$$

DELIMITER ;
