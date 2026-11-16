-- HU-22: ingreso de equipos de la OS. Ejecutar con Alt+X (No al aviso) y reiniciar la API.
-- ============================================================
-- Migración 117 — Ingreso de equipos de la OS desde la app móvil (App Mobile HU-22)
--   1. os_equipo_ingreso: el ingreso formal de un equipo de la OS (estado de ingreso: operativo, operativo con observaciones o inoperativo;
--      observación obligatoria si no está operativo). Un equipo se ingresa UNA sola vez en la misma OS (lo controla SP_RegistrarIngresoEquipoMovil).
--   2. os_equipo_ingreso_foto: fotos de evidencia (solo cámara) del ingreso con observaciones o inoperativo.
--   No cambia datos existentes. IDEMPOTENTE.
-- ============================================================

CREATE TABLE IF NOT EXISTS os_equipo_ingreso (
    id              BIGINT       NOT NULL AUTO_INCREMENT,
    id_os           BIGINT       NOT NULL,
    id_os_equipo    BIGINT       NOT NULL,
    estado_ingreso  ENUM('operativo','con_observaciones','inoperativo') NOT NULL,
    observacion     VARCHAR(500) NULL,
    ingresado_utc   DATETIME     NOT NULL,
    id_usuario      BIGINT       NOT NULL,
    creado_en       DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    eliminado_en    DATETIME     NULL,
    PRIMARY KEY (id),
    KEY ix_ingreso_os (id_os),
    KEY ix_ingreso_os_equipo (id_os_equipo)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS os_equipo_ingreso_foto (
    id          BIGINT       NOT NULL AUTO_INCREMENT,
    id_ingreso  BIGINT       NOT NULL,
    orden       INT          NOT NULL,
    ruta        VARCHAR(500) NOT NULL,
    creado_en   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY ix_ingreso_foto (id_ingreso)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ============================================================
-- SP_ObtenerIngresosEquiposMovil  (App Mobile HU-22 — Ingreso de equipos (OS) · lectura)
-- Ingresos ya registrados de los equipos de una OS del técnico (la lista de equipos sale de SP_ObtenerObjetivosMovil).
--   - El técnico sale del token; la OS debe ser suya.
-- Resultados: 1 mensaje · 2 una fila por equipo ingresado (id_os_equipo, estado_ingreso, observacion, ingresado_en en hora de Lima, fotos).
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerIngresosEquiposMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerIngresosEquiposMovil(
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

    SELECT i.id_os_equipo,
           i.estado_ingreso,
           i.observacion,
           CONVERT_TZ(i.ingresado_utc, '+00:00', '-05:00') AS ingresado_en,
           (SELECT COUNT(*) FROM os_equipo_ingreso_foto f WHERE f.id_ingreso = i.id) AS fotos
    FROM   os_equipo_ingreso i
    WHERE  i.id_os = p_id_os AND i.eliminado_en IS NULL
    ORDER BY i.id;
END$$

DELIMITER ;

-- ============================================================
-- SP_AgregarEquipoExistenteOsMovil  (App Mobile HU-22 — agregar a la OS un equipo YA REGISTRADO escaneando su QR / código · escritura)
-- El técnico escanea el QR de un equipo que existe en el maestro del cliente pero NO está en la lista de la OS: se agrega como objetivo de esta OS.
--   - El técnico sale del token; la OS debe ser suya. Hard Stop (HU-06): solo con la llegada registrada y la OS en curso (SP_EvaluarCampoMovil).
--   - El equipo se busca por COD TW, código del cliente o N/S (sin distinguir mayúsculas), por una URL que traiga su COD TW / código (5 o más caracteres)
--     o por la etiqueta QR de TW ya vinculada al equipo (equipo_qr). Debe ser del MISMO cliente de la OS.
--   - No se agregan equipos inactivos ni en evaluación (bloqueados) ni en borrador (pendientes de validar). Si ya está en la lista de la OS, se avisa.
--   - Queda con el mismo tipo de intervención que los demás objetivos de la OS, al final de la lista, "por iniciar". Auditoría en auditoria_evento.
--   - Si el código no corresponde a ningún equipo del cliente, la app ofrece registrarlo como equipo nuevo (NEW, con foto de la placa).
-- Resultados: 1 mensaje; 2 (id_os_equipo, id_equipo, codigo_tw).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_AgregarEquipoExistenteOsMovil;

DELIMITER $$

CREATE PROCEDURE SP_AgregarEquipoExistenteOsMovil(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT,
    IN p_codigo     VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_codigo      VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_clave       VARCHAR(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_estado_os   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_numero_os   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_cliente  BIGINT;
    DECLARE v_salida_utc  DATETIME;
    DECLARE v_llegada_utc DATETIME;
    DECLARE v_habilitado  TINYINT;
    DECLARE v_motivo_no   VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_equipo   BIGINT DEFAULT NULL;
    DECLARE v_id_cli_eq   BIGINT DEFAULT NULL;
    DECLARE v_codigo_tw   VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_activo      TINYINT DEFAULT 1;
    DECLARE v_estado_eq   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_oper        VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_tipo_interv INT DEFAULT NULL;
    DECLARE v_orden       INT DEFAULT 1;
    DECLARE v_id_oe       BIGINT DEFAULT NULL;

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
    SET v_codigo = UPPER(TRIM(IFNULL(p_codigo, '')));
    IF CHAR_LENGTH(v_codigo) = 0 OR CHAR_LENGTH(v_codigo) > 300 THEN
        SELECT 1 AS IdTipoMensaje, 'El código escaneado no es válido.' AS Mensaje;
        LEAVE proc;
    END IF;

    START TRANSACTION;

    SELECT os.estado, os.numero, os.id_cliente INTO v_estado_os, v_numero_os, v_id_cliente
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

    CALL SP_EvaluarCampoMovil(p_id_os, v_estado_os, v_salida_utc, v_llegada_utc, v_habilitado, v_motivo_no);
    IF v_habilitado = 0 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, v_motivo_no AS Mensaje;
        LEAVE proc;
    END IF;

    -- Etiqueta QR de TW (enlace corto): se reconoce si ya está vinculada a un equipo
    CALL SP_NormalizarQrMovil(p_codigo, v_clave);

    -- Primero entre los equipos del cliente de la OS (la coincidencia exacta gana sobre la que solo contiene el código)
    SELECT ec.id_equipo, ec.codigo_tw, ec.id_cliente, IF(ec.es_activo = 0 OR ec.estado = 'inactivo' OR ec.estado_operativo = 'evaluacion', 0, 1), ec.estado
    INTO   v_id_equipo, v_codigo_tw, v_id_cli_eq, v_activo, v_estado_eq
    FROM   equipo_cliente ec
    WHERE  ec.SoftDelete = 0 AND ec.id_cliente = v_id_cliente
      AND  (UPPER(ec.codigo_tw) = v_codigo OR UPPER(ec.codigo_cliente) = v_codigo OR UPPER(ec.num_serie) = v_codigo
            OR (CHAR_LENGTH(IFNULL(ec.codigo_tw, '')) >= 5 AND LOCATE(UPPER(ec.codigo_tw), v_codigo) > 0)
            OR (CHAR_LENGTH(IFNULL(ec.codigo_cliente, '')) >= 5 AND LOCATE(UPPER(ec.codigo_cliente), v_codigo) > 0)
            OR (v_clave IS NOT NULL AND ec.id_equipo IN (SELECT q.id_equipo FROM equipo_qr q WHERE q.clave = v_clave AND q.eliminado_en IS NULL)))
    ORDER BY (UPPER(ec.codigo_tw) = v_codigo OR UPPER(ec.codigo_cliente) = v_codigo OR UPPER(ec.num_serie) = v_codigo) DESC, ec.id_equipo
    LIMIT 1;

    IF v_id_equipo IS NULL THEN
        -- ¿Existe, pero es de otro cliente?
        IF EXISTS (SELECT 1 FROM equipo_cliente ec
                   WHERE ec.SoftDelete = 0 AND (UPPER(ec.codigo_tw) = v_codigo OR UPPER(ec.codigo_cliente) = v_codigo OR UPPER(ec.num_serie) = v_codigo)) THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, 'Ese equipo pertenece a otro cliente: no se puede agregar a esta OS.' AS Mensaje;
        ELSE
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, 'El código no corresponde a ningún equipo registrado de este cliente. Regístralo como equipo nuevo (NEW).' AS Mensaje;
        END IF;
        LEAVE proc;
    END IF;

    IF v_activo = 0 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, CONCAT(v_codigo_tw, ' está inactivo o en evaluación: no se puede agregar a la OS.') AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_estado_eq = 'borrador' THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, CONCAT(v_codigo_tw, ' está pendiente de validar en la intranet: aún no se puede agregar a otra OS.') AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT oe.id INTO v_id_oe FROM os_equipo oe WHERE oe.id_os = p_id_os AND oe.id_equipo = v_id_equipo AND oe.eliminado_en IS NULL LIMIT 1;
    IF v_id_oe IS NOT NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, CONCAT(v_codigo_tw, ' ya está en la lista de esta OS: búscalo y selecciónalo.') AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT oe.id_tipo_intervencion INTO v_tipo_interv
    FROM   os_equipo oe
    WHERE  oe.id_os = p_id_os AND oe.eliminado_en IS NULL AND oe.id_tipo_intervencion IS NOT NULL
    ORDER BY oe.id LIMIT 1;
    SELECT IFNULL(MAX(IFNULL(oe.orden, oe.id)), 0) + 1 INTO v_orden
    FROM   os_equipo oe WHERE oe.id_os = p_id_os AND oe.eliminado_en IS NULL;

    INSERT INTO os_equipo (id_os, id_equipo, id_tipo_intervencion, orden, ingresado_en_campo, estado_ejecucion, creado_por)
    VALUES (p_id_os, v_id_equipo, v_tipo_interv, v_orden, 0, 'pendiente', p_id_usuario);
    SET v_id_oe = LAST_INSERT_ID();

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('os_equipo', v_id_oe, 'agregar_equipo_existente', NULL, 'por iniciar',
            LEFT(CONCAT('Equipo ', v_codigo_tw, ' agregado desde campo (QR) a ', v_numero_os), 300),
            p_id_usuario, NOW(),
            JSON_OBJECT('id_os', p_id_os, 'id_equipo', v_id_equipo, 'codigo_tw', v_codigo_tw));

    COMMIT;

    SELECT 2 AS IdTipoMensaje, CONCAT(v_codigo_tw, ' agregado a la lista de la OS.') AS Mensaje;
    SELECT v_id_oe AS id_os_equipo, v_id_equipo AS id_equipo, v_codigo_tw AS codigo_tw;
END$$

DELIMITER ;

-- ============================================================
-- SP_RegistrarIngresoEquipoMovil  (App Mobile HU-22 — "Registrar equipo" del Ingreso de equipos (OS) · escritura)
-- El técnico registra el ingreso formal de un equipo de su OS: estado de ingreso, observación y fotos.
--   - El técnico sale del token; la OS debe ser suya. Hard Stop (HU-06): solo con la llegada registrada y la OS en curso (SP_ArmarObjetivosMovil).
--   - Estado de ingreso obligatorio: operativo · con_observaciones · inoperativo.
--     Con observaciones o inoperativo: observación (mínimo 3 caracteres, máximo 500) y al menos una foto (máximo 5) obligatorias.
--     Operativo: la observación es opcional y no se guardan fotos.
--   - Un equipo se ingresa UNA sola vez en la misma OS: si ya tiene ingreso se bloquea y se dice cómo y cuándo se registró.
--   - Los equipos bloqueados (inactivos o en evaluación) no se pueden ingresar. Un equipo nuevo (NEW) en borrador SÍ se ingresa (queda pendiente de validar en la intranet).
--   - p_fotos: arreglo JSON con las rutas ya guardadas por el back (["ingresos-equipos/12/….jpg", …]).
--   - Deja el ingreso en auditoria_evento (entidad 'os_equipo').
-- Resultados: 1 mensaje; 2 (id_ingreso, id_os_equipo, estado_ingreso, ingresado_en, fotos).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_RegistrarIngresoEquipoMovil;

DELIMITER $$

CREATE PROCEDURE SP_RegistrarIngresoEquipoMovil(
    IN p_id_usuario   BIGINT,
    IN p_id_os        BIGINT,
    IN p_id_os_equipo BIGINT,
    IN p_estado       VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_observacion  VARCHAR(600) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_fotos        JSON
)
proc: BEGIN
    DECLARE v_estado      VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_obs         VARCHAR(600) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_estado_os   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_salida_utc  DATETIME;
    DECLARE v_llegada_utc DATETIME;
    DECLARE v_habilitado  TINYINT;
    DECLARE v_motivo_no   VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_bloqueado   TINYINT DEFAULT 0;
    DECLARE v_nombre      VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_n_fotos     INT DEFAULT 0;
    DECLARE v_ahora_utc   DATETIME;
    DECLARE v_id          BIGINT;
    DECLARE v_prev_estado VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_prev_utc    DATETIME DEFAULT NULL;
    DECLARE v_oe          BIGINT DEFAULT NULL;

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

    SET v_estado = LOWER(TRIM(IFNULL(p_estado, '')));
    IF v_estado NOT IN ('operativo', 'con_observaciones', 'inoperativo') THEN
        SELECT 1 AS IdTipoMensaje, 'Selecciona el estado de ingreso del equipo.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_obs = NULLIF(TRIM(IFNULL(p_observacion, '')), '');
    IF CHAR_LENGTH(IFNULL(v_obs, '')) > 500 THEN
        SELECT 1 AS IdTipoMensaje, 'La observación puede tener hasta 500 caracteres.' AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_n_fotos = IF(p_fotos IS NULL OR JSON_TYPE(p_fotos) <> 'ARRAY', 0, JSON_LENGTH(p_fotos));
    IF v_estado <> 'operativo' THEN
        IF v_obs IS NULL OR CHAR_LENGTH(v_obs) < 3 THEN
            SELECT 1 AS IdTipoMensaje, 'Escribe la observación del estado del equipo (mínimo 3 caracteres).' AS Mensaje;
            LEAVE proc;
        END IF;
        IF v_n_fotos < 1 THEN
            SELECT 1 AS IdTipoMensaje, 'Toma al menos una foto de evidencia (solo cámara).' AS Mensaje;
            LEAVE proc;
        END IF;
        IF v_n_fotos > 5 THEN
            SELECT 1 AS IdTipoMensaje, 'Puedes adjuntar hasta 5 fotos.' AS Mensaje;
            LEAVE proc;
        END IF;
    ELSE
        SET v_n_fotos = 0;
    END IF;

    START TRANSACTION;

    -- La OS debe ser del técnico del token
    SELECT os.estado INTO v_estado_os
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

    -- El equipo debe ser de esa OS (se bloquea la fila: dos envíos a la vez no ingresan dos veces)
    SELECT oe.id INTO v_oe FROM os_equipo oe WHERE oe.id = p_id_os_equipo AND oe.id_os = p_id_os AND oe.eliminado_en IS NULL FOR UPDATE;
    IF v_oe IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'El equipo no pertenece a este servicio.' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Hard Stop (HU-06) y datos del equipo
    CALL SP_ArmarObjetivosMovil(p_id_os, v_estado_os, v_salida_utc, v_llegada_utc, v_habilitado, v_motivo_no);
    SELECT t.bloqueado, CONCAT(IFNULL(t.codigo_cliente, IFNULL(t.num_serie, t.codigo_tw)), ' · ', IFNULL(t.nombre, 'Equipo'))
    INTO   v_bloqueado, v_nombre
    FROM   tmp_obj_mov t
    WHERE  t.id_os_equipo = p_id_os_equipo;
    DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;

    IF v_llegada_utc IS NULL OR v_habilitado = 0 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, v_motivo_no AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_nombre IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'El equipo no forma parte de los objetivos de este servicio.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_bloqueado = 1 THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Este equipo no se puede ingresar (está inactivo o en evaluación).' AS Mensaje;
        LEAVE proc;
    END IF;

    -- Un equipo se ingresa una sola vez en la misma OS
    SELECT i.estado_ingreso, i.ingresado_utc INTO v_prev_estado, v_prev_utc
    FROM   os_equipo_ingreso i
    WHERE  i.id_os_equipo = p_id_os_equipo AND i.eliminado_en IS NULL
    ORDER BY i.id LIMIT 1;
    IF v_prev_estado IS NOT NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje,
               CONCAT(v_nombre, ' ya se registró hoy a las ', DATE_FORMAT(CONVERT_TZ(v_prev_utc, '+00:00', '-05:00'), '%H:%i'), ' como ',
                      CASE v_prev_estado WHEN 'operativo' THEN 'Operativo' WHEN 'con_observaciones' THEN 'Operativo con observaciones' ELSE 'Inoperativo' END,
                      '. No se puede ingresar dos veces en la misma OS.') AS Mensaje;
        LEAVE proc;
    END IF;

    SET v_ahora_utc = UTC_TIMESTAMP();
    INSERT INTO os_equipo_ingreso (id_os, id_os_equipo, estado_ingreso, observacion, ingresado_utc, id_usuario)
    VALUES (p_id_os, p_id_os_equipo, v_estado, v_obs, v_ahora_utc, p_id_usuario);
    SET v_id = LAST_INSERT_ID();

    IF v_n_fotos > 0 THEN
        INSERT INTO os_equipo_ingreso_foto (id_ingreso, orden, ruta)
        SELECT v_id, jt.orden, jt.ruta
        FROM   JSON_TABLE(p_fotos, '$[*]' COLUMNS (orden FOR ORDINALITY, ruta VARCHAR(500) PATH '$')) jt
        WHERE  NULLIF(TRIM(jt.ruta), '') IS NOT NULL;
    END IF;

    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('os_equipo', p_id_os_equipo, 'ingreso_equipo', NULL,
            CASE v_estado WHEN 'operativo' THEN 'Operativo' WHEN 'con_observaciones' THEN 'Operativo con observaciones' ELSE 'Inoperativo' END,
            LEFT(CONCAT('Ingreso del equipo', IF(v_obs IS NULL, '', CONCAT(': ', v_obs))), 300),
            p_id_usuario, NOW(),
            JSON_OBJECT('id_os', p_id_os, 'id_ingreso', v_id, 'fotos', v_n_fotos));

    COMMIT;

    SELECT 2 AS IdTipoMensaje, CONCAT(v_nombre, ' registrado como ',
           CASE v_estado WHEN 'operativo' THEN 'Operativo' WHEN 'con_observaciones' THEN 'Operativo con observaciones' ELSE 'Inoperativo' END, '.') AS Mensaje;
    SELECT v_id AS id_ingreso, p_id_os_equipo AS id_os_equipo, v_estado AS estado_ingreso,
           CONVERT_TZ(v_ahora_utc, '+00:00', '-05:00') AS ingresado_en, v_n_fotos AS fotos;
END$$

DELIMITER ;
