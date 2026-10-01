-- ============================================================
-- Migración 26 — HU-86 (complemento): catálogos de Marca y Modelo
--   de suministros. Códigos iguales a los del front (MARCAS_SUMINISTRO
--   y MODELOS_SUMINISTRO) para que los registros ya guardados coincidan.
--   Nota: IdMaestro 76 = TIPO_PROCEDIMIENTO (HU-87).
-- ============================================================

-- Marca (77)
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2) VALUES
(1, 77, 'MARCA_SUMINISTRO',  1, '3S CIENTIFIC',   '3s_cientific'),
(1, 77, 'MARCA_SUMINISTRO',  2, 'A&D',            'ad'),
(1, 77, 'MARCA_SUMINISTRO',  3, 'METTLER TOLEDO', 'mettler_toledo'),
(1, 77, 'MARCA_SUMINISTRO',  4, 'MITUTOYO',       'mitutoyo'),
(1, 77, 'MARCA_SUMINISTRO',  5, 'OHAUS',          'ohaus'),
(1, 77, 'MARCA_SUMINISTRO',  6, 'RADWAG',         'radwag'),
(1, 77, 'MARCA_SUMINISTRO',  7, 'RICE LAKE',      'rice_lake'),
(1, 77, 'MARCA_SUMINISTRO',  8, 'SARTORIUS',      'sartorius'),
(1, 77, 'MARCA_SUMINISTRO',  9, 'SHIMADZU',       'shimadzu'),
(1, 77, 'MARCA_SUMINISTRO', 10, 'TOTAL WEIGHT',   'total_weight');

-- Modelo (78)
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2) VALUES
(1, 78, 'MODELO_SUMINISTRO', 1, 'HTC-8',          'htc_8'),
(1, 78, 'MODELO_SUMINISTRO', 2, 'PTI-1212-T32XW', 'pti_1212_t32xw'),
(1, 78, 'MODELO_SUMINISTRO', 3, '516-106-10',     '516_106_10'),
(1, 78, 'MODELO_SUMINISTRO', 4, 'PDX50',          'pdx50'),
(1, 78, 'MODELO_SUMINISTRO', 5, '820',            '820'),
(1, 78, 'MODELO_SUMINISTRO', 6, 'TW-M1',          'tw_m1'),
(1, 78, 'MODELO_SUMINISTRO', 7, 'EK-6000',        'ek_6000');
