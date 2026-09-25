-- ============================================================
-- 07_seed_catalogos_sede.sql
-- Seed catálogos para HU-80: TIPO_INSTALACION (60) + REGION_PERU (61)
-- ============================================================

-- TIPO_INSTALACION (IdMaestro = 60)
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, Num2, Num3, String1, String2, String3)
VALUES
  (1, 60, 'TIPO_INSTALACION', 1, NULL, NULL, 'Mina y Tajo Abierto',                    NULL, NULL),
  (1, 60, 'TIPO_INSTALACION', 2, NULL, NULL, 'Planta de Procesamiento / Concentradora', NULL, NULL),
  (1, 60, 'TIPO_INSTALACION', 3, NULL, NULL, 'Campamento Minero',                       NULL, NULL),
  (1, 60, 'TIPO_INSTALACION', 4, NULL, NULL, 'Oficina Administrativa',                  NULL, NULL),
  (1, 60, 'TIPO_INSTALACION', 5, NULL, NULL, 'Almacén / Depósito',                      NULL, NULL),
  (1, 60, 'TIPO_INSTALACION', 6, NULL, NULL, 'Puerto / Muelle de Embarque',             NULL, NULL);

-- REGION_PERU (IdMaestro = 61)
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, Num2, Num3, String1, String2, String3)
VALUES
  (1, 61, 'REGION_PERU',  1, NULL, NULL, 'Amazonas',           NULL, NULL),
  (1, 61, 'REGION_PERU',  2, NULL, NULL, 'Áncash',             NULL, NULL),
  (1, 61, 'REGION_PERU',  3, NULL, NULL, 'Apurímac',           NULL, NULL),
  (1, 61, 'REGION_PERU',  4, NULL, NULL, 'Arequipa',           NULL, NULL),
  (1, 61, 'REGION_PERU',  5, NULL, NULL, 'Ayacucho',           NULL, NULL),
  (1, 61, 'REGION_PERU',  6, NULL, NULL, 'Cajamarca',          NULL, NULL),
  (1, 61, 'REGION_PERU',  7, NULL, NULL, 'Callao',             NULL, NULL),
  (1, 61, 'REGION_PERU',  8, NULL, NULL, 'Cusco',              NULL, NULL),
  (1, 61, 'REGION_PERU',  9, NULL, NULL, 'Huancavelica',       NULL, NULL),
  (1, 61, 'REGION_PERU', 10, NULL, NULL, 'Huánuco',            NULL, NULL),
  (1, 61, 'REGION_PERU', 11, NULL, NULL, 'Ica',                NULL, NULL),
  (1, 61, 'REGION_PERU', 12, NULL, NULL, 'Junín',              NULL, NULL),
  (1, 61, 'REGION_PERU', 13, NULL, NULL, 'La Libertad',        NULL, NULL),
  (1, 61, 'REGION_PERU', 14, NULL, NULL, 'Lambayeque',         NULL, NULL),
  (1, 61, 'REGION_PERU', 15, NULL, NULL, 'Lima',               NULL, NULL),
  (1, 61, 'REGION_PERU', 16, NULL, NULL, 'Lima Metropolitana', NULL, NULL),
  (1, 61, 'REGION_PERU', 17, NULL, NULL, 'Loreto',             NULL, NULL),
  (1, 61, 'REGION_PERU', 18, NULL, NULL, 'Madre de Dios',      NULL, NULL),
  (1, 61, 'REGION_PERU', 19, NULL, NULL, 'Moquegua',           NULL, NULL),
  (1, 61, 'REGION_PERU', 20, NULL, NULL, 'Pasco',              NULL, NULL),
  (1, 61, 'REGION_PERU', 21, NULL, NULL, 'Piura',              NULL, NULL),
  (1, 61, 'REGION_PERU', 22, NULL, NULL, 'Puno',               NULL, NULL),
  (1, 61, 'REGION_PERU', 23, NULL, NULL, 'San Martín',         NULL, NULL),
  (1, 61, 'REGION_PERU', 24, NULL, NULL, 'Tacna',              NULL, NULL),
  (1, 61, 'REGION_PERU', 25, NULL, NULL, 'Tumbes',             NULL, NULL),
  (1, 61, 'REGION_PERU', 26, NULL, NULL, 'Ucayali',            NULL, NULL);
