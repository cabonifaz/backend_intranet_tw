-- ============================================================
-- Migración 101 — Registro fotográfico con validación IA, evidencia forzada y microvideo de encendido (App Mobile HU-11 / HU-12 / HU-13)
--   evidencia_fotografica (migración 01; id_equipo en la 91) pasa a guardar cada INTENTO de captura del panel de 9 evidencias de un equipo:
--     codigo ............ placa | inicial | encendido | desmontaje | abierto | prueba | final | informe | qr (SP_CatalogoEvidenciasMovil)
--     pagina ............ el informe a mano puede tener varias hojas (1, 2, 3…); las demás evidencias usan 1
--     es_video, duracion_seg ...... microvideo de encendido (HU-13: de 3 a 5 s)
--     precision_m ....... precisión del GPS al capturar (latitud y longitud ya existían)
--     intento ........... número de intento de ese codigo y página (1, 2, 3…); vigente = 1 solo en el último
--     motivo_rechazo_ia . por qué la IA rechazó la toma; resultado_ia = lo que leyó (JSON: datos de la placa, legibilidad del informe, display detectado…)
--     ruta_cuadro ....... cuadro de la imagen analizado por la IA en un video (también sirve de miniatura)
--     motivo_forzado, forzada_en ... HU-12: la toma rechazada que el técnico aceptó con un motivo escrito (override_aprobado e id_usuario_override ya existían)
--   No borra ni cambia datos existentes. IDEMPOTENTE. Requiere las migraciones 91, 98 y 99.
-- ============================================================

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'evidencia_fotografica' AND COLUMN_NAME = 'codigo'),
    'ALTER TABLE evidencia_fotografica ADD COLUMN codigo VARCHAR(20) NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'evidencia_fotografica' AND COLUMN_NAME = 'pagina'),
    'ALTER TABLE evidencia_fotografica ADD COLUMN pagina INT NOT NULL DEFAULT 1', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'evidencia_fotografica' AND COLUMN_NAME = 'es_video'),
    'ALTER TABLE evidencia_fotografica ADD COLUMN es_video TINYINT(1) NOT NULL DEFAULT 0', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'evidencia_fotografica' AND COLUMN_NAME = 'duracion_seg'),
    'ALTER TABLE evidencia_fotografica ADD COLUMN duracion_seg DECIMAL(5,1) NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'evidencia_fotografica' AND COLUMN_NAME = 'precision_m'),
    'ALTER TABLE evidencia_fotografica ADD COLUMN precision_m DECIMAL(8,1) NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'evidencia_fotografica' AND COLUMN_NAME = 'intento'),
    'ALTER TABLE evidencia_fotografica ADD COLUMN intento INT NOT NULL DEFAULT 1', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'evidencia_fotografica' AND COLUMN_NAME = 'vigente'),
    'ALTER TABLE evidencia_fotografica ADD COLUMN vigente TINYINT(1) NOT NULL DEFAULT 1', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'evidencia_fotografica' AND COLUMN_NAME = 'motivo_rechazo_ia'),
    'ALTER TABLE evidencia_fotografica ADD COLUMN motivo_rechazo_ia VARCHAR(300) NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'evidencia_fotografica' AND COLUMN_NAME = 'resultado_ia'),
    'ALTER TABLE evidencia_fotografica ADD COLUMN resultado_ia JSON NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'evidencia_fotografica' AND COLUMN_NAME = 'ruta_cuadro'),
    'ALTER TABLE evidencia_fotografica ADD COLUMN ruta_cuadro VARCHAR(500) NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'evidencia_fotografica' AND COLUMN_NAME = 'motivo_forzado'),
    'ALTER TABLE evidencia_fotografica ADD COLUMN motivo_forzado VARCHAR(300) NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'evidencia_fotografica' AND COLUMN_NAME = 'forzada_en'),
    'ALTER TABLE evidencia_fotografica ADD COLUMN forzada_en DATETIME NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'evidencia_fotografica' AND INDEX_NAME = 'ix_evidencia_os_equipo_codigo'),
    'ALTER TABLE evidencia_fotografica ADD KEY ix_evidencia_os_equipo_codigo (id_os, id_equipo, codigo, vigente)', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SELECT 'Migración 101 (debe ser 13)' AS verificacion,
       (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'evidencia_fotografica'
           AND COLUMN_NAME IN ('codigo', 'pagina', 'es_video', 'duracion_seg', 'precision_m', 'intento', 'vigente', 'motivo_rechazo_ia', 'resultado_ia', 'ruta_cuadro',
                               'motivo_forzado', 'forzada_en'))
     + (SELECT COUNT(*) FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'evidencia_fotografica'
           AND INDEX_NAME = 'ix_evidencia_os_equipo_codigo' AND SEQ_IN_INDEX = 1) AS valor;
