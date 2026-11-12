-- ============================================================
-- SP_RevisarGastoMovil  (App Mobile HU-31 — el Jefe de Operaciones aprueba, observa o rechaza un gasto desde la bandeja de aprobaciones · escritura)
--   Resuelve la programación del gasto y llama a SP_RevisarGastoProgramacion (HU-45), que valida: solo prog_aprobar_reprogramacion, programación confirmada,
--   rendición abierta, acción aprobar | observar | rechazar con su comentario (obligatorio al observar o rechazar) y que un gasto ya aprobado o rechazado
--   no se vuelve a resolver (si otro jefe ya lo resolvió responde con un mensaje de negocio). Notifica al técnico y deja auditoría.
-- Resultados: los de SP_RevisarGastoProgramacion (1 mensaje, 2 gasto resultante, 3 tarjetas de la rendición).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_RevisarGastoMovil;

DELIMITER $$

CREATE PROCEDURE SP_RevisarGastoMovil(
    IN p_id_usuario BIGINT,
    IN p_id_gasto   BIGINT,
    IN p_accion     VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_comentario VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_n    INT DEFAULT 0;
    DECLARE v_id_os BIGINT;
    DECLARE v_prog BIGINT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF FN_PermisoAccion(p_id_usuario, 'prog_aprobar_reprogramacion') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Solo el Jefe de Operaciones puede revisar los gastos rendidos.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF IFNULL(p_id_gasto, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El gasto no existe.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT COUNT(*), MAX(id_os), MAX(id_programacion) INTO v_n, v_id_os, v_prog
    FROM gasto_viatico WHERE id_gasto = p_id_gasto AND tipo = 'gasto_solicitado' AND eliminado_en IS NULL;
    IF v_n = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El gasto no existe.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_prog IS NULL THEN
        SELECT MAX(id_programacion) INTO v_prog FROM programacion WHERE id_os = v_id_os AND estado <> 'cancelada' AND eliminado_en IS NULL;
    END IF;
    IF v_prog IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'El servicio del gasto no tiene una programación activa.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_RevisarGastoProgramacion(p_id_usuario, v_prog, p_id_gasto, p_accion, p_comentario);
END$$

DELIMITER ;
