-- ============================================================
-- SP_ArmarEtapasEquipoMovil  (App Mobile HU-08 / HU-15 / HU-16 — apoyo, NO es un endpoint)
-- Las 5 etapas del trabajo en un equipo y sus PENDIENTES, UNA sola vez. Las leen SP_ObtenerTrabajoEquipoMovil (pantalla "Trabajo en el equipo"),
-- SP_ValidarCierreEquipoMovil (Hard Stop de "Finalizar trabajo en equipo") y SP_GenerarInformeEquipoMovil (generar el informe técnico): así el botón, el
-- modal de pendientes y la generación nunca discrepan. Quien la llame debe terminar con DROP TEMPORARY TABLE IF EXISTS tmp_etapas_mov, tmp_pend_eq.
--   tmp_etapas_mov (orden, codigo, nombre, estado, detalle, disponible):
--     estado: conforme | en_curso | pendiente | bloqueado | no_conforme (Ensayos finalizados CON error crítico: bloquea el cierre).
--     1 variables   conforme con las variables ambientales guardadas (HU-09).
--     2 fotos       conforme con las 9 evidencias completas: aprobadas por la IA, forzadas o sin validar (SP_ResumenEvidenciasMovil, HU-11 / HU-12).
--     3 ensayos     bloqueado sin variables; conforme al finalizar sin error crítico; NO CONFORME si se finalizó con error crítico (HU-10).
--     4 cabecera    "Cabecera del informe" (HU-15): conforme con la cabecera guardada y sin pendientes (recomendaciones o "sin recomendaciones", fallas o
--                   "sin fallas", Detalle Serv. guardado, Diagnóstico final completo y cada falla con su prueba).
--     5 correlativo conforme con el certificado guardado en el informe (HU-14); bloqueado hasta finalizar los ensayos.
--   tmp_pend_eq (id, orden, codigo, texto): una fila por pendiente con el texto para el técnico ("Falta la foto Final", "Error crítico en 20,000 kg (+34 kg ·
--     EMP ±20 kg)", "Falta completar el Diagnóstico final", "Esperando el correlativo de Metrología (TK-MET-00241)"…). Una etapa conforme no tiene pendientes.
--   p_conformes = etapas conformes de 5.
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ArmarEtapasEquipoMovil;

DELIMITER $$

CREATE PROCEDURE SP_ArmarEtapasEquipoMovil(
    IN  p_id_os     BIGINT,
    IN  p_id_equipo BIGINT,
    OUT p_conformes INT
)
BEGIN
    DECLARE v_vars       TINYINT DEFAULT 0;
    DECLARE v_det_vars   VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_informe    BIGINT DEFAULT NULL;
    DECLARE v_n_ensayos  INT DEFAULT 0;
    DECLARE v_ens_final  DATETIME DEFAULT NULL;
    DECLARE v_ens_motivo VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_cert       VARCHAR(50)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_cab_guard  DATETIME DEFAULT NULL;
    DECLARE v_tiene_det  TINYINT DEFAULT 0;
    DECLARE v_sev        VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_est_fin    VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_sin_rec    TINYINT DEFAULT 0;
    DECLARE v_sin_fal    TINYINT DEFAULT 0;
    DECLARE v_n_rec      INT DEFAULT 0;
    DECLARE v_n_fal      INT DEFAULT 0;
    DECLARE v_clase      VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_unidad     VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_cap        DECIMAL(14,4);
    DECLARE v_d          DECIMAL(14,4);
    DECLARE v_e          DECIMAL(14,4);
    DECLARE v_ev_total   INT DEFAULT 9;
    DECLARE v_ev_compl   INT DEFAULT 0;
    DECLARE v_ev_forz    INT DEFAULT 0;
    DECLARE v_ev_rech    INT DEFAULT 0;
    DECLARE v_ev_oblig   INT DEFAULT 0;
    DECLARE v_tk_estado  VARCHAR(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_tk_num     VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_tk_corr    VARCHAR(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_crit_carga DECIMAL(14,4) DEFAULT NULL;
    DECLARE v_pend_cab   INT DEFAULT 0;
    DECLARE v_prim_cab   VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE s1 VARCHAR(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE s2 VARCHAR(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE s3 VARCHAR(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE s4 VARCHAR(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE s5 VARCHAR(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

    DROP TEMPORARY TABLE IF EXISTS tmp_etapas_mov;
    CREATE TEMPORARY TABLE tmp_etapas_mov (
        orden INT NOT NULL, codigo VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, nombre VARCHAR(60) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        estado VARCHAR(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, detalle VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        disponible TINYINT DEFAULT 0, PRIMARY KEY (orden));
    DROP TEMPORARY TABLE IF EXISTS tmp_pend_eq;
    CREATE TEMPORARY TABLE tmp_pend_eq (
        id INT NOT NULL AUTO_INCREMENT, orden INT NOT NULL, codigo VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        texto VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, PRIMARY KEY (id));

    CALL SP_EspecEquipoMovil(p_id_equipo, v_clase, v_unidad, v_cap, v_d, v_e);

    -- ── 1. Variables ambientales (HU-09) ───────────────────────────────────────────────────────
    SELECT COUNT(*) INTO v_vars FROM variable_ambiental va WHERE va.id_os = p_id_os AND va.id_equipo = p_id_equipo AND va.eliminado_en IS NULL;
    IF v_vars > 0 THEN
        SELECT CONCAT('T° ', TRIM(TRAILING '.' FROM TRIM(TRAILING '0' FROM CAST(va.temperatura_c AS CHAR))), ' °C · h ',
                      TRIM(TRAILING '.' FROM TRIM(TRAILING '0' FROM CAST(va.humedad_pct AS CHAR))), ' % · Procedencia ', IFNULL(va.procedencia, 'N.I'))
        INTO   v_det_vars
        FROM   variable_ambiental va
        WHERE  va.id_os = p_id_os AND va.id_equipo = p_id_equipo AND va.eliminado_en IS NULL
        ORDER BY va.id_variable DESC LIMIT 1;
    ELSE
        INSERT INTO tmp_pend_eq (orden, codigo, texto) VALUES (1, 'variables', 'Faltan las variables ambientales (temperatura y humedad)');
    END IF;

    -- ── 2. Registro fotográfico (HU-11): una pendiente por evidencia que falta ─────────────────
    CALL SP_ResumenEvidenciasMovil(p_id_os, p_id_equipo, v_ev_total, v_ev_compl, v_ev_forz, v_ev_rech, v_ev_oblig);
    INSERT INTO tmp_pend_eq (orden, codigo, texto)
    SELECT 2, 'fotos',
           CASE WHEN c.rechazada = 1 THEN CONCAT('La toma de ', c.nombre, ' fue rechazada: repítela o acéptala con un motivo')
                WHEN c.codigo = 'qr' THEN 'Falta la foto del QR'
                WHEN c.codigo = 'placa' THEN 'Falta la foto de la placa'
                WHEN c.codigo = 'informe' THEN 'Falta la foto del informe a mano'
                WHEN c.medio = 'video' THEN CONCAT('Falta el video de ', LOWER(c.nombre))
                ELSE CONCAT('Falta la foto ', c.nombre) END
    FROM   tmp_cat_evid c
    WHERE  c.completa = 0
    ORDER BY c.orden;
    DROP TEMPORARY TABLE IF EXISTS tmp_cat_evid;

    -- ── Informe técnico del equipo (lo crea la primera captura de ensayos o de la cabecera) ───
    SELECT it.id_informe, it.ensayos_finalizado_en, it.error_critico_motivo, it.numero_certificado, it.cabecera_guardada_en, IF(it.detalle_servicio IS NULL, 0, 1),
           it.severidad_general, it.estado_equipo_final, it.sin_recomendaciones, it.sin_fallas
    INTO   v_informe, v_ens_final, v_ens_motivo, v_cert, v_cab_guard, v_tiene_det, v_sev, v_est_fin, v_sin_rec, v_sin_fal
    FROM   informe_tecnico it
    WHERE  it.id_os = p_id_os AND it.id_equipo = p_id_equipo AND it.eliminado_en IS NULL
    ORDER BY it.id_informe DESC LIMIT 1;
    IF v_informe IS NOT NULL THEN
        SELECT COUNT(*) INTO v_n_ensayos FROM informe_ensayo ie WHERE ie.id_informe = v_informe AND ie.eliminado_en IS NULL;
        SELECT COUNT(*) INTO v_n_rec FROM informe_recomendacion r WHERE r.id_informe = v_informe AND r.origen = 'tecnico' AND r.eliminado_en IS NULL;
        SELECT COUNT(*) INTO v_n_fal FROM informe_observacion o WHERE o.id_informe = v_informe AND o.origen = 'tecnico' AND o.eliminado_en IS NULL;
    END IF;

    -- ── 3. Ensayos y Calibración (HU-10) ───────────────────────────────────────────────────────
    IF v_vars = 0 THEN
        INSERT INTO tmp_pend_eq (orden, codigo, texto) VALUES (3, 'ensayos', 'Se habilita al guardar las variables ambientales');
    ELSEIF v_ens_final IS NULL THEN
        INSERT INTO tmp_pend_eq (orden, codigo, texto) VALUES (3, 'ensayos', 'Falta finalizar los ensayos y la calibración');
    ELSEIF v_ens_motivo IS NOT NULL THEN
        -- Finalizado CON error crítico: una pendiente por cada lectura fuera del EMP (carga, error con signo y EMP)
        INSERT INTO tmp_pend_eq (orden, codigo, texto)
        SELECT 3, 'ensayos',
               LEFT(CONCAT('Error crítico en ', FORMAT(en.carga, 0), ' ', v_unidad, ' (', IF(en.error >= 0, '+', ''),
                           TRIM(TRAILING '.' FROM TRIM(TRAILING '0' FROM CAST(ROUND(en.error, 4) AS CHAR))), ' ', v_unidad, ' · EMP ±',
                           IFNULL(TRIM(TRAILING '.' FROM TRIM(TRAILING '0' FROM CAST(ROUND(en.tolerancia, 4) AS CHAR))), '?'), ' ', v_unidad, ')'), 250)
        FROM   informe_ensayo en
        WHERE  en.id_informe = v_informe AND en.eliminado_en IS NULL AND en.critico = 1
        ORDER BY en.tipo, en.grupo, en.orden;
        SELECT MIN(en.carga) INTO v_crit_carga FROM informe_ensayo en WHERE en.id_informe = v_informe AND en.eliminado_en IS NULL AND en.critico = 1;
        IF NOT EXISTS (SELECT 1 FROM tmp_pend_eq WHERE orden = 3) THEN
            INSERT INTO tmp_pend_eq (orden, codigo, texto) VALUES (3, 'ensayos', 'El ensayo se guardó con un error crítico: repítelo o corrige la lectura');
        END IF;
    END IF;

    -- ── 4. Cabecera del informe (HU-15) ────────────────────────────────────────────────────────
    IF v_cab_guard IS NULL THEN
        INSERT INTO tmp_pend_eq (orden, codigo, texto) VALUES (4, 'cabecera', 'Falta completar la cabecera del informe (Datos, Detalle Serv. y Observación y pruebas)');
    ELSE
        IF v_tiene_det = 0 THEN
            INSERT INTO tmp_pend_eq (orden, codigo, texto) VALUES (4, 'cabecera', 'Falta completar el Detalle del servicio');
        END IF;
        IF v_n_rec = 0 AND v_sin_rec = 0 THEN
            INSERT INTO tmp_pend_eq (orden, codigo, texto) VALUES (4, 'cabecera', 'Faltan las recomendaciones inmediatas (o indicar que no hay)');
        END IF;
        IF v_n_fal = 0 AND v_sin_fal = 0 THEN
            INSERT INTO tmp_pend_eq (orden, codigo, texto) VALUES (4, 'cabecera', 'Faltan las fallas del equipo (o indicar que no hay)');
        END IF;
        INSERT INTO tmp_pend_eq (orden, codigo, texto)
        SELECT 4, 'cabecera', LEFT(CONCAT('La falla ', o.codigo, ' no tiene una prueba que la justifique'), 250)
        FROM   informe_observacion o
        WHERE  o.id_informe = v_informe AND o.origen = 'tecnico' AND o.eliminado_en IS NULL
          AND  NOT EXISTS (SELECT 1 FROM informe_observacion_prueba p WHERE p.id_observacion = o.id_observacion AND p.eliminado_en IS NULL)
        ORDER BY o.orden;
        IF v_sev IS NULL OR v_est_fin IS NULL THEN
            INSERT INTO tmp_pend_eq (orden, codigo, texto) VALUES (4, 'cabecera', 'Falta completar el Diagnóstico final');
        END IF;
    END IF;
    SELECT COUNT(*) INTO v_pend_cab FROM tmp_pend_eq WHERE orden = 4;
    SELECT texto INTO v_prim_cab FROM tmp_pend_eq WHERE orden = 4 ORDER BY id LIMIT 1;

    -- ── 5. Correlativo y certificado (HU-14) ───────────────────────────────────────────────────
    SELECT t.estado, t.numero, t.correlativo_asignado INTO v_tk_estado, v_tk_num, v_tk_corr
    FROM   ticket_metrologia t
    WHERE  t.id_os = p_id_os AND t.id_equipo = p_id_equipo AND t.estado IN ('solicitado', 'asignado') AND t.eliminado_en IS NULL
    ORDER BY t.id_ticket_met DESC LIMIT 1;
    IF v_cert IS NULL THEN
        INSERT INTO tmp_pend_eq (orden, codigo, texto)
        VALUES (5, 'correlativo',
                CASE WHEN v_ens_final IS NULL THEN 'Se habilita al finalizar los ensayos y la calibración'
                     WHEN v_tk_estado = 'asignado' THEN CONCAT('Falta usar el correlativo asignado (', IFNULL(v_tk_corr, ''), ')')
                     WHEN v_tk_estado = 'solicitado' THEN CONCAT('Esperando el correlativo de Metrología (', v_tk_num, ')')
                     ELSE 'Falta solicitar el correlativo de Metrología' END);
    END IF;

    -- ── Estados y detalle de las 5 etapas ──────────────────────────────────────────────────────
    SET s1 = IF(v_vars > 0, 'conforme', 'pendiente');
    SET s2 = IF(v_ev_compl >= v_ev_total, 'conforme', IF(v_ev_compl > 0 OR v_ev_rech > 0, 'en_curso', 'pendiente'));
    SET s3 = IF(v_vars = 0, 'bloqueado', IF(v_ens_final IS NOT NULL, IF(v_ens_motivo IS NULL, 'conforme', 'no_conforme'), IF(v_n_ensayos > 0, 'en_curso', 'pendiente')));
    SET s4 = IF(v_cab_guard IS NOT NULL AND v_pend_cab = 0, 'conforme', IF(v_cab_guard IS NOT NULL, 'en_curso', 'pendiente'));
    SET s5 = IF(v_cert IS NOT NULL, 'conforme', IF(v_ens_final IS NULL, 'bloqueado', IF(v_tk_estado IS NOT NULL, 'en_curso', 'pendiente')));

    INSERT INTO tmp_etapas_mov (orden, codigo, nombre, estado, detalle, disponible) VALUES
        (1, 'variables', 'Variables ambientales', s1, IF(v_vars > 0, v_det_vars, 'Temperatura, humedad y procedencia'), 1),
        (2, 'fotos', 'Registro fotográfico', s2,
            CONCAT(v_ev_compl, ' de ', v_ev_total, ' · incluye foto del informe a mano', IF(v_ev_forz > 0, CONCAT(' · ', v_ev_forz, IF(v_ev_forz = 1, ' forzada', ' forzadas')), '')), 1),
        (3, 'ensayos', 'Ensayos y Calibración', s3,
            IF(v_vars = 0, 'Se habilita al guardar las variables ambientales',
               IF(v_ens_final IS NOT NULL,
                  IF(v_ens_motivo IS NULL, 'Pesaje y excentricidad conformes',
                     CONCAT('Pesaje guardado con error crítico', IF(v_crit_carga IS NULL, '', CONCAT(' (', FORMAT(v_crit_carga, 0), ' ', v_unidad, ')')))),
                  IF(v_n_ensayos > 0, CONCAT(v_n_ensayos, ' lecturas guardadas · falta finalizar'), 'Verificación de pesaje tras el ajuste'))), 1),
        (4, 'cabecera', 'Cabecera del informe', s4,
            IF(s4 = 'conforme', 'Cabecera completa', IF(s4 = 'en_curso', v_prim_cab, 'Datos · Detalle Serv. · Observación y pruebas')), 1),
        (5, 'correlativo', 'Correlativo y certificado', s5,
            IF(v_cert IS NOT NULL, CONCAT('Certificado ', v_cert),
               IF(v_ens_final IS NULL, 'Se habilita al finalizar los ensayos',
                  IF(v_tk_estado = 'asignado', CONCAT(v_tk_num, ' asignado · listo para usar'),
                     IF(v_tk_estado = 'solicitado', CONCAT(v_tk_num, ' · esperando a Metrología'), 'Correlativo de Metrología → N° de certificado')))), 1);

    SELECT COUNT(*) INTO p_conformes FROM tmp_etapas_mov WHERE estado = 'conforme';
END$$

DELIMITER ;
