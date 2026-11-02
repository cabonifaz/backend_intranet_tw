-- ============================================================
-- Migración 82 — Observaciones del cliente Sprint 3 y 4 (31/10): Requerimientos y Cartera de clientes
--   1. Área de servicio del RQ (catálogo AREA_REQUERIMIENTO 64): solo Comercial, Servicio Técnico y Metrología.
--      Calibración pasa a Metrología; Mantenimiento, Soporte técnico e Instalación pasan a Servicio Técnico
--      (se actualizan los RQ existentes y el ruteo de la app móvil, area_servicio_rq). Las áreas viejas quedan
--      dadas de baja (eliminado_en) para no aparecer en la ficha.
--   2. requerimiento.fecha_necesidad: DATE → DATETIME ("Fecha de requerimiento" con hora).
--   3. requerimiento.id_contacto_secundario: segundo contacto del RQ.
--   4. requerimiento.es_inacal (ya existía) = "Proyecto entra al sistema de acreditación"; se asegura NOT NULL DEFAULT 0.
--   5. Cartera de clientes: cliente.id_comercial_cartera / cartera_asignado_en / cartera_asignado_por y la acción
--      cartera_asignar (nivel 4 en maestro_clientes: solo administradores).
--   6. Tipo de documento "Adjunto del requerimiento" (catálogo 96) para los adjuntos del RQ.
--
--   IDEMPOTENTE. Se puede re-ejecutar.
-- ============================================================

DROP PROCEDURE IF EXISTS tmp_mig82_columna;
DELIMITER $$
CREATE PROCEDURE tmp_mig82_columna(IN p_tabla VARCHAR(64), IN p_columna VARCHAR(64), IN p_definicion VARCHAR(500))
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                   WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = p_tabla AND COLUMN_NAME = p_columna) THEN
        SET @sql = CONCAT('ALTER TABLE ', p_tabla, ' ADD COLUMN ', p_columna, ' ', p_definicion);
        PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;
    END IF;
END$$
DELIMITER ;

-- ── 1. Áreas del RQ ──────────────────────────────────────────────────────────
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2)
SELECT 1, 64, 'AREA_REQUERIMIENTO', (SELECT IFNULL(MAX(t.Num1), 0) + 1 FROM tabla_maestra t WHERE t.IdMaestro = 64 AND t.IdEmpresa = 1),
       'Comercial', 'comercial'
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra WHERE IdMaestro = 64 AND IdEmpresa = 1 AND String2 = 'comercial');

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2)
SELECT 1, 64, 'AREA_REQUERIMIENTO', (SELECT IFNULL(MAX(t.Num1), 0) + 1 FROM tabla_maestra t WHERE t.IdMaestro = 64 AND t.IdEmpresa = 1),
       'Servicio Técnico', 'servicio_tecnico'
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra WHERE IdMaestro = 64 AND IdEmpresa = 1 AND String2 = 'servicio_tecnico');

-- Metrología: la que ya existe (por nombre); si no hubiera, se crea
UPDATE tabla_maestra SET String2 = 'metrologia'
WHERE IdMaestro = 64 AND IdEmpresa = 1 AND String2 IS NULL AND LOWER(String1) LIKE 'metrolog%';

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2)
SELECT 1, 64, 'AREA_REQUERIMIENTO', (SELECT IFNULL(MAX(t.Num1), 0) + 1 FROM tabla_maestra t WHERE t.IdMaestro = 64 AND t.IdEmpresa = 1),
       'Metrología', 'metrologia'
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra WHERE IdMaestro = 64 AND IdEmpresa = 1 AND String2 = 'metrologia');

UPDATE tabla_maestra SET eliminado_en = NULL
WHERE IdMaestro = 64 AND IdEmpresa = 1 AND String2 IN ('comercial', 'servicio_tecnico', 'metrologia');

SET @a_met := (SELECT MIN(Num1) FROM tabla_maestra WHERE IdMaestro = 64 AND IdEmpresa = 1 AND String2 = 'metrologia');
SET @a_st  := (SELECT MIN(Num1) FROM tabla_maestra WHERE IdMaestro = 64 AND IdEmpresa = 1 AND String2 = 'servicio_tecnico');

-- RQ con las áreas viejas → nuevas (Calibración → Metrología; el resto → Servicio Técnico)
UPDATE requerimiento r
JOIN tabla_maestra t ON t.IdMaestro = 64 AND t.IdEmpresa = 1 AND t.Num1 = r.id_area
SET r.id_area = IF(LOWER(t.String1) LIKE '%calibra%' OR LOWER(t.String1) LIKE '%metrolog%', @a_met, @a_st)
WHERE IFNULL(t.String2, '') NOT IN ('comercial', 'servicio_tecnico', 'metrologia');

UPDATE tabla_maestra SET eliminado_en = IFNULL(eliminado_en, NOW())
WHERE IdMaestro = 64 AND IdEmpresa = 1 AND IFNULL(String2, '') NOT IN ('comercial', 'servicio_tecnico', 'metrologia');

-- Ruteo de la app móvil (autorización de salida): Servicio Técnico y Metrología. Comercial no se mapea (va a ambos).
INSERT INTO area_servicio_rq (id_area_rq, area_usuario)
SELECT @a_st, 'servicio_tecnico' FROM DUAL
WHERE @a_st IS NOT NULL AND NOT EXISTS (SELECT 1 FROM area_servicio_rq WHERE id_area_rq = @a_st);
INSERT INTO area_servicio_rq (id_area_rq, area_usuario)
SELECT @a_met, 'metrologia' FROM DUAL
WHERE @a_met IS NOT NULL AND NOT EXISTS (SELECT 1 FROM area_servicio_rq WHERE id_area_rq = @a_met);

-- ── 2. Fecha de requerimiento con hora ──────────────────────────────────────
SET @sql := IF(EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'requerimiento'
                         AND COLUMN_NAME = 'fecha_necesidad' AND DATA_TYPE = 'date'),
    'ALTER TABLE requerimiento MODIFY COLUMN fecha_necesidad DATETIME NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- ── 3. Segundo contacto ─────────────────────────────────────────────────────
CALL tmp_mig82_columna('requerimiento', 'id_contacto_secundario', 'BIGINT NULL AFTER id_contacto');

-- ── 4. Acreditación ─────────────────────────────────────────────────────────
CALL tmp_mig82_columna('requerimiento', 'es_inacal', 'TINYINT(1) NOT NULL DEFAULT 0');
UPDATE requerimiento SET es_inacal = 0 WHERE es_inacal IS NULL;
ALTER TABLE requerimiento MODIFY COLUMN es_inacal TINYINT(1) NOT NULL DEFAULT 0;

-- ── 5. Cartera de clientes ──────────────────────────────────────────────────
CALL tmp_mig82_columna('cliente', 'id_comercial_cartera', 'BIGINT NULL');
CALL tmp_mig82_columna('cliente', 'cartera_asignado_en',  'DATETIME NULL');
CALL tmp_mig82_columna('cliente', 'cartera_asignado_por', 'BIGINT NULL');

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2, String3)
SELECT 1, 88, 'ACCION_SISTEMA', 4, 'Asignar la cartera de clientes a los comerciales', 'cartera_asignar', 'maestro_clientes'
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra WHERE IdMaestro = 88 AND IdEmpresa = 1 AND String2 = 'cartera_asignar');

-- ── 6. Tipo de documento de los adjuntos del RQ ─────────────────────────────
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2)
SELECT 1, 96, 'TIPO_DOCUMENTO_ADJUNTO', (SELECT IFNULL(MAX(t.Num1), 0) + 1 FROM tabla_maestra t WHERE t.IdMaestro = 96 AND t.IdEmpresa = 1),
       'Adjunto del requerimiento', 'ADJUNTO_REQUERIMIENTO'
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra WHERE IdMaestro = 96 AND IdEmpresa = 1 AND String2 = 'ADJUNTO_REQUERIMIENTO');

DROP PROCEDURE IF EXISTS tmp_mig82_columna;
