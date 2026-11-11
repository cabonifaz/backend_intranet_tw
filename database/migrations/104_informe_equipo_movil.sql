-- ============================================================
-- Migración 104 — Cabecera del informe y cierre del trabajo en el equipo (App Mobile HU-15 / HU-16)
--   El técnico completa la "Cabecera del informe" del equipo (Datos · Detalle Serv. · Observación y pruebas) y, con las 5 etapas conformes, genera el
--   informe técnico (Hard Stop de cierre). Todo vive en informe_tecnico y sus tablas hijas (migración 93 / 100): la app no crea tablas paralelas.
--   1. informe_tecnico: + numero_informe (NNNN-AAAA, único; se asigna al GENERAR el informe y se copia a `numero`, que antes era el borrador BRR-########),
--      generado_en / generado_por, "Quién atiende en planta" (responsable_*), detalle_servicio (JSON: tipo de equipo, celdas mV, sumatoria, comparación,
--      anillos), comentario_pruebas, Diagnóstico final (severidad general, estado del equipo y los 4 interruptores), sin_recomendaciones / sin_fallas y
--      cabecera_guardada_en.
--   2. informe_secuencia: último número de informe emitido por año (secuencia propia, atómica).
--   3. informe_procedimiento.codigo: el paso del checklist de "Detalle Serv." (catálogo CHECKLIST_SERVICIO).
--   4. informe_observacion.clasificacion / componente: una falla = una observación (OBS-01…) del informe; nivel_afectacion = severidad
--      (baja → bajo, media → medio, alta → alto, crítica → crítico). Sus fotos son evidencia_fotografica.id_observacion (migración 93).
--   5. informe_observacion_prueba: la prueba que justifica cada falla (repetibilidad · pesaje · excentricidad) con L, I, E y EMP calculados por el servidor.
--   6. Catálogos de referencia en tabla_maestra: CHECKLIST_SERVICIO (checks de Detalle Serv. para OS y OM), CLASIFICACION_FALLA y COMPONENTE_FALLA.
--   No borra ni cambia datos existentes. IDEMPOTENTE. Requiere las migraciones 93, 100 y 101.
-- ============================================================

DROP PROCEDURE IF EXISTS tmp_m104_columna;
DELIMITER $$
CREATE PROCEDURE tmp_m104_columna(IN p_tabla VARCHAR(64), IN p_columna VARCHAR(64), IN p_definicion VARCHAR(500))
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                   WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = p_tabla AND COLUMN_NAME = p_columna) THEN
        SET @sql := CONCAT('ALTER TABLE ', p_tabla, ' ADD COLUMN ', p_columna, ' ', p_definicion);
        PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;
    END IF;
END$$
DELIMITER ;

-- ── 1. informe_tecnico ─────────────────────────────────────────────────────────────────────
CALL tmp_m104_columna('informe_tecnico', 'numero_informe',        'VARCHAR(20) NULL');
CALL tmp_m104_columna('informe_tecnico', 'generado_en',           'DATETIME NULL');
CALL tmp_m104_columna('informe_tecnico', 'generado_por',          'BIGINT NULL');
CALL tmp_m104_columna('informe_tecnico', 'responsable_nombre',    'VARCHAR(150) NULL');
CALL tmp_m104_columna('informe_tecnico', 'responsable_cargo',     'VARCHAR(100) NULL');
CALL tmp_m104_columna('informe_tecnico', 'responsable_telefono',  'VARCHAR(30) NULL');
CALL tmp_m104_columna('informe_tecnico', 'detalle_servicio',      'JSON NULL');
CALL tmp_m104_columna('informe_tecnico', 'comentario_pruebas',    'VARCHAR(500) NULL');
CALL tmp_m104_columna('informe_tecnico', 'sin_recomendaciones',   'TINYINT(1) NOT NULL DEFAULT 0');
CALL tmp_m104_columna('informe_tecnico', 'sin_fallas',            'TINYINT(1) NOT NULL DEFAULT 0');
CALL tmp_m104_columna('informe_tecnico', 'severidad_general',     "ENUM('baja','media','alta','critica') NULL");
CALL tmp_m104_columna('informe_tecnico', 'estado_equipo_final',   "ENUM('operativo','con_observaciones','inoperativo') NULL");
CALL tmp_m104_columna('informe_tecnico', 'rev_jefatura',          'TINYINT(1) NOT NULL DEFAULT 0');
CALL tmp_m104_columna('informe_tecnico', 'requiere_precotizacion','TINYINT(1) NOT NULL DEFAULT 0');
CALL tmp_m104_columna('informe_tecnico', 'segunda_visita',        'TINYINT(1) NOT NULL DEFAULT 0');
CALL tmp_m104_columna('informe_tecnico', 'aplica_garantia',       'TINYINT(1) NOT NULL DEFAULT 0');
CALL tmp_m104_columna('informe_tecnico', 'cabecera_guardada_en',  'DATETIME NULL');

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'informe_tecnico' AND INDEX_NAME = 'ux_informe_numero_informe'),
    'ALTER TABLE informe_tecnico ADD UNIQUE KEY ux_informe_numero_informe (numero_informe)', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- ── 2. informe_secuencia ───────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS informe_secuencia (
    anio            SMALLINT     NOT NULL,
    ultimo          INT          NOT NULL DEFAULT 0,
    modificado_en   DATETIME     NULL ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (anio)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

SET @anio := YEAR(UTC_TIMESTAMP() - INTERVAL 5 HOUR);
INSERT INTO informe_secuencia (anio, ultimo)
SELECT @anio, (SELECT IFNULL(MAX(CAST(LEFT(x.n, 4) AS UNSIGNED)), 0)
               FROM (SELECT it.numero AS n FROM informe_tecnico it WHERE it.numero REGEXP '^[0-9]{4}-[0-9]{4}$' AND RIGHT(it.numero, 4) = CAST(@anio AS CHAR)
                     UNION ALL
                     SELECT it.numero_informe FROM informe_tecnico it WHERE it.numero_informe REGEXP '^[0-9]{4}-[0-9]{4}$' AND RIGHT(it.numero_informe, 4) = CAST(@anio AS CHAR)) x)
FROM DUAL
WHERE NOT EXISTS (SELECT 1 FROM informe_secuencia s WHERE s.anio = @anio);

-- ── 3 y 4. Hijas del informe ───────────────────────────────────────────────────────────────
CALL tmp_m104_columna('informe_procedimiento', 'codigo',        'VARCHAR(40) NULL');
CALL tmp_m104_columna('informe_observacion',   'clasificacion', 'VARCHAR(40) NULL');
CALL tmp_m104_columna('informe_observacion',   'componente',    'VARCHAR(60) NULL');

-- ── 5. Prueba que justifica cada falla ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS informe_observacion_prueba (
    id_prueba       BIGINT        NOT NULL AUTO_INCREMENT,
    id_observacion  BIGINT        NOT NULL,
    tipo            ENUM('repetibilidad','pesaje','excentricidad') NOT NULL,
    orden           INT           NOT NULL DEFAULT 0,
    posicion        INT           NULL,
    carga           DECIMAL(14,4) NOT NULL,
    indicacion      DECIMAL(14,4) NOT NULL,
    error           DECIMAL(14,4) NOT NULL,
    emp             DECIMAL(14,4) NULL,
    resultado       ENUM('conforme','no_conforme') NULL,
    creado_en       DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    creado_por      BIGINT        NULL,
    eliminado_en    DATETIME      NULL,
    eliminado_por   BIGINT        NULL,
    PRIMARY KEY (id_prueba),
    KEY ix_obs_prueba (id_observacion)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ── 6. Catálogos de referencia (tabla_maestra: String1 = nombre, String2 = código, String3 = filtro, Num1 = orden) ──
SET @id_chk := COALESCE((SELECT MAX(IdMaestro) FROM tabla_maestra WHERE Descripcion = 'CHECKLIST_SERVICIO'), (SELECT MAX(IdMaestro) + 1 FROM tabla_maestra));
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2, String3)
SELECT 1, @id_chk, 'CHECKLIST_SERVICIO', v.n, v.nombre, v.codigo, v.tipo
FROM (SELECT  1 AS n, 'Desmontaje de balanza' AS nombre, 'desmontaje' AS codigo, 'OS' AS tipo
      UNION ALL SELECT  2, 'Revisión de celda(s)',                    'rev_celdas',         'OS'
      UNION ALL SELECT  3, 'Revisión de tarjetas electrónicas',       'rev_tarjetas',       'OS'
      UNION ALL SELECT  4, 'Limpieza de carcasa',                     'limp_carcasa',       'OS'
      UNION ALL SELECT  5, 'Revisión y/o limpieza de estructura',     'rev_estructura',     'OS'
      UNION ALL SELECT  6, 'Pintado de estructura',                   'pintado',            'OS'
      UNION ALL SELECT  7, 'Revisión de piezas mecánicas',            'rev_mecanicas',      'OS'
      UNION ALL SELECT  8, 'Ajuste con pesas patrones',               'ajuste_pesas',       'OS'
      UNION ALL SELECT  9, 'Revisión de caja sumatoria',              'rev_sumatoria',      'OS'
      UNION ALL SELECT 10, 'Pruebas de correcto funcionamiento',      'prueba_funcional',   'OS'
      UNION ALL SELECT 11, 'Balanza queda operativa',                 'queda_operativa',    'OS'
      UNION ALL SELECT  1, 'Inspección visual y limpieza',            'om_inspeccion',      'OM'
      UNION ALL SELECT  2, 'Verificación de nivelación',              'om_nivelacion',      'OM'
      UNION ALL SELECT  3, 'Verificación de estabilidad del cero',    'om_cero',            'OM'
      UNION ALL SELECT  4, 'Ajuste con pesas patrones',               'om_ajuste',          'OM'
      UNION ALL SELECT  5, 'Pruebas de repetibilidad',                'om_repetibilidad',   'OM'
      UNION ALL SELECT  6, 'Pruebas de excentricidad',                'om_excentricidad',   'OM'
      UNION ALL SELECT  7, 'Pruebas de pesaje',                       'om_pesaje',          'OM'
      UNION ALL SELECT  8, 'Revisión de pesas patrón utilizadas',     'om_patrones',        'OM'
      UNION ALL SELECT  9, 'Balanza queda operativa',                 'om_operativa',       'OM') v
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra t WHERE t.Descripcion = 'CHECKLIST_SERVICIO' AND t.IdEmpresa = 1 AND t.String2 = v.codigo);

SET @id_cla := COALESCE((SELECT MAX(IdMaestro) FROM tabla_maestra WHERE Descripcion = 'CLASIFICACION_FALLA'), (SELECT MAX(IdMaestro) + 1 FROM tabla_maestra));
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2)
SELECT 1, @id_cla, 'CLASIFICACION_FALLA', v.n, v.nombre, v.codigo
FROM (SELECT 1 AS n, 'Eléctrica' AS nombre, 'electrica' AS codigo
      UNION ALL SELECT 2, 'Electrónica', 'electronica'
      UNION ALL SELECT 3, 'Mecánica',    'mecanica'
      UNION ALL SELECT 4, 'Estructural', 'estructural'
      UNION ALL SELECT 5, 'Calibración', 'calibracion'
      UNION ALL SELECT 6, 'Otra',        'otra') v
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra t WHERE t.Descripcion = 'CLASIFICACION_FALLA' AND t.IdEmpresa = 1 AND t.String2 = v.codigo);

SET @id_com := COALESCE((SELECT MAX(IdMaestro) FROM tabla_maestra WHERE Descripcion = 'COMPONENTE_FALLA'), (SELECT MAX(IdMaestro) + 1 FROM tabla_maestra));
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2, String3)
SELECT 1, @id_com, 'COMPONENTE_FALLA', v.n, v.nombre, v.codigo, v.clasificacion
FROM (SELECT  1 AS n, 'Caja de conexiones' AS nombre, 'caja_conexiones' AS codigo, 'electrica' AS clasificacion
      UNION ALL SELECT  2, 'Celda de carga',          'celda_carga',      'electrica'
      UNION ALL SELECT  3, 'Cableado',                'cableado',         'electrica'
      UNION ALL SELECT  4, 'Indicador',               'indicador',        'electronica'
      UNION ALL SELECT  5, 'Tarjeta electrónica',     'tarjeta',          'electronica'
      UNION ALL SELECT  6, 'Display',                 'display',          'electronica'
      UNION ALL SELECT  7, 'Plataforma',              'plataforma',       'mecanica'
      UNION ALL SELECT  8, 'Pivotes y apoyos',        'pivotes',          'mecanica'
      UNION ALL SELECT  9, 'Estructura',              'estructura',       'estructural'
      UNION ALL SELECT 10, 'Pintura y protección',    'pintura',          'estructural'
      UNION ALL SELECT 11, 'Ajuste de la balanza',    'ajuste',           'calibracion'
      UNION ALL SELECT 12, 'Otro componente',         'otro',             'otra') v
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra t WHERE t.Descripcion = 'COMPONENTE_FALLA' AND t.IdEmpresa = 1 AND t.String2 = v.codigo);

SELECT 'Migración 104 (debe ser 24)' AS verificacion,
       (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'informe_tecnico'
           AND COLUMN_NAME IN ('numero_informe', 'generado_en', 'generado_por', 'responsable_nombre', 'responsable_cargo', 'responsable_telefono', 'detalle_servicio', 'comentario_pruebas',
                               'sin_recomendaciones', 'sin_fallas', 'severidad_general', 'estado_equipo_final', 'rev_jefatura', 'requiere_precotizacion', 'segunda_visita', 'aplica_garantia', 'cabecera_guardada_en'))
     + (SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME IN ('informe_secuencia', 'informe_observacion_prueba'))
     + (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'informe_procedimiento' AND COLUMN_NAME = 'codigo')
     + (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'informe_observacion' AND COLUMN_NAME IN ('clasificacion', 'componente'))
     + (SELECT COUNT(*) FROM informe_secuencia WHERE anio = YEAR(UTC_TIMESTAMP() - INTERVAL 5 HOUR))
     + (SELECT COUNT(*) FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'informe_tecnico' AND INDEX_NAME = 'ux_informe_numero_informe' AND SEQ_IN_INDEX = 1) AS valor;

DROP PROCEDURE IF EXISTS tmp_m104_columna;
