-- Aplicar en la base (migración 101 + procedimientos de las HU-11, HU-12 y HU-13, sin datos de prueba). Ejecutar completo con Alt+X. NO subir al repositorio.
-- Requiere haber aplicado antes los scripts de las HU-07, HU-08/09 y HU-10. Después REINICIAR la API.

-- ############################################################
-- 1) Migración 101
-- ############################################################
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

-- ############################################################
-- 2) SP_ContextoEquipoMovil
-- ############################################################
-- ============================================================
-- SP_ContextoEquipoMovil  (App Mobile HU-10 / HU-11 — apoyo, no es un endpoint)
-- Valida y arma, UNA sola vez, el contexto básico para trabajar en un equipo de una OS. Lo usan SP_ContextoEnsayoMovil (ensayos) y las evidencias.
--   - La OS debe ser del técnico. Hard Stop (HU-06): llegada registrada y servicio en curso (p_habilitado). El equipo debe estar iniciado
--     (en ejecución, pausado o completado); p_estado_equipo lo dice y quien escribe exige 'en_ejecucion'.
--   p_mensaje trae el texto para el técnico cuando algo impide continuar (lo demás queda NULL). Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ContextoEquipoMovil;

DELIMITER $$

CREATE PROCEDURE SP_ContextoEquipoMovil(
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
    OUT p_servicio      VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
BEGIN
    DECLARE v_estado_os   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_salida_utc  DATETIME;
    DECLARE v_llegada_utc DATETIME;
    DECLARE v_motivo      VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    SET p_mensaje = NULL, p_id_equipo = NULL, p_estado_equipo = NULL, p_habilitado = 0, p_numero = NULL, p_nombre_equipo = NULL, p_numero_os = NULL, p_servicio = NULL;

    SELECT os.estado, os.numero INTO v_estado_os, p_numero_os
    FROM   orden_servicio os
    WHERE  os.id_os = p_id_os AND os.eliminado_en IS NULL
      AND  (os.id_tecnico_principal = p_id_usuario
            OR EXISTS (SELECT 1 FROM os_personal op
                       WHERE op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL));
    IF v_estado_os IS NULL THEN
        SET p_mensaje = 'Servicio no encontrado o no asignado a tu usuario.';
    ELSE
        CALL SP_ArmarObjetivosMovil(p_id_os, v_estado_os, v_salida_utc, v_llegada_utc, p_habilitado, v_motivo);
        IF v_llegada_utc IS NULL THEN
            SET p_mensaje = v_motivo;
        ELSE
            SELECT t.id_equipo, t.estado, t.numero, t.nombre, COALESCE(t.tipo_corto, t.tipo_intervencion)
            INTO   p_id_equipo, p_estado_equipo, p_numero, p_nombre_equipo, p_servicio
            FROM   tmp_obj_mov t WHERE t.id_os_equipo = p_id_os_equipo;
            IF p_id_equipo IS NULL THEN
                SET p_mensaje = 'El equipo no forma parte de los objetivos de este servicio.';
            ELSEIF p_estado_equipo NOT IN ('en_ejecucion', 'pausado', 'completado') THEN
                SET p_mensaje = 'Primero inicia el trabajo en este equipo desde los objetivos.';
            END IF;
        END IF;
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
    END IF;
END$$

DELIMITER ;

-- ############################################################
-- 3) SP_ContextoEnsayoMovil (actualizado: usa el contexto base)
-- ############################################################
-- ============================================================
-- SP_ContextoEnsayoMovil  (App Mobile HU-10 — apoyo, no es un endpoint)
-- Valida y arma, UNA sola vez, el contexto de los ensayos de un equipo. Lo usan SP_ObtenerEnsayosMovil, SP_GuardarEnsayosMovil y
-- SP_RegistrarLlamadaEnsayoMovil. Si algo impide trabajar, p_mensaje trae el texto para el técnico (y lo demás queda NULL).
--   - La OS debe ser del técnico. Hard Stop (HU-06): llegada registrada y servicio en curso. El equipo debe estar EN EJECUCIÓN o PAUSADO (lectura) —
--     p_estado_equipo lo dice, quien escribe exige 'en_ejecucion'.
--   - HU-09: antes de los ensayos deben estar guardadas las variables ambientales (temperatura y humedad).
--   - Especificaciones del equipo (equipo_cliente): clase de exactitud, capacidad máxima, d y e. Vienen como texto ("80 000 kg", "10 kg", "0,5 g"):
--     se toma el número (coma decimal o separador de miles) y la unidad (kg por defecto). e = división de verificación; si no tiene, d.
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
    DECLARE v_cap_txt     VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_d_txt       VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_e_txt       VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

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
        SELECT UPPER(NULLIF(TRIM(ec.clase_exactitud), '')), ec.alcance_maximo, ec.division_minima, IF(ec.division_verif_igual = 1, NULL, ec.division_verif)
        INTO   p_clase, v_cap_txt, v_d_txt, v_e_txt
        FROM   equipo_cliente ec WHERE ec.id_equipo = p_id_equipo;

        -- Número: "80,000" y "80 000" son miles; "0,5" es decimal. Unidad: letras del primer dato (kg por defecto).
        SET p_cap_max = CAST(NULLIF(REGEXP_SUBSTR(IF(REGEXP_LIKE(TRIM(IFNULL(v_cap_txt, '')), '^[0-9]+,[0-9]{1,2}([^0-9]|$)'), REPLACE(v_cap_txt, ',', '.'), REPLACE(REPLACE(IFNULL(v_cap_txt, ''), ',', ''), ' ', '')), '[0-9]+(\\.[0-9]+)?'), '') AS DECIMAL(14,4));
        SET p_d       = CAST(NULLIF(REGEXP_SUBSTR(IF(REGEXP_LIKE(TRIM(IFNULL(v_d_txt, '')), '^[0-9]+,[0-9]{1,2}([^0-9]|$)'), REPLACE(v_d_txt, ',', '.'), REPLACE(REPLACE(IFNULL(v_d_txt, ''), ',', ''), ' ', '')), '[0-9]+(\\.[0-9]+)?'), '') AS DECIMAL(14,4));
        SET p_e       = CAST(NULLIF(REGEXP_SUBSTR(IF(REGEXP_LIKE(TRIM(IFNULL(v_e_txt, '')), '^[0-9]+,[0-9]{1,2}([^0-9]|$)'), REPLACE(v_e_txt, ',', '.'), REPLACE(REPLACE(IFNULL(v_e_txt, ''), ',', ''), ' ', '')), '[0-9]+(\\.[0-9]+)?'), '') AS DECIMAL(14,4));
        SET p_e       = COALESCE(p_e, p_d);
        SET p_unidad  = LOWER(IFNULL(NULLIF(REGEXP_SUBSTR(COALESCE(v_cap_txt, v_d_txt, ''), '[A-Za-z]+'), ''), 'kg'));
    END IF;
END$$

DELIMITER ;

-- ############################################################
-- 4) SP_CatalogoEvidenciasMovil
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
        id_tipo INT NOT NULL, PRIMARY KEY (orden));
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
-- 5) SP_ResumenEvidenciasMovil
-- ############################################################
-- ============================================================
-- SP_ResumenEvidenciasMovil  (App Mobile HU-11 / HU-08 — apoyo, no es un endpoint)
-- Avance del registro fotográfico de un equipo, UNA sola vez. Lo usan el panel de evidencias y la etapa "Registro fotográfico" del trabajo en el equipo.
--   Evidencia COMPLETA = su última captura (vigente, página 1) está aprobada por la IA, fue forzada por el técnico (HU-12) o no se pudo validar con la IA
--   ("omitida": no cuenta como rechazo). Una toma rechazada y no forzada NO completa la evidencia.
-- Deja la tabla temporal tmp_cat_evid armada (quien llama la borra). Solo lectura.
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

    SELECT COUNT(*),
           IFNULL(SUM(f.id_evidencia IS NOT NULL AND (f.override_aprobado = 1 OR f.validacion_ia IN ('aprobada', 'omitida'))), 0),
           IFNULL(SUM(f.id_evidencia IS NOT NULL AND f.override_aprobado = 1), 0),
           IFNULL(SUM(f.id_evidencia IS NOT NULL AND f.override_aprobado = 0 AND f.validacion_ia = 'rechazada'), 0),
           IFNULL(SUM(c.obligatoria = 1 AND NOT (f.id_evidencia IS NOT NULL AND (f.override_aprobado = 1 OR f.validacion_ia IN ('aprobada', 'omitida')))), 0)
    INTO   p_total, p_completas, p_forzadas, p_rechazadas, p_oblig_faltan
    FROM   tmp_cat_evid c
    LEFT JOIN evidencia_fotografica f
           ON f.id_evidencia = (SELECT MAX(f2.id_evidencia) FROM evidencia_fotografica f2
                                WHERE f2.id_os = p_id_os AND f2.id_equipo = p_id_equipo AND f2.codigo = c.codigo
                                  AND f2.pagina = 1 AND f2.vigente = 1 AND f2.eliminado_en IS NULL);
END$$

DELIMITER ;

-- ############################################################
-- 6) SP_ObtenerEvidenciasMovil
-- ############################################################
-- ============================================================
-- SP_ObtenerEvidenciasMovil  (App Mobile HU-11 / HU-12 / HU-13 — panel de evidencias del equipo · lectura)
-- El panel del "Registro fotográfico": las 9 evidencias (SP_CatalogoEvidenciasMovil) con su estado, el avance "N de 9 completas" y lo que necesita el
-- botón "Guardar y volver" (puede_guardar = las 9 completas). Acceso: SP_ContextoEquipoMovil (OS del técnico, Hard Stop, equipo iniciado).
--   estado de cada evidencia: pendiente | aprobada | rechazada | forzada | omitida  (omitida = la IA no estuvo disponible; cuenta como completa)
--   Para una evidencia FORZADA (HU-12) trae lo de "Ver detalles": motivo del técnico, rechazo de la IA, quién la aceptó, cuándo y los intentos previos.
--   Informe a mano: paginas = hojas válidas; la tarjeta muestra la primera.
-- Resultados: 1 mensaje · 2 cabecera (1 fila) · 3 evidencias (9 filas).
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerEvidenciasMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerEvidenciasMovil(
    IN p_id_usuario   BIGINT,
    IN p_id_os        BIGINT,
    IN p_id_os_equipo BIGINT
)
proc: BEGIN
    DECLARE v_msg      VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_eq    BIGINT;
    DECLARE v_est_eq   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_hab      TINYINT;
    DECLARE v_numero   INT;
    DECLARE v_nombre   VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_num_os   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_servicio VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_rq       VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_total    INT;
    DECLARE v_compl    INT;
    DECLARE v_forz     INT;
    DECLARE v_rech     INT;
    DECLARE v_oblig    INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
        DROP TEMPORARY TABLE IF EXISTS tmp_cat_evid;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    CALL SP_ContextoEquipoMovil(p_id_usuario, p_id_os, p_id_os_equipo, v_msg, v_id_eq, v_est_eq, v_hab, v_numero, v_nombre, v_num_os, v_servicio);
    IF v_msg IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT rq.numero INTO v_rq
    FROM   orden_servicio os
    JOIN   expediente_digital ed ON ed.id_expediente = os.id_expediente
    JOIN   requerimiento      rq ON rq.id_requerimiento = ed.id_requerimiento
    WHERE  os.id_os = p_id_os LIMIT 1;

    CALL SP_ResumenEvidenciasMovil(p_id_os, v_id_eq, v_total, v_compl, v_forz, v_rech, v_oblig);

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Cabecera
    SELECT p_id_os AS id_os, p_id_os_equipo AS id_os_equipo, v_num_os AS numero_os, v_nombre AS nombre, v_numero AS numero, v_servicio AS servicio_sigla,
           NULLIF(TRIM(ec.num_serie), '') AS num_serie, NULLIF(ec.codigo_cliente, '') AS codigo_cliente, ec.codigo_tw, ec.marca, ec.modelo,
           v_est_eq AS estado, IF(v_est_eq = 'en_ejecucion' AND v_hab = 1, 1, 0) AS puede_registrar, v_rq AS numero_rq,
           v_total AS total, v_compl AS completas, v_forz AS forzadas, v_rech AS rechazadas, v_oblig AS obligatorias_faltan,
           IF(v_compl = v_total, 1, 0) AS puede_guardar
    FROM   equipo_cliente ec WHERE ec.id_equipo = v_id_eq;

    -- 3. Las 9 evidencias (la última captura de cada una)
    SELECT c.orden, c.codigo, c.nombre, c.descripcion, c.obligatoria, c.medio,
           CASE WHEN f.id_evidencia IS NULL THEN 'pendiente'
                WHEN f.override_aprobado = 1 THEN 'forzada'
                ELSE f.validacion_ia END AS estado,
           f.id_evidencia, f.intento, f.es_video, f.duracion_seg,
           (SELECT COUNT(*) FROM evidencia_fotografica p
            WHERE p.id_os = p_id_os AND p.id_equipo = v_id_eq AND p.codigo = c.codigo AND p.vigente = 1 AND p.eliminado_en IS NULL
              AND (p.override_aprobado = 1 OR p.validacion_ia <> 'rechazada')) AS paginas,
           f.motivo_rechazo_ia, f.motivo_forzado,
           TRIM(CONCAT(IFNULL(uf.nombre, ''), ' ', IFNULL(uf.apellido, ''))) AS forzada_por,
           IF(f.forzada_en IS NULL, NULL, CONVERT_TZ(f.forzada_en, '+00:00', '-05:00')) AS forzada_en,
           IF(f.id_evidencia IS NULL, 0, f.intento - 1) AS intentos_previos,
           CONVERT_TZ(f.timestamp_captura, '+00:00', '-05:00') AS capturada_en,
           CAST(f.resultado_ia AS CHAR) AS resultado_ia,
           IF(f.ruta_cuadro IS NULL, 0, 1) AS tiene_cuadro
    FROM   tmp_cat_evid c
    LEFT JOIN evidencia_fotografica f
           ON f.id_evidencia = (SELECT MAX(f2.id_evidencia) FROM evidencia_fotografica f2
                                WHERE f2.id_os = p_id_os AND f2.id_equipo = v_id_eq AND f2.codigo = c.codigo
                                  AND f2.pagina = 1 AND f2.vigente = 1 AND f2.eliminado_en IS NULL)
    LEFT JOIN usuario uf ON uf.id_usuario = f.id_usuario_override
    ORDER BY c.orden;

    DROP TEMPORARY TABLE IF EXISTS tmp_cat_evid;
END$$

DELIMITER ;

-- ############################################################
-- 7) SP_RegistrarEvidenciaMovil
-- ############################################################
-- ============================================================
-- SP_RegistrarEvidenciaMovil  (App Mobile HU-11 / HU-13 — guarda una captura del panel de evidencias · escritura)
-- Guarda UN intento de captura (foto, microvideo de encendido o lectura del QR) con el resultado de la validación IA que ya hizo el back.
--   - Acceso: SP_ContextoEquipoMovil (OS del técnico, Hard Stop) y el equipo EN EJECUCIÓN.
--   - p_codigo: una de las 9 evidencias (SP_CatalogoEvidenciasMovil). p_pagina: solo el informe a mano admite varias hojas (1 a 10).
--   - Encendido (HU-13): el microvideo dura de 3 a 5 s (se tolera 0,5 s). p_ruta_cuadro = cuadro de la imagen que analizó la IA.
--   - QR: p_qr_texto es lo que leyó la cámara; debe corresponder a ESTE equipo (N/S, código del cliente o COD TW, igual que la búsqueda por QR de la HU-07).
--   - p_ia_estado = aprobada | rechazada | omitida (la IA no estuvo disponible: no bloquea) con p_ia_motivo y p_ia_json (lo que leyó).
--     Placa: si la IA leyó la serie y no coincide con la del equipo, la toma se RECHAZA aquí (la regla vive solo en este SP).
--   - Cada captura es un intento nuevo (intento = 1, 2, 3…); la última queda vigente y reemplaza a la anterior. Una toma rechazada se puede
--     aceptar a la fuerza con SP_ForzarEvidenciaMovil (HU-12).
--   - Deja el registro en auditoria_evento.
-- Resultados: 1 mensaje; 2 (id_evidencia, estado, motivo_rechazo, intento, coincide, numero_rq).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_RegistrarEvidenciaMovil;

DELIMITER $$

CREATE PROCEDURE SP_RegistrarEvidenciaMovil(
    IN p_id_usuario    BIGINT,
    IN p_id_os         BIGINT,
    IN p_id_os_equipo  BIGINT,
    IN p_codigo        VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_pagina        INT,
    IN p_ruta_archivo  VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_ruta_cuadro   VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_duracion      DECIMAL(5,1),
    IN p_latitud       DECIMAL(10,7),
    IN p_longitud      DECIMAL(10,7),
    IN p_precision     DECIMAL(8,1),
    IN p_capturado_utc DATETIME,
    IN p_qr_texto      VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_ia_estado     VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_ia_motivo     VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_ia_json       LONGTEXT     CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_msg      VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_eq    BIGINT;
    DECLARE v_est_eq   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_hab      TINYINT;
    DECLARE v_numero   INT;
    DECLARE v_nombre   VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_num_os   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_servicio VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_tipo  INT DEFAULT NULL;
    DECLARE v_medio    VARCHAR(6) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_pagina   INT;
    DECLARE v_serie    VARCHAR(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cod_tw   VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cod_cli  VARCHAR(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_qr       VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado   VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_motivo   VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_json     LONGTEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_serie_ia VARCHAR(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_coincide TINYINT DEFAULT NULL;
    DECLARE v_rq       VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_intento  INT DEFAULT 1;
    DECLARE v_id_evid  BIGINT;
    DECLARE v_ahora    DATETIME;
    DECLARE v_capt     DATETIME;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
        DROP TEMPORARY TABLE IF EXISTS tmp_cat_evid;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 OR IFNULL(p_id_os_equipo, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio o equipo no encontrado.' AS Mensaje; LEAVE proc;
    END IF;
    SET v_estado = LOWER(TRIM(IFNULL(p_ia_estado, 'omitida')));
    IF v_estado NOT IN ('aprobada', 'rechazada', 'omitida') THEN
        SELECT 1 AS IdTipoMensaje, 'El resultado de la validación no es válido.' AS Mensaje; LEAVE proc;
    END IF;
    IF p_latitud IS NOT NULL AND (p_latitud NOT BETWEEN -90 AND 90 OR p_longitud IS NULL OR p_longitud NOT BETWEEN -180 AND 180) THEN
        SELECT 1 AS IdTipoMensaje, 'La ubicación GPS no es válida.' AS Mensaje; LEAVE proc;
    END IF;
    SET v_json = IF(p_ia_json IS NOT NULL AND JSON_VALID(p_ia_json) AND CHAR_LENGTH(p_ia_json) <= 8000, p_ia_json, NULL);
    SET v_motivo = LEFT(NULLIF(TRIM(IFNULL(p_ia_motivo, '')), ''), 300);

    CALL SP_CatalogoEvidenciasMovil();
    SELECT c.id_tipo, c.medio INTO v_id_tipo, v_medio FROM tmp_cat_evid c WHERE c.codigo = LOWER(TRIM(IFNULL(p_codigo, '')));
    DROP TEMPORARY TABLE IF EXISTS tmp_cat_evid;
    IF v_id_tipo IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'La evidencia no existe en el panel.' AS Mensaje; LEAVE proc;
    END IF;
    SET p_codigo = LOWER(TRIM(p_codigo));
    SET v_pagina = IF(p_codigo = 'informe', IFNULL(p_pagina, 1), 1);
    IF v_pagina < 1 OR v_pagina > 10 THEN
        SELECT 1 AS IdTipoMensaje, 'El informe admite hasta 10 hojas.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_medio = 'video' AND (p_duracion IS NULL OR p_duracion < 2.5 OR p_duracion > 5.5) THEN
        SELECT 1 AS IdTipoMensaje, 'El microvideo debe durar de 3 a 5 segundos.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_medio = 'qr' THEN
        SET v_qr = UPPER(TRIM(IFNULL(p_qr_texto, '')));
        IF v_qr = '' OR CHAR_LENGTH(v_qr) > 300 THEN
            SELECT 1 AS IdTipoMensaje, 'El código leído no es válido.' AS Mensaje; LEAVE proc;
        END IF;
    ELSEIF NULLIF(TRIM(IFNULL(p_ruta_archivo, '')), '') IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Falta el archivo de la captura.' AS Mensaje; LEAVE proc;
    END IF;

    SET v_ahora = UTC_TIMESTAMP();
    SET v_capt  = v_ahora;
    IF p_capturado_utc IS NOT NULL AND p_capturado_utc >= v_ahora - INTERVAL 24 HOUR AND p_capturado_utc <= v_ahora + INTERVAL 5 MINUTE THEN
        SET v_capt = LEAST(p_capturado_utc, v_ahora);
    END IF;

    START TRANSACTION;

    CALL SP_ContextoEquipoMovil(p_id_usuario, p_id_os, p_id_os_equipo, v_msg, v_id_eq, v_est_eq, v_hab, v_numero, v_nombre, v_num_os, v_servicio);
    IF v_msg IS NULL AND (v_hab = 0 OR v_est_eq <> 'en_ejecucion') THEN
        SET v_msg = IF(v_est_eq = 'pausado', 'El equipo está pausado: reanúdalo para registrar evidencias.',
                       IF(v_est_eq = 'completado', 'Este equipo ya está completado.', 'El servicio ya no está en curso: no se pueden registrar evidencias.'));
    END IF;
    IF v_msg IS NOT NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje; LEAVE proc;
    END IF;

    SELECT NULLIF(TRIM(ec.num_serie), ''), ec.codigo_tw, NULLIF(ec.codigo_cliente, '') INTO v_serie, v_cod_tw, v_cod_cli
    FROM   equipo_cliente ec WHERE ec.id_equipo = v_id_eq;
    SELECT rq.numero INTO v_rq
    FROM   orden_servicio os
    JOIN   expediente_digital ed ON ed.id_expediente = os.id_expediente
    JOIN   requerimiento      rq ON rq.id_requerimiento = ed.id_requerimiento
    WHERE  os.id_os = p_id_os LIMIT 1;

    -- Reglas propias de cada evidencia
    IF v_medio = 'qr' THEN
        SET v_coincide = IF(UPPER(IFNULL(v_serie, '')) = v_qr OR UPPER(IFNULL(v_cod_cli, '')) = v_qr OR UPPER(IFNULL(v_cod_tw, '')) = v_qr
                            OR (CHAR_LENGTH(IFNULL(v_cod_tw, '')) >= 5 AND LOCATE(UPPER(v_cod_tw), v_qr) > 0)
                            OR (CHAR_LENGTH(IFNULL(v_cod_cli, '')) >= 5 AND LOCATE(UPPER(v_cod_cli), v_qr) > 0), 1, 0);
        SET v_estado = IF(v_coincide = 1, 'aprobada', 'rechazada');
        SET v_motivo = IF(v_coincide = 1, NULL, 'El QR leído no corresponde a este equipo. Escanea la etiqueta del equipo que estás trabajando.');
        SET v_json = JSON_OBJECT('qr', LEFT(TRIM(p_qr_texto), 300));
        SET p_ruta_archivo = 'qr://leido';
    ELSEIF p_codigo = 'placa' AND v_estado = 'aprobada' AND v_json IS NOT NULL THEN
        SET v_serie_ia = NULLIF(UPPER(REGEXP_REPLACE(IFNULL(JSON_UNQUOTE(JSON_EXTRACT(v_json, '$.serie')), ''), '[^A-Za-z0-9]', '')), '');
        IF v_serie_ia IS NOT NULL AND v_serie IS NOT NULL THEN
            SET v_coincide = IF(v_serie_ia = UPPER(REGEXP_REPLACE(v_serie, '[^A-Za-z0-9]', '')), 1, 0);
            IF v_coincide = 0 THEN
                SET v_estado = 'rechazada';
                SET v_motivo = LEFT(CONCAT('La serie de la placa (', JSON_UNQUOTE(JSON_EXTRACT(v_json, '$.serie')), ') no coincide con la del equipo (', v_serie, ').'), 300);
            END IF;
        END IF;
    END IF;
    IF v_estado = 'rechazada' AND v_motivo IS NULL THEN SET v_motivo = 'La IA no pudo validar la toma. Repite la foto con mejor luz y enfoque.'; END IF;
    IF v_estado <> 'rechazada' THEN SET v_motivo = NULL; END IF;

    -- Intento nuevo: el último queda vigente y reemplaza al anterior de esa evidencia (y página)
    SELECT IFNULL(MAX(f.intento), 0) + 1 INTO v_intento
    FROM   evidencia_fotografica f
    WHERE  f.id_os = p_id_os AND f.id_equipo = v_id_eq AND f.codigo = p_codigo AND f.pagina = v_pagina AND f.eliminado_en IS NULL;
    UPDATE evidencia_fotografica SET vigente = 0
    WHERE  id_os = p_id_os AND id_equipo = v_id_eq AND codigo = p_codigo AND pagina = v_pagina AND vigente = 1 AND eliminado_en IS NULL;

    INSERT INTO evidencia_fotografica (id_os, id_equipo, id_usuario, id_tipo_evidencia, url_archivo, latitud, longitud, timestamp_captura, validacion_ia,
                                       override_aprobado, codigo, pagina, es_video, duracion_seg, precision_m, intento, vigente, motivo_rechazo_ia, resultado_ia,
                                       ruta_cuadro, creado_por)
    VALUES (p_id_os, v_id_eq, p_id_usuario, v_id_tipo, IFNULL(NULLIF(TRIM(p_ruta_archivo), ''), 'qr://leido'), p_latitud, p_longitud, v_capt, v_estado,
            0, p_codigo, v_pagina, IF(v_medio = 'video', 1, 0), IF(v_medio = 'video', p_duracion, NULL), p_precision, v_intento, 1, v_motivo, v_json,
            NULLIF(TRIM(IFNULL(p_ruta_cuadro, '')), ''), p_id_usuario);
    SET v_id_evid = LAST_INSERT_ID();

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('os_equipo', p_id_os_equipo, 'registrar_evidencia', NULL, v_estado,
            LEFT(CONCAT('Evidencia ', p_codigo, IF(v_pagina > 1, CONCAT(' (hoja ', v_pagina, ')'), ''), ' de ', v_num_os, ' · intento ', v_intento, ': ', v_estado,
                        IF(v_motivo IS NULL, '', CONCAT('. ', v_motivo))), 900),
            p_id_usuario, NOW(),
            JSON_OBJECT('id_evidencia', v_id_evid, 'codigo', p_codigo, 'intento', v_intento, 'resultado', v_estado));

    COMMIT;

    SELECT 2 AS IdTipoMensaje,
           CASE v_estado WHEN 'aprobada' THEN 'Evidencia guardada y validada por la IA.'
                         WHEN 'omitida'  THEN 'Evidencia guardada (la IA no estuvo disponible para validarla).'
                         ELSE 'La IA rechazó la toma.' END AS Mensaje;
    SELECT v_id_evid AS id_evidencia, v_estado AS estado, v_motivo AS motivo_rechazo, v_intento AS intento, v_coincide AS coincide, v_rq AS numero_rq;
END$$

DELIMITER ;

-- ############################################################
-- 8) SP_ForzarEvidenciaMovil
-- ############################################################
-- ============================================================
-- SP_ForzarEvidenciaMovil  (App Mobile HU-12 — Override de evidencia fotográfica · escritura)
-- El técnico acepta a la fuerza una toma que la IA rechazó, en una situación excepcional donde no puede conseguir una mejor.
--   - Solo con un MOTIVO ESCRITO (3 a 300 caracteres). Solo se fuerza la última captura de la evidencia (vigente) y solo si está rechazada.
--   - Acceso: OS del técnico, Hard Stop y equipo EN EJECUCIÓN (SP_ContextoEquipoMovil).
--   - Marca la evidencia FORZADA (override_aprobado = 1) con el motivo, quién y cuándo (la validación de la IA y su motivo de rechazo se conservan).
--     Cuenta como completa en el panel.
--   - Consecuencias que la app muestra ANTES de confirmar y que se cumplen aquí: queda registrada como excepción en el expediente (auditoria_evento),
--     suma al contador de evidencias forzadas del scorecard del técnico del mes (tecnico_scorecard.foto_override_count) y queda visible para Jefatura
--     (notificación al encargado del área según la RQ; si no hay, a los administradores).
--   - Repetir la petición sobre una evidencia ya forzada responde éxito sin duplicar nada.
-- Resultados: 1 mensaje; 2 (id_evidencia, forzada_en en Lima, intentos_previos, notificados).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ForzarEvidenciaMovil;

DELIMITER $$

CREATE PROCEDURE SP_ForzarEvidenciaMovil(
    IN p_id_usuario    BIGINT,
    IN p_id_os         BIGINT,
    IN p_id_os_equipo  BIGINT,
    IN p_id_evidencia  BIGINT,
    IN p_motivo        VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_msg      VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_eq    BIGINT;
    DECLARE v_est_eq   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_hab      TINYINT;
    DECLARE v_numero   INT;
    DECLARE v_nombre   VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_num_os   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_servicio VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_motivo   VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_codigo   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_valida   VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_ya       TINYINT DEFAULT 0;
    DECLARE v_vigente  TINYINT DEFAULT 0;
    DECLARE v_intento  INT DEFAULT 1;
    DECLARE v_motivo_ia VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_forzada  DATETIME DEFAULT NULL;
    DECLARE v_mes      DATE;
    DECLARE v_area     VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_enc   BIGINT;
    DECLARE v_nom_enc  VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_car_enc  VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tel_enc  VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_nombre_tec VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_texto    VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_notif    INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 OR IFNULL(p_id_os_equipo, 0) <= 0 OR IFNULL(p_id_evidencia, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Evidencia no encontrada.' AS Mensaje; LEAVE proc;
    END IF;
    SET v_motivo = NULLIF(TRIM(IFNULL(p_motivo, '')), '');
    IF v_motivo IS NULL OR CHAR_LENGTH(v_motivo) < 3 THEN
        SELECT 1 AS IdTipoMensaje, 'Escribe el motivo por el que aceptas la foto (mínimo 3 caracteres).' AS Mensaje; LEAVE proc;
    END IF;
    IF CHAR_LENGTH(v_motivo) > 300 THEN
        SELECT 1 AS IdTipoMensaje, 'El motivo puede tener hasta 300 caracteres.' AS Mensaje; LEAVE proc;
    END IF;

    START TRANSACTION;

    CALL SP_ContextoEquipoMovil(p_id_usuario, p_id_os, p_id_os_equipo, v_msg, v_id_eq, v_est_eq, v_hab, v_numero, v_nombre, v_num_os, v_servicio);
    IF v_msg IS NULL AND (v_hab = 0 OR v_est_eq <> 'en_ejecucion') THEN
        SET v_msg = IF(v_est_eq = 'pausado', 'El equipo está pausado: reanúdalo para registrar evidencias.',
                       IF(v_est_eq = 'completado', 'Este equipo ya está completado.', 'El servicio ya no está en curso: no se pueden registrar evidencias.'));
    END IF;
    IF v_msg IS NOT NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje; LEAVE proc;
    END IF;

    SELECT f.codigo, f.validacion_ia, f.override_aprobado, f.vigente, f.intento, f.motivo_rechazo_ia, f.forzada_en
    INTO   v_codigo, v_valida, v_ya, v_vigente, v_intento, v_motivo_ia, v_forzada
    FROM   evidencia_fotografica f
    WHERE  f.id_evidencia = p_id_evidencia AND f.id_os = p_id_os AND f.id_equipo = v_id_eq AND f.eliminado_en IS NULL
    FOR UPDATE;

    IF v_codigo IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Evidencia no encontrada.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_ya = 1 THEN
        COMMIT;
        SELECT 2 AS IdTipoMensaje, 'Esta evidencia ya estaba aceptada como forzada.' AS Mensaje;
        SELECT p_id_evidencia AS id_evidencia, CONVERT_TZ(v_forzada, '+00:00', '-05:00') AS forzada_en, v_intento - 1 AS intentos_previos, 0 AS notificados;
        LEAVE proc;
    END IF;
    IF v_valida <> 'rechazada' THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Solo se puede forzar una foto que la IA rechazó.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_vigente = 0 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Esa toma ya fue reemplazada por una más reciente.' AS Mensaje; LEAVE proc;
    END IF;

    SET v_forzada = UTC_TIMESTAMP();
    UPDATE evidencia_fotografica
    SET    override_aprobado = 1, id_usuario_override = p_id_usuario, motivo_forzado = v_motivo, forzada_en = v_forzada, modificado_por = p_id_usuario
    WHERE  id_evidencia = p_id_evidencia;

    -- Scorecard del técnico (mes en curso, hora de Lima)
    SET v_mes = DATE_FORMAT(UTC_TIMESTAMP() - INTERVAL 5 HOUR, '%Y-%m-01');
    UPDATE tecnico_scorecard SET foto_override_count = foto_override_count + 1, modificado_por = p_id_usuario
    WHERE  id_usuario = p_id_usuario AND periodo_mes = v_mes AND eliminado_en IS NULL;
    IF ROW_COUNT() = 0 THEN
        INSERT INTO tecnico_scorecard (id_usuario, periodo_mes, foto_override_count, creado_por) VALUES (p_id_usuario, v_mes, 1, p_id_usuario);
    END IF;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('os_equipo', p_id_os_equipo, 'forzar_evidencia', 'rechazada', 'forzada',
            LEFT(CONCAT('Evidencia ', v_codigo, ' de ', v_num_os, ' aceptada a la fuerza tras ', v_intento, IF(v_intento = 1, ' intento', ' intentos'),
                        '. Rechazo de la IA: ', IFNULL(v_motivo_ia, '—'), '. Motivo del técnico: ', v_motivo), 900),
            p_id_usuario, NOW(),
            JSON_OBJECT('id_evidencia', p_id_evidencia, 'codigo', v_codigo, 'intentos', v_intento, 'motivo', v_motivo, 'motivo_ia', v_motivo_ia));

    -- Visible para Jefatura: aviso al encargado del área (si no hay, a los administradores)
    CALL SP_ContactoEncargadoEnsayoMovil(p_id_os, v_area, v_id_enc, v_nom_enc, v_car_enc, v_tel_enc);
    SELECT TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))) INTO v_nombre_tec FROM usuario u WHERE u.id_usuario = p_id_usuario LIMIT 1;
    SET v_texto = LEFT(CONCAT(v_nombre_tec, ' aceptó a la fuerza la evidencia «', v_codigo, '» de ', v_nombre, ' (', v_num_os, '), rechazada por la IA. Motivo: ', v_motivo), 500);
    IF v_id_enc IS NOT NULL AND v_id_enc <> p_id_usuario THEN
        INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
        VALUES (v_id_enc, 5, 'Evidencia forzada', v_texto, 'orden_servicio', p_id_os, NOW(), p_id_usuario);
        SET v_notif = 1;
    ELSE
        INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
        SELECT u.id_usuario, 5, 'Evidencia forzada', v_texto, 'orden_servicio', p_id_os, NOW(), p_id_usuario
        FROM   usuario u
        WHERE  u.eliminado_en IS NULL AND u.estado = 'activo' AND u.id_usuario <> p_id_usuario AND u.rol_sistema IN ('administrador', 'admin');
        SET v_notif = ROW_COUNT();
    END IF;

    COMMIT;

    SELECT 2 AS IdTipoMensaje, 'Foto aceptada como evidencia forzada: quedó registrada y visible para Jefatura.' AS Mensaje;
    SELECT p_id_evidencia AS id_evidencia, CONVERT_TZ(v_forzada, '+00:00', '-05:00') AS forzada_en, v_intento - 1 AS intentos_previos, v_notif AS notificados;
END$$

DELIMITER ;

-- ############################################################
-- 9) SP_ObtenerArchivoEvidenciaMovil
-- ############################################################
-- ============================================================
-- SP_ObtenerArchivoEvidenciaMovil  (App Mobile HU-11 — ruta del archivo de una evidencia para mostrarla · lectura)
-- Devuelve dónde está guardada una evidencia (foto, video o cuadro) SOLO si la OS es del técnico del token y la evidencia es de esa OS y ese equipo
-- (misma respuesta si no existe o no es suya). No exige llegada: el técnico puede ver lo que ya capturó.
-- Resultados: 1 mensaje; 2 (ruta, ruta_cuadro, es_video). Las evidencias del QR no tienen archivo.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerArchivoEvidenciaMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerArchivoEvidenciaMovil(
    IN p_id_usuario   BIGINT,
    IN p_id_os        BIGINT,
    IN p_id_os_equipo BIGINT,
    IN p_id_evidencia BIGINT
)
BEGIN
    DECLARE v_ruta   VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_cuadro VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_video  TINYINT DEFAULT 0;

    SELECT f.url_archivo, f.ruta_cuadro, f.es_video INTO v_ruta, v_cuadro, v_video
    FROM   evidencia_fotografica f
    JOIN   os_equipo oe ON oe.id = p_id_os_equipo AND oe.id_os = f.id_os AND oe.id_equipo = f.id_equipo AND oe.eliminado_en IS NULL
    JOIN   orden_servicio os ON os.id_os = f.id_os AND os.eliminado_en IS NULL
    WHERE  f.id_evidencia = p_id_evidencia AND f.id_os = p_id_os AND f.eliminado_en IS NULL
      AND  f.url_archivo NOT LIKE 'qr://%'
      AND  (os.id_tecnico_principal = p_id_usuario
            OR EXISTS (SELECT 1 FROM os_personal op WHERE op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL));

    IF v_ruta IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Evidencia no encontrada.' AS Mensaje;
    ELSE
        SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;
        SELECT v_ruta AS ruta, v_cuadro AS ruta_cuadro, v_video AS es_video;
    END IF;
END$$

DELIMITER ;

-- ############################################################
-- 10) SP_ObtenerTrabajoEquipoMovil (actualizado: etapa de registro fotográfico)
-- ############################################################
-- ============================================================
-- SP_ObtenerTrabajoEquipoMovil  (App Mobile HU-08 — "Trabajo en el equipo": cabecera y las 5 etapas · lectura)
-- Pantalla a la que entra el técnico con "Trabajar en el equipo". El técnico sale del token; la OS debe ser suya.
--   - Hard Stop (HU-06): sin llegada registrada no se entrega nada. El equipo debe haberse iniciado (en ejecución, pausado o completado).
--   - Tipo de orden según la RQ: el área de la RQ (area_servicio_rq) define OS (servicio técnico) u OM (metrología).
--   - Servicio: sigla y nombre del tipo de intervención del equipo; si no tiene, el tipo de servicio de la OS.
--   - Etapas (siempre las 5, una sola vez aquí): variables (HU-09), fotos, ensayos, cabecera y correlativo.
--       estado: conforme | en_curso | pendiente | bloqueado.  "Ensayos y Calibración" queda BLOQUEADO hasta guardar las variables ambientales (HU-09).
--       disponible = 0 → la etapa aún no tiene pantalla en la app (la app avisa que se habilita más adelante).
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
    DECLARE v_area        VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_numero_rq   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_servicio    VARCHAR(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_n_fotos     INT DEFAULT 0;
    DECLARE v_n_ensayos   INT DEFAULT 0;
    DECLARE v_informe     BIGINT DEFAULT NULL;
    DECLARE v_vars        TINYINT DEFAULT 0;
    DECLARE v_det_vars    VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_sigla       VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_tipo_int    VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_conformes   INT DEFAULT 0;
    DECLARE v_ev_total    INT DEFAULT 9;
    DECLARE v_ev_compl    INT DEFAULT 0;
    DECLARE v_ev_forz     INT DEFAULT 0;
    DECLARE v_ev_rech     INT DEFAULT 0;
    DECLARE v_ev_oblig    INT DEFAULT 0;
    DECLARE v_ens_final   DATETIME DEFAULT NULL;
    DECLARE v_ens_motivo  VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
        DROP TEMPORARY TABLE IF EXISTS tmp_etapas_mov;
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

    -- Tipo de orden según la RQ: servicio técnico → OS, metrología → OM
    SELECT asr.area_usuario, rq.numero INTO v_area, v_numero_rq
    FROM   orden_servicio os
    JOIN   expediente_digital ed  ON ed.id_expediente = os.id_expediente
    JOIN   requerimiento      rq  ON rq.id_requerimiento = ed.id_requerimiento
    LEFT JOIN area_servicio_rq asr ON asr.id_area_rq = rq.id_area
    WHERE  os.id_os = p_id_os
    LIMIT 1;
    SET v_tipo_orden = IF(v_area = 'metrologia', 'OM', 'OS');

    -- Variables ambientales (HU-09)
    SELECT COUNT(*) INTO v_vars
    FROM   variable_ambiental va WHERE va.id_os = p_id_os AND va.id_equipo = v_id_equipo AND va.eliminado_en IS NULL;
    IF v_vars > 0 THEN
        SELECT CONCAT('T° ', TRIM(TRAILING '.' FROM TRIM(TRAILING '0' FROM CAST(va.temperatura_c AS CHAR))), ' °C · h ',
                      TRIM(TRAILING '.' FROM TRIM(TRAILING '0' FROM CAST(va.humedad_pct AS CHAR))), ' % · Procedencia ', IFNULL(va.procedencia, 'N.I'))
        INTO   v_det_vars
        FROM   variable_ambiental va
        WHERE  va.id_os = p_id_os AND va.id_equipo = v_id_equipo AND va.eliminado_en IS NULL
        ORDER BY va.id_variable DESC LIMIT 1;
    END IF;

    -- Registro fotográfico (HU-11): el avance lo calcula SP_ResumenEvidenciasMovil, una sola vez
    CALL SP_ResumenEvidenciasMovil(p_id_os, v_id_equipo, v_ev_total, v_ev_compl, v_ev_forz, v_ev_rech, v_ev_oblig);
    DROP TEMPORARY TABLE IF EXISTS tmp_cat_evid;
    SET v_n_fotos = v_ev_compl;

    SELECT it.id_informe, it.ensayos_finalizado_en, it.error_critico_motivo INTO v_informe, v_ens_final, v_ens_motivo
    FROM   informe_tecnico it
    WHERE  it.id_os = p_id_os AND it.id_equipo = v_id_equipo AND it.eliminado_en IS NULL
    ORDER BY it.id_informe DESC LIMIT 1;
    IF v_informe IS NOT NULL THEN
        SELECT COUNT(*) INTO v_n_ensayos FROM informe_ensayo ie WHERE ie.id_informe = v_informe AND ie.eliminado_en IS NULL;
    END IF;

    DROP TEMPORARY TABLE IF EXISTS tmp_etapas_mov;
    CREATE TEMPORARY TABLE tmp_etapas_mov (
        orden INT NOT NULL, codigo VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, nombre VARCHAR(60) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        estado VARCHAR(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, detalle VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        disponible TINYINT DEFAULT 0, PRIMARY KEY (orden));

    INSERT INTO tmp_etapas_mov (orden, codigo, nombre, estado, detalle, disponible) VALUES
        (1, 'variables', 'Variables ambientales', IF(v_vars > 0, 'conforme', 'pendiente'),
            IF(v_vars > 0, v_det_vars, 'Temperatura, humedad y procedencia'), 1),
        (2, 'fotos', 'Registro fotográfico', IF(v_ev_compl >= v_ev_total, 'conforme', IF(v_ev_compl > 0 OR v_ev_rech > 0, 'en_curso', 'pendiente')),
            CONCAT(v_ev_compl, ' de ', v_ev_total, ' · incluye foto del informe a mano',
                   IF(v_ev_forz > 0, CONCAT(' · ', v_ev_forz, IF(v_ev_forz = 1, ' forzada', ' forzadas')), '')), 1),
        (3, 'ensayos', 'Ensayos y Calibración',
            IF(v_vars = 0, 'bloqueado', IF(v_ens_final IS NOT NULL, 'conforme', IF(v_n_ensayos > 0, 'en_curso', 'pendiente'))),
            IF(v_vars = 0, 'Se habilita al guardar las variables ambientales',
               IF(v_ens_final IS NOT NULL, IF(v_ens_motivo IS NULL, 'Pesaje y excentricidad conformes', 'Finalizado con error crítico: se avisó al encargado'),
                  IF(v_n_ensayos > 0, CONCAT(v_n_ensayos, ' lecturas guardadas · falta finalizar'), 'Verificación de pesaje tras el ajuste'))), 1),
        (4, 'cabecera', 'Cabecera del informe', IF(v_informe IS NOT NULL, 'en_curso', 'pendiente'), 'Datos · Detalle Serv. · Observación y pruebas', 0),
        (5, 'correlativo', 'Correlativo y certificado', 'pendiente', 'Correlativo de Metrología → N° de certificado', 0);

    SELECT COUNT(*) INTO v_conformes FROM tmp_etapas_mov WHERE estado = 'conforme';

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
    DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
END$$

DELIMITER ;

-- ============================================================
-- COMPROBACIÓN (solo lectura, no modifica datos)
-- ============================================================
-- A) Procedimientos con la fecha/hora de hoy (deben ser 9)
SELECT ROUTINE_NAME AS procedimiento, LAST_ALTERED AS actualizado FROM INFORMATION_SCHEMA.ROUTINES
WHERE ROUTINE_SCHEMA = DATABASE() AND ROUTINE_NAME IN ('SP_ContextoEquipoMovil', 'SP_ContextoEnsayoMovil', 'SP_CatalogoEvidenciasMovil', 'SP_ResumenEvidenciasMovil',
      'SP_ObtenerEvidenciasMovil', 'SP_RegistrarEvidenciaMovil', 'SP_ForzarEvidenciaMovil', 'SP_ObtenerArchivoEvidenciaMovil', 'SP_ObtenerTrabajoEquipoMovil') ORDER BY ROUTINE_NAME;

-- B) Un equipo inexistente: "Servicio no encontrado o no asignado a tu usuario."
CALL SP_ObtenerEvidenciasMovil(0, 0, 0);

-- C) Panel de evidencias del equipo en ejecución de la OS de prueba (9 filas; todas "pendiente" mientras no se capture nada)
SET @os = 8;
SET @tec = (SELECT id_tecnico_principal FROM orden_servicio WHERE id_os = @os);
SET @oe = (SELECT MIN(id) FROM os_equipo WHERE id_os = @os AND estado_ejecucion = 'en_proceso' AND eliminado_en IS NULL);
CALL SP_ObtenerEvidenciasMovil(@tec, @os, @oe);

-- D) La etapa "Registro fotográfico" en el trabajo del equipo (debe decir "0 de 9 · incluye foto del informe a mano")
CALL SP_ObtenerTrabajoEquipoMovil(@tec, @os, @oe);
