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
