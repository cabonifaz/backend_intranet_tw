-- ============================================================
-- SP_CatalogoEvidenciasMovil  (App Mobile HU-11 — apoyo, no es un endpoint)
-- Las 9 evidencias del registro fotográfico de un equipo, UNA sola vez, en la tabla temporal tmp_cat_evid (el que la llama la borra al terminar):
--   orden · codigo · nombre · descripcion · obligatoria (la placa y la foto inicial: "(*) obligatorias para cerrar el equipo") ·
--   medio (foto | video | qr) · id_tipo (TIPO_EVIDENCIA de la migración 01 al que se asocia cada una).
-- Todas se necesitan para "Guardar y volver" (panel completo). Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_CatalogoEvidenciasMovil;

DELIMITER $$

CREATE PROCEDURE SP_CatalogoEvidenciasMovil()
BEGIN
    DROP TEMPORARY TABLE IF EXISTS tmp_cat_evid;
    CREATE TEMPORARY TABLE tmp_cat_evid (
        orden INT NOT NULL, codigo VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, nombre VARCHAR(60) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        descripcion VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, obligatoria TINYINT DEFAULT 0, medio VARCHAR(6) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        id_tipo INT NOT NULL,
        -- Los llena SP_ResumenEvidenciasMovil (una sola vez): la última toma vigente está aprobada/forzada/omitida · fue forzada · quedó rechazada
        completa TINYINT NOT NULL DEFAULT 0, forzada TINYINT NOT NULL DEFAULT 0, rechazada TINYINT NOT NULL DEFAULT 0, PRIMARY KEY (orden));
    INSERT INTO tmp_cat_evid (orden, codigo, nombre, descripcion, obligatoria, medio, id_tipo) VALUES
        (1, 'placa',      'Placa de identificación', 'Especificaciones del equipo', 1, 'foto',  1),
        (2, 'inicial',    'Inicial',                 'Estado inicial del equipo',   1, 'foto',  1),
        (3, 'encendido',  'Encendido',               'Video del display (HU-13)',   0, 'video', 2),
        (4, 'desmontaje', 'Desmontaje',              'Partes desmontadas',          0, 'foto',  2),
        (5, 'abierto',    'Abierto',                 'Interior del equipo',         0, 'foto',  2),
        (6, 'prueba',     'Prueba',                  'Equipo con pesas patrón',     0, 'foto',  2),
        (7, 'final',      'Final',                   'Equipo terminado y limpio',   0, 'foto',  3),
        (8, 'informe',    'Informe',                 'Foto del informe a mano',     0, 'foto',  2),
        (9, 'qr',         'QR',                      'Etiqueta QR del equipo',      0, 'qr',    1);
END$$

DELIMITER ;
