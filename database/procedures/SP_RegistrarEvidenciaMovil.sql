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
                ELSE CASE v_estado WHEN 'aprobada' THEN 'Evidencia guardada y validada por la IA.'
                         WHEN 'omitida'  THEN 'Evidencia guardada (la IA no estuvo disponible para validarla).'
                         ELSE 'La IA rechazó la toma.' END END AS Mensaje;
    SELECT v_id_evid AS id_evidencia, v_estado AS estado, v_motivo AS motivo_rechazo, v_intento AS intento, v_coincide AS coincide, v_rq AS numero_rq;
END$$

DELIMITER ;
