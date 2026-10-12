-- ============================================================
-- Migración 56 — HU-19 Registro de acciones de seguimiento (llamadas y correos)
--   1. seguimiento_comercial: id_contacto, duracion_minutos (llamadas), asunto (correos)
--   2. seguimiento_correo: correos de seguimiento (borrador, enviado o error)
--   3. plantilla_correo_seguimiento: plantillas predefinidas con variables
--        {{contacto}} {{numero_propuesta}} {{cliente}} {{referencia}}
--        {{usuario}} {{cargo_usuario}} {{fecha_envio}}
--   4. seguimiento_adjunto: documentos adjuntos (opcionales) de un seguimiento
--   5. CANAL_COMUNICACION (26): Num2 = 1 marca los tipos de seguimiento disponibles
--      (Llamada, Correo, WhatsApp, Visita y la nueva Reunión virtual)
--
--   IDEMPOTENTE. Se puede re-ejecutar.
-- ============================================================

-- 1. Columnas nuevas en seguimiento_comercial
SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'seguimiento_comercial'
                             AND COLUMN_NAME = 'id_contacto'),
    'ALTER TABLE seguimiento_comercial ADD COLUMN id_contacto BIGINT NULL AFTER id_responsable',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'seguimiento_comercial'
                             AND COLUMN_NAME = 'duracion_minutos'),
    'ALTER TABLE seguimiento_comercial ADD COLUMN duracion_minutos INT NULL AFTER fecha_interaccion',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'seguimiento_comercial'
                             AND COLUMN_NAME = 'asunto'),
    'ALTER TABLE seguimiento_comercial ADD COLUMN asunto VARCHAR(300) NULL AFTER notas',
    'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- 2. Correos de seguimiento
CREATE TABLE IF NOT EXISTS seguimiento_correo (
    id_correo           BIGINT          NOT NULL AUTO_INCREMENT,
    id_propuesta        BIGINT          NOT NULL,
    id_seguimiento      BIGINT          NULL,
    id_plantilla        INT             NULL,
    para                JSON            NOT NULL,
    cc                  JSON            NULL,
    asunto              VARCHAR(300)    NOT NULL,
    cuerpo_html         MEDIUMTEXT      NOT NULL,
    estado              ENUM('borrador','enviado','error') NOT NULL DEFAULT 'borrador',
    proveedor           VARCHAR(40)     NULL,
    id_mensaje          VARCHAR(200)    NULL,
    error               VARCHAR(500)    NULL,
    fecha_envio         DATETIME        NULL,
    id_usuario          BIGINT          NOT NULL,
    -- AUDITORÍA
    creado_en           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por          BIGINT          NULL,
    modificado_en       DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por      BIGINT          NULL,
    eliminado_en        DATETIME        NULL,
    eliminado_por       BIGINT          NULL,
    PRIMARY KEY (id_correo)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- 3. Plantillas de correo
CREATE TABLE IF NOT EXISTS plantilla_correo_seguimiento (
    id_plantilla        INT             NOT NULL AUTO_INCREMENT,
    codigo              VARCHAR(40)     NOT NULL,
    nombre              VARCHAR(100)    NOT NULL,
    asunto              VARCHAR(300)    NOT NULL,
    cuerpo_html         MEDIUMTEXT      NOT NULL,
    orden               INT             NOT NULL DEFAULT 1,
    activo              TINYINT(1)      NOT NULL DEFAULT 1,
    -- AUDITORÍA
    creado_en           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por          BIGINT          NULL,
    modificado_en       DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por      BIGINT          NULL,
    eliminado_en        DATETIME        NULL,
    eliminado_por       BIGINT          NULL,
    PRIMARY KEY (id_plantilla)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

INSERT INTO plantilla_correo_seguimiento (codigo, nombre, asunto, cuerpo_html, orden)
SELECT t.codigo, t.nombre, t.asunto, t.cuerpo, t.orden
FROM (
    SELECT 'SEGUIMIENTO_INICIAL' AS codigo, 'Seguimiento inicial' AS nombre,
           'Seguimiento Propuesta {{numero_propuesta}}' AS asunto,
           CONCAT('<p>Estimado(a) {{contacto}},</p>',
                  '<p>Espero que este correo le encuentre bien. Me pongo en contacto para realizar el seguimiento de la propuesta <strong>{{numero_propuesta}}</strong> enviada el {{fecha_envio}} para {{referencia}}.</p>',
                  '<p>Quisiera saber si ha tenido oportunidad de revisarla o si tiene alguna duda técnica que nuestro equipo pueda resolver.</p>',
                  '<p>Quedo a la espera de sus comentarios.</p>',
                  '<p>Saludos cordiales,<br><strong>{{usuario}}</strong><br>{{cargo_usuario}} | Total Weight</p>') AS cuerpo,
           1 AS orden
    UNION ALL
    SELECT 'RECORDATORIO', 'Recordatorio',
           'Recordatorio: Propuesta {{numero_propuesta}}',
           CONCAT('<p>Estimado(a) {{contacto}},</p>',
                  '<p>Le escribo para recordarle la propuesta <strong>{{numero_propuesta}}</strong> que le enviamos el {{fecha_envio}}.</p>',
                  '<p>Si necesita alguna aclaración o ajuste, con gusto lo coordinamos.</p>',
                  '<p>Saludos cordiales,<br><strong>{{usuario}}</strong><br>{{cargo_usuario}} | Total Weight</p>'),
           2
    UNION ALL
    SELECT 'ENVIO_AJUSTES', 'Envío de ajustes',
           'Propuesta {{numero_propuesta}} - ajustes solicitados',
           CONCAT('<p>Estimado(a) {{contacto}},</p>',
                  '<p>Según lo conversado, hemos realizado los ajustes solicitados a la propuesta <strong>{{numero_propuesta}}</strong>.</p>',
                  '<p>Quedamos atentos a su revisión y conformidad.</p>',
                  '<p>Saludos cordiales,<br><strong>{{usuario}}</strong><br>{{cargo_usuario}} | Total Weight</p>'),
           3
) t
WHERE NOT EXISTS (SELECT 1 FROM plantilla_correo_seguimiento x WHERE x.codigo = t.codigo);

-- 4. Adjuntos del seguimiento
CREATE TABLE IF NOT EXISTS seguimiento_adjunto (
    id_adjunto          BIGINT          NOT NULL AUTO_INCREMENT,
    id_seguimiento      BIGINT          NOT NULL,
    nombre_archivo      VARCHAR(255)    NOT NULL,
    ruta                VARCHAR(500)    NOT NULL,
    tipo_contenido      VARCHAR(100)    NOT NULL,
    tamano_bytes        BIGINT          NOT NULL,
    -- AUDITORÍA
    creado_en           DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por          BIGINT          NULL,
    modificado_en       DATETIME        NULL ON UPDATE CURRENT_TIMESTAMP,
    modificado_por      BIGINT          NULL,
    eliminado_en        DATETIME        NULL,
    eliminado_por       BIGINT          NULL,
    PRIMARY KEY (id_adjunto)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- 5. Tipos de seguimiento (CANAL_COMUNICACION con Num2 = 1)
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2)
SELECT 1, 26, 'CANAL_COMUNICACION', 8, 'Reunión virtual', 'REUNION'
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra WHERE IdMaestro = 26 AND IdEmpresa = 1 AND String2 = 'REUNION');

UPDATE tabla_maestra SET Num2 = 1
WHERE IdMaestro = 26 AND IdEmpresa = 1
  AND String2 IN ('LLAMADA', 'CORREO', 'WHATSAPP', 'VISITA', 'REUNION')
  AND IFNULL(Num2, 0) <> 1;
