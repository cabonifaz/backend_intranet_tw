-- Registrar el informe de un equipo desde la intranet, en nombre del técnico (HU-55). Ejecutar con Alt+X (No al aviso de variables) y reiniciar la API.
-- Requiere antes: la migración 92 (registro del Asistente: catálogo MOTIVO_CAMBIO_MANUAL y acción seg_registrar) y los scripts móviles del flujo del informe (trabajo del equipo, evidencias, ensayos,
-- cabecera, correlativos y firma/constancia): este script NO los toca; los SP nuevos los llaman. No crea datos de negocio.
-- Qué hace: migración 127 (informe_tecnico: id_registrado_por, via y registrado_en · tabla registro_informe_intranet · motivo PLANTA_SIN_CELULAR · acción seg_registrar_informe) y crea 8
-- procedimientos nuevos: SP_AutorizarRegistroIntranet, SP_ContextoRegistroIntranet, SP_IniciarRegistroIntranet, SP_LiberarRegistroIntranet, SP_MarcarRegistroInformeIntranet,
-- SP_AjustarTiempoEquipoIntranet, SP_ForzarEvidenciaIntranet y SP_PausarEquipoAbiertoIntranet. No cambia ningún SP existente ni su firma: la app móvil sigue igual.
-- Después de ejecutarlo, asigna la acción seg_registrar_informe (módulo operaciones, nivel editar) a quien deba registrar: la matriz permiso_area_rol ya la da a quien tiene «editar» en operaciones.
-- Este archivo se genera concatenando database/migrations/127_registro_informe_intranet.sql (sin su verificación) y los 8 database/procedures/SP_*Intranet.sql de la HU-55.

-- ============================================================
-- Migración 127 — HU-55: registrar el informe de un equipo desde la intranet (Asistente de Seguimiento / Jefe de Operaciones)
--   Cuando el cliente no deja usar celular en planta, el trabajo del técnico en un equipo lo registra la intranet EN NOMBRE DEL TÉCNICO
--   (variables, evidencias, ensayos, cabecera, correlativo, cierre y generar informe). El informe queda a nombre del técnico asignado y se guarda quién lo registró.
--   1. informe_tecnico: id_registrado_por (quién lo registró de verdad), via ('app' | 'intranet', por defecto 'app') y registrado_en (UTC, la primera vez que se registró desde
--      la intranet). NO se toca el ENUM `origen` de las tablas hijas: los filtros origen = 'tecnico' del Hard Stop, la cabecera y los ensayos dejarían de ver lo registrado.
--      Los informes anteriores quedan con via = 'app' e id_registrado_por = NULL.
--   2. registro_informe_intranet: la sesión de registro de un equipo (bloqueo entre quienes registran desde la intranet; caduca a los 30 min sin actividad) con las horas de
--      inicio y fin del trabajo que indicó quien registra y el motivo. Una sesión activa por equipo.
--   3. Catálogo MOTIVO_CAMBIO_MANUAL: código nuevo PLANTA_SIN_CELULAR («Planta no permite celular»). Requiere la migración 92 (si el catálogo no existe, no inserta nada).
--   4. Acción seg_registrar_informe (88 ACCION_SISTEMA, nivel 2 = editar, módulo operaciones): el mismo patrón que seg_registrar; la matriz permiso_area_rol ya da el acceso por nivel.
--   No borra ni cambia datos existentes. IDEMPOTENTE.
-- ============================================================

-- ── 1. informe_tecnico: quién lo registró y por qué vía ─────────────────────────────────────
SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'informe_tecnico' AND COLUMN_NAME = 'id_registrado_por'),
    'ALTER TABLE informe_tecnico ADD COLUMN id_registrado_por BIGINT NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'informe_tecnico' AND COLUMN_NAME = 'via'),
    'ALTER TABLE informe_tecnico ADD COLUMN via ENUM(''app'',''intranet'') NOT NULL DEFAULT ''app''', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

SET @sql := IF(NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                           WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'informe_tecnico' AND COLUMN_NAME = 'registrado_en'),
    'ALTER TABLE informe_tecnico ADD COLUMN registrado_en DATETIME NULL', 'SELECT 1');
PREPARE st FROM @sql; EXECUTE st; DEALLOCATE PREPARE st;

-- ── 2. Sesión de registro desde la intranet (bloqueo por equipo) ────────────────────────────
CREATE TABLE IF NOT EXISTS registro_informe_intranet (
    id_registro         BIGINT       NOT NULL AUTO_INCREMENT,
    id_os               BIGINT       NOT NULL,
    id_os_equipo        BIGINT       NOT NULL,
    id_tecnico          BIGINT       NOT NULL,
    id_registrador      BIGINT       NOT NULL,
    inicio_utc          DATETIME     NOT NULL,
    fin_utc             DATETIME     NOT NULL,
    tiempo_aplicado_seg INT          NULL,
    motivo_codigo       VARCHAR(40)  NOT NULL,
    comentario          VARCHAR(300) NULL,
    estado              ENUM('activo','liberado','caducado','cerrado') NOT NULL DEFAULT 'activo',
    tomado_en           DATETIME     NOT NULL,
    ultima_actividad    DATETIME     NOT NULL,
    liberado_en         DATETIME     NULL,
    creado_en           DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id_registro),
    KEY ix_rii_equipo (id_os_equipo, estado),
    KEY ix_rii_registrador (id_registrador, estado)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ── 3. Motivo «Planta no permite celular» (se agrega al catálogo MOTIVO_CAMBIO_MANUAL de la migración 92) ──
SET @id_motivo := (SELECT MAX(IdMaestro) FROM tabla_maestra WHERE Descripcion = 'MOTIVO_CAMBIO_MANUAL' AND IdEmpresa = 1);
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2)
SELECT 1, @id_motivo, 'MOTIVO_CAMBIO_MANUAL',
       (SELECT MAX(t2.Num1) + 1 FROM tabla_maestra t2 WHERE t2.Descripcion = 'MOTIVO_CAMBIO_MANUAL' AND t2.IdEmpresa = 1),
       'Planta no permite celular', 'PLANTA_SIN_CELULAR'
FROM (SELECT 1) u
WHERE @id_motivo IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM tabla_maestra t WHERE t.Descripcion = 'MOTIVO_CAMBIO_MANUAL' AND t.IdEmpresa = 1 AND t.String2 = 'PLANTA_SIN_CELULAR');

-- ── 4. Acción (88 ACCION_SISTEMA: Num1 = nivel, String3 = módulo) ───────────────────────────
INSERT INTO tabla_maestra (IdEmpresa, IdMaestro, Descripcion, Num1, String1, String2, String3)
SELECT 1, 88, 'ACCION_SISTEMA', 2, 'Registrar el informe técnico de un equipo desde la intranet, en nombre del técnico (HU-55)', 'seg_registrar_informe', 'operaciones'
WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra t WHERE t.IdMaestro = 88 AND t.IdEmpresa = 1 AND t.String2 = 'seg_registrar_informe');


-- ============================================================
-- SP_AutorizarRegistroIntranet  (HU-55 — puerta de entrada de CADA lectura o escritura del registro del informe desde la intranet · apoyo de la API)
-- Valida el permiso (acción seg_registrar_informe), resuelve el técnico asignado de la OS (el que se pasa a los casos de uso móviles: nunca el id de quien registra) y, en escritura,
-- exige y renueva el bloqueo del equipo (registro_informe_intranet).
--   p_modo = 'lectura'   permiso + técnico + OS no anulada; p_id_os_equipo puede ser NULL (pasos a nivel de OS: firma y constancia después de generar, cuando el bloqueo ya se liberó).
--            No toca el bloqueo.
--   p_modo = 'escritura' además exige p_id_os_equipo y la sesión ACTIVA PROPIA de ese equipo y renueva ultima_actividad. Sin sesión: "Primero inicia el registro de este equipo.".
--            Si otra persona la tiene con actividad en los últimos 30 min: regla de negocio con el prefijo "[409] " (la API lo convierte en HTTP 409). Si la sesión propia
--            estaba inactiva más de 30 min pero nadie la tomó, se renueva (el bloqueo solo se libera cuando otra persona lo pide en SP_IniciarRegistroIntranet).
-- No valida el estado de la OS ni del equipo más allá de "no anulada": eso lo hacen los SP móviles que se llaman después con el técnico.
-- Resultados: 1 mensaje (1 regla de negocio · 2 éxito · 3 error) · solo con 2: id_tecnico, id_registro (NULL en lectura), informe_fisico (0/1).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_AutorizarRegistroIntranet;

DELIMITER $$

CREATE PROCEDURE SP_AutorizarRegistroIntranet(
    IN p_id_registrador BIGINT,
    IN p_id_os          BIGINT,
    IN p_id_os_equipo   BIGINT,
    IN p_modo           VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_modo       VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado_os  VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_tecnico    BIGINT       DEFAULT NULL;
    DECLARE v_fisico     TINYINT      DEFAULT 1;
    DECLARE v_id_equipo  BIGINT       DEFAULT NULL;
    DECLARE v_reg_id     BIGINT       DEFAULT NULL;
    DECLARE v_reg_user   BIGINT       DEFAULT NULL;
    DECLARE v_reg_act    DATETIME     DEFAULT NULL;
    DECLARE v_reg_nombre VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_ahora      DATETIME;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    SET v_modo = LOWER(TRIM(IFNULL(p_modo, '')));
    IF IFNULL(p_id_registrador, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio o equipo no encontrado.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_modo NOT IN ('lectura', 'escritura') THEN
        SELECT 1 AS IdTipoMensaje, 'El modo de acceso no es válido.' AS Mensaje; LEAVE proc;
    END IF;
    IF FN_PermisoAccion(p_id_registrador, 'seg_registrar_informe') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para registrar informes desde la intranet.' AS Mensaje; LEAVE proc;
    END IF;

    SELECT os.estado, os.id_tecnico_principal, IF(os.informe_fisico = 0, 0, 1) INTO v_estado_os, v_tecnico, v_fisico
    FROM   orden_servicio os
    WHERE  os.id_os = p_id_os AND os.eliminado_en IS NULL;
    IF v_estado_os IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio no encontrado.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_estado_os = 'anulada' THEN
        SELECT 1 AS IdTipoMensaje, 'La OS está anulada.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_tecnico IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'El servicio no tiene un técnico asignado.' AS Mensaje; LEAVE proc;
    END IF;

    IF p_id_os_equipo IS NOT NULL THEN
        SELECT oe.id_equipo INTO v_id_equipo FROM os_equipo oe WHERE oe.id = p_id_os_equipo AND oe.id_os = p_id_os AND oe.eliminado_en IS NULL;
        IF v_id_equipo IS NULL THEN
            SELECT 1 AS IdTipoMensaje, 'El equipo no pertenece a este servicio.' AS Mensaje; LEAVE proc;
        END IF;
    END IF;

    IF v_modo = 'lectura' THEN
        SELECT 2 AS IdTipoMensaje, 'Autorizado.' AS Mensaje;
        SELECT v_tecnico AS id_tecnico, NULL AS id_registro, v_fisico AS informe_fisico;
        LEAVE proc;
    END IF;

    -- Escritura: exige la sesión propia del equipo
    IF IFNULL(p_id_os_equipo, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Indica el equipo.' AS Mensaje; LEAVE proc;
    END IF;

    SET v_ahora = UTC_TIMESTAMP();
    START TRANSACTION;

    SELECT r.id_registro, r.id_registrador, r.ultima_actividad INTO v_reg_id, v_reg_user, v_reg_act
    FROM   registro_informe_intranet r
    WHERE  r.id_os_equipo = p_id_os_equipo AND r.id_os = p_id_os AND r.estado = 'activo'
    ORDER BY r.id_registro DESC LIMIT 1
    FOR UPDATE;

    IF v_reg_id IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Primero inicia el registro de este equipo.' AS Mensaje; LEAVE proc;
    END IF;

    IF v_reg_user = p_id_registrador THEN
        UPDATE registro_informe_intranet SET ultima_actividad = v_ahora WHERE id_registro = v_reg_id;
        COMMIT;
        SELECT 2 AS IdTipoMensaje, 'Autorizado.' AS Mensaje;
        SELECT v_tecnico AS id_tecnico, v_reg_id AS id_registro, v_fisico AS informe_fisico;
        LEAVE proc;
    END IF;

    -- La sesión es de otra persona
    IF v_reg_act >= v_ahora - INTERVAL 30 MINUTE THEN
        SELECT TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))) INTO v_reg_nombre FROM usuario u WHERE u.id_usuario = v_reg_user LIMIT 1;
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje,
               CONCAT('[409] ', IFNULL(NULLIF(v_reg_nombre, ''), 'Otra persona'), ' está registrando el informe de este equipo. Inténtalo cuando termine o pasen 30 minutos sin actividad.') AS Mensaje;
        LEAVE proc;
    END IF;

    -- Esa sesión caducó y quien llama no la tiene: se libera y debe iniciar el registro
    UPDATE registro_informe_intranet SET estado = 'caducado', liberado_en = v_ahora WHERE id_registro = v_reg_id;
    COMMIT;
    SELECT 1 AS IdTipoMensaje, 'Primero inicia el registro de este equipo.' AS Mensaje;
END$$

DELIMITER ;

-- ============================================================
-- SP_ContextoRegistroIntranet  (HU-55 — registrar el informe de un equipo desde la intranet · SOLO LECTURA)
-- Todo lo que necesita la pantalla "Registrar informe" de la Asistente de Seguimiento / Jefe de Operaciones ANTES de comenzar: la OS, el cliente y la planta, el equipo, el técnico
-- asignado, si el servicio lleva informe físico, el estado de las 5 etapas, el informe (borrador o generado), si se puede iniciar el registro, quién lo tiene abierto y los catálogos.
-- NO escribe nada (ni llegada, ni inicio del equipo, ni bloqueo): eso lo hace SP_IniciarRegistroIntranet. Acceso: acción seg_registrar_informe (FN_PermisoAccion).
-- Reutiliza SP_ArmarObjetivosMovil (estado del equipo), SP_ArmarEtapasEquipoMovil (las 5 etapas) y SP_TipoOrdenMovil: la regla de cada una vive solo allí. No modifica ningún SP móvil.
-- Reglas de puede_iniciar (motivo_no_puede dice la primera que falla): técnico asignado · OS en programada, reprogramada, en_ruta, en_ejecucion o pausada (anulada, borrador, emitida,
--   bloqueada por SSOMA y finalizada NO: la finalizada está pendiente de decisión) · el equipo es un objetivo de la OS, no está bloqueado ni completado y su informe no está generado
--   (para corregirlo existe el informe complementario) · el técnico no tiene OTRO equipo en ejecución (otro_equipo_abierto: pausarlo con SP_PausarEquipoAbiertoIntranet) · nadie más tiene
--   el registro abierto con actividad en los últimos 30 min. Si el registro propio está abierto, puede_iniciar sigue en 1 (volver a entrar es idempotente).
-- Horas de registro_ultima_actividad en hora de Lima. actividad_previa_tecnico = el equipo ya tiene variables, evidencias o ensayos y nunca se abrió un registro desde la intranet
--   (es decir, el técnico ya trabajó desde su app: avisar a la Asistente antes de mezclar).
-- Resultados: 1 mensaje (1 regla de negocio · 2 éxito · 3 error) · solo con 2: 2 contexto (1 fila) · 3 etapas (orden, codigo, nombre, estado, detalle) ·
--   4 catálogos en formato largo (catalogo, codigo, nombre, clasificacion, orden): procedencia, tipo_equipo, forma_plato, checklist_os, checklist_om, severidad, estado_equipo,
--   clasificacion_falla, componente_falla (clasificacion = padre) y motivo_manual.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ContextoRegistroIntranet;

DELIMITER $$

CREATE PROCEDURE SP_ContextoRegistroIntranet(
    IN p_id_registrador BIGINT,
    IN p_id_os          BIGINT,
    IN p_id_os_equipo   BIGINT
)
proc: BEGIN
    DECLARE v_estado_os   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_estado_chk  VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_numero_os   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_tecnico     BIGINT       DEFAULT NULL;
    DECLARE v_id_equipo   BIGINT       DEFAULT NULL;
    DECLARE v_tipo        VARCHAR(2)   CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT 'OS';
    DECLARE v_rq          VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_salida      DATETIME     DEFAULT NULL;
    DECLARE v_llegada     DATETIME     DEFAULT NULL;
    DECLARE v_hab         TINYINT      DEFAULT 0;
    DECLARE v_motivo_obj  VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_hay_obj     TINYINT      DEFAULT 0;
    DECLARE v_estado_eq   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_bloqueado   TINYINT      DEFAULT 0;
    DECLARE v_req_aprob   TINYINT      DEFAULT 0;
    DECLARE v_informe     BIGINT       DEFAULT NULL;
    DECLARE v_gen         DATETIME     DEFAULT NULL;
    DECLARE v_num_inf     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_puede       TINYINT      DEFAULT 1;
    DECLARE v_motivo_no   VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_reg_id      BIGINT       DEFAULT NULL;
    DECLARE v_reg_user    BIGINT       DEFAULT NULL;
    DECLARE v_reg_act     DATETIME     DEFAULT NULL;
    DECLARE v_reg_activo  TINYINT      DEFAULT 0;
    DECLARE v_reg_propio  TINYINT      DEFAULT 0;
    DECLARE v_reg_nombre  VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_previa      TINYINT      DEFAULT 0;
    DECLARE v_otro        VARCHAR(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_conformes   INT          DEFAULT 0;
    DECLARE v_ahora       DATETIME;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov, tmp_etapas_mov, tmp_pend_eq, tmp_cat_evid;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_registrador, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 OR IFNULL(p_id_os_equipo, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio o equipo no encontrado.' AS Mensaje; LEAVE proc;
    END IF;
    IF FN_PermisoAccion(p_id_registrador, 'seg_registrar_informe') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para registrar informes desde la intranet.' AS Mensaje; LEAVE proc;
    END IF;

    SET v_ahora = UTC_TIMESTAMP();

    SELECT os.estado, os.numero, os.id_tecnico_principal INTO v_estado_os, v_numero_os, v_tecnico
    FROM   orden_servicio os
    WHERE  os.id_os = p_id_os AND os.eliminado_en IS NULL;
    IF v_estado_os IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio no encontrado.' AS Mensaje; LEAVE proc;
    END IF;

    SELECT oe.id_equipo INTO v_id_equipo
    FROM   os_equipo oe
    WHERE  oe.id = p_id_os_equipo AND oe.id_os = p_id_os AND oe.eliminado_en IS NULL;
    IF v_id_equipo IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'El equipo no pertenece a este servicio.' AS Mensaje; LEAVE proc;
    END IF;

    CALL SP_TipoOrdenMovil(p_id_os, v_tipo, v_rq);

    -- Estado del equipo y de la OS: una sola vez, en SP_ArmarObjetivosMovil (solo lectura; deja tmp_obj_mov)
    CALL SP_ArmarObjetivosMovil(p_id_os, v_estado_chk, v_salida, v_llegada, v_hab, v_motivo_obj);
    SELECT 1, t.estado, t.bloqueado, t.requiere_aprobacion INTO v_hay_obj, v_estado_eq, v_bloqueado, v_req_aprob
    FROM   tmp_obj_mov t WHERE t.id_os_equipo = p_id_os_equipo;

    -- Informe técnico del equipo (borrador o generado; el complementario no tiene id_os ni id_equipo y no entra aquí)
    SELECT it.id_informe, it.generado_en, it.numero_informe INTO v_informe, v_gen, v_num_inf
    FROM   informe_tecnico it
    WHERE  it.id_os = p_id_os AND it.id_equipo = v_id_equipo AND it.eliminado_en IS NULL
    ORDER BY it.id_informe DESC LIMIT 1;

    -- Quién tiene abierto el registro (activo y con actividad en los últimos 30 min)
    SELECT r.id_registro, r.id_registrador, r.ultima_actividad INTO v_reg_id, v_reg_user, v_reg_act
    FROM   registro_informe_intranet r
    WHERE  r.id_os_equipo = p_id_os_equipo AND r.estado = 'activo'
    ORDER BY r.id_registro DESC LIMIT 1;
    IF v_reg_id IS NOT NULL AND v_reg_act >= v_ahora - INTERVAL 30 MINUTE THEN
        SET v_reg_activo = 1;
        SET v_reg_propio = IF(v_reg_user = p_id_registrador, 1, 0);
        SELECT TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))) INTO v_reg_nombre FROM usuario u WHERE u.id_usuario = v_reg_user LIMIT 1;
    ELSE
        SET v_reg_id = NULL, v_reg_user = NULL, v_reg_act = NULL;
    END IF;

    -- El técnico ya trabajó desde su app en este equipo (hay datos y nunca se abrió un registro desde la intranet)
    IF NOT EXISTS (SELECT 1 FROM registro_informe_intranet r WHERE r.id_os_equipo = p_id_os_equipo)
       AND (EXISTS (SELECT 1 FROM variable_ambiental va WHERE va.id_os = p_id_os AND va.id_equipo = v_id_equipo AND va.eliminado_en IS NULL)
            OR EXISTS (SELECT 1 FROM evidencia_fotografica f WHERE f.id_os = p_id_os AND f.id_equipo = v_id_equipo AND f.eliminado_en IS NULL)
            OR EXISTS (SELECT 1 FROM informe_ensayo ie JOIN informe_tecnico it2 ON it2.id_informe = ie.id_informe
                       WHERE it2.id_os = p_id_os AND it2.id_equipo = v_id_equipo AND it2.eliminado_en IS NULL AND ie.eliminado_en IS NULL)) THEN
        SET v_previa = 1;
    END IF;

    -- Otro equipo del técnico en ejecución (la regla móvil: un técnico trabaja en un solo equipo a la vez)
    IF v_tecnico IS NOT NULL THEN
        SELECT CONCAT(IFNULL(NULLIF(ec.codigo_cliente, ''), ec.codigo_tw), ' (', o2.numero, ')') INTO v_otro
        FROM   os_equipo x
        JOIN   equipo_cliente ec ON ec.id_equipo = x.id_equipo
        JOIN   orden_servicio o2 ON o2.id_os = x.id_os
        WHERE  x.id_usuario_ejecucion = v_tecnico AND x.estado_ejecucion = 'en_proceso' AND x.pausado = 0
          AND  x.id <> p_id_os_equipo AND x.eliminado_en IS NULL
        LIMIT 1;
    END IF;

    -- ¿Se puede iniciar el registro? La primera regla que falla da el motivo
    IF v_tecnico IS NULL THEN
        SET v_puede = 0, v_motivo_no = 'El servicio no tiene un técnico asignado.';
    ELSEIF v_estado_os = 'finalizada' THEN
        SET v_puede = 0, v_motivo_no = 'La OS ya está finalizada: esta función aún no cubre ese caso.';
    ELSEIF v_estado_os = 'anulada' THEN
        SET v_puede = 0, v_motivo_no = 'La OS está anulada.';
    ELSEIF v_estado_os = 'bloqueada' THEN
        SET v_puede = 0, v_motivo_no = 'La OS está bloqueada por SSOMA.';
    ELSEIF v_estado_os IN ('borrador', 'emitida') THEN
        SET v_puede = 0, v_motivo_no = 'La OS todavía no está programada ni tiene técnico asignado.';
    ELSEIF v_estado_os NOT IN ('programada', 'reprogramada', 'en_ruta', 'en_ejecucion', 'pausada') THEN
        SET v_puede = 0, v_motivo_no = 'El estado de la OS no permite registrar el informe.';
    ELSEIF v_hay_obj = 0 THEN
        SET v_puede = 0, v_motivo_no = 'El equipo no forma parte de los objetivos de este servicio.';
    ELSEIF v_gen IS NOT NULL THEN
        SET v_puede = 0, v_motivo_no = 'Este equipo ya tiene el informe generado. Para corregirlo usa el informe complementario.';
    ELSEIF v_estado_eq = 'completado' THEN
        SET v_puede = 0, v_motivo_no = 'Este equipo ya está completado.';
    ELSEIF v_bloqueado = 1 THEN
        SET v_puede = 0, v_motivo_no = 'Este equipo está bloqueado y no se puede intervenir.';
    ELSEIF v_estado_eq = 'pausado' AND v_req_aprob = 1 THEN
        SET v_puede = 0, v_motivo_no = 'El equipo está pausado esperando la aprobación de un supervisor.';
    ELSEIF v_reg_activo = 1 AND v_reg_propio = 0 THEN
        SET v_puede = 0, v_motivo_no = CONCAT('Otra persona (', IFNULL(v_reg_nombre, 'otro usuario'), ') está registrando este equipo.');
    ELSEIF v_otro IS NOT NULL THEN
        SET v_puede = 0, v_motivo_no = CONCAT('El técnico ya tiene en ejecución el equipo ', v_otro, ': pausa ese equipo antes de continuar con otro.');
    END IF;

    -- Las 5 etapas (deja tmp_etapas_mov y tmp_pend_eq; sin datos salen pendiente / bloqueado, sin error)
    CALL SP_ArmarEtapasEquipoMovil(p_id_os, v_id_equipo, v_conformes);

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2. Contexto
    SELECT os.id_os, os.numero AS numero_os, v_tipo AS tipo_orden, v_rq AS numero_rq, os.estado AS estado_os,
           c.razon_social AS cliente, c.ruc AS ruc, sc.nombre AS planta, sc.direccion_exacta AS direccion_planta,
           p_id_os_equipo AS id_os_equipo, v_id_equipo AS id_equipo, IFNULL(t.nombre, 'Equipo') AS equipo_nombre, IFNULL(t.numero, 0) AS numero_equipo,
           NULLIF(TRIM(ec.num_serie), '') AS numero_serie, NULLIF(ec.codigo_cliente, '') AS codigo_cliente, ec.codigo_tw, ec.marca, ec.modelo,
           v_tecnico AS id_tecnico, NULLIF(TRIM(CONCAT(IFNULL(ut.nombre, ''), ' ', IFNULL(ut.apellido, ''))), '') AS tecnico,
           IF(os.informe_fisico = 0, 0, 1) AS informe_fisico,
           IFNULL(v_estado_eq, 'por_iniciar') AS estado_equipo,
           IF(v_estado_eq IN ('en_ejecucion', 'pausado', 'completado'), 1, 0) AS iniciado,
           IF(v_gen IS NULL, 0, 1) AS informe_generado, v_num_inf AS numero_informe, v_informe AS id_informe,
           v_puede AS puede_iniciar, v_motivo_no AS motivo_no_puede,
           v_reg_activo AS registro_activo, v_reg_user AS registrador_id, v_reg_nombre AS registrador_nombre, v_reg_propio AS registro_propio,
           CONVERT_TZ(v_reg_act, '+00:00', '-05:00') AS registro_ultima_actividad,
           v_previa AS actividad_previa_tecnico, v_otro AS otro_equipo_abierto
    FROM   orden_servicio os
    JOIN   equipo_cliente ec          ON ec.id_equipo = v_id_equipo
    LEFT JOIN cliente c               ON c.id_cliente = os.id_cliente
    LEFT JOIN sede_cliente sc         ON sc.id_sede = os.id_sede
    LEFT JOIN usuario ut              ON ut.id_usuario = v_tecnico
    LEFT JOIN tmp_obj_mov t           ON t.id_os_equipo = p_id_os_equipo
    WHERE  os.id_os = p_id_os;

    -- 3. Etapas
    SELECT e.orden, e.codigo, e.nombre, e.estado, e.detalle FROM tmp_etapas_mov e ORDER BY e.orden;

    -- 4. Catálogos (formato largo). Las formas del plato, severidades y estados del equipo son los valores que validan los SP móviles de ensayos y cabecera.
    SELECT 'procedencia' AS catalogo, 'N.I' AS codigo, 'No indicado' AS nombre, NULL AS clasificacion, 1 AS orden
    UNION ALL
    SELECT 'tipo_equipo', m.String2, m.String1, NULL, ROW_NUMBER() OVER (ORDER BY m.String1)
    FROM   tabla_maestra m WHERE m.Descripcion = 'CLASIFICACION_EQUIPO' AND m.IdEmpresa = 1 AND m.eliminado_en IS NULL
    UNION ALL
    SELECT 'forma_plato', 'rectangular', 'Rectangular', NULL, 1
    UNION ALL
    SELECT 'forma_plato', 'circular', 'Circular', NULL, 2
    UNION ALL
    SELECT 'forma_plato', 'triangular', 'Triangular', NULL, 3
    UNION ALL
    SELECT IF(m.String3 = 'OM', 'checklist_om', 'checklist_os'), m.String2, m.String1, NULL, m.Num1
    FROM   tabla_maestra m WHERE m.Descripcion = 'CHECKLIST_SERVICIO' AND m.IdEmpresa = 1 AND m.String3 IN ('OS', 'OM') AND m.eliminado_en IS NULL
    UNION ALL
    SELECT 'severidad', 'baja', 'Baja', NULL, 1
    UNION ALL
    SELECT 'severidad', 'media', 'Media', NULL, 2
    UNION ALL
    SELECT 'severidad', 'alta', 'Alta', NULL, 3
    UNION ALL
    SELECT 'severidad', 'critica', 'Crítica', NULL, 4
    UNION ALL
    SELECT 'estado_equipo', 'operativo', 'Operativo', NULL, 1
    UNION ALL
    SELECT 'estado_equipo', 'con_observaciones', 'Con observaciones', NULL, 2
    UNION ALL
    SELECT 'estado_equipo', 'inoperativo', 'Inoperativo', NULL, 3
    UNION ALL
    SELECT 'clasificacion_falla', m.String2, m.String1, NULL, ROW_NUMBER() OVER (ORDER BY m.String1)
    FROM   tabla_maestra m WHERE m.Descripcion = 'CLASIFICACION_FALLA' AND m.IdEmpresa = 1 AND m.eliminado_en IS NULL
    UNION ALL
    SELECT 'componente_falla', m.String2, m.String1, m.String3, ROW_NUMBER() OVER (ORDER BY m.String1)
    FROM   tabla_maestra m WHERE m.Descripcion = 'COMPONENTE_FALLA' AND m.IdEmpresa = 1 AND m.eliminado_en IS NULL
    UNION ALL
    SELECT 'motivo_manual', m.String2, m.String1, NULL, m.Num1
    FROM   tabla_maestra m WHERE m.Descripcion = 'MOTIVO_CAMBIO_MANUAL' AND m.IdEmpresa = 1 AND m.eliminado_en IS NULL
    ORDER BY catalogo, orden, nombre;

    DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov, tmp_etapas_mov, tmp_pend_eq;
END$$

DELIMITER ;

-- ============================================================
-- SP_IniciarRegistroIntranet  (HU-55 — "Comenzar registro" del informe de un equipo desde la intranet · escritura)
-- La Asistente de Seguimiento / el Jefe de Operaciones abren el registro del trabajo del técnico en un equipo cuando éste no puede usar el celular en planta.
-- Una sola transacción, con bloqueo en orden fijo (orden_servicio → os_equipo → registro_informe_intranet), que:
--   · valida el permiso (acción seg_registrar_informe), las horas, el motivo y el estado de la OS y del equipo;
--   · toma el bloqueo del equipo (registro_informe_intranet): si otra persona lo tiene con actividad en los últimos 30 min responde regla de negocio con el prefijo "[409] "
--     (la API lo convierte en HTTP 409); si su actividad es anterior a 30 min lo marca 'caducado' y lo toma;
--   · marca la LLEGADA del servicio (evento de campo con la hora de inicio, sin GPS) solo si falta, y el INICIO_TRABAJO solo si la OS aún no tiene uno (un INICIO posterior al CIERRE
--     haría que SP_ConsolidarHorasTecnicoMovil deje el día "sin cierre");
--   · pasa la OS de programada / reprogramada / en_ruta / pausada a en_ejecucion (SP_EvaluarCampoMovil solo deja operar en en_ruta, en_ejecucion o pausada);
--   · deja el equipo en proceso a nombre del técnico asignado (id_usuario_ejecucion) con el tiempo trabajado = fin − inicio (acumulado_seg) y reanudado_utc = NULL, para que
--     SP_GenerarInformeEquipoMovil (que suma ahora − reanudado_utc) no distorsione el tiempo real. Si el técnico ya había iniciado el equipo desde su app, se CONSERVA su iniciado_utc y se
--     suma su tramo en curso hasta la hora de fin (no se pisa lo que registró el técnico);
--   · guarda la sesión (horas indicadas, motivo del catálogo MOTIVO_CAMBIO_MANUAL, comentario) y la auditoría (equipo y expediente) con quién registró y en nombre de quién.
-- IDEMPOTENTE: si quien llama ya tiene el registro activo de ese equipo, solo renueva su actividad (idempotente = 1; no duplica eventos ni cambia los tiempos).
-- Horas: p_inicio_utc y p_fin_utc en UTC (la API recibe la hora de Lima y la convierte). Reglas: inicio < fin, fin no futuro (tolerancia de 5 min; se recorta a ahora), duración
--   mayor que 0 y menor de 7 días. Motivo obligatorio y del catálogo; con el motivo OTRO el comentario es obligatorio (mínimo 10 caracteres); comentario hasta 300.
-- Estados de la OS que NO permiten iniciar: anulada, borrador, emitida, bloqueada (SSOMA) y finalizada (pendiente de decisión). Del equipo: informe ya generado (usar el informe
--   complementario), completado, bloqueado, pausado esperando aprobación, fuera de los objetivos de la OS, o si el técnico tiene OTRO equipo en ejecución (pausarlo con
--   SP_PausarEquipoAbiertoIntranet).
-- Resultados: 1 mensaje (1 regla de negocio · 2 éxito · 3 error) · solo con 2: id_registro, idempotente, estado_os, estado_equipo, id_tecnico, tiempo_aplicado_min.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_IniciarRegistroIntranet;

DELIMITER $$

CREATE PROCEDURE SP_IniciarRegistroIntranet(
    IN p_id_registrador BIGINT,
    IN p_id_os          BIGINT,
    IN p_id_os_equipo   BIGINT,
    IN p_inicio_utc     DATETIME,
    IN p_fin_utc        DATETIME,
    IN p_motivo         VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_comentario     VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_ahora       DATETIME;
    DECLARE v_fin         DATETIME;
    DECLARE v_dur         BIGINT;
    DECLARE v_motivo_cod  VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_motivo_nom  VARCHAR(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_com         VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_estado_os   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_estado_nue  VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_estado_chk  VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_numero_os   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_tecnico     BIGINT       DEFAULT NULL;
    DECLARE v_exp         BIGINT       DEFAULT NULL;
    DECLARE v_id_equipo   BIGINT       DEFAULT NULL;
    DECLARE v_estado_ej   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_pausado     TINYINT      DEFAULT 0;
    DECLARE v_req_aprob   TINYINT      DEFAULT 0;
    DECLARE v_iniciado    DATETIME     DEFAULT NULL;
    DECLARE v_reanudado   DATETIME     DEFAULT NULL;
    DECLARE v_acum        INT          DEFAULT 0;
    DECLARE v_estado_eq   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_ant_txt     VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_reg_id      BIGINT       DEFAULT NULL;
    DECLARE v_reg_user    BIGINT       DEFAULT NULL;
    DECLARE v_reg_act     DATETIME     DEFAULT NULL;
    DECLARE v_reg_seg     INT          DEFAULT NULL;
    DECLARE v_reg_nombre  VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_asistente   VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_nom_tec     VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_nom_eq      VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_informe     BIGINT       DEFAULT NULL;
    DECLARE v_gen         DATETIME     DEFAULT NULL;
    DECLARE v_salida      DATETIME     DEFAULT NULL;
    DECLARE v_llegada     DATETIME     DEFAULT NULL;
    DECLARE v_hab         TINYINT      DEFAULT 0;
    DECLARE v_motivo_obj  VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_bloqueado   TINYINT      DEFAULT NULL;
    DECLARE v_otro        VARCHAR(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_tipo_lleg   INT          DEFAULT NULL;
    DECLARE v_tipo_ini    INT          DEFAULT NULL;
    DECLARE v_t_lleg      DATETIME;
    DECLARE v_hay_inicio  TINYINT      DEFAULT 0;
    DECLARE v_tiempo_seg  INT          DEFAULT 0;
    DECLARE v_id_reg      BIGINT       DEFAULT NULL;
    DECLARE v_notas       VARCHAR(1000) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_ini_txt     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_fin_txt     VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    -- ── Validaciones de entrada (antes de tocar datos) ───────────────────────────────────
    IF IFNULL(p_id_registrador, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 OR IFNULL(p_id_os_equipo, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio o equipo no encontrado.' AS Mensaje; LEAVE proc;
    END IF;
    IF FN_PermisoAccion(p_id_registrador, 'seg_registrar_informe') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para registrar informes desde la intranet.' AS Mensaje; LEAVE proc;
    END IF;
    IF p_inicio_utc IS NULL OR p_fin_utc IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Indica la hora de inicio y la de fin del trabajo en el equipo.' AS Mensaje; LEAVE proc;
    END IF;

    SET v_ahora = UTC_TIMESTAMP();
    IF p_fin_utc > v_ahora + INTERVAL 5 MINUTE THEN
        SELECT 1 AS IdTipoMensaje, 'La hora de fin no puede ser futura.' AS Mensaje; LEAVE proc;
    END IF;
    SET v_fin = LEAST(p_fin_utc, v_ahora);
    IF p_inicio_utc >= v_fin THEN
        SELECT 1 AS IdTipoMensaje, 'La hora de inicio debe ser anterior a la de fin.' AS Mensaje; LEAVE proc;
    END IF;
    SET v_dur = TIMESTAMPDIFF(SECOND, p_inicio_utc, v_fin);
    IF v_dur >= 7 * 86400 THEN
        SELECT 1 AS IdTipoMensaje, 'El trabajo en el equipo no puede durar 7 días o más.' AS Mensaje; LEAVE proc;
    END IF;

    IF NULLIF(TRIM(IFNULL(p_motivo, '')), '') IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Elige el motivo por el que se registra desde la intranet.' AS Mensaje; LEAVE proc;
    END IF;
    SELECT m.String2, m.String1 INTO v_motivo_cod, v_motivo_nom
    FROM   tabla_maestra m
    WHERE  m.Descripcion = 'MOTIVO_CAMBIO_MANUAL' AND m.IdEmpresa = 1 AND m.String2 = TRIM(p_motivo) AND m.eliminado_en IS NULL
    LIMIT 1;
    IF v_motivo_cod IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'El motivo no es válido.' AS Mensaje; LEAVE proc;
    END IF;
    SET v_com = NULLIF(TRIM(IFNULL(p_comentario, '')), '');
    IF CHAR_LENGTH(IFNULL(p_comentario, '')) > 300 THEN
        SELECT 1 AS IdTipoMensaje, 'El comentario puede tener hasta 300 caracteres.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_motivo_cod = 'OTRO' AND (v_com IS NULL OR CHAR_LENGTH(v_com) < 10) THEN
        SELECT 1 AS IdTipoMensaje, 'Cuando el motivo es "Otro" escribe un comentario (mínimo 10 caracteres).' AS Mensaje; LEAVE proc;
    END IF;

    -- ── Escritura (una transacción) ──────────────────────────────────────────────────────
    START TRANSACTION;

    SELECT os.estado, os.numero, os.id_tecnico_principal, os.id_expediente INTO v_estado_os, v_numero_os, v_tecnico, v_exp
    FROM   orden_servicio os
    WHERE  os.id_os = p_id_os AND os.eliminado_en IS NULL
    FOR UPDATE;
    IF v_estado_os IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Servicio no encontrado.' AS Mensaje; LEAVE proc;
    END IF;

    SELECT oe.id_equipo, oe.estado_ejecucion, oe.pausado, oe.pausa_requiere_aprobacion, oe.iniciado_utc, oe.reanudado_utc, oe.acumulado_seg
    INTO   v_id_equipo, v_estado_ej, v_pausado, v_req_aprob, v_iniciado, v_reanudado, v_acum
    FROM   os_equipo oe
    WHERE  oe.id = p_id_os_equipo AND oe.id_os = p_id_os AND oe.eliminado_en IS NULL
    FOR UPDATE;
    IF v_id_equipo IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'El equipo no pertenece a este servicio.' AS Mensaje; LEAVE proc;
    END IF;

    -- Estado actual del equipo (la misma lectura que SP_ArmarObjetivosMovil)
    SET v_estado_eq = CASE WHEN v_estado_ej = 'ejecutado' THEN 'completado' WHEN v_pausado = 1 THEN 'pausado' WHEN v_estado_ej = 'observado' THEN 'observado'
                           WHEN v_estado_ej = 'en_proceso' THEN 'en_ejecucion' ELSE 'por_iniciar' END;
    SET v_ant_txt = CASE v_estado_eq WHEN 'por_iniciar' THEN 'por iniciar' WHEN 'en_ejecucion' THEN 'en ejecución' ELSE v_estado_eq END;

    SELECT TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))) INTO v_asistente FROM usuario u WHERE u.id_usuario = p_id_registrador LIMIT 1;

    -- Bloqueo del equipo: una sesión activa por equipo
    SELECT r.id_registro, r.id_registrador, r.ultima_actividad, r.tiempo_aplicado_seg INTO v_reg_id, v_reg_user, v_reg_act, v_reg_seg
    FROM   registro_informe_intranet r
    WHERE  r.id_os_equipo = p_id_os_equipo AND r.estado = 'activo'
    ORDER BY r.id_registro DESC LIMIT 1
    FOR UPDATE;
    IF v_reg_id IS NOT NULL THEN
        IF v_reg_user = p_id_registrador THEN
            -- Idempotente: ya lo tenía abierto; solo se renueva la actividad
            UPDATE registro_informe_intranet SET ultima_actividad = v_ahora WHERE id_registro = v_reg_id;
            COMMIT;
            SELECT 2 AS IdTipoMensaje, 'Ya tenías abierto el registro de este equipo.' AS Mensaje;
            SELECT v_reg_id AS id_registro, 1 AS idempotente, v_estado_os AS estado_os, v_estado_eq AS estado_equipo, v_tecnico AS id_tecnico,
                   FLOOR(IFNULL(v_reg_seg, 0) / 60) AS tiempo_aplicado_min;
            LEAVE proc;
        ELSEIF v_reg_act >= v_ahora - INTERVAL 30 MINUTE THEN
            SELECT TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))) INTO v_reg_nombre FROM usuario u WHERE u.id_usuario = v_reg_user LIMIT 1;
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje,
                   CONCAT('[409] ', IFNULL(NULLIF(v_reg_nombre, ''), 'Otra persona'), ' está registrando el informe de este equipo. Inténtalo cuando termine o pasen 30 minutos sin actividad.') AS Mensaje;
            LEAVE proc;
        ELSE
            -- La sesión de la otra persona caducó (más de 30 min sin actividad): se libera y se toma
            UPDATE registro_informe_intranet SET estado = 'caducado', liberado_en = v_ahora WHERE id_registro = v_reg_id;
        END IF;
    END IF;

    -- Reglas del servicio y del equipo
    IF v_tecnico IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'El servicio no tiene un técnico asignado.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_estado_os = 'finalizada' THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'La OS ya está finalizada: esta función aún no cubre ese caso.' AS Mensaje; LEAVE proc;
    ELSEIF v_estado_os = 'anulada' THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'La OS está anulada.' AS Mensaje; LEAVE proc;
    ELSEIF v_estado_os = 'bloqueada' THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'La OS está bloqueada por SSOMA.' AS Mensaje; LEAVE proc;
    ELSEIF v_estado_os IN ('borrador', 'emitida') THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'La OS todavía no está programada ni tiene técnico asignado.' AS Mensaje; LEAVE proc;
    ELSEIF v_estado_os NOT IN ('programada', 'reprogramada', 'en_ruta', 'en_ejecucion', 'pausada') THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'El estado de la OS no permite registrar el informe.' AS Mensaje; LEAVE proc;
    END IF;

    SELECT it.id_informe, it.generado_en INTO v_informe, v_gen
    FROM   informe_tecnico it
    WHERE  it.id_os = p_id_os AND it.id_equipo = v_id_equipo AND it.eliminado_en IS NULL
    ORDER BY it.id_informe DESC LIMIT 1;
    IF v_gen IS NOT NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Este equipo ya tiene el informe generado. Para corregirlo usa el informe complementario.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_estado_eq = 'completado' THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Este equipo ya está completado.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_estado_eq = 'pausado' AND v_req_aprob = 1 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'El equipo está pausado esperando la aprobación de un supervisor.' AS Mensaje; LEAVE proc;
    END IF;

    -- Objetivos de la OS: el equipo debe ser uno de ellos y no estar bloqueado (inactivo o en evaluación). También da la llegada y la salida de la OS.
    CALL SP_ArmarObjetivosMovil(p_id_os, v_estado_chk, v_salida, v_llegada, v_hab, v_motivo_obj);
    SELECT t.bloqueado, CONCAT(IFNULL(t.codigo_cliente, IFNULL(t.num_serie, t.codigo_tw)), ' · ', IFNULL(t.nombre, 'Equipo'))
    INTO   v_bloqueado, v_nom_eq
    FROM   tmp_obj_mov t
    WHERE  t.id_os_equipo = p_id_os_equipo;
    DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
    IF v_bloqueado IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'El equipo no forma parte de los objetivos de este servicio.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_bloqueado = 1 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Este equipo está bloqueado y no se puede intervenir.' AS Mensaje; LEAVE proc;
    END IF;

    -- Un técnico trabaja en un solo equipo a la vez (la misma regla que SP_CambiarEstadoEquipoMovil)
    SELECT CONCAT(IFNULL(NULLIF(ec.codigo_cliente, ''), ec.codigo_tw), ' (', o2.numero, ')') INTO v_otro
    FROM   os_equipo x
    JOIN   equipo_cliente ec ON ec.id_equipo = x.id_equipo
    JOIN   orden_servicio o2 ON o2.id_os = x.id_os
    WHERE  x.id_usuario_ejecucion = v_tecnico AND x.estado_ejecucion = 'en_proceso' AND x.pausado = 0
      AND  x.id <> p_id_os_equipo AND x.eliminado_en IS NULL
    LIMIT 1;
    IF v_otro IS NOT NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje,
               CONCAT('El técnico ya tiene en ejecución el equipo ', v_otro, ': pausa ese equipo antes de continuar con otro.') AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))) INTO v_nom_tec FROM usuario u WHERE u.id_usuario = v_tecnico LIMIT 1;
    SET v_ini_txt = DATE_FORMAT(CONVERT_TZ(p_inicio_utc, '+00:00', '-05:00'), '%d/%m/%Y %H:%i');
    SET v_fin_txt = DATE_FORMAT(CONVERT_TZ(v_fin, '+00:00', '-05:00'), '%d/%m/%Y %H:%i');
    SET v_notas = LEFT(CONCAT('Registrado desde la intranet por ', IFNULL(v_asistente, ''), ' en nombre de ', IFNULL(v_nom_tec, ''), '. Motivo: ', v_motivo_nom,
                              IF(v_com IS NULL, '', CONCAT('. ', v_com))), 1000);

    -- LLEGADA: solo si falta (SP_EvaluarCampoMovil exige una LLEGADA posterior a la última SALIDA_BASE). Sin GPS.
    IF v_llegada IS NULL THEN
        SELECT m.Num1 INTO v_tipo_lleg FROM tabla_maestra m
        WHERE  m.IdMaestro = 29 AND m.IdEmpresa = 1 AND m.String2 = 'LLEGADA' AND m.eliminado_en IS NULL LIMIT 1;
        IF v_tipo_lleg IS NULL THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, 'El hito de campo LLEGADA no está configurado.' AS Mensaje; LEAVE proc;
        END IF;
        SET v_t_lleg = GREATEST(p_inicio_utc, IFNULL(v_salida, p_inicio_utc));
        INSERT INTO evento_campo (id_os, id_usuario, id_tipo_evento, timestamp_utc, sincronizado, notas, creado_por)
        VALUES (p_id_os, v_tecnico, v_tipo_lleg, v_t_lleg, 1, v_notas, p_id_registrador);
        UPDATE orden_servicio SET hora_llegada_real = IFNULL(hora_llegada_real, TIME(CONVERT_TZ(v_t_lleg, '+00:00', '-05:00'))) WHERE id_os = p_id_os;
    END IF;

    -- INICIO_TRABAJO: solo si la OS aún no tiene uno desde la última salida
    SELECT IF(COUNT(*) > 0, 1, 0) INTO v_hay_inicio
    FROM   evento_campo e
    JOIN   tabla_maestra m ON m.IdMaestro = 29 AND m.IdEmpresa = 1 AND m.Num1 = e.id_tipo_evento AND m.String2 = 'INICIO_TRABAJO'
    WHERE  e.id_os = p_id_os AND e.eliminado_en IS NULL AND e.timestamp_utc >= IFNULL(v_salida, '1000-01-01');
    IF v_hay_inicio = 0 THEN
        SELECT m.Num1 INTO v_tipo_ini FROM tabla_maestra m
        WHERE  m.IdMaestro = 29 AND m.IdEmpresa = 1 AND m.String2 = 'INICIO_TRABAJO' AND m.eliminado_en IS NULL LIMIT 1;
        IF v_tipo_ini IS NOT NULL THEN
            INSERT INTO evento_campo (id_os, id_usuario, id_tipo_evento, timestamp_utc, sincronizado, notas, creado_por)
            VALUES (p_id_os, v_tecnico, v_tipo_ini, p_inicio_utc, 1, v_notas, p_id_registrador);
        END IF;
    END IF;

    -- La OS pasa a "en ejecución" (SP_EvaluarCampoMovil solo deja operar en en_ruta, en_ejecucion o pausada)
    SET v_estado_nue = v_estado_os;
    IF v_estado_os IN ('programada', 'reprogramada', 'en_ruta', 'pausada') THEN
        SET v_estado_nue = 'en_ejecucion';
        UPDATE orden_servicio SET estado = 'en_ejecucion', modificado_por = p_id_registrador, modificado_en = NOW() WHERE id_os = p_id_os;
    END IF;

    -- El equipo: en proceso a nombre del técnico, con el tiempo trabajado cerrado (reanudado_utc = NULL: el generar del informe no suma nada)
    IF v_iniciado IS NULL THEN
        SET v_tiempo_seg = v_dur;
    ELSE
        SET v_tiempo_seg = v_acum + IF(v_reanudado IS NULL, 0, GREATEST(0, TIMESTAMPDIFF(SECOND, v_reanudado, v_fin)));
    END IF;
    UPDATE os_equipo
    SET    estado_ejecucion = 'en_proceso', iniciado_utc = IFNULL(iniciado_utc, p_inicio_utc), acumulado_seg = v_tiempo_seg, reanudado_utc = NULL,
           pausado = 0, motivo_pausa = NULL, pausa_requiere_aprobacion = 0, id_usuario_ejecucion = v_tecnico, modificado_por = p_id_registrador
    WHERE  id = p_id_os_equipo;

    -- La sesión (el bloqueo) con las horas y el motivo
    INSERT INTO registro_informe_intranet (id_os, id_os_equipo, id_tecnico, id_registrador, inicio_utc, fin_utc, tiempo_aplicado_seg, motivo_codigo, comentario,
                                           estado, tomado_en, ultima_actividad)
    VALUES (p_id_os, p_id_os_equipo, v_tecnico, p_id_registrador, p_inicio_utc, v_fin, v_tiempo_seg, v_motivo_cod, v_com, 'activo', v_ahora, v_ahora);
    SET v_id_reg = LAST_INSERT_ID();

    -- Auditoría: quién registró, en nombre de quién y con qué horas, en el equipo y en el historial del expediente
    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('os_equipo', p_id_os_equipo, 'iniciar_registro_intranet', v_ant_txt, 'en ejecución',
            LEFT(CONCAT(IFNULL(v_asistente, ''), ' inició desde la intranet el registro del informe de ', IFNULL(v_nom_eq, 'un equipo'), ' (', v_numero_os, ') en nombre de ',
                        IFNULL(v_nom_tec, ''), '. Trabajo del ', v_ini_txt, ' al ', v_fin_txt, ' (hora de Lima). Motivo: ', v_motivo_nom, '.'), 900),
            p_id_registrador, NOW(),
            JSON_OBJECT('idRegistro', v_id_reg, 'via', 'intranet', 'idTecnico', v_tecnico, 'idOs', p_id_os, 'inicioLima', v_ini_txt, 'finLima', v_fin_txt,
                        'motivo', v_motivo_cod, 'tiempoAplicadoSeg', v_tiempo_seg, 'estadoOsAnterior', v_estado_os));
    IF v_exp IS NOT NULL THEN
        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
        VALUES ('expediente', v_exp, 'iniciar_registro_intranet', NULL, NULL,
                LEFT(CONCAT(IFNULL(v_asistente, ''), ' inició el registro del informe de ', IFNULL(v_nom_eq, 'un equipo'), ' del servicio ', v_numero_os, ' en nombre de ',
                            IFNULL(v_nom_tec, ''), '. Motivo: ', v_motivo_nom, '.'), 900),
                p_id_registrador, NOW(), JSON_OBJECT('idRegistro', v_id_reg, 'idOs', p_id_os, 'idOsEquipo', p_id_os_equipo));
    END IF;

    COMMIT;

    SELECT 2 AS IdTipoMensaje, 'Registro iniciado.' AS Mensaje;
    SELECT v_id_reg AS id_registro, 0 AS idempotente, v_estado_nue AS estado_os, 'en_ejecucion' AS estado_equipo, v_tecnico AS id_tecnico,
           FLOOR(v_tiempo_seg / 60) AS tiempo_aplicado_min;
END$$

DELIMITER ;

-- ============================================================
-- SP_LiberarRegistroIntranet  (HU-55 — cerrar o soltar el registro del informe de un equipo desde la intranet · escritura)
-- Libera el bloqueo del equipo que tiene quien llama: la sesión activa pasa a 'cerrado' si el informe del equipo ya se generó (la API lo llama justo después de generar) o a 'liberado'
-- si no (la persona suelta el equipo sin terminar). No cambia el estado del equipo ni de la OS: un equipo liberado sin informe queda en proceso con su tiempo ya cerrado
-- (reanudado_utc = NULL) y se puede retomar con SP_IniciarRegistroIntranet, o pausar con SP_PausarEquipoAbiertoIntranet.
-- Idempotente: si quien llama no tenía una sesión activa de ese equipo, responde éxito sin cambiar nada. Solo se puede liberar la sesión propia.
-- Resultados: 1 mensaje (1 regla de negocio · 2 éxito · 3 error).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_LiberarRegistroIntranet;

DELIMITER $$

CREATE PROCEDURE SP_LiberarRegistroIntranet(
    IN p_id_registrador BIGINT,
    IN p_id_os          BIGINT,
    IN p_id_os_equipo   BIGINT
)
proc: BEGIN
    DECLARE v_generado TINYINT DEFAULT 0;
    DECLARE v_filas    INT     DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_registrador, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 OR IFNULL(p_id_os_equipo, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio o equipo no encontrado.' AS Mensaje; LEAVE proc;
    END IF;
    IF FN_PermisoAccion(p_id_registrador, 'seg_registrar_informe') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para registrar informes desde la intranet.' AS Mensaje; LEAVE proc;
    END IF;

    SELECT IF(COUNT(*) > 0, 1, 0) INTO v_generado
    FROM   informe_tecnico it
    JOIN   os_equipo oe ON oe.id = p_id_os_equipo AND oe.id_os = p_id_os AND oe.id_equipo = it.id_equipo
    WHERE  it.id_os = p_id_os AND it.generado_en IS NOT NULL AND it.eliminado_en IS NULL;

    UPDATE registro_informe_intranet
    SET    estado = IF(v_generado = 1, 'cerrado', 'liberado'), liberado_en = UTC_TIMESTAMP()
    WHERE  id_os = p_id_os AND id_os_equipo = p_id_os_equipo AND id_registrador = p_id_registrador AND estado = 'activo';
    SET v_filas = ROW_COUNT();

    SELECT 2 AS IdTipoMensaje, IF(v_filas > 0, 'Registro liberado.', 'No había un registro abierto de este equipo.') AS Mensaje;
END$$

DELIMITER ;

-- ============================================================
-- SP_MarcarRegistroInformeIntranet  (HU-55 — estampa quién registró el informe desde la intranet · escritura)
-- La API la llama después de cada escritura que crea o cambia el informe del equipo (ensayos, cabecera, foto de falla y generar): deja en informe_tecnico
--   id_registrado_por = quien registra (si registraron dos personas en distintos momentos, queda la última), via = 'intranet' y registrado_en = la PRIMERA vez (UTC).
-- El informe sigue a nombre del técnico (id_tecnico no se toca). NO cambia el `origen` de las tablas hijas. Si el equipo aún no tiene informe (p. ej. solo se guardaron las variables
-- ambientales o fotos), no hace nada y responde éxito: la siguiente llamada, cuando el informe exista, lo estampa.
-- Resultados: 1 mensaje (1 regla de negocio · 2 éxito · 3 error).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_MarcarRegistroInformeIntranet;

DELIMITER $$

CREATE PROCEDURE SP_MarcarRegistroInformeIntranet(
    IN p_id_registrador BIGINT,
    IN p_id_os          BIGINT,
    IN p_id_os_equipo   BIGINT
)
proc: BEGIN
    DECLARE v_id_equipo BIGINT DEFAULT NULL;
    DECLARE v_informe   BIGINT DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_registrador, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 OR IFNULL(p_id_os_equipo, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio o equipo no encontrado.' AS Mensaje; LEAVE proc;
    END IF;
    IF FN_PermisoAccion(p_id_registrador, 'seg_registrar_informe') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para registrar informes desde la intranet.' AS Mensaje; LEAVE proc;
    END IF;

    SELECT oe.id_equipo INTO v_id_equipo FROM os_equipo oe WHERE oe.id = p_id_os_equipo AND oe.id_os = p_id_os AND oe.eliminado_en IS NULL;
    IF v_id_equipo IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'El equipo no pertenece a este servicio.' AS Mensaje; LEAVE proc;
    END IF;

    SELECT it.id_informe INTO v_informe
    FROM   informe_tecnico it
    WHERE  it.id_os = p_id_os AND it.id_equipo = v_id_equipo AND it.eliminado_en IS NULL
    ORDER BY it.id_informe DESC LIMIT 1;

    IF v_informe IS NOT NULL THEN
        UPDATE informe_tecnico
        SET    id_registrado_por = p_id_registrador, via = 'intranet', registrado_en = IFNULL(registrado_en, UTC_TIMESTAMP())
        WHERE  id_informe = v_informe;
    END IF;

    SELECT 2 AS IdTipoMensaje, IF(v_informe IS NULL, 'El equipo aún no tiene informe: nada que marcar.', 'Informe marcado como registrado desde la intranet.') AS Mensaje;
END$$

DELIMITER ;

-- ============================================================
-- SP_AjustarTiempoEquipoIntranet  (HU-55 — fija el tiempo trabajado del equipo justo antes de generar el informe · escritura)
-- SP_GenerarInformeEquipoMovil cierra el tiempo del equipo sumando (ahora − reanudado_utc). En un registro desde la intranet el tiempo trabajado es el que indicó quien registra
-- (SP_IniciarRegistroIntranet lo dejó en registro_informe_intranet.tiempo_aplicado_seg): esta ayuda reafirma os_equipo.acumulado_seg = ese tiempo y reanudado_utc = NULL para que
-- el generar sume 0. La API la llama justo antes de POST informe. No cambia el estado del equipo (sigue en proceso, que es lo que exige el generar).
-- Exige la sesión ACTIVA PROPIA de ese equipo (si no: "Primero inicia el registro de este equipo.").
-- Resultados: 1 mensaje (1 regla de negocio · 2 éxito · 3 error).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_AjustarTiempoEquipoIntranet;

DELIMITER $$

CREATE PROCEDURE SP_AjustarTiempoEquipoIntranet(
    IN p_id_registrador BIGINT,
    IN p_id_os          BIGINT,
    IN p_id_os_equipo   BIGINT
)
proc: BEGIN
    DECLARE v_reg_id  BIGINT DEFAULT NULL;
    DECLARE v_seg     INT    DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_registrador, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 OR IFNULL(p_id_os_equipo, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio o equipo no encontrado.' AS Mensaje; LEAVE proc;
    END IF;
    IF FN_PermisoAccion(p_id_registrador, 'seg_registrar_informe') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para registrar informes desde la intranet.' AS Mensaje; LEAVE proc;
    END IF;

    START TRANSACTION;

    SELECT r.id_registro, r.tiempo_aplicado_seg INTO v_reg_id, v_seg
    FROM   registro_informe_intranet r
    WHERE  r.id_os = p_id_os AND r.id_os_equipo = p_id_os_equipo AND r.id_registrador = p_id_registrador AND r.estado = 'activo'
    ORDER BY r.id_registro DESC LIMIT 1
    FOR UPDATE;
    IF v_reg_id IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Primero inicia el registro de este equipo.' AS Mensaje; LEAVE proc;
    END IF;

    IF v_seg IS NOT NULL THEN
        UPDATE os_equipo
        SET    acumulado_seg = v_seg, reanudado_utc = NULL, modificado_por = p_id_registrador
        WHERE  id = p_id_os_equipo AND id_os = p_id_os AND eliminado_en IS NULL;
    END IF;

    COMMIT;
    SELECT 2 AS IdTipoMensaje, 'Tiempo del equipo ajustado.' AS Mensaje;
END$$

DELIMITER ;

-- ============================================================
-- SP_ForzarEvidenciaIntranet  (HU-55 — forzar una evidencia que la IA rechazó, desde la intranet · escritura)
-- Copia ADAPTADA de SP_ForzarEvidenciaMovil (que no se toca) para quien registra el informe en nombre del técnico:
--   - El técnico se resuelve dentro (orden_servicio.id_tecnico_principal) y el acceso móvil (OS del técnico, llegada, equipo EN EJECUCIÓN) lo valida SP_ContextoEquipoMovil con ese técnico.
--     Acción seg_registrar_informe (FN_PermisoAccion).
--   - Solo con un MOTIVO ESCRITO (3 a 300 caracteres), solo la última captura vigente y solo si está rechazada. Repetirlo sobre una ya forzada responde éxito sin duplicar nada.
--   - Marca la evidencia FORZADA (override_aprobado = 1) con el motivo, quién la forzó (id_usuario_override = QUIEN REGISTRA, no el técnico) y cuándo.
--   - NO suma foto_override_count al scorecard del técnico (la decisión no es suya), a diferencia del SP móvil.
--   - Deja el forzado en auditoria_evento (con quién, en nombre de quién y via = intranet) y avisa a Jefatura igual que el SP móvil (Área + Rol, SP_ArmarAprobadoresOsMovil; si no hay, el
--     encargado del área según la RQ; si tampoco, los administradores), sin avisar a quien registra.
-- Resultados: 1 mensaje; 2 (id_evidencia, forzada_en en Lima, intentos_previos, notificados) — los mismos que SP_ForzarEvidenciaMovil.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ForzarEvidenciaIntranet;

DELIMITER $$

CREATE PROCEDURE SP_ForzarEvidenciaIntranet(
    IN p_id_registrador BIGINT,
    IN p_id_os          BIGINT,
    IN p_id_os_equipo   BIGINT,
    IN p_id_evidencia   BIGINT,
    IN p_motivo         VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_msg      VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tecnico  BIGINT       DEFAULT NULL;
    DECLARE v_id_eq    BIGINT;
    DECLARE v_est_eq   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_hab      TINYINT;
    DECLARE v_numero   INT;
    DECLARE v_nombre   VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_num_os   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_servicio VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_motivo   VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_codigo   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_valida   VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_ya       TINYINT DEFAULT 0;
    DECLARE v_vigente  TINYINT DEFAULT 0;
    DECLARE v_intento  INT DEFAULT 1;
    DECLARE v_motivo_ia VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_forzada  DATETIME DEFAULT NULL;
    DECLARE v_area     VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_enc   BIGINT;
    DECLARE v_nom_enc  VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_car_enc  VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tel_enc  VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_nom_reg  VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_nom_tec  VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_texto    VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_notif    INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov, tmp_aprobadores;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_registrador, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 OR IFNULL(p_id_os_equipo, 0) <= 0 OR IFNULL(p_id_evidencia, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Evidencia no encontrada.' AS Mensaje; LEAVE proc;
    END IF;
    IF FN_PermisoAccion(p_id_registrador, 'seg_registrar_informe') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para registrar informes desde la intranet.' AS Mensaje; LEAVE proc;
    END IF;
    SET v_motivo = NULLIF(TRIM(IFNULL(p_motivo, '')), '');
    IF v_motivo IS NULL OR CHAR_LENGTH(v_motivo) < 3 THEN
        SELECT 1 AS IdTipoMensaje, 'Escribe el motivo por el que se acepta la foto (mínimo 3 caracteres).' AS Mensaje; LEAVE proc;
    END IF;
    IF CHAR_LENGTH(v_motivo) > 300 THEN
        SELECT 1 AS IdTipoMensaje, 'El motivo puede tener hasta 300 caracteres.' AS Mensaje; LEAVE proc;
    END IF;

    SELECT os.id_tecnico_principal INTO v_tecnico FROM orden_servicio os WHERE os.id_os = p_id_os AND os.eliminado_en IS NULL;
    IF v_tecnico IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio no encontrado o sin técnico asignado.' AS Mensaje; LEAVE proc;
    END IF;

    START TRANSACTION;

    CALL SP_ContextoEquipoMovil(v_tecnico, p_id_os, p_id_os_equipo, v_msg, v_id_eq, v_est_eq, v_hab, v_numero, v_nombre, v_num_os, v_servicio);
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

    SELECT TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))) INTO v_nom_reg FROM usuario u WHERE u.id_usuario = p_id_registrador LIMIT 1;
    SELECT TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))) INTO v_nom_tec FROM usuario u WHERE u.id_usuario = v_tecnico LIMIT 1;

    -- Quien fuerza es QUIEN REGISTRA; el scorecard del técnico NO se toca
    SET v_forzada = UTC_TIMESTAMP();
    UPDATE evidencia_fotografica
    SET    override_aprobado = 1, id_usuario_override = p_id_registrador, motivo_forzado = v_motivo, forzada_en = v_forzada, modificado_por = p_id_registrador
    WHERE  id_evidencia = p_id_evidencia;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('os_equipo', p_id_os_equipo, 'forzar_evidencia', 'rechazada', 'forzada',
            LEFT(CONCAT('Evidencia ', v_codigo, ' de ', v_num_os, ' aceptada a la fuerza tras ', v_intento, IF(v_intento = 1, ' intento', ' intentos'),
                        ' desde la intranet por ', IFNULL(v_nom_reg, ''), ' en nombre del técnico ', IFNULL(v_nom_tec, ''),
                        '. Rechazo de la IA: ', IFNULL(v_motivo_ia, '—'), '. Motivo: ', v_motivo), 900),
            p_id_registrador, NOW(),
            JSON_OBJECT('id_evidencia', p_id_evidencia, 'codigo', v_codigo, 'intentos', v_intento, 'motivo', v_motivo, 'motivo_ia', v_motivo_ia,
                        'via', 'intranet', 'id_registrador', p_id_registrador, 'id_tecnico', v_tecnico));

    -- Visible para Jefatura (igual que el SP móvil): aviso al encargado del área (si no hay, a los administradores); nunca a quien registra
    CALL SP_ContactoEncargadoEnsayoMovil(p_id_os, v_area, v_id_enc, v_nom_enc, v_car_enc, v_tel_enc);
    SET v_texto = LEFT(CONCAT(IFNULL(v_nom_reg, ''), ' (desde la intranet, en nombre de ', IFNULL(v_nom_tec, ''), ') aceptó a la fuerza la evidencia «', v_codigo, '» de ', v_nombre,
                              ' (', v_num_os, '), rechazada por la IA. Motivo: ', v_motivo), 500);
    CALL SP_ArmarAprobadoresOsMovil(p_id_os);
    INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
    SELECT a.id_usuario, 5, 'Evidencia forzada', v_texto, 'orden_servicio', p_id_os, NOW(), p_id_registrador
    FROM   tmp_aprobadores a
    WHERE  a.id_usuario <> p_id_registrador;
    SET v_notif = ROW_COUNT();
    DROP TEMPORARY TABLE IF EXISTS tmp_aprobadores;
    IF v_notif > 0 THEN
        SET v_notif = v_notif;
    ELSEIF v_id_enc IS NOT NULL AND v_id_enc <> p_id_registrador THEN
        INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
        VALUES (v_id_enc, 5, 'Evidencia forzada', v_texto, 'orden_servicio', p_id_os, NOW(), p_id_registrador);
        SET v_notif = 1;
    ELSE
        INSERT INTO notificacion (id_usuario_destino, id_canal, titulo, cuerpo, entidad_tipo, id_entidad, fecha_creacion, creado_por)
        SELECT u.id_usuario, 5, 'Evidencia forzada', v_texto, 'orden_servicio', p_id_os, NOW(), p_id_registrador
        FROM   usuario u
        WHERE  u.eliminado_en IS NULL AND u.estado = 'activo' AND u.id_usuario <> p_id_registrador AND u.rol_sistema IN ('administrador', 'admin');
        SET v_notif = ROW_COUNT();
    END IF;

    COMMIT;

    SELECT 2 AS IdTipoMensaje, 'Foto aceptada como evidencia forzada: quedó registrada y visible para Jefatura.' AS Mensaje;
    SELECT p_id_evidencia AS id_evidencia, CONVERT_TZ(v_forzada, '+00:00', '-05:00') AS forzada_en, v_intento - 1 AS intentos_previos, v_notif AS notificados;
END$$

DELIMITER ;

-- ============================================================
-- SP_PausarEquipoAbiertoIntranet  (HU-55 — pausar el OTRO equipo que el técnico dejó en ejecución · escritura)
-- Un técnico solo puede tener un equipo en ejecución a la vez (SP_CambiarEstadoEquipoMovil). Si SP_IniciarRegistroIntranet responde que el técnico ya tiene otro equipo abierto,
-- quien registra lo pausa con este SP (en la OS que sea) y vuelve a iniciar el registro. p_id_os / p_id_os_equipo son el servicio y el equipo que se quiere registrar: de la OS sale el
-- técnico; el equipo a pausar es el OTRO en proceso y sin pausa de ese técnico (p_id_os_equipo se excluye).
-- Es una COPIA de la rama «pausar» de SP_CambiarEstadoEquipoMovil (que no se llama: su resultado se mezclaría con el de este SP y exige la llegada del otro servicio): cierra el
-- tramo de tiempo (acumulado_seg += ahora − reanudado_utc), deja pausado = 1 con el motivo, registra el evento de campo PAUSA a nombre del técnico (creado_por = quien registra) y la
-- auditoría. La pausa NO requiere aprobación. Motivo obligatorio (3 a 200 caracteres); en la pausa se guarda «Pausado desde la intranet por <quien registra>: <motivo>».
-- Acción seg_registrar_informe (FN_PermisoAccion).
-- Resultados: 1 mensaje (1 regla de negocio · 2 éxito · 3 error) · solo con 2: id_os, id_os_equipo, nombre (el equipo pausado).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_PausarEquipoAbiertoIntranet;

DELIMITER $$

CREATE PROCEDURE SP_PausarEquipoAbiertoIntranet(
    IN p_id_registrador BIGINT,
    IN p_id_os          BIGINT,
    IN p_id_os_equipo   BIGINT,
    IN p_motivo         VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_motivo    VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_motivo_p  VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_tecnico   BIGINT       DEFAULT NULL;
    DECLARE v_otro_id   BIGINT       DEFAULT NULL;
    DECLARE v_otro_os   BIGINT       DEFAULT NULL;
    DECLARE v_otro_num  VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_otro_nom  VARCHAR(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_en_proc   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_pausado   TINYINT      DEFAULT 0;
    DECLARE v_ahora     DATETIME;
    DECLARE v_tipo_evt  INT          DEFAULT NULL;
    DECLARE v_nom_reg   VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_registrador, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 OR IFNULL(p_id_os_equipo, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio o equipo no encontrado.' AS Mensaje; LEAVE proc;
    END IF;
    IF FN_PermisoAccion(p_id_registrador, 'seg_registrar_informe') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para registrar informes desde la intranet.' AS Mensaje; LEAVE proc;
    END IF;
    SET v_motivo = NULLIF(TRIM(IFNULL(p_motivo, '')), '');
    IF v_motivo IS NULL OR CHAR_LENGTH(v_motivo) < 3 THEN
        SELECT 1 AS IdTipoMensaje, 'Indica el motivo de la pausa (mínimo 3 caracteres).' AS Mensaje; LEAVE proc;
    END IF;
    IF CHAR_LENGTH(IFNULL(p_motivo, '')) > 200 THEN
        SELECT 1 AS IdTipoMensaje, 'El motivo puede tener hasta 200 caracteres.' AS Mensaje; LEAVE proc;
    END IF;

    SELECT os.id_tecnico_principal INTO v_tecnico FROM orden_servicio os WHERE os.id_os = p_id_os AND os.eliminado_en IS NULL;
    IF v_tecnico IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio no encontrado o sin técnico asignado.' AS Mensaje; LEAVE proc;
    END IF;

    START TRANSACTION;

    -- El otro equipo abierto del técnico (la misma condición que la regla "un solo equipo a la vez")
    SELECT x.id, x.id_os, o2.numero, CONCAT(IFNULL(NULLIF(ec.codigo_cliente, ''), ec.codigo_tw), ' (', o2.numero, ')')
    INTO   v_otro_id, v_otro_os, v_otro_num, v_otro_nom
    FROM   os_equipo x
    JOIN   equipo_cliente ec ON ec.id_equipo = x.id_equipo
    JOIN   orden_servicio o2 ON o2.id_os = x.id_os
    WHERE  x.id_usuario_ejecucion = v_tecnico AND x.estado_ejecucion = 'en_proceso' AND x.pausado = 0
      AND  x.id <> p_id_os_equipo AND x.eliminado_en IS NULL
    LIMIT 1;
    IF v_otro_id IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'No hay otro equipo en ejecución.' AS Mensaje; LEAVE proc;
    END IF;

    -- Se bloquea la fila y se vuelve a leer (otro envío pudo pausarlo entre tanto)
    SELECT oe.estado_ejecucion, oe.pausado INTO v_en_proc, v_pausado FROM os_equipo oe WHERE oe.id = v_otro_id FOR UPDATE;
    IF v_en_proc <> 'en_proceso' OR v_pausado = 1 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'No hay otro equipo en ejecución.' AS Mensaje; LEAVE proc;
    END IF;

    SET v_ahora = UTC_TIMESTAMP();
    SELECT TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))) INTO v_nom_reg FROM usuario u WHERE u.id_usuario = p_id_registrador LIMIT 1;
    SET v_motivo_p = LEFT(CONCAT('Pausado desde la intranet por ', IFNULL(v_nom_reg, ''), ': ', v_motivo), 300);

    UPDATE os_equipo
    SET    acumulado_seg = acumulado_seg + IF(reanudado_utc IS NULL, 0, GREATEST(0, TIMESTAMPDIFF(SECOND, reanudado_utc, v_ahora))),
           reanudado_utc = NULL, pausado = 1, motivo_pausa = v_motivo_p, pausa_requiere_aprobacion = 0, modificado_por = p_id_registrador
    WHERE  id = v_otro_id;

    SELECT m.Num1 INTO v_tipo_evt FROM tabla_maestra m
    WHERE  m.IdMaestro = 29 AND m.IdEmpresa = 1 AND m.String2 = 'PAUSA' AND m.eliminado_en IS NULL LIMIT 1;
    IF v_tipo_evt IS NOT NULL THEN
        INSERT INTO evento_campo (id_os, id_usuario, id_tipo_evento, timestamp_utc, sincronizado, notas, creado_por)
        VALUES (v_otro_os, v_tecnico, v_tipo_evt, v_ahora, 1, LEFT(CONCAT('Pausa en ', v_otro_nom, '. Motivo: ', v_motivo_p), 1000), p_id_registrador);
    END IF;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('os_equipo', v_otro_id, 'pausar_equipo', 'en ejecución', 'pausado', LEFT(CONCAT('Pausa: ', v_motivo_p), 300), p_id_registrador, NOW(),
            JSON_OBJECT('id_os', v_otro_os, 'accion', 'pausar', 'via', 'intranet', 'idTecnico', v_tecnico, 'idRegistrador', p_id_registrador));

    COMMIT;

    SELECT 2 AS IdTipoMensaje, 'Equipo pausado.' AS Mensaje;
    SELECT v_otro_os AS id_os, v_otro_id AS id_os_equipo, v_otro_nom AS nombre;
END$$

DELIMITER ;

-- ============================================================
-- VERIFICACIÓN (solo lectura: no crea datos)
-- ============================================================
SELECT 'Migración 127 (debe ser 6)' AS verificacion,
       (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'informe_tecnico' AND COLUMN_NAME IN ('id_registrado_por', 'via', 'registrado_en'))
     + (SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'registro_informe_intranet')
     + (SELECT COUNT(*) FROM tabla_maestra WHERE Descripcion = 'MOTIVO_CAMBIO_MANUAL' AND IdEmpresa = 1 AND String2 = 'PLANTA_SIN_CELULAR')
     + (SELECT COUNT(*) FROM tabla_maestra WHERE IdMaestro = 88 AND IdEmpresa = 1 AND String2 = 'seg_registrar_informe') AS valor
UNION ALL
SELECT 'Procedimientos de la HU-55 (deben ser 8)',
       (SELECT COUNT(*) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = DATABASE()
          AND ROUTINE_NAME IN ('SP_AutorizarRegistroIntranet', 'SP_ContextoRegistroIntranet', 'SP_IniciarRegistroIntranet', 'SP_LiberarRegistroIntranet',
                               'SP_MarcarRegistroInformeIntranet', 'SP_AjustarTiempoEquipoIntranet', 'SP_ForzarEvidenciaIntranet', 'SP_PausarEquipoAbiertoIntranet'))
UNION ALL
SELECT 'Todos validan la acción seg_registrar_informe (deben ser 8)',
       (SELECT COUNT(*) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = DATABASE() AND ROUTINE_DEFINITION LIKE '%seg_registrar_informe%'
          AND ROUTINE_NAME IN ('SP_AutorizarRegistroIntranet', 'SP_ContextoRegistroIntranet', 'SP_IniciarRegistroIntranet', 'SP_LiberarRegistroIntranet',
                               'SP_MarcarRegistroInformeIntranet', 'SP_AjustarTiempoEquipoIntranet', 'SP_ForzarEvidenciaIntranet', 'SP_PausarEquipoAbiertoIntranet'))
UNION ALL
SELECT 'Iniciar registro toma el bloqueo y avisa el 409 (debe ser 1)',
       (SELECT COUNT(*) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = DATABASE() AND ROUTINE_NAME = 'SP_IniciarRegistroIntranet'
          AND ROUTINE_DEFINITION LIKE '%registro_informe_intranet%' AND ROUTINE_DEFINITION LIKE '%[409] %')
UNION ALL
SELECT 'Forzar de intranet NO toca el scorecard (debe ser 1)',
       (SELECT COUNT(*) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = DATABASE() AND ROUTINE_NAME = 'SP_ForzarEvidenciaIntranet'
          AND ROUTINE_DEFINITION NOT LIKE '%INSERT INTO tecnico_scorecard%' AND ROUTINE_DEFINITION NOT LIKE '%UPDATE tecnico_scorecard%')
UNION ALL
SELECT 'Los SP móviles no cambiaron de firma: ContextoEquipo y CambiarEstadoEquipo siguen sin parámetros de intranet (debe ser 2)',
       (SELECT COUNT(*) FROM information_schema.ROUTINES r WHERE r.ROUTINE_SCHEMA = DATABASE() AND r.ROUTINE_NAME IN ('SP_ContextoEquipoMovil', 'SP_CambiarEstadoEquipoMovil')
          AND NOT EXISTS (SELECT 1 FROM information_schema.PARAMETERS p
                          WHERE p.SPECIFIC_SCHEMA = r.ROUTINE_SCHEMA AND p.SPECIFIC_NAME = r.ROUTINE_NAME
                            AND (p.PARAMETER_NAME LIKE '%registrador%' OR p.PARAMETER_NAME LIKE '%intranet%')));
