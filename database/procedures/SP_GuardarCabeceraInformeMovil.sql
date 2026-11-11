-- ============================================================
-- SP_GuardarCabeceraInformeMovil  (App Mobile HU-15 — guardar la Cabecera del informe: Datos · Detalle Serv. · Observación y pruebas)
-- El técnico guarda lo que digitó en las 3 pestañas. Una sección que NO viene en el JSON no se toca; una que viene REEMPLAZA lo que el técnico había guardado
-- (lo que agregue el supervisor en la intranet, origen = 'supervisor', nunca se toca).
--   p_json = {
--     "datos":   {"responsableNombre","responsableCargo","responsableTelefono"}                         → "Quién atiende en planta"
--     "detalle": {"tipoEquipo","celdas":[mV…],"sumatoriaHasta","comparacionHasta","anillosFijacion","checks":["codigo"…]}   → Detalle Serv.
--     "recomendaciones":[{"titulo","descripcion","prioridad"}] · "sinRecomendaciones":bool
--     "fallas":[{"clasificacion","componente","severidad","descripcion","fotos":[idEvidencia…],"pruebas":[{"tipo","posicion","carga","indicacion"}]}] · "sinFallas":bool
--     "comentarioPruebas" · "diagnostico":{"severidadGeneral","estadoEquipo","revisionJefatura","precotizacion","segundaVisita","aplicaGarantia"} }
--   Reglas: la OS es del técnico, Hard Stop de llegada y equipo iniciado (SP_ContextoEquipoMovil); el equipo EN EJECUCIÓN y el informe aún sin generar (HU-16).
--   REGLA DE LA HU-15: cada falla exige una prueba que la justifique (repetibilidad, pesaje o excentricidad) con L e I digitados; el servidor CALCULA E = I − L y el EMP
--   (SP_EmpEnsayoMovil, el mismo de Ensayos y Calibración) y la conformidad de cada lectura. Las fotos de una falla son capturas ya subidas con SP_RegistrarFotoFallaMovil
--   (de este técnico y este equipo). El checklist se valida contra el catálogo CHECKLIST_SERVICIO del tipo de orden (OS / OM, SP_TipoOrdenMovil).
--   Se bloquea el equipo y luego el informe (se crea el borrador si aún no existe). Auditoría: auditoria_evento (informe_tecnico).
-- Resultados: 1 mensaje (1 regla de negocio · 2 éxito · 3 error) · 2 (solo éxito) id_informe, guardada_en, n_fallas, n_recomendaciones.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_GuardarCabeceraInformeMovil;

DELIMITER $$

CREATE PROCEDURE SP_GuardarCabeceraInformeMovil(
    IN p_id_usuario   BIGINT,
    IN p_id_os        BIGINT,
    IN p_id_os_equipo BIGINT,
    IN p_json         LONGTEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_msg      VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_err      VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_id_eq    BIGINT DEFAULT NULL;
    DECLARE v_estado   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_hab      TINYINT DEFAULT 0;
    DECLARE v_numero   INT DEFAULT NULL;
    DECLARE v_nombre   VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_num_os   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_servicio VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_oe       BIGINT DEFAULT NULL;
    DECLARE v_informe  BIGINT DEFAULT NULL;
    DECLARE v_gen      DATETIME DEFAULT NULL;
    DECLARE v_tipo     VARCHAR(2) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT 'OS';
    DECLARE v_rq       VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_clase    VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_unidad   VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cap      DECIMAL(14,4);
    DECLARE v_d        DECIMAL(14,4);
    DECLARE v_e        DECIMAL(14,4);
    DECLARE v_h_datos  TINYINT DEFAULT 0;
    DECLARE v_h_det    TINYINT DEFAULT 0;
    DECLARE v_h_rec    TINYINT DEFAULT 0;
    DECLARE v_h_fal    TINYINT DEFAULT 0;
    DECLARE v_h_diag   TINYINT DEFAULT 0;
    DECLARE v_h_com    TINYINT DEFAULT 0;
    DECLARE v_h_sinrec TINYINT DEFAULT 0;
    DECLARE v_h_sinfal TINYINT DEFAULT 0;
    DECLARE v_r_nom    VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_r_car    VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_r_tel    VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_d_tipo   VARCHAR(60) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_d_suma   DECIMAL(14,4) DEFAULT NULL;
    DECLARE v_d_comp   DECIMAL(14,4) DEFAULT NULL;
    DECLARE v_d_anillo VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_com      VARCHAR(700) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_sinrec   VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_sinfal   VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_sev      VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_est_eq   VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_t_rev    VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_t_pre    VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_t_seg    VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_t_gar    VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_n_rec    INT DEFAULT 0;
    DECLARE v_n_fal    INT DEFAULT 0;
    DECLARE v_n_pru    INT DEFAULT 0;
    DECLARE v_n_celdas INT DEFAULT 0;
    DECLARE v_i        INT DEFAULT 0;
    DECLARE v_fila     INT;
    DECLARE v_carga    DECIMAL(14,4);
    DECLARE v_emp      DECIMAL(14,4);
    DECLARE v_f_cla    VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_f_com    VARCHAR(60) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_f_sev    VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_f_des    VARCHAR(1500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cla_nom  VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_com_nom  VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_obs      BIGINT;
    DECLARE v_nombre_tec VARCHAR(220) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_cab_rec;
        DROP TEMPORARY TABLE IF EXISTS tmp_cab_fal;
        DROP TEMPORARY TABLE IF EXISTS tmp_cab_pru;
        DROP TEMPORARY TABLE IF EXISTS tmp_cab_foto;
        DROP TEMPORARY TABLE IF EXISTS tmp_cab_chk;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 OR IFNULL(p_id_os_equipo, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio o equipo no encontrado.' AS Mensaje; LEAVE proc;
    END IF;
    IF p_json IS NULL OR NOT JSON_VALID(p_json) OR CHAR_LENGTH(p_json) > 60000 OR JSON_TYPE(p_json) <> 'OBJECT' THEN
        SELECT 1 AS IdTipoMensaje, 'Los datos de la cabecera no son válidos.' AS Mensaje; LEAVE proc;
    END IF;

    START TRANSACTION;

    CALL SP_ContextoEquipoMovil(p_id_usuario, p_id_os, p_id_os_equipo, v_msg, v_id_eq, v_estado, v_hab, v_numero, v_nombre, v_num_os, v_servicio);
    IF v_msg IS NULL AND (v_hab = 0 OR v_estado <> 'en_ejecucion') THEN
        SET v_msg = IF(v_estado = 'pausado', 'El equipo está pausado: reanúdalo para guardar la cabecera del informe.',
                       IF(v_estado = 'completado', 'Este equipo ya está completado: el informe no se puede modificar.', 'El servicio ya no está en curso: no se puede guardar la cabecera.'));
    END IF;
    IF v_msg IS NOT NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje; LEAVE proc;
    END IF;

    -- Bloqueos en orden fijo: el equipo (objetivo) y luego su informe (se crea el borrador si todavía no existe)
    SELECT oe.id INTO v_oe FROM os_equipo oe WHERE oe.id = p_id_os_equipo AND oe.id_os = p_id_os AND oe.eliminado_en IS NULL FOR UPDATE;
    SELECT it.id_informe, it.generado_en INTO v_informe, v_gen
    FROM   informe_tecnico it
    WHERE  it.id_os = p_id_os AND it.id_equipo = v_id_eq AND it.eliminado_en IS NULL
    ORDER BY it.id_informe DESC LIMIT 1
    FOR UPDATE;
    IF v_gen IS NOT NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'El informe técnico ya fue generado: no se puede modificar la cabecera.' AS Mensaje; LEAVE proc;
    END IF;
    IF v_informe IS NULL THEN
        INSERT INTO informe_tecnico (numero, id_os, id_equipo, id_tecnico, estado, version, fecha_creacion, creado_por)
        VALUES (CONCAT('BRR-', FLOOR(RAND() * 1000000000)), p_id_os, v_id_eq, p_id_usuario, 'borrador', 1, NOW(), p_id_usuario);
        SET v_informe = LAST_INSERT_ID();
        UPDATE informe_tecnico SET numero = CONCAT('BRR-', LPAD(v_informe, 8, '0')) WHERE id_informe = v_informe;
    END IF;

    CALL SP_TipoOrdenMovil(p_id_os, v_tipo, v_rq);
    CALL SP_EspecEquipoMovil(v_id_eq, v_clase, v_unidad, v_cap, v_d, v_e);

    -- ── Qué secciones vienen ───────────────────────────────────────────────────────────────────
    SET v_h_datos  = IF(JSON_CONTAINS_PATH(p_json, 'one', '$.datos'), 1, 0);
    SET v_h_det    = IF(JSON_CONTAINS_PATH(p_json, 'one', '$.detalle'), 1, 0);
    SET v_h_rec    = IF(JSON_CONTAINS_PATH(p_json, 'one', '$.recomendaciones'), 1, 0);
    SET v_h_fal    = IF(JSON_CONTAINS_PATH(p_json, 'one', '$.fallas'), 1, 0);
    SET v_h_diag   = IF(JSON_CONTAINS_PATH(p_json, 'one', '$.diagnostico'), 1, 0);
    SET v_h_com    = IF(JSON_CONTAINS_PATH(p_json, 'one', '$.comentarioPruebas'), 1, 0);
    SET v_h_sinrec = IF(JSON_CONTAINS_PATH(p_json, 'one', '$.sinRecomendaciones'), 1, 0);
    SET v_h_sinfal = IF(JSON_CONTAINS_PATH(p_json, 'one', '$.sinFallas'), 1, 0);

    -- ── Valores sueltos (una sola lectura del JSON) ────────────────────────────────────────────
    SELECT jt.r_nom, jt.r_car, jt.r_tel, jt.d_tipo, jt.d_suma, jt.d_comp, jt.d_anillo, jt.com, jt.sinrec, jt.sinfal, jt.sev, jt.est_eq, jt.t_rev, jt.t_pre, jt.t_seg, jt.t_gar
    INTO   v_r_nom, v_r_car, v_r_tel, v_d_tipo, v_d_suma, v_d_comp, v_d_anillo, v_com, v_sinrec, v_sinfal, v_sev, v_est_eq, v_t_rev, v_t_pre, v_t_seg, v_t_gar
    FROM   JSON_TABLE(p_json, '$' COLUMNS (
               r_nom    VARCHAR(300)  PATH '$.datos.responsableNombre'   NULL ON EMPTY NULL ON ERROR,
               r_car    VARCHAR(300)  PATH '$.datos.responsableCargo'    NULL ON EMPTY NULL ON ERROR,
               r_tel    VARCHAR(100)  PATH '$.datos.responsableTelefono' NULL ON EMPTY NULL ON ERROR,
               d_tipo   VARCHAR(60)   PATH '$.detalle.tipoEquipo'        NULL ON EMPTY NULL ON ERROR,
               d_suma   DECIMAL(14,4) PATH '$.detalle.sumatoriaHasta'    NULL ON EMPTY NULL ON ERROR,
               d_comp   DECIMAL(14,4) PATH '$.detalle.comparacionHasta'  NULL ON EMPTY NULL ON ERROR,
               d_anillo VARCHAR(10)   PATH '$.detalle.anillosFijacion'   NULL ON EMPTY NULL ON ERROR,
               com      VARCHAR(700)  PATH '$.comentarioPruebas'         NULL ON EMPTY NULL ON ERROR,
               sinrec   VARCHAR(10)   PATH '$.sinRecomendaciones'        NULL ON EMPTY NULL ON ERROR,
               sinfal   VARCHAR(10)   PATH '$.sinFallas'                 NULL ON EMPTY NULL ON ERROR,
               sev      VARCHAR(20)   PATH '$.diagnostico.severidadGeneral'  NULL ON EMPTY NULL ON ERROR,
               est_eq   VARCHAR(30)   PATH '$.diagnostico.estadoEquipo'      NULL ON EMPTY NULL ON ERROR,
               t_rev    VARCHAR(10)   PATH '$.diagnostico.revisionJefatura'  NULL ON EMPTY NULL ON ERROR,
               t_pre    VARCHAR(10)   PATH '$.diagnostico.precotizacion'     NULL ON EMPTY NULL ON ERROR,
               t_seg    VARCHAR(10)   PATH '$.diagnostico.segundaVisita'     NULL ON EMPTY NULL ON ERROR,
               t_gar    VARCHAR(10)   PATH '$.diagnostico.aplicaGarantia'    NULL ON EMPTY NULL ON ERROR)) jt;
    SET v_r_nom = NULLIF(TRIM(NULLIF(v_r_nom, 'null')), '');
    SET v_r_car = NULLIF(TRIM(NULLIF(v_r_car, 'null')), '');
    SET v_r_tel = NULLIF(TRIM(NULLIF(v_r_tel, 'null')), '');
    SET v_d_tipo = NULLIF(TRIM(NULLIF(v_d_tipo, 'null')), '');
    SET v_com    = NULLIF(TRIM(NULLIF(v_com, 'null')), '');
    SET v_sev    = NULLIF(NULLIF(v_sev, 'null'), '');
    SET v_est_eq = NULLIF(NULLIF(v_est_eq, 'null'), '');

    -- ── Secciones en tablas temporales ─────────────────────────────────────────────────────────
    DROP TEMPORARY TABLE IF EXISTS tmp_cab_rec;
    CREATE TEMPORARY TABLE tmp_cab_rec (n INT NOT NULL, titulo VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, descripcion VARCHAR(1500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
                                        prioridad VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, PRIMARY KEY (n));
    INSERT INTO tmp_cab_rec (n, titulo, descripcion, prioridad)
    SELECT jt.n, jt.titulo, jt.descripcion, jt.prioridad
    FROM   JSON_TABLE(p_json, '$.recomendaciones[*]' COLUMNS (
               n FOR ORDINALITY,
               titulo      VARCHAR(300)  PATH '$.titulo'      NULL ON EMPTY NULL ON ERROR,
               descripcion VARCHAR(1500) PATH '$.descripcion' NULL ON EMPTY NULL ON ERROR,
               prioridad   VARCHAR(10)   PATH '$.prioridad'   NULL ON EMPTY NULL ON ERROR)) jt;

    DROP TEMPORARY TABLE IF EXISTS tmp_cab_fal;
    CREATE TEMPORARY TABLE tmp_cab_fal (n INT NOT NULL, clasificacion VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, componente VARCHAR(60) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
                                        severidad VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, descripcion VARCHAR(1500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, PRIMARY KEY (n));
    INSERT INTO tmp_cab_fal (n, clasificacion, componente, severidad, descripcion)
    SELECT jt.n, jt.clasificacion, jt.componente, jt.severidad, jt.descripcion
    FROM   JSON_TABLE(p_json, '$.fallas[*]' COLUMNS (
               n FOR ORDINALITY,
               clasificacion VARCHAR(40)   PATH '$.clasificacion' NULL ON EMPTY NULL ON ERROR,
               componente    VARCHAR(60)   PATH '$.componente'    NULL ON EMPTY NULL ON ERROR,
               severidad     VARCHAR(10)   PATH '$.severidad'     NULL ON EMPTY NULL ON ERROR,
               descripcion   VARCHAR(1500) PATH '$.descripcion'   NULL ON EMPTY NULL ON ERROR)) jt;

    DROP TEMPORARY TABLE IF EXISTS tmp_cab_pru;
    CREATE TEMPORARY TABLE tmp_cab_pru (id INT NOT NULL AUTO_INCREMENT, falla INT NOT NULL, m INT NOT NULL, tipo VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, posicion INT NULL,
                                        carga DECIMAL(14,4) NULL, ind DECIMAL(14,4) NULL, emp DECIMAL(14,4) NULL, err DECIMAL(14,4) NULL, res VARCHAR(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
                                        PRIMARY KEY (id));
    INSERT INTO tmp_cab_pru (falla, m, tipo, posicion, carga, ind)
    SELECT jt.f, jt.m, jt.tipo, jt.posicion, jt.carga, jt.ind
    FROM   JSON_TABLE(p_json, '$.fallas[*]' COLUMNS (
               f FOR ORDINALITY,
               NESTED PATH '$.pruebas[*]' COLUMNS (
                   m FOR ORDINALITY,
                   tipo     VARCHAR(20)   PATH '$.tipo'       NULL ON EMPTY NULL ON ERROR,
                   posicion INT           PATH '$.posicion'   NULL ON EMPTY NULL ON ERROR,
                   carga    DECIMAL(14,4) PATH '$.carga'      NULL ON EMPTY NULL ON ERROR,
                   ind      DECIMAL(14,4) PATH '$.indicacion' NULL ON EMPTY NULL ON ERROR))) jt
    WHERE  jt.m IS NOT NULL;

    DROP TEMPORARY TABLE IF EXISTS tmp_cab_foto;
    CREATE TEMPORARY TABLE tmp_cab_foto (id INT NOT NULL AUTO_INCREMENT, falla INT NOT NULL, id_evidencia BIGINT NULL, PRIMARY KEY (id));
    INSERT INTO tmp_cab_foto (falla, id_evidencia)
    SELECT jt.f, jt.foto
    FROM   JSON_TABLE(p_json, '$.fallas[*]' COLUMNS (
               f FOR ORDINALITY,
               NESTED PATH '$.fotos[*]' COLUMNS (foto BIGINT PATH '$' NULL ON EMPTY NULL ON ERROR))) jt
    WHERE  jt.foto IS NOT NULL;

    DROP TEMPORARY TABLE IF EXISTS tmp_cab_chk;
    CREATE TEMPORARY TABLE tmp_cab_chk (codigo VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL, PRIMARY KEY (codigo));
    INSERT IGNORE INTO tmp_cab_chk (codigo)
    SELECT jt.codigo FROM JSON_TABLE(p_json, '$.detalle.checks[*]' COLUMNS (codigo VARCHAR(40) PATH '$' NULL ON EMPTY NULL ON ERROR)) jt WHERE jt.codigo IS NOT NULL;

    SELECT COUNT(*) INTO v_n_rec FROM tmp_cab_rec;
    SELECT COUNT(*) INTO v_n_fal FROM tmp_cab_fal;
    SELECT COUNT(*) INTO v_n_pru FROM tmp_cab_pru;
    SET v_n_celdas = IFNULL(JSON_LENGTH(JSON_EXTRACT(p_json, '$.detalle.celdas')), 0);

    -- ── Validación (primer error en orden) ─────────────────────────────────────────────────────
    IF v_h_datos = 1 AND (CHAR_LENGTH(IFNULL(v_r_nom, '')) > 150 OR CHAR_LENGTH(IFNULL(v_r_car, '')) > 100 OR CHAR_LENGTH(IFNULL(v_r_tel, '')) > 30) THEN
        SET v_err = 'Revisa "Quién atiende en planta": nombre hasta 150 caracteres, cargo hasta 100 y teléfono hasta 30.';
    ELSEIF v_h_det = 1 AND (JSON_TYPE(JSON_EXTRACT(p_json, '$.detalle')) <> 'OBJECT' OR CHAR_LENGTH(JSON_EXTRACT(p_json, '$.detalle')) > 4000) THEN
        SET v_err = 'Los datos de Detalle Serv. no son válidos.';
    ELSEIF v_h_det = 1 AND v_d_tipo IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM tabla_maestra m WHERE m.Descripcion = 'CLASIFICACION_EQUIPO' AND m.IdEmpresa = 1 AND m.String2 = v_d_tipo) THEN
        SET v_err = 'El tipo de equipo no es válido.';
    ELSEIF v_h_det = 1 AND (v_n_celdas > 12
           OR (v_n_celdas > 0 AND (SELECT COUNT(*) FROM JSON_TABLE(p_json, '$.detalle.celdas[*]' COLUMNS (v DECIMAL(14,4) PATH '$' NULL ON EMPTY NULL ON ERROR)) c
                                   WHERE c.v IS NULL OR ABS(c.v) > 100000) > 0)) THEN
        SET v_err = 'Las celdas (mV) deben ser números, hasta 12 celdas.';
    ELSEIF v_h_det = 1 AND ((v_d_suma IS NOT NULL AND (v_d_suma < 0 OR v_d_suma > 100000000)) OR (v_d_comp IS NOT NULL AND (v_d_comp < 0 OR v_d_comp > 100000000))) THEN
        SET v_err = 'Las pruebas por sumatoria y por comparación deben ser valores positivos.';
    ELSEIF v_h_det = 1 AND (SELECT COUNT(*) FROM tmp_cab_chk c
                            WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra m WHERE m.Descripcion = 'CHECKLIST_SERVICIO' AND m.IdEmpresa = 1 AND m.String3 = v_tipo AND m.String2 = c.codigo)) > 0 THEN
        SET v_err = 'El checklist tiene un paso que no corresponde a este tipo de orden.';
    ELSEIF v_h_rec = 1 AND v_n_rec > 20 THEN
        SET v_err = 'Se admiten hasta 20 recomendaciones.';
    ELSEIF v_h_rec = 1 AND (SELECT COUNT(*) FROM tmp_cab_rec r
                            WHERE r.titulo IS NULL OR CHAR_LENGTH(TRIM(r.titulo)) < 3 OR CHAR_LENGTH(TRIM(r.titulo)) > 200
                               OR CHAR_LENGTH(IFNULL(r.descripcion, '')) > 1000 OR IFNULL(r.prioridad, 'alta') NOT IN ('alta', 'media', 'baja')) > 0 THEN
        SET v_err = 'Cada recomendación necesita un texto de 3 a 200 caracteres y una prioridad válida.';
    ELSEIF v_h_fal = 1 AND v_n_fal > 15 THEN
        SET v_err = 'Se admiten hasta 15 fallas.';
    ELSEIF v_h_fal = 1 AND (SELECT COUNT(*) FROM tmp_cab_fal f
                            WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra m WHERE m.Descripcion = 'CLASIFICACION_FALLA' AND m.IdEmpresa = 1 AND m.String2 = f.clasificacion)) > 0 THEN
        SET v_err = 'Elige la clasificación de cada falla.';
    ELSEIF v_h_fal = 1 AND (SELECT COUNT(*) FROM tmp_cab_fal f
                            WHERE NOT EXISTS (SELECT 1 FROM tabla_maestra m WHERE m.Descripcion = 'COMPONENTE_FALLA' AND m.IdEmpresa = 1 AND m.String2 = f.componente AND m.String3 = f.clasificacion)) > 0 THEN
        SET v_err = 'Elige el componente de cada falla (debe corresponder a su clasificación).';
    ELSEIF v_h_fal = 1 AND (SELECT COUNT(*) FROM tmp_cab_fal f WHERE IFNULL(f.severidad, '') NOT IN ('baja', 'media', 'alta', 'critica')) > 0 THEN
        SET v_err = 'Elige la severidad de cada falla (Baja, Media, Alta o Crítica).';
    ELSEIF v_h_fal = 1 AND (SELECT COUNT(*) FROM tmp_cab_fal f WHERE f.descripcion IS NULL OR CHAR_LENGTH(TRIM(f.descripcion)) < 5 OR CHAR_LENGTH(TRIM(f.descripcion)) > 1000) > 0 THEN
        SET v_err = 'Describe cada falla (de 5 a 1000 caracteres).';
    ELSEIF v_h_fal = 1 AND (SELECT COUNT(*) FROM tmp_cab_pru p WHERE IFNULL(p.tipo, '') NOT IN ('repetibilidad', 'pesaje', 'excentricidad')
                               OR p.carga IS NULL OR p.carga <= 0 OR p.carga > 100000000 OR p.ind IS NULL OR p.ind < 0 OR p.ind > 100000000
                               OR (p.posicion IS NOT NULL AND (p.posicion < 1 OR p.posicion > 9))) > 0 THEN
        SET v_err = 'Revisa la prueba de cada falla: tipo válido, carga L mayor que 0 e indicación I digitada.';
    ELSEIF v_h_fal = 1 AND (SELECT COUNT(*) FROM (SELECT p.falla FROM tmp_cab_pru p GROUP BY p.falla HAVING COUNT(*) > 12) x) > 0 THEN
        SET v_err = 'Una falla admite hasta 12 lecturas de prueba.';
    ELSEIF v_h_fal = 1 THEN
        -- La regla de la HU-15: cada falla exige una prueba que la justifique
        SELECT CONCAT('La falla ', f.n, ' necesita una prueba que la justifique (Repetibilidad, Pesaje o Excentricidad con L e I).') INTO v_err
        FROM   tmp_cab_fal f
        WHERE  NOT EXISTS (SELECT 1 FROM tmp_cab_pru p WHERE p.falla = f.n)
        ORDER BY f.n LIMIT 1;
    END IF;
    IF v_err IS NULL AND v_h_fal = 1 AND (SELECT COUNT(*) FROM (SELECT ft.falla FROM tmp_cab_foto ft GROUP BY ft.falla HAVING COUNT(*) > 5) x) > 0 THEN
        SET v_err = 'Una falla admite hasta 5 fotos.';
    END IF;
    IF v_err IS NULL AND v_h_fal = 1 AND (SELECT COUNT(*) FROM (SELECT ft.id_evidencia FROM tmp_cab_foto ft GROUP BY ft.id_evidencia HAVING COUNT(*) > 1) x) > 0 THEN
        SET v_err = 'Una foto no puede estar en dos fallas.';
    END IF;
    IF v_err IS NULL AND v_h_fal = 1 AND (SELECT COUNT(*) FROM tmp_cab_foto ft
                                          WHERE NOT EXISTS (SELECT 1 FROM evidencia_fotografica e
                                                            WHERE e.id_evidencia = ft.id_evidencia AND e.id_os = p_id_os AND e.id_equipo = v_id_eq AND e.codigo = 'falla'
                                                              AND e.id_usuario = p_id_usuario AND e.eliminado_en IS NULL)) > 0 THEN
        SET v_err = 'Una de las fotos de las fallas no existe o no es de este equipo.';
    END IF;
    IF v_err IS NULL AND v_h_diag = 1 AND ((v_sev IS NOT NULL AND v_sev NOT IN ('baja', 'media', 'alta', 'critica'))
                                           OR (v_est_eq IS NOT NULL AND v_est_eq NOT IN ('operativo', 'con_observaciones', 'inoperativo'))) THEN
        SET v_err = 'El diagnóstico final no es válido: revisa la severidad general y el estado del equipo.';
    END IF;
    IF v_err IS NULL AND v_h_com = 1 AND CHAR_LENGTH(IFNULL(v_com, '')) > 500 THEN
        SET v_err = 'El comentario de las pruebas puede tener hasta 500 caracteres.';
    END IF;
    IF v_err IS NOT NULL THEN
        ROLLBACK;
        DROP TEMPORARY TABLE IF EXISTS tmp_cab_rec;
        DROP TEMPORARY TABLE IF EXISTS tmp_cab_fal;
        DROP TEMPORARY TABLE IF EXISTS tmp_cab_pru;
        DROP TEMPORARY TABLE IF EXISTS tmp_cab_foto;
        DROP TEMPORARY TABLE IF EXISTS tmp_cab_chk;
        SELECT 1 AS IdTipoMensaje, v_err AS Mensaje; LEAVE proc;
    END IF;

    -- ── Escritura ──────────────────────────────────────────────────────────────────────────────
    UPDATE informe_tecnico
    SET    responsable_nombre    = IF(v_h_datos = 1, v_r_nom, responsable_nombre),
           responsable_cargo     = IF(v_h_datos = 1, v_r_car, responsable_cargo),
           responsable_telefono  = IF(v_h_datos = 1, v_r_tel, responsable_telefono),
           detalle_servicio      = IF(v_h_det = 1, JSON_REMOVE(JSON_SET(JSON_EXTRACT(p_json, '$.detalle'), '$.tipoEquipo', IFNULL(v_d_tipo, '')), '$.checks'), detalle_servicio),
           comentario_pruebas    = IF(v_h_com = 1, v_com, comentario_pruebas),
           sin_recomendaciones   = IF(v_h_sinrec = 1, IF(v_sinrec IN ('true', '1'), 1, 0), sin_recomendaciones),
           sin_fallas            = IF(v_h_sinfal = 1, IF(v_sinfal IN ('true', '1'), 1, 0), sin_fallas),
           severidad_general     = IF(v_h_diag = 1, v_sev, severidad_general),
           estado_equipo_final   = IF(v_h_diag = 1, v_est_eq, estado_equipo_final),
           rev_jefatura          = IF(v_h_diag = 1, IF(v_t_rev IN ('true', '1'), 1, 0), rev_jefatura),
           requiere_precotizacion= IF(v_h_diag = 1, IF(v_t_pre IN ('true', '1'), 1, 0), requiere_precotizacion),
           segunda_visita        = IF(v_h_diag = 1, IF(v_t_seg IN ('true', '1'), 1, 0), segunda_visita),
           aplica_garantia       = IF(v_h_diag = 1, IF(v_t_gar IN ('true', '1'), 1, 0), aplica_garantia),
           cabecera_guardada_en  = NOW(), modificado_por = p_id_usuario
    WHERE  id_informe = v_informe;

    -- Checklist de Detalle Serv.: todos los pasos del tipo de orden, con lo marcado
    IF v_h_det = 1 THEN
        UPDATE informe_procedimiento SET eliminado_en = NOW(), eliminado_por = p_id_usuario
        WHERE  id_informe = v_informe AND origen = 'tecnico' AND codigo IS NOT NULL AND eliminado_en IS NULL;
        INSERT INTO informe_procedimiento (id_informe, orden, titulo, realizado, origen, creado_por, codigo)
        SELECT v_informe, m.Num1, m.String1, IF(c.codigo IS NULL, 0, 1), 'tecnico', p_id_usuario, m.String2
        FROM   tabla_maestra m
        LEFT JOIN tmp_cab_chk c ON c.codigo = m.String2
        WHERE  m.Descripcion = 'CHECKLIST_SERVICIO' AND m.IdEmpresa = 1 AND m.String3 = v_tipo AND m.eliminado_en IS NULL
        ORDER BY m.Num1;
    END IF;

    -- Recomendaciones inmediatas
    IF v_h_rec = 1 THEN
        UPDATE informe_recomendacion SET eliminado_en = NOW(), eliminado_por = p_id_usuario
        WHERE  id_informe = v_informe AND origen = 'tecnico' AND eliminado_en IS NULL;
        INSERT INTO informe_recomendacion (id_informe, codigo, orden, titulo, descripcion, prioridad, plazo, origen, creado_por)
        SELECT v_informe, CONCAT('REC-', LPAD(r.n, 2, '0')), r.n, LEFT(TRIM(r.titulo), 200), NULLIF(TRIM(r.descripcion), ''), IFNULL(r.prioridad, 'alta'), 'Inmediato', 'tecnico', p_id_usuario
        FROM   tmp_cab_rec r ORDER BY r.n;
    END IF;

    -- Fallas con su prueba y sus fotos
    IF v_h_fal = 1 THEN
        UPDATE evidencia_fotografica SET id_observacion = NULL
        WHERE  id_os = p_id_os AND id_equipo = v_id_eq AND codigo = 'falla'
          AND  id_observacion IN (SELECT o.id_observacion FROM informe_observacion o WHERE o.id_informe = v_informe AND o.origen = 'tecnico' AND o.eliminado_en IS NULL);
        UPDATE informe_observacion_prueba p JOIN informe_observacion o ON o.id_observacion = p.id_observacion
        SET    p.eliminado_en = NOW(), p.eliminado_por = p_id_usuario
        WHERE  o.id_informe = v_informe AND o.origen = 'tecnico' AND o.eliminado_en IS NULL AND p.eliminado_en IS NULL;
        UPDATE informe_observacion SET eliminado_en = NOW(), eliminado_por = p_id_usuario
        WHERE  id_informe = v_informe AND origen = 'tecnico' AND eliminado_en IS NULL;

        -- E = I − L, EMP y conformidad de cada lectura de prueba: aquí, una sola vez
        SET v_i = 0;
        WHILE v_i < v_n_pru DO
            SELECT p.id, p.carga INTO v_fila, v_carga FROM tmp_cab_pru p ORDER BY p.id LIMIT 1 OFFSET v_i;
            CALL SP_EmpEnsayoMovil(v_clase, v_e, v_carga, v_emp);
            UPDATE tmp_cab_pru SET emp = v_emp WHERE id = v_fila;
            SET v_i = v_i + 1;
        END WHILE;
        UPDATE tmp_cab_pru SET err = ind - carga, res = IF(emp IS NULL, NULL, IF(ABS(ind - carga) <= emp, 'conforme', 'no_conforme'));

        SET v_i = 1;
        WHILE v_i <= v_n_fal DO
            SELECT f.clasificacion, f.componente, f.severidad, TRIM(f.descripcion) INTO v_f_cla, v_f_com, v_f_sev, v_f_des FROM tmp_cab_fal f WHERE f.n = v_i;
            SELECT m.String1 INTO v_cla_nom FROM tabla_maestra m WHERE m.Descripcion = 'CLASIFICACION_FALLA' AND m.IdEmpresa = 1 AND m.String2 = v_f_cla LIMIT 1;
            SELECT m.String1 INTO v_com_nom FROM tabla_maestra m WHERE m.Descripcion = 'COMPONENTE_FALLA' AND m.IdEmpresa = 1 AND m.String2 = v_f_com LIMIT 1;
            INSERT INTO informe_observacion (id_informe, codigo, orden, titulo, descripcion, ubicacion, detalle_extra, nivel_afectacion, origen, creado_por, clasificacion, componente)
            VALUES (v_informe, CONCAT('OBS-', LPAD(v_i, 2, '0')), v_i, LEFT(v_com_nom, 200), v_f_des, LEFT(v_com_nom, 200), LEFT(v_cla_nom, 200),
                    CASE v_f_sev WHEN 'baja' THEN 'bajo' WHEN 'media' THEN 'medio' WHEN 'alta' THEN 'alto' ELSE 'critico' END, 'tecnico', p_id_usuario, v_f_cla, v_f_com);
            SET v_obs = LAST_INSERT_ID();
            INSERT INTO informe_observacion_prueba (id_observacion, tipo, orden, posicion, carga, indicacion, error, emp, resultado, creado_por)
            SELECT v_obs, p.tipo, p.m, p.posicion, p.carga, p.ind, p.err, p.emp, p.res, p_id_usuario FROM tmp_cab_pru p WHERE p.falla = v_i ORDER BY p.m;
            UPDATE evidencia_fotografica e JOIN tmp_cab_foto ft ON ft.id_evidencia = e.id_evidencia
            SET    e.id_observacion = v_obs
            WHERE  ft.falla = v_i;
            SET v_i = v_i + 1;
        END WHILE;
    END IF;

    SELECT TRIM(CONCAT(IFNULL(u.nombre, ''), ' ', IFNULL(u.apellido, ''))) INTO v_nombre_tec FROM usuario u WHERE u.id_usuario = p_id_usuario LIMIT 1;
    INSERT INTO auditoria_evento (entidad_tipo, id_entidad, accion, estado_anterior, estado_nuevo, descripcion, id_usuario, registrado_en, metadata)
    VALUES ('informe_tecnico', v_informe, 'guardar_cabecera', NULL, NULL,
            LEFT(CONCAT(IFNULL(v_nombre_tec, 'El técnico'), ' guardó la cabecera del informe del equipo de ', v_num_os, ' (', v_tipo, ').'), 300),
            p_id_usuario, NOW(),
            JSON_OBJECT('id_os', p_id_os, 'id_os_equipo', p_id_os_equipo,
                        'secciones', JSON_ARRAY(IF(v_h_datos = 1, 'datos', NULL), IF(v_h_det = 1, 'detalle', NULL), IF(v_h_rec = 1, 'recomendaciones', NULL),
                                                IF(v_h_fal = 1, 'fallas', NULL), IF(v_h_diag = 1, 'diagnostico', NULL)),
                        'n_fallas', v_n_fal, 'n_recomendaciones', v_n_rec));

    COMMIT;

    DROP TEMPORARY TABLE IF EXISTS tmp_cab_rec;
    DROP TEMPORARY TABLE IF EXISTS tmp_cab_fal;
    DROP TEMPORARY TABLE IF EXISTS tmp_cab_pru;
    DROP TEMPORARY TABLE IF EXISTS tmp_cab_foto;
    DROP TEMPORARY TABLE IF EXISTS tmp_cab_chk;

    SELECT 2 AS IdTipoMensaje, 'Cabecera del informe guardada.' AS Mensaje;
    SELECT v_informe AS id_informe, NOW() AS guardada_en, v_n_fal AS n_fallas, v_n_rec AS n_recomendaciones;
END$$

DELIMITER ;
