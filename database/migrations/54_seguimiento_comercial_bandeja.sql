-- ============================================================
-- Migración 54 — HU-17 Bandeja de Seguimiento Comercial
--   1. seguimiento_comercial: tipo y detalle de la próxima acción
--      (id_tipo_proxima_accion, proxima_accion_detalle)
--   2. Catálogo TIPO_ACCION_SEGUIMIENTO (Num1 = id, String1 = nombre, String2 = código)
--   3. RESULTADO_SEGUIMIENTO (27): nuevo resultado SOLICITA_AJUSTE (estado visual "Requiere ajuste")
--   4. PARAMETRO_PROPUESTA: SEGUIMIENTO_DIAS_SIN_RESPUESTA (7) y SEGUIMIENTO_META_ACEPTADAS_MES (8)
--   5. CONFIG_SLA (49): propuesta / seguimiento = 48 h límite, 24 h alerta, días calendario
--   6. Acciones: propuesta_seguimiento_bandeja (nivel 2) y propuesta_seguimiento_todas (nivel 4)
--
--   IDEMPOTENTE. Se puede re-ejecutar.
-- ============================================================

-- 1. Columnas nuevas en seguimiento_comercial
SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'seguimiento_comercial'
                             AND COLUMN_NAME = 'id_tipo_proxima_accion'),
    'ALTER TABLE seguimiento_comercial ADD COLUMN id_tipo_proxima_accion INT NULL AFTER proxima_accion_fecha',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'seguimiento_comercial'
                             AND COLUMN_NAME = 'proxima_accion_detalle'),
    'ALTER TABLE seguimiento_comercial ADD COLUMN proxima_accion_detalle VARCHAR(200) NULL AFTER id_tipo_proxima_accion',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- 2. Catálogo TIPO_ACCION_SEGUIMIENTO (el IdMaestro se reserva al crear la primera fila)
SET @id_tipo := (SELECT MAX(IdMaestro) FROM tabla_maestra WHERE Descripcion = 'TIPO_ACCION_SEGUIMIENTO');
SET @id_tipo := IFNULL(@id_tipo, (SELECT MAX(IdMaestro) + 1 FROM tabla_maestra));

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2)
SELECT 1, @id_tipo, 'TIPO_ACCION_SEGUIMIENTO', t.id, t.nombre, t.codigo
FROM (
          SELECT 1 AS id, 'Llamada de seguimiento'  AS nombre, 'LLAMADA'         AS codigo
UNION ALL SELECT 2, 'Envío de correo',                 'CORREO'
UNION ALL SELECT 3, 'Reunión con el cliente',          'REUNION'
UNION ALL SELECT 4, 'Visita presencial',               'VISITA'
UNION ALL SELECT 5, 'Reenvío de ajustes',              'REENVIO_AJUSTES'
UNION ALL SELECT 6, 'Generar orden de compra',         'GENERAR_OC'
UNION ALL SELECT 7, 'Otra acción',                     'OTRO'
) t
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra x
                  WHERE x.Descripcion = 'TIPO_ACCION_SEGUIMIENTO' AND x.String2 = t.codigo);

-- 3. Resultado "Cliente solicita ajustes"
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2)
SELECT 1, 27, 'RESULTADO_SEGUIMIENTO', 7, 'Cliente solicita ajustes', 'SOLICITA_AJUSTE'
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra WHERE IdMaestro = 27 AND IdEmpresa = 1 AND String2 = 'SOLICITA_AJUSTE');

-- 4. Parámetros de la bandeja
SET @id_param := (SELECT MAX(IdMaestro) FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROPUESTA');
SET @id_param := IFNULL(@id_param, (SELECT MAX(IdMaestro) + 1 FROM tabla_maestra));
SET @n_param  := (SELECT IFNULL(MAX(Num1), 0) FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROPUESTA');

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, Num2, String1, String2)
SELECT 1, @id_param, 'PARAMETRO_PROPUESTA', @n_param + 1, 7,
       'Días sin respuesta del cliente para marcar la propuesta como Sin respuesta', 'SEGUIMIENTO_DIAS_SIN_RESPUESTA'
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROPUESTA' AND String2 = 'SEGUIMIENTO_DIAS_SIN_RESPUESTA');

SET @n_param  := (SELECT IFNULL(MAX(Num1), 0) FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROPUESTA');

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, Num2, String1, String2)
SELECT 1, @id_param, 'PARAMETRO_PROPUESTA', @n_param + 1, 8,
       'Meta mensual de propuestas aceptadas (KPI de la bandeja de seguimiento)', 'SEGUIMIENTO_META_ACEPTADAS_MES'
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROPUESTA' AND String2 = 'SEGUIMIENTO_META_ACEPTADAS_MES');

-- 5. SLA del seguimiento (Num2 = horas límite, Num3 = horas de alerta, String3 = días hábiles 0/1)
SET @n_sla := (SELECT IFNULL(MAX(Num1), 0) + 1 FROM tabla_maestra WHERE IdMaestro = 49 AND IdEmpresa = 1);

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, Num2, Num3, String1, String2, String3)
SELECT 1, 49, 'CONFIG_SLA', @n_sla, 48, 24, 'propuesta', 'seguimiento', '0'
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra
                  WHERE IdMaestro = 49 AND IdEmpresa = 1 AND String1 = 'propuesta' AND String2 = 'seguimiento');

-- 6. Acciones (módulo propuestas)
--    nivel 2 = editar  -> usuario (asistente), supervisor (jefe) y administrador del área
--    nivel 4 = administrar -> administradores de Gerencia y TI ven todas las áreas
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2, String3)
SELECT 1, 88, 'ACCION_SISTEMA', a.nivel, a.etiqueta, a.codigo, a.modulo
FROM (
          SELECT 2 AS nivel, 'Ver bandeja de seguimiento comercial' AS etiqueta,
                 'propuesta_seguimiento_bandeja' AS codigo, 'propuestas' AS modulo
UNION ALL SELECT 4, 'Ver el seguimiento comercial de todas las áreas',
                 'propuesta_seguimiento_todas', 'propuestas'
) a
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra x WHERE x.IdMaestro = 88 AND x.IdEmpresa = 1 AND x.String2 = a.codigo);
