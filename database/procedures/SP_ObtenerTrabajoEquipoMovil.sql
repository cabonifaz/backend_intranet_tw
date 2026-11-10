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
    DECLARE v_ev_total    INT DEFAULT 9;
    DECLARE v_ev_compl    INT DEFAULT 0;
    DECLARE v_ev_forz     INT DEFAULT 0;
    DECLARE v_ev_rech     INT DEFAULT 0;
    DECLARE v_ev_oblig    INT DEFAULT 0;
    DECLARE v_ens_final   DATETIME DEFAULT NULL;
    DECLARE v_ens_motivo  VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_cert        VARCHAR(50)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_tk_estado   VARCHAR(12)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_tk_num      VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_obj_mov;
        DROP TEMPORARY TABLE IF EXISTS tmp_etapas_mov;
        DROP TEMPORARY TABLE IF EXISTS tmp_cat_evid;
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

    -- Registro fotográfico (HU-11): el avance lo calcula SP_ResumenEvidenciasMovil, una sola vez
    CALL SP_ResumenEvidenciasMovil(p_id_os, v_id_equipo, v_ev_total, v_ev_compl, v_ev_forz, v_ev_rech, v_ev_oblig);
    DROP TEMPORARY TABLE IF EXISTS tmp_cat_evid;
    SET v_n_fotos = v_ev_compl;

    SELECT it.id_informe, it.ensayos_finalizado_en, it.error_critico_motivo, it.numero_certificado INTO v_informe, v_ens_final, v_ens_motivo, v_cert
    FROM   informe_tecnico it
    WHERE  it.id_os = p_id_os AND it.id_equipo = v_id_equipo AND it.eliminado_en IS NULL
    ORDER BY it.id_informe DESC LIMIT 1;
    IF v_informe IS NOT NULL THEN
        SELECT COUNT(*) INTO v_n_ensayos FROM informe_ensayo ie WHERE ie.id_informe = v_informe AND ie.eliminado_en IS NULL;
    END IF;

    -- Correlativo y certificado (HU-14): el ticket abierto de este equipo en Metrología (solicitado o asignado)
    SELECT t.estado, t.numero INTO v_tk_estado, v_tk_num
    FROM   ticket_metrologia t
    WHERE  t.id_os = p_id_os AND t.id_equipo = v_id_equipo AND t.estado IN ('solicitado', 'asignado') AND t.eliminado_en IS NULL
    ORDER BY t.id_ticket_met DESC LIMIT 1;

    DROP TEMPORARY TABLE IF EXISTS tmp_etapas_mov;
    CREATE TEMPORARY TABLE tmp_etapas_mov (
        orden INT NOT NULL, codigo VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, nombre VARCHAR(60) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        estado VARCHAR(12) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, detalle VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        disponible TINYINT DEFAULT 0, PRIMARY KEY (orden));

    INSERT INTO tmp_etapas_mov (orden, codigo, nombre, estado, detalle, disponible) VALUES
        (1, 'variables', 'Variables ambientales', IF(v_vars > 0, 'conforme', 'pendiente'),
            IF(v_vars > 0, v_det_vars, 'Temperatura, humedad y procedencia'), 1),
        (2, 'fotos', 'Registro fotográfico', IF(v_ev_compl >= v_ev_total, 'conforme', IF(v_ev_compl > 0 OR v_ev_rech > 0, 'en_curso', 'pendiente')),
            CONCAT(v_ev_compl, ' de ', v_ev_total, ' · incluye foto del informe a mano',
                   IF(v_ev_forz > 0, CONCAT(' · ', v_ev_forz, IF(v_ev_forz = 1, ' forzada', ' forzadas')), '')), 1),
        (3, 'ensayos', 'Ensayos y Calibración',
            IF(v_vars = 0, 'bloqueado', IF(v_ens_final IS NOT NULL, 'conforme', IF(v_n_ensayos > 0, 'en_curso', 'pendiente'))),
            IF(v_vars = 0, 'Se habilita al guardar las variables ambientales',
               IF(v_ens_final IS NOT NULL, IF(v_ens_motivo IS NULL, 'Pesaje y excentricidad conformes', 'Finalizado con error crítico: se avisó al encargado'),
                  IF(v_n_ensayos > 0, CONCAT(v_n_ensayos, ' lecturas guardadas · falta finalizar'), 'Verificación de pesaje tras el ajuste'))), 1),
        (4, 'cabecera', 'Cabecera del informe', IF(v_informe IS NOT NULL, 'en_curso', 'pendiente'), 'Datos · Detalle Serv. · Observación y pruebas', 0),
        (5, 'correlativo', 'Correlativo y certificado',
            IF(v_cert IS NOT NULL, 'conforme', IF(v_ens_final IS NULL, 'bloqueado', IF(v_tk_estado IS NOT NULL, 'en_curso', 'pendiente'))),
            IF(v_cert IS NOT NULL, CONCAT('Certificado ', v_cert),
               IF(v_ens_final IS NULL, 'Se habilita al finalizar los ensayos',
                  IF(v_tk_estado = 'asignado', CONCAT(v_tk_num, ' asignado · listo para usar'),
                     IF(v_tk_estado = 'solicitado', CONCAT(v_tk_num, ' · esperando a Metrología'), 'Correlativo de Metrología → N° de certificado')))), 1);

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
