-- Aplicar en la base (Cabecera del informe HU-15 + Hard Stop de cierre HU-16 de la app móvil del técnico). Incluye la migración 104. Sin datos de prueba.
-- Ejecutar completo con Alt+X. NO subir al repositorio. Después REINICIAR la API.
-- ORDEN: aplica antes _aplicar_correlativos_movil.sql (HU-14 / HU-34) y los de HU-28 y HU-29 / HU-30, y DESPUÉS de este el script de la HU-17 (firma de informes).
--   No vuelvas a ejecutar _aplicar_correlativos_movil.sql ni _aplicar_ensayos_movil.sql / _aplicar_evidencias_movil.sql después de este: dejarían
--   SP_ObtenerTrabajoEquipoMovil, SP_ContextoEnsayoMovil o SP_ResumenEvidenciasMovil con su versión anterior (este script las reemplaza).
-- Requiere (ya existentes): migraciones 93, 100 y 101, SP_ContextoEquipoMovil, SP_EmpEnsayoMovil y la tabla ticket_metrologia con las columnas de la migración 103.
-- Qué hace: migración 104 (informe_tecnico, informe_secuencia, informe_observacion_prueba y catálogos de referencia); crea SP_EspecEquipoMovil, SP_TipoOrdenMovil,
--   SP_ArmarEtapasEquipoMovil, SP_ValidarCierreEquipoMovil, SP_GenerarInformeEquipoMovil, SP_ObtenerCabeceraInformeMovil, SP_GuardarCabeceraInformeMovil y
--   SP_RegistrarFotoFallaMovil; actualiza SP_ContextoEnsayoMovil, SP_CatalogoEvidenciasMovil, SP_ResumenEvidenciasMovil y SP_ObtenerTrabajoEquipoMovil.

-- ############################################################
-- 0) Requisitos
-- ############################################################
DROP PROCEDURE IF EXISTS tmp_hu15_requisitos;
DELIMITER $$
CREATE PROCEDURE tmp_hu15_requisitos()
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'informe_tecnico' AND COLUMN_NAME = 'ensayos_finalizado_en') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Falta aplicar antes la migración 100_ensayos_calibracion_movil.sql (HU-10).';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'evidencia_fotografica' AND COLUMN_NAME = 'codigo') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Falta aplicar antes la migración 101_evidencias_movil.sql (HU-11).';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'informe_observacion' AND COLUMN_NAME = 'nivel_afectacion') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Falta aplicar antes la migración 93_revision_tecnica.sql.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'evidencia_fotografica' AND COLUMN_NAME = 'id_observacion') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Falta evidencia_fotografica.id_observacion (migración 93_revision_tecnica.sql).';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'informe_tecnico' AND COLUMN_NAME = 'numero_certificado') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Falta aplicar antes _aplicar_correlativos_movil.sql (HU-14 / HU-34): informe_tecnico.numero_certificado.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = DATABASE() AND ROUTINE_NAME = 'SP_ContextoEquipoMovil') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Falta aplicar antes _aplicar_ensayos_movil.sql (HU-10): SP_ContextoEquipoMovil.';
    END IF;
END$$
DELIMITER ;
CALL tmp_hu15_requisitos();
DROP PROCEDURE IF EXISTS tmp_hu15_requisitos;


-- ############################################################
-- 1) Migración 104
-- ############################################################
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

-- ############################################################
-- 2) SP_EspecEquipoMovil
-- ############################################################
-- ============================================================
-- SP_EspecEquipoMovil  (App Mobile HU-10 / HU-15 — apoyo, NO es un endpoint)
-- Especificaciones metrológicas de un equipo, UNA sola vez: clase de exactitud, unidad, capacidad máxima, d y e (división de verificación; si no tiene,
-- la división mínima). Los datos del equipo son texto libre ("80,000 kg", "0,5 g"): "80,000" y "80 000" son miles, "0,5" es decimal; la unidad son las letras
-- del primer dato (kg por defecto). Lo usan SP_ContextoEnsayoMovil (Ensayos y Calibración) y SP_GuardarCabeceraInformeMovil (EMP de la prueba de una falla).
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_EspecEquipoMovil;

DELIMITER $$

CREATE PROCEDURE SP_EspecEquipoMovil(
    IN  p_id_equipo BIGINT,
    OUT p_clase     VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    OUT p_unidad    VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    OUT p_cap_max   DECIMAL(14,4),
    OUT p_d         DECIMAL(14,4),
    OUT p_e         DECIMAL(14,4)
)
BEGIN
    DECLARE v_cap_txt VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_d_txt   VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_e_txt   VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;

    SET p_clase = NULL, p_unidad = 'kg', p_cap_max = NULL, p_d = NULL, p_e = NULL;

    SELECT UPPER(NULLIF(TRIM(ec.clase_exactitud), '')), ec.alcance_maximo, ec.division_minima, IF(ec.division_verif_igual = 1, NULL, ec.division_verif)
    INTO   p_clase, v_cap_txt, v_d_txt, v_e_txt
    FROM   equipo_cliente ec WHERE ec.id_equipo = p_id_equipo;

    SET p_cap_max = CAST(NULLIF(REGEXP_SUBSTR(IF(REGEXP_LIKE(TRIM(IFNULL(v_cap_txt, '')), '^[0-9]+,[0-9]{1,2}([^0-9]|$)'), REPLACE(v_cap_txt, ',', '.'), REPLACE(REPLACE(IFNULL(v_cap_txt, ''), ',', ''), ' ', '')), '[0-9]+(\\.[0-9]+)?'), '') AS DECIMAL(14,4));
    SET p_d       = CAST(NULLIF(REGEXP_SUBSTR(IF(REGEXP_LIKE(TRIM(IFNULL(v_d_txt, '')), '^[0-9]+,[0-9]{1,2}([^0-9]|$)'), REPLACE(v_d_txt, ',', '.'), REPLACE(REPLACE(IFNULL(v_d_txt, ''), ',', ''), ' ', '')), '[0-9]+(\\.[0-9]+)?'), '') AS DECIMAL(14,4));
    SET p_e       = CAST(NULLIF(REGEXP_SUBSTR(IF(REGEXP_LIKE(TRIM(IFNULL(v_e_txt, '')), '^[0-9]+,[0-9]{1,2}([^0-9]|$)'), REPLACE(v_e_txt, ',', '.'), REPLACE(REPLACE(IFNULL(v_e_txt, ''), ',', ''), ' ', '')), '[0-9]+(\\.[0-9]+)?'), '') AS DECIMAL(14,4));
    SET p_e       = COALESCE(p_e, p_d);
    SET p_unidad  = LOWER(IFNULL(NULLIF(REGEXP_SUBSTR(COALESCE(v_cap_txt, v_d_txt, ''), '[A-Za-z]+'), ''), 'kg'));
END$$

DELIMITER ;

-- ############################################################
-- 3) SP_TipoOrdenMovil
-- ############################################################
-- ============================================================
-- SP_TipoOrdenMovil  (App Mobile HU-08 / HU-15 — apoyo, NO es un endpoint)
-- Tipo de orden de una OS, UNA sola vez: lo define el área de la RQ (area_servicio_rq.area_usuario): servicio técnico → OS, metrología → OM.
-- Devuelve también el número de la RQ. Lo usan SP_ObtenerTrabajoEquipoMovil y la Cabecera del informe (SP_ObtenerCabeceraInformeMovil / SP_GuardarCabeceraInformeMovil).
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_TipoOrdenMovil;

DELIMITER $$

CREATE PROCEDURE SP_TipoOrdenMovil(
    IN  p_id_os     BIGINT,
    OUT p_tipo      VARCHAR(2)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    OUT p_numero_rq VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
BEGIN
    DECLARE v_area VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;

    SET p_tipo = 'OS', p_numero_rq = NULL;
    SELECT asr.area_usuario, rq.numero INTO v_area, p_numero_rq
    FROM   orden_servicio os
    JOIN   expediente_digital ed  ON ed.id_expediente = os.id_expediente
    JOIN   requerimiento      rq  ON rq.id_requerimiento = ed.id_requerimiento
    LEFT JOIN area_servicio_rq asr ON asr.id_area_rq = rq.id_area
    WHERE  os.id_os = p_id_os
    LIMIT 1;
    SET p_tipo = IF(v_area = 'metrologia', 'OM', 'OS');
END$$

DELIMITER ;

-- ############################################################
-- 4) SP_ContextoEnsayoMovil
-- ############################################################
-- ============================================================
-- SP_ContextoEnsayoMovil  (App Mobile HU-10 — apoyo, no es un endpoint)
-- Valida y arma, UNA sola vez, el contexto de los ensayos de un equipo. Lo usan SP_ObtenerEnsayosMovil, SP_GuardarEnsayosMovil y
-- SP_RegistrarLlamadaEnsayoMovil. Si algo impide trabajar, p_mensaje trae el texto para el técnico (y lo demás queda NULL).
--   - La OS debe ser del técnico. Hard Stop (HU-06): llegada registrada y servicio en curso. El equipo debe estar EN EJECUCIÓN o PAUSADO (lectura) —
--     p_estado_equipo lo dice, quien escribe exige 'en_ejecucion'.
--   - HU-09: antes de los ensayos deben estar guardadas las variables ambientales (temperatura y humedad).
--   - Especificaciones del equipo (clase de exactitud, unidad, capacidad máxima, d y e): SP_EspecEquipoMovil (una sola vez; HU-15 también la usa).
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ContextoEnsayoMovil;

DELIMITER $$

CREATE PROCEDURE SP_ContextoEnsayoMovil(
    IN  p_id_usuario    BIGINT,
    IN  p_id_os         BIGINT,
    IN  p_id_os_equipo  BIGINT,
    OUT p_mensaje       VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    OUT p_id_equipo     BIGINT,
    OUT p_estado_equipo VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    OUT p_habilitado    TINYINT,
    OUT p_numero        INT,
    OUT p_nombre_equipo VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    OUT p_numero_os     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    OUT p_clase         VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    OUT p_unidad        VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    OUT p_cap_max       DECIMAL(14,4),
    OUT p_d             DECIMAL(14,4),
    OUT p_e             DECIMAL(14,4)
)
BEGIN
    DECLARE v_servicio    VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_vars        INT DEFAULT 0;

    SET p_mensaje = NULL, p_id_equipo = NULL, p_estado_equipo = NULL, p_habilitado = 0, p_numero = NULL, p_nombre_equipo = NULL, p_numero_os = NULL,
        p_clase = NULL, p_unidad = 'kg', p_cap_max = NULL, p_d = NULL, p_e = NULL;

    -- OS del técnico, Hard Stop y equipo iniciado: una sola vez, en SP_ContextoEquipoMovil
    CALL SP_ContextoEquipoMovil(p_id_usuario, p_id_os, p_id_os_equipo, p_mensaje, p_id_equipo, p_estado_equipo, p_habilitado, p_numero, p_nombre_equipo, p_numero_os, v_servicio);

    IF p_mensaje IS NULL THEN
        SELECT COUNT(*) INTO v_vars
        FROM   variable_ambiental va
        WHERE  va.id_os = p_id_os AND va.id_equipo = p_id_equipo AND va.eliminado_en IS NULL
          AND  va.temperatura_c IS NOT NULL AND va.humedad_pct IS NOT NULL;
        IF v_vars = 0 THEN
            SET p_mensaje = 'Primero registra las variables ambientales: Ensayos y Calibración se habilita al guardarlas.';
        END IF;
    END IF;

    IF p_mensaje IS NULL THEN
        -- Clase, unidad, capacidad máxima, d y e: una sola vez, en SP_EspecEquipoMovil
        CALL SP_EspecEquipoMovil(p_id_equipo, p_clase, p_unidad, p_cap_max, p_d, p_e);
    END IF;
END$$

DELIMITER ;

-- ############################################################
-- 5) SP_CatalogoEvidenciasMovil
-- ############################################################
-- ============================================================
-- SP_CatalogoEvidenciasMovil  (App Mobile HU-11 — apoyo, no es un endpoint)
-- Las 9 evidencias del registro fotográfico de un equipo, UNA sola vez, en la tabla temporal tmp_cat_evid (el que la llama la borra al terminar):
--   orden · codigo · nombre · descripcion · obligatoria (la placa y la foto inicial: "(*) obligatorias para cerrar el equipo") ·
--   medio (foto | video | qr) · id_tipo (TIPO_EVIDENCIA de la migración 01 al que se asocia cada una).
-- Todas se necesitan para "Guardar y volver" (panel completo). Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_CatalogoEvidenciasMovil;

DELIMITER $$

CREATE PROCEDURE SP_CatalogoEvidenciasMovil()
BEGIN
    DROP TEMPORARY TABLE IF EXISTS tmp_cat_evid;
    CREATE TEMPORARY TABLE tmp_cat_evid (
        orden INT NOT NULL, codigo VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, nombre VARCHAR(60) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        descripcion VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, obligatoria TINYINT DEFAULT 0, medio VARCHAR(6) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        id_tipo INT NOT NULL,
        -- Los llena SP_ResumenEvidenciasMovil (una sola vez): la última toma vigente está aprobada/forzada/omitida · fue forzada · quedó rechazada
        completa TINYINT NOT NULL DEFAULT 0, forzada TINYINT NOT NULL DEFAULT 0, rechazada TINYINT NOT NULL DEFAULT 0, PRIMARY KEY (orden));
    INSERT INTO tmp_cat_evid (orden, codigo, nombre, descripcion, obligatoria, medio, id_tipo) VALUES
        (1, 'placa',      'Placa de identificación', 'Especificaciones del equipo', 1, 'foto',  1),
        (2, 'inicial',    'Inicial',                 'Estado inicial del equipo',   1, 'foto',  1),
        (3, 'encendido',  'Encendido',               'Video del display (HU-13)',   0, 'video', 2),
        (4, 'desmontaje', 'Desmontaje',              'Partes desmontadas',          0, 'foto',  2),
        (5, 'abierto',    'Abierto',                 'Interior del equipo',         0, 'foto',  2),
        (6, 'prueba',     'Prueba',                  'Equipo con pesas patrón',     0, 'foto',  2),
        (7, 'final',      'Final',                   'Equipo terminado y limpio',   0, 'foto',  3),
        (8, 'informe',    'Informe',                 'Foto del informe a mano',     0, 'foto',  2),
        (9, 'qr',         'QR',                      'Etiqueta QR del equipo',      0, 'qr',    1);
END$$

DELIMITER ;

-- ############################################################
-- 6) SP_ResumenEvidenciasMovil
-- ############################################################
-- ============================================================
-- SP_ResumenEvidenciasMovil  (App Mobile HU-11 / HU-08 — apoyo, no es un endpoint)
-- Avance del registro fotográfico de un equipo, UNA sola vez. Lo usan el panel de evidencias y la etapa "Registro fotográfico" del trabajo en el equipo.
--   Evidencia COMPLETA = su última captura (vigente, página 1) está aprobada por la IA, fue forzada por el técnico (HU-12) o no se pudo validar con la IA
--   ("omitida": no cuenta como rechazo). Una toma rechazada y no forzada NO completa la evidencia.
-- Deja la tabla temporal tmp_cat_evid armada, con completa / forzada / rechazada por evidencia (quien llama la borra; HU-16 lista las que faltan). Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ResumenEvidenciasMovil;

DELIMITER $$

CREATE PROCEDURE SP_ResumenEvidenciasMovil(
    IN  p_id_os          BIGINT,
    IN  p_id_equipo      BIGINT,
    OUT p_total          INT,
    OUT p_completas      INT,
    OUT p_forzadas       INT,
    OUT p_rechazadas     INT,
    OUT p_oblig_faltan   INT
)
BEGIN
    CALL SP_CatalogoEvidenciasMovil();

    -- Última toma vigente (página 1) de cada evidencia: completa = aprobada por la IA, forzada o sin validar ('omitida'); una rechazada y no forzada NO completa
    UPDATE tmp_cat_evid c
    JOIN  (SELECT f2.codigo, MAX(f2.id_evidencia) AS id_ultima
           FROM   evidencia_fotografica f2
           WHERE  f2.id_os = p_id_os AND f2.id_equipo = p_id_equipo AND f2.pagina = 1 AND f2.vigente = 1 AND f2.eliminado_en IS NULL
           GROUP BY f2.codigo) u ON u.codigo = c.codigo
    JOIN   evidencia_fotografica f ON f.id_evidencia = u.id_ultima
    SET    c.completa  = IF(f.override_aprobado = 1 OR f.validacion_ia IN ('aprobada', 'omitida'), 1, 0),
           c.forzada   = IF(f.override_aprobado = 1, 1, 0),
           c.rechazada = IF(f.override_aprobado = 0 AND f.validacion_ia = 'rechazada', 1, 0);

    SELECT COUNT(*), IFNULL(SUM(completa), 0), IFNULL(SUM(forzada), 0), IFNULL(SUM(rechazada), 0), IFNULL(SUM(obligatoria = 1 AND completa = 0), 0)
    INTO   p_total, p_completas, p_forzadas, p_rechazadas, p_oblig_faltan
    FROM   tmp_cat_evid;
END$$

DELIMITER ;

-- ############################################################
-- 7) SP_ArmarEtapasEquipoMovil
-- ############################################################
-- ============================================================
-- SP_ArmarEtapasEquipoMovil  (App Mobile HU-08 / HU-15 / HU-16 — apoyo, NO es un endpoint)
-- Las 5 etapas del trabajo en un equipo y sus PENDIENTES, UNA sola vez. Las leen SP_ObtenerTrabajoEquipoMovil (pantalla "Trabajo en el equipo"),
-- SP_ValidarCierreEquipoMovil (Hard Stop de "Finalizar trabajo en equipo") y SP_GenerarInformeEquipoMovil (generar el informe técnico): así el botón, el
-- modal de pendientes y la generación nunca discrepan. Quien la llame debe terminar con DROP TEMPORARY TABLE IF EXISTS tmp_etapas_mov, tmp_pend_eq.
--   tmp_etapas_mov (orden, codigo, nombre, estado, detalle, disponible):
--     estado: conforme | en_curso | pendiente | bloqueado | no_conforme (Ensayos finalizados CON error crítico: bloquea el cierre).
--     1 variables   conforme con las variables ambientales guardadas (HU-09).
--     2 fotos       conforme con las 9 evidencias completas: aprobadas por la IA, forzadas o sin validar (SP_ResumenEvidenciasMovil, HU-11 / HU-12).
--     3 ensayos     bloqueado sin variables; conforme al finalizar sin error crítico; NO CONFORME si se finalizó con error crítico (HU-10).
--     4 cabecera    "Cabecera del informe" (HU-15): conforme con la cabecera guardada y sin pendientes (recomendaciones o "sin recomendaciones", fallas o
--                   "sin fallas", Detalle Serv. guardado, Diagnóstico final completo y cada falla con su prueba).
--     5 correlativo conforme con el certificado guardado en el informe (HU-14); bloqueado hasta finalizar los ensayos.
--   tmp_pend_eq (id, orden, codigo, texto): una fila por pendiente con el texto para el técnico ("Falta la foto Final", "Error crítico en 20,000 kg (+34 kg ·
--     EMP ±20 kg)", "Falta completar el Diagnóstico final", "Esperando el correlativo de Metrología (TK-MET-00241)"…). Una etapa conforme no tiene pendientes.
--   p_conformes = etapas conformes de 5.
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ArmarEtapasEquipoMovil;

DELIMITER $$

CREATE PROCEDURE SP_ArmarEtapasEquipoMovil(
    IN  p_id_os     BIGINT,
    IN  p_id_equipo BIGINT,
    OUT p_conformes INT
)
BEGIN
    DECLARE v_vars       TINYINT DEFAULT 0;
    DECLARE v_det_vars   VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_informe    BIGINT DEFAULT NULL;
    DECLARE v_n_ensayos  INT DEFAULT 0;
    DECLARE v_ens_final  DATETIME DEFAULT NULL;
    DECLARE v_ens_motivo VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_cert       VARCHAR(50)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_cab_guard  DATETIME DEFAULT NULL;
    DECLARE v_tiene_det  TINYINT DEFAULT 0;
    DECLARE v_sev        VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_est_fin    VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_sin_rec    TINYINT DEFAULT 0;
    DECLARE v_sin_fal    TINYINT DEFAULT 0;
    DECLARE v_n_rec      INT DEFAULT 0;
    DECLARE v_n_fal      INT DEFAULT 0;
    DECLARE v_clase      VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_unidad     VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cap        DECIMAL(14,4);
    DECLARE v_d          DECIMAL(14,4);
    DECLARE v_e          DECIMAL(14,4);
    DECLARE v_ev_total   INT DEFAULT 9;
    DECLARE v_ev_compl   INT DEFAULT 0;
    DECLARE v_ev_forz    INT DEFAULT 0;
    DECLARE v_ev_rech    INT DEFAULT 0;
    DECLARE v_ev_oblig   INT DEFAULT 0;
    DECLARE v_tk_estado  VARCHAR(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_tk_num     VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_tk_corr    VARCHAR(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_crit_carga DECIMAL(14,4) DEFAULT NULL;
    DECLARE v_pend_cab   INT DEFAULT 0;
    DECLARE v_prim_cab   VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE s1 VARCHAR(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE s2 VARCHAR(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE s3 VARCHAR(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE s4 VARCHAR(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE s5 VARCHAR(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DROP TEMPORARY TABLE IF EXISTS tmp_etapas_mov;
    CREATE TEMPORARY TABLE tmp_etapas_mov (
        orden INT NOT NULL, codigo VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, nombre VARCHAR(60) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        estado VARCHAR(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, detalle VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        disponible TINYINT DEFAULT 0, PRIMARY KEY (orden));
    DROP TEMPORARY TABLE IF EXISTS tmp_pend_eq;
    CREATE TEMPORARY TABLE tmp_pend_eq (
        id INT NOT NULL AUTO_INCREMENT, orden INT NOT NULL, codigo VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        texto VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, PRIMARY KEY (id));

    CALL SP_EspecEquipoMovil(p_id_equipo, v_clase, v_unidad, v_cap, v_d, v_e);

    -- ── 1. Variables ambientales (HU-09) ───────────────────────────────────────────────────────
    SELECT COUNT(*) INTO v_vars FROM variable_ambiental va WHERE va.id_os = p_id_os AND va.id_equipo = p_id_equipo AND va.eliminado_en IS NULL;
    IF v_vars > 0 THEN
        SELECT CONCAT('T° ', TRIM(TRAILING '.' FROM TRIM(TRAILING '0' FROM CAST(va.temperatura_c AS CHAR))), ' °C · h ',
                      TRIM(TRAILING '.' FROM TRIM(TRAILING '0' FROM CAST(va.humedad_pct AS CHAR))), ' % · Procedencia ', IFNULL(va.procedencia, 'N.I'))
        INTO   v_det_vars
        FROM   variable_ambiental va
        WHERE  va.id_os = p_id_os AND va.id_equipo = p_id_equipo AND va.eliminado_en IS NULL
        ORDER BY va.id_variable DESC LIMIT 1;
    ELSE
        INSERT INTO tmp_pend_eq (orden, codigo, texto) VALUES (1, 'variables', 'Faltan las variables ambientales (temperatura y humedad)');
    END IF;

    -- ── 2. Registro fotográfico (HU-11): una pendiente por evidencia que falta ─────────────────
    CALL SP_ResumenEvidenciasMovil(p_id_os, p_id_equipo, v_ev_total, v_ev_compl, v_ev_forz, v_ev_rech, v_ev_oblig);
    INSERT INTO tmp_pend_eq (orden, codigo, texto)
    SELECT 2, 'fotos',
           CASE WHEN c.rechazada = 1 THEN CONCAT('La toma de ', c.nombre, ' fue rechazada: repítela o acéptala con un motivo')
                WHEN c.codigo = 'qr' THEN 'Falta la foto del QR'
                WHEN c.codigo = 'placa' THEN 'Falta la foto de la placa'
                WHEN c.codigo = 'informe' THEN 'Falta la foto del informe a mano'
                WHEN c.medio = 'video' THEN CONCAT('Falta el video de ', LOWER(c.nombre))
                ELSE CONCAT('Falta la foto ', c.nombre) END
    FROM   tmp_cat_evid c
    WHERE  c.completa = 0
    ORDER BY c.orden;
    DROP TEMPORARY TABLE IF EXISTS tmp_cat_evid;

    -- ── Informe técnico del equipo (lo crea la primera captura de ensayos o de la cabecera) ───
    SELECT it.id_informe, it.ensayos_finalizado_en, it.error_critico_motivo, it.numero_certificado, it.cabecera_guardada_en, IF(it.detalle_servicio IS NULL, 0, 1),
           it.severidad_general, it.estado_equipo_final, it.sin_recomendaciones, it.sin_fallas
    INTO   v_informe, v_ens_final, v_ens_motivo, v_cert, v_cab_guard, v_tiene_det, v_sev, v_est_fin, v_sin_rec, v_sin_fal
    FROM   informe_tecnico it
    WHERE  it.id_os = p_id_os AND it.id_equipo = p_id_equipo AND it.eliminado_en IS NULL
    ORDER BY it.id_informe DESC LIMIT 1;
    IF v_informe IS NOT NULL THEN
        SELECT COUNT(*) INTO v_n_ensayos FROM informe_ensayo ie WHERE ie.id_informe = v_informe AND ie.eliminado_en IS NULL;
        SELECT COUNT(*) INTO v_n_rec FROM informe_recomendacion r WHERE r.id_informe = v_informe AND r.origen = 'tecnico' AND r.eliminado_en IS NULL;
        SELECT COUNT(*) INTO v_n_fal FROM informe_observacion o WHERE o.id_informe = v_informe AND o.origen = 'tecnico' AND o.eliminado_en IS NULL;
    END IF;

    -- ── 3. Ensayos y Calibración (HU-10) ───────────────────────────────────────────────────────
    IF v_vars = 0 THEN
        INSERT INTO tmp_pend_eq (orden, codigo, texto) VALUES (3, 'ensayos', 'Se habilita al guardar las variables ambientales');
    ELSEIF v_ens_final IS NULL THEN
        INSERT INTO tmp_pend_eq (orden, codigo, texto) VALUES (3, 'ensayos', 'Falta finalizar los ensayos y la calibración');
    ELSEIF v_ens_motivo IS NOT NULL THEN
        -- Finalizado CON error crítico: una pendiente por cada lectura fuera del EMP (carga, error con signo y EMP)
        INSERT INTO tmp_pend_eq (orden, codigo, texto)
        SELECT 3, 'ensayos',
               LEFT(CONCAT('Error crítico en ', FORMAT(en.carga, 0), ' ', v_unidad, ' (', IF(en.error >= 0, '+', ''),
                           TRIM(TRAILING '.' FROM TRIM(TRAILING '0' FROM CAST(ROUND(en.error, 4) AS CHAR))), ' ', v_unidad, ' · EMP ±',
                           IFNULL(TRIM(TRAILING '.' FROM TRIM(TRAILING '0' FROM CAST(ROUND(en.tolerancia, 4) AS CHAR))), '?'), ' ', v_unidad, ')'), 250)
        FROM   informe_ensayo en
        WHERE  en.id_informe = v_informe AND en.eliminado_en IS NULL AND en.critico = 1
        ORDER BY en.tipo, en.grupo, en.orden;
        SELECT MIN(en.carga) INTO v_crit_carga FROM informe_ensayo en WHERE en.id_informe = v_informe AND en.eliminado_en IS NULL AND en.critico = 1;
        IF NOT EXISTS (SELECT 1 FROM tmp_pend_eq WHERE orden = 3) THEN
            INSERT INTO tmp_pend_eq (orden, codigo, texto) VALUES (3, 'ensayos', 'El ensayo se guardó con un error crítico: repítelo o corrige la lectura');
        END IF;
    END IF;

    -- ── 4. Cabecera del informe (HU-15) ────────────────────────────────────────────────────────
    IF v_cab_guard IS NULL THEN
        INSERT INTO tmp_pend_eq (orden, codigo, texto) VALUES (4, 'cabecera', 'Falta completar la cabecera del informe (Datos, Detalle Serv. y Observación y pruebas)');
    ELSE
        IF v_tiene_det = 0 THEN
            INSERT INTO tmp_pend_eq (orden, codigo, texto) VALUES (4, 'cabecera', 'Falta completar el Detalle del servicio');
        END IF;
        IF v_n_rec = 0 AND v_sin_rec = 0 THEN
            INSERT INTO tmp_pend_eq (orden, codigo, texto) VALUES (4, 'cabecera', 'Faltan las recomendaciones inmediatas (o indicar que no hay)');
        END IF;
        IF v_n_fal = 0 AND v_sin_fal = 0 THEN
            INSERT INTO tmp_pend_eq (orden, codigo, texto) VALUES (4, 'cabecera', 'Faltan las fallas del equipo (o indicar que no hay)');
        END IF;
        INSERT INTO tmp_pend_eq (orden, codigo, texto)
        SELECT 4, 'cabecera', LEFT(CONCAT('La falla ', o.codigo, ' no tiene una prueba que la justifique'), 250)
        FROM   informe_observacion o
        WHERE  o.id_informe = v_informe AND o.origen = 'tecnico' AND o.eliminado_en IS NULL
          AND  NOT EXISTS (SELECT 1 FROM informe_observacion_prueba p WHERE p.id_observacion = o.id_observacion AND p.eliminado_en IS NULL)
        ORDER BY o.orden;
        IF v_sev IS NULL OR v_est_fin IS NULL THEN
            INSERT INTO tmp_pend_eq (orden, codigo, texto) VALUES (4, 'cabecera', 'Falta completar el Diagnóstico final');
        END IF;
    END IF;
    SELECT COUNT(*) INTO v_pend_cab FROM tmp_pend_eq WHERE orden = 4;
    SELECT texto INTO v_prim_cab FROM tmp_pend_eq WHERE orden = 4 ORDER BY id LIMIT 1;

    -- ── 5. Correlativo y certificado (HU-14) ───────────────────────────────────────────────────
    SELECT t.estado, t.numero, t.correlativo_asignado INTO v_tk_estado, v_tk_num, v_tk_corr
    FROM   ticket_metrologia t
    WHERE  t.id_os = p_id_os AND t.id_equipo = p_id_equipo AND t.estado IN ('solicitado', 'asignado') AND t.eliminado_en IS NULL
    ORDER BY t.id_ticket_met DESC LIMIT 1;
    IF v_cert IS NULL THEN
        INSERT INTO tmp_pend_eq (orden, codigo, texto)
        VALUES (5, 'correlativo',
                CASE WHEN v_ens_final IS NULL THEN 'Se habilita al finalizar los ensayos y la calibración'
                     WHEN v_tk_estado = 'asignado' THEN CONCAT('Falta usar el correlativo asignado (', IFNULL(v_tk_corr, ''), ')')
                     WHEN v_tk_estado = 'solicitado' THEN CONCAT('Esperando el correlativo de Metrología (', v_tk_num, ')')
                     ELSE 'Falta solicitar el correlativo de Metrología' END);
    END IF;

    -- ── Estados y detalle de las 5 etapas ──────────────────────────────────────────────────────
    SET s1 = IF(v_vars > 0, 'conforme', 'pendiente');
    SET s2 = IF(v_ev_compl >= v_ev_total, 'conforme', IF(v_ev_compl > 0 OR v_ev_rech > 0, 'en_curso', 'pendiente'));
    SET s3 = IF(v_vars = 0, 'bloqueado', IF(v_ens_final IS NOT NULL, IF(v_ens_motivo IS NULL, 'conforme', 'no_conforme'), IF(v_n_ensayos > 0, 'en_curso', 'pendiente')));
    SET s4 = IF(v_cab_guard IS NOT NULL AND v_pend_cab = 0, 'conforme', IF(v_cab_guard IS NOT NULL, 'en_curso', 'pendiente'));
    SET s5 = IF(v_cert IS NOT NULL, 'conforme', IF(v_ens_final IS NULL, 'bloqueado', IF(v_tk_estado IS NOT NULL, 'en_curso', 'pendiente')));

    INSERT INTO tmp_etapas_mov (orden, codigo, nombre, estado, detalle, disponible) VALUES
        (1, 'variables', 'Variables ambientales', s1, IF(v_vars > 0, v_det_vars, 'Temperatura, humedad y procedencia'), 1),
        (2, 'fotos', 'Registro fotográfico', s2,
            CONCAT(v_ev_compl, ' de ', v_ev_total, ' · incluye foto del informe a mano', IF(v_ev_forz > 0, CONCAT(' · ', v_ev_forz, IF(v_ev_forz = 1, ' forzada', ' forzadas')), '')), 1),
        (3, 'ensayos', 'Ensayos y Calibración', s3,
            IF(v_vars = 0, 'Se habilita al guardar las variables ambientales',
               IF(v_ens_final IS NOT NULL,
                  IF(v_ens_motivo IS NULL, 'Pesaje y excentricidad conformes',
                     CONCAT('Pesaje guardado con error crítico', IF(v_crit_carga IS NULL, '', CONCAT(' (', FORMAT(v_crit_carga, 0), ' ', v_unidad, ')')))),
                  IF(v_n_ensayos > 0, CONCAT(v_n_ensayos, ' lecturas guardadas · falta finalizar'), 'Verificación de pesaje tras el ajuste'))), 1),
        (4, 'cabecera', 'Cabecera del informe', s4,
            IF(s4 = 'conforme', 'Cabecera completa', IF(s4 = 'en_curso', v_prim_cab, 'Datos · Detalle Serv. · Observación y pruebas')), 1),
        (5, 'correlativo', 'Correlativo y certificado', s5,
            IF(v_cert IS NOT NULL, CONCAT('Certificado ', v_cert),
               IF(v_ens_final IS NULL, 'Se habilita al finalizar los ensayos',
                  IF(v_tk_estado = 'asignado', CONCAT(v_tk_num, ' asignado · listo para usar'),
                     IF(v_tk_estado = 'solicitado', CONCAT(v_tk_num, ' · esperando a Metrología'), 'Correlativo de Metrología → N° de certificado')))), 1);

    SELECT COUNT(*) INTO p_conformes FROM tmp_etapas_mov WHERE estado = 'conforme';
END$$

DELIMITER ;

-- ############################################################
-- 8) SP_ObtenerTrabajoEquipoMovil
-- ############################################################
-- ============================================================
-- SP_ObtenerTrabajoEquipoMovil  (App Mobile HU-08 — "Trabajo en el equipo": cabecera y las 5 etapas · lectura)
-- Pantalla a la que entra el técnico con "Trabajar en el equipo". El técnico sale del token; la OS debe ser suya.
--   - Hard Stop (HU-06): sin llegada registrada no se entrega nada. El equipo debe haberse iniciado (en ejecución, pausado o completado).
--   - Tipo de orden según la RQ: el área de la RQ (area_servicio_rq) define OS (servicio técnico) u OM (metrología).
--   - Servicio: sigla y nombre del tipo de intervención del equipo; si no tiene, el tipo de servicio de la OS.
--   - Etapas (siempre las 5): variables (HU-09), fotos (HU-11), ensayos (HU-10), cabecera (HU-15) y correlativo (HU-14). Las calcula SP_ArmarEtapasEquipoMovil, UNA sola vez
--     (la misma regla del Hard Stop de cierre, HU-16: SP_ValidarCierreEquipoMovil / SP_GenerarInformeEquipoMovil).
--       estado: conforme | en_curso | pendiente | bloqueado | no_conforme (ensayos finalizados con error crítico).
--       disponible = 0 → la etapa aún no tiene pantalla en la app (hoy las 5 la tienen).
--   - Avance = etapas conformes de 5. "Finalizar trabajo" se habilita cuando las 5 están conformes (puede_finalizar).
--   - puede_registrar = el equipo está EN EJECUCIÓN y el servicio en curso: solo así se guardan datos de las etapas.
-- Resultados: 1 mensaje · 2 cabecera (1 fila) · 3 variables ambientales (0 o 1 fila) · 4 etapas (5 filas).
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerTrabajoEquipoMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerTrabajoEquipoMovil(
    IN p_id_usuario   BIGINT,
    IN p_id_os        BIGINT,
    IN p_id_os_equipo BIGINT
)
proc: BEGIN
    DECLARE v_estado_os   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_salida_utc  DATETIME;
    DECLARE v_llegada_utc DATETIME;
    DECLARE v_habilitado  TINYINT;
    DECLARE v_motivo      VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_equipo   BIGINT DEFAULT NULL;
    DECLARE v_estado      VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_tipo_orden  VARCHAR(2)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT 'OS';
    DECLARE v_numero_rq   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_servicio    VARCHAR(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_sigla       VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_tipo_int    VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_conformes   INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
        DROP TEMPORARY TABLE IF EXISTS tmp_etapas_mov;
        DROP TEMPORARY TABLE IF EXISTS tmp_pend_eq;
        DROP TEMPORARY TABLE IF EXISTS tmp_cat_evid;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SELECT os.estado INTO v_estado_os
    FROM   orden_servicio os
    WHERE  os.id_os = p_id_os AND os.eliminado_en IS NULL
      AND  (os.id_tecnico_principal = p_id_usuario
            OR EXISTS (SELECT 1 FROM os_personal op
                       WHERE op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL));
    IF v_estado_os IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio no encontrado o no asignado a tu usuario.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Objetivo (equipo) de esa OS, con su estado: SP_ArmarObjetivosMovil (una sola vez)
    CALL SP_ArmarObjetivosMovil(p_id_os, v_estado_os, v_salida_utc, v_llegada_utc, v_habilitado, v_motivo);
    IF v_llegada_utc IS NULL THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
        SELECT 1 AS IdTipoMensaje, v_motivo AS Mensaje;
        LEAVE proc;
    END IF;
    SELECT t.id_equipo, t.estado, COALESCE(t.tipo_corto, t.tipo_intervencion), t.tipo_intervencion INTO v_id_equipo, v_estado, v_sigla, v_tipo_int
    FROM   tmp_obj_mov t WHERE t.id_os_equipo = p_id_os_equipo;
    IF v_id_equipo IS NULL THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
        SELECT 1 AS IdTipoMensaje, 'El equipo no forma parte de los objetivos de este servicio.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_estado NOT IN ('en_ejecucion', 'pausado', 'completado') THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
        SELECT 1 AS IdTipoMensaje, 'Primero inicia el trabajo en este equipo desde los objetivos.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Tipo de orden según la RQ (servicio técnico → OS, metrología → OM): una sola vez, en SP_TipoOrdenMovil
    CALL SP_TipoOrdenMovil(p_id_os, v_tipo_orden, v_numero_rq);

    -- Las 5 etapas (estado, detalle y pendientes): una sola vez, en SP_ArmarEtapasEquipoMovil (la comparten el Hard Stop de cierre y la generación del informe)
    CALL SP_ArmarEtapasEquipoMovil(p_id_os, v_id_equipo, v_conformes);

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Cabecera
    SELECT os.id_os, os.numero AS numero_os, COALESCE(NULLIF(c.nombre_comercial, ''), c.razon_social) AS cliente,
           v_tipo_orden AS tipo_orden, v_numero_rq AS numero_rq,
           v_sigla AS servicio_sigla,
           COALESCE(v_tipo_int, (SELECT ts.String1 FROM tabla_maestra ts
                                 WHERE ts.Descripcion = 'TIPO_SERVICIO' AND ts.IdEmpresa = 1 AND ts.Num1 = os.id_tipo_servicio LIMIT 1)) AS servicio,
           e.id_os_equipo, e.nombre, e.num_serie, e.codigo_cliente, e.codigo_tw, e.marca, e.modelo, e.ubicacion, e.estado,
           e.tiempo_estimado_min, e.tiempo_real_min, CONVERT_TZ(e.iniciado_utc, '+00:00', '-05:00') AS iniciado_en,
           IF(e.estado = 'en_ejecucion' AND v_habilitado = 1, 1, 0) AS puede_registrar,
           v_conformes AS etapas_conformes,
           5 AS etapas_total,
           IF(v_conformes = 5 AND e.estado = 'en_ejecucion', 1, 0) AS puede_finalizar
    FROM   tmp_obj_mov e
    JOIN   orden_servicio os ON os.id_os = p_id_os
    LEFT JOIN cliente c ON c.id_cliente = os.id_cliente
    WHERE  e.id_os_equipo = p_id_os_equipo;

    -- 3. Variables ambientales vigentes (hora de Lima)
    SELECT va.temperatura_c, va.humedad_pct, IFNULL(va.procedencia, 'N.I') AS procedencia,
           CONVERT_TZ(va.registrado_en, '+00:00', '-05:00') AS registrado_en
    FROM   variable_ambiental va
    WHERE  va.id_os = p_id_os AND va.id_equipo = v_id_equipo AND va.eliminado_en IS NULL
    ORDER BY va.id_variable DESC LIMIT 1;

    -- 4. Etapas
    SELECT s.orden, s.codigo, s.nombre, s.estado, s.detalle, s.disponible FROM tmp_etapas_mov s ORDER BY s.orden;

    DROP TEMPORARY TABLE IF EXISTS tmp_etapas_mov;
    DROP TEMPORARY TABLE IF EXISTS tmp_pend_eq;
    DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
END$$

DELIMITER ;

-- ############################################################
-- 9) SP_ValidarCierreEquipoMovil
-- ############################################################
-- ============================================================
-- SP_ValidarCierreEquipoMovil  (App Mobile HU-16 — Hard Stop de "Finalizar trabajo en equipo" · solo lectura)
-- Al tocar "Finalizar trabajo en equipo" el servidor valida las 5 etapas con la MISMA regla que pinta la pantalla de Trabajo en el equipo
-- (SP_ArmarEtapasEquipoMovil, una sola vez) y responde SIEMPRE: o "Validación completa" o los pendientes por etapa. No escribe nada.
--   - La OS debe ser del técnico, con la llegada registrada y el equipo iniciado (SP_ContextoEquipoMovil). Un equipo pausado debe reanudarse primero.
--   - puede_generar = las 5 etapas conformes Y el equipo en ejecución Y el informe aún no generado (ya_generado = 1 → la app va directo a Firma de informes).
--   - Un ensayo finalizado con error crítico es NO CONFORME y bloquea el cierre, igual que una evidencia, la cabecera o el correlativo pendientes.
-- Resultados: 1 mensaje · 2 resumen (1 fila: puede_generar, ya_generado, numero_informe, conformes, total, pendientes, estado_equipo, equipo, numero_os) ·
--   3 etapas (5 filas: orden, codigo, nombre, estado, detalle, n_pendientes) · 4 pendientes (orden, codigo, texto).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ValidarCierreEquipoMovil;

DELIMITER $$

CREATE PROCEDURE SP_ValidarCierreEquipoMovil(
    IN p_id_usuario   BIGINT,
    IN p_id_os        BIGINT,
    IN p_id_os_equipo BIGINT
)
proc: BEGIN
    DECLARE v_msg       VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_id_eq     BIGINT DEFAULT NULL;
    DECLARE v_estado    VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_hab       TINYINT DEFAULT 0;
    DECLARE v_numero    INT DEFAULT NULL;
    DECLARE v_nombre    VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_num_os    VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_servicio  VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_conformes INT DEFAULT 0;
    DECLARE v_n_pend    INT DEFAULT 0;
    DECLARE v_gen       DATETIME DEFAULT NULL;
    DECLARE v_num_inf   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_etapas_mov;
        DROP TEMPORARY TABLE IF EXISTS tmp_pend_eq;
        DROP TEMPORARY TABLE IF EXISTS tmp_cat_evid;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 OR IFNULL(p_id_os_equipo, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio o equipo no encontrado.' AS Mensaje; LEAVE proc;
    END IF;

    CALL SP_ContextoEquipoMovil(p_id_usuario, p_id_os, p_id_os_equipo, v_msg, v_id_eq, v_estado, v_hab, v_numero, v_nombre, v_num_os, v_servicio);
    IF v_msg IS NULL AND v_estado = 'pausado' THEN
        SET v_msg = 'El equipo está pausado: reanúdalo para finalizar el trabajo.';
    END IF;
    IF v_msg IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje; LEAVE proc;
    END IF;

    CALL SP_ArmarEtapasEquipoMovil(p_id_os, v_id_eq, v_conformes);
    SELECT COUNT(*) INTO v_n_pend FROM tmp_pend_eq;
    SELECT it.generado_en, it.numero_informe INTO v_gen, v_num_inf
    FROM   informe_tecnico it
    WHERE  it.id_os = p_id_os AND it.id_equipo = v_id_eq AND it.eliminado_en IS NULL
    ORDER BY it.id_informe DESC LIMIT 1;

    SELECT 2 AS IdTipoMensaje, IF(v_conformes = 5, 'Validación completa.', 'No es posible finalizar el trabajo en el equipo.') AS Mensaje;

    SELECT IF(v_conformes = 5 AND v_estado = 'en_ejecucion' AND v_gen IS NULL, 1, 0) AS puede_generar,
           IF(v_gen IS NULL, 0, 1) AS ya_generado, v_num_inf AS numero_informe,
           v_conformes AS conformes, 5 AS total, v_n_pend AS pendientes, v_estado AS estado_equipo,
           CONCAT(IFNULL(v_nombre, 'Equipo'), ' #', LPAD(IFNULL(v_numero, 0), 2, '0')) AS equipo, v_num_os AS numero_os;

    SELECT e.orden, e.codigo, e.nombre, e.estado, e.detalle,
           (SELECT COUNT(*) FROM tmp_pend_eq p WHERE p.orden = e.orden) AS n_pendientes
    FROM   tmp_etapas_mov e
    ORDER BY e.orden;

    SELECT p.orden, p.codigo, p.texto FROM tmp_pend_eq p ORDER BY p.orden, p.id;

    DROP TEMPORARY TABLE IF EXISTS tmp_etapas_mov;
    DROP TEMPORARY TABLE IF EXISTS tmp_pend_eq;
END$$

DELIMITER ;

-- ############################################################
-- 10) SP_GenerarInformeEquipoMovil
-- ############################################################
-- ============================================================
-- SP_GenerarInformeEquipoMovil  (App Mobile HU-16 — "Generar informe técnico" tras la Validación completa)
-- Con las 5 etapas conformes el técnico genera el informe técnico del equipo:
--   · el equipo pasa a COMPLETADO (os_equipo.estado_ejecucion = 'ejecutado'; se cierra su tramo de tiempo),
--   · el informe recibe su N° definitivo NNNN-AAAA de la secuencia propia (informe_secuencia, atómica; se copia también a informe_tecnico.numero, que era el borrador
--     BRR-########) y queda con generado_en / generado_por. Un informe generado es el que lista y firma la HU-17 (Firma de informes).
--   El informe NO cambia de estado (sigue 'borrador'): el envío a Revisión Técnica de la intranet corresponde al cierre del servicio (constancia, HU-17).
--   Reglas (una sola vez): el contexto lo valida SP_ContextoEquipoMovil (OS del técnico del token, Hard Stop de llegada, equipo iniciado); las 5 etapas
--   SP_ArmarEtapasEquipoMovil (la misma regla de SP_ValidarCierreEquipoMovil). Equipo EN EJECUCIÓN (no pausado). Idempotente: si el informe ya estaba generado
--   responde éxito con el mismo número (repetida = 1) sin tocar nada. Orden de bloqueos fijo: os_equipo → informe técnico → secuencia del año.
--   Auditoría: auditoria_evento (os_equipo y informe_tecnico).
-- Resultados: 1 mensaje (1 regla de negocio · 2 éxito · 3 error) · 2 (solo éxito) id_informe, numero_informe, estado_equipo, repetida.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_GenerarInformeEquipoMovil;

DELIMITER $$

CREATE PROCEDURE SP_GenerarInformeEquipoMovil(
    IN p_id_usuario   BIGINT,
    IN p_id_os        BIGINT,
    IN p_id_os_equipo BIGINT
)
proc: BEGIN
    DECLARE v_msg       VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_id_eq     BIGINT DEFAULT NULL;
    DECLARE v_estado    VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_hab       TINYINT DEFAULT 0;
    DECLARE v_numero    INT DEFAULT NULL;
    DECLARE v_nombre    VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_num_os    VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_servicio  VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_oe        BIGINT DEFAULT NULL;
    DECLARE v_informe   BIGINT DEFAULT NULL;
    DECLARE v_gen       DATETIME DEFAULT NULL;
    DECLARE v_num_inf   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_conformes INT DEFAULT 0;
    DECLARE v_anio      SMALLINT;
    DECLARE v_ultimo    INT DEFAULT 0;
    DECLARE v_n         INT;
    DECLARE v_cod       VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_ahora_utc DATETIME;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_etapas_mov;
        DROP TEMPORARY TABLE IF EXISTS tmp_pend_eq;
        DROP TEMPORARY TABLE IF EXISTS tmp_cat_evid;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 OR IFNULL(p_id_os_equipo, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio o equipo no encontrado.' AS Mensaje; LEAVE proc;
    END IF;

    START TRANSACTION;

    CALL SP_ContextoEquipoMovil(p_id_usuario, p_id_os, p_id_os_equipo, v_msg, v_id_eq, v_estado, v_hab, v_numero, v_nombre, v_num_os, v_servicio);
    IF v_msg IS NOT NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje; LEAVE proc;
    END IF;

    -- Bloqueos en orden fijo: el equipo (objetivo) y luego su informe
    SELECT oe.id INTO v_oe FROM os_equipo oe WHERE oe.id = p_id_os_equipo AND oe.id_os = p_id_os AND oe.eliminado_en IS NULL FOR UPDATE;
    SELECT it.id_informe, it.generado_en, it.numero_informe INTO v_informe, v_gen, v_num_inf
    FROM   informe_tecnico it
    WHERE  it.id_os = p_id_os AND it.id_equipo = v_id_eq AND it.eliminado_en IS NULL
    ORDER BY it.id_informe DESC LIMIT 1
    FOR UPDATE;

    IF v_gen IS NOT NULL THEN
        ROLLBACK;
        SELECT 2 AS IdTipoMensaje, 'El informe técnico ya estaba generado.' AS Mensaje;
        SELECT v_informe AS id_informe, v_num_inf AS numero_informe, 'completado' AS estado_equipo, 1 AS repetida;
        LEAVE proc;
    END IF;
    IF v_estado = 'pausado' THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'El equipo está pausado: reanúdalo para generar el informe.' AS Mensaje; LEAVE proc;
    ELSEIF v_estado <> 'en_ejecucion' OR v_hab = 0 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'El equipo debe estar en ejecución para generar el informe técnico.' AS Mensaje; LEAVE proc;
    END IF;

    -- Hard Stop: las 5 etapas conformes (la misma regla que SP_ValidarCierreEquipoMovil)
    CALL SP_ArmarEtapasEquipoMovil(p_id_os, v_id_eq, v_conformes);
    DROP TEMPORARY TABLE IF EXISTS tmp_etapas_mov;
    DROP TEMPORARY TABLE IF EXISTS tmp_pend_eq;
    IF v_informe IS NULL OR v_conformes < 5 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje,
               CONCAT('No es posible finalizar el trabajo en el equipo: ', 5 - v_conformes, IF(5 - v_conformes = 1, ' etapa está incompleta o no conforme.', ' etapas están incompletas o no conformes.'),
                      ' Revisa los pendientes.') AS Mensaje;
        LEAVE proc;
    END IF;

    -- N° del informe: la secuencia propia del año (se salta cualquier número ya usado)
    SET v_anio = YEAR(UTC_TIMESTAMP() - INTERVAL 5 HOUR);
    INSERT IGNORE INTO informe_secuencia (anio, ultimo) VALUES (v_anio, 0);
    SELECT s.ultimo INTO v_ultimo FROM informe_secuencia s WHERE s.anio = v_anio FOR UPDATE;
    SET v_n = v_ultimo + 1;
    SET v_cod = CONCAT(LPAD(v_n, 4, '0'), '-', v_anio);
    WHILE v_n <= 9999 AND EXISTS (SELECT 1 FROM informe_tecnico x WHERE x.numero_informe = v_cod OR x.numero = v_cod) DO
        SET v_n = v_n + 1;
        SET v_cod = CONCAT(LPAD(v_n, 4, '0'), '-', v_anio);
    END WHILE;
    IF v_n > 9999 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Se agotaron los números de informe del año.' AS Mensaje; LEAVE proc;
    END IF;
    UPDATE informe_secuencia SET ultimo = v_n WHERE anio = v_anio;

    SET v_ahora_utc = UTC_TIMESTAMP();
    UPDATE informe_tecnico
    SET    numero_informe = v_cod, numero = v_cod, generado_en = UTC_TIMESTAMP(), generado_por = p_id_usuario, modificado_por = p_id_usuario
    WHERE  id_informe = v_informe;

    -- El equipo queda COMPLETADO y se cierra su tramo de tiempo
    UPDATE os_equipo
    SET    estado_ejecucion = 'ejecutado', fecha_ejecucion = NOW(),
           acumulado_seg = acumulado_seg + IF(reanudado_utc IS NULL, 0, GREATEST(0, TIMESTAMPDIFF(SECOND, reanudado_utc, v_ahora_utc))),
           reanudado_utc = NULL, pausado = 0, motivo_pausa = NULL, pausa_requiere_aprobacion = 0, modificado_por = p_id_usuario
    WHERE  id = p_id_os_equipo;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('os_equipo', p_id_os_equipo, 'finalizar_equipo', 'en ejecución', 'completado',
            LEFT(CONCAT('Trabajo finalizado en ', IFNULL(v_nombre, 'el equipo'), ' (', v_num_os, '). Informe técnico ', v_cod, '.'), 300),
            p_id_usuario, NOW(), JSON_OBJECT('id_os', p_id_os, 'numero_informe', v_cod));
    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('informe_tecnico', v_informe, 'generar_informe', 'borrador', v_cod,
            LEFT(CONCAT('Informe técnico ', v_cod, ' generado desde la app (HU-16) con las 5 etapas conformes.'), 300),
            p_id_usuario, NOW(), JSON_OBJECT('id_os', p_id_os, 'id_os_equipo', p_id_os_equipo, 'numero_informe', v_cod));

    COMMIT;

    SELECT 2 AS IdTipoMensaje, CONCAT('Informe técnico ', v_cod, ' generado.') AS Mensaje;
    SELECT v_informe AS id_informe, v_cod AS numero_informe, 'completado' AS estado_equipo, 0 AS repetida;
END$$

DELIMITER ;

-- ############################################################
-- 11) SP_ObtenerCabeceraInformeMovil
-- ############################################################
-- ============================================================
-- SP_ObtenerCabeceraInformeMovil  (App Mobile HU-15 — Cabecera del informe: Datos · Detalle Serv. · Observación y pruebas · solo lectura)
-- Todo lo que muestran las 3 pestañas de la cabecera del informe del equipo (informe_tecnico y sus hijas, migraciones 93 / 100 / 104). El técnico sale del token; el
-- contexto (OS suya, Hard Stop de llegada, equipo iniciado) lo valida SP_ContextoEquipoMovil, UNA sola vez; el tipo de orden OS / OM, SP_TipoOrdenMovil.
--   Datos: N° de informe (NNNN-AAAA al generar; antes NULL), RQ, orden, cliente (empresa, dirección, contacto), equipo (marca, modelo, serie, código, capacidad, d, e,
--     COD TW, ubicación, clase), datos del informe (propuesta, comercial, técnico, fecha, horas, tipo de servicio) y "Quién atiende en planta" (lo guardado o, si no hay,
--     el contacto de la OS).
--   puede_editar = el equipo está EN EJECUCIÓN y el informe aún no se generó (HU-16). Sin informe todavía, todo sale vacío: se crea al primer guardado.
-- Resultados: 1 mensaje · 2 cabecera (1 fila) · 3 checklist de Detalle Serv. (catálogo CHECKLIST_SERVICIO del tipo OS / OM, con lo marcado) · 4 recomendaciones ·
--   5 fallas · 6 fotos de las fallas · 7 pruebas de las fallas · 8 ensayos de HU-10 (Pruebas generales, formato resumido) · 9 opciones (tipos de equipo, clasificación y
--   componente de las fallas).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerCabeceraInformeMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerCabeceraInformeMovil(
    IN p_id_usuario   BIGINT,
    IN p_id_os        BIGINT,
    IN p_id_os_equipo BIGINT
)
proc: BEGIN
    DECLARE v_msg      VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_id_eq    BIGINT DEFAULT NULL;
    DECLARE v_estado   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_hab      TINYINT DEFAULT 0;
    DECLARE v_numero   INT DEFAULT NULL;
    DECLARE v_nombre   VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_num_os   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_servicio VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_tipo     VARCHAR(2) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT 'OS';
    DECLARE v_rq       VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_informe  BIGINT DEFAULT NULL;
    DECLARE v_gen      DATETIME DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 OR IFNULL(p_id_os_equipo, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio o equipo no encontrado.' AS Mensaje; LEAVE proc;
    END IF;

    CALL SP_ContextoEquipoMovil(p_id_usuario, p_id_os, p_id_os_equipo, v_msg, v_id_eq, v_estado, v_hab, v_numero, v_nombre, v_num_os, v_servicio);
    IF v_msg IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje; LEAVE proc;
    END IF;
    CALL SP_TipoOrdenMovil(p_id_os, v_tipo, v_rq);

    SELECT it.id_informe, it.generado_en INTO v_informe, v_gen
    FROM   informe_tecnico it
    WHERE  it.id_os = p_id_os AND it.id_equipo = v_id_eq AND it.eliminado_en IS NULL
    ORDER BY it.id_informe DESC LIMIT 1;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Cabecera: Datos, Detalle Serv. (JSON), Diagnóstico final
    SELECT p_id_os AS id_os, v_num_os AS numero_os, v_tipo AS tipo_orden, v_rq AS numero_rq,
           v_informe AS id_informe, it.numero_informe, IF(v_gen IS NULL, 0, 1) AS generado,
           IF(v_estado = 'en_ejecucion' AND v_hab = 1 AND v_gen IS NULL, 1, 0) AS puede_editar,
           c.razon_social AS empresa, c.ruc AS ruc, sc.direccion_exacta AS direccion,
           co.nombres AS contacto, co.cargo AS contacto_cargo, NULLIF(TRIM(co.telefono_movil), '') AS contacto_telefono, NULLIF(TRIM(co.correo), '') AS contacto_correo,
           ec.marca, ec.modelo, NULLIF(TRIM(ec.num_serie), '') AS num_serie, NULLIF(ec.codigo_cliente, '') AS codigo_cliente, ec.codigo_tw,
           ec.alcance_maximo AS capacidad_max, ec.division_minima AS d, IF(ec.division_verif_igual = 1, ec.division_minima, ec.division_verif) AS e,
           NULLIF(ec.ubicacion_especifica, '') AS ubicacion, ec.clase_exactitud AS clase, ec.clasificacion AS tipo_equipo,
           pr.numero AS propuesta, NULLIF(TRIM(CONCAT(IFNULL(ucom.nombre, ''), ' ', IFNULL(ucom.apellido, ''))), '') AS comercial,
           NULLIF(TRIM(CONCAT(IFNULL(ut.nombre, ''), ' ', IFNULL(ut.apellido, ''))), '') AS tecnico,
           os.fecha_ejecucion AS fecha,
           TIME_FORMAT(COALESCE(os.hora_llegada_real, os.hora_inicio), '%H:%i') AS hora_inicio,
           TIME_FORMAT(COALESCE(os.hora_fin_real, os.hora_fin_estimada), '%H:%i') AS hora_fin,
           ts.String1 AS tipo_servicio,
           COALESCE(NULLIF(TRIM(it.responsable_nombre), ''), co.nombres)                  AS responsable_nombre,
           COALESCE(NULLIF(TRIM(it.responsable_cargo), ''), co.cargo)                     AS responsable_cargo,
           COALESCE(NULLIF(TRIM(it.responsable_telefono), ''), NULLIF(TRIM(co.telefono_movil), '')) AS responsable_telefono,
           it.detalle_servicio, it.comentario_pruebas, IFNULL(it.sin_recomendaciones, 0) AS sin_recomendaciones, IFNULL(it.sin_fallas, 0) AS sin_fallas,
           it.severidad_general, it.estado_equipo_final,
           IFNULL(it.rev_jefatura, 0) AS rev_jefatura, IFNULL(it.requiere_precotizacion, 0) AS requiere_precotizacion,
           IFNULL(it.segunda_visita, 0) AS segunda_visita, IFNULL(it.aplica_garantia, 0) AS aplica_garantia, it.cabecera_guardada_en AS guardada_en,
           it.error_critico_motivo AS error_critico, it.ensayos_finalizado_en AS ensayos_finalizados_en
    FROM   orden_servicio os
    JOIN   equipo_cliente ec          ON ec.id_equipo = v_id_eq
    LEFT JOIN informe_tecnico it      ON it.id_informe = v_informe
    LEFT JOIN cliente c               ON c.id_cliente = os.id_cliente
    LEFT JOIN sede_cliente sc         ON sc.id_sede = os.id_sede
    LEFT JOIN contacto_cliente co     ON co.id_contacto = os.id_contacto
    LEFT JOIN expediente_digital ed   ON ed.id_expediente = os.id_expediente
    LEFT JOIN propuesta_comercial pr  ON pr.id_propuesta = COALESCE(os.id_propuesta, ed.id_propuesta)
    LEFT JOIN usuario ucom            ON ucom.id_usuario = pr.id_creador
    LEFT JOIN usuario ut              ON ut.id_usuario = p_id_usuario
    LEFT JOIN tabla_maestra ts        ON ts.Descripcion = 'TIPO_SERVICIO' AND ts.IdEmpresa = 1 AND ts.Num1 = os.id_tipo_servicio
    WHERE  os.id_os = p_id_os;

    -- 3. Checklist de Detalle Serv.: el del tipo de orden (OS / OM), con lo marcado
    SELECT m.String2 AS codigo, m.String1 AS titulo, m.Num1 AS orden,
           IF(EXISTS (SELECT 1 FROM informe_procedimiento ip
                      WHERE ip.id_informe = v_informe AND ip.codigo = m.String2 AND ip.realizado = 1 AND ip.eliminado_en IS NULL), 1, 0) AS marcado
    FROM   tabla_maestra m
    WHERE  m.Descripcion = 'CHECKLIST_SERVICIO' AND m.IdEmpresa = 1 AND m.String3 = v_tipo AND m.eliminado_en IS NULL
    ORDER BY m.Num1;

    -- 4. Recomendaciones inmediatas
    SELECT r.id_recomendacion, r.codigo, r.titulo, r.descripcion, r.prioridad, r.plazo
    FROM   informe_recomendacion r
    WHERE  r.id_informe = v_informe AND r.origen = 'tecnico' AND r.eliminado_en IS NULL
    ORDER BY r.orden, r.id_recomendacion;

    -- 5. Fallas
    SELECT o.id_observacion, o.codigo, o.orden, o.clasificacion, o.componente, o.titulo AS componente_nombre, o.detalle_extra AS clasificacion_nombre,
           o.descripcion, o.nivel_afectacion
    FROM   informe_observacion o
    WHERE  o.id_informe = v_informe AND o.origen = 'tecnico' AND o.eliminado_en IS NULL
    ORDER BY o.orden, o.id_observacion;

    -- 6. Fotos de las fallas
    SELECT f.id_observacion, f.id_evidencia
    FROM   evidencia_fotografica f
    WHERE  f.id_os = p_id_os AND f.id_equipo = v_id_eq AND f.codigo = 'falla' AND f.eliminado_en IS NULL AND f.id_observacion IS NOT NULL
      AND  EXISTS (SELECT 1 FROM informe_observacion o WHERE o.id_observacion = f.id_observacion AND o.id_informe = v_informe AND o.eliminado_en IS NULL)
    ORDER BY f.id_observacion, f.id_evidencia;

    -- 7. Pruebas que justifican cada falla
    SELECT p.id_observacion, p.tipo, p.orden, p.posicion, p.carga, p.indicacion, p.error, p.emp, p.resultado
    FROM   informe_observacion_prueba p
    JOIN   informe_observacion o ON o.id_observacion = p.id_observacion
    WHERE  o.id_informe = v_informe AND o.origen = 'tecnico' AND o.eliminado_en IS NULL AND p.eliminado_en IS NULL
    ORDER BY o.orden, p.tipo, p.orden, p.id_prueba;

    -- 8. Pruebas generales (formato resumido): lo que guardó Ensayos y Calibración (HU-10)
    SELECT en.tipo, IFNULL(en.grupo, 0) AS grupo, en.orden, en.punto, en.carga, en.lectura, en.error, en.tolerancia, en.resultado, en.critico
    FROM   informe_ensayo en
    WHERE  en.id_informe = v_informe AND en.origen = 'tecnico' AND en.eliminado_en IS NULL
    ORDER BY (en.tipo = 'excentricidad'), en.grupo, en.orden, en.id_ensayo;

    -- 9. Opciones de las listas
    SELECT 'tipo_equipo' AS lista, m.String2 AS codigo, m.String1 AS nombre, NULL AS padre
    FROM   tabla_maestra m WHERE m.Descripcion = 'CLASIFICACION_EQUIPO' AND m.IdEmpresa = 1 AND m.eliminado_en IS NULL
    UNION ALL
    SELECT 'clasificacion', m.String2, m.String1, NULL
    FROM   tabla_maestra m WHERE m.Descripcion = 'CLASIFICACION_FALLA' AND m.IdEmpresa = 1 AND m.eliminado_en IS NULL
    UNION ALL
    SELECT 'componente', m.String2, m.String1, m.String3
    FROM   tabla_maestra m WHERE m.Descripcion = 'COMPONENTE_FALLA' AND m.IdEmpresa = 1 AND m.eliminado_en IS NULL
    ORDER BY lista, nombre;
END$$

DELIMITER ;

-- ############################################################
-- 12) SP_GuardarCabeceraInformeMovil
-- ############################################################
-- ============================================================
-- SP_GuardarCabeceraInformeMovil  (App Mobile HU-15 — guardar la Cabecera del informe: Datos · Detalle Serv. · Observación y pruebas)
-- El técnico guarda lo que digitó en las 3 pestañas. Una sección que NO viene en el JSON no se toca; una que viene REEMPLAZA lo que el técnico había guardado
-- (lo que agregue el supervisor en la intranet, origen = 'supervisor', nunca se toca).
--   p_json = {
--     "datos":   {"responsableNombre","responsableCargo","responsableTelefono"}                         → "Quién atiende en planta"
--     "detalle": {"tipoEquipo","celdas":[mV…],"sumatoriaHasta","comparacionHasta","anillosFijacion","checks":["codigo"…]}   → Detalle Serv.
--     "recomendaciones":[{"titulo","descripcion","prioridad"}] · "sinRecomendaciones":bool
--     "fallas":[{"clasificacion","componente","severidad","descripcion","fotos":[idEvidencia…],"pruebas":[{"tipo","posicion","carga","indicacion"}]}] · "sinFallas":bool
--     "comentarioPruebas" · "diagnostico":{"severidadGeneral","estadoEquipo","revisionJefatura","precotizacion","segundaVisita","aplicaGarantia"} }
--   Reglas: la OS es del técnico, Hard Stop de llegada y equipo iniciado (SP_ContextoEquipoMovil); el equipo EN EJECUCIÓN y el informe aún sin generar (HU-16).
--   REGLA DE LA HU-15: cada falla exige una prueba que la justifique (repetibilidad, pesaje o excentricidad) con L e I digitados; el servidor CALCULA E = I − L y el EMP
--   (SP_EmpEnsayoMovil, el mismo de Ensayos y Calibración) y la conformidad de cada lectura. Las fotos de una falla son capturas ya subidas con SP_RegistrarFotoFallaMovil
--   (de este técnico y este equipo). El checklist se valida contra el catálogo CHECKLIST_SERVICIO del tipo de orden (OS / OM, SP_TipoOrdenMovil).
--   Se bloquea el equipo y luego el informe (se crea el borrador si aún no existe). Auditoría: auditoria_evento (informe_tecnico).
-- Resultados: 1 mensaje (1 regla de negocio · 2 éxito · 3 error) · 2 (solo éxito) id_informe, guardada_en, n_fallas, n_recomendaciones.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_GuardarCabeceraInformeMovil;

DELIMITER $$

CREATE PROCEDURE SP_GuardarCabeceraInformeMovil(
    IN p_id_usuario   BIGINT,
    IN p_id_os        BIGINT,
    IN p_id_os_equipo BIGINT,
    IN p_json         LONGTEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_msg      VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_err      VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_id_eq    BIGINT DEFAULT NULL;
    DECLARE v_estado   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_hab      TINYINT DEFAULT 0;
    DECLARE v_numero   INT DEFAULT NULL;
    DECLARE v_nombre   VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_num_os   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_servicio VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_oe       BIGINT DEFAULT NULL;
    DECLARE v_informe  BIGINT DEFAULT NULL;
    DECLARE v_gen      DATETIME DEFAULT NULL;
    DECLARE v_tipo     VARCHAR(2) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT 'OS';
    DECLARE v_rq       VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_clase    VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_unidad   VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cap      DECIMAL(14,4);
    DECLARE v_d        DECIMAL(14,4);
    DECLARE v_e        DECIMAL(14,4);
    DECLARE v_h_datos  TINYINT DEFAULT 0;
    DECLARE v_h_det    TINYINT DEFAULT 0;
    DECLARE v_h_rec    TINYINT DEFAULT 0;
    DECLARE v_h_fal    TINYINT DEFAULT 0;
    DECLARE v_h_diag   TINYINT DEFAULT 0;
    DECLARE v_h_com    TINYINT DEFAULT 0;
    DECLARE v_h_sinrec TINYINT DEFAULT 0;
    DECLARE v_h_sinfal TINYINT DEFAULT 0;
    DECLARE v_r_nom    VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_r_car    VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_r_tel    VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_d_tipo   VARCHAR(60) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_d_suma   DECIMAL(14,4) DEFAULT NULL;
    DECLARE v_d_comp   DECIMAL(14,4) DEFAULT NULL;
    DECLARE v_d_anillo VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_com      VARCHAR(700) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_sinrec   VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_sinfal   VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_sev      VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_est_eq   VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_t_rev    VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_t_pre    VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_t_seg    VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_t_gar    VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_n_rec    INT DEFAULT 0;
    DECLARE v_n_fal    INT DEFAULT 0;
    DECLARE v_n_pru    INT DEFAULT 0;
    DECLARE v_n_celdas INT DEFAULT 0;
    DECLARE v_i        INT DEFAULT 0;
    DECLARE v_fila     INT;
    DECLARE v_carga    DECIMAL(14,4);
    DECLARE v_emp      DECIMAL(14,4);
    DECLARE v_f_cla    VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_f_com    VARCHAR(60) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_f_sev    VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_f_des    VARCHAR(1500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cla_nom  VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_com_nom  VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_obs      BIGINT;
    DECLARE v_nombre_tec VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_cab_rec;
        DROP TEMPORARY TABLE IF EXISTS tmp_cab_fal;
        DROP TEMPORARY TABLE IF EXISTS tmp_cab_pru;
        DROP TEMPORARY TABLE IF EXISTS tmp_cab_foto;
        DROP TEMPORARY TABLE IF EXISTS tmp_cab_chk;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 OR IFNULL(p_id_os_equipo, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio o equipo no encontrado.' AS Mensaje; LEAVE proc;
    END IF;
    IF p_json IS NULL OR NOT JSON_VALID(p_json) OR CHAR_LENGTH(p_json) > 60000 OR JSON_TYPE(p_json) <> 'OBJECT' THEN
        SELECT 1 AS IdTipoMensaje, 'Los datos de la cabecera no son válidos.' AS Mensaje; LEAVE proc;
    END IF;

    START TRANSACTION;

    CALL SP_ContextoEquipoMovil(p_id_usuario, p_id_os, p_id_os_equipo, v_msg, v_id_eq, v_estado, v_hab, v_numero, v_nombre, v_num_os, v_servicio);
    IF v_msg IS NULL AND (v_hab = 0 OR v_estado <> 'en_ejecucion') THEN
        SET v_msg = IF(v_estado = 'pausado', 'El equipo está pausado: reanúdalo para guardar la cabecera del informe.',
                       IF(v_estado = 'completado', 'Este equipo ya está completado: el informe no se puede modificar.', 'El servicio ya no está en curso: no se puede guardar la cabecera.'));
    END IF;
    IF v_msg IS NOT NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje; LEAVE proc;
    END IF;

    -- Bloqueos en orden fijo: el equipo (objetivo) y luego su informe (se crea el borrador si todavía no existe)
    SELECT oe.id INTO v_oe FROM os_equipo oe WHERE oe.id = p_id_os_equipo AND oe.id_os = p_id_os AND oe.eliminado_en IS NULL FOR UPDATE;
    SELECT it.id_informe, it.generado_en INTO v_informe, v_gen
    FROM   informe_tecnico it
    WHERE  it.id_os = p_id_os AND it.id_equipo = v_id_eq AND it.eliminado_en IS NULL
    ORDER BY it.id_informe DESC LIMIT 1
    FOR UPDATE;
    IF v_gen IS NOT NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'El informe técnico ya fue generado: no se puede modificar la cabecera.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_informe IS NULL THEN
        INSERT INTO informe_tecnico (numero, id_os, id_equipo, id_tecnico, estado, version, fecha_creacion, creado_por)
        VALUES (CONCAT('BRR-', FLOOR(RAND() * 1000000000)), p_id_os, v_id_eq, p_id_usuario, 'borrador', 1, NOW(), p_id_usuario);
        SET v_informe = LAST_INSERT_ID();
        UPDATE informe_tecnico SET numero = CONCAT('BRR-', LPAD(v_informe, 8, '0')) WHERE id_informe = v_informe;
    END IF;

    CALL SP_TipoOrdenMovil(p_id_os, v_tipo, v_rq);
    CALL SP_EspecEquipoMovil(v_id_eq, v_clase, v_unidad, v_cap, v_d, v_e);

    -- ── Qué secciones vienen ───────────────────────────────────────────────────────────────────
    SET v_h_datos  = IF(JSON_CONTAINS_PATH(p_json, 'one', '$.datos'), 1, 0);
    SET v_h_det    = IF(JSON_CONTAINS_PATH(p_json, 'one', '$.detalle'), 1, 0);
    SET v_h_rec    = IF(JSON_CONTAINS_PATH(p_json, 'one', '$.recomendaciones'), 1, 0);
    SET v_h_fal    = IF(JSON_CONTAINS_PATH(p_json, 'one', '$.fallas'), 1, 0);
    SET v_h_diag   = IF(JSON_CONTAINS_PATH(p_json, 'one', '$.diagnostico'), 1, 0);
    SET v_h_com    = IF(JSON_CONTAINS_PATH(p_json, 'one', '$.comentarioPruebas'), 1, 0);
    SET v_h_sinrec = IF(JSON_CONTAINS_PATH(p_json, 'one', '$.sinRecomendaciones'), 1, 0);
    SET v_h_sinfal = IF(JSON_CONTAINS_PATH(p_json, 'one', '$.sinFallas'), 1, 0);

    -- ── Valores sueltos (una sola lectura del JSON) ────────────────────────────────────────────
    SELECT jt.r_nom, jt.r_car, jt.r_tel, jt.d_tipo, jt.d_suma, jt.d_comp, jt.d_anillo, jt.com, jt.sinrec, jt.sinfal, jt.sev, jt.est_eq, jt.t_rev, jt.t_pre, jt.t_seg, jt.t_gar
    INTO   v_r_nom, v_r_car, v_r_tel, v_d_tipo, v_d_suma, v_d_comp, v_d_anillo, v_com, v_sinrec, v_sinfal, v_sev, v_est_eq, v_t_rev, v_t_pre, v_t_seg, v_t_gar
    FROM   JSON_TABLE(p_json, '$' COLUMNS (
               r_nom    VARCHAR(300)  PATH '$.datos.responsableNombre'   NULL ON EMPTY NULL ON ERROR,
               r_car    VARCHAR(300)  PATH '$.datos.responsableCargo'    NULL ON EMPTY NULL ON ERROR,
               r_tel    VARCHAR(100)  PATH '$.datos.responsableTelefono' NULL ON EMPTY NULL ON ERROR,
               d_tipo   VARCHAR(60)   PATH '$.detalle.tipoEquipo'        NULL ON EMPTY NULL ON ERROR,
               d_suma   DECIMAL(14,4) PATH '$.detalle.sumatoriaHasta'    NULL ON EMPTY NULL ON ERROR,
               d_comp   DECIMAL(14,4) PATH '$.detalle.comparacionHasta'  NULL ON EMPTY NULL ON ERROR,
               d_anillo VARCHAR(10)   PATH '$.detalle.anillosFijacion'   NULL ON EMPTY NULL ON ERROR,
               com      VARCHAR(700)  PATH '$.comentarioPruebas'         NULL ON EMPTY NULL ON ERROR,
               sinrec   VARCHAR(10)   PATH '$.sinRecomendaciones'        NULL ON EMPTY NULL ON ERROR,
               sinfal   VARCHAR(10)   PATH '$.sinFallas'                 NULL ON EMPTY NULL ON ERROR,
               sev      VARCHAR(20)   PATH '$.diagnostico.severidadGeneral'  NULL ON EMPTY NULL ON ERROR,
               est_eq   VARCHAR(30)   PATH '$.diagnostico.estadoEquipo'      NULL ON EMPTY NULL ON ERROR,
               t_rev    VARCHAR(10)   PATH '$.diagnostico.revisionJefatura'  NULL ON EMPTY NULL ON ERROR,
               t_pre    VARCHAR(10)   PATH '$.diagnostico.precotizacion'     NULL ON EMPTY NULL ON ERROR,
               t_seg    VARCHAR(10)   PATH '$.diagnostico.segundaVisita'     NULL ON EMPTY NULL ON ERROR,
               t_gar    VARCHAR(10)   PATH '$.diagnostico.aplicaGarantia'    NULL ON EMPTY NULL ON ERROR)) jt;
    SET v_r_nom = NULLIF(TRIM(NULLIF(v_r_nom, 'null')), '');
    SET v_r_car = NULLIF(TRIM(NULLIF(v_r_car, 'null')), '');
    SET v_r_tel = NULLIF(TRIM(NULLIF(v_r_tel, 'null')), '');
    SET v_d_tipo = NULLIF(TRIM(NULLIF(v_d_tipo, 'null')), '');
    SET v_com    = NULLIF(TRIM(NULLIF(v_com, 'null')), '');
    SET v_sev    = NULLIF(NULLIF(v_sev, 'null'), '');
    SET v_est_eq = NULLIF(NULLIF(v_est_eq, 'null'), '');

    -- ── Secciones en tablas temporales ─────────────────────────────────────────────────────────
    DROP TEMPORARY TABLE IF EXISTS tmp_cab_rec;
    CREATE TEMPORARY TABLE tmp_cab_rec (n INT NOT NULL, titulo VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, descripcion VARCHAR(1500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
                                        prioridad VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, PRIMARY KEY (n));
    INSERT INTO tmp_cab_rec (n, titulo, descripcion, prioridad)
    SELECT jt.n, jt.titulo, jt.descripcion, jt.prioridad
    FROM   JSON_TABLE(p_json, '$.recomendaciones[*]' COLUMNS (
               n FOR ORDINALITY,
               titulo      VARCHAR(300)  PATH '$.titulo'      NULL ON EMPTY NULL ON ERROR,
               descripcion VARCHAR(1500) PATH '$.descripcion' NULL ON EMPTY NULL ON ERROR,
               prioridad   VARCHAR(10)   PATH '$.prioridad'   NULL ON EMPTY NULL ON ERROR)) jt;

    DROP TEMPORARY TABLE IF EXISTS tmp_cab_fal;
    CREATE TEMPORARY TABLE tmp_cab_fal (n INT NOT NULL, clasificacion VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, componente VARCHAR(60) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
                                        severidad VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, descripcion VARCHAR(1500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, PRIMARY KEY (n));
    INSERT INTO tmp_cab_fal (n, clasificacion, componente, severidad, descripcion)
    SELECT jt.n, jt.clasificacion, jt.componente, jt.severidad, jt.descripcion
    FROM   JSON_TABLE(p_json, '$.fallas[*]' COLUMNS (
               n FOR ORDINALITY,
               clasificacion VARCHAR(40)   PATH '$.clasificacion' NULL ON EMPTY NULL ON ERROR,
               componente    VARCHAR(60)   PATH '$.componente'    NULL ON EMPTY NULL ON ERROR,
               severidad     VARCHAR(10)   PATH '$.severidad'     NULL ON EMPTY NULL ON ERROR,
               descripcion   VARCHAR(1500) PATH '$.descripcion'   NULL ON EMPTY NULL ON ERROR)) jt;

    DROP TEMPORARY TABLE IF EXISTS tmp_cab_pru;
    CREATE TEMPORARY TABLE tmp_cab_pru (id INT NOT NULL AUTO_INCREMENT, falla INT NOT NULL, m INT NOT NULL, tipo VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, posicion INT NULL,
                                        carga DECIMAL(14,4) NULL, ind DECIMAL(14,4) NULL, emp DECIMAL(14,4) NULL, err DECIMAL(14,4) NULL, res VARCHAR(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
                                        PRIMARY KEY (id));
    INSERT INTO tmp_cab_pru (falla, m, tipo, posicion, carga, ind)
    SELECT jt.f, jt.m, jt.tipo, jt.posicion, jt.carga, jt.ind
    FROM   JSON_TABLE(p_json, '$.fallas[*]' COLUMNS (
               f FOR ORDINALITY,
               NESTED PATH '$.pruebas[*]' COLUMNS (
                   m FOR ORDINALITY,
                   tipo     VARCHAR(20)   PATH '$.tipo'       NULL ON EMPTY NULL ON ERROR,
                   posicion INT           PATH '$.posicion'   NULL ON EMPTY NULL ON ERROR,
                   carga    DECIMAL(14,4) PATH '$.carga'      NULL ON EMPTY NULL ON ERROR,
                   ind      DECIMAL(14,4) PATH '$.indicacion' NULL ON EMPTY NULL ON ERROR))) jt
    WHERE  jt.m IS NOT NULL;

    DROP TEMPORARY TABLE IF EXISTS tmp_cab_foto;
    CREATE TEMPORARY TABLE tmp_cab_foto (id INT NOT NULL AUTO_INCREMENT, falla INT NOT NULL, id_evidencia BIGINT NULL, PRIMARY KEY (id));
    INSERT INTO tmp_cab_foto (falla, id_evidencia)
    SELECT jt.f, jt.foto
    FROM   JSON_TABLE(p_json, '$.fallas[*]' COLUMNS (
               f FOR ORDINALITY,
               NESTED PATH '$.fotos[*]' COLUMNS (foto BIGINT PATH '$' NULL ON EMPTY NULL ON ERROR))) jt
    WHERE  jt.foto IS NOT NULL;

    DROP TEMPORARY TABLE IF EXISTS tmp_cab_chk;
    CREATE TEMPORARY TABLE tmp_cab_chk (codigo VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL, PRIMARY KEY (codigo));
    INSERT IGNORE INTO tmp_cab_chk (codigo)
    SELECT jt.codigo FROM JSON_TABLE(p_json, '$.detalle.checks[*]' COLUMNS (codigo VARCHAR(40) PATH '$' NULL ON EMPTY NULL ON ERROR)) jt WHERE jt.codigo IS NOT NULL;

    SELECT COUNT(*) INTO v_n_rec FROM tmp_cab_rec;
    SELECT COUNT(*) INTO v_n_fal FROM tmp_cab_fal;
    SELECT COUNT(*) INTO v_n_pru FROM tmp_cab_pru;
    SET v_n_celdas = IFNULL(JSON_LENGTH(JSON_EXTRACT(p_json, '$.detalle.celdas')), 0);

    -- ── Validación (primer error en orden) ─────────────────────────────────────────────────────
    IF v_h_datos = 1 AND (CHAR_LENGTH(IFNULL(v_r_nom, '')) > 150 OR CHAR_LENGTH(IFNULL(v_r_car, '')) > 100 OR CHAR_LENGTH(IFNULL(v_r_tel, '')) > 30) THEN
        SET v_err = 'Revisa "Quién atiende en planta": nombre hasta 150 caracteres, cargo hasta 100 y teléfono hasta 30.';
    ELSEIF v_h_det = 1 AND (JSON_TYPE(JSON_EXTRACT(p_json, '$.detalle')) <> 'OBJECT' OR CHAR_LENGTH(JSON_EXTRACT(p_json, '$.detalle')) > 4000) THEN
        SET v_err = 'Los datos de Detalle Serv. no son válidos.';
    ELSEIF v_h_det = 1 AND v_d_tipo IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM tabla_maestra m WHERE m.Descripcion = 'CLASIFICACION_EQUIPO' AND m.IdEmpresa = 1 AND m.String2 = v_d_tipo) THEN
        SET v_err = 'El tipo de equipo no es válido.';
    ELSEIF v_h_det = 1 AND (v_n_celdas > 12
           OR (v_n_celdas > 0 AND (SELECT COUNT(*) FROM JSON_TABLE(p_json, '$.detalle.celdas[*]' COLUMNS (v DECIMAL(14,4) PATH '$' NULL ON EMPTY NULL ON ERROR)) c
                                   WHERE c.v IS NULL OR ABS(c.v) > 100000) > 0)) THEN
        SET v_err = 'Las celdas (mV) deben ser números, hasta 12 celdas.';
    ELSEIF v_h_det = 1 AND ((v_d_suma IS NOT NULL AND (v_d_suma < 0 OR v_d_suma > 100000000)) OR (v_d_comp IS NOT NULL AND (v_d_comp < 0 OR v_d_comp > 100000000))) THEN
        SET v_err = 'Las pruebas por sumatoria y por comparación deben ser valores positivos.';
    ELSEIF v_h_det = 1 AND (SELECT COUNT(*) FROM tmp_cab_chk c
                            WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra m WHERE m.Descripcion = 'CHECKLIST_SERVICIO' AND m.IdEmpresa = 1 AND m.String3 = v_tipo AND m.String2 = c.codigo)) > 0 THEN
        SET v_err = 'El checklist tiene un paso que no corresponde a este tipo de orden.';
    ELSEIF v_h_rec = 1 AND v_n_rec > 20 THEN
        SET v_err = 'Se admiten hasta 20 recomendaciones.';
    ELSEIF v_h_rec = 1 AND (SELECT COUNT(*) FROM tmp_cab_rec r
                            WHERE r.titulo IS NULL OR CHAR_LENGTH(TRIM(r.titulo)) < 3 OR CHAR_LENGTH(TRIM(r.titulo)) > 200
                               OR CHAR_LENGTH(IFNULL(r.descripcion, '')) > 1000 OR IFNULL(r.prioridad, 'alta') NOT IN ('alta', 'media', 'baja')) > 0 THEN
        SET v_err = 'Cada recomendación necesita un texto de 3 a 200 caracteres y una prioridad válida.';
    ELSEIF v_h_fal = 1 AND v_n_fal > 15 THEN
        SET v_err = 'Se admiten hasta 15 fallas.';
    ELSEIF v_h_fal = 1 AND (SELECT COUNT(*) FROM tmp_cab_fal f
                            WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra m WHERE m.Descripcion = 'CLASIFICACION_FALLA' AND m.IdEmpresa = 1 AND m.String2 = f.clasificacion)) > 0 THEN
        SET v_err = 'Elige la clasificación de cada falla.';
    ELSEIF v_h_fal = 1 AND (SELECT COUNT(*) FROM tmp_cab_fal f
                            WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra m WHERE m.Descripcion = 'COMPONENTE_FALLA' AND m.IdEmpresa = 1 AND m.String2 = f.componente AND m.String3 = f.clasificacion)) > 0 THEN
        SET v_err = 'Elige el componente de cada falla (debe corresponder a su clasificación).';
    ELSEIF v_h_fal = 1 AND (SELECT COUNT(*) FROM tmp_cab_fal f WHERE IFNULL(f.severidad, '') NOT IN ('baja', 'media', 'alta', 'critica')) > 0 THEN
        SET v_err = 'Elige la severidad de cada falla (Baja, Media, Alta o Crítica).';
    ELSEIF v_h_fal = 1 AND (SELECT COUNT(*) FROM tmp_cab_fal f WHERE f.descripcion IS NULL OR CHAR_LENGTH(TRIM(f.descripcion)) < 5 OR CHAR_LENGTH(TRIM(f.descripcion)) > 1000) > 0 THEN
        SET v_err = 'Describe cada falla (de 5 a 1000 caracteres).';
    ELSEIF v_h_fal = 1 AND (SELECT COUNT(*) FROM tmp_cab_pru p WHERE IFNULL(p.tipo, '') NOT IN ('repetibilidad', 'pesaje', 'excentricidad')
                               OR p.carga IS NULL OR p.carga <= 0 OR p.carga > 100000000 OR p.ind IS NULL OR p.ind < 0 OR p.ind > 100000000
                               OR (p.posicion IS NOT NULL AND (p.posicion < 1 OR p.posicion > 9))) > 0 THEN
        SET v_err = 'Revisa la prueba de cada falla: tipo válido, carga L mayor que 0 e indicación I digitada.';
    ELSEIF v_h_fal = 1 AND (SELECT COUNT(*) FROM (SELECT p.falla FROM tmp_cab_pru p GROUP BY p.falla HAVING COUNT(*) > 12) x) > 0 THEN
        SET v_err = 'Una falla admite hasta 12 lecturas de prueba.';
    ELSEIF v_h_fal = 1 THEN
        -- La regla de la HU-15: cada falla exige una prueba que la justifique
        SELECT CONCAT('La falla ', f.n, ' necesita una prueba que la justifique (Repetibilidad, Pesaje o Excentricidad con L e I).') INTO v_err
        FROM   tmp_cab_fal f
        WHERE  NOT EXISTS (SELECT 1 FROM tmp_cab_pru p WHERE p.falla = f.n)
        ORDER BY f.n LIMIT 1;
    END IF;
    IF v_err IS NULL AND v_h_fal = 1 AND (SELECT COUNT(*) FROM (SELECT ft.falla FROM tmp_cab_foto ft GROUP BY ft.falla HAVING COUNT(*) > 5) x) > 0 THEN
        SET v_err = 'Una falla admite hasta 5 fotos.';
    END IF;
    IF v_err IS NULL AND v_h_fal = 1 AND (SELECT COUNT(*) FROM (SELECT ft.id_evidencia FROM tmp_cab_foto ft GROUP BY ft.id_evidencia HAVING COUNT(*) > 1) x) > 0 THEN
        SET v_err = 'Una foto no puede estar en dos fallas.';
    END IF;
    IF v_err IS NULL AND v_h_fal = 1 AND (SELECT COUNT(*) FROM tmp_cab_foto ft
                                          WHERE NOT EXISTS (SELECT 1 FROM evidencia_fotografica e
                                                            WHERE e.id_evidencia = ft.id_evidencia AND e.id_os = p_id_os AND e.id_equipo = v_id_eq AND e.codigo = 'falla'
                                                              AND e.id_usuario = p_id_usuario AND e.eliminado_en IS NULL)) > 0 THEN
        SET v_err = 'Una de las fotos de las fallas no existe o no es de este equipo.';
    END IF;
    IF v_err IS NULL AND v_h_diag = 1 AND ((v_sev IS NOT NULL AND v_sev NOT IN ('baja', 'media', 'alta', 'critica'))
                                           OR (v_est_eq IS NOT NULL AND v_est_eq NOT IN ('operativo', 'con_observaciones', 'inoperativo'))) THEN
        SET v_err = 'El diagnóstico final no es válido: revisa la severidad general y el estado del equipo.';
    END IF;
    IF v_err IS NULL AND v_h_com = 1 AND CHAR_LENGTH(IFNULL(v_com, '')) > 500 THEN
        SET v_err = 'El comentario de las pruebas puede tener hasta 500 caracteres.';
    END IF;
    IF v_err IS NOT NULL THEN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_cab_rec;
        DROP TEMPORARY TABLE IF EXISTS tmp_cab_fal;
        DROP TEMPORARY TABLE IF EXISTS tmp_cab_pru;
        DROP TEMPORARY TABLE IF EXISTS tmp_cab_foto;
        DROP TEMPORARY TABLE IF EXISTS tmp_cab_chk;
        SELECT 1 AS IdTipoMensaje, v_err AS Mensaje; LEAVE proc;
    END IF;

    -- ── Escritura ──────────────────────────────────────────────────────────────────────────────
    UPDATE informe_tecnico
    SET    responsable_nombre    = IF(v_h_datos = 1, v_r_nom, responsable_nombre),
           responsable_cargo     = IF(v_h_datos = 1, v_r_car, responsable_cargo),
           responsable_telefono  = IF(v_h_datos = 1, v_r_tel, responsable_telefono),
           detalle_servicio      = IF(v_h_det = 1, JSON_REMOVE(JSON_SET(JSON_EXTRACT(p_json, '$.detalle'), '$.tipoEquipo', IFNULL(v_d_tipo, '')), '$.checks'), detalle_servicio),
           comentario_pruebas    = IF(v_h_com = 1, v_com, comentario_pruebas),
           sin_recomendaciones   = IF(v_h_sinrec = 1, IF(v_sinrec IN ('true', '1'), 1, 0), sin_recomendaciones),
           sin_fallas            = IF(v_h_sinfal = 1, IF(v_sinfal IN ('true', '1'), 1, 0), sin_fallas),
           severidad_general     = IF(v_h_diag = 1, v_sev, severidad_general),
           estado_equipo_final   = IF(v_h_diag = 1, v_est_eq, estado_equipo_final),
           rev_jefatura          = IF(v_h_diag = 1, IF(v_t_rev IN ('true', '1'), 1, 0), rev_jefatura),
           requiere_precotizacion= IF(v_h_diag = 1, IF(v_t_pre IN ('true', '1'), 1, 0), requiere_precotizacion),
           segunda_visita        = IF(v_h_diag = 1, IF(v_t_seg IN ('true', '1'), 1, 0), segunda_visita),
           aplica_garantia       = IF(v_h_diag = 1, IF(v_t_gar IN ('true', '1'), 1, 0), aplica_garantia),
           cabecera_guardada_en  = NOW(), modificado_por = p_id_usuario
    WHERE  id_informe = v_informe;

    -- Checklist de Detalle Serv.: todos los pasos del tipo de orden, con lo marcado
    IF v_h_det = 1 THEN
        UPDATE informe_procedimiento SET eliminado_en = NOW(), eliminado_por = p_id_usuario
        WHERE  id_informe = v_informe AND origen = 'tecnico' AND codigo IS NOT NULL AND eliminado_en IS NULL;
        INSERT INTO informe_procedimiento (id_informe, orden, titulo, realizado, origen, creado_por, codigo)
        SELECT v_informe, m.Num1, m.String1, IF(c.codigo IS NULL, 0, 1), 'tecnico', p_id_usuario, m.String2
        FROM   tabla_maestra m
        LEFT JOIN tmp_cab_chk c ON c.codigo = m.String2
        WHERE  m.Descripcion = 'CHECKLIST_SERVICIO' AND m.IdEmpresa = 1 AND m.String3 = v_tipo AND m.eliminado_en IS NULL
        ORDER BY m.Num1;
    END IF;

    -- Recomendaciones inmediatas
    IF v_h_rec = 1 THEN
        UPDATE informe_recomendacion SET eliminado_en = NOW(), eliminado_por = p_id_usuario
        WHERE  id_informe = v_informe AND origen = 'tecnico' AND eliminado_en IS NULL;
        INSERT INTO informe_recomendacion (id_informe, codigo, orden, titulo, descripcion, prioridad, plazo, origen, creado_por)
        SELECT v_informe, CONCAT('REC-', LPAD(r.n, 2, '0')), r.n, LEFT(TRIM(r.titulo), 200), NULLIF(TRIM(r.descripcion), ''), IFNULL(r.prioridad, 'alta'), 'Inmediato', 'tecnico', p_id_usuario
        FROM   tmp_cab_rec r ORDER BY r.n;
    END IF;

    -- Fallas con su prueba y sus fotos
    IF v_h_fal = 1 THEN
        UPDATE evidencia_fotografica SET id_observacion = NULL
        WHERE  id_os = p_id_os AND id_equipo = v_id_eq AND codigo = 'falla'
          AND  id_observacion IN (SELECT o.id_observacion FROM informe_observacion o WHERE o.id_informe = v_informe AND o.origen = 'tecnico' AND o.eliminado_en IS NULL);
        UPDATE informe_observacion_prueba p JOIN informe_observacion o ON o.id_observacion = p.id_observacion
        SET    p.eliminado_en = NOW(), p.eliminado_por = p_id_usuario
        WHERE  o.id_informe = v_informe AND o.origen = 'tecnico' AND o.eliminado_en IS NULL AND p.eliminado_en IS NULL;
        UPDATE informe_observacion SET eliminado_en = NOW(), eliminado_por = p_id_usuario
        WHERE  id_informe = v_informe AND origen = 'tecnico' AND eliminado_en IS NULL;

        -- E = I − L, EMP y conformidad de cada lectura de prueba: aquí, una sola vez
        SET v_i = 0;
        WHILE v_i < v_n_pru DO
            SELECT p.id, p.carga INTO v_fila, v_carga FROM tmp_cab_pru p ORDER BY p.id LIMIT 1 OFFSET v_i;
            CALL SP_EmpEnsayoMovil(v_clase, v_e, v_carga, v_emp);
            UPDATE tmp_cab_pru SET emp = v_emp WHERE id = v_fila;
            SET v_i = v_i + 1;
        END WHILE;
        UPDATE tmp_cab_pru SET err = ind - carga, res = IF(emp IS NULL, NULL, IF(ABS(ind - carga) <= emp, 'conforme', 'no_conforme'));

        SET v_i = 1;
        WHILE v_i <= v_n_fal DO
            SELECT f.clasificacion, f.componente, f.severidad, TRIM(f.descripcion) INTO v_f_cla, v_f_com, v_f_sev, v_f_des FROM tmp_cab_fal f WHERE f.n = v_i;
            SELECT m.String1 INTO v_cla_nom FROM tabla_maestra m WHERE m.Descripcion = 'CLASIFICACION_FALLA' AND m.IdEmpresa = 1 AND m.String2 = v_f_cla LIMIT 1;
            SELECT m.String1 INTO v_com_nom FROM tabla_maestra m WHERE m.Descripcion = 'COMPONENTE_FALLA' AND m.IdEmpresa = 1 AND m.String2 = v_f_com LIMIT 1;
            INSERT INTO informe_observacion (id_informe, codigo, orden, titulo, descripcion, ubicacion, detalle_extra, nivel_afectacion, origen, creado_por, clasificacion, componente)
            VALUES (v_informe, CONCAT('OBS-', LPAD(v_i, 2, '0')), v_i, LEFT(v_com_nom, 200), v_f_des, LEFT(v_com_nom, 200), LEFT(v_cla_nom, 200),
                    CASE v_f_sev WHEN 'baja' THEN 'bajo' WHEN 'media' THEN 'medio' WHEN 'alta' THEN 'alto' ELSE 'critico' END, 'tecnico', p_id_usuario, v_f_cla, v_f_com);
            SET v_obs = LAST_INSERT_ID();
            INSERT INTO informe_observacion_prueba (id_observacion, tipo, orden, posicion, carga, indicacion, error, emp, resultado, creado_por)
            SELECT v_obs, p.tipo, p.m, p.posicion, p.carga, p.ind, p.err, p.emp, p.res, p_id_usuario FROM tmp_cab_pru p WHERE p.falla = v_i ORDER BY p.m;
            UPDATE evidencia_fotografica e JOIN tmp_cab_foto ft ON ft.id_evidencia = e.id_evidencia
            SET    e.id_observacion = v_obs
            WHERE  ft.falla = v_i;
            SET v_i = v_i + 1;
        END WHILE;
    END IF;

    SELECT TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))) INTO v_nombre_tec FROM usuario u WHERE u.id_usuario = p_id_usuario LIMIT 1;
    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('informe_tecnico', v_informe, 'guardar_cabecera', NULL, NULL,
            LEFT(CONCAT(IFNULL(v_nombre_tec, 'El técnico'), ' guardó la cabecera del informe del equipo de ', v_num_os, ' (', v_tipo, ').'), 300),
            p_id_usuario, NOW(),
            JSON_OBJECT('id_os', p_id_os, 'id_os_equipo', p_id_os_equipo,
                        'secciones', JSON_ARRAY(IF(v_h_datos = 1, 'datos', NULL), IF(v_h_det = 1, 'detalle', NULL), IF(v_h_rec = 1, 'recomendaciones', NULL),
                                                IF(v_h_fal = 1, 'fallas', NULL), IF(v_h_diag = 1, 'diagnostico', NULL)),
                        'n_fallas', v_n_fal, 'n_recomendaciones', v_n_rec));

    COMMIT;

    DROP TEMPORARY TABLE IF EXISTS tmp_cab_rec;
    DROP TEMPORARY TABLE IF EXISTS tmp_cab_fal;
    DROP TEMPORARY TABLE IF EXISTS tmp_cab_pru;
    DROP TEMPORARY TABLE IF EXISTS tmp_cab_foto;
    DROP TEMPORARY TABLE IF EXISTS tmp_cab_chk;

    SELECT 2 AS IdTipoMensaje, 'Cabecera del informe guardada.' AS Mensaje;
    SELECT v_informe AS id_informe, NOW() AS guardada_en, v_n_fal AS n_fallas, v_n_rec AS n_recomendaciones;
END$$

DELIMITER ;

-- ############################################################
-- 13) SP_RegistrarFotoFallaMovil
-- ############################################################
-- ============================================================
-- SP_RegistrarFotoFallaMovil  (App Mobile HU-15 — foto de una falla, "Nueva falla" → Foto)
-- Registra la foto que el técnico tomó con la cámara de la app para una falla del informe del equipo (evidencia_fotografica, codigo = 'falla'). La foto queda suelta
-- (id_observacion NULL) hasta que SP_GuardarCabeceraInformeMovil la vincula a la falla al guardar la cabecera; se ve con el mismo archivo de evidencias
-- (SP_ObtenerArchivoEvidenciaMovil). NO pasa por la IA ni cuenta en las 9 evidencias del registro fotográfico (HU-11: el panel solo mira los códigos de su catálogo).
--   Reglas: la OS es del técnico, Hard Stop de llegada y equipo iniciado (SP_ContextoEquipoMovil); el equipo EN EJECUCIÓN y el informe aún sin generar. Máximo 40 fotos de
--   fallas por equipo (las que quedan sin vincular también cuentan). El GPS es opcional; la hora de la toma solo se respeta si no es futura (5 min) ni de más de 24 h.
-- Resultados: 1 mensaje (1 regla de negocio · 2 éxito · 3 error) · 2 (solo éxito) id_evidencia.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_RegistrarFotoFallaMovil;

DELIMITER $$

CREATE PROCEDURE SP_RegistrarFotoFallaMovil(
    IN p_id_usuario    BIGINT,
    IN p_id_os         BIGINT,
    IN p_id_os_equipo  BIGINT,
    IN p_ruta_archivo  VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_latitud       DECIMAL(10,7),
    IN p_longitud      DECIMAL(10,7),
    IN p_precision     DECIMAL(8,1),
    IN p_capturado_utc DATETIME
)
proc: BEGIN
    DECLARE v_msg      VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_id_eq    BIGINT DEFAULT NULL;
    DECLARE v_estado   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_hab      TINYINT DEFAULT 0;
    DECLARE v_numero   INT DEFAULT NULL;
    DECLARE v_nombre   VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_num_os   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_servicio VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_gen      DATETIME DEFAULT NULL;
    DECLARE v_n        INT DEFAULT 0;
    DECLARE v_ahora    DATETIME;
    DECLARE v_capt     DATETIME;
    DECLARE v_id       BIGINT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 OR IFNULL(p_id_os_equipo, 0) <= 0 OR NULLIF(TRIM(IFNULL(p_ruta_archivo, '')), '') IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio o equipo no encontrado.' AS Mensaje; LEAVE proc;
    END IF;
    IF (p_latitud IS NOT NULL AND (p_latitud < -90 OR p_latitud > 90)) OR (p_longitud IS NOT NULL AND (p_longitud < -180 OR p_longitud > 180))
       OR (p_precision IS NOT NULL AND (p_precision < 0 OR p_precision > 5000)) THEN
        SELECT 1 AS IdTipoMensaje, 'La ubicación GPS no es válida.' AS Mensaje; LEAVE proc;
    END IF;

    CALL SP_ContextoEquipoMovil(p_id_usuario, p_id_os, p_id_os_equipo, v_msg, v_id_eq, v_estado, v_hab, v_numero, v_nombre, v_num_os, v_servicio);
    IF v_msg IS NULL AND (v_hab = 0 OR v_estado <> 'en_ejecucion') THEN
        SET v_msg = IF(v_estado = 'pausado', 'El equipo está pausado: reanúdalo para agregar fotos a las fallas.', 'El equipo debe estar en ejecución para agregar fotos a las fallas.');
    END IF;
    IF v_msg IS NULL THEN
        SELECT it.generado_en INTO v_gen
        FROM   informe_tecnico it
        WHERE  it.id_os = p_id_os AND it.id_equipo = v_id_eq AND it.eliminado_en IS NULL
        ORDER BY it.id_informe DESC LIMIT 1;
        IF v_gen IS NOT NULL THEN SET v_msg = 'El informe técnico ya fue generado: no se pueden agregar fotos.'; END IF;
    END IF;
    IF v_msg IS NULL THEN
        SELECT COUNT(*) INTO v_n FROM evidencia_fotografica f
        WHERE  f.id_os = p_id_os AND f.id_equipo = v_id_eq AND f.codigo = 'falla' AND f.eliminado_en IS NULL;
        IF v_n >= 40 THEN SET v_msg = 'Este equipo ya tiene el máximo de 40 fotos de fallas.'; END IF;
    END IF;
    IF v_msg IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje; LEAVE proc;
    END IF;

    SET v_ahora = UTC_TIMESTAMP();
    SET v_capt  = v_ahora;
    IF p_capturado_utc IS NOT NULL AND p_capturado_utc >= v_ahora - INTERVAL 24 HOUR AND p_capturado_utc <= v_ahora + INTERVAL 5 MINUTE THEN
        SET v_capt = LEAST(p_capturado_utc, v_ahora);
    END IF;

    INSERT INTO evidencia_fotografica (id_os, id_equipo, id_usuario, id_tipo_evidencia, url_archivo, latitud, longitud, timestamp_captura, validacion_ia,
                                       override_aprobado, codigo, pagina, es_video, precision_m, intento, vigente, creado_por)
    VALUES (p_id_os, v_id_eq, p_id_usuario, 2, TRIM(p_ruta_archivo), p_latitud, p_longitud, v_capt, 'omitida', 0, 'falla', 1, 0, p_precision, 1, 1, p_id_usuario);
    SET v_id = LAST_INSERT_ID();

    SELECT 2 AS IdTipoMensaje, 'Foto de la falla guardada.' AS Mensaje;
    SELECT v_id AS id_evidencia;
END$$

DELIMITER ;

-- ============================================================
-- COMPROBACIÓN (solo lectura, no modifica datos)
-- ============================================================
-- A) Procedimientos con la fecha/hora de hoy (deben ser 12)
SELECT ROUTINE_NAME AS procedimiento, LAST_ALTERED AS actualizado FROM INFORMATION_SCHEMA.ROUTINES
WHERE ROUTINE_SCHEMA = DATABASE() AND ROUTINE_NAME IN ('SP_EspecEquipoMovil', 'SP_TipoOrdenMovil', 'SP_ContextoEnsayoMovil', 'SP_CatalogoEvidenciasMovil', 'SP_ResumenEvidenciasMovil',
      'SP_ArmarEtapasEquipoMovil', 'SP_ObtenerTrabajoEquipoMovil', 'SP_ValidarCierreEquipoMovil', 'SP_GenerarInformeEquipoMovil', 'SP_ObtenerCabeceraInformeMovil',
      'SP_GuardarCabeceraInformeMovil', 'SP_RegistrarFotoFallaMovil')
ORDER BY ROUTINE_NAME;

-- B) Migración 104 (debe dar 24) y los catálogos de referencia (20 pasos de checklist · 6 clasificaciones · 12 componentes)
SELECT 'Migración 104 (debe ser 24)' AS verificacion,
       (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'informe_tecnico'
           AND COLUMN_NAME IN ('numero_informe', 'generado_en', 'generado_por', 'responsable_nombre', 'responsable_cargo', 'responsable_telefono', 'detalle_servicio', 'comentario_pruebas',
                               'sin_recomendaciones', 'sin_fallas', 'severidad_general', 'estado_equipo_final', 'rev_jefatura', 'requiere_precotizacion', 'segunda_visita', 'aplica_garantia', 'cabecera_guardada_en'))
     + (SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME IN ('informe_secuencia', 'informe_observacion_prueba'))
     + (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'informe_procedimiento' AND COLUMN_NAME = 'codigo')
     + (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'informe_observacion' AND COLUMN_NAME IN ('clasificacion', 'componente'))
     + (SELECT COUNT(*) FROM informe_secuencia WHERE anio = YEAR(UTC_TIMESTAMP() - INTERVAL 5 HOUR))
     + (SELECT COUNT(*) FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'informe_tecnico' AND INDEX_NAME = 'ux_informe_numero_informe' AND SEQ_IN_INDEX = 1) AS valor;
SELECT Descripcion AS catalogo, COUNT(*) AS filas FROM tabla_maestra
WHERE Descripcion IN ('CHECKLIST_SERVICIO', 'CLASIFICACION_FALLA', 'COMPONENTE_FALLA') AND IdEmpresa = 1 GROUP BY Descripcion;

-- C) Secuencia del año de los números de informe (el siguiente será ultimo + 1; confirma con Servicio Técnico desde qué número deben arrancar)
SELECT anio, ultimo FROM informe_secuencia ORDER BY anio DESC;

-- D) Validaciones: solo responden un mensaje de regla de negocio, NO escriben nada
CALL SP_ValidarCierreEquipoMovil(0, 0, 0);                    -- "Servicio o equipo no encontrado."
CALL SP_GenerarInformeEquipoMovil(0, 0, 0);                   -- "Servicio o equipo no encontrado."
CALL SP_ObtenerCabeceraInformeMovil(0, 0, 0);                 -- "Servicio o equipo no encontrado."
CALL SP_GuardarCabeceraInformeMovil(0, 0, 0, 'x');            -- "Servicio o equipo no encontrado."
CALL SP_GuardarCabeceraInformeMovil(1, 1, 1, 'x');            -- "Los datos de la cabecera no son válidos."
CALL SP_RegistrarFotoFallaMovil(0, 0, 0, NULL, NULL, NULL, NULL, NULL);   -- "Servicio o equipo no encontrado."

-- E) Lectura real de un equipo (OS-000005 · LOMA LCW-6000, el del técnico de las pruebas): las 5 etapas, el cierre y la cabecera (solo lectura)
SET @os  = 8;
SET @oe  = 20;
SET @tec = (SELECT id_tecnico_principal FROM orden_servicio WHERE id_os = @os);
SELECT @tec AS tecnico_de_la_os;
CALL SP_ObtenerTrabajoEquipoMovil(@tec, @os, @oe);            -- 1 mensaje · 2 cabecera · 3 variables · 4 etapas (NO CONFORME si el ensayo se guardó con error crítico)
CALL SP_ValidarCierreEquipoMovil(@tec, @os, @oe);             -- 1 mensaje · 2 resumen · 3 etapas · 4 pendientes por etapa
CALL SP_ObtenerCabeceraInformeMovil(@tec, @os, @oe);          -- 1 mensaje · 2 cabecera · 3 checklist · 4 a 9
