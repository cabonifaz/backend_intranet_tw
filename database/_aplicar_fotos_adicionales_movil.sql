-- Fotos adicionales del Registro fotográfico (app móvil). Ejecutar con Alt+X (No al aviso) y reiniciar la API.
-- Requiere antes el Registro fotográfico de la app (HU-11: SP_CatalogoEvidenciasMovil, SP_ResumenEvidenciasMovil, SP_ContextoEquipoMovil). No crea tablas ni datos: las fotos adicionales
-- se guardan en evidencia_fotografica con codigo = 'adicional'.
-- Una foto adicional es una foto EXTRA del servicio (hasta 20 por equipo): NO es obligatoria, NO pasa por la IA y NO cuenta en "N de 9 completas" ni en "Guardar y volver".
-- Actualiza 2 procedimientos (SP_RegistrarEvidenciaMovil acepta el código 'adicional'; SP_ObtenerEvidenciasMovil devuelve además la lista de adicionales) y crea 1 nuevo (SP_QuitarEvidenciaAdicionalMovil).

-- ============================================================
-- SP_RegistrarEvidenciaMovil  (App Mobile HU-11 / HU-13 — guarda una captura del panel de evidencias · escritura)
-- Guarda UN intento de captura (foto, microvideo de encendido o lectura del QR) con el resultado de la validación IA que ya hizo el back.
--   - Acceso: SP_ContextoEquipoMovil (OS del técnico, Hard Stop) y el equipo EN EJECUCIÓN.
--   - p_codigo: una de las 9 evidencias (SP_CatalogoEvidenciasMovil). p_pagina: solo el informe a mano admite varias hojas (1 a 10).
--   - Encendido (HU-13): el microvideo dura de 3 a 5 s (se tolera 0,5 s). p_ruta_cuadro = cuadro de la imagen que analizó la IA.
--   - QR: p_qr_texto es lo que leyó la cámara; debe corresponder a ESTE equipo (N/S, código del cliente o COD TW, igual que la búsqueda por QR de la HU-07) o ser una
--     etiqueta QR de TW (enlace q.me-qr.com/… o tw.com.pe/e/…, SP_NormalizarQrMovil) vinculada a este equipo en equipo_qr: la primera lectura de una etiqueta que no
--     pertenece a nadie la vincula a este equipo; una etiqueta de OTRO equipo se rechaza.
--   - p_ia_estado = aprobada | rechazada | omitida (la IA no estuvo disponible: no bloquea) con p_ia_motivo y p_ia_json (lo que leyó).
--     Placa: si la IA leyó la serie y no coincide con la del equipo, la toma se RECHAZA aquí (la regla vive solo en este SP).
--   - Cada captura es un intento nuevo (intento = 1, 2, 3…); la última queda vigente y reemplaza a la anterior. Una toma rechazada se puede
--     aceptar a la fuerza con SP_ForzarEvidenciaMovil (HU-12).
--   - p_codigo = 'adicional' (fotos adicionales, opcionales): foto extra del servicio, hasta 20 por equipo; el SP le asigna el número; NO pasa por la IA
--     (queda 'omitida'), no forma parte de las 9 ni cuenta para "Guardar y volver".
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
    DECLARE v_clave    VARCHAR(120) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_vinc_eq  BIGINT DEFAULT NULL;
    DECLARE v_vinc_cod VARCHAR(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_filas    INT DEFAULT 0;
    DECLARE v_vinculado TINYINT DEFAULT 0;
    DECLARE v_motivo_qr VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;

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

    SET p_codigo = LOWER(TRIM(IFNULL(p_codigo, '')));
    IF p_codigo = 'adicional' THEN
        -- Fotos adicionales: extras opcionales del servicio. No forman parte de las 9 del panel, no pasan por la IA y no cuentan para "Guardar y volver"
        SET v_id_tipo = 2, v_medio = 'foto', v_estado = 'omitida', v_json = NULL, v_motivo = NULL;
    ELSE
        CALL SP_CatalogoEvidenciasMovil();
        SELECT c.id_tipo, c.medio INTO v_id_tipo, v_medio FROM tmp_cat_evid c WHERE c.codigo = p_codigo;
        DROP TEMPORARY TABLE IF EXISTS tmp_cat_evid;
    END IF;
    IF v_id_tipo IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'La evidencia no existe en el panel.' AS Mensaje; LEAVE proc;
    END IF;
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

    -- Foto adicional: el SP asigna el número (1, 2, 3…) y no admite más de 20 por equipo
    IF p_codigo = 'adicional' THEN
        SELECT IFNULL(MAX(f.pagina), 0) + 1 INTO v_pagina
        FROM   evidencia_fotografica f
        WHERE  f.id_os = p_id_os AND f.id_equipo = v_id_eq AND f.codigo = 'adicional' AND f.eliminado_en IS NULL;
        IF v_pagina > 20 THEN
            ROLLBACK;
            SELECT 1 AS IdTipoMensaje, 'Un equipo admite hasta 20 fotos adicionales. Quita alguna para agregar otra.' AS Mensaje; LEAVE proc;
        END IF;
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
        -- Etiqueta QR de TW (enlace corto q.me-qr.com/… o tw.com.pe/e/…): no trae el código del equipo, así que se reconoce por su clave (SP_NormalizarQrMovil).
        -- Si ya está vinculada a ESTE equipo, coincide; si no pertenece a nadie, queda vinculada a este equipo (primera lectura); si es de otro, se rechaza.
        IF v_coincide = 0 THEN
            CALL SP_NormalizarQrMovil(p_qr_texto, v_clave);
            IF v_clave IS NOT NULL THEN
                SELECT q.id_equipo INTO v_vinc_eq FROM equipo_qr q WHERE q.clave = v_clave AND q.eliminado_en IS NULL LIMIT 1;
                IF v_vinc_eq IS NULL THEN
                    INSERT IGNORE INTO equipo_qr (id_equipo, clave, texto, creado_por) VALUES (v_id_eq, v_clave, LEFT(TRIM(p_qr_texto), 300), p_id_usuario);
                    SET v_filas = ROW_COUNT();
                    SELECT q.id_equipo INTO v_vinc_eq FROM equipo_qr q WHERE q.clave = v_clave AND q.eliminado_en IS NULL LIMIT 1;
                    SET v_vinculado = IF(v_filas = 1, 1, 0);
                END IF;
                IF v_vinc_eq = v_id_eq THEN
                    SET v_coincide = 1;
                ELSE
                    SELECT COALESCE(NULLIF(ec.codigo_cliente, ''), NULLIF(ec.codigo_tw, ''), ec.num_serie) INTO v_vinc_cod FROM equipo_cliente ec WHERE ec.id_equipo = v_vinc_eq;
                    SET v_motivo_qr = LEFT(CONCAT('Este QR ya pertenece a otro equipo (', IFNULL(v_vinc_cod, 'sin código'), '). Escanea la etiqueta del equipo que estás trabajando.'), 300);
                END IF;
            END IF;
        END IF;
        SET v_estado = IF(v_coincide = 1, 'aprobada', 'rechazada');
        SET v_motivo = IF(v_coincide = 1, NULL, COALESCE(v_motivo_qr, 'El QR leído no corresponde a este equipo. Escanea la etiqueta del equipo que estás trabajando.'));
        SET v_json = JSON_OBJECT('qr', LEFT(TRIM(p_qr_texto), 300), 'vinculado', v_vinculado = 1);
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
           CASE WHEN v_medio = 'qr' AND v_estado = 'aprobada' THEN IF(v_vinculado = 1, 'QR leído y vinculado a este equipo.', 'QR del equipo leído.')
                WHEN v_medio = 'qr' THEN 'El QR no corresponde a este equipo.'
                WHEN p_codigo = 'adicional' THEN 'Foto adicional guardada.'
                ELSE CASE v_estado WHEN 'aprobada' THEN 'Evidencia guardada y validada por la IA.'
                         WHEN 'omitida'  THEN 'Evidencia guardada (la IA no estuvo disponible para validarla).'
                         ELSE 'La IA rechazó la toma.' END END AS Mensaje;
    SELECT v_id_evid AS id_evidencia, v_estado AS estado, v_motivo AS motivo_rechazo, v_intento AS intento, v_coincide AS coincide, v_rq AS numero_rq;
END$$

DELIMITER ;

-- ============================================================
-- SP_ObtenerEvidenciasMovil  (App Mobile HU-11 / HU-12 / HU-13 — panel de evidencias del equipo · lectura)
-- El panel del "Registro fotográfico": las 9 evidencias (SP_CatalogoEvidenciasMovil) con su estado, el avance "N de 9 completas" y lo que necesita el
-- botón "Guardar y volver" (puede_guardar = las 9 completas). Acceso: SP_ContextoEquipoMovil (OS del técnico, Hard Stop, equipo iniciado).
--   estado de cada evidencia: pendiente | aprobada | rechazada | forzada | omitida  (omitida = la IA no estuvo disponible; cuenta como completa)
--   Para una evidencia FORZADA (HU-12) trae lo de "Ver detalles": motivo del técnico, rechazo de la IA, quién la aceptó, cuándo y los intentos previos.
--   Informe a mano: paginas = hojas válidas; la tarjeta muestra la primera.
-- Resultados: 1 mensaje · 2 cabecera (1 fila) · 3 evidencias (9 filas) · 4 fotos adicionales (0 a 20 filas; no cuentan en el avance ni en "Guardar y volver").
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

    -- 4. Fotos adicionales (opcionales, no cuentan en las 9): de la más antigua a la más reciente
    SELECT f.id_evidencia, f.pagina AS numero, CONVERT_TZ(f.timestamp_captura, '+00:00', '-05:00') AS capturada_en
    FROM   evidencia_fotografica f
    WHERE  f.id_os = p_id_os AND f.id_equipo = v_id_eq AND f.codigo = 'adicional' AND f.eliminado_en IS NULL
    ORDER BY f.pagina, f.id_evidencia;

    DROP TEMPORARY TABLE IF EXISTS tmp_cat_evid;
END$$

DELIMITER ;

-- ============================================================
-- SP_QuitarEvidenciaAdicionalMovil  (App Mobile — quita una foto adicional del registro fotográfico · escritura)
-- El técnico quita una de sus FOTOS ADICIONALES (las extras opcionales, codigo 'adicional') mientras el equipo siga en ejecución. Solo estas: las 9 evidencias
-- del panel no se quitan (se repiten). Borrado lógico (eliminado_en / eliminado_por); el archivo se conserva. Acceso: SP_ContextoEquipoMovil (OS del técnico, Hard Stop).
-- Deja el registro en auditoria_evento.
-- Resultados: 1 mensaje.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_QuitarEvidenciaAdicionalMovil;

DELIMITER $$

CREATE PROCEDURE SP_QuitarEvidenciaAdicionalMovil(
    IN p_id_usuario   BIGINT,
    IN p_id_os        BIGINT,
    IN p_id_os_equipo BIGINT,
    IN p_id_evidencia BIGINT
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
    DECLARE v_pagina   INT DEFAULT NULL;
    DECLARE v_filas    INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 OR IFNULL(p_id_os_equipo, 0) <= 0 OR IFNULL(p_id_evidencia, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Foto no encontrada.' AS Mensaje; LEAVE proc;
    END IF;

    START TRANSACTION;

    CALL SP_ContextoEquipoMovil(p_id_usuario, p_id_os, p_id_os_equipo, v_msg, v_id_eq, v_est_eq, v_hab, v_numero, v_nombre, v_num_os, v_servicio);
    IF v_msg IS NULL AND (v_hab = 0 OR v_est_eq <> 'en_ejecucion') THEN
        SET v_msg = IF(v_est_eq = 'pausado', 'El equipo está pausado: reanúdalo para quitar fotos.',
                       IF(v_est_eq = 'completado', 'Este equipo ya está completado.', 'El servicio ya no está en curso: no se pueden quitar fotos.'));
    END IF;
    IF v_msg IS NOT NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje; LEAVE proc;
    END IF;

    SELECT f.pagina INTO v_pagina
    FROM   evidencia_fotografica f
    WHERE  f.id_evidencia = p_id_evidencia AND f.id_os = p_id_os AND f.id_equipo = v_id_eq AND f.codigo = 'adicional' AND f.eliminado_en IS NULL
    FOR UPDATE;

    IF v_pagina IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Foto adicional no encontrada.' AS Mensaje; LEAVE proc;
    END IF;

    UPDATE evidencia_fotografica SET eliminado_en = NOW(), eliminado_por = p_id_usuario WHERE id_evidencia = p_id_evidencia AND eliminado_en IS NULL;
    SET v_filas = ROW_COUNT();

    IF v_filas = 1 THEN
        INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
        VALUES ('os_equipo', p_id_os_equipo, 'quitar_evidencia_adicional', NULL, 'quitada',
                LEFT(CONCAT('Foto adicional ', v_pagina, ' de ', v_num_os, ' quitada por el técnico.'), 900),
                p_id_usuario, NOW(), JSON_OBJECT('id_evidencia', p_id_evidencia, 'numero', v_pagina));
    END IF;

    COMMIT;
    SELECT 2 AS IdTipoMensaje, 'Foto adicional quitada.' AS Mensaje;
END$$

DELIMITER ;

-- ============================================================
-- VERIFICACIÓN (solo lectura: no crea datos)
-- ============================================================
SELECT 'Registrar acepta fotos adicionales (debe ser 1)' AS verificacion,
       (SELECT COUNT(*) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = DATABASE() AND ROUTINE_NAME = 'SP_RegistrarEvidenciaMovil' AND ROUTINE_DEFINITION LIKE '%adicional%') AS valor
UNION ALL
SELECT 'El panel devuelve las fotos adicionales (debe ser 1)',
       (SELECT COUNT(*) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = DATABASE() AND ROUTINE_NAME = 'SP_ObtenerEvidenciasMovil' AND ROUTINE_DEFINITION LIKE '%adicional%')
UNION ALL
SELECT 'Quitar foto adicional creado (debe ser 1)',
       (SELECT COUNT(*) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = DATABASE() AND ROUTINE_NAME = 'SP_QuitarEvidenciaAdicionalMovil');
