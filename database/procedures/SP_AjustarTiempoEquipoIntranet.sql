-- ============================================================
-- SP_AjustarTiempoEquipoIntranet  (HU-55 — fija el tiempo trabajado del equipo justo antes de generar el informe · escritura)
-- SP_GenerarInformeEquipoMovil cierra el tiempo del equipo sumando (ahora − reanudado_utc). En un registro desde la intranet el tiempo trabajado es el que indicó quien registra
-- (SP_IniciarRegistroIntranet lo dejó en registro_informe_intranet.tiempo_aplicado_seg): esta ayuda reafirma os_equipo.acumulado_seg = ese tiempo y reanudado_utc = NULL para que
-- el generar sume 0. La API la llama justo antes de POST informe. No cambia el estado del equipo (sigue en proceso, que es lo que exige el generar).
-- Exige la sesión ACTIVA PROPIA de ese equipo (si no: "Primero inicia el registro de este equipo.").
-- Resultados: 1 mensaje (1 regla de negocio · 2 éxito · 3 error).
-- ============================================================
DROP PROCEDURE IF EXISTS SP_AjustarTiempoEquipoIntranet;

DELIMITER $$

CREATE PROCEDURE SP_AjustarTiempoEquipoIntranet(
    IN p_id_registrador BIGINT,
    IN p_id_os          BIGINT,
    IN p_id_os_equipo   BIGINT
)
proc: BEGIN
    DECLARE v_reg_id  BIGINT DEFAULT NULL;
    DECLARE v_seg     INT    DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        GET DIAGNOSTICS CONDITION 1 @err_msg = MESSAGE_TEXT, @err_code = MYSQL_ERRNO;
        SELECT 3 AS IdTipoMensaje, CONCAT('[MySQL ', @err_code, '] ', @err_msg) AS Mensaje;
    END;

    IF IFNULL(p_id_registrador, 0) <= 0 OR IFNULL(p_id_os, 0) <= 0 OR IFNULL(p_id_os_equipo, 0) <= 0 THEN
        SELECT 1 AS IdTipoMensaje, 'Servicio o equipo no encontrado.' AS Mensaje; LEAVE proc;
    END IF;
    IF FN_PermisoAccion(p_id_registrador, 'seg_registrar_informe') = 0 THEN
        SELECT 1 AS IdTipoMensaje, 'No tienes permiso para registrar informes desde la intranet.' AS Mensaje; LEAVE proc;
    END IF;

    START TRANSACTION;

    SELECT r.id_registro, r.tiempo_aplicado_seg INTO v_reg_id, v_seg
    FROM   registro_informe_intranet r
    WHERE  r.id_os = p_id_os AND r.id_os_equipo = p_id_os_equipo AND r.id_registrador = p_id_registrador AND r.estado = 'activo'
    ORDER BY r.id_registro DESC LIMIT 1
    FOR UPDATE;
    IF v_reg_id IS NULL THEN
        ROLLBACK;
        SELECT 1 AS IdTipoMensaje, 'Primero inicia el registro de este equipo.' AS Mensaje; LEAVE proc;
    END IF;

    IF v_seg IS NOT NULL THEN
        UPDATE os_equipo
        SET    acumulado_seg = v_seg, reanudado_utc = NULL, modificado_por = p_id_registrador
        WHERE  id = p_id_os_equipo AND id_os = p_id_os AND eliminado_en IS NULL;
    END IF;

    COMMIT;
    SELECT 2 AS IdTipoMensaje, 'Tiempo del equipo ajustado.' AS Mensaje;
END$$

DELIMITER ;
