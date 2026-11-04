-- ============================================================
-- Migración 86 — Programación de OS y asignación de recursos (HU-36, Sprint 5)
--   1. programacion ........... una fila por programación de una OS/OM (PRG-AAAA-NNNN). Una OS puede tener varias en el
--                               tiempo (si se cancela una, se crea otra) pero una sola activa a la vez: la regla la valida
--                               SP_CrearProgramacion (no hay UNIQUE por la convención del borrado lógico).
--   2. programacion_tecnico ... técnicos asignados (principal y apoyo) con su situación SSOMA al programar.
--   3. programacion_equipo .... equipos de la OS que se confirman para esta programación.
--   La programación también se refleja en la OS (técnico, fecha, horas, estado 'programada', os_personal) para que la
--   bandeja HU-35, el expediente y la agenda de la app móvil sigan leyendo la programación de la OS.
--   4. ssoma_requisito_documento ... equivalencia entre el requisito SSOMA que pide el cliente (REQUISITO_SSOMA, catálogo 48)
--                               y el tipo de documento que carga el técnico (TIPO_DOCUMENTO_SSOMA, catálogo 36). Se llena por código.
--   5. PARAMETRO_PROGRAMACION: SERVICIOS_MAX_DIA (4) · DIAS_POR_VENCER_SSOMA (30) · SSOMA_EXIGIR_DOCUMENTO (0).
--      SSOMA_EXIGIR_DOCUMENTO = 0 solo bloquea la evidencia negativa (vencido, observado, vence antes del servicio);
--      con 1 también bloquea que falte el documento de un requisito del cliente.
--   Acceso: acción prog_gestionar (migración 85). Reemplaza a las versiones anteriores 86 y 87 (si copió la 87, bórrela).
--   No borra ni cambia datos existentes. IDEMPOTENTE. Ejecutar junto con los SPs de este mismo paquete.
-- ============================================================

-- ── 1. Programación ───────────────────────────────────────────────────────────
-- estado: pendiente_confirmacion (recién creada, falta el OK del cliente) → confirmada | cancelada
CREATE TABLE IF NOT EXISTS programacion (
    id_programacion        BIGINT          NOT NULL AUTO_INCREMENT,
    codigo                 VARCHAR(20)     NOT NULL,
    id_os                  BIGINT          NOT NULL,
    estado                 ENUM('pendiente_confirmacion','confirmada','cancelada') NOT NULL DEFAULT 'pendiente_confirmacion',
    fecha_ejecucion        DATE            NOT NULL,
    hora_inicio            TIME            NOT NULL,
    hora_fin_estimada      TIME            NOT NULL,
    id_tecnico_principal   BIGINT          NOT NULL,
    observaciones          VARCHAR(500)    NULL,
    -- AUDITORÍA
    creado_en              DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por             BIGINT          NULL,
    modificado_en          DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por         BIGINT          NULL,
    eliminado_en           DATETIME        NULL,
    eliminado_por          BIGINT          NULL,
    PRIMARY KEY (id_programacion),
    KEY ix_programacion_os (id_os, estado),
    KEY ix_programacion_codigo (codigo)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ── 2. Técnicos de la programación ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS programacion_tecnico (
    id                     BIGINT          NOT NULL AUTO_INCREMENT,
    id_programacion        BIGINT          NOT NULL,
    id_usuario             BIGINT          NOT NULL,
    rol                    ENUM('principal','apoyo') NOT NULL DEFAULT 'apoyo',
    estado_ssoma           ENUM('conforme','por_vencer','incompleto','bloqueado') NOT NULL DEFAULT 'conforme',
    -- AUDITORÍA
    creado_en              DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por             BIGINT          NULL,
    modificado_en          DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por         BIGINT          NULL,
    eliminado_en           DATETIME        NULL,
    eliminado_por          BIGINT          NULL,
    PRIMARY KEY (id),
    KEY ix_programacion_tecnico_prog (id_programacion)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ── 3. Equipos de la programación ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS programacion_equipo (
    id                     BIGINT          NOT NULL AUTO_INCREMENT,
    id_programacion        BIGINT          NOT NULL,
    id_equipo              BIGINT          NOT NULL,
    -- AUDITORÍA
    creado_en              DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por             BIGINT          NULL,
    modificado_en          DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por         BIGINT          NULL,
    eliminado_en           DATETIME        NULL,
    eliminado_por          BIGINT          NULL,
    PRIMARY KEY (id),
    KEY ix_programacion_equipo_prog (id_programacion)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Bases que ya tenían la versión anterior de la tabla: se agrega 'incompleto' al estado SSOMA.
SET @sql := IF(EXISTS (SELECT 1 FROM information_schema.COLUMNS
                       WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'programacion_tecnico'
                         AND COLUMN_NAME = 'estado_ssoma' AND COLUMN_TYPE NOT LIKE '%incompleto%'),
    'ALTER TABLE programacion_tecnico MODIFY COLUMN estado_ssoma ENUM(''conforme'',''por_vencer'',''incompleto'',''bloqueado'') NOT NULL DEFAULT ''conforme''',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- ── 4. Equivalencia requisito del cliente ↔ tipo de documento SSOMA ──────────
CREATE TABLE IF NOT EXISTS ssoma_requisito_documento (
    id                  BIGINT          NOT NULL AUTO_INCREMENT,
    id_requisito        INT             NOT NULL,   -- Num1 de REQUISITO_SSOMA (catálogo 48)
    id_tipo_documento   INT             NOT NULL,   -- Num1 de TIPO_DOCUMENTO_SSOMA (catálogo 36)
    -- AUDITORÍA
    creado_en           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por          BIGINT          NULL,
    modificado_en       DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por      BIGINT          NULL,
    eliminado_en        DATETIME        NULL,
    eliminado_por       BIGINT          NULL,
    PRIMARY KEY (id),
    KEY ix_ssoma_requisito_documento_req (id_requisito)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

INSERT INTO ssoma_requisito_documento (id_requisito, id_tipo_documento)
SELECT r.Num1, d.Num1
FROM (SELECT 'sctr' AS req, 'SCTR' AS doc UNION ALL
      SELECT 'examen_medico',   'CERT_MEDICO' UNION ALL
      SELECT 'altura',          'PETAR'       UNION ALL
      SELECT 'epp',             'EPP'         UNION ALL
      SELECT 'induccion_ssoma', 'INDUCCION') m
JOIN tabla_maestra r ON r.IdMaestro = 48 AND r.IdEmpresa = 1 AND r.String2 = m.req
JOIN tabla_maestra d ON d.IdMaestro = 36 AND d.IdEmpresa = 1 AND d.String2 = m.doc
WHERE NOT EXISTS (SELECT 1 FROM ssoma_requisito_documento x
                  WHERE x.id_requisito = r.Num1 AND x.eliminado_en IS NULL);

-- ── 5. Parámetros de la programación (Num2 = valor) ─────────────────────────
SET @id_param := (SELECT MAX(IdMaestro) FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROGRAMACION');
SET @id_param := IFNULL(@id_param, (SELECT MAX(IdMaestro) + 1 FROM tabla_maestra));

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, Num2, String1, String2)
SELECT 1, @id_param, 'PARAMETRO_PROGRAMACION', x.n, x.valor, x.nombre, x.codigo
FROM (SELECT 3 AS n, 4 AS valor, 'Servicios máximos por técnico en un día (cupo del panel "Carga del día")'             AS nombre, 'SERVICIOS_MAX_DIA'         AS codigo UNION ALL
      SELECT 5,      30,         'Días después del servicio en que un documento SSOMA se considera por vencer',                  'DIAS_POR_VENCER_SSOMA'            UNION ALL
      SELECT 6,      0,          '1 = falta de documento de un requisito del cliente bloquea la programación; 0 = solo avisa',   'SSOMA_EXIGIR_DOCUMENTO') x
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra t WHERE t.Descripcion = 'PARAMETRO_PROGRAMACION' AND t.IdEmpresa = 1 AND t.String2 = x.codigo);

-- ── Verificación ─────────────────────────────────────────────────────────────
SELECT 'Migración 86 (debe ser 8)' AS verificacion,
       (SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME IN ('programacion', 'programacion_tecnico', 'programacion_equipo', 'ssoma_requisito_documento'))
     + (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'programacion_tecnico'
          AND COLUMN_NAME = 'estado_ssoma' AND COLUMN_TYPE LIKE '%incompleto%')
     + (SELECT COUNT(DISTINCT String2) FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROGRAMACION' AND IdEmpresa = 1
          AND String2 IN ('SERVICIOS_MAX_DIA', 'DIAS_POR_VENCER_SSOMA', 'SSOMA_EXIGIR_DOCUMENTO')) AS valor;
