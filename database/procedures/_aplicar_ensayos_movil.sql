-- Aplicar en la base (migración 100 + procedimientos de la HU-10, sin datos de prueba). Ejecutar completo con Alt+X. NO subir al repositorio.
-- Requiere haber aplicado antes _aplicar_objetivos_movil.sql (HU-07) y _aplicar_trabajo_equipo_movil.sql (HU-08/09). Después REINICIAR la API.

-- ############################################################
-- 1) Migración 100
-- ############################################################
-- ============================================================
-- Migración 100 — Ejecución de Ensayos y Calibración desde la app móvil (App Mobile HU-10)
--   El técnico registra las lecturas de pesaje y excentricidad del equipo; la app envía solo la carga (L) y la indicación (I) y el servidor calcula
--   el error (E = I − L), el EMP (error máximo permitido según la clase y e) y la conformidad. Se guarda en informe_ensayo (migración 93), que es lo que
--   luego lee la Cabecera del informe.
--   1. informe_ensayo: + grupo (excentricidad: número de la carga de prueba) y critico (la lectura supera el EMP).
--   2. informe_tecnico: + forma_plato (rectangular | circular | triangular, define las posiciones de excentricidad), error_critico_motivo (motivo con el
--      que el técnico guardó "de todas formas" un ensayo con error crítico) y ensayos_finalizado_en (cuándo finalizó la etapa).
--   No borra ni cambia datos existentes. IDEMPOTENTE. Requiere las migraciones 93, 98 y 99.
-- ============================================================

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'informe_ensayo' AND COLUMN_NAME = 'grupo'),
    'ALTER TABLE informe_ensayo ADD COLUMN grupo INT NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'informe_ensayo' AND COLUMN_NAME = 'critico'),
    'ALTER TABLE informe_ensayo ADD COLUMN critico TINYINT(1) NOT NULL DEFAULT 0', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'informe_tecnico' AND COLUMN_NAME = 'forma_plato'),
    'ALTER TABLE informe_tecnico ADD COLUMN forma_plato VARCHAR(20) NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'informe_tecnico' AND COLUMN_NAME = 'error_critico_motivo'),
    'ALTER TABLE informe_tecnico ADD COLUMN error_critico_motivo VARCHAR(300) NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'informe_tecnico' AND COLUMN_NAME = 'ensayos_finalizado_en'),
    'ALTER TABLE informe_tecnico ADD COLUMN ensayos_finalizado_en DATETIME NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SELECT 'Migración 100 (debe ser 5)' AS verificacion,
       (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'informe_ensayo' AND COLUMN_NAME IN ('grupo', 'critico'))
     + (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'informe_tecnico'
           AND COLUMN_NAME IN ('forma_plato', 'error_critico_motivo', 'ensayos_finalizado_en')) AS valor;

-- ############################################################
-- 2) SP_ArmarObjetivosMovil (actualizado: tipo = concepto del servicio)
-- ############################################################
-- ============================================================
-- SP_ArmarObjetivosMovil  (App Mobile HU-07 — apoyo, no es un endpoint)
-- Arma, UNA sola vez, los objetivos de la OS (un objetivo = un equipo a intervenir, `os_equipo`) en la tabla temporal `tmp_obj_mov`,
-- con su estado, tiempos y lo que el técnico puede hacer. Lo usan la lista, la búsqueda por QR y las acciones (iniciar/pausar/reanudar):
-- la regla de qué botón se habilita vive solo aquí. Los SP que la llaman deben terminar con DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov.
--   Objetivos = equipos de la OS que se confirmaron en la programación vigente (sin selección, todos) + los registrados en campo (NEW).
--   estado: por_iniciar | en_ejecucion | pausado | completado | observado
--   Observados (contador) = observado + pausados que esperan aprobación de un supervisor (esos NO se pueden reanudar).
--   Tipo de intervención = el del equipo en la OS; si no lo tiene, el concepto del servicio (os_concepto: el aplicado a ese equipo o, si no hay,
--   el general de la OS, p. ej. "Servicio Mantenimiento y Calibración"); si tampoco, el tipo de servicio de la OS (TIPO_SERVICIO). Sin sigla.
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
           LEFT(COALESCE(ti.String1,
                         (SELECT oc.descripcion FROM os_concepto oc
                          LEFT JOIN os_concepto_equipo oce ON oce.id_os_concepto = oc.id AND oce.eliminado_en IS NULL
                          WHERE oc.id_os = oe.id_os AND oc.eliminado_en IS NULL
                            AND (oce.id_os_equipo = oe.id
                                 OR NOT EXISTS (SELECT 1 FROM os_concepto_equipo z WHERE z.id_os_concepto = oc.id AND z.eliminado_en IS NULL))
                          ORDER BY (oce.id_os_equipo = oe.id) DESC, IFNULL(oc.orden, oc.id), oc.id LIMIT 1),
                         tsv.String1), 100), NULLIF(ti.String3, ''),
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
-- 3) SP_EmpEnsayoMovil
-- ############################################################
-- ============================================================
-- SP_EmpEnsayoMovil  (App Mobile HU-10 — apoyo, no es un endpoint)
-- Error máximo permitido (EMP) de una carga, UNA sola vez: ±0,5 e, ±1 e o ±1,5 e según cuántas divisiones (m = carga / e) tenga la carga y la clase de
-- exactitud del equipo (verificación inicial, OIML R76):
--   clase I   : hasta 50 000 e → 0,5 e · hasta 200 000 e → 1 e · más → 1,5 e
--   clase II  : hasta  5 000 e → 0,5 e · hasta  20 000 e → 1 e · más → 1,5 e
--   clase III : hasta    500 e → 0,5 e · hasta   2 000 e → 1 e · más → 1,5 e
--   clase IIII (IV): hasta 50 e → 0,5 e · hasta 200 e → 1 e · más → 1,5 e
-- Con la clase vacía o desconocida, o sin e, el EMP es NULL (no se puede evaluar). Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_EmpEnsayoMovil;

DELIMITER $$

CREATE PROCEDURE SP_EmpEnsayoMovil(
    IN  p_clase VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN  p_e     DECIMAL(14,4),
    IN  p_carga DECIMAL(14,4),
    OUT p_emp   DECIMAL(14,4)
)
BEGIN
    DECLARE v_l1 DECIMAL(14,2) DEFAULT NULL;
    DECLARE v_l2 DECIMAL(14,2) DEFAULT NULL;
    DECLARE v_m  DECIMAL(24,6);

    SET p_emp = NULL;
    IF p_e IS NULL OR p_e <= 0 OR p_carga IS NULL THEN
        SET p_emp = NULL;
    ELSE
        CASE UPPER(TRIM(IFNULL(p_clase, '')))
            WHEN 'I'    THEN SET v_l1 = 50000, v_l2 = 200000;
            WHEN 'II'   THEN SET v_l1 = 5000,  v_l2 = 20000;
            WHEN 'III'  THEN SET v_l1 = 500,   v_l2 = 2000;
            WHEN 'IIII' THEN SET v_l1 = 50,    v_l2 = 200;
            WHEN 'IV'   THEN SET v_l1 = 50,    v_l2 = 200;
            ELSE BEGIN END;
        END CASE;
        IF v_l1 IS NOT NULL THEN
            SET v_m = p_carga / p_e;
            SET p_emp = p_e * IF(v_m <= v_l1, 0.5, IF(v_m <= v_l2, 1, 1.5));
        END IF;
    END IF;
END$$

DELIMITER ;

-- ############################################################
-- 4) SP_ContactoEncargadoEnsayoMovil
-- ############################################################
-- ============================================================
-- SP_ContactoEncargadoEnsayoMovil  (App Mobile HU-10 — apoyo, no es un endpoint)
-- Encargado del área responsable de la OS según la RQ (area_servicio_rq: metrologia | servicio_tecnico), UNA sola vez. Lo usan "Llamar al encargado",
-- el aviso de "Guardar de todas formas" y la cabecera de Ensayos.
--   Prioridad: el usuario activo con cargo jefe_<área>; si no hay, un supervisor / administrador del área; si no hay, nadie (todo NULL).
--   p_area = área de la RQ; p_nombre, p_cargo, p_telefono, p_id_usuario = del encargado. Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ContactoEncargadoEnsayoMovil;

DELIMITER $$

CREATE PROCEDURE SP_ContactoEncargadoEnsayoMovil(
    IN  p_id_os     BIGINT,
    OUT p_area      VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    OUT p_id_usuario BIGINT,
    OUT p_nombre    VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    OUT p_cargo     VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    OUT p_telefono  VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
BEGIN
    SET p_area = NULL, p_id_usuario = NULL, p_nombre = NULL, p_cargo = NULL, p_telefono = NULL;

    SELECT asr.area_usuario INTO p_area
    FROM   orden_servicio os
    JOIN   expediente_digital ed ON ed.id_expediente = os.id_expediente
    JOIN   requerimiento      rq ON rq.id_requerimiento = ed.id_requerimiento
    JOIN   area_servicio_rq  asr ON asr.id_area_rq = rq.id_area
    WHERE  os.id_os = p_id_os
    LIMIT 1;

    IF p_area IS NOT NULL THEN
        SELECT u.id_usuario, TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))),
               COALESCE(c.String1, u.cargo, IF(p_area = 'metrologia', 'Jefe de Metrología', 'Jefe de Servicio Técnico')),
               NULLIF(TRIM(u.telefono), '')
        INTO   p_id_usuario, p_nombre, p_cargo, p_telefono
        FROM   usuario u
        LEFT JOIN tabla_maestra c ON c.IdMaestro = 80 AND c.IdEmpresa = 1 AND c.String2 = u.cargo
        WHERE  u.eliminado_en IS NULL AND u.estado = 'activo'
          AND  (u.cargo = CONCAT('jefe_', p_area) OR (u.area = p_area AND u.rol_sistema IN ('supervisor', 'administrador')))
        ORDER BY (u.cargo = CONCAT('jefe_', p_area)) DESC, (NULLIF(TRIM(u.telefono), '') IS NOT NULL) DESC, u.id_usuario
        LIMIT 1;
    END IF;
END$$

DELIMITER ;

-- ############################################################
-- 5) SP_ContextoEnsayoMovil
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
    DECLARE v_estado_os   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_salida_utc  DATETIME;
    DECLARE v_llegada_utc DATETIME;
    DECLARE v_motivo      VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_vars        INT DEFAULT 0;
    DECLARE v_cap_txt     VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_d_txt       VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_e_txt       VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    SET p_mensaje = NULL, p_id_equipo = NULL, p_estado_equipo = NULL, p_habilitado = 0, p_numero = NULL, p_nombre_equipo = NULL, p_numero_os = NULL,
        p_clase = NULL, p_unidad = 'kg', p_cap_max = NULL, p_d = NULL, p_e = NULL;

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
            SELECT t.id_equipo, t.estado, t.numero, t.nombre INTO p_id_equipo, p_estado_equipo, p_numero, p_nombre_equipo
            FROM   tmp_obj_mov t WHERE t.id_os_equipo = p_id_os_equipo;
            IF p_id_equipo IS NULL THEN
                SET p_mensaje = 'El equipo no forma parte de los objetivos de este servicio.';
            ELSEIF p_estado_equipo NOT IN ('en_ejecucion', 'pausado', 'completado') THEN
                SET p_mensaje = 'Primero inicia el trabajo en este equipo desde los objetivos.';
            END IF;
        END IF;
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
    END IF;

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
-- 6) SP_ObtenerEnsayosMovil
-- ############################################################
-- ============================================================
-- SP_ObtenerEnsayosMovil  (App Mobile HU-10 — Ensayos y Calibración · lectura)
-- Lo que necesita la pantalla: especificaciones del equipo (unidad, clase, capacidad máxima, d, e), la forma del plato, las lecturas ya guardadas de
-- pesaje y excentricidad (con su error, EMP y conformidad, calculados por el servidor al guardar), el estado de la etapa y el encargado del área a quien
-- llamar. Las reglas de acceso (Hard Stop, equipo iniciado, variables ambientales guardadas) están en SP_ContextoEnsayoMovil.
--   puede_registrar = el equipo está EN EJECUCIÓN. Sin clase de exactitud o sin e el EMP no se puede evaluar (evaluable = 0).
--   acepta_error = el técnico guardó "de todas formas" con un motivo (error_critico_motivo).
-- Resultados: 1 mensaje · 2 cabecera (1 fila) · 3 pesaje · 4 excentricidad · 5 encargado (0 o 1 fila).
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerEnsayosMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerEnsayosMovil(
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
    DECLARE v_clase    VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_unidad   VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cap      DECIMAL(14,4);
    DECLARE v_d        DECIMAL(14,4);
    DECLARE v_e        DECIMAL(14,4);
    DECLARE v_informe  BIGINT DEFAULT NULL;
    DECLARE v_forma    VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_motivo   VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_final    DATETIME DEFAULT NULL;
    DECLARE v_area     VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_enc   BIGINT;
    DECLARE v_nom_enc  VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_car_enc  VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tel_enc  VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    CALL SP_ContextoEnsayoMovil(p_id_usuario, p_id_os, p_id_os_equipo, v_msg, v_id_eq, v_est_eq, v_hab, v_numero, v_nombre, v_num_os, v_clase, v_unidad, v_cap, v_d, v_e);
    IF v_msg IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT it.id_informe, it.forma_plato, it.error_critico_motivo, it.ensayos_finalizado_en INTO v_informe, v_forma, v_motivo, v_final
    FROM   informe_tecnico it
    WHERE  it.id_os = p_id_os AND it.id_equipo = v_id_eq AND it.eliminado_en IS NULL
    ORDER BY it.id_informe DESC LIMIT 1;

    CALL SP_ContactoEncargadoEnsayoMovil(p_id_os, v_area, v_id_enc, v_nom_enc, v_car_enc, v_tel_enc);

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Cabecera
    SELECT p_id_os AS id_os, p_id_os_equipo AS id_os_equipo, v_num_os AS numero_os, v_nombre AS nombre, v_numero AS numero,
           v_unidad AS unidad, v_clase AS clase, v_cap AS cap_maxima, v_d AS d, v_e AS e, IF(v_clase IS NOT NULL AND v_e IS NOT NULL AND v_e > 0, 1, 0) AS evaluable,
           IFNULL(v_forma, 'rectangular') AS forma_plato, v_motivo AS motivo_error_critico, IF(v_motivo IS NULL, 0, 1) AS acepta_error,
           IF(v_final IS NULL, 0, 1) AS finalizado,
           IF(v_final IS NULL, NULL, CONVERT_TZ(v_final, '+00:00', '-05:00')) AS finalizado_en,
           IF(v_est_eq = 'en_ejecucion' AND v_hab = 1, 1, 0) AS puede_registrar,
           v_area AS area_encargado;

    -- 3. Pesaje (carga L, indicación I, error E, EMP y conformidad guardados)
    SELECT ie.orden, ie.carga, ie.lectura AS indicacion, ie.error, ie.tolerancia AS emp, ie.resultado, ie.critico
    FROM   informe_ensayo ie
    WHERE  ie.id_informe = v_informe AND ie.tipo = 'pesaje' AND ie.eliminado_en IS NULL
    ORDER BY ie.orden, ie.id_ensayo;

    -- 4. Excentricidad (grupo = número de la carga de prueba; orden = posición)
    SELECT ie.grupo, ie.orden AS posicion, ie.carga, ie.lectura AS indicacion, ie.error, ie.tolerancia AS emp, ie.resultado, ie.critico
    FROM   informe_ensayo ie
    WHERE  ie.id_informe = v_informe AND ie.tipo = 'excentricidad' AND ie.eliminado_en IS NULL
    ORDER BY ie.grupo, ie.orden, ie.id_ensayo;

    -- 5. Encargado del área (a quien llamar)
    SELECT v_id_enc AS id_usuario, v_nom_enc AS nombre, v_car_enc AS cargo, v_tel_enc AS telefono, v_area AS area
    FROM   DUAL WHERE v_nom_enc IS NOT NULL;
END$$

DELIMITER ;

-- ############################################################
-- 7) SP_GuardarEnsayosMovil
-- ############################################################
-- ============================================================
-- SP_GuardarEnsayosMovil  (App Mobile HU-10 — Ensayos y Calibración · escritura)
-- Guarda las lecturas de pesaje y excentricidad del equipo. La app envía SOLO la carga (L) y la indicación (I); aquí se calcula el error (E = I − L),
-- el EMP (SP_EmpEnsayoMovil) y la conformidad (|E| ≤ EMP): nunca se confía en lo que la app mostró.
--   - Acceso (SP_ContextoEnsayoMovil): OS del técnico, llegada registrada (Hard Stop), equipo EN EJECUCIÓN y variables ambientales guardadas (HU-09).
--   - p_json = {"pesaje":[{"carga":10000,"indicacion":10005}], "excentricidad":[{"carga":26000,"lecturas":[26000,26004,null,…]}]}. Se puede guardar
--     incompleto (borrador); cada guardado REEMPLAZA las lecturas del técnico de ese informe.
--   - Excentricidad: posiciones por forma del plato (rectangular y circular 5, triangular 4); la lectura 1 es el centro.
--   - Error crítico = una lectura fuera del EMP. Se puede guardar igual (borrador); para FINALIZAR hay que corregirlo o aceptarlo con un motivo (3 a 300
--     caracteres, "Guardar de todas formas"): el motivo se guarda, el ensayo queda marcado con error en el informe y se avisa al encargado del área.
--   - p_finalizar = 1 exige pesaje y excentricidad completos (todas las posiciones de cada carga) y marca la etapa como finalizada; guardar de nuevo
--     sin finalizar la reabre ("Editar lecturas").
--   - Crea el informe técnico en borrador (informe_tecnico, número provisional BRR-…) si todavía no existe; lo definitivo lo asigna la generación del informe.
--   - Deja el registro en auditoria_evento.
-- Resultados: 1 mensaje; 2 (id_informe, criticos, finalizado, notificados).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_GuardarEnsayosMovil;

DELIMITER $$

CREATE PROCEDURE SP_GuardarEnsayosMovil(
    IN p_id_usuario   BIGINT,
    IN p_id_os        BIGINT,
    IN p_id_os_equipo BIGINT,
    IN p_forma        VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_json         LONGTEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_motivo       VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_finalizar    TINYINT
)
proc: BEGIN
    DECLARE v_msg      VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_eq    BIGINT;
    DECLARE v_est_eq   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_hab      TINYINT;
    DECLARE v_numero   INT;
    DECLARE v_nombre   VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_num_os   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_clase    VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_unidad   VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cap      DECIMAL(14,4);
    DECLARE v_d        DECIMAL(14,4);
    DECLARE v_e        DECIMAL(14,4);
    DECLARE v_forma    VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_motivo   VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_motivo_ant VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_pos_req  INT;
    DECLARE v_n        INT DEFAULT 0;
    DECLARE v_i        INT DEFAULT 0;
    DECLARE v_fila     BIGINT;
    DECLARE v_carga    DECIMAL(14,4);
    DECLARE v_emp      DECIMAL(14,4);
    DECLARE v_n_pes    INT DEFAULT 0;
    DECLARE v_n_ecc    INT DEFAULT 0;
    DECLARE v_incompl  INT DEFAULT 0;
    DECLARE v_invalid  INT DEFAULT 0;
    DECLARE v_criticos INT DEFAULT 0;
    DECLARE v_err_max  DECIMAL(14,4) DEFAULT NULL;
    DECLARE v_informe  BIGINT DEFAULT NULL;
    DECLARE v_final    TINYINT DEFAULT 0;
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
        DROP TEMPORARY TABLE IF EXISTS tmp_ens_filas;
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 OR IFNULL(p_id_os_equipo, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio o equipo no encontrado.' AS Mensaje; LEAVE proc;
    END IF;
    SET v_forma = LOWER(TRIM(IFNULL(p_forma, 'rectangular')));
    IF v_forma NOT IN ('rectangular', 'circular', 'triangular') THEN
        SELECT 1 AS IdTipoMensaje, 'La forma del plato no es válida.' AS Mensaje; LEAVE proc;
    END IF;
    SET v_pos_req = IF(v_forma = 'triangular', 4, 5);
    IF p_json IS NULL OR NOT JSON_VALID(p_json) OR CHAR_LENGTH(p_json) > 30000 THEN
        SELECT 1 AS IdTipoMensaje, 'Las lecturas enviadas no son válidas.' AS Mensaje; LEAVE proc;
    END IF;
    SET v_motivo = NULLIF(TRIM(IFNULL(p_motivo, '')), '');
    IF v_motivo IS NOT NULL AND (CHAR_LENGTH(v_motivo) < 3 OR CHAR_LENGTH(v_motivo) > 300) THEN
        SELECT 1 AS IdTipoMensaje, 'El motivo debe tener entre 3 y 300 caracteres.' AS Mensaje; LEAVE proc;
    END IF;

    START TRANSACTION;

    CALL SP_ContextoEnsayoMovil(p_id_usuario, p_id_os, p_id_os_equipo, v_msg, v_id_eq, v_est_eq, v_hab, v_numero, v_nombre, v_num_os, v_clase, v_unidad, v_cap, v_d, v_e);
    IF v_msg IS NULL AND (v_hab = 0 OR v_est_eq <> 'en_ejecucion') THEN
        SET v_msg = IF(v_est_eq = 'pausado', 'El equipo está pausado: reanúdalo para registrar los ensayos.',
                       IF(v_est_eq = 'completado', 'Este equipo ya está completado.', 'El servicio ya no está en curso: no se pueden registrar ensayos.'));
    END IF;
    IF v_msg IS NULL AND (v_clase IS NULL OR v_e IS NULL OR v_e <= 0) THEN
        SET v_msg = 'El equipo no tiene clase de exactitud o división e registradas: complétalas en la ficha del equipo para evaluar el ensayo.';
    END IF;
    IF v_msg IS NOT NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje; LEAVE proc;
    END IF;

    -- ── Lecturas que llegan ─────────────────────────────────────────────────────────────────────
    DROP TEMPORARY TABLE IF EXISTS tmp_ens_filas;
    CREATE TEMPORARY TABLE tmp_ens_filas (
        id INT NOT NULL AUTO_INCREMENT, tipo VARCHAR(15) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, grupo INT NULL, pos INT NULL,
        carga DECIMAL(14,4) NULL, ind DECIMAL(14,4) NULL, emp DECIMAL(14,4) NULL, err DECIMAL(14,4) NULL, res VARCHAR(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        PRIMARY KEY (id));

    INSERT INTO tmp_ens_filas (tipo, grupo, pos, carga, ind)
    SELECT 'pesaje', NULL, jt.n, jt.carga, jt.ind
    FROM   JSON_TABLE(p_json, '$.pesaje[*]' COLUMNS (
               n FOR ORDINALITY,
               carga DECIMAL(14,4) PATH '$.carga'      NULL ON EMPTY NULL ON ERROR,
               ind   DECIMAL(14,4) PATH '$.indicacion' NULL ON EMPTY NULL ON ERROR)) jt;

    INSERT INTO tmp_ens_filas (tipo, grupo, pos, carga, ind)
    SELECT 'excentricidad', jt.g, jt.pos, jt.carga, jt.ind
    FROM   JSON_TABLE(p_json, '$.excentricidad[*]' COLUMNS (
               g FOR ORDINALITY,
               carga DECIMAL(14,4) PATH '$.carga' NULL ON EMPTY NULL ON ERROR,
               NESTED PATH '$.lecturas[*]' COLUMNS (
                   pos FOR ORDINALITY,
                   ind DECIMAL(14,4) PATH '$' NULL ON EMPTY NULL ON ERROR))) jt
    WHERE  jt.pos IS NOT NULL;

    SELECT COUNT(*) INTO v_n FROM tmp_ens_filas;
    SELECT COUNT(*) INTO v_n_pes FROM tmp_ens_filas WHERE tipo = 'pesaje';
    SELECT COUNT(DISTINCT grupo) INTO v_n_ecc FROM tmp_ens_filas WHERE tipo = 'excentricidad';

    -- Límites: cantidad de filas, cargas e indicaciones razonables y posiciones según la forma del plato
    SELECT COUNT(*) INTO v_invalid
    FROM   tmp_ens_filas
    WHERE  carga IS NULL OR carga <= 0 OR carga > 100000000 OR (ind IS NOT NULL AND (ind < 0 OR ind > 100000000))
        OR (tipo = 'pesaje' AND pos > 12) OR (tipo = 'excentricidad' AND (grupo > 10 OR pos > v_pos_req));
    IF v_n = 0 OR v_n_pes > 12 OR v_n_ecc > 10 OR v_invalid > 0 THEN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_ens_filas;
        SELECT 1 AS IdTipoMensaje,
               IF(v_n = 0, 'No hay lecturas para guardar.',
                  'Revisa las lecturas: cada carga debe ser mayor que 0, las indicaciones no pueden ser negativas y no se aceptan más de 12 cargas de pesaje, 10 de excentricidad ni posiciones fuera del plato.') AS Mensaje;
        LEAVE proc;
    END IF;

    -- ── EMP, error y conformidad: aquí, una sola vez ───────────────────────────────────────────
    WHILE v_i < v_n DO
        SELECT id, carga INTO v_fila, v_carga FROM tmp_ens_filas ORDER BY id LIMIT 1 OFFSET v_i;
        CALL SP_EmpEnsayoMovil(v_clase, v_e, v_carga, v_emp);
        UPDATE tmp_ens_filas SET emp = v_emp WHERE id = v_fila;
        SET v_i = v_i + 1;
    END WHILE;
    UPDATE tmp_ens_filas
    SET    err = IF(ind IS NULL, NULL, ind - carga),
           res = IF(ind IS NULL OR emp IS NULL, NULL, IF(ABS(ind - carga) <= emp, 'conforme', 'no_conforme'));

    SELECT COUNT(*) INTO v_criticos FROM tmp_ens_filas WHERE res = 'no_conforme';
    SELECT MAX(ABS(err)) INTO v_err_max FROM tmp_ens_filas WHERE tipo = 'pesaje';

    -- Completitud (para finalizar): todo con indicación y cada carga de excentricidad con todas sus posiciones
    SELECT COUNT(*) INTO v_incompl FROM tmp_ens_filas WHERE ind IS NULL;
    IF v_n_pes = 0 OR v_n_ecc = 0 THEN SET v_incompl = v_incompl + 1; END IF;
    SELECT COUNT(*) INTO v_invalid
    FROM  (SELECT grupo, COUNT(*) AS c FROM tmp_ens_filas WHERE tipo = 'excentricidad' GROUP BY grupo HAVING COUNT(*) <> v_pos_req) x;
    SET v_incompl = v_incompl + v_invalid;

    IF p_finalizar = 1 THEN
        IF v_incompl > 0 THEN
            ROLLBACK;
            DROP TEMPORARY TABLE IF EXISTS tmp_ens_filas;
            SELECT 1 AS IdTipoMensaje, 'Completa todas las lecturas de pesaje y de excentricidad (todas las posiciones de cada carga) antes de finalizar el ensayo.' AS Mensaje;
            LEAVE proc;
        END IF;
        IF v_criticos > 0 AND v_motivo IS NULL THEN
            ROLLBACK;
            DROP TEMPORARY TABLE IF EXISTS tmp_ens_filas;
            SELECT 1 AS IdTipoMensaje, 'Hay un error crítico: corrige la lectura, repite el ensayo o usa "Guardar de todas formas" con un motivo.' AS Mensaje;
            LEAVE proc;
        END IF;
        SET v_final = 1;
    END IF;

    -- ── Informe técnico (borrador) ───────────────────────────────────────────────────────────
    SELECT it.id_informe, it.error_critico_motivo INTO v_informe, v_motivo_ant
    FROM   informe_tecnico it
    WHERE  it.id_os = p_id_os AND it.id_equipo = v_id_eq AND it.eliminado_en IS NULL
    ORDER BY it.id_informe DESC LIMIT 1
    FOR UPDATE;
    IF v_informe IS NULL THEN
        INSERT INTO informe_tecnico (numero, id_os, id_equipo, id_tecnico, estado, version, fecha_creacion, creado_por)
        VALUES (CONCAT('BRR-', FLOOR(RAND() * 1000000000)), p_id_os, v_id_eq, p_id_usuario, 'borrador', 1, NOW(), p_id_usuario);
        SET v_informe = LAST_INSERT_ID();
        UPDATE informe_tecnico SET numero = CONCAT('BRR-', LPAD(v_informe, 8, '0')) WHERE id_informe = v_informe;
    END IF;

    UPDATE informe_ensayo
    SET    eliminado_en = NOW(), eliminado_por = p_id_usuario
    WHERE  id_informe = v_informe AND tipo IN ('pesaje', 'excentricidad') AND origen = 'tecnico' AND eliminado_en IS NULL;

    INSERT INTO informe_ensayo (id_informe, tipo, orden, punto, carga, lectura, error, tolerancia, resultado, origen, creado_por, grupo, critico)
    SELECT v_informe, t.tipo, t.pos, IF(t.tipo = 'pesaje', CONCAT('Carga ', t.pos), CONCAT('Pos. ', t.pos)), t.carga, t.ind, t.err, t.emp, t.res,
           'tecnico', p_id_usuario, t.grupo, IF(t.res = 'no_conforme', 1, 0)
    FROM   tmp_ens_filas t
    ORDER BY t.id;

    UPDATE informe_tecnico
    SET    forma_plato = v_forma,
           error_critico_motivo = IF(v_criticos > 0, v_motivo, NULL),
           ensayos_finalizado_en = IF(v_final = 1, UTC_TIMESTAMP(), NULL),
           resultado_global = IF(v_criticos > 0, 'fuera', 'dentro'),
           error_maximo = v_err_max,
           modificado_por = p_id_usuario
    WHERE  id_informe = v_informe;

    -- ── Error crítico aceptado: aviso al encargado del área (y, si no hay, a los administradores) ──────────
    IF v_criticos > 0 AND v_motivo IS NOT NULL AND (v_motivo_ant IS NULL OR v_motivo_ant <> v_motivo) THEN
        CALL SP_ContactoEncargadoEnsayoMovil(p_id_os, v_area, v_id_enc, v_nom_enc, v_car_enc, v_tel_enc);
        SELECT TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))) INTO v_nombre_tec FROM usuario u WHERE u.id_usuario = p_id_usuario LIMIT 1;
        SET v_texto = LEFT(CONCAT(v_nombre_tec, ' guardó el ensayo de ', v_nombre, ' (', v_num_os, ') con ', v_criticos,
                                  IF(v_criticos = 1, ' lectura fuera', ' lecturas fuera'), ' del EMP. Motivo: ', v_motivo), 500);
        IF v_id_enc IS NOT NULL AND v_id_enc <> p_id_usuario THEN
            INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
            VALUES (v_id_enc, 5, 'Ensayo con error crítico', v_texto, 'orden_servicio', p_id_os, NOW(), p_id_usuario);
            SET v_notif = 1;
        ELSE
            INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
            SELECT u.id_usuario, 5, 'Ensayo con error crítico', v_texto, 'orden_servicio', p_id_os, NOW(), p_id_usuario
            FROM   usuario u
            WHERE  u.eliminado_en IS NULL AND u.estado = 'activo' AND u.id_usuario <> p_id_usuario AND u.rol_sistema IN ('administrador', 'admin');
            SET v_notif = ROW_COUNT();
        END IF;
    END IF;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('os_equipo', p_id_os_equipo, IF(v_final = 1, 'finalizar_ensayos', 'guardar_ensayos'), NULL, IF(v_final = 1, 'finalizado', 'borrador'),
            LEFT(CONCAT(IF(v_final = 1, 'Ensayos finalizados', 'Ensayos guardados'), ' en ', v_num_os, ': ', v_n_pes, ' cargas de pesaje, ', v_n_ecc, ' de excentricidad, ',
                        v_criticos, ' fuera del EMP', IF(v_criticos > 0 AND v_motivo IS NOT NULL, CONCAT('. Motivo: ', v_motivo), '')), 900),
            p_id_usuario, NOW(),
            JSON_OBJECT('id_informe', v_informe, 'criticos', v_criticos, 'clase', v_clase, 'e', v_e));

    COMMIT;
    DROP TEMPORARY TABLE IF EXISTS tmp_ens_filas;

    SELECT 2 AS IdTipoMensaje,
           IF(v_final = 1, 'Ensayo finalizado.', IF(v_criticos > 0 AND v_motivo IS NOT NULL, 'Ensayo guardado con error crítico: se avisó al encargado.', 'Ensayo guardado.')) AS Mensaje;
    SELECT v_informe AS id_informe, v_criticos AS criticos, v_final AS finalizado, v_notif AS notificados;
END$$

DELIMITER ;

-- ############################################################
-- 8) SP_RegistrarLlamadaEnsayoMovil
-- ############################################################
-- ============================================================
-- SP_RegistrarLlamadaEnsayoMovil  (App Mobile HU-10 — "Llamar" al encargado ante un error crítico · escritura)
-- El técnico llama al encargado del área (según la RQ) para comunicarle el error en la calibración. Se REGISTRA la llamada en el ensayo (hora y error
-- reportado) en auditoria_evento, y se devuelve a quién llamar. La llamada en sí la hace el teléfono; aquí solo queda constancia.
--   - Mismo acceso que los ensayos (SP_ContextoEnsayoMovil). p_detalle = el error reportado (hasta 300 caracteres).
-- Resultados: 1 mensaje; 2 (nombre, cargo, telefono, area). Sin encargado con teléfono responde la regla de negocio.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_RegistrarLlamadaEnsayoMovil;

DELIMITER $$

CREATE PROCEDURE SP_RegistrarLlamadaEnsayoMovil(
    IN p_id_usuario   BIGINT,
    IN p_id_os        BIGINT,
    IN p_id_os_equipo BIGINT,
    IN p_detalle      VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_msg      VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_eq    BIGINT;
    DECLARE v_est_eq   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_hab      TINYINT;
    DECLARE v_numero   INT;
    DECLARE v_nombre   VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_num_os   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_clase    VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_unidad   VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cap      DECIMAL(14,4);
    DECLARE v_d        DECIMAL(14,4);
    DECLARE v_e        DECIMAL(14,4);
    DECLARE v_area     VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_enc   BIGINT;
    DECLARE v_nom_enc  VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_car_enc  VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tel_enc  VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF CHAR_LENGTH(IFNULL(p_detalle, '')) > 300 THEN
        SELECT 1 AS IdTipoMensaje, 'El detalle puede tener hasta 300 caracteres.' AS Mensaje; LEAVE proc;
    END IF;

    CALL SP_ContextoEnsayoMovil(p_id_usuario, p_id_os, p_id_os_equipo, v_msg, v_id_eq, v_est_eq, v_hab, v_numero, v_nombre, v_num_os, v_clase, v_unidad, v_cap, v_d, v_e);
    IF v_msg IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje; LEAVE proc;
    END IF;

    CALL SP_ContactoEncargadoEnsayoMovil(p_id_os, v_area, v_id_enc, v_nom_enc, v_car_enc, v_tel_enc);
    IF v_nom_enc IS NULL OR v_tel_enc IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'No hay un encargado del área con teléfono registrado. Comunícate con Operaciones.' AS Mensaje; LEAVE proc;
    END IF;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('os_equipo', p_id_os_equipo, 'llamar_encargado_ensayo', NULL, NULL,
            LEFT(CONCAT('Llamada al encargado ', v_nom_enc, ' (', IFNULL(v_area, ''), ') por error en el ensayo de ', v_nombre, ' en ', v_num_os,
                        IF(NULLIF(TRIM(IFNULL(p_detalle, '')), '') IS NULL, '', CONCAT(': ', TRIM(p_detalle)))), 900),
            p_id_usuario, NOW(),
            JSON_OBJECT('id_os', p_id_os, 'id_encargado', v_id_enc, 'telefono', v_tel_enc));

    SELECT 2 AS IdTipoMensaje, 'Llamada registrada en el ensayo.' AS Mensaje;
    SELECT v_nom_enc AS nombre, v_car_enc AS cargo, v_tel_enc AS telefono, v_area AS area;
END$$

DELIMITER ;

-- ############################################################
-- 9) SP_ObtenerTrabajoEquipoMovil (actualizado: etapa de ensayos)
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
    DECLARE v_ens_final   DATETIME DEFAULT NULL;
    DECLARE v_ens_motivo  VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;

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
        (2, 'fotos', 'Registro fotográfico', IF(v_n_fotos > 0, 'en_curso', 'pendiente'),
            IF(v_n_fotos > 0, CONCAT(v_n_fotos, IF(v_n_fotos = 1, ' foto registrada', ' fotos registradas')), 'Fotos del equipo y del informe a mano'), 0),
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
-- A) Procedimientos con la fecha/hora de hoy (deben ser 8)
SELECT ROUTINE_NAME AS procedimiento, LAST_ALTERED AS actualizado FROM INFORMATION_SCHEMA.ROUTINES
WHERE ROUTINE_SCHEMA = DATABASE() AND ROUTINE_NAME IN ('SP_ArmarObjetivosMovil', 'SP_EmpEnsayoMovil', 'SP_ContactoEncargadoEnsayoMovil', 'SP_ContextoEnsayoMovil',
      'SP_ObtenerEnsayosMovil', 'SP_GuardarEnsayosMovil', 'SP_RegistrarLlamadaEnsayoMovil', 'SP_ObtenerTrabajoEquipoMovil') ORDER BY ROUTINE_NAME;

-- B) EMP de la maqueta (clase III, e = 20 kg): 10 000 → 10 · 20 000 → 20 · 40 000 → 20 · 80 000 → 30
CALL SP_EmpEnsayoMovil('III', 20, 10000, @a);  CALL SP_EmpEnsayoMovil('III', 20, 20000, @b);
CALL SP_EmpEnsayoMovil('III', 20, 40000, @c);  CALL SP_EmpEnsayoMovil('III', 20, 80000, @d);
SELECT @a AS emp_10000, @b AS emp_20000, @c AS emp_40000, @d AS emp_80000;

-- C) Un equipo inexistente: "Servicio no encontrado o no asignado a tu usuario."
CALL SP_ObtenerEnsayosMovil(0, 0, 0);

-- D) Datos del equipo en ejecución de la OS de prueba (clase de exactitud, alcance, d y e que usará el ensayo)
SELECT ec.id_equipo, ec.clase_exactitud, ec.alcance_maximo, ec.division_minima, ec.division_verif, ec.division_verif_igual
FROM os_equipo oe JOIN equipo_cliente ec ON ec.id_equipo = oe.id_equipo
WHERE oe.id_os = 8 AND oe.eliminado_en IS NULL;
