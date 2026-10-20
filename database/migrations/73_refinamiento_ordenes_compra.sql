-- ============================================================
-- Migración 73 — Refinamiento del módulo de Órdenes de Compra (Sprint 4, HU-22 a HU-28)
--
--   1. orden_compra: estados nuevos RECIBIDA / VALIDADA / VALIDADA_PARCIAL / OBSERVADA / ANULADA
--      (consolidado de las vinculaciones), datos que extrae la IA (RUC y razón social de la OC, N° de
--      propuesta referenciada, condición de pago, IGV, descuento, conceptos), checkbox "¿La factura
--      tendrá lo mismo que la OC?", OC autogenerada (OC-AUTO) y su reemplazo, y anulación con motivo.
--   2. oc_propuesta: estado de validación por vinculación (pendiente, validada, observada), tipo de
--      observación (informativa, corrección del cliente, nueva versión de propuesta) y la versión nueva.
--   3. orden_compra_validacion: cada corrida de la validación contra una propuesta (historial del modal IA).
--   4. Catálogo MOTIVO_ANULACION_OC (102) y acción oc_anular.
--   5. Se elimina lo que ya no está en el refinamiento: OC complementaria, distribución de saldo,
--      liberación a programación, observación con motivos (tablas orden_compra_observacion*),
--      vigencia en días y montos aplicados calculados. Las OC existentes pasan al estado nuevo.
--
--   IDEMPOTENTE. Se puede re-ejecutar.
-- ============================================================

DROP PROCEDURE IF EXISTS _m73_agregar_columna;
DROP PROCEDURE IF EXISTS _m73_quitar_columna;

DELIMITER $$

CREATE PROCEDURE _m73_agregar_columna(IN p_tabla VARCHAR(64), IN p_columna VARCHAR(64), IN p_definicion VARCHAR(500))
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                   WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = p_tabla AND COLUMN_NAME = p_columna) THEN
        SET @m73_sql = CONCAT('ALTER TABLE ', p_tabla, ' ADD COLUMN ', p_columna, ' ', p_definicion);
        PREPARE st FROM @m73_sql; EXECUTE st; DEALLOCATE PREPARE st;
    END IF;
END$$

CREATE PROCEDURE _m73_quitar_columna(IN p_tabla VARCHAR(64), IN p_columna VARCHAR(64))
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.COLUMNS
               WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = p_tabla AND COLUMN_NAME = p_columna) THEN
        SET @m73_sql = CONCAT('ALTER TABLE ', p_tabla, ' DROP COLUMN ', p_columna);
        PREPARE st FROM @m73_sql; EXECUTE st; DEALLOCATE PREPARE st;
    END IF;
END$$

DELIMITER ;

-- ── 1. orden_compra: columnas nuevas ───────────────────────────────────────
CALL _m73_agregar_columna('orden_compra', 'es_autogenerada',     'TINYINT(1) NOT NULL DEFAULT 0 AFTER numero_oc');
CALL _m73_agregar_columna('orden_compra', 'id_oc_reemplazada',   'BIGINT NULL AFTER es_autogenerada');
CALL _m73_agregar_columna('orden_compra', 'reemplazada_por',     'BIGINT NULL AFTER id_oc_reemplazada');
CALL _m73_agregar_columna('orden_compra', 'fecha_reemplazo',     'DATETIME NULL AFTER reemplazada_por');
CALL _m73_agregar_columna('orden_compra', 'ruc_cliente_oc',      'VARCHAR(11) NULL AFTER id_cliente');
CALL _m73_agregar_columna('orden_compra', 'razon_social_oc',     'VARCHAR(300) NULL AFTER ruc_cliente_oc');
CALL _m73_agregar_columna('orden_compra', 'numero_propuesta_ref','VARCHAR(50) NULL AFTER razon_social_oc');
CALL _m73_agregar_columna('orden_compra', 'id_condicion_pago',   'INT NULL AFTER monto_total');
CALL _m73_agregar_columna('orden_compra', 'forma_pago',          'VARCHAR(150) NULL AFTER id_condicion_pago');
CALL _m73_agregar_columna('orden_compra', 'igv_incluido',        'TINYINT(1) NULL AFTER forma_pago');
CALL _m73_agregar_columna('orden_compra', 'igv_pct',             'DECIMAL(5,2) NULL AFTER igv_incluido');
CALL _m73_agregar_columna('orden_compra', 'descuento_monto',     'DECIMAL(14,2) NULL AFTER igv_pct');
CALL _m73_agregar_columna('orden_compra', 'factura_igual_oc',    'TINYINT(1) NOT NULL DEFAULT 1 AFTER descuento_monto');
CALL _m73_agregar_columna('orden_compra', 'conceptos',           'JSON NULL AFTER observaciones');
CALL _m73_agregar_columna('orden_compra', 'campos_ia',           'JSON NULL AFTER conceptos');
CALL _m73_agregar_columna('orden_compra', 'campos_manuales',     'JSON NULL AFTER campos_ia');
CALL _m73_agregar_columna('orden_compra', 'id_motivo_anulacion', 'INT NULL AFTER estado');
CALL _m73_agregar_columna('orden_compra', 'justificacion_anulacion', 'VARCHAR(1000) NULL AFTER id_motivo_anulacion');
CALL _m73_agregar_columna('orden_compra', 'fecha_anulacion',     'DATETIME NULL AFTER justificacion_anulacion');
CALL _m73_agregar_columna('orden_compra', 'anulado_por',         'BIGINT NULL AFTER fecha_anulacion');

-- ── 2. oc_propuesta: estado por vinculación ────────────────────────────────
CALL _m73_agregar_columna('oc_propuesta', 'estado_validacion',
     'ENUM(''pendiente'',''validada'',''observada'') NOT NULL DEFAULT ''pendiente'' AFTER monto_asignado');
CALL _m73_agregar_columna('oc_propuesta', 'tipo_observacion',
     'ENUM(''informativa'',''correccion_cliente'',''nueva_version'') NULL AFTER estado_validacion');
CALL _m73_agregar_columna('oc_propuesta', 'resultado_ia',
     'ENUM(''ok'',''advertencia'',''critico'') NULL AFTER tipo_observacion');
CALL _m73_agregar_columna('oc_propuesta', 'id_validacion',             'BIGINT NULL AFTER resultado_ia');
CALL _m73_agregar_columna('oc_propuesta', 'id_propuesta_nueva_version','BIGINT NULL AFTER id_validacion');
CALL _m73_agregar_columna('oc_propuesta', 'fecha_decision',            'DATETIME NULL AFTER id_propuesta_nueva_version');
CALL _m73_agregar_columna('oc_propuesta', 'decidido_por',              'BIGINT NULL AFTER fecha_decision');

-- ── 3. Historial de validaciones (modal "Detalle de Validación IA") ────────
CREATE TABLE IF NOT EXISTS orden_compra_validacion (
    id_validacion   BIGINT       NOT NULL AUTO_INCREMENT,
    id_oc           BIGINT       NOT NULL,
    id_propuesta    BIGINT       NOT NULL,
    corrida         INT          NOT NULL,             -- 1, 2, 3… por OC y propuesta
    origen          VARCHAR(30)  NOT NULL,             -- registro, edicion, reemplazo_pdf, oc_corregida, revalidacion, validar_contra_propuesta
    resultado       ENUM('ok','advertencia','critico') NOT NULL,
    coincidencias   INT          NOT NULL DEFAULT 0,
    advertencias    INT          NOT NULL DEFAULT 0,
    criticas        INT          NOT NULL DEFAULT 0,
    total_campos    INT          NOT NULL DEFAULT 0,
    detalle         JSON         NULL,                 -- [{campo, etiqueta, valor_oc, valor_propuesta, severidad, mensaje, accion}]
    conceptos       JSON         NULL,                 -- [{descripcion, monto_oc, monto_propuesta, estado}]
    dictamen        TEXT         NULL,
    insights        JSON         NULL,                 -- [{campo, titulo, explicacion, accion, recomendado}]
    confianza       DECIMAL(5,2) NULL,
    motor           VARCHAR(80)  NULL,                 -- reglas / gemini-x
    sugerencia      VARCHAR(30)  NULL,                 -- validar, correccion_cliente, nueva_version
    fecha_validacion DATETIME    NOT NULL,
    id_usuario      BIGINT       NULL,
    creado_en       DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por      BIGINT       NULL,
    modificado_en   DATETIME     NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por  BIGINT       NULL,
    eliminado_en    DATETIME     NULL,
    eliminado_por   BIGINT       NULL,
    PRIMARY KEY (id_validacion)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ── 4. Datos existentes: estado nuevo de cada vinculación y de la OC ───────
-- (solo mientras aún existen las columnas y tablas antiguas)
SET @m73_estado_antiguo := (SELECT COUNT(*) FROM information_schema.COLUMNS
                            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'orden_compra'
                              AND COLUMN_NAME = 'estado' AND COLUMN_TYPE LIKE '%pendiente_validacion%');
SET @m73_hay_obs := (SELECT COUNT(*) FROM information_schema.TABLES
                     WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'orden_compra_observacion');

-- a. La propuesta principal de cada OC debe estar en oc_propuesta (la migración 69 ya lo hizo; por si acaso)
SET @sql := IF(@m73_estado_antiguo > 0,
    'INSERT INTO oc_propuesta (id_oc, id_propuesta, monto_asignado, creado_por)
     SELECT oc.id_oc, oc.id_propuesta, oc.monto_total, oc.creado_por
     FROM orden_compra oc
     WHERE oc.id_propuesta IS NOT NULL AND oc.eliminado_en IS NULL
       AND NOT EXISTS (SELECT 1 FROM oc_propuesta op WHERE op.id_oc = oc.id_oc AND op.id_propuesta = oc.id_propuesta
                         AND op.eliminado_en IS NULL)',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- b. Vinculaciones de OC validadas → validada
SET @sql := IF(@m73_estado_antiguo > 0,
    'UPDATE oc_propuesta op JOIN orden_compra oc ON oc.id_oc = op.id_oc
     SET op.estado_validacion = ''validada'', op.fecha_decision = IFNULL(oc.modificado_en, oc.fecha_registro),
         op.decidido_por = IFNULL(oc.id_validado_por, oc.creado_por)
     WHERE oc.estado IN (''vigente'', ''cobertura_parcial'', ''saldo_insuficiente'', ''vencida'')',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- c. OC con una observación abierta → observada, pendiente de corrección del cliente
SET @sql := IF(@m73_estado_antiguo > 0 AND @m73_hay_obs > 0,
    'UPDATE oc_propuesta op
     SET op.estado_validacion = ''observada'', op.tipo_observacion = ''correccion_cliente''
     WHERE EXISTS (SELECT 1 FROM orden_compra_observacion ob
                   WHERE ob.id_oc = op.id_oc AND ob.estado = ''abierta'' AND ob.eliminado_en IS NULL)',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- d. La observación abierta queda en el detalle de la OC como texto (para no perder el motivo)
SET @sql := IF(@m73_estado_antiguo > 0 AND @m73_hay_obs > 0,
    'UPDATE orden_compra oc
     JOIN (SELECT ob.id_oc, GROUP_CONCAT(ob.detalle ORDER BY ob.id_observacion SEPARATOR '' / '') AS detalle
           FROM orden_compra_observacion ob WHERE ob.estado = ''abierta'' AND ob.eliminado_en IS NULL
           GROUP BY ob.id_oc) x ON x.id_oc = oc.id_oc
     SET oc.observaciones = LEFT(CONCAT(IFNULL(CONCAT(oc.observaciones, '' | ''), ''''), ''Observación: '', x.detalle), 500)',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- e. Estado de la OC: el ENUM pasa por un conjunto con los dos juegos de valores y luego queda solo el nuevo
SET @sql := IF(@m73_estado_antiguo > 0,
    'ALTER TABLE orden_compra MODIFY COLUMN estado ENUM(''pendiente_validacion'',''vigente'',''cobertura_parcial'',
        ''saldo_insuficiente'',''vencida'',''anulada'',''recibida'',''validada'',''validada_parcial'',''observada'') NOT NULL',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

UPDATE orden_compra oc
SET oc.estado = CASE
        WHEN oc.estado = 'anulada' THEN 'anulada'
        WHEN NOT EXISTS (SELECT 1 FROM oc_propuesta op WHERE op.id_oc = oc.id_oc AND op.eliminado_en IS NULL
                           AND op.estado_validacion <> 'validada') THEN 'validada'
        WHEN EXISTS (SELECT 1 FROM oc_propuesta op WHERE op.id_oc = oc.id_oc AND op.eliminado_en IS NULL
                       AND op.estado_validacion = 'validada') THEN 'validada_parcial'
        ELSE 'observada'
    END
WHERE oc.estado IN ('pendiente_validacion', 'vigente', 'cobertura_parcial', 'saldo_insuficiente', 'vencida', 'anulada');

SET @sql := IF(EXISTS (SELECT 1 FROM information_schema.COLUMNS
                       WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'orden_compra'
                         AND COLUMN_NAME = 'estado' AND COLUMN_TYPE LIKE '%pendiente_validacion%'),
    'ALTER TABLE orden_compra MODIFY COLUMN estado ENUM(''recibida'',''validada'',''validada_parcial'',''observada'',''anulada'') NOT NULL',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- f. Condición de pago y IGV de las OC existentes: se toman de la propuesta (antes no se registraban)
UPDATE orden_compra oc
JOIN propuesta_comercial p ON p.id_propuesta = oc.id_propuesta
SET oc.id_condicion_pago = IFNULL(oc.id_condicion_pago, p.id_condicion_pago),
    oc.igv_incluido      = IFNULL(oc.igv_incluido, p.aplica_igv),
    oc.igv_pct           = IFNULL(oc.igv_pct, IF(p.aplica_igv = 1, p.igv_pct, NULL))
WHERE oc.id_condicion_pago IS NULL OR oc.igv_incluido IS NULL;

-- g. Bloqueos del expediente que abrió la observación antigua de la OC: quedan resueltos
SET @sql := IF(@m73_hay_obs > 0,
    'UPDATE expediente_bloqueador
     SET resuelto = 1, sustento = IFNULL(sustento, ''Migración 73: la observación de la OC pasa al estado de la vinculación.''),
         fecha_resolucion = IFNULL(fecha_resolucion, NOW())
     WHERE origen_tipo = ''orden_compra'' AND resuelto = 0 AND eliminado_en IS NULL',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- ── 5. Se elimina lo que ya no está en el refinamiento ─────────────────────
CALL _m73_quitar_columna('orden_compra', 'tipo_oc');
CALL _m73_quitar_columna('orden_compra', 'id_oc_origen');
CALL _m73_quitar_columna('orden_compra', 'fecha_liberacion');
CALL _m73_quitar_columna('orden_compra', 'liberado_por');
CALL _m73_quitar_columna('orden_compra', 'monto_aplicado');
CALL _m73_quitar_columna('orden_compra', 'saldo');
CALL _m73_quitar_columna('orden_compra', 'cobertura_pct');
CALL _m73_quitar_columna('orden_compra', 'id_motivo_observacion');
CALL _m73_quitar_columna('orden_compra', 'id_validado_por');
CALL _m73_quitar_columna('orden_compra', 'vigencia_desde');
CALL _m73_quitar_columna('orden_compra', 'vigencia_dias');

DROP TABLE IF EXISTS orden_compra_observacion_motivo;
DROP TABLE IF EXISTS orden_compra_observacion;

-- Catálogo de motivos de observación de OC y parámetros de vigencia/tolerancia: de baja
UPDATE tabla_maestra SET eliminado_en = NOW()
WHERE IdEmpresa = 1 AND eliminado_en IS NULL
  AND (IdMaestro = 14
       OR (Descripcion = 'PARAMETRO_PROPUESTA' AND String2 IN ('OC_VIGENCIA_DIAS_DEFECTO', 'OC_TOLERANCIA_MONTO_PCT')));

-- Acciones de distribución y liberación: de baja (FN_PermisoAccion ya no las encuentra)
DELETE FROM tabla_maestra WHERE IdMaestro = 88 AND IdEmpresa = 1 AND String2 IN ('oc_distribuir', 'oc_liberar');

-- ── 6. Catálogos y acciones nuevas ─────────────────────────────────────────
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2)
SELECT 1, 102, 'MOTIVO_ANULACION_OC', x.n, x.nombre, x.codigo
FROM (SELECT 1 AS n, 'OC duplicada' AS nombre, 'DUPLICADA' AS codigo
      UNION ALL SELECT 2, 'Error de registro', 'ERROR_REGISTRO'
      UNION ALL SELECT 3, 'Cancelada por el cliente', 'CANCELADA_CLIENTE'
      UNION ALL SELECT 4, 'Otro', 'OTRO') x
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra t WHERE t.IdMaestro = 102 AND t.IdEmpresa = 1 AND t.String2 = x.codigo);

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2, String3)
SELECT 1, 88, 'ACCION_SISTEMA', 3, 'Anular órdenes de compra', 'oc_anular', 'propuestas'
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra WHERE IdMaestro = 88 AND IdEmpresa = 1 AND String2 = 'oc_anular');

-- Re-validar ya no decide nada (solo vuelve a correr la validación): basta el nivel editar
UPDATE tabla_maestra SET String1 = 'Re-validar la orden de compra contra sus propuestas', Num1 = 2
WHERE IdMaestro = 88 AND IdEmpresa = 1 AND String2 = 'oc_validar';

DROP PROCEDURE IF EXISTS _m73_agregar_columna;
DROP PROCEDURE IF EXISTS _m73_quitar_columna;

-- ── 7. Procedimientos de los flujos eliminados ─────────────────────────────
DROP PROCEDURE IF EXISTS SP_EvaluarOrdenCompra;
DROP PROCEDURE IF EXISTS SP_EvaluarValidacionOrdenCompra;
DROP PROCEDURE IF EXISTS SP_PrepararValidacionOrdenCompra;
DROP PROCEDURE IF EXISTS SP_ValidarOrdenCompra;
DROP PROCEDURE IF EXISTS SP_ValidarOrdenCompraInterno;
DROP PROCEDURE IF EXISTS SP_ObservarOrdenCompra;
DROP PROCEDURE IF EXISTS SP_ObservarOrdenCompraInterno;
DROP PROCEDURE IF EXISTS SP_LevantarObservacionOrdenCompra;
DROP PROCEDURE IF EXISTS SP_LevantarObservacionOrdenCompraInterno;
DROP PROCEDURE IF EXISTS SP_PrepararDistribucionOrdenCompra;
DROP PROCEDURE IF EXISTS SP_DistribuirOrdenCompra;
DROP PROCEDURE IF EXISTS SP_DistribuirOrdenCompraInterno;
DROP PROCEDURE IF EXISTS SP_PrepararOcComplementaria;
DROP PROCEDURE IF EXISTS SP_RegistrarOcComplementaria;
DROP PROCEDURE IF EXISTS SP_RegistrarOcComplementariaInterno;
DROP PROCEDURE IF EXISTS SP_PrepararLiberacionOrdenCompra;
DROP PROCEDURE IF EXISTS SP_EvaluarLiberacionOrdenCompra;
DROP PROCEDURE IF EXISTS SP_LiberarOrdenCompra;
DROP PROCEDURE IF EXISTS SP_LiberarOrdenCompraInterno;
DROP PROCEDURE IF EXISTS SP_ObtenerDocumentosOrdenCompra;
DROP PROCEDURE IF EXISTS SP_ObtenerVersionDocumentoOrdenCompra;
DROP PROCEDURE IF EXISTS SP_AgregarVersionDocumentoOc;
DROP PROCEDURE IF EXISTS SP_ObtenerPropuestasSinOrdenCompra;
