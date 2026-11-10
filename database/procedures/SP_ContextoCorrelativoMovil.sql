-- ============================================================
-- SP_ContextoCorrelativoMovil  (App Mobile HU-14 — apoyo, NO es un endpoint)
-- Valida y arma, UNA sola vez, el contexto del técnico para pedir / usar el correlativo de un equipo: la OS es suya, Hard Stop de llegada y equipo iniciado
-- (SP_ContextoEquipoMovil), los datos del equipo y el estado de su informe técnico. Deja UNA fila en la tabla temporal `tmp_cc_ctx` (quien la llame debe
-- terminar con DROP TEMPORARY TABLE IF EXISTS tmp_cc_ctx). `mensaje` trae el texto para el técnico cuando algo impide continuar (lo demás queda NULL).
--   tipo_orden: según la RQ, servicio técnico → OS, metrología → OM (igual que SP_ObtenerTrabajoEquipoMovil).
--   ens_final: cuándo se finalizaron los ensayos (HU-10). resultado: Conforme / No conforme (resultado_global que deja HU-10) o NULL.
--   tecnico_metrologia: el técnico recibe la reserva diaria de correlativos (SP_ArmarTecnicosMetrologiaMovil).
-- Solo lectura.
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ContextoCorrelativoMovil;

DELIMITER $$

CREATE PROCEDURE SP_ContextoCorrelativoMovil(
    IN p_id_usuario   BIGINT,
    IN p_id_os        BIGINT,
    IN p_id_os_equipo BIGINT
)
BEGIN
    DECLARE v_msg      VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_id_eq    BIGINT DEFAULT NULL;
    DECLARE v_est_eq   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_hab      TINYINT DEFAULT 0;
    DECLARE v_numero   INT DEFAULT NULL;
    DECLARE v_nombre   VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_num_os   VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_servicio VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_area     VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_rq       VARCHAR(20)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_informe  BIGINT DEFAULT NULL;
    DECLARE v_final    DATETIME DEFAULT NULL;
    DECLARE v_global   VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_cert     VARCHAR(50)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_critico  VARCHAR(300) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_serie    VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_cod_cli  VARCHAR(80)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_cod_tw   VARCHAR(30)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_clase    VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_alcance  VARCHAR(40)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_es_tec   TINYINT DEFAULT 0;

    CALL SP_ContextoEquipoMovil(p_id_usuario, p_id_os, p_id_os_equipo, v_msg, v_id_eq, v_est_eq, v_hab, v_numero, v_nombre, v_num_os, v_servicio);

    IF v_msg IS NULL THEN
        SELECT asr.area_usuario, rq.numero INTO v_area, v_rq
        FROM   orden_servicio os
        JOIN   expediente_digital ed  ON ed.id_expediente = os.id_expediente
        JOIN   requerimiento      rq  ON rq.id_requerimiento = ed.id_requerimiento
        LEFT JOIN area_servicio_rq asr ON asr.id_area_rq = rq.id_area
        WHERE  os.id_os = p_id_os LIMIT 1;

        SELECT it.id_informe, it.ensayos_finalizado_en, it.resultado_global, it.numero_certificado, it.error_critico_motivo
        INTO   v_informe, v_final, v_global, v_cert, v_critico
        FROM   informe_tecnico it
        WHERE  it.id_os = p_id_os AND it.id_equipo = v_id_eq AND it.eliminado_en IS NULL
        ORDER BY it.id_informe DESC LIMIT 1;

        SELECT ec.num_serie, ec.codigo_cliente, ec.codigo_tw, ec.clase_exactitud, ec.alcance_maximo
        INTO   v_serie, v_cod_cli, v_cod_tw, v_clase, v_alcance
        FROM   equipo_cliente ec WHERE ec.id_equipo = v_id_eq LIMIT 1;

        CALL SP_ArmarTecnicosMetrologiaMovil();
        SELECT COUNT(*) INTO v_es_tec FROM tmp_tm_tec WHERE id_usuario = p_id_usuario;
        DROP TEMPORARY TABLE IF EXISTS tmp_tm_tec;
    END IF;

    DROP TEMPORARY TABLE IF EXISTS tmp_cc_ctx;
    CREATE TEMPORARY TABLE tmp_cc_ctx (
        mensaje VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        id_os BIGINT, id_os_equipo BIGINT, id_equipo BIGINT, numero_os VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        nombre_equipo VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, numero INT, estado_equipo VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        habilitado TINYINT, tipo_orden VARCHAR(2) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci, numero_rq VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
        id_informe BIGINT NULL, ens_final DATETIME NULL, resultado VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        numero_certificado VARCHAR(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        num_serie VARCHAR(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL, codigo_cliente VARCHAR(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        codigo_tw VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL, clase VARCHAR(10) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL,
        capacidad VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NULL, tecnico_metrologia TINYINT);

    INSERT INTO tmp_cc_ctx
    VALUES (v_msg, p_id_os, p_id_os_equipo, v_id_eq, v_num_os, v_nombre, v_numero, v_est_eq, v_hab, IF(v_area = 'metrologia', 'OM', 'OS'), v_rq,
            v_informe, v_final,
            IF(v_final IS NULL, NULL, IF(v_global = 'fuera' OR v_critico IS NOT NULL, 'No conforme', 'Conforme')),
            v_cert, v_serie, v_cod_cli, v_cod_tw, v_clase, v_alcance, v_es_tec);
END$$

DELIMITER ;
