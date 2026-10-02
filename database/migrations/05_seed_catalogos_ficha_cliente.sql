-- ============================================================
-- 05_seed_catalogos_ficha_cliente.sql
-- Ajusta CONDICION_PAGO (IdMaestro=39) y agrega los catálogos
-- faltantes para la ficha de cliente HU-79:
--   57 · TIPO_DOC_CLIENTE
--   58 · TIPO_CLIENTE
--   59 · PATRON_MASAS
-- ============================================================

-- Limpiar y recargar CONDICION_PAGO para agregar Crédito 90 días
DELETE FROM tabla_maestra WHERE IdEmpresa = 1 AND IdMaestro = 39;

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, Num2, Num3, String1, String2, String3)
VALUES
(1, 39, 'CONDICION_PAGO', 1, NULL, NULL, 'Contado',                           'CONTADO',      NULL),
(1, 39, 'CONDICION_PAGO', 2, NULL, NULL, 'Crédito 15 días',                   'CREDITO_15',   NULL),
(1, 39, 'CONDICION_PAGO', 3, NULL, NULL, 'Crédito 30 días',                   'CREDITO_30',   NULL),
(1, 39, 'CONDICION_PAGO', 4, NULL, NULL, 'Crédito 45 días',                   'CREDITO_45',   NULL),
(1, 39, 'CONDICION_PAGO', 5, NULL, NULL, 'Crédito 60 días',                   'CREDITO_60',   NULL),
(1, 39, 'CONDICION_PAGO', 6, NULL, NULL, 'Crédito 90 días',                   'CREDITO_90',   NULL),
(1, 39, 'CONDICION_PAGO', 7, NULL, NULL, '50% adelanto + 50% contra entrega', 'ADELANTO_50',  NULL),
(1, 39, 'CONDICION_PAGO', 8, NULL, NULL, 'Otro acuerdo',                      'OTRO',         NULL);

-- TIPO_DOC_CLIENTE (IdMaestro=57)
DELETE FROM tabla_maestra WHERE IdEmpresa = 1 AND IdMaestro = 57;

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, Num2, Num3, String1, String2, String3)
VALUES
(1, 57, 'TIPO_DOC_CLIENTE', 1, NULL, NULL, 'RUC', 'RUC', NULL),
(1, 57, 'TIPO_DOC_CLIENTE', 2, NULL, NULL, 'DNI', 'DNI', NULL),
(1, 57, 'TIPO_DOC_CLIENTE', 3, NULL, NULL, 'CE',  'CE',  NULL);

-- TIPO_CLIENTE — segmentos de industria TW (IdMaestro=58)
DELETE FROM tabla_maestra WHERE IdEmpresa = 1 AND IdMaestro = 58;

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, Num2, Num3, String1, String2, String3)
VALUES
(1, 58, 'TIPO_CLIENTE', 1, NULL, NULL, 'Gran Minería',            'GRAN_MINERIA',   NULL),
(1, 58, 'TIPO_CLIENTE', 2, NULL, NULL, 'Mediana Minería',         'MEDIANA_MINERIA',NULL),
(1, 58, 'TIPO_CLIENTE', 3, NULL, NULL, 'Pequeña Minería',         'PEQUENA_MINERIA',NULL),
(1, 58, 'TIPO_CLIENTE', 4, NULL, NULL, 'Petroquímica / Energía',  'PETROQUIMICA',   NULL),
(1, 58, 'TIPO_CLIENTE', 5, NULL, NULL, 'Industrial',              'INDUSTRIAL',     NULL),
(1, 58, 'TIPO_CLIENTE', 6, NULL, NULL, 'Gobierno / Estado',       'GOBIERNO',       NULL),
(1, 58, 'TIPO_CLIENTE', 7, NULL, NULL, 'Otro',                    'OTRO',           NULL);

-- PATRON_MASAS — clases INACAL (IdMaestro=59)
DELETE FROM tabla_maestra WHERE IdEmpresa = 1 AND IdMaestro = 59;

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, Num2, Num3, String1, String2, String3)
VALUES
(1, 59, 'PATRON_MASAS', 1, NULL, NULL, 'Clase E2 Certificado INACAL',       'E2',     NULL),
(1, 59, 'PATRON_MASAS', 2, NULL, NULL, 'Clase F1 Certificado INACAL',       'F1',     NULL),
(1, 59, 'PATRON_MASAS', 3, NULL, NULL, 'Clase F2 Certificado INACAL',       'F2',     NULL),
(1, 59, 'PATRON_MASAS', 4, NULL, NULL, 'Clase M1 / F2 Certificado INACAL',  'M1_F2',  NULL),
(1, 59, 'PATRON_MASAS', 5, NULL, NULL, 'Clase M2 Certificado INACAL',       'M2',     NULL);
