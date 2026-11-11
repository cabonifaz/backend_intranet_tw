-- Aplicar en la base (migración 102 + procedimientos de la HU-19 Asistente IA, sin datos de prueba). Ejecutar completo con Alt+X. NO subir al repositorio.
-- Requiere haber aplicado antes los scripts de las HU-07 a HU-13 (usa SP_ArmarObjetivosMovil) y las migraciones 24, 25, 42 y 80. Después REINICIAR la API.

-- ############################################################
-- 1) Migración 102
-- ############################################################
-- ============================================================
-- Migración 102 — Asistente IA y Procedimientos (App Mobile HU-19)
--   asistente_consulta ... cada consulta del técnico al asistente: quién, sobre qué equipo, qué preguntó (texto, voz o sugerencia), qué documentos oficiales
--                          se le dieron a la IA, qué respondió y con qué motor, cuánto tardó y si el técnico la valoró (¿te sirvió la respuesta?).
--                          Es también la bitácora de uso del asistente y la base del límite de consultas (10 por minuto y 200 por día por técnico).
--     estado: procesando | respondida | sin_respuesta (la IA no lo encontró en los documentos) | sin_fuentes (el equipo no tiene documentos oficiales) | error_ia
--     creado_en / valorada_en se guardan en UTC (como las evidencias); los SP los devuelven en hora de Lima.
--   asistente_guardado ... copia de una respuesta o de un fragmento citado que el técnico guardó para leer sin conexión (soft delete).
--                          n = 0 para una respuesta; n = número de la fuente para un fragmento.
--   tabla_maestra SUGERENCIA_ASISTENTE ... catálogo editable de "Sugerencias para este equipo" (String1 = texto, String2 = código, String3 = palabra clave
--                          opcional: solo se sugiere a equipos cuyo suministro (tipo, subtipo o descripción) la contenga; vacío = a todos; Num1 = orden).
--   No borra ni cambia datos existentes. IDEMPOTENTE.
-- ============================================================

CREATE TABLE IF NOT EXISTS asistente_consulta (
    id_consulta      BIGINT          NOT NULL AUTO_INCREMENT,
    id_usuario       BIGINT          NOT NULL,
    id_os            BIGINT          NULL,
    id_os_equipo     BIGINT          NULL,
    id_equipo        BIGINT          NULL,
    pregunta         VARCHAR(500)    NOT NULL,
    origen           VARCHAR(12)     NOT NULL DEFAULT 'texto',
    estado           VARCHAR(20)     NOT NULL DEFAULT 'procesando',
    documentos_json  JSON            NULL,
    respuesta_json   JSON            NULL,
    motor_ia         VARCHAR(60)     NULL,
    duracion_ms      INT             NULL,
    util             TINYINT(1)      NULL,
    valorada_en      DATETIME        NULL,
    creado_en        DATETIME        NOT NULL,
    PRIMARY KEY (id_consulta),
    KEY ix_asistente_consulta_usuario (id_usuario, creado_en),
    KEY ix_asistente_consulta_equipo  (id_os_equipo, id_usuario)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS asistente_guardado (
    id_guardado      BIGINT          NOT NULL AUTO_INCREMENT,
    id_usuario       BIGINT          NOT NULL,
    id_consulta      BIGINT          NOT NULL,
    tipo             VARCHAR(12)     NOT NULL,
    n                INT             NOT NULL DEFAULT 0,
    titulo           VARCHAR(200)    NOT NULL,
    subtitulo        VARCHAR(300)    NULL,
    contenido_json   JSON            NOT NULL,
    tamano_bytes     INT             NOT NULL DEFAULT 0,
    creado_en        DATETIME        NOT NULL,
    eliminado_en     DATETIME        NULL,
    eliminado_por    BIGINT          NULL,
    PRIMARY KEY (id_guardado),
    KEY ix_asistente_guardado_usuario  (id_usuario, eliminado_en, creado_en),
    KEY ix_asistente_guardado_consulta (id_consulta, id_usuario, tipo, n)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ── Catálogo SUGERENCIA_ASISTENTE (referencia, editable desde el maestro; no son datos de prueba) ──────────────
SET @id_sug := (SELECT MAX(IdMaestro) FROM tabla_maestra WHERE Descripcion = 'SUGERENCIA_ASISTENTE');
SET @id_sug := IFNULL(@id_sug, (SELECT MAX(IdMaestro) + 1 FROM tabla_maestra));

INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2)
SELECT 1, @id_sug, 'SUGERENCIA_ASISTENTE', v.orden, v.texto, v.codigo
FROM (
    SELECT 1 AS orden, 'Ajuste de excentricidad'        AS texto, 'AJUSTE_EXCENTRICIDAD'   AS codigo
    UNION ALL SELECT 2, 'Calibración con pesas',         'CALIBRACION_PESAS'
    UNION ALL SELECT 3, 'Verificación de linealidad',    'VERIFICACION_LINEALIDAD'
    UNION ALL SELECT 4, 'Errores del indicador',         'ERRORES_INDICADOR'
    UNION ALL SELECT 5, 'Reemplazo de celda de carga',   'REEMPLAZO_CELDA'
    UNION ALL SELECT 6, 'Humedad en caja de conexiones', 'HUMEDAD_CAJA_CONEXIONES'
    UNION ALL SELECT 7, 'Mantenimiento preventivo',      'MANTENIMIENTO_PREVENTIVO'
) v
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra t WHERE t.Descripcion = 'SUGERENCIA_ASISTENTE' AND t.IdEmpresa = 1 AND t.String2 = v.codigo);

-- ── Verificación ─────────────────────────────────────────────────────────────
SELECT 'Migración 102 (debe ser 9)' AS verificacion,
       (SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME IN ('asistente_consulta', 'asistente_guardado'))
     + (SELECT COUNT(*) FROM tabla_maestra WHERE Descripcion = 'SUGERENCIA_ASISTENTE' AND IdEmpresa = 1) AS valor;

-- ############################################################
-- 2) SP_ContextoAsistenteMovil
-- ############################################################
-- ============================================================
-- SP_ContextoAsistenteMovil  (App Mobile HU-19 — apoyo, no es un endpoint)
-- Valida y arma, UNA sola vez, el equipo que el técnico usa como contexto del Asistente IA. Lo usan SP_InicioAsistenteMovil, SP_DocumentosAsistenteMovil
-- y SP_RegistrarConsultaAsistenteMovil.
--   - La OS debe ser del técnico (principal o personal asignado), igual que SP_ContextoEquipoMovil.
--   - NO exige el Hard Stop de llegada ni que el equipo esté iniciado: consultar un manual no es registrar trabajo. Sí debe ser un objetivo de la OS
--     (SP_ArmarObjetivosMovil) y la OS no puede estar finalizada ni anulada.
--   p_mensaje trae el texto para el técnico cuando algo impide continuar (lo demás queda NULL). Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ContextoAsistenteMovil;

DELIMITER $$

CREATE PROCEDURE SP_ContextoAsistenteMovil(
    IN  p_id_usuario     BIGINT,
    IN  p_id_os          BIGINT,
    IN  p_id_os_equipo   BIGINT,
    OUT p_mensaje        VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    OUT p_id_equipo      BIGINT,
    OUT p_id_suministro  BIGINT,
    OUT p_estado_equipo  VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    OUT p_numero         INT,
    OUT p_nombre_equipo  VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    OUT p_numero_os      VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    OUT p_servicio       VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    OUT p_marca          VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    OUT p_modelo         VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    OUT p_codigo_cliente VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    OUT p_num_serie      VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
BEGIN
    DECLARE v_estado_os   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_salida_utc  DATETIME;
    DECLARE v_llegada_utc DATETIME;
    DECLARE v_hab         TINYINT;
    DECLARE v_motivo      VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    SET p_mensaje = NULL, p_id_equipo = NULL, p_id_suministro = NULL, p_estado_equipo = NULL, p_numero = NULL, p_nombre_equipo = NULL, p_numero_os = NULL,
        p_servicio = NULL, p_marca = NULL, p_modelo = NULL, p_codigo_cliente = NULL, p_num_serie = NULL;

    SELECT os.estado, os.numero INTO v_estado_os, p_numero_os
    FROM   orden_servicio os
    WHERE  os.id_os = p_id_os AND os.eliminado_en IS NULL
      AND  (os.id_tecnico_principal = p_id_usuario
            OR EXISTS (SELECT 1 FROM os_personal op
                       WHERE op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL));
    IF v_estado_os IS NULL THEN
        SET p_mensaje = 'Servicio no encontrado o no asignado a tu usuario.';
    ELSEIF v_estado_os IN ('finalizada', 'anulada') THEN
        SET p_mensaje = 'Este servicio ya no está activo.';
    ELSE
        -- Solo se aprovecha la tabla de objetivos (equipo, número, nombre): el Hard Stop (llegada) no se exige
        CALL SP_ArmarObjetivosMovil(p_id_os, v_estado_os, v_salida_utc, v_llegada_utc, v_hab, v_motivo);
        SELECT t.id_equipo, t.estado, t.numero, t.nombre, COALESCE(t.tipo_corto, t.tipo_intervencion), t.marca, t.modelo, t.codigo_cliente, t.num_serie
        INTO   p_id_equipo, p_estado_equipo, p_numero, p_nombre_equipo, p_servicio, p_marca, p_modelo, p_codigo_cliente, p_num_serie
        FROM   tmp_obj_mov t WHERE t.id_os_equipo = p_id_os_equipo;
        IF p_id_equipo IS NULL THEN
            SET p_mensaje = 'El equipo no forma parte de los objetivos de este servicio.';
        ELSE
            SELECT ec.id_suministro INTO p_id_suministro FROM equipo_cliente ec WHERE ec.id_equipo = p_id_equipo LIMIT 1;
        END IF;
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
    END IF;
END$$

DELIMITER ;

-- ############################################################
-- 3) SP_ArmarDocumentosAsistenteMovil
-- ############################################################
-- ============================================================
-- SP_ArmarDocumentosAsistenteMovil  (App Mobile HU-19 — apoyo, no es un endpoint)
-- Arma, UNA sola vez, la lista de documentos OFICIALES que el Asistente IA puede consultar para un equipo, en la tabla temporal `tmp_doc_asist`.
-- Lo usan SP_InicioAsistenteMovil, SP_DocumentosAsistenteMovil y SP_EquiposAsistenteMovil; quien lo llame debe terminar con DROP TEMPORARY TABLE IF EXISTS tmp_doc_asist.
--   1. Manual del equipo = suministros.url_manual_pdf del suministro del equipo (equipo_cliente.id_suministro). Siempre aparece si tiene URL; `disponible` = 1
--      solo si es https (el back además la valida con guardas anti-SSRF al descargarla).
--   2. Procedimientos del servicio = los que tienen asociados los conceptos del servicio (os_concepto → suministros de clase servicio:
--      id_primer_procedimiento / id_segundo_procedimiento) aplicados a ese equipo (o generales de la OS, sin filas en os_concepto_equipo).
--      Se resuelven contra procedimiento_metrologico por código (el valor guardado puede venir como "código - título" o como el id) y solo entran los
--      ACTIVOS con PDF aprobado cargado (url_pdf_aprobado = ruta interna del almacenamiento). Si el código tiene varias versiones, la más reciente.
--   Orden: manual primero, luego procedimientos (primer procedimiento antes que el segundo). El back usa los 3 primeros disponibles.
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ArmarDocumentosAsistenteMovil;

DELIMITER $$

CREATE PROCEDURE SP_ArmarDocumentosAsistenteMovil(
    IN p_id_os         BIGINT,
    IN p_id_os_equipo  BIGINT,
    IN p_id_suministro BIGINT
)
BEGIN
    DROP TEMPORARY TABLE IF EXISTS tmp_doc_asist;
    CREATE TEMPORARY TABLE tmp_doc_asist (
        orden        INT NOT NULL AUTO_INCREMENT,
        id_documento VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL,
        tipo         VARCHAR(15)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL,
        titulo       VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL,
        version      VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        entidad      VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        actualizado  DATE NULL,
        ubicacion    VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        disponible   TINYINT NOT NULL DEFAULT 1,
        PRIMARY KEY (orden),
        UNIQUE KEY ux_tmp_doc_asist (id_documento)
    );

    -- 1. Manual del suministro del equipo
    INSERT INTO tmp_doc_asist (id_documento, tipo, titulo, version, entidad, actualizado, ubicacion, disponible)
    SELECT CONCAT('M-', su.id_suministro), 'manual',
           LEFT(CONCAT('Manual ', COALESCE(NULLIF(TRIM(CONCAT_WS(' ', su.marca, su.modelo)), ''), NULLIF(TRIM(su.descripcion), ''), su.codigo)), 300),
           NULL, NULLIF(TRIM(su.marca), ''), DATE(COALESCE(su.modificado_en, su.creado_en)), TRIM(su.url_manual_pdf),
           IF(LOWER(TRIM(su.url_manual_pdf)) LIKE 'https://%', 1, 0)
    FROM   suministros su
    WHERE  su.id_suministro = p_id_suministro AND su.eliminado_en IS NULL AND NULLIF(TRIM(su.url_manual_pdf), '') IS NOT NULL;

    -- 2. PDF aprobado de los procedimientos del servicio (ranking = la versión más reciente de cada código)
    INSERT IGNORE INTO tmp_doc_asist (id_documento, tipo, titulo, version, entidad, actualizado, ubicacion, disponible)
    SELECT CONCAT('P-', x.id_procedimiento), 'procedimiento', LEFT(CONCAT(x.codigo, ' · ', x.descripcion), 300), CONCAT('v', x.version),
           NULLIF(TRIM(x.autor_norma), ''), DATE(COALESCE(x.pdf_subido_en, x.FchMod, x.FchCre)), x.url_pdf_aprobado, 1
    FROM (
        SELECT pm.id_procedimiento, pm.codigo, pm.descripcion, pm.version, pm.autor_norma, pm.pdf_subido_en, pm.FchMod, pm.FchCre, pm.url_pdf_aprobado, r.ord,
               ROW_NUMBER() OVER (PARTITION BY r.ref ORDER BY r.ord, pm.anio DESC, pm.version DESC, pm.id_procedimiento DESC) AS rn
        FROM (
            SELECT TRIM(su2.id_primer_procedimiento) AS ref, 1 AS ord
            FROM   os_concepto oc
            JOIN   suministros su2 ON su2.id_suministro = oc.id_suministro AND su2.eliminado_en IS NULL
            WHERE  oc.id_os = p_id_os AND oc.eliminado_en IS NULL AND NULLIF(TRIM(su2.id_primer_procedimiento), '') IS NOT NULL
              AND  (EXISTS (SELECT 1 FROM os_concepto_equipo oce WHERE oce.id_os_concepto = oc.id AND oce.id_os_equipo = p_id_os_equipo AND oce.eliminado_en IS NULL)
                    OR NOT EXISTS (SELECT 1 FROM os_concepto_equipo z WHERE z.id_os_concepto = oc.id AND z.eliminado_en IS NULL))
            UNION
            SELECT TRIM(su3.id_segundo_procedimiento), 2
            FROM   os_concepto oc
            JOIN   suministros su3 ON su3.id_suministro = oc.id_suministro AND su3.eliminado_en IS NULL
            WHERE  oc.id_os = p_id_os AND oc.eliminado_en IS NULL AND NULLIF(TRIM(su3.id_segundo_procedimiento), '') IS NOT NULL
              AND  (EXISTS (SELECT 1 FROM os_concepto_equipo oce WHERE oce.id_os_concepto = oc.id AND oce.id_os_equipo = p_id_os_equipo AND oce.eliminado_en IS NULL)
                    OR NOT EXISTS (SELECT 1 FROM os_concepto_equipo z WHERE z.id_os_concepto = oc.id AND z.eliminado_en IS NULL))
        ) r
        JOIN procedimiento_metrologico pm
          ON pm.SoftDelete = 0 AND pm.estado = 'activo' AND NULLIF(TRIM(pm.url_pdf_aprobado), '') IS NOT NULL
         AND (pm.codigo = TRIM(SUBSTRING_INDEX(r.ref, ' - ', 1)) OR CAST(pm.id_procedimiento AS CHAR) COLLATE utf8mb4_0900_ai_ci = r.ref)
    ) x
    WHERE x.rn = 1
    ORDER BY x.ord, x.id_procedimiento;
END$$

DELIMITER ;

-- ############################################################
-- 4) SP_DocumentosAsistenteMovil
-- ############################################################
-- ============================================================
-- SP_DocumentosAsistenteMovil  (App Mobile HU-19 — contexto y documentos oficiales del equipo · lectura)
-- Lo que necesita el back para consultar al Asistente IA: el equipo en contexto (SP_ContextoAsistenteMovil) y los documentos oficiales que se le dan a la
-- IA (SP_ArmarDocumentosAsistenteMovil: manual del suministro y PDF aprobado de los procedimientos del servicio).
-- Resultados: 1 mensaje · 2 contexto (1 fila) · 3 documentos (0 a N filas: id_documento, tipo, titulo, version, entidad, actualizado, ubicacion, disponible).
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_DocumentosAsistenteMovil;

DELIMITER $$

CREATE PROCEDURE SP_DocumentosAsistenteMovil(
    IN p_id_usuario   BIGINT,
    IN p_id_os        BIGINT,
    IN p_id_os_equipo BIGINT
)
proc: BEGIN
    DECLARE v_msg       VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_eq     BIGINT;
    DECLARE v_id_sum    BIGINT;
    DECLARE v_estado    VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_numero    INT;
    DECLARE v_nombre    VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_num_os    VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_servicio  VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_marca     VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_modelo    VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cod_cli   VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_serie     VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tipo_eq   VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
        DROP TEMPORARY TABLE IF EXISTS tmp_doc_asist;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 OR IFNULL(p_id_os_equipo, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio o equipo no encontrado.' AS Mensaje; LEAVE proc;
    END IF;

    CALL SP_ContextoAsistenteMovil(p_id_usuario, p_id_os, p_id_os_equipo, v_msg, v_id_eq, v_id_sum, v_estado, v_numero, v_nombre, v_num_os, v_servicio,
                                   v_marca, v_modelo, v_cod_cli, v_serie);
    IF v_msg IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje; LEAVE proc;
    END IF;

    SELECT NULLIF(TRIM(su.descripcion), '') INTO v_tipo_eq FROM suministros su WHERE su.id_suministro = v_id_sum LIMIT 1;
    CALL SP_ArmarDocumentosAsistenteMovil(p_id_os, p_id_os_equipo, v_id_sum);

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT p_id_os AS id_os, v_num_os AS numero_os, p_id_os_equipo AS id_os_equipo, v_nombre AS nombre, v_numero AS numero, v_marca AS marca, v_modelo AS modelo,
           v_cod_cli AS codigo_cliente, v_serie AS numero_serie, v_servicio AS servicio_sigla, v_estado AS estado, v_tipo_eq AS tipo_equipo;

    SELECT d.id_documento, d.tipo, d.titulo, d.version, d.entidad, d.actualizado, d.ubicacion, d.disponible
    FROM   tmp_doc_asist d ORDER BY d.orden;

    DROP TEMPORARY TABLE IF EXISTS tmp_doc_asist;
END$$

DELIMITER ;

-- ############################################################
-- 5) SP_InicioAsistenteMovil
-- ############################################################
-- ============================================================
-- SP_InicioAsistenteMovil  (App Mobile HU-19 — inicio del Asistente IA · lectura)
-- La pantalla de inicio: el equipo en contexto, los documentos oficiales que consultará el asistente, las sugerencias y las consultas recientes.
--   - Sin p_id_os ni p_id_os_equipo: el equipo EN EJECUCIÓN del técnico (trabaja uno a la vez); si no hay ninguno el contexto va vacío y la app
--     ofrece "Cambiar". Con ambos: ese equipo (SP_ContextoAsistenteMovil: OS del técnico, objetivo de la OS, OS activa). Con uno solo: error.
--   - Fuentes = SP_ArmarDocumentosAsistenteMovil (manual del suministro y PDF aprobado de los procedimientos del servicio).
--   - Sugerencias (máx. 6) = hasta 2 procedimientos del equipo ("Procedimiento PC-001") y el catálogo SUGERENCIA_ASISTENTE hasta completar; una sugerencia con
--     palabra clave (String3) solo aplica a equipos cuyo suministro (tipo, subtipo o descripción) la contenga.
--   - Recientes (máx. 5) = las últimas consultas con respuesta del técnico, del equipo en contexto o, sin contexto, de cualquiera. Horas de Lima.
-- Resultados: 1 mensaje · 2 contexto (0 o 1 fila) · 3 fuentes · 4 sugerencias · 5 recientes.
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_InicioAsistenteMovil;

DELIMITER $$

CREATE PROCEDURE SP_InicioAsistenteMovil(
    IN p_id_usuario   BIGINT,
    IN p_id_os        BIGINT,
    IN p_id_os_equipo BIGINT
)
proc: BEGIN
    DECLARE v_msg       VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_os     BIGINT DEFAULT NULL;
    DECLARE v_id_oe     BIGINT DEFAULT NULL;
    DECLARE v_id_eq     BIGINT;
    DECLARE v_id_sum    BIGINT;
    DECLARE v_estado    VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_numero    INT;
    DECLARE v_nombre    VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_num_os    VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_servicio  VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_marca     VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_modelo    VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cod_cli   VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_serie     VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_clave_su  VARCHAR(400) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT '';

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
        DROP TEMPORARY TABLE IF EXISTS tmp_doc_asist;
        DROP TEMPORARY TABLE IF EXISTS tmp_sug_asist;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no válido.' AS Mensaje; LEAVE proc;
    END IF;
    IF IFNULL(p_id_os, 0) > 0 AND IFNULL(p_id_os_equipo, 0) > 0 THEN
        SET v_id_os = p_id_os, v_id_oe = p_id_os_equipo;
    ELSEIF IFNULL(p_id_os, 0) > 0 OR IFNULL(p_id_os_equipo, 0) > 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio o equipo no encontrado.' AS Mensaje; LEAVE proc;
    ELSE
        -- El equipo en ejecución del técnico (uno a la vez)
        SELECT oe.id_os, oe.id INTO v_id_os, v_id_oe
        FROM   os_equipo oe
        JOIN   orden_servicio os ON os.id_os = oe.id_os AND os.eliminado_en IS NULL AND os.estado NOT IN ('finalizada', 'anulada')
        WHERE  oe.eliminado_en IS NULL AND oe.estado_ejecucion = 'en_proceso' AND oe.pausado = 0
          AND  (os.id_tecnico_principal = p_id_usuario
                OR EXISTS (SELECT 1 FROM os_personal op WHERE op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL))
        ORDER BY oe.iniciado_utc DESC, oe.id DESC LIMIT 1;
    END IF;

    DROP TEMPORARY TABLE IF EXISTS tmp_sug_asist;
    CREATE TEMPORARY TABLE tmp_sug_asist (orden INT NOT NULL AUTO_INCREMENT, texto VARCHAR(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL, PRIMARY KEY (orden));

    IF v_id_oe IS NOT NULL THEN
        CALL SP_ContextoAsistenteMovil(p_id_usuario, v_id_os, v_id_oe, v_msg, v_id_eq, v_id_sum, v_estado, v_numero, v_nombre, v_num_os, v_servicio,
                                       v_marca, v_modelo, v_cod_cli, v_serie);
        IF v_msg IS NOT NULL THEN
            DROP TEMPORARY TABLE IF EXISTS tmp_sug_asist;
            SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje; LEAVE proc;
        END IF;
        SELECT LOWER(CONCAT_WS(' ', su.tipo, su.subtipo, su.descripcion)) INTO v_clave_su FROM suministros su WHERE su.id_suministro = v_id_sum LIMIT 1;
        SET v_clave_su = IFNULL(v_clave_su, '');
        CALL SP_ArmarDocumentosAsistenteMovil(v_id_os, v_id_oe, v_id_sum);

        -- Sugerencias: primero los procedimientos del equipo (máx. 2)
        INSERT INTO tmp_sug_asist (texto)
        SELECT LEFT(CONCAT('Procedimiento ', TRIM(SUBSTRING_INDEX(d.titulo, ' · ', 1))), 120) FROM tmp_doc_asist d WHERE d.tipo = 'procedimiento' ORDER BY d.orden LIMIT 2;
    END IF;

    INSERT INTO tmp_sug_asist (texto)
    SELECT LEFT(t.String1, 120)
    FROM   tabla_maestra t
    WHERE  t.Descripcion = 'SUGERENCIA_ASISTENTE' AND t.IdEmpresa = 1 AND NULLIF(TRIM(t.String1), '') IS NOT NULL
      AND  (NULLIF(TRIM(t.String3), '') IS NULL OR LOCATE(LOWER(TRIM(t.String3)), v_clave_su) > 0)
    ORDER BY t.Num1, t.IdTablaMaestra
    LIMIT 6;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Contexto (vacío si el técnico no tiene un equipo en trabajo)
    IF v_id_oe IS NOT NULL THEN
        SELECT v_id_os AS id_os, v_num_os AS numero_os, v_id_oe AS id_os_equipo, v_nombre AS nombre, v_numero AS numero, v_marca AS marca, v_modelo AS modelo,
               v_cod_cli AS codigo_cliente, v_serie AS numero_serie, v_servicio AS servicio_sigla, v_estado AS estado;
    ELSE
        SELECT NULL AS id_os, NULL AS numero_os, NULL AS id_os_equipo, NULL AS nombre, NULL AS numero, NULL AS marca, NULL AS modelo,
               NULL AS codigo_cliente, NULL AS numero_serie, NULL AS servicio_sigla, NULL AS estado FROM DUAL WHERE 1 = 0;
    END IF;

    -- 3. Fuentes
    IF v_id_oe IS NOT NULL THEN
        SELECT d.id_documento, d.tipo, d.titulo, d.version, d.entidad, DATE_FORMAT(d.actualizado, '%Y-%m-%d') AS actualizado, d.disponible
        FROM   tmp_doc_asist d ORDER BY d.orden;
    ELSE
        SELECT NULL AS id_documento, NULL AS tipo, NULL AS titulo, NULL AS version, NULL AS entidad, NULL AS actualizado, NULL AS disponible FROM DUAL WHERE 1 = 0;
    END IF;

    -- 4. Sugerencias (máx. 6: los procedimientos y el catálogo hasta completar)
    SELECT s.texto FROM tmp_sug_asist s ORDER BY s.orden LIMIT 6;

    -- 5. Consultas recientes con respuesta
    SELECT c.id_consulta, c.pregunta,
           NULLIF(CONCAT(IFNULL(NULLIF(JSON_UNQUOTE(JSON_EXTRACT(c.respuesta_json, '$.fuentes[0].documento')), 'null'), ''),
                         IF(JSON_UNQUOTE(JSON_EXTRACT(c.respuesta_json, '$.fuentes[0].seccion')) REGEXP '^[0-9]',
                            CONCAT(' §', SUBSTRING_INDEX(JSON_UNQUOTE(JSON_EXTRACT(c.respuesta_json, '$.fuentes[0].seccion')), ' ', 1)), '')), '') AS fuente,
           CONVERT_TZ(c.creado_en, '+00:00', '-05:00') AS creado_en
    FROM   asistente_consulta c
    WHERE  c.id_usuario = p_id_usuario AND c.respuesta_json IS NOT NULL AND c.estado IN ('respondida', 'sin_respuesta', 'sin_fuentes')
      AND  (v_id_oe IS NULL OR c.id_os_equipo = v_id_oe)
    ORDER BY c.creado_en DESC, c.id_consulta DESC LIMIT 5;

    DROP TEMPORARY TABLE IF EXISTS tmp_doc_asist;
    DROP TEMPORARY TABLE IF EXISTS tmp_sug_asist;
END$$

DELIMITER ;

-- ############################################################
-- 6) SP_EquiposAsistenteMovil
-- ############################################################
-- ============================================================
-- SP_EquiposAsistenteMovil  (App Mobile HU-19 — "Cambiar" el equipo del contexto · lectura)
-- Los equipos (objetivos, SP_ArmarObjetivosMovil) de las OS asignadas al técnico que siguen activas (no finalizadas, anuladas ni reprogramadas), con cuántos
-- documentos oficiales consultables tiene cada uno (SP_ArmarDocumentosAsistenteMovil, solo los disponibles). El equipo en ejecución va primero, luego los pausados,
-- por iniciar, observados y completados. Máx. 15 OS y 50 equipos.
-- Resultados: 1 mensaje · 2 equipos (id_os, numero_os, id_os_equipo, nombre, numero, marca, modelo, codigo_cliente, estado, en_trabajo, fuentes_disponibles).
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_EquiposAsistenteMovil;

DELIMITER $$

CREATE PROCEDURE SP_EquiposAsistenteMovil(
    IN p_id_usuario BIGINT
)
proc: BEGIN
    DECLARE v_i         INT DEFAULT 1;
    DECLARE v_n         INT DEFAULT 0;
    DECLARE v_os        BIGINT;
    DECLARE v_num       VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_oe        BIGINT;
    DECLARE v_sum       BIGINT;
    DECLARE v_cuenta    INT;
    DECLARE v_estado_os VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_salida    DATETIME;
    DECLARE v_llegada   DATETIME;
    DECLARE v_hab       TINYINT;
    DECLARE v_motivo    VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
        DROP TEMPORARY TABLE IF EXISTS tmp_doc_asist;
        DROP TEMPORARY TABLE IF EXISTS tmp_os_asist;
        DROP TEMPORARY TABLE IF EXISTS tmp_eq_asist;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no válido.' AS Mensaje; LEAVE proc;
    END IF;

    DROP TEMPORARY TABLE IF EXISTS tmp_os_asist;
    CREATE TEMPORARY TABLE tmp_os_asist (
        n INT NOT NULL AUTO_INCREMENT, id_os BIGINT NOT NULL, numero_os VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL, PRIMARY KEY (n));
    INSERT INTO tmp_os_asist (id_os, numero_os)
    SELECT os.id_os, os.numero
    FROM   orden_servicio os
    WHERE  os.eliminado_en IS NULL AND os.estado NOT IN ('finalizada', 'anulada', 'reprogramada')
      AND  (os.id_tecnico_principal = p_id_usuario
            OR EXISTS (SELECT 1 FROM os_personal op WHERE op.id_os = os.id_os AND op.id_usuario = p_id_usuario AND op.eliminado_en IS NULL))
    ORDER BY os.id_os DESC LIMIT 15;

    DROP TEMPORARY TABLE IF EXISTS tmp_eq_asist;
    CREATE TEMPORARY TABLE tmp_eq_asist (
        n INT NOT NULL AUTO_INCREMENT, id_os BIGINT NOT NULL, numero_os VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, id_os_equipo BIGINT NOT NULL,
        id_suministro BIGINT NULL, nombre VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, numero INT,
        marca VARCHAR(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, modelo VARCHAR(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        codigo_cliente VARCHAR(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, estado VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        prioridad INT NOT NULL DEFAULT 4, fuentes INT NOT NULL DEFAULT 0, PRIMARY KEY (n));

    -- Los objetivos de cada OS salen de SP_ArmarObjetivosMovil (una sola regla de qué es un equipo del servicio)
    SELECT COUNT(*) INTO v_n FROM tmp_os_asist;
    SET v_i = 1;
    WHILE v_i <= v_n DO
        SELECT o.id_os, o.numero_os INTO v_os, v_num FROM tmp_os_asist o WHERE o.n = v_i;
        CALL SP_ArmarObjetivosMovil(v_os, v_estado_os, v_salida, v_llegada, v_hab, v_motivo);
        INSERT INTO tmp_eq_asist (id_os, numero_os, id_os_equipo, id_suministro, nombre, numero, marca, modelo, codigo_cliente, estado, prioridad)
        SELECT v_os, v_num, t.id_os_equipo, ec.id_suministro, t.nombre, t.numero, t.marca, t.modelo, t.codigo_cliente, t.estado,
               CASE t.estado WHEN 'en_ejecucion' THEN 0 WHEN 'pausado' THEN 1 WHEN 'por_iniciar' THEN 2 WHEN 'observado' THEN 3 ELSE 4 END
        FROM   tmp_obj_mov t
        LEFT JOIN equipo_cliente ec ON ec.id_equipo = t.id_equipo;
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
        SET v_i = v_i + 1;
    END WHILE;

    -- Documentos oficiales disponibles de cada equipo (se calculan para los primeros 200)
    DELETE e FROM tmp_eq_asist e WHERE e.n > 200;
    SELECT COUNT(*) INTO v_n FROM tmp_eq_asist;
    SET v_i = 1;
    WHILE v_i <= v_n DO
        SELECT e.id_os, e.id_os_equipo, e.id_suministro INTO v_os, v_oe, v_sum FROM tmp_eq_asist e WHERE e.n = v_i;
        CALL SP_ArmarDocumentosAsistenteMovil(v_os, v_oe, v_sum);
        SELECT COUNT(*) INTO v_cuenta FROM tmp_doc_asist d WHERE d.disponible = 1;
        UPDATE tmp_eq_asist SET fuentes = v_cuenta WHERE n = v_i;
        SET v_i = v_i + 1;
    END WHILE;
    DROP TEMPORARY TABLE IF EXISTS tmp_doc_asist;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT e.id_os, e.numero_os, e.id_os_equipo, e.nombre, e.numero, e.marca, e.modelo, e.codigo_cliente, e.estado,
           IF(e.estado = 'en_ejecucion', 1, 0) AS en_trabajo, e.fuentes AS fuentes_disponibles
    FROM   tmp_eq_asist e
    ORDER BY e.prioridad, e.id_os DESC, e.numero, e.id_os_equipo
    LIMIT 50;

    DROP TEMPORARY TABLE IF EXISTS tmp_eq_asist;
    DROP TEMPORARY TABLE IF EXISTS tmp_os_asist;
END$$

DELIMITER ;

-- ############################################################
-- 7) SP_RegistrarConsultaAsistenteMovil
-- ############################################################
-- ============================================================
-- SP_RegistrarConsultaAsistenteMovil  (App Mobile HU-19 — consulta al Asistente IA · escritura en dos fases)
-- La consulta se registra ANTES de llamar a la IA (para que el límite de uso se cuente aunque la IA falle) y se completa al terminar:
--   Fase 1 (p_id_consulta NULL): valida la pregunta (3 a 500 caracteres) y el origen (texto | voz | sugerencia), el equipo en contexto
--     (SP_ContextoAsistenteMovil: OS del técnico) y el LÍMITE DE USO: máx. 10 consultas por minuto y 200 por 24 horas por técnico (las consultas en
--     proceso, respondidas y con error cuentan). El técnico se bloquea (FOR UPDATE) para que dos consultas simultáneas no se salten el límite.
--     Inserta la consulta en estado 'procesando'.
--   Fase 2 (p_id_consulta con valor): completa SU consulta (del mismo técnico, aún 'procesando') con el resultado: p_estado = respondida | sin_respuesta
--     (la IA no lo encontró en los documentos) | sin_fuentes (el equipo no tiene documentos oficiales) | error_ia, los documentos usados, la respuesta
--     (JSON), el motor de IA y la duración. El texto del error de la IA NO se guarda como respuesta.
-- Resultados: 1 mensaje · 2 (id_consulta, creado_en en hora de Lima).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_RegistrarConsultaAsistenteMovil;

DELIMITER $$

CREATE PROCEDURE SP_RegistrarConsultaAsistenteMovil(
    IN p_id_usuario      BIGINT,
    IN p_id_consulta     BIGINT,
    IN p_id_os           BIGINT,
    IN p_id_os_equipo    BIGINT,
    IN p_pregunta        VARCHAR(600) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_origen          VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_estado          VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_documentos_json LONGTEXT     CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_respuesta_json  LONGTEXT     CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_motor           VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_duracion_ms     INT
)
proc: BEGIN
    DECLARE v_msg      VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_eq    BIGINT;
    DECLARE v_id_sum   BIGINT;
    DECLARE v_estado   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_numero   INT;
    DECLARE v_nombre   VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_num_os   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_servicio VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_marca    VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_modelo   VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cod_cli  VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_serie    VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_pregunta VARCHAR(600) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_origen   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_usuario  BIGINT DEFAULT NULL;
    DECLARE v_minuto   INT DEFAULT 0;
    DECLARE v_dia      INT DEFAULT 0;
    DECLARE v_id       BIGINT DEFAULT NULL;
    DECLARE v_actual   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_creado   DATETIME;
    DECLARE v_docs     LONGTEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_resp     LONGTEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no válido.' AS Mensaje; LEAVE proc;
    END IF;

    -- ══════════ Fase 2: completar la consulta ══════════
    IF p_id_consulta IS NOT NULL THEN
        IF p_estado IS NULL OR p_estado NOT IN ('respondida', 'sin_respuesta', 'sin_fuentes', 'error_ia') THEN
            SELECT 1 AS IdTipoMensaje, 'Estado de la consulta no válido.' AS Mensaje; LEAVE proc;
        END IF;
        SET v_docs = IF(p_documentos_json IS NOT NULL AND JSON_VALID(p_documentos_json) AND CHAR_LENGTH(p_documentos_json) <= 8000, p_documentos_json, NULL);
        SET v_resp = IF(p_estado <> 'error_ia' AND p_respuesta_json IS NOT NULL AND JSON_VALID(p_respuesta_json) AND CHAR_LENGTH(p_respuesta_json) <= 60000, p_respuesta_json, NULL);

        START TRANSACTION;
        SELECT c.id_consulta, c.estado, c.creado_en INTO v_id, v_actual, v_creado
        FROM   asistente_consulta c
        WHERE  c.id_consulta = p_id_consulta AND c.id_usuario = p_id_usuario
        FOR UPDATE;
        IF v_id IS NULL THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, 'Consulta no encontrada.' AS Mensaje; LEAVE proc;
        END IF;
        IF v_actual <> 'procesando' THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, 'La consulta ya fue completada.' AS Mensaje; LEAVE proc;
        END IF;

        UPDATE asistente_consulta
        SET    estado = p_estado, documentos_json = v_docs, respuesta_json = v_resp, motor_ia = LEFT(NULLIF(TRIM(IFNULL(p_motor, '')), ''), 60),
               duracion_ms = IF(p_duracion_ms BETWEEN 0 AND 2000000, p_duracion_ms, NULL)
        WHERE  id_consulta = p_id_consulta;
        COMMIT;

        SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;
        SELECT p_id_consulta AS id_consulta, CONVERT_TZ(v_creado, '+00:00', '-05:00') AS creado_en;
        LEAVE proc;
    END IF;

    -- ══════════ Fase 1: validar, aplicar el límite y registrar ══════════
    IF IFNULL(p_id_os, 0) <= 0 OR IFNULL(p_id_os_equipo, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio o equipo no encontrado.' AS Mensaje; LEAVE proc;
    END IF;
    SET v_pregunta = NULLIF(TRIM(IFNULL(p_pregunta, '')), '');
    IF v_pregunta IS NULL OR CHAR_LENGTH(v_pregunta) < 3 THEN
        SELECT 1 AS IdTipoMensaje, 'Escribe tu consulta (mínimo 3 caracteres).' AS Mensaje; LEAVE proc;
    END IF;
    IF CHAR_LENGTH(v_pregunta) > 500 THEN
        SELECT 1 AS IdTipoMensaje, 'La consulta puede tener hasta 500 caracteres.' AS Mensaje; LEAVE proc;
    END IF;
    SET v_origen = LOWER(TRIM(IFNULL(p_origen, 'texto')));
    IF v_origen NOT IN ('texto', 'voz', 'sugerencia') THEN
        SELECT 1 AS IdTipoMensaje, 'El origen de la consulta no es válido.' AS Mensaje; LEAVE proc;
    END IF;

    START TRANSACTION;

    SELECT u.id_usuario INTO v_usuario FROM usuario u WHERE u.id_usuario = p_id_usuario AND u.eliminado_en IS NULL FOR UPDATE;
    IF v_usuario IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Usuario no válido.' AS Mensaje; LEAVE proc;
    END IF;

    CALL SP_ContextoAsistenteMovil(p_id_usuario, p_id_os, p_id_os_equipo, v_msg, v_id_eq, v_id_sum, v_estado, v_numero, v_nombre, v_num_os, v_servicio,
                                   v_marca, v_modelo, v_cod_cli, v_serie);
    IF v_msg IS NOT NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje; LEAVE proc;
    END IF;

    SELECT COUNT(*) INTO v_minuto FROM asistente_consulta c WHERE c.id_usuario = p_id_usuario AND c.creado_en >= UTC_TIMESTAMP() - INTERVAL 1 MINUTE;
    IF v_minuto >= 10 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Hiciste muchas consultas seguidas. Espera un minuto e inténtalo de nuevo.' AS Mensaje; LEAVE proc;
    END IF;
    SELECT COUNT(*) INTO v_dia FROM asistente_consulta c WHERE c.id_usuario = p_id_usuario AND c.creado_en >= UTC_TIMESTAMP() - INTERVAL 24 HOUR;
    IF v_dia >= 200 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Llegaste al límite de 200 consultas al día. Podrás volver a consultar mañana.' AS Mensaje; LEAVE proc;
    END IF;

    SET v_creado = UTC_TIMESTAMP();
    INSERT INTO asistente_consulta (id_usuario, id_os, id_os_equipo, id_equipo, pregunta, origen, estado, creado_en)
    VALUES (p_id_usuario, p_id_os, p_id_os_equipo, v_id_eq, v_pregunta, v_origen, 'procesando', v_creado);
    SET v_id = LAST_INSERT_ID();
    COMMIT;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;
    SELECT v_id AS id_consulta, CONVERT_TZ(v_creado, '+00:00', '-05:00') AS creado_en;
END$$

DELIMITER ;

-- ############################################################
-- 8) SP_ObtenerConsultaAsistenteMovil
-- ############################################################
-- ============================================================
-- SP_ObtenerConsultaAsistenteMovil  (App Mobile HU-19 — reabrir una consulta reciente · lectura)
-- Una consulta con su respuesta (pregunta, advertencia, pasos y fuentes en `respuesta_json`) y la valoración del técnico. Solo la consulta es del propio técnico y
-- debe tener respuesta (las que se quedaron en proceso o terminaron en error de la IA no se pueden abrir). Horas de Lima.
-- Resultados: 1 mensaje · 2 consulta (1 fila).
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerConsultaAsistenteMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerConsultaAsistenteMovil(
    IN p_id_usuario  BIGINT,
    IN p_id_consulta BIGINT
)
proc: BEGIN
    DECLARE v_id     BIGINT DEFAULT NULL;
    DECLARE v_resp   TINYINT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_consulta, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Consulta no encontrada.' AS Mensaje; LEAVE proc;
    END IF;

    SELECT c.id_consulta, IF(c.respuesta_json IS NULL, 0, 1) INTO v_id, v_resp
    FROM   asistente_consulta c
    WHERE  c.id_consulta = p_id_consulta AND c.id_usuario = p_id_usuario;
    IF v_id IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Consulta no encontrada.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_resp = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Esta consulta no tiene respuesta.' AS Mensaje; LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;
    SELECT c.id_consulta, c.id_os, c.id_os_equipo, c.pregunta, c.origen, c.estado, CONVERT_TZ(c.creado_en, '+00:00', '-05:00') AS creado_en,
           CAST(c.respuesta_json AS CHAR) AS respuesta_json, c.util
    FROM   asistente_consulta c
    WHERE  c.id_consulta = p_id_consulta AND c.id_usuario = p_id_usuario;
END$$

DELIMITER ;

-- ############################################################
-- 9) SP_ValorarConsultaAsistenteMovil
-- ############################################################
-- ============================================================
-- SP_ValorarConsultaAsistenteMovil  (App Mobile HU-19 — "¿Te sirvió la respuesta?" · escritura)
-- El técnico marca su consulta como útil (1) o no útil (0). Solo su propia consulta y solo si tiene respuesta. Se puede cambiar de opinión.
-- Resultados: 1 mensaje.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ValorarConsultaAsistenteMovil;

DELIMITER $$

CREATE PROCEDURE SP_ValorarConsultaAsistenteMovil(
    IN p_id_usuario  BIGINT,
    IN p_id_consulta BIGINT,
    IN p_util        TINYINT
)
proc: BEGIN
    DECLARE v_id   BIGINT DEFAULT NULL;
    DECLARE v_resp TINYINT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_consulta, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Consulta no encontrada.' AS Mensaje; LEAVE proc;
    END IF;
    IF p_util IS NULL OR p_util NOT IN (0, 1) THEN
        SELECT 1 AS IdTipoMensaje, 'La valoración no es válida.' AS Mensaje; LEAVE proc;
    END IF;

    START TRANSACTION;
    SELECT c.id_consulta, IF(c.respuesta_json IS NULL, 0, 1) INTO v_id, v_resp
    FROM   asistente_consulta c
    WHERE  c.id_consulta = p_id_consulta AND c.id_usuario = p_id_usuario
    FOR UPDATE;
    IF v_id IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Consulta no encontrada.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_resp = 0 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Esta consulta no tiene respuesta que valorar.' AS Mensaje; LEAVE proc;
    END IF;

    UPDATE asistente_consulta SET util = p_util, valorada_en = UTC_TIMESTAMP() WHERE id_consulta = p_id_consulta;
    COMMIT;

    SELECT 2 AS IdTipoMensaje, 'Gracias por tu valoración.' AS Mensaje;
END$$

DELIMITER ;

-- ############################################################
-- 10) SP_ListarGuardadosAsistenteMovil
-- ############################################################
-- ============================================================
-- SP_ListarGuardadosAsistenteMovil  (App Mobile HU-19 — "Guardados" del Asistente IA · lectura)
-- Respuestas y fragmentos que el técnico guardó (sin los eliminados), los más recientes primero, máx. 100. p_busqueda filtra por título o subtítulo
-- (los comodines % y _ del texto se tratan como texto). Horas de Lima.
-- Resultados: 1 mensaje · 2 guardados (id_guardado, tipo, titulo, subtitulo, creado_en, tamano_bytes).
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ListarGuardadosAsistenteMovil;

DELIMITER $$

CREATE PROCEDURE SP_ListarGuardadosAsistenteMovil(
    IN p_id_usuario BIGINT,
    IN p_busqueda   VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_texto VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Usuario no válido.' AS Mensaje; LEAVE proc;
    END IF;

    SET v_texto = NULLIF(TRIM(IFNULL(p_busqueda, '')), '');
    IF v_texto IS NOT NULL THEN
        SET v_texto = CONCAT('%', REPLACE(REPLACE(REPLACE(v_texto, '\\', '\\\\'), '%', '\\%'), '_', '\\_'), '%');
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    SELECT g.id_guardado, g.tipo, g.titulo, g.subtitulo, CONVERT_TZ(g.creado_en, '+00:00', '-05:00') AS creado_en, g.tamano_bytes
    FROM   asistente_guardado g
    WHERE  g.id_usuario = p_id_usuario AND g.eliminado_en IS NULL
      AND  (v_texto IS NULL OR g.titulo LIKE v_texto OR g.subtitulo LIKE v_texto)
    ORDER BY g.creado_en DESC, g.id_guardado DESC
    LIMIT 100;
END$$

DELIMITER ;

-- ############################################################
-- 11) SP_GuardarAsistenteMovil
-- ############################################################
-- ============================================================
-- SP_GuardarAsistenteMovil  (App Mobile HU-19 — "Guardar offline" / "Fragmento" · escritura)
-- Guarda una copia de la respuesta (tipo 'respuesta', n = 0) o de uno de los fragmentos citados (tipo 'fragmento', n = número de la fuente, 1 a 20) de una consulta
-- del técnico, para que la app la lea sin conexión (la "descarga de sección" es el fragmento citado con su fuente, no un PDF recortado).
--   - La consulta debe ser del técnico y tener respuesta. El contenido (JSON) lo arma el back a partir de la consulta guardada, no la app.
--   - Idempotente: guardar dos veces lo mismo devuelve el guardado existente. Máx. 300 guardados por técnico.
-- Resultados: 1 mensaje · 2 guardado (id_guardado, tipo, titulo, subtitulo, creado_en en hora de Lima, tamano_bytes, contenido_json).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_GuardarAsistenteMovil;

DELIMITER $$

CREATE PROCEDURE SP_GuardarAsistenteMovil(
    IN p_id_usuario     BIGINT,
    IN p_id_consulta    BIGINT,
    IN p_tipo           VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_n              INT,
    IN p_titulo         VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_subtitulo      VARCHAR(400) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_contenido_json LONGTEXT     CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_tipo     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_titulo   VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_subt     VARCHAR(400) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_n        INT;
    DECLARE v_consulta BIGINT DEFAULT NULL;
    DECLARE v_resp     TINYINT DEFAULT 0;
    DECLARE v_id       BIGINT DEFAULT NULL;
    DECLARE v_total    INT DEFAULT 0;
    DECLARE v_creado   DATETIME;
    DECLARE v_bytes    INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_consulta, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Consulta no encontrada.' AS Mensaje; LEAVE proc;
    END IF;
    SET v_tipo = LOWER(TRIM(IFNULL(p_tipo, '')));
    IF v_tipo NOT IN ('respuesta', 'fragmento') THEN
        SELECT 1 AS IdTipoMensaje, 'Lo que quieres guardar no es válido.' AS Mensaje; LEAVE proc;
    END IF;
    SET v_n = IF(v_tipo = 'respuesta', 0, IFNULL(p_n, 0));
    IF v_tipo = 'fragmento' AND (v_n < 1 OR v_n > 20) THEN
        SELECT 1 AS IdTipoMensaje, 'La fuente indicada no existe.' AS Mensaje; LEAVE proc;
    END IF;
    SET v_titulo = NULLIF(TRIM(IFNULL(p_titulo, '')), '');
    SET v_subt   = NULLIF(TRIM(IFNULL(p_subtitulo, '')), '');
    IF v_titulo IS NULL OR CHAR_LENGTH(v_titulo) > 200 OR (v_subt IS NOT NULL AND CHAR_LENGTH(v_subt) > 300) THEN
        SELECT 1 AS IdTipoMensaje, 'El título o el subtítulo del guardado no son válidos.' AS Mensaje; LEAVE proc;
    END IF;
    IF p_contenido_json IS NULL OR NOT JSON_VALID(p_contenido_json) OR CHAR_LENGTH(p_contenido_json) > 60000 THEN
        SELECT 1 AS IdTipoMensaje, 'El contenido a guardar no es válido.' AS Mensaje; LEAVE proc;
    END IF;

    START TRANSACTION;

    SELECT c.id_consulta, IF(c.respuesta_json IS NULL, 0, 1) INTO v_consulta, v_resp
    FROM   asistente_consulta c
    WHERE  c.id_consulta = p_id_consulta AND c.id_usuario = p_id_usuario
    FOR UPDATE;
    IF v_consulta IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Consulta no encontrada.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_resp = 0 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Esta consulta no tiene respuesta que guardar.' AS Mensaje; LEAVE proc;
    END IF;

    SELECT g.id_guardado INTO v_id
    FROM   asistente_guardado g
    WHERE  g.id_usuario = p_id_usuario AND g.id_consulta = p_id_consulta AND g.tipo = v_tipo AND g.n = v_n AND g.eliminado_en IS NULL
    ORDER BY g.id_guardado LIMIT 1;

    IF v_id IS NULL THEN
        SELECT COUNT(*) INTO v_total FROM asistente_guardado g WHERE g.id_usuario = p_id_usuario AND g.eliminado_en IS NULL;
        IF v_total >= 300 THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, 'Llegaste al máximo de 300 guardados. Elimina alguno para guardar otro.' AS Mensaje; LEAVE proc;
        END IF;
        SET v_creado = UTC_TIMESTAMP();
        SET v_bytes  = LENGTH(p_contenido_json);
        INSERT INTO asistente_guardado (id_usuario, id_consulta, tipo, n, titulo, subtitulo, contenido_json, tamano_bytes, creado_en)
        VALUES (p_id_usuario, p_id_consulta, v_tipo, v_n, v_titulo, v_subt, p_contenido_json, v_bytes, v_creado);
        SET v_id = LAST_INSERT_ID();
    END IF;
    COMMIT;

    SELECT 2 AS IdTipoMensaje, 'Guardado en el teléfono: ya puedes leerlo sin conexión.' AS Mensaje;
    SELECT g.id_guardado, g.tipo, g.titulo, g.subtitulo, CONVERT_TZ(g.creado_en, '+00:00', '-05:00') AS creado_en, g.tamano_bytes, CAST(g.contenido_json AS CHAR) AS contenido_json
    FROM   asistente_guardado g WHERE g.id_guardado = v_id;
END$$

DELIMITER ;

-- ############################################################
-- 12) SP_ObtenerGuardadoAsistenteMovil
-- ############################################################
-- ============================================================
-- SP_ObtenerGuardadoAsistenteMovil  (App Mobile HU-19 — abrir un guardado · lectura)
-- Un guardado del propio técnico (no eliminado) con su contenido completo (JSON: la respuesta o el fragmento citado con su fuente). Horas de Lima.
-- Resultados: 1 mensaje · 2 guardado (id_guardado, tipo, titulo, subtitulo, creado_en, tamano_bytes, contenido_json).
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerGuardadoAsistenteMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerGuardadoAsistenteMovil(
    IN p_id_usuario  BIGINT,
    IN p_id_guardado BIGINT
)
proc: BEGIN
    DECLARE v_id BIGINT DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_guardado, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Guardado no encontrado.' AS Mensaje; LEAVE proc;
    END IF;

    SELECT g.id_guardado INTO v_id
    FROM   asistente_guardado g
    WHERE  g.id_guardado = p_id_guardado AND g.id_usuario = p_id_usuario AND g.eliminado_en IS NULL;
    IF v_id IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Guardado no encontrado.' AS Mensaje; LEAVE proc;
    END IF;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;
    SELECT g.id_guardado, g.tipo, g.titulo, g.subtitulo, CONVERT_TZ(g.creado_en, '+00:00', '-05:00') AS creado_en, g.tamano_bytes, CAST(g.contenido_json AS CHAR) AS contenido_json
    FROM   asistente_guardado g WHERE g.id_guardado = v_id;
END$$

DELIMITER ;

-- ############################################################
-- 13) SP_EliminarGuardadoAsistenteMovil
-- ############################################################
-- ============================================================
-- SP_EliminarGuardadoAsistenteMovil  (App Mobile HU-19 — quitar un guardado · escritura)
-- Eliminación lógica (eliminado_en / eliminado_por) de un guardado del propio técnico; queda en la bitácora de auditoría (auditoria_evento).
-- Repetir la petición sobre un guardado ya eliminado responde éxito sin duplicar nada.
-- Resultados: 1 mensaje.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_EliminarGuardadoAsistenteMovil;

DELIMITER $$

CREATE PROCEDURE SP_EliminarGuardadoAsistenteMovil(
    IN p_id_usuario  BIGINT,
    IN p_id_guardado BIGINT
)
proc: BEGIN
    DECLARE v_id       BIGINT DEFAULT NULL;
    DECLARE v_eliminado DATETIME DEFAULT NULL;
    DECLARE v_titulo   VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_tipo     VARCHAR(12)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_consulta BIGINT DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_guardado, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Guardado no encontrado.' AS Mensaje; LEAVE proc;
    END IF;

    START TRANSACTION;
    SELECT g.id_guardado, g.eliminado_en, g.titulo, g.tipo, g.id_consulta INTO v_id, v_eliminado, v_titulo, v_tipo, v_consulta
    FROM   asistente_guardado g
    WHERE  g.id_guardado = p_id_guardado AND g.id_usuario = p_id_usuario
    FOR UPDATE;
    IF v_id IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Guardado no encontrado.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_eliminado IS NOT NULL THEN
        COMMIT;
        SELECT 2 AS IdTipoMensaje, 'El guardado ya estaba eliminado.' AS Mensaje; LEAVE proc;
    END IF;

    UPDATE asistente_guardado SET eliminado_en = UTC_TIMESTAMP(), eliminado_por = p_id_usuario WHERE id_guardado = p_id_guardado;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('asistente_guardado', p_id_guardado, 'eliminar_guardado', 'guardado', 'eliminado',
            LEFT(CONCAT('Guardado del Asistente IA eliminado: ', v_titulo), 900), p_id_usuario, NOW(),
            JSON_OBJECT('id_guardado', p_id_guardado, 'id_consulta', v_consulta, 'tipo', v_tipo));
    COMMIT;

    SELECT 2 AS IdTipoMensaje, 'Guardado eliminado.' AS Mensaje;
END$$

DELIMITER ;

-- ============================================================
-- COMPROBACIÓN (solo lectura, no modifica datos)
-- ============================================================
-- A) Procedimientos con la fecha/hora de hoy (deben ser 12)
SELECT ROUTINE_NAME AS procedimiento, LAST_ALTERED AS actualizado FROM INFORMATION_SCHEMA.ROUTINES
WHERE ROUTINE_SCHEMA = DATABASE() AND ROUTINE_NAME IN ('SP_ContextoAsistenteMovil', 'SP_ArmarDocumentosAsistenteMovil', 'SP_DocumentosAsistenteMovil', 'SP_InicioAsistenteMovil',
      'SP_EquiposAsistenteMovil', 'SP_RegistrarConsultaAsistenteMovil', 'SP_ObtenerConsultaAsistenteMovil', 'SP_ValorarConsultaAsistenteMovil',
      'SP_ListarGuardadosAsistenteMovil', 'SP_GuardarAsistenteMovil', 'SP_ObtenerGuardadoAsistenteMovil', 'SP_EliminarGuardadoAsistenteMovil') ORDER BY ROUTINE_NAME;

-- B) Usuario inexistente: "Usuario no válido."
CALL SP_InicioAsistenteMovil(0, NULL, NULL);

-- C) Inicio del asistente del técnico de la OS de prueba (2 contexto: el equipo en ejecución si lo hay; 3 fuentes; 4 sugerencias; 5 recientes)
SET @os = 8;
SET @tec = (SELECT id_tecnico_principal FROM orden_servicio WHERE id_os = @os);
SET @oe = (SELECT MIN(id) FROM os_equipo WHERE id_os = @os AND eliminado_en IS NULL);
CALL SP_InicioAsistenteMovil(@tec, NULL, NULL);

-- D) Inicio con un equipo indicado y los documentos oficiales que se le darían a la IA (3 = lista de documentos; puede estar vacía si el equipo aún no tiene manual ni procedimientos con PDF)
CALL SP_InicioAsistenteMovil(@tec, @os, @oe);
CALL SP_DocumentosAsistenteMovil(@tec, @os, @oe);

-- E) Equipos para "Cambiar" (el equipo en ejecución primero, con cuántos documentos consultables tiene cada uno)
CALL SP_EquiposAsistenteMovil(@tec);

-- F) Guardados del técnico (vacío mientras no se guarde nada) y una consulta inexistente ("Consulta no encontrada.")
CALL SP_ListarGuardadosAsistenteMovil(@tec, NULL);
CALL SP_ObtenerConsultaAsistenteMovil(@tec, 0);

-- G) Las dos tablas nuevas y las 7 sugerencias (debe ser 9)
SELECT 'Migración 102 (debe ser 9)' AS verificacion,
       (SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME IN ('asistente_consulta', 'asistente_guardado'))
     + (SELECT COUNT(*) FROM tabla_maestra WHERE Descripcion = 'SUGERENCIA_ASISTENTE' AND IdEmpresa = 1) AS valor;
