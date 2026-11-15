-- HU-52 (Sprint 5) Revisar un gasto rendido desde la pestaña Viáticos del Detalle del Servicio en Ruta.
--   Anti-IDOR: antes de revisar comprueba que el gasto sea un gasto rendido de ESA OS; luego llama a SP_RevisarGastoProgramacion (HU-45), que valida
--   que solo el Jefe de Operaciones (prog_aprobar_reprogramacion) revise, con la programación confirmada y la rendición abierta, y la acción
--   (aprobar | observar | rechazar) con su comentario. Acceso adicional: seg_bandeja (la pestaña es del Seguimiento).
-- Resultados: los de SP_RevisarGastoProgramacion (1 mensaje, 2 gasto resultante, 3 tarjetas de la rendición).
DROP PROCEDURE IF EXISTS SP_RevisarGastoServicioRuta;

DELIMITER $$

CREATE PROCEDURE SP_RevisarGastoServicioRuta(
    IN p_id_usuario BIGINT,
    IN p_id_os      BIGINT,
    IN p_id_gasto   BIGINT,
    IN p_accion     VARCHAR(10)  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci,
    IN p_comentario VARCHAR(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci
)
proc: BEGIN
    DECLARE v_n    INT DEFAULT 0;
    DECLARE v_prog BIGINT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF FN_PermisoAccion(p_id_usuario, 'seg_bandeja') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para ver el seguimiento operativo.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF IFNULL(p_id_os, 0) <= 0 OR IFNULL(p_id_gasto, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El gasto indicado no es válido.' AS Mensaje;
        LEAVE proc;
    END IF;

    SELECT COUNT(*), MAX(g.id_programacion) INTO v_n, v_prog
    FROM gasto_viatico g
    JOIN orden_servicio os ON os.id_os = g.id_os AND os.eliminado_en IS NULL
    WHERE g.id_gasto = p_id_gasto AND g.id_os = p_id_os AND g.tipo = 'gasto_solicitado' AND g.eliminado_en IS NULL;
    IF v_n = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'El gasto no pertenece a este servicio.' AS Mensaje;
        LEAVE proc;
    END IF;
    IF v_prog IS NULL THEN
        SELECT MAX(id_programacion) INTO v_prog
        FROM programacion WHERE id_os = p_id_os AND estado <> 'cancelada' AND eliminado_en IS NULL;
    END IF;
    IF v_prog IS NULL THEN
        SELECT 1 AS IdTipoMensaje, 'El servicio no tiene una programación activa.' AS Mensaje;
        LEAVE proc;
    END IF;

    CALL SP_RevisarGastoProgramacion(p_id_usuario, v_prog, p_id_gasto, p_accion, p_comentario);
END$$

DELIMITER ;
