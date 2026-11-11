-- ============================================================
-- SP_ValidarCierreEquipoMovil  (App Mobile HU-16 — Hard Stop de "Finalizar trabajo en equipo" · solo lectura)
-- Al tocar "Finalizar trabajo en equipo" el servidor valida las 5 etapas con la MISMA regla que pinta la pantalla de Trabajo en el equipo
-- (SP_ArmarEtapasEquipoMovil, una sola vez) y responde SIEMPRE: o "Validación completa" o los pendientes por etapa. No escribe nada.
--   - La OS debe ser del técnico, con la llegada registrada y el equipo iniciado (SP_ContextoEquipoMovil). Un equipo pausado debe reanudarse primero.
--   - puede_generar = las 5 etapas conformes Y el equipo en ejecución Y el informe aún no generado (ya_generado = 1 → la app va directo a Firma de informes).
--   - Un ensayo finalizado con error crítico es NO CONFORME y bloquea el cierre, igual que una evidencia, la cabecera o el correlativo pendientes.
-- Resultados: 1 mensaje · 2 resumen (1 fila: puede_generar, ya_generado, numero_informe, conformes, total, pendientes, estado_equipo, equipo, numero_os) ·
--   3 etapas (5 filas: orden, codigo, nombre, estado, detalle, n_pendientes) · 4 pendientes (orden, codigo, texto).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_ValidarCierreEquipoMovil;

DELIMITER $$

CREATE PROCEDURE SP_ValidarCierreEquipoMovil(
    IN p_id_usuario   BIGINT,
    IN p_id_os        BIGINT,
    IN p_id_os_equipo BIGINT
)
proc: BEGIN
    DECLARE v_msg       VARCHAR(250) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_id_eq     BIGINT DEFAULT NULL;
    DECLARE v_estado    VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_hab       TINYINT DEFAULT 0;
    DECLARE v_numero    INT DEFAULT NULL;
    DECLARE v_nombre    VARCHAR(150) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_num_os    VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_servicio  VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;
    DECLARE v_conformes INT DEFAULT 0;
    DECLARE v_n_pend    INT DEFAULT 0;
    DECLARE v_gen       DATETIME DEFAULT NULL;
    DECLARE v_num_inf   VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_etapas_mov;
        DROP TEMPORARY TABLE IF EXISTS tmp_pend_eq;
        DROP TEMPORARY TABLE IF EXISTS tmp_cat_evid;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_usuario, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 OR IFNULL(p_id_os_equipo, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio o equipo no encontrado.' AS Mensaje; LEAVE proc;
    END IF;

    CALL SP_ContextoEquipoMovil(p_id_usuario, p_id_os, p_id_os_equipo, v_msg, v_id_eq, v_estado, v_hab, v_numero, v_nombre, v_num_os, v_servicio);
    IF v_msg IS NULL AND v_estado = 'pausado' THEN
        SET v_msg = 'El equipo está pausado: reanúdalo para finalizar el trabajo.';
    END IF;
    IF v_msg IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje; LEAVE proc;
    END IF;

    CALL SP_ArmarEtapasEquipoMovil(p_id_os, v_id_eq, v_conformes);
    SELECT COUNT(*) INTO v_n_pend FROM tmp_pend_eq;
    SELECT it.generado_en, it.numero_informe INTO v_gen, v_num_inf
    FROM   informe_tecnico it
    WHERE  it.id_os = p_id_os AND it.id_equipo = v_id_eq AND it.eliminado_en IS NULL
    ORDER BY it.id_informe DESC LIMIT 1;

    SELECT 2 AS IdTipoMensaje, IF(v_conformes = 5, 'Validación completa.', 'No es posible finalizar el trabajo en el equipo.') AS Mensaje;

    SELECT IF(v_conformes = 5 AND v_estado = 'en_ejecucion' AND v_gen IS NULL, 1, 0) AS puede_generar,
           IF(v_gen IS NULL, 0, 1) AS ya_generado, v_num_inf AS numero_informe,
           v_conformes AS conformes, 5 AS total, v_n_pend AS pendientes, v_estado AS estado_equipo,
           CONCAT(IFNULL(v_nombre, 'Equipo'), ' #', LPAD(IFNULL(v_numero, 0), 2, '0')) AS equipo, v_num_os AS numero_os;

    SELECT e.orden, e.codigo, e.nombre, e.estado, e.detalle,
           (SELECT COUNT(*) FROM tmp_pend_eq p WHERE p.orden = e.orden) AS n_pendientes
    FROM   tmp_etapas_mov e
    ORDER BY e.orden;

    SELECT p.orden, p.codigo, p.texto FROM tmp_pend_eq p ORDER BY p.orden, p.id;

    DROP TEMPORARY TABLE IF EXISTS tmp_etapas_mov;
    DROP TEMPORARY TABLE IF EXISTS tmp_pend_eq;
END$$

DELIMITER ;
