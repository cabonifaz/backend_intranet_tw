-- ============================================================
-- Migración 45 — HU-13 Bandeja de Visto Bueno y HU-14 Revisión y comparación de versiones
--
--   Decisiones (equipo, 09-oct):
--     · Aprobar → propuesta 'aprobado' (VB aprobado, lista para enviar al cliente).
--       Solicitar corrección → vuelve a 'borrador'. Rechazar → 'rechazado' (cerrada).
--       Corrección y rechazo exigen comentario.
--     · SLA en HORAS HÁBILES: lun–vie, 08:00–18:00, 4 h. Próximo a vencer al quedar el 25 %.
--     · Margen real con el precio de costo de los suministros (visible solo a jefaturas).
--     · Crédito: línea del cliente vs. propuestas aceptadas (con OC) aún sin facturar.
--       Stock: no disponible hasta integrar inventario.
--   IDEMPOTENTE. Ejecutar junto con las funciones y SPs de este paquete.
-- ============================================================

-- ── 1. Visto bueno: estado "devuelto" (corrección), quién resolvió y su comentario ──
ALTER TABLE visto_bueno
    MODIFY COLUMN estado ENUM('pendiente','aprobado','rechazado','reasignado','cancelado','devuelto')
                  NOT NULL DEFAULT 'pendiente';

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE()
                           AND TABLE_NAME = 'visto_bueno' AND COLUMN_NAME = 'resuelto_por'),
    'ALTER TABLE visto_bueno ADD COLUMN resuelto_por BIGINT NULL AFTER fecha_respuesta', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE()
                           AND TABLE_NAME = 'visto_bueno' AND COLUMN_NAME = 'comentario_respuesta'),
    'ALTER TABLE visto_bueno ADD COLUMN comentario_respuesta TEXT NULL AFTER resuelto_por', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE()
                           AND TABLE_NAME = 'visto_bueno' AND INDEX_NAME = 'ix_vb_propuesta'),
    'CREATE INDEX ix_vb_propuesta ON visto_bueno (id_propuesta, estado)', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- ── 2. Suministros: precio de costo (margen real, solo jefaturas) ────────
SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE()
                           AND TABLE_NAME = 'suministros' AND COLUMN_NAME = 'precio_costo'),
    'ALTER TABLE suministros ADD COLUMN precio_costo DECIMAL(12,2) NULL AFTER precio_referencia', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE()
                           AND TABLE_NAME = 'suministros' AND COLUMN_NAME = 'costo_actualizado_en'),
    'ALTER TABLE suministros ADD COLUMN costo_actualizado_en DATETIME NULL AFTER precio_costo,
                             ADD COLUMN costo_actualizado_por BIGINT NULL AFTER costo_actualizado_en', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- ── 3. Parámetros (PARAMETRO_PROPUESTA) ──────────────────────────────────
SET @id_param := (SELECT MAX(IdMaestro) FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROPUESTA');
SET @id_param := IFNULL(@id_param, (SELECT MAX(IdMaestro) + 1 FROM tabla_maestra));

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, Num2, String1, String2)
SELECT 1, @id_param, 'PARAMETRO_PROPUESTA', n.orden, n.valor, n.etiqueta, n.codigo
FROM (
          SELECT 10 AS orden, 10 AS valor, 'Margen mínimo aceptable (%)'                   AS etiqueta, 'MARGEN_MINIMO_PCT'       AS codigo
UNION ALL SELECT 11, 15,  'Margen desde el cual se alerta (%)',                    'MARGEN_ALERTA_PCT'
UNION ALL SELECT 12, 8,   'Inicio de la jornada hábil (hora)',                     'JORNADA_INICIO'
UNION ALL SELECT 13, 18,  'Fin de la jornada hábil (hora)',                        'JORNADA_FIN'
UNION ALL SELECT 14, 25,  'VB próximo a vencer al quedar este % del SLA',          'VB_PROXIMO_VENCER_PCT'
UNION ALL SELECT 15, 80,  'Alerta de crédito al usar este % de la línea',          'CREDITO_ALERTA_PCT'
) n
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra x WHERE x.Descripcion = 'PARAMETRO_PROPUESTA' AND x.String2 = n.codigo);

-- SLA del visto bueno: 4 horas hábiles (antes 24 h calendario). Solo si sigue en el valor original.
UPDATE tabla_maestra SET Num2 = 4, String3 = 'horas_habiles'
WHERE IdMaestro = 49 AND IdEmpresa = 1 AND String1 = 'propuesta' AND String2 = 'pendiente_vb' AND Num2 = 24;

-- ── 4. Acciones (#4301) ──────────────────────────────────────────────────
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2, String3)
SELECT 1, 88, 'ACCION_SISTEMA', a.nivel, a.etiqueta, a.codigo, a.modulo
FROM (
          SELECT 3 AS nivel, 'Ver bandeja de visto bueno de su equipo' AS etiqueta, 'propuesta_vb_bandeja' AS codigo, 'propuestas' AS modulo
UNION ALL SELECT 3, 'Aprobar, devolver o rechazar propuestas (VB)',  'propuesta_vb_resolver',  'propuestas'
UNION ALL SELECT 4, 'Ver y resolver el visto bueno de todas las áreas', 'propuesta_vb_todas',  'propuestas'
UNION ALL SELECT 3, 'Ver precio de costo y margen',                  'suministro_costo_ver',   'propuestas'
UNION ALL SELECT 2, 'Registrar precio de costo de suministros',      'suministro_costo_guardar','maestro_suministros'
) a
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra x WHERE x.IdMaestro = 88 AND x.IdEmpresa = 1 AND x.String2 = a.codigo);
