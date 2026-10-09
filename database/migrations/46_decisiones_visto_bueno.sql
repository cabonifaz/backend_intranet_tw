-- ============================================================
-- Migración 46 — HU-15: Emisión de Decisiones (Aprobar, Rechazar, Corregir)
--   Complementa la migración 45 (SP_ResolverVistoBueno de HU-13/14).
--   1. visto_bueno: motivo del rechazo (MOTIVO_RECHAZO, IdMaestro 10) y
--      validaciones confirmadas al aprobar (JSON con los códigos marcados).
--   2. propuesta_correccion: cada solicitud de corrección con sus áreas,
--      observaciones, responsable y fecha límite. La propuesta vuelve a
--      borrador y queda "en corrección" mientras la solicitud esté pendiente.
--      Al reenviarla a visto bueno la solicitud pasa a atendida.
--   3. Catálogos (configurables desde tabla_maestra):
--        VALIDACION_APROBACION_VB   casillas que el aprobador debe confirmar
--                                   String1 = texto, String2 = código, Num2 = 1 obligatoria
--        AREA_CORRECCION_PROPUESTA  áreas que se pueden marcar para corregir
--                                   String1 = etiqueta, String2 = código
--   4. Parámetro CORRECCION_PLAZO_HORAS (horas hábiles) para sugerir la fecha límite.
--   IDEMPOTENTE. Sin punto y coma dentro de los comentarios.
-- ============================================================

-- 1. visto_bueno
SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE()
                           AND TABLE_NAME = 'visto_bueno' AND COLUMN_NAME = 'id_motivo_rechazo'),
    'ALTER TABLE visto_bueno ADD COLUMN id_motivo_rechazo INT NULL AFTER comentario_respuesta', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE()
                           AND TABLE_NAME = 'visto_bueno' AND COLUMN_NAME = 'validaciones_confirmadas'),
    'ALTER TABLE visto_bueno ADD COLUMN validaciones_confirmadas JSON NULL AFTER id_motivo_rechazo', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- 2. propuesta_correccion
CREATE TABLE IF NOT EXISTS propuesta_correccion (
    id_correccion     BIGINT        NOT NULL AUTO_INCREMENT,
    id_propuesta      BIGINT        NOT NULL,
    id_vb             BIGINT        NULL,
    areas             JSON          NOT NULL,
    observaciones     TEXT          NOT NULL,
    id_responsable    BIGINT        NULL,
    fecha_limite      DATETIME      NOT NULL,
    estado            ENUM('pendiente','atendida','cancelada') NOT NULL DEFAULT 'pendiente',
    atendida_en       DATETIME      NULL,
    solicitado_por    BIGINT        NOT NULL,
    creado_en         DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    eliminado_en      DATETIME      NULL,
    PRIMARY KEY (id_correccion),
    KEY ix_correccion_propuesta (id_propuesta, estado)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- 3a. VALIDACION_APROBACION_VB
SET @id_val := (SELECT MAX(IdMaestro) FROM tabla_maestra WHERE Descripcion = 'VALIDACION_APROBACION_VB');
SET @id_val := IFNULL(@id_val, (SELECT MAX(IdMaestro) + 1 FROM tabla_maestra));

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, Num2, String1, String2)
SELECT 1, @id_val, 'VALIDACION_APROBACION_VB', v.orden, 1, v.texto, v.codigo
FROM (
          SELECT 1 AS orden, 'Verificación de disponibilidad de stock confirmada.' AS texto, 'stock_confirmado' AS codigo
UNION ALL SELECT 2,        'Términos comerciales y plazos de entrega validados.',          'terminos_validados'
) v
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra x WHERE x.Descripcion = 'VALIDACION_APROBACION_VB' AND x.String2 = v.codigo);

-- 3b. AREA_CORRECCION_PROPUESTA
SET @id_area := (SELECT MAX(IdMaestro) FROM tabla_maestra WHERE Descripcion = 'AREA_CORRECCION_PROPUESTA');
SET @id_area := IFNULL(@id_area, (SELECT MAX(IdMaestro) + 1 FROM tabla_maestra));

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2)
SELECT 1, @id_area, 'AREA_CORRECCION_PROPUESTA', a.orden, a.etiqueta, a.codigo
FROM (
          SELECT 1 AS orden, 'Configuración' AS etiqueta, 'configuracion' AS codigo
UNION ALL SELECT 2, 'Ítems y precios',  'items'
UNION ALL SELECT 3, 'Descuento',        'descuento'
UNION ALL SELECT 4, 'Detalle',          'detalle'
UNION ALL SELECT 5, 'Forma de Pago',    'forma_pago'
UNION ALL SELECT 6, 'Condiciones',      'condiciones'
UNION ALL SELECT 7, 'Equipos',          'equipos'
UNION ALL SELECT 8, 'Documentos',       'documentos'
) a
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra x WHERE x.Descripcion = 'AREA_CORRECCION_PROPUESTA' AND x.String2 = a.codigo);

-- 4. Parámetro de plazo sugerido para la corrección
SET @id_param := (SELECT MAX(IdMaestro) FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROPUESTA');

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, Num2, String1, String2)
SELECT 1, @id_param, 'PARAMETRO_PROPUESTA', 20, 8,
       'Plazo sugerido para atender una corrección (horas hábiles)', 'CORRECCION_PLAZO_HORAS'
FROM DUAL
WHERE @id_param IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROPUESTA' AND String2 = 'CORRECCION_PLAZO_HORAS');
