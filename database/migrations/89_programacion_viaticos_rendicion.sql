-- ============================================================
-- Migración 89 — Asignación de viáticos y rendición de gastos operativos de la Programación (HU-45, Sprint 5)
--   Modelo B (adelanto + rendición): el Jefe de Operaciones asigna un monto por técnico y concepto (gasto_viatico.tipo = 'viatico_asignado');
--   el técnico rinde sus gastos desde la app (tipo = 'gasto_solicitado') y el Jefe los aprueba, observa o rechaza.
--   Convenciones que ya usaban las HU anteriores y se respetan: en un viático asignado, estado 'aprobado' = DEPOSITADO por Contabilidad
--   (este módulo nunca lo marca) y cualquier otro estado = pendiente de depósito.
--   1. gasto_viatico: se vincula a la programación y se agregan los datos de la rendición:
--        id_programacion · fecha_gasto (cuándo gastó el técnico) · comentario_revision (observación o motivo de rechazo) ·
--        revisado_por / revisado_en · fecha_deposito (la completa Contabilidad) · notificado_en (cuándo se avisó a Contabilidad)
--   2. programacion_rendicion: cierre de la rendición de una programación (saldo final y a favor de quién).
--   3. Catálogo de conceptos (CONCEPTO_GASTO, IdMaestro 25): se completan por código los que falten (no duplica los existentes).
--   No borra ni cambia datos existentes. IDEMPOTENTE. Ejecutar junto con los SPs de este mismo paquete.
-- ============================================================

-- ── 1. gasto_viatico: vínculo con la programación y datos de la rendición ───────────────────
SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'gasto_viatico' AND COLUMN_NAME = 'id_programacion'),
    'ALTER TABLE gasto_viatico ADD COLUMN id_programacion BIGINT NULL AFTER id_os', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'gasto_viatico' AND COLUMN_NAME = 'fecha_gasto'),
    'ALTER TABLE gasto_viatico ADD COLUMN fecha_gasto DATE NULL AFTER fecha_solicitud', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'gasto_viatico' AND COLUMN_NAME = 'comentario_revision'),
    'ALTER TABLE gasto_viatico ADD COLUMN comentario_revision VARCHAR(500) NULL AFTER aprobado_por', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'gasto_viatico' AND COLUMN_NAME = 'revisado_por'),
    'ALTER TABLE gasto_viatico ADD COLUMN revisado_por BIGINT NULL AFTER comentario_revision', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'gasto_viatico' AND COLUMN_NAME = 'revisado_en'),
    'ALTER TABLE gasto_viatico ADD COLUMN revisado_en DATETIME NULL AFTER revisado_por', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'gasto_viatico' AND COLUMN_NAME = 'fecha_deposito'),
    'ALTER TABLE gasto_viatico ADD COLUMN fecha_deposito DATE NULL AFTER revisado_en', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'gasto_viatico' AND COLUMN_NAME = 'notificado_en'),
    'ALTER TABLE gasto_viatico ADD COLUMN notificado_en DATETIME NULL AFTER fecha_deposito', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'gasto_viatico' AND INDEX_NAME = 'ix_gasto_programacion'),
    'CREATE INDEX ix_gasto_programacion ON gasto_viatico (id_programacion, tipo, estado)', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'gasto_viatico' AND INDEX_NAME = 'ix_gasto_os_tipo'),
    'CREATE INDEX ix_gasto_os_tipo ON gasto_viatico (id_os, tipo, estado)', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- ── 2. Cierre de la rendición ───────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS programacion_rendicion (
    id_rendicion        BIGINT          NOT NULL AUTO_INCREMENT,
    id_programacion     BIGINT          NOT NULL,
    id_os               BIGINT          NOT NULL,
    total_asignado      DECIMAL(12,2)   NOT NULL DEFAULT 0,
    total_depositado    DECIMAL(12,2)   NOT NULL DEFAULT 0,
    total_solicitado    DECIMAL(12,2)   NOT NULL DEFAULT 0,
    total_aprobado      DECIMAL(12,2)   NOT NULL DEFAULT 0,
    total_rechazado     DECIMAL(12,2)   NOT NULL DEFAULT 0,
    saldo               DECIMAL(12,2)   NOT NULL DEFAULT 0,     -- aprobado − asignado (>0 reembolso al técnico · <0 devolución del técnico)
    tipo_saldo          ENUM('reembolso','devolucion','cuadrado') NOT NULL,
    cerrado_por         BIGINT          NOT NULL,
    cerrado_en          DATETIME        NOT NULL,
    -- AUDITORÍA
    creado_en           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por          BIGINT          NULL,
    modificado_en       DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por      BIGINT          NULL,
    eliminado_en        DATETIME        NULL,
    eliminado_por       BIGINT          NULL,
    PRIMARY KEY (id_rendicion),
    KEY ix_rendicion_programacion (id_programacion)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ── 3. Catálogo de conceptos de gasto (por código, sin duplicar lo existente) ─────────────────
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2, String3)
SELECT 1, 25, 'CONCEPTO_GASTO', (SELECT IFNULL(MAX(t.Num1), 0) + 1 FROM tabla_maestra t WHERE t.IdMaestro = 25 AND t.IdEmpresa = 1),
       v.nombre, v.categoria, v.codigo
FROM (SELECT 'Movilidad / Transporte' AS nombre, 'viatico' AS categoria, 'MOVILIDAD' AS codigo) v
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra x WHERE x.IdMaestro = 25 AND x.IdEmpresa = 1 AND x.String3 = v.codigo);

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2, String3)
SELECT 1, 25, 'CONCEPTO_GASTO', (SELECT IFNULL(MAX(t.Num1), 0) + 1 FROM tabla_maestra t WHERE t.IdMaestro = 25 AND t.IdEmpresa = 1),
       v.nombre, v.categoria, v.codigo
FROM (SELECT 'Alimentación' AS nombre, 'viatico' AS categoria, 'ALIMENTACION' AS codigo) v
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra x WHERE x.IdMaestro = 25 AND x.IdEmpresa = 1 AND x.String3 = v.codigo);

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2, String3)
SELECT 1, 25, 'CONCEPTO_GASTO', (SELECT IFNULL(MAX(t.Num1), 0) + 1 FROM tabla_maestra t WHERE t.IdMaestro = 25 AND t.IdEmpresa = 1),
       v.nombre, v.categoria, v.codigo
FROM (SELECT 'Alojamiento' AS nombre, 'viatico' AS categoria, 'ALOJAMIENTO' AS codigo) v
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra x WHERE x.IdMaestro = 25 AND x.IdEmpresa = 1 AND x.String3 = v.codigo);

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2, String3)
SELECT 1, 25, 'CONCEPTO_GASTO', (SELECT IFNULL(MAX(t.Num1), 0) + 1 FROM tabla_maestra t WHERE t.IdMaestro = 25 AND t.IdEmpresa = 1),
       v.nombre, v.categoria, v.codigo
FROM (SELECT 'Peaje' AS nombre, 'gasto_operativo' AS categoria, 'PEAJE' AS codigo) v
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra x WHERE x.IdMaestro = 25 AND x.IdEmpresa = 1 AND x.String3 = v.codigo);

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2, String3)
SELECT 1, 25, 'CONCEPTO_GASTO', (SELECT IFNULL(MAX(t.Num1), 0) + 1 FROM tabla_maestra t WHERE t.IdMaestro = 25 AND t.IdEmpresa = 1),
       v.nombre, v.categoria, v.codigo
FROM (SELECT 'Estacionamiento' AS nombre, 'gasto_operativo' AS categoria, 'ESTACIONAMIENTO' AS codigo) v
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra x WHERE x.IdMaestro = 25 AND x.IdEmpresa = 1 AND x.String3 = v.codigo);

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2, String3)
SELECT 1, 25, 'CONCEPTO_GASTO', (SELECT IFNULL(MAX(t.Num1), 0) + 1 FROM tabla_maestra t WHERE t.IdMaestro = 25 AND t.IdEmpresa = 1),
       v.nombre, v.categoria, v.codigo
FROM (SELECT 'Insumo / Repuesto menor' AS nombre, 'gasto_operativo' AS categoria, 'INSUMO' AS codigo) v
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra x WHERE x.IdMaestro = 25 AND x.IdEmpresa = 1 AND x.String3 = v.codigo);

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2, String3)
SELECT 1, 25, 'CONCEPTO_GASTO', (SELECT IFNULL(MAX(t.Num1), 0) + 1 FROM tabla_maestra t WHERE t.IdMaestro = 25 AND t.IdEmpresa = 1),
       v.nombre, v.categoria, v.codigo
FROM (SELECT 'Combustible' AS nombre, 'gasto_operativo' AS categoria, 'COMBUSTIBLE' AS codigo) v
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra x WHERE x.IdMaestro = 25 AND x.IdEmpresa = 1 AND x.String3 = v.codigo);

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2, String3)
SELECT 1, 25, 'CONCEPTO_GASTO', (SELECT IFNULL(MAX(t.Num1), 0) + 1 FROM tabla_maestra t WHERE t.IdMaestro = 25 AND t.IdEmpresa = 1),
       v.nombre, v.categoria, v.codigo
FROM (SELECT 'Otro concepto' AS nombre, 'gasto_operativo' AS categoria, 'OTRO' AS codigo) v
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra x WHERE x.IdMaestro = 25 AND x.IdEmpresa = 1 AND x.String3 = v.codigo);
