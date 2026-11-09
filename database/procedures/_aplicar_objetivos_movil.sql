-- Aplicar en la base (migración 98 + 7 procedimientos de la HU-07, sin datos de prueba). Ejecutar completo con Alt+X. NO subir al repositorio.
-- Orden: primero la migración (columnas nuevas) y luego los procedimientos. Después REINICIAR la API (MySqlConnector guarda en caché los procedimientos).
-- Requiere las migraciones 80 y 97 y el SP_LeerParametroProgramacion (ya aplicados con las HU anteriores).

-- ############################################################
-- 1) Migración 98 (columnas, catálogo y parámetro)
-- ############################################################
-- ============================================================
-- Migración 98 — Lista de objetivos y selección de equipos desde la app móvil (App Mobile HU-07)
--   1. os_equipo (el "objetivo" de la OS = un equipo a intervenir): seguimiento de la ejecución desde la app.
--        iniciado_utc / reanudado_utc / acumulado_seg   tiempo real trabajado (reanudado_utc = inicio del tramo en curso; NULL = detenido)
--        pausado / motivo_pausa / pausa_requiere_aprobacion   "PAUSADO"; si requiere aprobación, el técnico NO puede reanudar
--        id_usuario_ejecucion   quién lo inició o reanudó (un técnico trabaja en un solo equipo a la vez)
--   2. equipo_cliente: equipos registrados en campo desde la app (NEW): quedan en estado 'borrador' hasta que la intranet los apruebe y
--      les asigne el COD TW. registrado_en_campo, id_os_registro y foto_placa_url (foto de la placa, solo cámara).
--   3. Catálogo TIPO_INTERVENCION_EQUIPO: String3 = sigla ("MC", "MP") y Num2 = minutos estimados del objetivo (solo si están vacíos;
--      Calibración 30 y Mantenimiento correctivo 60 según el mockup; el resto usa el parámetro de abajo).
--   4. Parámetro OBJETIVO_MINUTOS_POR_DEFECTO (60): minutos estimados cuando el tipo de intervención no define los suyos.
--   No borra ni cambia datos existentes. IDEMPOTENTE. Requiere las migraciones 80 y 97.
-- ============================================================

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'os_equipo' AND COLUMN_NAME = 'iniciado_utc'),
    'ALTER TABLE os_equipo ADD COLUMN iniciado_utc DATETIME NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'os_equipo' AND COLUMN_NAME = 'reanudado_utc'),
    'ALTER TABLE os_equipo ADD COLUMN reanudado_utc DATETIME NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'os_equipo' AND COLUMN_NAME = 'acumulado_seg'),
    'ALTER TABLE os_equipo ADD COLUMN acumulado_seg INT NOT NULL DEFAULT 0', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'os_equipo' AND COLUMN_NAME = 'pausado'),
    'ALTER TABLE os_equipo ADD COLUMN pausado TINYINT(1) NOT NULL DEFAULT 0', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'os_equipo' AND COLUMN_NAME = 'motivo_pausa'),
    'ALTER TABLE os_equipo ADD COLUMN motivo_pausa VARCHAR(300) NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'os_equipo' AND COLUMN_NAME = 'pausa_requiere_aprobacion'),
    'ALTER TABLE os_equipo ADD COLUMN pausa_requiere_aprobacion TINYINT(1) NOT NULL DEFAULT 0', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'os_equipo' AND COLUMN_NAME = 'id_usuario_ejecucion'),
    'ALTER TABLE os_equipo ADD COLUMN id_usuario_ejecucion BIGINT NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'equipo_cliente' AND COLUMN_NAME = 'registrado_en_campo'),
    'ALTER TABLE equipo_cliente ADD COLUMN registrado_en_campo TINYINT(1) NOT NULL DEFAULT 0', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'equipo_cliente' AND COLUMN_NAME = 'id_os_registro'),
    'ALTER TABLE equipo_cliente ADD COLUMN id_os_registro BIGINT NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'equipo_cliente' AND COLUMN_NAME = 'foto_placa_url'),
    'ALTER TABLE equipo_cliente ADD COLUMN foto_placa_url VARCHAR(500) NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- ── Catálogo TIPO_INTERVENCION_EQUIPO (31): sigla y minutos estimados, solo donde están vacíos ──────────
UPDATE tabla_maestra
SET    String3 = CASE String2 WHEN 'MANTENIMIENTO_CORR' THEN 'MC' WHEN 'MANTENIMIENTO_PREV' THEN 'MP' END
WHERE  Descripcion = 'TIPO_INTERVENCION_EQUIPO' AND IdEmpresa = 1 AND (String3 IS NULL OR String3 = '') AND String2 IN ('MANTENIMIENTO_CORR', 'MANTENIMIENTO_PREV');

UPDATE tabla_maestra
SET    Num2 = CASE String2 WHEN 'CALIBRACION' THEN 30 WHEN 'MANTENIMIENTO_CORR' THEN 60 END
WHERE  Descripcion = 'TIPO_INTERVENCION_EQUIPO' AND IdEmpresa = 1 AND Num2 IS NULL AND String2 IN ('CALIBRACION', 'MANTENIMIENTO_CORR');

-- ── Parámetro ──────────────────────────────────────────────────────────────────────────────
SET @id_param := (SELECT MAX(IdMaestro) FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROGRAMACION');
SET @id_param := IFNULL(@id_param, (SELECT MAX(IdMaestro) + 1 FROM tabla_maestra));

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, Num2, String1, String2)
SELECT 1, @id_param, 'PARAMETRO_PROGRAMACION',
       (SELECT IFNULL(MAX(t.Num1), 0) + 1 FROM tabla_maestra t WHERE t.IdMaestro = @id_param AND t.IdEmpresa = 1),
       60, 'Minutos estimados de un objetivo cuando su tipo de intervención no define los suyos', 'OBJETIVO_MINUTOS_POR_DEFECTO'
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra t WHERE t.Descripcion = 'PARAMETRO_PROGRAMACION' AND t.IdEmpresa = 1 AND t.String2 = 'OBJETIVO_MINUTOS_POR_DEFECTO');

-- ── Verificación ─────────────────────────────────────────────────────────────
SELECT 'Migración 98 (debe ser 11)' AS verificacion,
       (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'os_equipo'
           AND COLUMN_NAME IN ('iniciado_utc', 'reanudado_utc', 'acumulado_seg', 'pausado', 'motivo_pausa', 'pausa_requiere_aprobacion', 'id_usuario_ejecucion'))
     + (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'equipo_cliente'
           AND COLUMN_NAME IN ('registrado_en_campo', 'id_os_registro', 'foto_placa_url'))
     + (SELECT COUNT(*) FROM tabla_maestra WHERE Descripcion = 'PARAMETRO_PROGRAMACION' AND IdEmpresa = 1 AND String2 = 'OBJETIVO_MINUTOS_POR_DEFECTO') AS valor;

-- ############################################################
-- 2) SP_EvaluarCampoMovil
-- ############################################################
-- ============================================================
-- SP_EvaluarCampoMovil  (App Mobile HU-06 / HU-07 — apoyo, no es un endpoint)
-- Hard Stop de los objetivos, UNA sola vez: ¿el técnico ya registró su llegada a planta en este viaje y el servicio sigue en curso?
--   p_llegada_utc : llegada de ESTE viaje (último evento LLEGADA posterior a la última SALIDA_BASE); NULL = sin marca de llegada
--   p_habilitado  : 1 = se puede trabajar en los equipos (llegada registrada y OS en ruta, en ejecución o en pausa)
--   p_motivo      : por qué no (cuando p_habilitado = 0)
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_EvaluarCampoMovil;

DELIMITER $$

CREATE PROCEDURE SP_EvaluarCampoMovil(
    IN  p_id_os       BIGINT,
    OUT p_estado      VARCHAR(20),
    OUT p_salida_utc  DATETIME,
    OUT p_llegada_utc DATETIME,
    OUT p_habilitado  TINYINT,
    OUT p_motivo      VARCHAR(200)
)
BEGIN
    SET p_estado      = NULL;
    SET p_salida_utc  = NULL;
    SET p_llegada_utc = NULL;
    SET p_habilitado  = 0;
    SET p_motivo      = NULL;

    SELECT os.estado INTO p_estado FROM orden_servicio os WHERE os.id_os = p_id_os AND os.eliminado_en IS NULL;

    SELECT MAX(e.timestamp_utc) INTO p_salida_utc
    FROM   evento_campo e
    JOIN   tabla_maestra m ON m.IdMaestro = 29 AND m.IdEmpresa = 1 AND m.Num1 = e.id_tipo_evento AND m.String2 = 'SALIDA_BASE'
    WHERE  e.id_os = p_id_os AND e.eliminado_en IS NULL;

    SELECT MAX(e.timestamp_utc) INTO p_llegada_utc
    FROM   evento_campo e
    JOIN   tabla_maestra m ON m.IdMaestro = 29 AND m.IdEmpresa = 1 AND m.Num1 = e.id_tipo_evento AND m.String2 = 'LLEGADA'
    WHERE  e.id_os = p_id_os AND e.eliminado_en IS NULL AND e.timestamp_utc >= IFNULL(p_salida_utc, '1000-01-01');

    IF p_llegada_utc IS NULL THEN
        SET p_motivo = 'Sin marca de llegada: primero registra tu llegada a planta antes de acceder a los objetivos.';
    ELSEIF p_estado NOT IN ('en_ruta', 'en_ejecucion', 'pausada') THEN
        SET p_motivo = 'El servicio ya no está en curso: los equipos no se pueden modificar.';
    ELSE
        SET p_habilitado = 1;
    END IF;
END$$

DELIMITER ;

-- ############################################################
-- 3) SP_ArmarObjetivosMovil
-- ############################################################
-- ============================================================
-- SP_ArmarObjetivosMovil  (App Mobile HU-07 — apoyo, no es un endpoint)
-- Arma, UNA sola vez, los objetivos de la OS (un objetivo = un equipo a intervenir, `os_equipo`) en la tabla temporal `tmp_obj_mov`,
-- con su estado, tiempos y lo que el técnico puede hacer. Lo usan la lista, la búsqueda por QR y las acciones (iniciar/pausar/reanudar):
-- la regla de qué botón se habilita vive solo aquí. Los SP que la llaman deben terminar con DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov.
--   Objetivos = equipos de la OS que se confirmaron en la programación vigente (sin selección, todos) + los registrados en campo (NEW).
--   estado: por_iniciar | en_ejecucion | pausado | completado | observado
--   Observados (contador) = observado + pausados que esperan aprobación de un supervisor (esos NO se pueden reanudar).
--   Tiempo estimado = Num2 del tipo de intervención (TIPO_INTERVENCION_EQUIPO) o el parámetro OBJETIVO_MINUTOS_POR_DEFECTO (60).
--   Nombre = descripción del suministro del equipo ("Balanza industrial unicelda de piso"); sin suministro, su clasificación (Equipo / Instrumento / Pesa).
--   Bloqueado (no se puede seleccionar) = equipo inactivo o "En Evaluación" (en el laboratorio, no está en la planta).
--   falta_equipo = el objetivo no tiene N/S ni equipo identificado ("FALTA EQUIPO/INSTRUMENTO").
--   puede_iniciar / puede_pausar / puede_reanudar: solo con la llegada registrada y el servicio en curso (SP_EvaluarCampoMovil).
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ArmarObjetivosMovil;

DELIMITER $$

CREATE PROCEDURE SP_ArmarObjetivosMovil(
    IN  p_id_os       BIGINT,
    OUT p_estado      VARCHAR(20),
    OUT p_salida_utc  DATETIME,
    OUT p_llegada_utc DATETIME,
    OUT p_habilitado  TINYINT,
    OUT p_motivo      VARCHAR(200)
)
BEGIN
    DECLARE v_id_prog   BIGINT DEFAULT NULL;
    DECLARE v_n_eq_prog INT    DEFAULT 0;
    DECLARE v_min_def   DECIMAL(18,6);
    DECLARE v_ahora_utc DATETIME;

    CALL SP_EvaluarCampoMovil(p_id_os, p_estado, p_salida_utc, p_llegada_utc, p_habilitado, p_motivo);
    CALL SP_LeerParametroProgramacion('OBJETIVO_MINUTOS_POR_DEFECTO', 60, v_min_def);
    SET v_ahora_utc = UTC_TIMESTAMP();

    SELECT pr.id_programacion INTO v_id_prog
    FROM   programacion pr
    WHERE  pr.id_os = p_id_os AND pr.estado <> 'cancelada' AND pr.eliminado_en IS NULL
    ORDER BY pr.id_programacion DESC LIMIT 1;

    SELECT COUNT(*) INTO v_n_eq_prog
    FROM   programacion_equipo pe
    WHERE  pe.id_programacion = v_id_prog AND pe.eliminado_en IS NULL;

    DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
    CREATE TEMPORARY TABLE tmp_obj_mov (
        id_os_equipo BIGINT NOT NULL, id_equipo BIGINT NOT NULL, orden_clave BIGINT, numero INT DEFAULT 0,
        tipo_intervencion VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, tipo_corto VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        nombre VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        codigo_tw VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, codigo_cliente VARCHAR(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        marca VARCHAR(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, modelo VARCHAR(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        num_serie VARCHAR(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, ubicacion VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        estado_equipo VARCHAR(60) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, bloqueado TINYINT DEFAULT 0, en_campo TINYINT DEFAULT 0, falta_equipo TINYINT DEFAULT 0,
        estado VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, observado_cuenta TINYINT DEFAULT 0,
        tiempo_estimado_min INT, tiempo_real_min INT, iniciado_utc DATETIME,
        motivo_pausa VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, requiere_aprobacion TINYINT DEFAULT 0,
        ultima_intervencion DATE, ultima_parte VARCHAR(320) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, alertas_pendientes INT DEFAULT 0,
        puede_iniciar TINYINT DEFAULT 0, puede_pausar TINYINT DEFAULT 0, puede_reanudar TINYINT DEFAULT 0,
        PRIMARY KEY (id_os_equipo)
    );

    INSERT INTO tmp_obj_mov (id_os_equipo, id_equipo, orden_clave, tipo_intervencion, tipo_corto, nombre, codigo_tw, codigo_cliente, marca, modelo, num_serie, ubicacion,
                             estado_equipo, bloqueado, en_campo, falta_equipo, estado, observado_cuenta, tiempo_estimado_min, tiempo_real_min, iniciado_utc,
                             motivo_pausa, requiere_aprobacion, ultima_intervencion, ultima_parte, alertas_pendientes)
    SELECT oe.id, oe.id_equipo, IFNULL(oe.orden, oe.id),
           ti.String1, NULLIF(ti.String3, ''),
           LEFT(COALESCE(NULLIF(TRIM(su.descripcion), ''), tc.String1, ec.clasificacion, 'Equipo'), 150),
           ec.codigo_tw, NULLIF(ec.codigo_cliente, ''), ec.marca, ec.modelo, NULLIF(TRIM(ec.num_serie), ''), NULLIF(ec.ubicacion_especifica, ''),
           teo.String1,
           IF(ec.es_activo = 0 OR ec.estado = 'inactivo' OR ec.estado_operativo = 'evaluacion', 1, 0),
           oe.ingresado_en_campo,
           IF(NULLIF(TRIM(ec.num_serie), '') IS NULL, 1, 0),
           CASE WHEN oe.estado_ejecucion = 'ejecutado' THEN 'completado'
                WHEN oe.pausado = 1 THEN 'pausado'
                WHEN oe.estado_ejecucion = 'observado' THEN 'observado'
                WHEN oe.estado_ejecucion = 'en_proceso' THEN 'en_ejecucion'
                ELSE 'por_iniciar' END,
           IF(oe.estado_ejecucion = 'observado' OR (oe.pausado = 1 AND oe.pausa_requiere_aprobacion = 1), 1, 0),
           COALESCE(ti.Num2, v_min_def),
           FLOOR((oe.acumulado_seg + IF(oe.reanudado_utc IS NULL, 0, GREATEST(0, TIMESTAMPDIFF(SECOND, oe.reanudado_utc, v_ahora_utc)))) / 60),
           oe.iniciado_utc,
           IF(oe.pausado = 1, oe.motivo_pausa, NULL), IF(oe.pausado = 1, oe.pausa_requiere_aprobacion, 0),
           (SELECT DATE(MAX(x.fecha_ejecucion)) FROM os_equipo x
            WHERE x.id_equipo = oe.id_equipo AND x.id_os <> oe.id_os AND x.estado_ejecucion = 'ejecutado' AND x.eliminado_en IS NULL),
           (SELECT LEFT(CONCAT(h.campo_modificado, ': ', h.valor_nuevo), 320) FROM equipo_historial h
            WHERE h.id_equipo = oe.id_equipo ORDER BY h.registrado_en DESC, h.id_historial DESC LIMIT 1),
           (SELECT COUNT(*) FROM alerta_predictiva ap WHERE ap.id_equipo = oe.id_equipo AND ap.resuelta = 0 AND ap.eliminado_en IS NULL)
    FROM   os_equipo oe
    JOIN   equipo_cliente ec ON ec.id_equipo = oe.id_equipo
    LEFT JOIN tabla_maestra ti  ON ti.Descripcion  = 'TIPO_INTERVENCION_EQUIPO' AND ti.IdEmpresa  = 1 AND ti.Num1 = oe.id_tipo_intervencion
    LEFT JOIN suministros   su  ON su.id_suministro = ec.id_suministro
    LEFT JOIN tabla_maestra tc  ON tc.IdMaestro    = 71                         AND tc.IdEmpresa  = 1 AND tc.String2 = ec.clasificacion
    LEFT JOIN tabla_maestra teo ON teo.Descripcion = 'ESTADO_OPERATIVO_EQUIPO'   AND teo.IdEmpresa = 1 AND teo.String2 = ec.estado_operativo
    WHERE  oe.id_os = p_id_os AND oe.eliminado_en IS NULL
      AND  (v_n_eq_prog = 0 OR oe.ingresado_en_campo = 1
            OR EXISTS (SELECT 1 FROM programacion_equipo pe
                       WHERE pe.id_programacion = v_id_prog AND pe.id_equipo = oe.id_equipo AND pe.eliminado_en IS NULL));

    SET @n_obj_mov := 0;
    UPDATE tmp_obj_mov SET numero = (@n_obj_mov := @n_obj_mov + 1) ORDER BY orden_clave, id_os_equipo;

    UPDATE tmp_obj_mov
    SET puede_iniciar   = IF(p_habilitado = 1 AND bloqueado = 0 AND estado IN ('por_iniciar', 'observado'), 1, 0),
        puede_pausar    = IF(p_habilitado = 1 AND estado = 'en_ejecucion', 1, 0),
        puede_reanudar  = IF(p_habilitado = 1 AND estado = 'pausado' AND requiere_aprobacion = 0 AND bloqueado = 0, 1, 0);
END$$

DELIMITER ;

-- ############################################################
-- 4) SP_ObtenerObjetivosMovil
-- ############################################################
-- ============================================================
-- SP_ObtenerObjetivosMovil  (App Mobile HU-07 — Lista de objetivos y selección de equipos · lectura)
-- Objetivos de la OS del técnico que inició sesión (el id sale del token), numerados y con su estado.
--   - Hard Stop (HU-06): sin llegada registrada en este viaje NO se entregan los objetivos (responde la regla de negocio con el motivo).
--   - p_buscar (opcional, máx. 100): filtra la LISTA por N/S, código del cliente, COD TW, marca, modelo, ubicación o tipo de equipo
--     (sin comodines: se busca el texto tal cual). Los contadores y el tiempo estimado siempre son de TODOS los objetivos.
--   - Los objetivos los arma SP_ArmarObjetivosMovil (una sola vez); aquí solo se leen.
-- Resultados: 1 mensaje · 2 resumen (1 fila) · 3 contadores (1 fila) · 4 equipos (con puede_iniciar/pausar/reanudar) ·
--             5 cambios (historial del equipo y cambios de estado desde la app, el más reciente primero, máx. 300 de la OS).
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerObjetivosMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerObjetivosMovil(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT,
    IN p_buscar     VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_existe     TINYINT DEFAULT 0;
    DECLARE v_estado     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_salida_utc DATETIME;
    DECLARE v_llegada_utc DATETIME;
    DECLARE v_habilitado TINYINT;
    DECLARE v_motivo     VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_buscar     VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estimado   INT DEFAULT 0;
    DECLARE v_ahora_utc  DATETIME;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SELECT IF(COUNT(*) > 0, 1, 0) INTO v_existe
    FROM   orden_servicio os
    WHERE  os.id_os = p_id_os AND os.eliminado_en IS NULL
      AND  (os.id_tecnico_principal = p_id_usuario
            OR EXISTS (SELECT 1 FROM os_personal op
                       WHERE op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL));
    IF v_existe = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio no encontrado o no asignado a tu usuario.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_buscar = LOWER(TRIM(IFNULL(p_buscar, '')));
    IF CHAR_LENGTH(v_buscar) > 100 THEN
        SELECT 1 AS IdTipoMensaje, 'La búsqueda puede tener hasta 100 caracteres.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_ArmarObjetivosMovil(p_id_os, v_estado, v_salida_utc, v_llegada_utc, v_habilitado, v_motivo);

    -- Hard Stop: sin llegada no hay objetivos
    IF v_llegada_utc IS NULL THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
        SELECT 1 AS IdTipoMensaje, v_motivo AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_ahora_utc = UTC_TIMESTAMP();
    SELECT IFNULL(SUM(tiempo_estimado_min), 0) INTO v_estimado FROM tmp_obj_mov;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Resumen
    SELECT os.id_os,
           os.numero                                                         AS numero_os,
           os.estado                                                         AS estado_os,
           COALESCE(NULLIF(c.nombre_comercial, ''), c.razon_social)          AS cliente,
           sc.nombre                                                         AS sede,
           CONVERT_TZ(v_salida_utc, '+00:00', '-05:00')                      AS salida_en,
           CONVERT_TZ(v_llegada_utc, '+00:00', '-05:00')                     AS llegada_en,
           IF(v_salida_utc IS NULL, NULL, GREATEST(0, TIMESTAMPDIFF(MINUTE, v_salida_utc, v_llegada_utc))) AS traslado_min,
           GREATEST(0, TIMESTAMPDIFF(MINUTE, v_llegada_utc, v_ahora_utc))    AS en_planta_min,
           v_estimado                                                        AS estimado_min
    FROM   orden_servicio os
    LEFT JOIN cliente      c  ON c.id_cliente = os.id_cliente
    LEFT JOIN sede_cliente sc ON sc.id_sede   = os.id_sede
    WHERE  os.id_os = p_id_os;

    -- 3. Contadores (de todos los objetivos)
    SELECT IFNULL(SUM(estado = 'completado'), 0)                                  AS completados,
           IFNULL(SUM(estado <> 'completado' AND observado_cuenta = 0), 0)        AS pendientes,
           IFNULL(SUM(estado <> 'completado' AND observado_cuenta = 1), 0)        AS observados,
           COUNT(*)                                                               AS total
    FROM   tmp_obj_mov;

    -- 4. Equipos (con el filtro de búsqueda)
    SELECT t.id_os_equipo, t.id_equipo, t.numero, t.tipo_intervencion, t.tipo_corto, t.nombre, t.codigo_tw, t.codigo_cliente, t.marca, t.modelo,
           t.num_serie, t.ubicacion, t.estado_equipo, t.bloqueado, t.en_campo, t.falta_equipo, t.estado, t.tiempo_estimado_min, t.tiempo_real_min,
           CONVERT_TZ(t.iniciado_utc, '+00:00', '-05:00') AS iniciado_en, t.motivo_pausa, t.requiere_aprobacion, t.ultima_intervencion, t.ultima_parte,
           t.alertas_pendientes, t.puede_iniciar, t.puede_pausar, t.puede_reanudar
    FROM   tmp_obj_mov t
    WHERE  v_buscar = ''
       OR  LOCATE(v_buscar, LOWER(CONCAT_WS(' ', t.num_serie, t.codigo_cliente, t.codigo_tw, t.marca, t.modelo, t.ubicacion, t.nombre))) > 0
    ORDER BY t.numero;

    -- 5. Cambios: historial del equipo (intranet) y cambios de estado hechos desde la app
    SELECT x.id_os_equipo, x.fecha, x.campo, x.valor_anterior, x.valor_nuevo, x.detalle, x.usuario
    FROM (
        SELECT oe.id AS id_os_equipo, h.registrado_en AS fecha, h.campo_modificado AS campo, h.valor_anterior, h.valor_nuevo,
               LEFT(IFNULL(h.motivo, ''), 300) AS detalle, TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))) AS usuario
        FROM   os_equipo oe
        JOIN   equipo_historial h ON h.id_equipo = oe.id_equipo
        LEFT JOIN usuario u ON u.id_usuario = h.registrado_por
        WHERE  oe.id_os = p_id_os AND oe.eliminado_en IS NULL
        UNION ALL
        SELECT a.id_entidad, a.registrado_en, 'Estado', a.estado_anterior, a.estado_nuevo, LEFT(IFNULL(a.descripcion, ''), 300),
               TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, '')))
        FROM   auditoria_evento a
        LEFT JOIN usuario u ON u.id_usuario = a.id_usuario
        WHERE  a.entidad_tipo = 'os_equipo'
          AND  a.id_entidad IN (SELECT o2.id FROM os_equipo o2 WHERE o2.id_os = p_id_os AND o2.eliminado_en IS NULL)
    ) x
    ORDER BY x.fecha DESC
    LIMIT 300;

    DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
END$$

DELIMITER ;

-- ############################################################
-- 5) SP_BuscarEquipoQrMovil
-- ############################################################
-- ============================================================
-- SP_BuscarEquipoQrMovil  (App Mobile HU-07 — selección de equipo escaneando su código o QR · lectura)
-- Busca, entre los objetivos de la OS del técnico, el equipo cuyo N/S, código del cliente o COD TW coincide con lo escaneado.
--   - Coincidencia exacta (sin distinguir mayúsculas) con N/S, código del cliente o COD TW; o, si el QR trae un texto más largo (una URL
--     con el código al final), que contenga el COD TW o el código del cliente (de 5 o más caracteres).
--   - Hard Stop (HU-06): sin llegada registrada no se entregan equipos.
--   - Si no está en la lista de la OS responde la regla de negocio (la app ofrece buscarlo o registrarlo como equipo nuevo).
-- Resultados: 1 mensaje · 2 el equipo (mismas columnas que el resultado 4 de SP_ObtenerObjetivosMovil).
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_BuscarEquipoQrMovil;

DELIMITER $$

CREATE PROCEDURE SP_BuscarEquipoQrMovil(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT,
    IN p_codigo     VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_existe     TINYINT DEFAULT 0;
    DECLARE v_estado     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_salida_utc DATETIME;
    DECLARE v_llegada_utc DATETIME;
    DECLARE v_habilitado TINYINT;
    DECLARE v_motivo     VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_codigo     VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id         BIGINT DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SELECT IF(COUNT(*) > 0, 1, 0) INTO v_existe
    FROM   orden_servicio os
    WHERE  os.id_os = p_id_os AND os.eliminado_en IS NULL
      AND  (os.id_tecnico_principal = p_id_usuario
            OR EXISTS (SELECT 1 FROM os_personal op
                       WHERE op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL));
    IF v_existe = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio no encontrado o no asignado a tu usuario.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_codigo = UPPER(TRIM(IFNULL(p_codigo, '')));
    IF CHAR_LENGTH(v_codigo) = 0 OR CHAR_LENGTH(v_codigo) > 300 THEN
        SELECT 1 AS IdTipoMensaje, 'El código escaneado no es válido.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_ArmarObjetivosMovil(p_id_os, v_estado, v_salida_utc, v_llegada_utc, v_habilitado, v_motivo);
    IF v_llegada_utc IS NULL THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
        SELECT 1 AS IdTipoMensaje, v_motivo AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT t.id_os_equipo INTO v_id
    FROM   tmp_obj_mov t
    WHERE  UPPER(t.num_serie) = v_codigo OR UPPER(t.codigo_cliente) = v_codigo OR UPPER(t.codigo_tw) = v_codigo
       OR  (CHAR_LENGTH(t.codigo_tw) >= 5 AND LOCATE(UPPER(t.codigo_tw), v_codigo) > 0)
       OR  (CHAR_LENGTH(IFNULL(t.codigo_cliente, '')) >= 5 AND LOCATE(UPPER(t.codigo_cliente), v_codigo) > 0)
    ORDER BY (UPPER(t.num_serie) = v_codigo OR UPPER(t.codigo_cliente) = v_codigo OR UPPER(t.codigo_tw) = v_codigo) DESC, t.numero
    LIMIT 1;

    IF v_id IS NULL THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
        SELECT 1 AS IdTipoMensaje, 'El código escaneado no corresponde a ningún equipo de esta O/S. Búscalo en la lista o regístralo como equipo nuevo (NEW).' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Equipo encontrado en la lista de la O/S.' AS Mensaje;
    SELECT t.id_os_equipo, t.id_equipo, t.numero, t.tipo_intervencion, t.tipo_corto, t.nombre, t.codigo_tw, t.codigo_cliente, t.marca, t.modelo,
           t.num_serie, t.ubicacion, t.estado_equipo, t.bloqueado, t.en_campo, t.falta_equipo, t.estado, t.tiempo_estimado_min, t.tiempo_real_min,
           CONVERT_TZ(t.iniciado_utc, '+00:00', '-05:00') AS iniciado_en, t.motivo_pausa, t.requiere_aprobacion, t.ultima_intervencion, t.ultima_parte,
           t.alertas_pendientes, t.puede_iniciar, t.puede_pausar, t.puede_reanudar
    FROM   tmp_obj_mov t
    WHERE  t.id_os_equipo = v_id;

    DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
END$$

DELIMITER ;

-- ############################################################
-- 6) SP_CambiarEstadoEquipoMovil
-- ############################################################
-- ============================================================
-- SP_CambiarEstadoEquipoMovil  (App Mobile HU-07 — "Trabajar en el equipo" / "Pausar" / "Reanudar" · escritura)
-- El técnico inicia, pausa o reanuda el trabajo en un objetivo (equipo) de su OS.
--   - El técnico sale del token; la OS debe ser suya. Hard Stop (HU-06): solo con la llegada registrada y la OS en curso.
--   - Qué acción está permitida lo decide SP_ArmarObjetivosMovil (puede_iniciar / puede_pausar / puede_reanudar): aquí no se repite la regla.
--       iniciar  : por iniciar u observado → en ejecución. Un técnico trabaja en UN solo equipo a la vez (pausa el otro primero).
--                  El primer inicio de la OS la pasa a "en ejecución" y registra el evento INICIO_TRABAJO (la bandeja de seguimiento lo lee).
--       pausar   : en ejecución → pausado. Exige un motivo (3 a 300 caracteres). Cierra el tramo de tiempo y registra el evento PAUSA.
--       reanudar : pausado → en ejecución (evento REANUDA). Si la pausa espera aprobación del supervisor, NO se puede reanudar.
--   - Repetir una acción que ya está aplicada (reintento de la app) responde éxito sin duplicar nada.
--   - Sin conexión: la app guarda la acción con la hora en que se tocó (p_capturado_utc, UTC del teléfono; solo se respeta si no es futura
--     —tolerancia 5 min— ni tiene más de 24 h) y la envía al recuperar la señal EN ORDEN; el tiempo trabajado usa esa hora.
--   - Deja el cambio de estado en auditoria_evento (entidad 'os_equipo'), que la tarjeta muestra como Campo / Anterior / Actual.
-- Resultados: 1 mensaje; 2 (id_os_equipo, accion, estado, repetida, diferida).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_CambiarEstadoEquipoMovil;

DELIMITER $$

CREATE PROCEDURE SP_CambiarEstadoEquipoMovil(
    IN p_id_usuario    BIGINT,
    IN p_id_os         BIGINT,
    IN p_id_os_equipo  BIGINT,
    IN p_accion        VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_motivo        VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_capturado_utc DATETIME
)
proc: BEGIN
    DECLARE v_accion      VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_motivo      VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado_os   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_numero_os   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_salida_utc  DATETIME;
    DECLARE v_llegada_utc DATETIME;
    DECLARE v_habilitado  TINYINT;
    DECLARE v_motivo_no   VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado      VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_p_iniciar   TINYINT DEFAULT 0;
    DECLARE v_p_pausar    TINYINT DEFAULT 0;
    DECLARE v_p_reanudar  TINYINT DEFAULT 0;
    DECLARE v_bloqueado   TINYINT DEFAULT 0;
    DECLARE v_req_aprob   TINYINT DEFAULT 0;
    DECLARE v_nombre      VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_otro        VARCHAR(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_reanudado   DATETIME;
    DECLARE v_ahora_utc   DATETIME;
    DECLARE v_capt_utc    DATETIME;
    DECLARE v_t_utc       DATETIME;
    DECLARE v_diferida    TINYINT DEFAULT 0;
    DECLARE v_repetida    TINYINT DEFAULT 0;
    DECLARE v_nuevo       VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tipo_evt    INT DEFAULT NULL;
    DECLARE v_hay_inicio  TINYINT DEFAULT 0;
    DECLARE v_cod_evt     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_ant_txt     VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_nue_txt     VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 OR IFNULL(p_id_os_equipo, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio o equipo no encontrado.' AS Mensaje;
        LEAVE proc;
    END IF;
    SET v_accion = LOWER(TRIM(IFNULL(p_accion, '')));
    IF v_accion NOT IN ('iniciar', 'pausar', 'reanudar') THEN
        SELECT 1 AS IdTipoMensaje, 'La acción no es válida.' AS Mensaje;
        LEAVE proc;
    END IF;
    SET v_motivo = NULLIF(TRIM(IFNULL(p_motivo, '')), '');
    IF v_accion = 'pausar' AND (v_motivo IS NULL OR CHAR_LENGTH(v_motivo) < 3) THEN
        SELECT 1 AS IdTipoMensaje, 'Indica el motivo de la pausa (mínimo 3 caracteres).' AS Mensaje;
        LEAVE proc;
    END IF;
    IF CHAR_LENGTH(IFNULL(p_motivo, '')) > 300 THEN
        SELECT 1 AS IdTipoMensaje, 'El motivo puede tener hasta 300 caracteres.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Hora de la acción: la del servidor, salvo una guardada sin conexión (la hora del teléfono, sin futuro ni más de 24 h)
    SET v_ahora_utc = UTC_TIMESTAMP();
    SET v_capt_utc  = v_ahora_utc;
    IF p_capturado_utc IS NOT NULL AND p_capturado_utc >= v_ahora_utc - INTERVAL 24 HOUR AND p_capturado_utc <= v_ahora_utc + INTERVAL 5 MINUTE THEN
        SET v_capt_utc = LEAST(p_capturado_utc, v_ahora_utc);
    END IF;
    SET v_diferida = IF(v_capt_utc < v_ahora_utc - INTERVAL 2 MINUTE, 1, 0);
    SET v_t_utc    = IF(v_diferida = 1, v_capt_utc, v_ahora_utc);

    START TRANSACTION;

    -- La OS debe ser del técnico del token
    SELECT os.estado, os.numero INTO v_estado_os, v_numero_os
    FROM   orden_servicio os
    WHERE  os.id_os = p_id_os AND os.eliminado_en IS NULL
      AND  (os.id_tecnico_principal = p_id_usuario
            OR EXISTS (SELECT 1 FROM os_personal op
                       WHERE op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL))
    FOR UPDATE;
    IF v_estado_os IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Servicio no encontrado o no asignado a tu usuario.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- El objetivo debe ser de esa OS (se bloquea la fila para que dos envíos no se pisen)
    SELECT oe.reanudado_utc INTO v_reanudado
    FROM   os_equipo oe
    WHERE  oe.id = p_id_os_equipo AND oe.id_os = p_id_os AND oe.eliminado_en IS NULL
    FOR UPDATE;
    IF NOT EXISTS (SELECT 1 FROM os_equipo oe WHERE oe.id = p_id_os_equipo AND oe.id_os = p_id_os AND oe.eliminado_en IS NULL) THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'El equipo no pertenece a este servicio.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Estado y permisos del objetivo: una sola vez, en SP_ArmarObjetivosMovil
    CALL SP_ArmarObjetivosMovil(p_id_os, v_estado_os, v_salida_utc, v_llegada_utc, v_habilitado, v_motivo_no);
    SELECT t.estado, t.puede_iniciar, t.puede_pausar, t.puede_reanudar, t.bloqueado, t.requiere_aprobacion,
           CONCAT(IFNULL(t.codigo_cliente, IFNULL(t.num_serie, t.codigo_tw)), ' · ', IFNULL(t.nombre, 'Equipo'))
    INTO   v_estado, v_p_iniciar, v_p_pausar, v_p_reanudar, v_bloqueado, v_req_aprob, v_nombre
    FROM   tmp_obj_mov t
    WHERE  t.id_os_equipo = p_id_os_equipo;
    DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;

    IF v_llegada_utc IS NULL OR v_habilitado = 0 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, v_motivo_no AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_estado IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'El equipo no forma parte de los objetivos de este servicio.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Validación por acción (idempotente: lo que ya está aplicado responde éxito)
    IF v_accion = 'iniciar' THEN
        IF v_estado = 'en_ejecucion' THEN
            SET v_repetida = 1;
        ELSEIF v_estado = 'completado' THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, 'Este equipo ya está completado.' AS Mensaje;
            LEAVE proc;
        ELSEIF v_estado = 'pausado' THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, 'El equipo está pausado: usa "Reanudar".' AS Mensaje;
            LEAVE proc;
        ELSEIF v_bloqueado = 1 THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, 'Este equipo está bloqueado y no se puede intervenir.' AS Mensaje;
            LEAVE proc;
        ELSEIF v_p_iniciar = 0 THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, 'No se puede iniciar el trabajo en este equipo.' AS Mensaje;
            LEAVE proc;
        END IF;
    ELSEIF v_accion = 'pausar' THEN
        IF v_estado = 'pausado' THEN
            SET v_repetida = 1;
        ELSEIF v_p_pausar = 0 THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, 'Solo se puede pausar un equipo que está en ejecución.' AS Mensaje;
            LEAVE proc;
        END IF;
    ELSE
        IF v_estado = 'en_ejecucion' THEN
            SET v_repetida = 1;
        ELSEIF v_estado = 'pausado' AND v_req_aprob = 1 THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, 'Esperando aprobación de supervisor: este equipo no se puede reanudar todavía.' AS Mensaje;
            LEAVE proc;
        ELSEIF v_p_reanudar = 0 THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, 'Solo se puede reanudar un equipo pausado.' AS Mensaje;
            LEAVE proc;
        END IF;
    END IF;

    -- Un técnico trabaja en un solo equipo a la vez
    IF v_repetida = 0 AND v_accion IN ('iniciar', 'reanudar') THEN
        SELECT CONCAT(IFNULL(NULLIF(ec.codigo_cliente, ''), ec.codigo_tw), ' (', o2.numero, ')') INTO v_otro
        FROM   os_equipo x
        JOIN   equipo_cliente ec ON ec.id_equipo = x.id_equipo
        JOIN   orden_servicio o2 ON o2.id_os = x.id_os
        WHERE  x.id_usuario_ejecucion = p_id_usuario AND x.estado_ejecucion = 'en_proceso' AND x.pausado = 0
          AND  x.id <> p_id_os_equipo AND x.eliminado_en IS NULL
        LIMIT 1;
        IF v_otro IS NOT NULL THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, CONCAT('Ya estás trabajando en el equipo ', v_otro, ': pausa ese equipo antes de continuar con otro.') AS Mensaje;
            LEAVE proc;
        END IF;
    END IF;

    IF v_repetida = 0 THEN
        SET v_nuevo = CASE v_accion WHEN 'pausar' THEN 'pausado' ELSE 'en_ejecucion' END;
        SET v_ant_txt = CASE v_estado WHEN 'por_iniciar' THEN 'por iniciar' WHEN 'en_ejecucion' THEN 'en ejecución' WHEN 'pausado' THEN 'pausado'
                                      WHEN 'observado' THEN 'observado' ELSE v_estado END;
        SET v_nue_txt = CASE v_nuevo WHEN 'pausado' THEN 'pausado' ELSE 'en ejecución' END;

        IF v_accion = 'iniciar' THEN
            UPDATE os_equipo
            SET    estado_ejecucion = 'en_proceso', iniciado_utc = IFNULL(iniciado_utc, v_t_utc), reanudado_utc = v_t_utc,
                   pausado = 0, motivo_pausa = NULL, pausa_requiere_aprobacion = 0, id_usuario_ejecucion = p_id_usuario, modificado_por = p_id_usuario
            WHERE  id = p_id_os_equipo;

            -- El primer equipo iniciado pone la OS "en ejecución" y marca el inicio del trabajo (lo lee la bandeja de seguimiento)
            IF v_estado_os = 'en_ruta' THEN
                UPDATE orden_servicio SET estado = 'en_ejecucion', modificado_por = p_id_usuario, modificado_en = NOW() WHERE id_os = p_id_os;
            END IF;
            SELECT IF(COUNT(*) > 0, 1, 0) INTO v_hay_inicio
            FROM   evento_campo e
            JOIN   tabla_maestra m ON m.IdMaestro = 29 AND m.IdEmpresa = 1 AND m.Num1 = e.id_tipo_evento AND m.String2 = 'INICIO_TRABAJO'
            WHERE  e.id_os = p_id_os AND e.eliminado_en IS NULL AND e.timestamp_utc >= IFNULL(v_salida_utc, '1000-01-01');
            SET v_cod_evt = IF(v_hay_inicio = 0, 'INICIO_TRABAJO', 'REANUDA');
        ELSEIF v_accion = 'pausar' THEN
            UPDATE os_equipo
            SET    acumulado_seg = acumulado_seg + IF(reanudado_utc IS NULL, 0, GREATEST(0, TIMESTAMPDIFF(SECOND, reanudado_utc, v_t_utc))),
                   reanudado_utc = NULL, pausado = 1, motivo_pausa = v_motivo, pausa_requiere_aprobacion = 0, modificado_por = p_id_usuario
            WHERE  id = p_id_os_equipo;
            SET v_cod_evt = 'PAUSA';
        ELSE
            UPDATE os_equipo
            SET    reanudado_utc = v_t_utc, pausado = 0, motivo_pausa = NULL, pausa_requiere_aprobacion = 0, id_usuario_ejecucion = p_id_usuario,
                   modificado_por = p_id_usuario
            WHERE  id = p_id_os_equipo;
            SET v_cod_evt = 'REANUDA';
        END IF;

        -- Evento de campo (la bandeja de seguimiento lo muestra en el timeline del día)
        SELECT m.Num1 INTO v_tipo_evt FROM tabla_maestra m
        WHERE  m.IdMaestro = 29 AND m.IdEmpresa = 1 AND m.String2 = v_cod_evt AND m.eliminado_en IS NULL LIMIT 1;
        IF v_tipo_evt IS NOT NULL THEN
            INSERT INTO evento_campo (id_os, id_usuario, id_tipo_evento, timestamp_utc, sincronizado, notas, creado_por)
            VALUES (p_id_os, p_id_usuario, v_tipo_evt, v_t_utc, 1,
                    LEFT(CONCAT(CASE v_accion WHEN 'iniciar' THEN 'Trabajo iniciado en ' WHEN 'pausar' THEN 'Pausa en ' ELSE 'Trabajo reanudado en ' END, v_nombre,
                                IF(v_accion = 'pausar', CONCAT('. Motivo: ', v_motivo), ''),
                                IF(v_diferida = 1, '. Registrado sin conexión y enviado después.', '')), 1000),
                    p_id_usuario);
        END IF;

        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
        VALUES ('os_equipo', p_id_os_equipo, CONCAT(v_accion, '_equipo'), v_ant_txt, v_nue_txt,
                LEFT(CASE v_accion WHEN 'iniciar' THEN 'Inicio' WHEN 'pausar' THEN CONCAT('Pausa: ', v_motivo) ELSE 'Reanudación' END, 300),
                p_id_usuario, NOW(),
                JSON_OBJECT('id_os', p_id_os, 'accion', v_accion, 'diferida', v_diferida = 1));
    END IF;

    COMMIT;

    SELECT 2 AS IdTipoMensaje,
           IF(v_repetida = 1, 'El equipo ya estaba en ese estado.',
              CASE v_accion WHEN 'iniciar' THEN 'Trabajo iniciado.' WHEN 'pausar' THEN 'Equipo pausado.' ELSE 'Trabajo reanudado.' END) AS Mensaje;
    SELECT p_id_os_equipo AS id_os_equipo, v_accion AS accion,
           IF(v_accion = 'pausar', 'pausado', 'en_ejecucion') AS estado, v_repetida AS repetida, v_diferida AS diferida;
END$$

DELIMITER ;

-- ############################################################
-- 7) SP_ObtenerOpcionesEquipoNuevoMovil
-- ############################################################
-- ============================================================
-- SP_ObtenerOpcionesEquipoNuevoMovil  (App Mobile HU-07 — formulario "Equipo nuevo (NEW)" · lectura)
-- Listas que necesita el formulario para registrar en campo un equipo que no está en la lista de la O/S:
--   - marcas  : catálogo MARCA_SUMINISTRO (la marca se elige de la lista, no se escribe libre)
--   - tipos   : suministros ACTIVOS de clase equipo / instrumento / pesa ("Balanza industrial de plataforma"); la clasificación del equipo sale de su clase
-- La OS debe ser del técnico del token (misma respuesta si no existe o no es suya).
-- Resultados: 1 mensaje · 2 marcas (marca) · 3 tipos (id_suministro, descripcion, clase, marca, modelo).
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerOpcionesEquipoNuevoMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerOpcionesEquipoNuevoMovil(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT
)
proc: BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF NOT EXISTS (SELECT 1
                   FROM   orden_servicio os
                   WHERE  os.id_os = p_id_os AND os.eliminado_en IS NULL
                     AND  (os.id_tecnico_principal = p_id_usuario
                           OR EXISTS (SELECT 1 FROM os_personal op
                                      WHERE op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL))) THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio no encontrado o no asignado a tu usuario.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT t.String1 AS marca
    FROM   tabla_maestra t
    WHERE  t.Descripcion = 'MARCA_SUMINISTRO' AND t.IdEmpresa = 1 AND t.eliminado_en IS NULL AND NULLIF(TRIM(t.String1), '') IS NOT NULL
    ORDER BY t.String1;

    SELECT su.id_suministro, su.descripcion, su.clase, NULLIF(TRIM(su.marca), '') AS marca, NULLIF(TRIM(su.modelo), '') AS modelo
    FROM   suministros su
    WHERE  su.eliminado_en IS NULL AND su.estado = 'activo' AND su.clase IN ('equipo', 'instrumento', 'pesa')
    ORDER BY su.descripcion
    LIMIT 500;
END$$

DELIMITER ;

-- ############################################################
-- 8) SP_RegistrarEquipoNuevoMovil
-- ############################################################
-- ============================================================
-- SP_RegistrarEquipoNuevoMovil  (App Mobile HU-07 — "Equipo nuevo (NEW)" · escritura)
-- El técnico registra en campo un equipo que no está en la lista de la O/S ("Registrar y seleccionar").
--   - El técnico sale del token; la OS debe ser suya. Hard Stop (HU-06): solo con la llegada registrada y la OS en curso (SP_EvaluarCampoMovil).
--   - Obligatorios: N/S, código del cliente, marca (del catálogo MARCA_SUMINISTRO), modelo, tipo de equipo (suministro activo de clase
--     equipo / instrumento / pesa), ubicación y la foto de la placa (solo cámara; la valida y guarda el back antes de llamar a este SP).
--   - El cliente y la sede salen de la OS. La clasificación sale de la clase del suministro.
--   - Si el equipo YA existe en el maestro del cliente (mismo N/S + marca + modelo) NO se duplica: se agrega a esta O/S como objetivo
--     (ya_existia = 1, la foto no se usa). Si ya está en la lista de esta O/S: no se agrega otra vez (responde cuál es), salvo que lo haya
--     registrado el mismo técnico en esta O/S (reintento de la app): responde éxito con el ya registrado (ya_registrado = 1).
--   - Equipo creado: equipo_cliente en estado 'borrador' (pendiente de aprobación de la intranet) con COD TW PROVISIONAL "NEW-000123";
--     la intranet asigna el COD TW definitivo (EQ-TW-AAAA-NNNN) al aprobar el registro. Queda marcado registrado_en_campo, con la O/S y la
--     foto de la placa. El objetivo (os_equipo) queda con ingresado_en_campo = 1 y el mismo tipo de intervención que los demás de la O/S.
--   - Avisa por notificación a los supervisores/administradores del área del técnico y a su jefe (jefe_<área>); si no hay, a los administradores.
--   - Deja el registro en auditoria_evento (equipo_cliente y os_equipo).
-- Resultados: 1 mensaje; 2 (id_os_equipo, id_equipo, codigo_tw, ya_existia, ya_registrado, foto_guardada, notificados).
--   foto_guardada = 1 solo si el equipo se creó con esa foto (si no, el back borra el archivo).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_RegistrarEquipoNuevoMovil;

DELIMITER $$

CREATE PROCEDURE SP_RegistrarEquipoNuevoMovil(
    IN p_id_usuario     BIGINT,
    IN p_id_os          BIGINT,
    IN p_num_serie      VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_codigo_cliente VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_marca          VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_modelo         VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_id_suministro  BIGINT,
    IN p_ubicacion      VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_foto_placa     VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_serie       VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_codigo_cli  VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_marca       VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_modelo      VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_marca_cat   VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_ubicacion   VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado_os   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_numero_os   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_cliente  BIGINT;
    DECLARE v_id_sede     BIGINT;
    DECLARE v_salida_utc  DATETIME;
    DECLARE v_llegada_utc DATETIME;
    DECLARE v_habilitado  TINYINT;
    DECLARE v_motivo_no   VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_clase       VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_id_equipo   BIGINT DEFAULT NULL;
    DECLARE v_codigo_tw   VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_oe       BIGINT DEFAULT NULL;
    DECLARE v_oe_campo    TINYINT DEFAULT 0;
    DECLARE v_oe_orden    INT DEFAULT NULL;
    DECLARE v_oe_usuario  BIGINT DEFAULT NULL;
    DECLARE v_ya_existia  TINYINT DEFAULT 0;
    DECLARE v_ya_reg      TINYINT DEFAULT 0;
    DECLARE v_foto_ok     TINYINT DEFAULT 0;
    DECLARE v_tipo_interv INT DEFAULT NULL;
    DECLARE v_orden       INT DEFAULT 1;
    DECLARE v_area        VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_login       VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_nombre_tec  VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_texto       VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_notif       INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio no encontrado o no asignado a tu usuario.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_serie      = TRIM(IFNULL(p_num_serie, ''));
    SET v_codigo_cli = TRIM(IFNULL(p_codigo_cliente, ''));
    SET v_marca      = TRIM(IFNULL(p_marca, ''));
    SET v_modelo     = TRIM(IFNULL(p_modelo, ''));
    SET v_ubicacion  = TRIM(IFNULL(p_ubicacion, ''));

    IF v_serie = '' THEN
        SELECT 1 AS IdTipoMensaje, 'Ingresa el N/S del equipo.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_codigo_cli = '' THEN
        SELECT 1 AS IdTipoMensaje, 'Ingresa el código del equipo.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_marca = '' THEN
        SELECT 1 AS IdTipoMensaje, 'Selecciona la marca.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_modelo = '' THEN
        SELECT 1 AS IdTipoMensaje, 'Ingresa el modelo.' AS Mensaje; LEAVE proc;
    END IF;
    IF IFNULL(p_id_suministro, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Selecciona el tipo de equipo.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_ubicacion = '' THEN
        SELECT 1 AS IdTipoMensaje, 'Ingresa la ubicación del equipo.' AS Mensaje; LEAVE proc;
    END IF;
    IF CHAR_LENGTH(IFNULL(p_num_serie, '')) > 80 OR CHAR_LENGTH(IFNULL(p_codigo_cliente, '')) > 80
       OR CHAR_LENGTH(IFNULL(p_modelo, '')) > 80 OR CHAR_LENGTH(IFNULL(p_ubicacion, '')) > 200 THEN
        SELECT 1 AS IdTipoMensaje, 'Algún dato supera el largo permitido (N/S, código y modelo: 80; ubicación: 200).' AS Mensaje; LEAVE proc;
    END IF;
    IF NULLIF(TRIM(IFNULL(p_foto_placa, '')), '') IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Toma la foto de la placa del equipo (solo cámara).' AS Mensaje; LEAVE proc;
    END IF;

    -- La marca debe ser una del catálogo (se guarda con el nombre del catálogo)
    SELECT t.String1 INTO v_marca_cat
    FROM   tabla_maestra t
    WHERE  t.Descripcion = 'MARCA_SUMINISTRO' AND t.IdEmpresa = 1 AND t.eliminado_en IS NULL AND t.String1 = v_marca
    LIMIT 1;
    IF v_marca_cat IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'La marca no está en el catálogo: elige una de la lista.' AS Mensaje; LEAVE proc;
    END IF;
    SET v_marca = v_marca_cat;

    -- El tipo de equipo es un suministro activo de clase equipo / instrumento / pesa
    SELECT su.clase INTO v_clase
    FROM   suministros su
    WHERE  su.id_suministro = p_id_suministro AND su.eliminado_en IS NULL AND su.estado = 'activo' AND su.clase IN ('equipo', 'instrumento', 'pesa');
    IF v_clase IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'El tipo de equipo elegido no existe o no está activo.' AS Mensaje; LEAVE proc;
    END IF;

    START TRANSACTION;

    -- La OS debe ser del técnico del token (se bloquea la fila: dos envíos seguidos no se pisan)
    SELECT os.estado, os.numero, os.id_cliente, os.id_sede INTO v_estado_os, v_numero_os, v_id_cliente, v_id_sede
    FROM   orden_servicio os
    WHERE  os.id_os = p_id_os AND os.eliminado_en IS NULL
      AND  (os.id_tecnico_principal = p_id_usuario
            OR EXISTS (SELECT 1 FROM os_personal op
                       WHERE op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL))
    FOR UPDATE;
    IF v_estado_os IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Servicio no encontrado o no asignado a tu usuario.' AS Mensaje; LEAVE proc;
    END IF;

    -- Hard Stop (HU-06): una sola vez, en SP_EvaluarCampoMovil
    CALL SP_EvaluarCampoMovil(p_id_os, v_estado_os, v_salida_utc, v_llegada_utc, v_habilitado, v_motivo_no);
    IF v_habilitado = 0 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, v_motivo_no AS Mensaje; LEAVE proc;
    END IF;

    SELECT u.correo, u.area, TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))) INTO v_login, v_area, v_nombre_tec
    FROM   usuario u WHERE u.id_usuario = p_id_usuario LIMIT 1;

    -- ¿El equipo ya existe en el maestro del cliente? (misma regla que SP_GuardarEquipoCliente: serie + marca + modelo)
    SELECT ec.id_equipo, ec.codigo_tw INTO v_id_equipo, v_codigo_tw
    FROM   equipo_cliente ec
    WHERE  ec.id_cliente = v_id_cliente AND ec.SoftDelete = 0
      AND  ec.num_serie = v_serie AND ec.marca = v_marca AND ec.modelo = v_modelo
    ORDER BY ec.id_equipo LIMIT 1;

    IF v_id_equipo IS NOT NULL THEN
        SET v_ya_existia = 1;
        SELECT oe.id, oe.ingresado_en_campo, oe.orden, oe.creado_por INTO v_id_oe, v_oe_campo, v_oe_orden, v_oe_usuario
        FROM   os_equipo oe
        WHERE  oe.id_os = p_id_os AND oe.id_equipo = v_id_equipo AND oe.eliminado_en IS NULL
        LIMIT 1;

        IF v_id_oe IS NOT NULL THEN
            IF v_oe_campo = 1 AND v_oe_usuario = p_id_usuario THEN
                -- Reintento de la app: ya lo registró este técnico en esta O/S
                SET v_ya_reg = 1;
            ELSE
                ROLLBACK;
                SELECT 1 AS IdTipoMensaje,
                       CONCAT('Este equipo ya está en la lista de la O/S (', v_codigo_tw, '): búscalo y selecciónalo.') AS Mensaje;
                LEAVE proc;
            END IF;
        END IF;
    END IF;

    IF v_ya_reg = 0 THEN
        -- Mismo tipo de intervención que los demás objetivos de la O/S (la intranet lo puede cambiar); el orden va al final
        SELECT oe.id_tipo_intervencion INTO v_tipo_interv
        FROM   os_equipo oe
        WHERE  oe.id_os = p_id_os AND oe.eliminado_en IS NULL AND oe.id_tipo_intervencion IS NOT NULL
        ORDER BY oe.id LIMIT 1;
        SELECT IFNULL(MAX(IFNULL(oe.orden, oe.id)), 0) + 1 INTO v_orden
        FROM   os_equipo oe WHERE oe.id_os = p_id_os AND oe.eliminado_en IS NULL;

        IF v_id_equipo IS NULL THEN
            -- COD TW provisional (único): la intranet asigna el definitivo al aprobar el registro
            INSERT INTO equipo_cliente (
                codigo_tw, num_serie, id_cliente, id_sede, codigo_cliente, clasificacion, marca, modelo, ubicacion_especifica,
                es_pre_revisado, bloqueado_para_servicios, id_suministro, estado_operativo, es_activo, estado,
                usuario_registro, SoftDelete, UsuCre, FchCre, registrado_en_campo, id_os_registro, foto_placa_url)
            VALUES (
                CONCAT('NEW-', UUID_SHORT()), v_serie, v_id_cliente, v_id_sede, v_codigo_cli, v_clase, v_marca, v_modelo, v_ubicacion,
                0, 0, p_id_suministro, NULL, 1, 'borrador',
                v_login, 0, v_login, NOW(), 1, p_id_os, TRIM(p_foto_placa));
            SET v_id_equipo = LAST_INSERT_ID();
            SET v_codigo_tw = CONCAT('NEW-', LPAD(v_id_equipo, 6, '0'));
            UPDATE equipo_cliente SET codigo_tw = v_codigo_tw WHERE id_equipo = v_id_equipo;
            SET v_foto_ok = 1;
        END IF;

        INSERT INTO os_equipo (id_os, id_equipo, id_tipo_intervencion, orden, ingresado_en_campo, estado_ejecucion, creado_por)
        VALUES (p_id_os, v_id_equipo, v_tipo_interv, v_orden, 1, 'pendiente', p_id_usuario);
        SET v_id_oe = LAST_INSERT_ID();

        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
        VALUES ('os_equipo', v_id_oe, 'registrar_equipo_campo', NULL, 'por iniciar',
                LEFT(CONCAT(IF(v_ya_existia = 1, 'Equipo ya registrado agregado desde campo a ', 'Equipo nuevo registrado desde campo en '), v_numero_os,
                            ': N/S ', v_serie, ' · ', v_marca, ' ', v_modelo, ' · ', v_ubicacion), 900),
                p_id_usuario, NOW(),
                JSON_OBJECT('id_os', p_id_os, 'id_equipo', v_id_equipo, 'codigo_tw', v_codigo_tw, 'ya_existia', v_ya_existia = 1));

        IF v_ya_existia = 0 THEN
            INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
            VALUES ('equipo_cliente', v_id_equipo, 'registrar_equipo_campo', NULL, 'borrador',
                    LEFT(CONCAT('Registrado desde la app móvil en ', v_numero_os, ' por ', v_nombre_tec, ': pendiente de aprobación (COD TW provisional ', v_codigo_tw, ').'), 900),
                    p_id_usuario, NOW(),
                    JSON_OBJECT('id_os', p_id_os, 'num_serie', v_serie, 'marca', v_marca, 'modelo', v_modelo, 'id_suministro', p_id_suministro));

            -- Aviso para aprobar el registro: supervisores/administradores del área del técnico y su jefe; si no hay, administradores
            SET v_texto = LEFT(CONCAT(v_nombre_tec, ' registró un equipo nuevo en la O/S ', v_numero_os, ' (N/S ', v_serie, ' · ', v_marca, ' ', v_modelo,
                                      '). Falta aprobar el registro y asignar su COD TW.'), 500);
            INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
            SELECT u.id_usuario, 5, 'Equipo nuevo por aprobar', v_texto, 'equipo_cliente', v_id_equipo, NOW(), p_id_usuario
            FROM   usuario u
            WHERE  u.eliminado_en IS NULL AND u.estado = 'activo' AND u.id_usuario <> p_id_usuario
              AND  IFNULL(v_area, '') <> ''
              AND  ((u.area = v_area AND u.rol_sistema IN ('supervisor', 'administrador'))
                    OR u.cargo = CONCAT('jefe_', v_area));
            SET v_notif = ROW_COUNT();
            IF v_notif = 0 THEN
                INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
                SELECT u.id_usuario, 5, 'Equipo nuevo por aprobar', v_texto, 'equipo_cliente', v_id_equipo, NOW(), p_id_usuario
                FROM   usuario u
                WHERE  u.eliminado_en IS NULL AND u.estado = 'activo' AND u.id_usuario <> p_id_usuario
                  AND  u.rol_sistema IN ('administrador', 'admin');
                SET v_notif = ROW_COUNT();
            END IF;
        END IF;
    END IF;

    COMMIT;

    SELECT 2 AS IdTipoMensaje,
           CASE WHEN v_ya_reg = 1 THEN 'Ya registraste este equipo.'
                WHEN v_ya_existia = 1 THEN 'El equipo ya estaba registrado en el sistema: se agregó a esta O/S.'
                ELSE 'Equipo registrado. El COD TW lo asigna la intranet al aprobar el registro.' END AS Mensaje;
    SELECT v_id_oe AS id_os_equipo, v_id_equipo AS id_equipo, v_codigo_tw AS codigo_tw, v_ya_existia AS ya_existia, v_ya_reg AS ya_registrado,
           v_foto_ok AS foto_guardada, v_notif AS notificados;
END$$

DELIMITER ;

-- ============================================================
-- COMPROBACIÓN (solo lectura, no modifica datos)
-- ============================================================

-- A) Los 7 procedimientos deben aparecer con la fecha/hora de hoy
SELECT ROUTINE_NAME AS procedimiento, LAST_ALTERED AS actualizado
FROM   INFORMATION_SCHEMA.ROUTINES
WHERE  ROUTINE_SCHEMA = DATABASE()
  AND  ROUTINE_NAME IN ('SP_EvaluarCampoMovil', 'SP_ArmarObjetivosMovil', 'SP_ObtenerObjetivosMovil', 'SP_BuscarEquipoQrMovil',
                        'SP_CambiarEstadoEquipoMovil', 'SP_ObtenerOpcionesEquipoNuevoMovil', 'SP_RegistrarEquipoNuevoMovil')
ORDER BY ROUTINE_NAME;

-- B) Tiempos y siglas del catálogo de tipos de intervención (Num2 = minutos estimados, String3 = sigla)
SELECT Num1 AS id, String1 AS tipo, String2 AS codigo, String3 AS sigla, Num2 AS minutos
FROM   tabla_maestra
WHERE  Descripcion = 'TIPO_INTERVENCION_EQUIPO' AND IdEmpresa = 1
ORDER BY Num1;

-- C) Un servicio inexistente debe responder "Servicio no encontrado o no asignado a tu usuario."
CALL SP_ObtenerObjetivosMovil(0, 0, NULL);

-- D) Objetivos de la última OS en curso: con llegada registrada devuelve resumen, contadores y equipos; sin llegada responde el Hard Stop
--    ("Sin marca de llegada: primero registra tu llegada a planta…")
SET @os  = (SELECT MAX(id_os) FROM orden_servicio WHERE estado IN ('en_ruta', 'en_ejecucion', 'pausada') AND eliminado_en IS NULL);
SET @tec = (SELECT id_tecnico_principal FROM orden_servicio WHERE id_os = @os);
CALL SP_ObtenerObjetivosMovil(@tec, @os, NULL);

-- E) Listas del formulario "Equipo nuevo": marcas y tipos de equipo (suministros activos de clase equipo / instrumento / pesa)
CALL SP_ObtenerOpcionesEquipoNuevoMovil(@tec, @os);
