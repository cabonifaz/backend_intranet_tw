-- ============================================================
-- Migración 127 — HU-55: registrar el informe de un equipo desde la intranet (Asistente de Seguimiento / Jefe de Operaciones)
--   Cuando el cliente no deja usar celular en planta, el trabajo del técnico en un equipo lo registra la intranet EN NOMBRE DEL TÉCNICO
--   (variables, evidencias, ensayos, cabecera, correlativo, cierre y generar informe). El informe queda a nombre del técnico asignado y se guarda quién lo registró.
--   1. informe_tecnico: id_registrado_por (quién lo registró de verdad), via ('app' | 'intranet', por defecto 'app') y registrado_en (UTC, la primera vez que se registró desde
--      la intranet). NO se toca el ENUM `origen` de las tablas hijas: los filtros origen = 'tecnico' del Hard Stop, la cabecera y los ensayos dejarían de ver lo registrado.
--      Los informes anteriores quedan con via = 'app' e id_registrado_por = NULL.
--   2. registro_informe_intranet: la sesión de registro de un equipo (bloqueo entre quienes registran desde la intranet; caduca a los 30 min sin actividad) con las horas de
--      inicio y fin del trabajo que indicó quien registra y el motivo. Una sesión activa por equipo.
--   3. Catálogo MOTIVO_CAMBIO_MANUAL: código nuevo PLANTA_SIN_CELULAR («Planta no permite celular»). Requiere la migración 92 (si el catálogo no existe, no inserta nada).
--   4. Acción seg_registrar_informe (88 ACCION_SISTEMA, nivel 2 = editar, módulo operaciones): el mismo patrón que seg_registrar; la matriz permiso_area_rol ya da el acceso por nivel.
--   No borra ni cambia datos existentes. IDEMPOTENTE.
-- ============================================================

-- ── 1. informe_tecnico: quién lo registró y por qué vía ─────────────────────────────────────
SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'informe_tecnico' AND COLUMN_NAME = 'id_registrado_por'),
    'ALTER TABLE informe_tecnico ADD COLUMN id_registrado_por BIGINT NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'informe_tecnico' AND COLUMN_NAME = 'via'),
    'ALTER TABLE informe_tecnico ADD COLUMN via ENUM(''app'',''intranet'') NOT NULL DEFAULT ''app''', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'informe_tecnico' AND COLUMN_NAME = 'registrado_en'),
    'ALTER TABLE informe_tecnico ADD COLUMN registrado_en DATETIME NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- ── 2. Sesión de registro desde la intranet (bloqueo por equipo) ────────────────────────────
CREATE TABLE IF NOT EXISTS registro_informe_intranet (
    id_registro         BIGINT       NOT NULL AUTO_INCREMENT,
    id_os               BIGINT       NOT NULL,
    id_os_equipo        BIGINT       NOT NULL,
    id_tecnico          BIGINT       NOT NULL,
    id_registrador      BIGINT       NOT NULL,
    inicio_utc          DATETIME     NOT NULL,
    fin_utc             DATETIME     NOT NULL,
    tiempo_aplicado_seg INT          NULL,
    motivo_codigo       VARCHAR(40)  NOT NULL,
    comentario          VARCHAR(300) NULL,
    estado              ENUM('activo','liberado','caducado','cerrado') NOT NULL DEFAULT 'activo',
    tomado_en           DATETIME     NOT NULL,
    ultima_actividad    DATETIME     NOT NULL,
    liberado_en         DATETIME     NULL,
    creado_en           DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id_registro),
    KEY ix_rii_equipo (id_os_equipo, estado),
    KEY ix_rii_registrador (id_registrador, estado)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ── 3. Motivo «Planta no permite celular» (se agrega al catálogo MOTIVO_CAMBIO_MANUAL de la migración 92) ──
SET @id_motivo := (SELECT MAX(IdMaestro) FROM tabla_maestra WHERE Descripcion = 'MOTIVO_CAMBIO_MANUAL' AND IdEmpresa = 1);
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2)
SELECT 1, @id_motivo, 'MOTIVO_CAMBIO_MANUAL',
       (SELECT MAX(t2.Num1) + 1 FROM tabla_maestra t2 WHERE t2.Descripcion = 'MOTIVO_CAMBIO_MANUAL' AND t2.IdEmpresa = 1),
       'Planta no permite celular', 'PLANTA_SIN_CELULAR'
FROM (SELECT 1) u
WHERE @id_motivo IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM tabla_maestra t WHERE t.Descripcion = 'MOTIVO_CAMBIO_MANUAL' AND t.IdEmpresa = 1 AND t.String2 = 'PLANTA_SIN_CELULAR');

-- ── 4. Acción (88 ACCION_SISTEMA: Num1 = nivel, String3 = módulo) ───────────────────────────
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2, String3)
SELECT 1, 88, 'ACCION_SISTEMA', 2, 'Registrar el informe técnico de un equipo desde la intranet, en nombre del técnico (HU-55)', 'seg_registrar_informe', 'operaciones'
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra t WHERE t.IdMaestro = 88 AND t.IdEmpresa = 1 AND t.String2 = 'seg_registrar_informe');

-- ── Verificación (solo lectura) ─────────────────────────────────────────────────────────────
SELECT 'Migración 127 (debe ser 6)' AS verificacion,
       (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'informe_tecnico' AND COLUMN_NAME IN ('id_registrado_por', 'via', 'registrado_en'))
     + (SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'registro_informe_intranet')
     + (SELECT COUNT(*) FROM tabla_maestra WHERE Descripcion = 'MOTIVO_CAMBIO_MANUAL' AND IdEmpresa = 1 AND String2 = 'PLANTA_SIN_CELULAR')
     + (SELECT COUNT(*) FROM tabla_maestra WHERE IdMaestro = 88 AND IdEmpresa = 1 AND String2 = 'seg_registrar_informe') AS valor;
