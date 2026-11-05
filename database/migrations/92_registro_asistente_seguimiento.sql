-- ============================================================
-- Migración 92 — Registro Operativo del Asistente de Seguimiento (HU-53, Sprint 5)
--   El Asistente registra desde la intranet, en nombre del técnico, cuando este no puede hacerlo desde su app móvil:
--   modo 1 Observación / Nota · modo 2 Demora / Incidente · modo 3 Cambio de estado del servicio (crítico).
--   1. registro_asistente: bitácora de los 3 modos (quién, cuándo, modo, datos). Es la única tabla nueva que se escribe.
--   2. Catálogos en tabla_maestra: TIPO_DEMORA_INCIDENTE (9 tipos) y MOTIVO_CAMBIO_MANUAL (5 motivos). IdMaestro nuevo (siguiente libre).
--   3. Hito "Ingreso a planta" (INGRESO_PLANTA) en TIPO_EVENTO_CAMPO, si el catálogo existe.
--   4. Acciones: seg_registrar (nivel 2 = editar: puede registrar) y seg_alerta_registro (nivel 3 = supervisar: recibe la notificación).
--   No borra ni cambia datos existentes. IDEMPOTENTE. Requiere las migraciones 90 y 91 (HU-51 y HU-52).
-- ============================================================

-- ── 1. Bitácora de registros del Asistente ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS registro_asistente (
    id_registro     BIGINT        NOT NULL AUTO_INCREMENT,
    id_os           BIGINT        NOT NULL,
    modo            ENUM('observacion','demora','cambio_estado') NOT NULL,
    id_usuario      BIGINT        NOT NULL,
    id_tecnico      BIGINT        NULL,
    descripcion     VARCHAR(1000) NOT NULL,
    fuente          VARCHAR(30)   NULL,
    vinculo_clave   VARCHAR(30)   NULL,
    id_tipo         INT           NULL,
    duracion_min    INT           NULL,
    impacto         ENUM('retrasa','detiene') NULL,
    evidencia_url   VARCHAR(500)  NULL,
    estado_anterior VARCHAR(20)   NULL,
    estado_nuevo    VARCHAR(20)   NULL,
    id_motivo       INT           NULL,
    id_evento_campo BIGINT        NULL,
    fecha_utc       DATETIME      NOT NULL,
    creado_en       DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id_registro),
    KEY ix_registro_asistente_os (id_os, fecha_utc),
    KEY ix_registro_asistente_usuario (id_usuario, fecha_utc)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ── 2. Catálogos (IdMaestro nuevo = siguiente libre; se reutiliza si ya existe) ────────────
SET @id_tipo := (SELECT MAX(IdMaestro) FROM tabla_maestra WHERE Descripcion = 'TIPO_DEMORA_INCIDENTE');
SET @id_tipo := IFNULL(@id_tipo, (SELECT MAX(IdMaestro) + 1 FROM tabla_maestra));
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2)
SELECT 1, @id_tipo, 'TIPO_DEMORA_INCIDENTE', x.n, x.nombre, x.codigo
FROM (SELECT 1 AS n, 'Tráfico' AS nombre, 'TRAFICO' AS codigo UNION ALL SELECT 2, 'Accidente propio', 'ACCIDENTE_PROPIO' UNION ALL
      SELECT 3, 'Accidente ajeno', 'ACCIDENTE_AJENO' UNION ALL SELECT 4, 'Falla vehículo', 'FALLA_VEHICULO' UNION ALL
      SELECT 5, 'Clima adverso', 'CLIMA_ADVERSO' UNION ALL SELECT 6, 'Cliente no disponible', 'CLIENTE_NO_DISPONIBLE' UNION ALL
      SELECT 7, 'Problema de acceso', 'PROBLEMA_ACCESO' UNION ALL SELECT 8, 'Falta repuesto', 'FALTA_REPUESTO' UNION ALL
      SELECT 9, 'Otros', 'OTROS') x
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra t WHERE t.Descripcion = 'TIPO_DEMORA_INCIDENTE' AND t.IdEmpresa = 1 AND t.String2 = x.codigo);

SET @id_motivo := (SELECT MAX(IdMaestro) FROM tabla_maestra WHERE Descripcion = 'MOTIVO_CAMBIO_MANUAL');
SET @id_motivo := IFNULL(@id_motivo, (SELECT MAX(IdMaestro) + 1 FROM tabla_maestra));
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2)
SELECT 1, @id_motivo, 'MOTIVO_CAMBIO_MANUAL', x.n, x.nombre, x.codigo
FROM (SELECT 1 AS n, 'Celular robado / perdido' AS nombre, 'CELULAR_ROBADO' AS codigo UNION ALL
      SELECT 2, 'Batería agotada sin posibilidad de carga', 'BATERIA_AGOTADA' UNION ALL
      SELECT 3, 'Equipo dañado (celular roto)', 'EQUIPO_DANADO' UNION ALL
      SELECT 4, 'App móvil con error técnico', 'APP_ERROR' UNION ALL
      SELECT 5, 'Otro (especificar en comentario)', 'OTRO') x
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra t WHERE t.Descripcion = 'MOTIVO_CAMBIO_MANUAL' AND t.IdEmpresa = 1 AND t.String2 = x.codigo);

-- ── 3. Hito "Ingreso a planta" (solo si ya existe el catálogo de eventos de campo) ────────
SET @id_evt := (SELECT MAX(IdMaestro) FROM tabla_maestra WHERE Descripcion = 'TIPO_EVENTO_CAMPO' AND IdEmpresa = 1);
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2)
SELECT 1, @id_evt, 'TIPO_EVENTO_CAMPO', (SELECT MAX(t2.Num1) + 1 FROM tabla_maestra t2 WHERE t2.Descripcion = 'TIPO_EVENTO_CAMPO' AND t2.IdEmpresa = 1),
       'Ingreso a planta', 'INGRESO_PLANTA'
FROM (SELECT 1) u
WHERE @id_evt IS NOT NULL AND NOT EXISTS (SELECT 1 FROM tabla_maestra t WHERE t.Descripcion = 'TIPO_EVENTO_CAMPO' AND t.IdEmpresa = 1 AND t.String2 = 'INGRESO_PLANTA');

-- ── 4. Acciones (88 ACCION_SISTEMA: Num1 = nivel, String3 = módulo) ───────────────────────
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2, String3)
SELECT 1, 88, 'ACCION_SISTEMA', 2, 'Registrar observaciones, demoras y cambios de estado en nombre del técnico (seguimiento operativo)', 'seg_registrar', 'operaciones'
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra t WHERE t.IdMaestro = 88 AND t.IdEmpresa = 1 AND t.String2 = 'seg_registrar');
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2, String3)
SELECT 1, 88, 'ACCION_SISTEMA', 3, 'Recibir la notificación de demoras que detienen y cambios manuales críticos del seguimiento operativo', 'seg_alerta_registro', 'operaciones'
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra t WHERE t.IdMaestro = 88 AND t.IdEmpresa = 1 AND t.String2 = 'seg_alerta_registro');

-- ── Verificación ─────────────────────────────────────────────────────────────
SELECT 'Migración 92 (debe ser 17)' AS verificacion,
       (SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'registro_asistente')
     + (SELECT COUNT(*) FROM tabla_maestra WHERE Descripcion = 'TIPO_DEMORA_INCIDENTE' AND IdEmpresa = 1)
     + (SELECT COUNT(*) FROM tabla_maestra WHERE Descripcion = 'MOTIVO_CAMBIO_MANUAL' AND IdEmpresa = 1)
     + (SELECT COUNT(*) FROM tabla_maestra WHERE IdMaestro = 88 AND IdEmpresa = 1 AND String2 IN ('seg_registrar', 'seg_alerta_registro')) AS valor;
