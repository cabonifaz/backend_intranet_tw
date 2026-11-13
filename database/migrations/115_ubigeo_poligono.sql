-- ============================================================
-- Migración 115 — Límites distritales (polígonos) para traducir una coordenada al ubigeo INEI (mapa de "Nueva/Editar Sede del Cliente")
--   ubigeo_poligono: un MULTIPOLYGON por distrito (codigo = ubigeo INEI). SRID 0 (cartesiano): x = longitud, y = latitud.
--   Los datos se cargan aparte con database/seeds/ubigeo_poligono/ubigeo_poligono_parte1..3.sql (límites INEI 2025, simplificados a ~50 m).
--   Además agrega a la tabla ubigeo los 2 distritos nuevos que trae el INEI 2025 y no estaban: 130112 Alto Trujillo y 180107 San Antonio.
--   No cambia datos existentes. IDEMPOTENTE.
-- ============================================================
CREATE TABLE IF NOT EXISTS ubigeo_poligono (
    codigo        CHAR(6)      NOT NULL,
    departamento  VARCHAR(60)  NOT NULL,
    provincia     VARCHAR(60)  NOT NULL,
    distrito      VARCHAR(80)  NOT NULL,
    geom          MULTIPOLYGON NOT NULL SRID 0,
    PRIMARY KEY (codigo),
    SPATIAL INDEX sx_ubigeo_poligono_geom (geom)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

INSERT IGNORE INTO ubigeo (codigo, departamento, provincia, distrito) VALUES
('130112', 'LA LIBERTAD', 'TRUJILLO', 'ALTO TRUJILLO'),
('180107', 'MOQUEGUA', 'MARISCAL NIETO', 'SAN ANTONIO');

SELECT 'Migración 115 · tabla ubigeo_poligono' AS verificacion,
       IF(EXISTS (SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'ubigeo_poligono'), 'OK', 'REVISAR') AS resultado
UNION ALL
SELECT 'Migración 115 · distritos nuevos en ubigeo',
       IF((SELECT COUNT(*) FROM ubigeo WHERE codigo IN ('130112', '180107')) = 2, 'OK', 'REVISAR');
