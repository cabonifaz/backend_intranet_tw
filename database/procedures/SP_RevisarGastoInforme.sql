-- Revisar (aprobar, observar o rechazar) un gasto rendido desde la pestaña Viáticos y Gastos del Detalle del Servicio Técnico (Revisión de Informes).
--   Resuelve informe → OS (SP_ResolverOsInformeViaticos: rt_bandeja y alcance del informe); comprueba que el gasto sea un gasto rendido de ESA OS (anti-IDOR) y llama a
--   SP_RevisarGastoProgramacion (HU-45), que es quien exige que revise solo el Jefe de Operaciones (prog_aprobar_reprogramacion), con la programación confirmada,
--   la rendición abierta y la acción con su comentario. Es la misma regla que la revisión del Seguimiento (SP_RevisarGastoServicioRuta).
-- Resultados: los de SP_RevisarGastoProgramacion (1 mensaje, 2 gasto resultante, 3 tarjetas de la rendición).
DROP PROCEDURE IF EXISTS SP_RevisarGastoInforme;

DELIMITER $$

CREATE PROCEDURE SP_RevisarGastoInforme(
    IN p_id_usuario BIGINT,
    IN p_id_informe BIGINT,
    IN p_id_gasto   BIGINT,
    IN p_accion     VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_comentario VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_msg   VARCHAR(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
    DECLARE v_id_os BIGINT;
    DECLARE v_n     INT DEFAULT 0;
    DECLARE v_prog  BIGINT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        DROP TEMPORARY TABLE IF EXISTS tmp_rt_base;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    CALL SP_ResolverOsInformeViaticos(p_id_usuario, p_id_informe, v_id_os, v_msg);
    IF v_msg IS NOT NULL THEN
        SELECT 1 AS IdTipoMensaje, v_msg AS Mensaje;
        LEAVE proc;
    END IF;
    IF IFNULL(p_id_gasto, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El gasto indicado no es válido.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT COUNT(*), MAX(g.id_programacion) INTO v_n, v_prog
    FROM gasto_viatico g
    JOIN orden_servicio os ON os.id_os = g.id_os AND os.eliminado_en IS NULL
    WHERE g.id_gasto = p_id_gasto AND g.id_os = v_id_os AND g.tipo = 'gasto_solicitado' AND g.eliminado_en IS NULL;
    IF v_n = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El gasto no pertenece a la orden de servicio de este informe.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_prog IS NULL THEN
        SELECT MAX(id_programacion) INTO v_prog
        FROM programacion WHERE id_os = v_id_os AND estado <> 'cancelada' AND eliminado_en IS NULL;
    END IF;
    IF v_prog IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'El servicio no tiene una programación activa.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_RevisarGastoProgramacion(p_id_usuario, v_prog, p_id_gasto, p_accion, p_comentario);
END$$

DELIMITER ;
