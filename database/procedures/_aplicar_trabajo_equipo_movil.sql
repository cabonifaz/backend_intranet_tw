-- Aplicar en la base (migración 99 + 3 procedimientos de HU-08 / HU-09, sin datos de prueba). Ejecutar completo con Alt+X. NO subir al repositorio.
-- Requiere haber aplicado antes _aplicar_objetivos_movil.sql (HU-07). Después REINICIAR la API (MySqlConnector guarda en caché los procedimientos).

-- ############################################################
-- 1) Migración 99
-- ############################################################
-- ============================================================
-- Migración 99 — Trabajo en el equipo y Variables ambientales desde la app móvil (App Mobile HU-08 / HU-09)
--   variable_ambiental era solo de la Orden de Metrología (id_om NOT NULL). La app registra las condiciones del entorno por EQUIPO de una OS
--   (servicio técnico) o de una OM (metrología), así que:
--     - id_om pasa a ser opcional;
--     - nuevas columnas id_os, id_equipo (equipo_cliente) y procedencia ("N.I" = no indicado, por defecto);
--     - índice por (id_os, id_equipo).
--   La fecha y la hora (registrado_en, UTC) las pone el servidor. Una sola fila vigente por OS + equipo: guardar otra vez la actualiza
--   (el cambio queda en auditoria_evento).
--   No borra ni cambia datos existentes. IDEMPOTENTE. Requiere las migraciones 80 y 98.
-- ============================================================

ALTER TABLE variable_ambiental MODIFY COLUMN id_om BIGINT NULL;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'variable_ambiental' AND COLUMN_NAME = 'id_os'),
    'ALTER TABLE variable_ambiental ADD COLUMN id_os BIGINT NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'variable_ambiental' AND COLUMN_NAME = 'id_equipo'),
    'ALTER TABLE variable_ambiental ADD COLUMN id_equipo BIGINT NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'variable_ambiental' AND COLUMN_NAME = 'procedencia'),
    'ALTER TABLE variable_ambiental ADD COLUMN procedencia VARCHAR(100) NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'variable_ambiental' AND INDEX_NAME = 'ix_variable_ambiental_os_equipo'),
    'ALTER TABLE variable_ambiental ADD KEY ix_variable_ambiental_os_equipo (id_os, id_equipo)', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SELECT 'Migración 99 (debe ser 4)' AS verificacion,
       (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'variable_ambiental'
           AND COLUMN_NAME IN ('id_os', 'id_equipo', 'procedencia'))
     + (SELECT COUNT(*) FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'variable_ambiental'
           AND INDEX_NAME = 'ix_variable_ambiental_os_equipo' AND SEQ_IN_INDEX = 1) AS valor;

-- ############################################################
-- 2) SP_ArmarObjetivosMovil (actualizado: tipo de servicio de respaldo)
-- ############################################################
-- ============================================================
-- SP_ArmarObjetivosMovil  (App Mobile HU-07 — apoyo, no es un endpoint)
-- Arma, UNA sola vez, los objetivos de la OS (un objetivo = un equipo a intervenir, `os_equipo`) en la tabla temporal `tmp_obj_mov`,
-- con su estado, tiempos y lo que el técnico puede hacer. Lo usan la lista, la búsqueda por QR y las acciones (iniciar/pausar/reanudar):
-- la regla de qué botón se habilita vive solo aquí. Los SP que la llaman deben terminar con DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov.
--   Objetivos = equipos de la OS que se confirmaron en la programación vigente (sin selección, todos) + los registrados en campo (NEW).
--   estado: por_iniciar | en_ejecucion | pausado | completado | observado
--   Observados (contador) = observado + pausados que esperan aprobación de un supervisor (esos NO se pueden reanudar).
--   Tipo de intervención = el del equipo en la OS; si no lo tiene, el tipo de servicio de la OS (TIPO_SERVICIO), sin sigla.
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
           LEFT(COALESCE(ti.String1, tsv.String1), 100), NULLIF(ti.String3, ''),
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
    LEFT JOIN orden_servicio osv ON osv.id_os = oe.id_os
    LEFT JOIN tabla_maestra tsv ON tsv.Descripcion = 'TIPO_SERVICIO' AND tsv.IdEmpresa = 1 AND tsv.Num1 = osv.id_tipo_servicio
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
-- 3) SP_ObtenerTrabajoEquipoMovil
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

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
        DROP TEMPORARY TABLE IF EXISTS tmp_etapas_mov;
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

    SELECT COUNT(*) INTO v_n_fotos
    FROM   evidencia_fotografica f WHERE f.id_os = p_id_os AND f.id_equipo = v_id_equipo AND f.eliminado_en IS NULL;

    SELECT it.id_informe INTO v_informe
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
        (2, 'fotos', 'Registro fotográfico', IF(v_n_fotos > 0, 'en_curso', 'pendiente'),
            IF(v_n_fotos > 0, CONCAT(v_n_fotos, IF(v_n_fotos = 1, ' foto registrada', ' fotos registradas')), 'Fotos del equipo y del informe a mano'), 0),
        (3, 'ensayos', 'Ensayos y Calibración', IF(v_vars = 0, 'bloqueado', IF(v_n_ensayos > 0, 'en_curso', 'pendiente')),
            IF(v_vars = 0, 'Se habilita al guardar las variables ambientales', 'Verificación de pesaje tras el ajuste'), 0),
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

-- ############################################################
-- 4) SP_GuardarVariablesAmbientalesMovil
-- ############################################################
-- ============================================================
-- SP_GuardarVariablesAmbientalesMovil  (App Mobile HU-09 — Registro de variables ambientales · escritura)
-- El técnico registra las condiciones del entorno del equipo antes de proceder con el pesaje.
--   - El técnico sale del token; la OS debe ser suya. Hard Stop (HU-06): solo con la llegada registrada y la OS en curso.
--   - El equipo debe estar EN EJECUCIÓN (primero se inicia desde los objetivos).
--   - Obligatorios: temperatura (°C, de -20 a 60) y humedad relativa (%, de 0 a 100). Procedencia opcional: vacía = "N.I" (no indicado).
--   - Fecha y hora las pone el servidor (UTC); el técnico no las edita. Sin conexión la app envía p_capturado_utc (hora del teléfono, solo se
--     respeta si no es futura —tolerancia 5 min— ni tiene más de 24 h).
--   - Una fila vigente por OS + equipo: guardar otra vez la actualiza (y el cambio queda en auditoria_evento con lo anterior y lo nuevo).
--     Repetir exactamente el mismo envío responde éxito sin cambiar nada.
--   - Habilita "Ensayos y Calibración" (SP_ObtenerTrabajoEquipoMovil la desbloquea al existir la fila).
-- Resultados: 1 mensaje; 2 (temperatura_c, humedad_pct, procedencia, registrado_en en Lima, actualizada, repetida).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_GuardarVariablesAmbientalesMovil;

DELIMITER $$

CREATE PROCEDURE SP_GuardarVariablesAmbientalesMovil(
    IN p_id_usuario    BIGINT,
    IN p_id_os         BIGINT,
    IN p_id_os_equipo  BIGINT,
    IN p_temperatura   DECIMAL(6,2),
    IN p_humedad       DECIMAL(5,2),
    IN p_procedencia   VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_capturado_utc DATETIME
)
proc: BEGIN
    DECLARE v_estado_os   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_numero_os   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_salida_utc  DATETIME;
    DECLARE v_llegada_utc DATETIME;
    DECLARE v_habilitado  TINYINT;
    DECLARE v_motivo      VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_equipo   BIGINT DEFAULT NULL;
    DECLARE v_estado      VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_proc        VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_var      BIGINT DEFAULT NULL;
    DECLARE v_t_ant       DECIMAL(6,2);
    DECLARE v_h_ant       DECIMAL(5,2);
    DECLARE v_p_ant       VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_ahora_utc   DATETIME;
    DECLARE v_t_utc       DATETIME;
    DECLARE v_repetida    TINYINT DEFAULT 0;
    DECLARE v_actualiza   TINYINT DEFAULT 0;

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
    IF p_temperatura IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Ingresa la temperatura (°C).' AS Mensaje; LEAVE proc;
    END IF;
    IF p_humedad IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Ingresa la humedad relativa (%).' AS Mensaje; LEAVE proc;
    END IF;
    IF p_temperatura < -20 OR p_temperatura > 60 THEN
        SELECT 1 AS IdTipoMensaje, 'La temperatura debe estar entre -20 y 60 °C.' AS Mensaje; LEAVE proc;
    END IF;
    IF p_humedad < 0 OR p_humedad > 100 THEN
        SELECT 1 AS IdTipoMensaje, 'La humedad relativa debe estar entre 0 y 100 %.' AS Mensaje; LEAVE proc;
    END IF;
    IF CHAR_LENGTH(TRIM(IFNULL(p_procedencia, ''))) > 100 THEN
        SELECT 1 AS IdTipoMensaje, 'La procedencia puede tener hasta 100 caracteres.' AS Mensaje; LEAVE proc;
    END IF;
    SET v_proc = IFNULL(NULLIF(TRIM(IFNULL(p_procedencia, '')), ''), 'N.I');

    SET v_ahora_utc = UTC_TIMESTAMP();
    SET v_t_utc     = v_ahora_utc;
    IF p_capturado_utc IS NOT NULL AND p_capturado_utc >= v_ahora_utc - INTERVAL 24 HOUR AND p_capturado_utc <= v_ahora_utc + INTERVAL 5 MINUTE THEN
        SET v_t_utc = LEAST(p_capturado_utc, v_ahora_utc);
    END IF;

    START TRANSACTION;

    SELECT os.estado, os.numero INTO v_estado_os, v_numero_os
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

    CALL SP_ArmarObjetivosMovil(p_id_os, v_estado_os, v_salida_utc, v_llegada_utc, v_habilitado, v_motivo);
    SELECT t.id_equipo, t.estado INTO v_id_equipo, v_estado FROM tmp_obj_mov t WHERE t.id_os_equipo = p_id_os_equipo;
    DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;

    IF v_habilitado = 0 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, v_motivo AS Mensaje; LEAVE proc;
    END IF;
    IF v_id_equipo IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'El equipo no forma parte de los objetivos de este servicio.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_estado <> 'en_ejecucion' THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje,
               IF(v_estado = 'pausado', 'El equipo está pausado: reanúdalo para registrar las variables ambientales.',
                  IF(v_estado = 'completado', 'Este equipo ya está completado.', 'Primero inicia el trabajo en este equipo desde los objetivos.')) AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT va.id_variable, va.temperatura_c, va.humedad_pct, IFNULL(va.procedencia, 'N.I') INTO v_id_var, v_t_ant, v_h_ant, v_p_ant
    FROM   variable_ambiental va
    WHERE  va.id_os = p_id_os AND va.id_equipo = v_id_equipo AND va.eliminado_en IS NULL
    ORDER BY va.id_variable DESC LIMIT 1
    FOR UPDATE;

    IF v_id_var IS NOT NULL AND v_t_ant = p_temperatura AND v_h_ant = p_humedad AND v_p_ant = v_proc THEN
        SET v_repetida = 1;
    ELSEIF v_id_var IS NOT NULL THEN
        SET v_actualiza = 1;
        UPDATE variable_ambiental
        SET    temperatura_c = p_temperatura, humedad_pct = p_humedad, procedencia = v_proc, id_usuario = p_id_usuario,
               registrado_en = v_t_utc, modificado_por = p_id_usuario
        WHERE  id_variable = v_id_var;
    ELSE
        INSERT INTO variable_ambiental (id_om, id_os, id_equipo, id_usuario, temperatura_c, humedad_pct, procedencia, registrado_en, creado_por)
        VALUES (NULL, p_id_os, v_id_equipo, p_id_usuario, p_temperatura, p_humedad, v_proc, v_t_utc, p_id_usuario);
        SET v_id_var = LAST_INSERT_ID();
    END IF;

    IF v_repetida = 0 THEN
        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
        VALUES ('os_equipo', p_id_os_equipo, IF(v_actualiza = 1, 'actualizar_variables_ambientales', 'registrar_variables_ambientales'),
                IF(v_actualiza = 1, CONCAT(v_t_ant, ' °C · ', v_h_ant, ' % · ', v_p_ant), NULL),
                CONCAT(p_temperatura, ' °C · ', p_humedad, ' % · ', v_proc),
                LEFT(CONCAT('Variables ambientales de ', v_numero_os, ': ', p_temperatura, ' °C, ', p_humedad, ' %, procedencia ', v_proc), 300),
                p_id_usuario, NOW(),
                JSON_OBJECT('id_os', p_id_os, 'id_variable', v_id_var));
    END IF;

    COMMIT;

    SELECT 2 AS IdTipoMensaje,
           IF(v_repetida = 1, 'Las variables ambientales ya estaban registradas.', 'Variables ambientales guardadas. Ya puedes continuar con Ensayos y Calibración.') AS Mensaje;
    SELECT p_temperatura AS temperatura_c, p_humedad AS humedad_pct, v_proc AS procedencia,
           CONVERT_TZ(IF(v_repetida = 1, (SELECT va.registrado_en FROM variable_ambiental va WHERE va.id_variable = v_id_var), v_t_utc), '+00:00', '-05:00') AS registrado_en,
           v_actualiza AS actualizada, v_repetida AS repetida;
END$$

DELIMITER ;

-- ============================================================
-- COMPROBACIÓN (solo lectura, no modifica datos)
-- ============================================================
-- A) Los 3 procedimientos con la fecha/hora de hoy
SELECT ROUTINE_NAME AS procedimiento, LAST_ALTERED AS actualizado FROM INFORMATION_SCHEMA.ROUTINES
WHERE ROUTINE_SCHEMA = DATABASE() AND ROUTINE_NAME IN ('SP_ArmarObjetivosMovil', 'SP_ObtenerTrabajoEquipoMovil', 'SP_GuardarVariablesAmbientalesMovil') ORDER BY ROUTINE_NAME;

-- B) Un equipo inexistente debe responder "Servicio no encontrado o no asignado a tu usuario."
CALL SP_ObtenerTrabajoEquipoMovil(0, 0, 0);

-- C) Objetivos de la última OS en curso: ahora el tipo de intervención cae al tipo de servicio de la OS (columna tipo_intervencion)
SET @os  = (SELECT MAX(id_os) FROM orden_servicio WHERE estado IN ('en_ruta', 'en_ejecucion', 'pausada') AND eliminado_en IS NULL);
SET @tec = (SELECT id_tecnico_principal FROM orden_servicio WHERE id_os = @os);
CALL SP_ObtenerObjetivosMovil(@tec, @os, NULL);

-- D) Trabajo del primer equipo de esa OS: si no está iniciado responde "Primero inicia el trabajo en este equipo desde los objetivos."
SET @oe = (SELECT MIN(id) FROM os_equipo WHERE id_os = @os AND eliminado_en IS NULL);
CALL SP_ObtenerTrabajoEquipoMovil(@tec, @os, @oe);
