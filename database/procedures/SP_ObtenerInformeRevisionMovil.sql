-- ============================================================
-- SP_ObtenerInformeRevisionMovil  (App Mobile HU-33 — "Revisar informe" del Jefe de Área · solo lectura)
-- Detalle de un informe para revisarlo desde la app: diagnóstico, VALIDACIONES, EVIDENCIAS (con las forzadas resaltadas y su motivo) y la corrección pedida si está observado.
-- Acceso: rt_bandeja + alcance de la app (regla ÁREA + ROL: SP_FijarAlcanceInformesMovil → SP_ArmarBaseInformes, la misma bandeja de la intranet).
-- Validaciones {codigo, titulo, detalle, estado ok | atencion | error, obligatoria}; salen de las MISMAS columnas de SP_ArmarBaseInformes que usan SP_PrepararRevisionInforme y
--   SP_RegistrarRevisionInforme (fotos, ensayos sin resultado, observaciones / precotización, pasos realizados): no hay otra regla. Las obligatorias en error bloquean "Aprobar y liberar":
--     datos (informativa) · ensayos (obligatoria) · evidencias (obligatoria: ≥ 1 foto y ninguna evidencia FORZADA sin revisar del jefe en Aprobaciones) · procedimiento (obligatoria) ·
--     precotizacion (obligatoria solo si hay observaciones) · firmas (informativa: el estado exacto de SP_ArmarFirmasOsMovil, HU-17; no bloquea).
--   puede_aprobar  = rt_revisar + informe sin revisar ni observado + sin corrección pendiente + ninguna obligatoria en error (SP_AprobarInformeMovil lo vuelve a validar).
--   puede_observar = rt_revisar + informe sin revisar + sin corrección pendiente. motivo_bloqueo = por qué no se puede aprobar (NULL si se puede).
--   estado: por_revisar | en_correccion | aprobado (la misma pestaña de la lista).
-- Resultados: 1 mensaje · 2 cabecera (1 fila) · 3 validaciones · 4 evidencias · 5 corrección pendiente (0 o 1 fila) · 6 motivos · 7 secciones · 8 plazos. Fechas: ISO sin zona (hora de Lima).
-- Requiere las migraciones 93, 101, 113 y 121.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ObtenerInformeRevisionMovil;

DELIMITER $$

CREATE PROCEDURE SP_ObtenerInformeRevisionMovil(
    IN p_id_usuario BIGINT,
    IN p_id_informe BIGINT
)
proc: BEGIN
    DECLARE v_tiene      TINYINT DEFAULT 0;
    DECLARE v_revisar    TINYINT DEFAULT 0;
    DECLARE v_existe     INT DEFAULT 0;
    DECLARE v_estado     VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_id_os      BIGINT DEFAULT NULL;
    DECLARE v_datos_ok   TINYINT DEFAULT 0;
    DECLARE v_n_fotos    INT DEFAULT 0;
    DECLARE v_n_forz     INT DEFAULT 0;
    DECLARE v_n_forz_sr  INT DEFAULT 0;
    DECLARE v_n_ens      INT DEFAULT 0;
    DECLARE v_n_ens_sr   INT DEFAULT 0;
    DECLARE v_n_ens_nc   INT DEFAULT 0;
    DECLARE v_n_obs      INT DEFAULT 0;
    DECLARE v_n_items    INT DEFAULT 0;
    DECLARE v_n_pasos    INT DEFAULT 0;
    DECLARE v_n_pasos_r  INT DEFAULT 0;
    DECLARE v_corr       BIGINT DEFAULT NULL;
    DECLARE v_f_horas    INT;
    DECLARE v_f_vence    DATETIME;
    DECLARE v_f_seg      INT;
    DECLARE v_f_ninf     INT;
    DECLARE v_f_ncomp    INT;
    DECLARE v_f_nfirm    INT;
    DECLARE v_f_nresp    INT;
    DECLARE v_f_nok      INT;
    DECLARE v_f_listo    TINYINT;
    DECLARE v_firmado    TINYINT DEFAULT 0;
    DECLARE v_completo   TINYINT DEFAULT 0;
    DECLARE v_ausente    TINYINT DEFAULT 0;
    DECLARE v_resp       VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_motivo_inc VARCHAR(160) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_err_obl    INT DEFAULT 0;
    DECLARE v_primer_err VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_aprobar    TINYINT DEFAULT 0;
    DECLARE v_observar   TINYINT DEFAULT 0;
    DECLARE v_bloqueo    VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SET @tw_inf_usuario = NULL, @tw_inf_ver_todo = NULL, @tw_inf_area = NULL;
        DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;
        DROP TEMPORARY TABLE IF EXISTS tmp_irv;
        DROP TEMPORARY TABLE IF EXISTS tmp_cat_rev;
        DROP TEMPORARY TABLE IF EXISTS tmp_fm_inf;
        DROP TEMPORARY TABLE IF EXISTS tmp_fm_resp;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF FN_PermisoAccion(p_id_usuario, 'rt_bandeja') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver la revisión de informes técnicos.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF IFNULL(p_id_informe, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El informe indicado no es válido.' AS Mensaje;
        LEAVE proc;
    END IF;
    SET v_revisar = FN_PermisoAccion(p_id_usuario, 'rt_revisar');

    CALL SP_FijarAlcanceInformesMovil(p_id_usuario, v_tiene);
    IF v_tiene = 0 THEN
        SET @tw_inf_usuario = NULL, @tw_inf_ver_todo = NULL, @tw_inf_area = NULL;
        SELECT 1 AS IdTipoMensaje, 'Tu cargo no tiene el menú de Jefatura.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_ArmarBaseInformes(p_id_usuario, p_id_informe);
    SET @tw_inf_usuario = NULL, @tw_inf_ver_todo = NULL, @tw_inf_area = NULL;

    SELECT COUNT(*) INTO v_existe FROM tmp_rt_base;
    IF v_existe = 0 THEN
        DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;
        SELECT 1 AS IdTipoMensaje, 'El informe no existe o no está en tu alcance.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT b.estado, b.id_os,
           IF(NULLIF(TRIM(IFNULL(b.diagnostico, '')), '') IS NOT NULL AND b.equipo IS NOT NULL AND b.tecnico IS NOT NULL AND b.numero_os IS NOT NULL, 1, 0),
           b.n_fotos, b.n_forzadas, b.n_forzadas_sin_revision,
           b.n_ensayos, b.n_ensayos_sin_resultado, b.n_ensayos_no_conformes,
           b.n_observaciones, IFNULL(b.n_items_precot, 0), b.n_pasos, b.n_pasos_realizados
      INTO v_estado, v_id_os, v_datos_ok,
           v_n_fotos, v_n_forz, v_n_forz_sr,
           v_n_ens, v_n_ens_sr, v_n_ens_nc,
           v_n_obs, v_n_items, v_n_pasos, v_n_pasos_r
    FROM tmp_rt_base b LIMIT 1;

    SELECT MAX(c.id_correccion) INTO v_corr
    FROM   informe_correccion c WHERE c.id_informe = p_id_informe AND c.estado = 'pendiente' AND c.eliminado_en IS NULL;

    -- Firmas del informe (HU-17): el estado exacto lo arma SP_ArmarFirmasOsMovil, una sola vez
    CALL SP_ArmarFirmasOsMovil(v_id_os, v_f_horas, v_f_vence, v_f_seg, v_f_ninf, v_f_ncomp, v_f_nfirm, v_f_nresp, v_f_nok, v_f_listo);
    SELECT IFNULL(MAX(i.firmado), 0), IFNULL(MAX(i.completo), 0), MAX(i.resp_nombre), MAX(i.motivo)
      INTO v_firmado, v_completo, v_resp, v_motivo_inc
    FROM tmp_fm_inf i WHERE i.id_informe = p_id_informe;
    SELECT IFNULL(MAX(r.ausente), 0) INTO v_ausente
    FROM tmp_fm_resp r JOIN tmp_fm_inf i ON i.clave = r.clave WHERE i.id_informe = p_id_informe;
    DROP TEMPORARY TABLE IF EXISTS tmp_fm_inf;
    DROP TEMPORARY TABLE IF EXISTS tmp_fm_resp;

    CALL SP_ArmarCatalogoRevisionInformeMovil();

    -- Validaciones
    DROP TEMPORARY TABLE IF EXISTS tmp_irv;
    CREATE TEMPORARY TABLE tmp_irv (
        orden      INT,
        codigo     VARCHAR(20),
        titulo     VARCHAR(80),
        detalle    VARCHAR(300),
        estado     VARCHAR(10),
        obligatoria TINYINT
    ) DEFAULT CHARSET = utf8mb4 COLLATE = utf8mb4_0900_ai_ci;

    INSERT INTO tmp_irv VALUES
        (1, 'datos', 'Datos del informe',
         IF(v_datos_ok = 1, 'Completo', 'Falta el diagnóstico o algún dato de la cabecera'),
         IF(v_datos_ok = 1, 'ok', 'atencion'), 0),
        (2, 'ensayos', 'Ensayos',
         CASE WHEN v_n_ens = 0     THEN 'No aplica: el informe no registra ensayos'
              WHEN v_n_ens_sr > 0  THEN CONCAT(v_n_ens_sr, IF(v_n_ens_sr = 1, ' lectura sin resultado', ' lecturas sin resultado'))
              WHEN v_n_ens_nc > 0  THEN CONCAT(v_n_ens_nc, IF(v_n_ens_nc = 1, ' lectura no conforme registrada', ' lecturas no conformes registradas'))
              ELSE 'Conformes' END,
         CASE WHEN v_n_ens_sr > 0 THEN 'error' WHEN v_n_ens_nc > 0 THEN 'atencion' ELSE 'ok' END, 1),
        (3, 'evidencias', 'Evidencias',
         CASE WHEN v_n_fotos = 0    THEN 'Faltan las fotos del servicio'
              WHEN v_n_forz_sr > 0  THEN CONCAT(v_n_forz_sr, IF(v_n_forz_sr = 1, ' forzada sin revisar', ' forzadas sin revisar'), ': resuelve primero la evidencia forzada en Aprobaciones')
              WHEN v_n_forz > 0     THEN CONCAT(v_n_fotos, IF(v_n_fotos = 1, ' evidencia · ', ' evidencias · '), v_n_forz, IF(v_n_forz = 1, ' forzada ya revisada', ' forzadas ya revisadas'), ' en Aprobaciones')
              ELSE CONCAT(v_n_fotos, IF(v_n_fotos = 1, ' evidencia', ' evidencias')) END,
         CASE WHEN v_n_fotos = 0 OR v_n_forz_sr > 0 THEN 'error' WHEN v_n_forz > 0 THEN 'atencion' ELSE 'ok' END, 1),
        (4, 'procedimiento', 'Procedimiento ejecutado',
         IF(v_n_pasos = 0, 'El informe no registra el procedimiento ejecutado', CONCAT(v_n_pasos_r, ' / ', v_n_pasos, ' pasos completados')),
         IF(v_n_pasos_r > 0, 'ok', 'error'), 1),
        (5, 'precotizacion', 'Precotización',
         CASE WHEN v_n_obs = 0   THEN 'No aplica: el servicio no tiene observaciones'
              WHEN v_n_items = 0 THEN 'Falta registrar la precotización (el servicio tiene observaciones)'
              ELSE CONCAT(v_n_items, IF(v_n_items = 1, ' concepto enviado', ' conceptos enviados')) END,
         IF(v_n_obs > 0 AND v_n_items = 0, 'error', 'ok'), IF(v_n_obs > 0, 1, 0)),
        (6, 'firmas', 'Firmas',
         CASE WHEN v_firmado = 1  THEN CONCAT('Firmado por ', IFNULL(v_resp, 'el responsable'))
              WHEN v_ausente = 1  THEN 'Cliente ausente'
              WHEN v_completo = 0 THEN IFNULL(v_motivo_inc, 'Aún sin responsable en planta')
              ELSE 'Pendiente de la firma del cliente' END,
         IF(v_firmado = 1 OR v_ausente = 1, 'ok', 'atencion'), 0);

    SELECT COUNT(*) INTO v_err_obl FROM tmp_irv WHERE obligatoria = 1 AND estado = 'error';
    SELECT v.detalle INTO v_primer_err FROM tmp_irv v WHERE v.obligatoria = 1 AND v.estado = 'error' ORDER BY v.orden LIMIT 1;

    SET v_observar = IF(v_revisar = 1 AND v_estado NOT IN ('revisado', 'aprobado') AND v_corr IS NULL, 1, 0);
    SET v_aprobar  = IF(v_revisar = 1 AND v_estado IN ('pendiente_revision', 'en_revision') AND v_corr IS NULL AND v_err_obl = 0, 1, 0);
    SET v_bloqueo  = CASE WHEN v_aprobar = 1 THEN NULL
                          WHEN v_revisar = 0 THEN 'No tienes permiso para aprobar informes.'
                          WHEN v_estado IN ('revisado', 'aprobado') THEN 'El informe ya fue revisado.'
                          WHEN v_corr IS NOT NULL OR v_estado = 'observado' THEN 'El informe está en corrección: el técnico debe atenderla antes de aprobarlo.'
                          ELSE v_primer_err END;

    SELECT 2 AS IdTipoMensaje, 'Éxito.' AS Mensaje;

    -- 2 Cabecera
    SELECT b.id_informe, b.numero_informe, b.tipo_servicio, b.numero_os, b.razon_social AS cliente, b.sede, b.equipo, b.codigo_tw, b.numero_serie, b.tecnico,
           DATE_FORMAT(b.fecha_ejecucion, '%Y-%m-%d')                                       AS fecha_ejecucion,
           b.diagnostico,
           CASE WHEN b.estado IN ('revisado', 'aprobado') THEN 'aprobado'
                WHEN b.estado = 'observado'               THEN 'en_correccion'
                ELSE 'por_revisar' END                                                      AS estado,
           b.sla_vencido, b.horas_espera,
           v_aprobar AS puede_aprobar, v_observar AS puede_observar, v_bloqueo AS motivo_bloqueo,
           b.revisor, DATE_FORMAT(b.fecha_revision, '%Y-%m-%dT%H:%i:%s')                    AS fecha_revision,
           b.nota_revision                                                                  AS nota
    FROM   tmp_rt_base b;

    -- 3 Validaciones
    SELECT v.codigo, v.titulo, v.detalle, v.estado, v.obligatoria FROM tmp_irv v ORDER BY v.orden;

    -- 4 Evidencias (las mismas del detalle de la intranet: sin lecturas del QR ni intentos descartados por retoma)
    SELECT f.id_evidencia,
           IF(f.es_video = 1, 'Video de encendido', IFNULL(tf.String1, 'Evidencia')) AS etiqueta,
           IF(f.override_aprobado = 1, 1, 0)                                         AS forzada,
           f.motivo_forzado                                                          AS motivo_forzada,
           f.es_video,
           f.validacion_ia
    FROM   evidencia_fotografica f
    JOIN   tmp_rt_base b ON b.id_informe = p_id_informe
    LEFT JOIN tabla_maestra tf ON tf.IdMaestro = 30 AND tf.IdEmpresa = 1 AND tf.Num1 = f.id_tipo_evidencia
    WHERE  f.eliminado_en IS NULL AND f.id_tipo_evidencia NOT IN (6, 7)
      AND  f.url_archivo NOT LIKE 'qr://%' AND IFNULL(f.vigente, 1) = 1
      AND  (f.id_informe = p_id_informe
            OR (f.id_informe IS NULL AND f.id_os = b.id_os AND (f.id_equipo = b.id_equipo OR f.id_equipo IS NULL)))
    ORDER BY f.timestamp_captura, f.id_evidencia;

    -- 5 Corrección pendiente (si el informe está observado)
    SELECT c.id_correccion, c.motivo, IFNULL(m.nombre, c.motivo) AS motivo_nombre, c.secciones, c.instruccion,
           DATE_FORMAT(c.plazo_en, '%Y-%m-%dT%H:%i:%s')    AS plazo_en,
           c.estado,
           NULLIF(TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))), '') AS por,
           DATE_FORMAT(c.creado_en, '%Y-%m-%dT%H:%i:%s')   AS creada_en
    FROM   informe_correccion c
    LEFT JOIN usuario u     ON u.id_usuario = c.id_jefe
    LEFT JOIN tmp_cat_rev m ON m.tipo = 'motivo' AND m.codigo = c.motivo
    WHERE  c.id_correccion = v_corr;

    -- 6 7 8 Catálogos del modal "Observar informe"
    SELECT k.codigo, k.nombre FROM tmp_cat_rev k WHERE k.tipo = 'motivo'  ORDER BY k.orden;
    SELECT k.codigo, k.nombre FROM tmp_cat_rev k WHERE k.tipo = 'seccion' ORDER BY k.orden;
    SELECT k.horas, k.nombre AS texto FROM tmp_cat_rev k WHERE k.tipo = 'plazo' ORDER BY k.orden;

    DROP TEMPORARY TABLE IF EXISTS tmp_irv;
    DROP TEMPORARY TABLE IF EXISTS tmp_cat_rev;
    DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;
END$$

DELIMITER ;
